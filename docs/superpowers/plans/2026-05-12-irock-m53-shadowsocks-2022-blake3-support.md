# M53 Shadowsocks 2022 Blake3 Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real support for `2022-blake3-aes-128-gcm`, `2022-blake3-aes-256-gcm`, and `2022-blake3-chacha20-poly1305` in the shared Shadowsocks codec and macOS unsigned local proxy.

**Architecture:** Keep `IrockProtocols` as the protocol boundary. Add an internal BLAKE3 implementation and a small Shadowsocks cipher descriptor so legacy AEAD and SS2022 share the stream encoder/decoder API but use different key derivation and AEAD algorithms. Keep the macOS POSIX listener as the app runtime socket boundary and make `AppViewModel` accept only implemented methods.

**Tech Stack:** Swift 5, SwiftPM, CryptoKit AES.GCM and ChaChaPoly, internal BLAKE3, XCTest, macOS POSIX sockets for unsigned app local proxy.

---

## File Structure

- Modify: `Package.swift`
  - Add `IrockProtocols` as an explicit dependency of `IrockAppFeature` because AppFeature uses `ShadowsocksStreamRequest.supportsCredential`.
- Create: `packages/IrockProtocols/Sources/IrockProtocols/BLAKE3.swift`
  - Internal BLAKE3 hash/derive-key implementation. No public API.
- Create: `packages/IrockProtocols/Sources/IrockProtocols/ShadowsocksCipher.swift`
  - Internal cipher descriptor for legacy AEAD and SS2022 methods.
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Route `ShadowsocksStreamRequest`, `ShadowsocksAEADStreamEncoder`, and `ShadowsocksAEADStreamDecoder` through `ShadowsocksCipher`.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Add BLAKE3 vectors, SS2022 method support tests, SS2022 stream-open tests, and codec round-trip tests.
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppFeatureModels.swift`
  - Keep `LocalProxyError.unsupportedCredential`.
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`
  - Keep preflight method support check and preserve specific failure messages.
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViews.swift`
  - Keep local proxy state visible near the connect button.
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`
  - Replace temporary 2022 rejection expectation with approved-method acceptance and unknown-method rejection.
- Modify: `apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift`
  - Keep POSIX listener and ensure SS2022 relay uses the shared encoder/decoder.
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`
  - Keep POSIX listener scaffold assertions and add SS2022-aware primitive assertions.

---

### Task 1: Preserve macOS local proxy observability and POSIX listener baseline

**Files:**
- Modify: `apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift`
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViews.swift`
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [ ] **Step 1: Keep the failing-startup feedback regression test**

Ensure `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift` contains:

```swift
@MainActor
func testAppViewModelConnectExposesLocalProxyStartupFailure() throws {
    let controller = ThrowingLocalProxyController()
    let model = AppViewModel(nodes: [], localProxyController: controller)
    try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

    let result = model.connect()

    XCTAssertEqual(result, .localProxyFailed("本地代理启动失败"))
    XCTAssertEqual(model.localProxyState.phase, .failed)
    XCTAssertEqual(model.localProxyState.message, "本地代理启动失败")
    XCTAssertTrue(model.overviewState.recentLogMessages.contains("本地代理启动失败"))
}

private final class ThrowingLocalProxyController: LocalProxyControlling {
    func start(node: ProxyNode, credential: String) throws -> LocalProxyEndpoint {
        throw LocalProxyError.unavailable
    }

    func stop() throws {}
}
```

- [ ] **Step 2: Run the feedback regression**

Run: `swift test --filter AppViewModelsTests/testAppViewModelConnectExposesLocalProxyStartupFailure`

Expected: PASS.

- [ ] **Step 3: Keep POSIX scaffold assertion**

Ensure `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift` asserts:

```swift
XCTAssertTrue(controller.contains("final class MacOSLocalProxyController: LocalProxyControlling"))
XCTAssertTrue(controller.contains("Darwin.socket"))
XCTAssertTrue(controller.contains("Darwin.accept"))
XCTAssertTrue(controller.contains("ShadowsocksStreamRequest"))
XCTAssertTrue(controller.contains("HTTP/1.1 501 Not Implemented"))
```

- [ ] **Step 4: Run the scaffold regression**

Run: `swift test --filter XcodeScaffoldTests/testMacOSAppWiresLocalProxyControllerForUnsignedUsability`

Expected: PASS.

- [ ] **Step 5: Build unsigned app**

Run: `apps/irock-macOS/build-unsigned-app.sh`

Expected: output ends with `** BUILD SUCCEEDED **` and prints `apps/irock-macOS/build/unsigned/irockMacApp.app`.

- [ ] **Step 6: Commit baseline listener work**

```bash
git add Package.swift apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift packages/IrockAppFeature/Sources/IrockAppFeature/AppFeatureModels.swift packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift packages/IrockAppFeature/Sources/IrockAppFeature/AppViews.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift
git commit -m "Fix macOS local proxy startup feedback"
```

---

### Task 2: Add internal BLAKE3 vector tests

**Files:**
- Create: `packages/IrockProtocols/Sources/IrockProtocols/BLAKE3.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Write failing BLAKE3 tests**

Add these tests near the Shadowsocks tests in `IrockProtocolsTests.swift`:

```swift
func testBLAKE3MatchesOfficialVectors() throws {
    let empty = Data()
    XCTAssertEqual(
        InternalBLAKE3.hash(empty, outputByteCount: 32).hexString,
        "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
    )

    let one = Data([0])
    XCTAssertEqual(
        InternalBLAKE3.hash(one, outputByteCount: 32).hexString,
        "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213"
    )

    let thousandTwentyFour = Data((0..<1024).map { UInt8($0 % 251) })
    XCTAssertEqual(
        InternalBLAKE3.hash(thousandTwentyFour, outputByteCount: 32).hexString,
        "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"
    )
}

func testBLAKE3DeriveKeyMatchesOfficialVectors() throws {
    let context = "BLAKE3 2019-12-27 16:29:52 test vectors context"
    XCTAssertEqual(
        InternalBLAKE3.deriveKey(context: context, material: Data(), outputByteCount: 32).hexString,
        "2cc39783c223154fea8dfb7c1b1660f2ac2dcbd1c1de8277b0b0dd39b7e50d7d"
    )

    XCTAssertEqual(
        InternalBLAKE3.deriveKey(context: context, material: Data([0]), outputByteCount: 32).hexString,
        "b3e2e340a117a499c6cf2398a19ee0d29cca2bb7404c73063382693bf66cb06c"
    )

    let thousandTwentyFour = Data((0..<1024).map { UInt8($0 % 251) })
    XCTAssertEqual(
        InternalBLAKE3.deriveKey(context: context, material: thousandTwentyFour, outputByteCount: 32).hexString,
        "7356cd7720d5b66b6d0697eb3177d9f8d73a4a5c5e968896eb6a68968430270"
    )
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IrockProtocolsTests/testBLAKE3`

Expected: FAIL because `InternalBLAKE3` is not defined.

- [ ] **Step 3: Create the internal BLAKE3 API shell**

Create `packages/IrockProtocols/Sources/IrockProtocols/BLAKE3.swift`:

```swift
import Foundation

enum InternalBLAKE3 {
    static func hash(_ input: Data, outputByteCount: Int) -> Data {
        fatalError("InternalBLAKE3.hash is implemented in Task 3")
    }

    static func deriveKey(context: String, material: Data, outputByteCount: Int) -> Data {
        fatalError("InternalBLAKE3.deriveKey is implemented in Task 3")
    }
}
```

- [ ] **Step 4: Run tests to verify shell compiles and fails at runtime**

Run: `swift test --filter IrockProtocolsTests/testBLAKE3MatchesOfficialVectors`

Expected: FAIL due to `fatalError`, proving the tests call the intended API.

- [ ] **Step 5: Commit red BLAKE3 tests and API shell**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/BLAKE3.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Add BLAKE3 vector tests"
```

---

### Task 3: Implement internal BLAKE3 hash and derive-key

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/BLAKE3.swift`
- Test: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Replace BLAKE3 shell with complete implementation**

Implement `InternalBLAKE3` in `BLAKE3.swift` with these exact API boundaries:

```swift
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
            let chunks = Array(input).chunked(into: 1024)
            if chunks.isEmpty {
                return output(chainingValue: compressChunk([], chunkCounter: 0, flags: flagsForMode() | Flags.chunkStart | Flags.chunkEnd), block: [], flags: flagsForMode() | Flags.chunkStart | Flags.chunkEnd | Flags.root, outputByteCount: outputByteCount)
            }

            var chainingValues: [[UInt32]] = []
            for index in chunks.indices {
                let chunk = chunks[index]
                var flags = flagsForMode()
                flags |= Flags.chunkStart
                flags |= Flags.chunkEnd
                let cv = compressChunk(chunk, chunkCounter: UInt64(index), flags: flags)
                chainingValues.append(cv)
            }

            while chainingValues.count > 1 {
                var next: [[UInt32]] = []
                var index = 0
                while index < chainingValues.count {
                    if index + 1 < chainingValues.count {
                        let blockWords = chainingValues[index] + chainingValues[index + 1]
                        next.append(compress(words: blockWords, chainingValue: IV.words, counter: 0, blockLength: 64, flags: flagsForMode() | Flags.parent))
                        index += 2
                    } else {
                        next.append(chainingValues[index])
                        index += 1
                    }
                }
                chainingValues = next
            }

            return output(chainingValue: chainingValues[0], block: [], flags: flagsForMode() | Flags.root, outputByteCount: outputByteCount)
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

        private func compressChunk(_ chunk: [UInt8], chunkCounter: UInt64, flags: UInt32) -> [UInt32] {
            var cv = keyWords()
            let blocks = chunk.chunked(into: 64)
            if blocks.isEmpty {
                return compress(block: [], chainingValue: cv, counter: chunkCounter, blockLength: 0, flags: flags)
            }
            for blockIndex in blocks.indices {
                var blockFlags = flags
                if blockIndex != 0 { blockFlags &= ~Flags.chunkStart }
                if blockIndex != blocks.indices.last { blockFlags &= ~Flags.chunkEnd }
                cv = compress(block: blocks[blockIndex], chainingValue: cv, counter: chunkCounter, blockLength: UInt32(blocks[blockIndex].count), flags: blockFlags)
            }
            return cv
        }

        private func output(chainingValue: [UInt32], block: [UInt8], flags: UInt32, outputByteCount: Int) -> Data {
            var out = Data()
            var counter: UInt64 = 0
            while out.count < outputByteCount {
                let words = compressOutput(block: block, chainingValue: chainingValue, counter: counter, blockLength: UInt32(block.count), flags: flags)
                for word in words {
                    var little = word.littleEndian
                    withUnsafeBytes(of: &little) { out.append(contentsOf: $0) }
                    if out.count >= outputByteCount { break }
                }
                counter += 1
            }
            return out.prefix(outputByteCount)
        }
    }

    private enum Flags {
        static let chunkStart: UInt32 = 1 << 0
        static let chunkEnd: UInt32 = 1 << 1
        static let parent: UInt32 = 1 << 2
        static let root: UInt32 = 1 << 3
        static let keyedHash: UInt32 = 1 << 4
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

    private static func compress(block: [UInt8], chainingValue: [UInt32], counter: UInt64, blockLength: UInt32, flags: UInt32) -> [UInt32] {
        let blockWords = words(fromPaddedBlock: block)
        return Array(compressOutput(blockWords: blockWords, chainingValue: chainingValue, counter: counter, blockLength: blockLength, flags: flags).prefix(8))
    }

    private static func compress(words blockWords: [UInt32], chainingValue: [UInt32], counter: UInt64, blockLength: UInt32, flags: UInt32) -> [UInt32] {
        Array(compressOutput(blockWords: blockWords, chainingValue: chainingValue, counter: counter, blockLength: blockLength, flags: flags).prefix(8))
    }

    private static func compressOutput(block: [UInt8], chainingValue: [UInt32], counter: UInt64, blockLength: UInt32, flags: UInt32) -> [UInt32] {
        compressOutput(blockWords: words(fromPaddedBlock: block), chainingValue: chainingValue, counter: counter, blockLength: blockLength, flags: flags)
    }

    private static func compressOutput(blockWords: [UInt32], chainingValue: [UInt32], counter: UInt64, blockLength: UInt32, flags: UInt32) -> [UInt32] {
        var state = chainingValue + IV.words + [UInt32(truncatingIfNeeded: counter), UInt32(truncatingIfNeeded: counter >> 32), blockLength, flags]
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
        var padded = block
        padded.append(contentsOf: repeatElement(0, count: max(0, 64 - padded.count)))
        return words(from: padded)
    }

    private static func words(from bytes: [UInt8]) -> [UInt32] {
        stride(from: 0, to: bytes.count, by: 4).map { offset in
            UInt32(bytes[offset]) |
            UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 |
            UInt32(bytes[offset + 3]) << 24
        }
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
```

- [ ] **Step 2: Run BLAKE3 vector tests**

Run: `swift test --filter IrockProtocolsTests/testBLAKE3`

Expected: PASS for both hash and derive-key tests. If the 1024-byte vector fails while 0/1 pass, inspect chunk tree logic before continuing.

- [ ] **Step 3: Commit BLAKE3 implementation**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/BLAKE3.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Add internal BLAKE3 implementation"
```

---

### Task 4: Add Shadowsocks cipher descriptor and method support tests

**Files:**
- Create: `packages/IrockProtocols/Sources/IrockProtocols/ShadowsocksCipher.swift`
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Write failing cipher support tests**

Add:

```swift
func testShadowsocksSupportsApproved2022Blake3Methods() {
    XCTAssertTrue(ShadowsocksStreamRequest.supportsCredential("2022-blake3-aes-128-gcm:test-key"))
    XCTAssertTrue(ShadowsocksStreamRequest.supportsCredential("2022-blake3-aes-256-gcm:test-key"))
    XCTAssertTrue(ShadowsocksStreamRequest.supportsCredential("2022-blake3-chacha20-poly1305:test-key"))
    XCTAssertTrue(ShadowsocksStreamRequest.supportsCredential("aes-256-gcm:pass"))
}

func testShadowsocksRejectsUnknown2022Blake3Methods() {
    XCTAssertFalse(ShadowsocksStreamRequest.supportsCredential("2022-blake3-aes-192-gcm:test-key"))
    XCTAssertFalse(ShadowsocksStreamRequest.supportsCredential("2022-blake3-chacha8-poly1305:test-key"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IrockProtocolsTests/testShadowsocksSupportsApproved2022Blake3Methods`

Expected: FAIL because `supportsCredential` only accepts legacy `aes-256-gcm`.

- [ ] **Step 3: Create cipher descriptor**

Create `packages/IrockProtocols/Sources/IrockProtocols/ShadowsocksCipher.swift`:

```swift
import CryptoKit
import Foundation

enum ShadowsocksAEADFamily: Equatable {
    case aes128GCM
    case aes256GCM
    case chacha20Poly1305
}

enum ShadowsocksCipherKind: Equatable {
    case legacyAEAD
    case shadowsocks2022
}

struct ShadowsocksCipher: Equatable {
    let method: String
    let keyLength: Int
    let saltLength: Int
    let family: ShadowsocksAEADFamily
    let kind: ShadowsocksCipherKind

    static func lookup(method: String) -> ShadowsocksCipher? {
        switch method.lowercased() {
        case "aes-256-gcm":
            return ShadowsocksCipher(method: "aes-256-gcm", keyLength: 32, saltLength: 32, family: .aes256GCM, kind: .legacyAEAD)
        case "2022-blake3-aes-128-gcm":
            return ShadowsocksCipher(method: "2022-blake3-aes-128-gcm", keyLength: 16, saltLength: 16, family: .aes128GCM, kind: .shadowsocks2022)
        case "2022-blake3-aes-256-gcm":
            return ShadowsocksCipher(method: "2022-blake3-aes-256-gcm", keyLength: 32, saltLength: 32, family: .aes256GCM, kind: .shadowsocks2022)
        case "2022-blake3-chacha20-poly1305":
            return ShadowsocksCipher(method: "2022-blake3-chacha20-poly1305", keyLength: 32, saltLength: 32, family: .chacha20Poly1305, kind: .shadowsocks2022)
        default:
            return nil
        }
    }

    func deriveSubkey(password: String, salt: Data) throws -> SymmetricKey {
        guard salt.count == saltLength else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks salt")
        }
        switch kind {
        case .legacyAEAD:
            let masterKey = SymmetricKey(data: ShadowsocksStreamRequest.evpBytesToKey(password: Data(password.utf8), keyLength: keyLength))
            return HKDF<Insecure.SHA1>.deriveKey(inputKeyMaterial: masterKey, salt: salt, info: Data("ss-subkey".utf8), outputByteCount: keyLength)
        case .shadowsocks2022:
            let psk = Data(password.utf8)
            let material = psk + salt
            let key = InternalBLAKE3.deriveKey(context: "shadowsocks 2022 session subkey", material: material, outputByteCount: keyLength)
            return SymmetricKey(data: key)
        }
    }

    func seal(_ data: Data, using key: SymmetricKey, nonceValue: UInt64) throws -> Data {
        switch family {
        case .aes128GCM, .aes256GCM:
            let sealed = try AES.GCM.seal(data, using: key, nonce: AES.GCM.Nonce(data: nonceBytes(nonceValue)))
            return sealed.ciphertext + sealed.tag
        case .chacha20Poly1305:
            let sealed = try ChaChaPoly.seal(data, using: key, nonce: ChaChaPoly.Nonce(data: nonceBytes(nonceValue)))
            return sealed.ciphertext + sealed.tag
        }
    }

    func open(_ data: Data, using key: SymmetricKey, nonceValue: UInt64) throws -> Data {
        guard data.count >= 16 else {
            throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks encrypted frame")
        }
        let ciphertext = data.prefix(data.count - 16)
        let tag = data.suffix(16)
        switch family {
        case .aes128GCM, .aes256GCM:
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceBytes(nonceValue)), ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: key)
        case .chacha20Poly1305:
            let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonceBytes(nonceValue)), ciphertext: ciphertext, tag: tag)
            return try ChaChaPoly.open(box, using: key)
        }
    }

    private func nonceBytes(_ value: UInt64) -> Data {
        var bytes = Data(repeating: 0, count: 12)
        var current = value
        for index in 0..<8 {
            bytes[index] = UInt8(current & 0xff)
            current >>= 8
        }
        return bytes
    }
}
```

- [ ] **Step 4: Update `supportsCredential`**

In `IrockProtocols.swift`, change:

```swift
public static func supportsCredential(_ credential: String) -> Bool {
    guard let parsed = try? parseCredential(credential) else { return false }
    return parsed.method == "aes-256-gcm"
}
```

to:

```swift
public static func supportsCredential(_ credential: String) -> Bool {
    guard let parsed = try? parseCredential(credential) else { return false }
    return ShadowsocksCipher.lookup(method: parsed.method) != nil
}
```

- [ ] **Step 5: Run support tests**

Run: `swift test --filter IrockProtocolsTests/testShadowsocksSupportsApproved2022Blake3Methods`

Expected: PASS.

Run: `swift test --filter IrockProtocolsTests/testShadowsocksRejectsUnknown2022Blake3Methods`

Expected: PASS.

- [ ] **Step 6: Commit cipher registry**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/ShadowsocksCipher.swift packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Add Shadowsocks cipher registry"
```

---

### Task 5: Route legacy AEAD stream codec through cipher descriptor

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Test: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Keep legacy regression tests**

Do not modify these expected values:

```swift
XCTAssertEqual(request.openBytesHex, "0101010101010101010101010101010101010101010101010101010101010101620abbadfec9a6d19bc1964dc25cdc714a40d7df10cbff62357470f76caa6c7eb90f8d9a21aab8e2bff8ab3c1b4997")
XCTAssertEqual(request.openBytes.count, 79)
```

- [ ] **Step 2: Run legacy test before refactor**

Run: `swift test --filter IrockProtocolsTests/testShadowsocksStreamRequestBuildsAES256GCMHostOpenBytes`

Expected: PASS.

- [ ] **Step 3: Replace encoder/decoder initialization with descriptor path**

In `ShadowsocksAEADStreamEncoder`, replace stored properties with:

```swift
private var nonceValue: UInt64
private let subkey: SymmetricKey
private let cipher: ShadowsocksCipher
```

Replace init body with:

```swift
public init(credential: String, salt: Data, initialNonce: UInt64 = 0) throws {
    let parsed = try ShadowsocksStreamRequest.parseCredential(credential)
    guard let cipher = ShadowsocksCipher.lookup(method: parsed.method) else {
        throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks method")
    }
    self.cipher = cipher
    self.subkey = try cipher.deriveSubkey(password: parsed.password, salt: salt)
    self.nonceValue = initialNonce
}
```

Replace encrypt calls:

```swift
let encryptedLength = try cipher.seal(length, using: subkey, nonceValue: nonceValue)
let encryptedPayload = try cipher.seal(payload, using: subkey, nonceValue: nonceValue)
```

- [ ] **Step 4: Update decoder similarly**

In `ShadowsocksAEADStreamDecoder`, add:

```swift
private let cipher: ShadowsocksCipher
```

Use the same lookup and `deriveSubkey` init pattern as encoder. Replace open calls with:

```swift
let lengthData = try cipher.open(Data(encryptedLength), using: subkey, nonceValue: nonceValue)
let payload = try cipher.open(Data(encryptedPayload), using: subkey, nonceValue: nonceValue)
```

- [ ] **Step 5: Update `ShadowsocksStreamRequest` legacy path through descriptor**

In `init(credential:destination:salt:)`, replace method guard/key derivation/seal with:

```swift
let parsed = try Self.parseCredential(credential)
guard let cipher = ShadowsocksCipher.lookup(method: parsed.method) else {
    throw ProxyProtocolError.invalidConfiguration("unsupported shadowsocks method")
}
guard cipher.kind == .legacyAEAD else {
    throw ProxyProtocolError.invalidConfiguration("shadowsocks 2022 stream header not implemented")
}

self.cipher = cipher.method
self.addressFrame = try Self.addressFrame(for: destination)
let subkey = try cipher.deriveSubkey(password: parsed.password, salt: salt)
let length = Data([UInt8(addressFrame.count >> 8), UInt8(addressFrame.count & 0xff)])
let encryptedLength = try cipher.seal(length, using: subkey, nonceValue: 0)
let encryptedPayload = try cipher.seal(addressFrame, using: subkey, nonceValue: 1)
self.openBytes = salt + encryptedLength + encryptedPayload
```

- [ ] **Step 6: Run legacy codec tests**

Run: `swift test --filter IrockProtocolsTests/Shadowsocks`

Expected: all existing legacy Shadowsocks tests pass except the old `testShadowsocks2022ExampleMethodIsUnsupportedUntilBlake3IsAvailable`, which will be replaced in Task 6.

- [ ] **Step 7: Commit descriptor refactor**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Sources/IrockProtocols/ShadowsocksCipher.swift
git commit -m "Route Shadowsocks codec through cipher descriptors"
```

---

### Task 6: Implement SS2022 stream-open format

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Replace old rejection test with SS2022 open tests**

Replace `testShadowsocks2022ExampleMethodIsUnsupportedUntilBlake3IsAvailable` with:

```swift
func testShadowsocks2022AES128BuildsClientStreamHeader() throws {
    let request = try ShadowsocksStreamRequest(
        credential: "2022-blake3-aes-128-gcm:0123456789abcdef",
        destination: .host("example.com", port: 80),
        salt: Data(repeating: 1, count: 16),
        timestamp: Date(timeIntervalSince1970: 1_715_000_000),
        padding: Data([0xaa])
    )

    XCTAssertEqual(request.cipher, "2022-blake3-aes-128-gcm")
    XCTAssertEqual(request.addressFrameHex, "030b6578616d706c652e636f6d0050")
    XCTAssertEqual(request.openBytes.count, 16 + 11 + 16 + 18 + 16)
}

func testShadowsocks2022AES256BuildsClientStreamHeader() throws {
    let request = try ShadowsocksStreamRequest(
        credential: "2022-blake3-aes-256-gcm:0123456789abcdef0123456789abcdef",
        destination: .ipv4("93.184.216.34", port: 443),
        salt: Data(repeating: 2, count: 32),
        timestamp: Date(timeIntervalSince1970: 1_715_000_000),
        padding: Data([0xbb])
    )

    XCTAssertEqual(request.cipher, "2022-blake3-aes-256-gcm")
    XCTAssertEqual(request.addressFrameHex, "015db8d82201bb")
    XCTAssertEqual(request.openBytes.count, 32 + 11 + 16 + 12 + 16)
}

func testShadowsocks2022ChaCha20Poly1305BuildsClientStreamHeader() throws {
    let request = try ShadowsocksStreamRequest(
        credential: "2022-blake3-chacha20-poly1305:0123456789abcdef0123456789abcdef",
        destination: .host("example.com", port: 443),
        salt: Data(repeating: 3, count: 32),
        timestamp: Date(timeIntervalSince1970: 1_715_000_000),
        padding: Data([0xcc])
    )

    XCTAssertEqual(request.cipher, "2022-blake3-chacha20-poly1305")
    XCTAssertEqual(request.addressFrameHex, "030b6578616d706c652e636f6d01bb")
    XCTAssertEqual(request.openBytes.count, 32 + 11 + 16 + 18 + 16)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IrockProtocolsTests/testShadowsocks2022`

Expected: FAIL because `ShadowsocksStreamRequest` lacks `timestamp` and `padding` initializer parameters and SS2022 header implementation.

- [ ] **Step 3: Add SS2022 initializer parameters with defaults**

Change `ShadowsocksStreamRequest` init signature to:

```swift
public init(
    credential: String,
    destination: ProxyDestination,
    salt: Data,
    timestamp: Date = Date(),
    padding: Data? = nil
) throws
```

- [ ] **Step 4: Implement SS2022 open branch**

Inside init, after cipher lookup and address frame setup, branch:

```swift
self.cipher = cipher.method
self.addressFrame = try Self.addressFrame(for: destination)
let subkey = try cipher.deriveSubkey(password: parsed.password, salt: salt)

switch cipher.kind {
case .legacyAEAD:
    let length = Data([UInt8(addressFrame.count >> 8), UInt8(addressFrame.count & 0xff)])
    let encryptedLength = try cipher.seal(length, using: subkey, nonceValue: 0)
    let encryptedPayload = try cipher.seal(addressFrame, using: subkey, nonceValue: 1)
    self.openBytes = salt + encryptedLength + encryptedPayload
case .shadowsocks2022:
    self.openBytes = try Self.shadowsocks2022OpenBytes(
        addressFrame: addressFrame,
        salt: salt,
        subkey: subkey,
        cipher: cipher,
        timestamp: timestamp,
        padding: padding ?? Data([0])
    )
}
```

Add helper:

```swift
private static func shadowsocks2022OpenBytes(
    addressFrame: Data,
    salt: Data,
    subkey: SymmetricKey,
    cipher: ShadowsocksCipher,
    timestamp: Date,
    padding: Data
) throws -> Data {
    guard !padding.isEmpty, padding.count <= 900 else {
        throw ProxyProtocolError.invalidConfiguration("invalid shadowsocks 2022 padding")
    }
    let timestampValue = UInt64(timestamp.timeIntervalSince1970)
    var fixedHeader = Data([0])
    fixedHeader.append(UInt8((timestampValue >> 56) & 0xff))
    fixedHeader.append(UInt8((timestampValue >> 48) & 0xff))
    fixedHeader.append(UInt8((timestampValue >> 40) & 0xff))
    fixedHeader.append(UInt8((timestampValue >> 32) & 0xff))
    fixedHeader.append(UInt8((timestampValue >> 24) & 0xff))
    fixedHeader.append(UInt8((timestampValue >> 16) & 0xff))
    fixedHeader.append(UInt8((timestampValue >> 8) & 0xff))
    fixedHeader.append(UInt8(timestampValue & 0xff))

    var variableHeader = Data()
    variableHeader.append(addressFrame)
    variableHeader.append(UInt8((padding.count >> 8) & 0xff))
    variableHeader.append(UInt8(padding.count & 0xff))
    variableHeader.append(padding)

    fixedHeader.append(UInt8((variableHeader.count >> 8) & 0xff))
    fixedHeader.append(UInt8(variableHeader.count & 0xff))

    let encryptedFixed = try cipher.seal(fixedHeader, using: subkey, nonceValue: 0)
    let encryptedVariable = try cipher.seal(variableHeader, using: subkey, nonceValue: 1)
    return salt + encryptedFixed + encryptedVariable
}
```

- [ ] **Step 5: Run SS2022 open tests**

Run: `swift test --filter IrockProtocolsTests/testShadowsocks2022`

Expected: PASS.

- [ ] **Step 6: Run legacy open test**

Run: `swift test --filter IrockProtocolsTests/testShadowsocksStreamRequestBuildsAES256GCMHostOpenBytes`

Expected: PASS with the old exact hex unchanged.

- [ ] **Step 7: Commit SS2022 open support**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Add Shadowsocks 2022 stream header support"
```

---

### Task 7: Add SS2022 streaming encoder and decoder round trips

**Files:**
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`

- [ ] **Step 1: Write round-trip tests for each approved method**

Add:

```swift
func testShadowsocks2022StreamCodecRoundTripsApprovedMethods() throws {
    let credentials = [
        "2022-blake3-aes-128-gcm:0123456789abcdef",
        "2022-blake3-aes-256-gcm:0123456789abcdef0123456789abcdef",
        "2022-blake3-chacha20-poly1305:0123456789abcdef0123456789abcdef"
    ]

    for credential in credentials {
        let saltLength = credential.contains("aes-128") ? 16 : 32
        let salt = Data(repeating: UInt8(saltLength), count: saltLength)
        var encoder = try ShadowsocksAEADStreamEncoder(credential: credential, salt: salt, initialNonce: 2)
        var decoder = try ShadowsocksAEADStreamDecoder(credential: credential, salt: salt, initialNonce: 2)

        let frame = try encoder.encrypt(Data("hello ss2022".utf8))

        XCTAssertEqual(try decoder.decrypt(frame), Data("hello ss2022".utf8), credential)
    }
}
```

- [ ] **Step 2: Run round-trip test**

Run: `swift test --filter IrockProtocolsTests/testShadowsocks2022StreamCodecRoundTripsApprovedMethods`

Expected: PASS if Task 5 descriptor routing is correct. If it fails for ChaCha only, inspect `ShadowsocksCipher` ChaChaPoly sealed-box construction.

- [ ] **Step 3: Add fragmented decode test for SS2022 AES-128**

Add:

```swift
func testShadowsocks2022DecoderBuffersFragmentedFrames() throws {
    let credential = "2022-blake3-aes-128-gcm:0123456789abcdef"
    let salt = Data(repeating: 9, count: 16)
    var encoder = try ShadowsocksAEADStreamEncoder(credential: credential, salt: salt, initialNonce: 2)
    var decoder = try ShadowsocksAEADStreamDecoder(credential: credential, salt: salt, initialNonce: 2)
    let ciphertext = try encoder.encrypt(Data("fragmented ss2022 payload".utf8))
    let splitIndex = ciphertext.index(ciphertext.startIndex, offsetBy: 7)

    XCTAssertNil(try decoder.appendAndDecrypt(ciphertext[..<splitIndex]))
    XCTAssertEqual(try decoder.appendAndDecrypt(ciphertext[splitIndex...]), Data("fragmented ss2022 payload".utf8))
}
```

- [ ] **Step 4: Run fragmented decode test**

Run: `swift test --filter IrockProtocolsTests/testShadowsocks2022DecoderBuffersFragmentedFrames`

Expected: PASS.

- [ ] **Step 5: Commit SS2022 streaming codec tests**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Add Shadowsocks 2022 stream codec round trips"
```

---

### Task 8: Update AppFeature method gating for approved SS2022 methods

**Files:**
- Modify: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift`
- Modify: `packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift`
- Modify: `Package.swift`

- [ ] **Step 1: Replace temporary unsupported-method test**

Replace `testAppViewModelConnectRejectsUnsupportedShadowsocksMethodBeforeStartingProxy` with:

```swift
@MainActor
func testAppViewModelConnectAllowsApprovedShadowsocks2022Methods() throws {
    let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
    let controller = RecordingLocalProxyController(endpoint: endpoint)
    let model = AppViewModel(nodes: [], localProxyController: controller)
    try model.importShadowsocksURI("ss://MjAyMi1ibGFrZTMtYWVzLTEyOC1nY206MDEyMzQ1Njc4OWFiY2RlZkBleGFtcGxlLmludmFsaWQ6NDI4MTc#Shadowsocks-2022-example")

    let result = model.connect()

    XCTAssertEqual(result, .localProxyStarted(endpoint))
    XCTAssertEqual(controller.startedNode?.name, "Shadowsocks-2022-example")
    XCTAssertEqual(controller.startedCredential, "2022-blake3-aes-128-gcm:0123456789abcdef")
    XCTAssertEqual(model.localProxyState.phase, .running)
}

@MainActor
func testAppViewModelConnectRejectsUnknownShadowsocks2022MethodBeforeStartingProxy() throws {
    let controller = RecordingLocalProxyController(endpoint: LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809))
    let model = AppViewModel(nodes: [], localProxyController: controller)
    try model.importShadowsocksURI("ss://MjAyMi1ibGFrZTMtYWVzLTE5Mi1nY206MDEyMzQ1Njc4OWFiY2RlZkBleGFtcGxlLmludmFsaWQ6NDI4MTc#Unknown-2022-example")

    let result = model.connect()

    XCTAssertEqual(result, .localProxyFailed("当前 Shadowsocks 加密方法暂不支持本地代理"))
    XCTAssertNil(controller.startedNode)
    XCTAssertEqual(model.localProxyState.phase, .failed)
}
```

- [ ] **Step 2: Run app feature tests to verify current behavior**

Run: `swift test --filter AppViewModelsTests/testAppViewModelConnectAllowsApprovedShadowsocks2022Methods`

Expected: PASS after protocol support exists.

Run: `swift test --filter AppViewModelsTests/testAppViewModelConnectRejectsUnknownShadowsocks2022MethodBeforeStartingProxy`

Expected: PASS.

- [ ] **Step 3: Ensure Package dependency is explicit**

In `Package.swift`, keep:

```swift
.target(
    name: "IrockAppFeature",
    dependencies: ["IrockCore", "IrockRouting", "IrockStorage", "IrockDiagnostics", "IrockProtocols"],
    path: "packages/IrockAppFeature/Sources/IrockAppFeature"
),
```

- [ ] **Step 4: Run AppFeature test target**

Run: `swift test --filter IrockAppFeatureTests`

Expected: PASS.

- [ ] **Step 5: Commit AppFeature gating update**

```bash
git add Package.swift packages/IrockAppFeature/Sources/IrockAppFeature/AppViewModels.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/AppViewModelsTests.swift
git commit -m "Allow approved Shadowsocks 2022 methods in app feature"
```

---

### Task 9: Verify macOS local proxy uses SS2022 codec path

**Files:**
- Modify: `apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift`
- Modify: `packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift`

- [ ] **Step 1: Confirm relay uses shared encoder/decoder only**

In `MacOSLocalProxyController.swift`, keep local relay code using:

```swift
let request = try ShadowsocksStreamRequest(credential: credential, destination: destination, salt: salt)
var encoder = try ShadowsocksAEADStreamEncoder(credential: credential, salt: clientSalt, initialNonce: 2)
var decoder = try ShadowsocksAEADStreamDecoder(credential: credential, salt: salt)
```

Do not add method-specific branching in the macOS file.

- [ ] **Step 2: Add scaffold assertions**

In `testMacOSAppWiresLocalProxyControllerForUnsignedUsability`, add:

```swift
XCTAssertTrue(controller.contains("ShadowsocksAEADStreamEncoder"))
XCTAssertTrue(controller.contains("ShadowsocksAEADStreamDecoder"))
XCTAssertFalse(controller.contains("2022-blake3-aes-128-gcm"))
```

- [ ] **Step 3: Run scaffold test**

Run: `swift test --filter XcodeScaffoldTests/testMacOSAppWiresLocalProxyControllerForUnsignedUsability`

Expected: PASS.

- [ ] **Step 4: Build unsigned app**

Run: `apps/irock-macOS/build-unsigned-app.sh`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual smoke with approved SS2022 node**

Use a credential-safe real node provided out-of-band. Do not paste the raw URI into logs or docs. In the app:

1. Import the `ss://` node.
2. Click `连接（本地代理）`.
3. Run `lsof -nP -iTCP:10808 -sTCP:LISTEN`.
4. Run `curl ip-api.com -x socks5h://127.0.0.1:10808 -v`.

Expected: local port listens; curl completes or fails with a remote-node/network-specific error, not local `Connection refused` and not SOCKS method unsupported.

- [ ] **Step 6: Commit macOS SS2022 relay verification**

```bash
git add apps/irock-macOS/irockMacApp/MacOSLocalProxyController.swift packages/IrockTooling/Tests/IrockToolingTests/XcodeScaffoldTests.swift
git commit -m "Verify macOS local proxy uses shared SS2022 codec"
```

---

### Task 10: Full verification and docs

**Files:**
- Modify: `docs/superpowers/specs/2026-05-12-irock-m53-shadowsocks-2022-blake3-support-design.md`
- Test all modified code

- [ ] **Step 1: Run full SwiftPM tests**

Run: `swift test`

Expected: all tests pass. Current expected count before this plan is 334; count may increase after added tests.

- [ ] **Step 2: Build unsigned macOS app**

Run: `apps/irock-macOS/build-unsigned-app.sh`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Scan for real secrets**

Run:

```bash
git diff -- docs packages apps Package.swift | grep -E 'ss://|BEGIN (RSA|OPENSSH|PRIVATE)|Team ID|password=' || true
```

Expected: no output containing real credentials. Synthetic test strings such as `credential-redacted`, `example.invalid`, and deterministic non-secret test keys are acceptable.

- [ ] **Step 4: Review current diff**

Run: `git diff --stat`.

Expected: changes limited to Package.swift, IrockProtocols, IrockAppFeature, macOS local proxy, tooling tests, and M53 docs/plans.

- [ ] **Step 5: Commit final verification docs if changed**

```bash
git add docs/superpowers/specs/2026-05-12-irock-m53-shadowsocks-2022-blake3-support-design.md docs/superpowers/plans/2026-05-12-irock-m53-shadowsocks-2022-blake3-support.md
git commit -m "Document Shadowsocks 2022 Blake3 support plan"
```

---

## Self-Review

- Spec coverage:
  - Internal BLAKE3: Tasks 2-3.
  - Approved methods only: Task 4.
  - SS2022 stream-open: Task 6.
  - Streaming chunk round trips: Task 7.
  - AppFeature gating: Task 8.
  - macOS local proxy: Task 9.
  - Full verification and no secrets: Task 10.
- Placeholder scan: no `TBD`, `TODO`, `implement later`, or open-ended edge-case instructions remain.
- Type consistency: `InternalBLAKE3`, `ShadowsocksCipher`, `ShadowsocksAEADStreamEncoder`, `ShadowsocksAEADStreamDecoder`, and `ShadowsocksStreamRequest.supportsCredential` are used consistently across tasks.
