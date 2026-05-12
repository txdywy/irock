import Foundation

enum InternalBLAKE3 {
    static func hash(_ input: Data, outputByteCount: Int) -> Data {
        Hasher(mode: .hash).finalize(input: input, outputByteCount: outputByteCount)
    }

    static func deriveKey(context: String, material: Data, outputByteCount: Int) -> Data {
        let contextKey = Hasher(mode: .deriveKeyContext).finalize(input: Data(context.utf8), outputByteCount: 32)
        return Hasher(mode: .deriveKeyMaterial(contextKey)).finalize(input: material, outputByteCount: outputByteCount)
    }

    private enum Mode {
        case hash
        case deriveKeyContext
        case deriveKeyMaterial(Data)
    }

    private struct Hasher {
        let mode: Mode

        func finalize(input: Data, outputByteCount: Int) -> Data {
            precondition(outputByteCount >= 0)

            let bytes = Array(input)
            let chunks = bytes.chunked(into: Constants.chunkLength)
            if chunks.isEmpty {
                return chunkOutput(bytes: [], chunkCounter: 0).rootOutputBytes(outputByteCount: outputByteCount)
            }

            var chainingValueStack: [[UInt32]] = []
            for chunkIndex in chunks.indices.dropLast() {
                let chunkChainingValue = chunkOutput(bytes: chunks[chunkIndex], chunkCounter: UInt64(chunkIndex)).chainingValue()
                addChunkChainingValue(chunkChainingValue, totalChunks: UInt64(chunkIndex + 1), to: &chainingValueStack)
            }

            let lastChunkIndex = chunks.index(before: chunks.endIndex)
            var rootOutput = chunkOutput(bytes: chunks[lastChunkIndex], chunkCounter: UInt64(lastChunkIndex))
            while let leftChainingValue = chainingValueStack.popLast() {
                rootOutput = parentOutput(left: leftChainingValue, right: rootOutput.chainingValue())
            }
            return rootOutput.rootOutputBytes(outputByteCount: outputByteCount)
        }

        private func addChunkChainingValue(_ newChainingValue: [UInt32], totalChunks: UInt64, to stack: inout [[UInt32]]) {
            var chainingValue = newChainingValue
            var chunksRemaining = totalChunks
            while chunksRemaining & 1 == 0 {
                chainingValue = parentOutput(left: stack.removeLast(), right: chainingValue).chainingValue()
                chunksRemaining >>= 1
            }
            stack.append(chainingValue)
        }

        private func chunkOutput(bytes: [UInt8], chunkCounter: UInt64) -> Output {
            var chainingValue = keyWords()
            let blocks = bytes.chunked(into: Constants.blockLength)
            if blocks.isEmpty {
                return Output(
                    inputChainingValue: chainingValue,
                    blockWords: words(fromPaddedBlock: []),
                    counter: chunkCounter,
                    blockLength: 0,
                    flags: flagsForMode() | Flags.chunkStart | Flags.chunkEnd
                )
            }

            for blockIndex in blocks.indices.dropLast() {
                var blockFlags = flagsForMode()
                if blockIndex == blocks.startIndex { blockFlags |= Flags.chunkStart }
                chainingValue = compress(
                    blockWords: words(fromPaddedBlock: blocks[blockIndex]),
                    chainingValue: chainingValue,
                    counter: chunkCounter,
                    blockLength: UInt32(blocks[blockIndex].count),
                    flags: blockFlags
                )
            }

            let lastIndex = blocks.index(before: blocks.endIndex)
            var lastBlockFlags = flagsForMode() | Flags.chunkEnd
            if lastIndex == blocks.startIndex { lastBlockFlags |= Flags.chunkStart }
            return Output(
                inputChainingValue: chainingValue,
                blockWords: words(fromPaddedBlock: blocks[lastIndex]),
                counter: chunkCounter,
                blockLength: UInt32(blocks[lastIndex].count),
                flags: lastBlockFlags
            )
        }

        private func parentOutput(left: [UInt32], right: [UInt32]) -> Output {
            Output(
                inputChainingValue: keyWords(),
                blockWords: left + right,
                counter: 0,
                blockLength: UInt32(Constants.blockLength),
                flags: flagsForMode() | Flags.parent
            )
        }

        private func flagsForMode() -> UInt32 {
            switch mode {
            case .hash:
                return 0
            case .deriveKeyContext:
                return Flags.deriveKeyContext
            case .deriveKeyMaterial:
                return Flags.deriveKeyMaterial
            }
        }

        private func keyWords() -> [UInt32] {
            switch mode {
            case .hash, .deriveKeyContext:
                return IV.words
            case let .deriveKeyMaterial(key):
                return words(from: Array(key))
            }
        }
    }

    private struct Output {
        let inputChainingValue: [UInt32]
        let blockWords: [UInt32]
        let counter: UInt64
        let blockLength: UInt32
        let flags: UInt32

        func chainingValue() -> [UInt32] {
            Array(compressOutput(
                blockWords: blockWords,
                chainingValue: inputChainingValue,
                counter: counter,
                blockLength: blockLength,
                flags: flags
            ).prefix(8))
        }

        func rootOutputBytes(outputByteCount: Int) -> Data {
            var output = Data()
            var outputBlockCounter: UInt64 = 0
            while output.count < outputByteCount {
                let words = compressOutput(
                    blockWords: blockWords,
                    chainingValue: inputChainingValue,
                    counter: outputBlockCounter,
                    blockLength: blockLength,
                    flags: flags | Flags.root
                )
                for word in words {
                    var littleEndianWord = word.littleEndian
                    withUnsafeBytes(of: &littleEndianWord) { bytes in
                        for byte in bytes {
                            if output.count < outputByteCount {
                                output.append(byte)
                            }
                        }
                    }
                    if output.count >= outputByteCount { break }
                }
                outputBlockCounter += 1
            }
            return Data(output.prefix(outputByteCount))
        }
    }

    private enum Constants {
        static let chunkLength = 1024
        static let blockLength = 64
    }

    private enum Flags {
        static let chunkStart: UInt32 = 1 << 0
        static let chunkEnd: UInt32 = 1 << 1
        static let parent: UInt32 = 1 << 2
        static let root: UInt32 = 1 << 3
        static let deriveKeyContext: UInt32 = 1 << 5
        static let deriveKeyMaterial: UInt32 = 1 << 6
    }

    private enum IV {
        static let words: [UInt32] = [
            0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
            0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
        ]
    }

    private static let messagePermutation = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]

    private static func compress(blockWords: [UInt32], chainingValue: [UInt32], counter: UInt64, blockLength: UInt32, flags: UInt32) -> [UInt32] {
        Array(compressOutput(
            blockWords: blockWords,
            chainingValue: chainingValue,
            counter: counter,
            blockLength: blockLength,
            flags: flags
        ).prefix(8))
    }

    private static func compressOutput(blockWords: [UInt32], chainingValue: [UInt32], counter: UInt64, blockLength: UInt32, flags: UInt32) -> [UInt32] {
        var state = chainingValue + Array(IV.words.prefix(4)) + [UInt32(truncatingIfNeeded: counter), UInt32(truncatingIfNeeded: counter >> 32), blockLength, flags]
        var message = blockWords
        for round in 0..<7 {
            roundFunction(state: &state, message: message)
            if round != 6 { message = permute(message) }
        }
        for index in 0..<8 { state[index] ^= state[index + 8] }
        for index in 0..<8 { state[index + 8] ^= chainingValue[index] }
        return state
    }

    private static func roundFunction(state: inout [UInt32], message: [UInt32]) {
        g(&state, 0, 4, 8, 12, message[0], message[1])
        g(&state, 1, 5, 9, 13, message[2], message[3])
        g(&state, 2, 6, 10, 14, message[4], message[5])
        g(&state, 3, 7, 11, 15, message[6], message[7])
        g(&state, 0, 5, 10, 15, message[8], message[9])
        g(&state, 1, 6, 11, 12, message[10], message[11])
        g(&state, 2, 7, 8, 13, message[12], message[13])
        g(&state, 3, 4, 9, 14, message[14], message[15])
    }

    private static func g(_ state: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
        state[a] = state[a] &+ state[b] &+ x
        state[d] = (state[d] ^ state[a]).rotatedRight(16)
        state[c] = state[c] &+ state[d]
        state[b] = (state[b] ^ state[c]).rotatedRight(12)
        state[a] = state[a] &+ state[b] &+ y
        state[d] = (state[d] ^ state[a]).rotatedRight(8)
        state[c] = state[c] &+ state[d]
        state[b] = (state[b] ^ state[c]).rotatedRight(7)
    }

    private static func permute(_ words: [UInt32]) -> [UInt32] {
        messagePermutation.map { words[$0] }
    }

    private static func words(fromPaddedBlock block: [UInt8]) -> [UInt32] {
        let wordCount = 16
        var words = [UInt32](repeating: 0, count: wordCount)
        var byteIndex = 0
        while byteIndex < block.count {
            let wordIndex = byteIndex / 4
            let shift = UInt32((byteIndex % 4) * 8)
            let shiftedByte = UInt32(block[byteIndex]) << shift
            words[wordIndex] |= shiftedByte
            byteIndex += 1
        }
        return words
    }

    private static func words(from bytes: [UInt8]) -> [UInt32] {
        var result: [UInt32] = []
        var offset = 0
        while offset < bytes.count {
            let byte0 = UInt32(bytes[offset])
            let byte1 = UInt32(bytes[offset + 1]) << 8
            let byte2 = UInt32(bytes[offset + 2]) << 16
            let byte3 = UInt32(bytes[offset + 3]) << 24
            result.append(byte0 | byte1 | byte2 | byte3)
            offset += 4
        }
        return result
    }
}

private extension UInt32 {
    func rotatedRight(_ amount: UInt32) -> UInt32 {
        (self >> amount) | (self << (32 - amount))
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
