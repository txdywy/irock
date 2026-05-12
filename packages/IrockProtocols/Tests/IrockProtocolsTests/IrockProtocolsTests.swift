import Foundation
import XCTest
import IrockCore
import IrockTransport
@testable import IrockProtocols

final class IrockProtocolsTests: XCTestCase {
    func testProxyDestinationEquatableCases() {
        XCTAssertEqual(ProxyDestination.host("apple.com", port: 443), .host("apple.com", port: 443))
        XCTAssertEqual(ProxyDestination.ipv4("93.184.216.34", port: 443), .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(ProxyDestination.ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443), .ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443))
        XCTAssertNotEqual(ProxyDestination.host("apple.com", port: 443), .host("apple.com", port: 80))
    }

    func testProtocolAddressEncoderBuildsDomainIPv4AndIPv6Frames() throws {
        XCTAssertEqual(
            try ProtocolAddressFrame(destination: .host("apple.com", port: 443), domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04).bytes,
            Data([0x03, 0x09]) + Data("apple.com".utf8) + Data([0x01, 0xbb])
        )
        XCTAssertEqual(
            try ProtocolAddressFrame(destination: .ipv4("93.184.216.34", port: 443), domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04).bytes,
            Data([0x01, 93, 184, 216, 34, 0x01, 0xbb])
        )
        XCTAssertEqual(
            try ProtocolAddressFrame(destination: .ipv6("2606:2800:220:1:248:1893:25c8:1946", port: 443), domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04).bytes,
            Data([0x04, 0x26, 0x06, 0x28, 0x00, 0x02, 0x20, 0x00, 0x01, 0x02, 0x48, 0x18, 0x93, 0x25, 0xc8, 0x19, 0x46, 0x01, 0xbb])
        )
        XCTAssertEqual(
            try ProtocolAddressFrame(destination: .ipv6("::1", port: 443), domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04).bytes,
            Data([0x04]) + Data(repeating: 0, count: 15) + Data([0x01, 0x01, 0xbb])
        )
    }

    func testProtocolAddressEncoderRejectsInvalidInputs() {
        let cases: [ProxyDestination] = [
            .host("", port: 443),
            .host(String(repeating: "a", count: 256), port: 443),
            .host("apple.com", port: 0),
            .ipv4("999.184.216.34", port: 443),
            .ipv6("not-ipv6", port: 443)
        ]

        for destination in cases {
            XCTAssertThrowsError(try ProtocolAddressFrame(destination: destination, domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04))
        }
    }

    func testSHA224MatchesKnownVectors() {
        let vectors = [
            ("", "d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f"),
            ("abc", "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"),
            ("secret-password", "869ce74cceadfb55774ed4ff96cdb65be71412e3d669878bec160955"),
            (String(repeating: "a", count: 64), "a88cd5cde6d6fe9136a4e58b49167461ea95d388ca2bdb7afdc3cbf4")
        ]

        for (input, expected) in vectors {
            XCTAssertEqual(SHA224.hashHex(input), expected)
        }
    }

    func testProxyRequestStoresNodeDestinationAndMetadata() {
        let node = makeNode(protocolType: .trojan, transport: .tcp)
        let request = ProxyRequest(
            node: node,
            destination: .host("apple.com", port: 443),
            metadata: ["source": "unit-test"]
        )

        XCTAssertEqual(request.node.protocolType, .trojan)
        XCTAssertEqual(request.destination, .host("apple.com", port: 443))
        XCTAssertEqual(request.metadata, ["source": "unit-test"])
    }

    func testProxyRequestDefaultsMetadataToEmpty() {
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp), destination: .ipv4("1.1.1.1", port: 53))

        XCTAssertEqual(request.metadata, [:])
    }

    func testShadowsocksStreamRequestBuildsAES256GCMHostOpenBytes() throws {
        let request = try ShadowsocksStreamRequest(
            credential: "aes-256-gcm:pass",
            destination: .host("apple.com", port: 443),
            salt: Data(repeating: 1, count: 32)
        )

        XCTAssertEqual(request.cipher, "aes-256-gcm")
        XCTAssertEqual(request.addressFrameHex, "03096170706c652e636f6d01bb")
        XCTAssertEqual(request.openBytesHex, "0101010101010101010101010101010101010101010101010101010101010101620abbadfec9a6d19bc1964dc25cdc714a40d7df10cbff62357470f76caa6c7eb90f8d9a21aab8e2bff8ab3c1b4997")
        XCTAssertEqual(request.openBytes.count, 79)
        XCTAssertEqual(request.metadata["shadowsocksCipher"], "aes-256-gcm")
        XCTAssertEqual(request.metadata["shadowsocksAddressFrameHex"], request.addressFrameHex)
        XCTAssertEqual(request.metadata["shadowsocksStreamOpenHex"], request.openBytesHex)
    }

    func testShadowsocksStreamRequestEncodesIPv4DestinationFrame() throws {
        let request = try ShadowsocksStreamRequest(
            credential: "aes-256-gcm:pass",
            destination: .ipv4("93.184.216.34", port: 443),
            salt: Data(repeating: 2, count: 32)
        )

        XCTAssertEqual(request.addressFrameHex, "015db8d82201bb")
    }

    func testShadowsocksStreamRequestEncodesIPv6DestinationFrame() throws {
        let request = try ShadowsocksStreamRequest(
            credential: "aes-256-gcm:pass",
            destination: .ipv6("2606:2800:0220:0001:0248:1893:25c8:1946", port: 443),
            salt: Data(repeating: 3, count: 32)
        )

        XCTAssertEqual(request.addressFrameHex, "0426062800022000010248189325c8194601bb")
    }

    func testShadowsocksStreamRequestRejectsUnsupportedMethod() {
        XCTAssertThrowsError(try ShadowsocksStreamRequest(
            credential: "chacha20-ietf-poly1305:pass",
            destination: .host("apple.com", port: 443),
            salt: Data(repeating: 1, count: 32)
        )) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("unsupported shadowsocks method"))
        }
    }

    func testShadowsocks2022AES128BuildsClientStreamHeader() throws {
        let credential = "2022-blake3-aes-128-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"
        let request = try ShadowsocksStreamRequest(
            credential: credential,
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
        let credential = "2022-blake3-aes-256-gcm:\(Data((0..<32).map(UInt8.init)).base64EncodedString())"
        let request = try ShadowsocksStreamRequest(
            credential: credential,
            destination: .ipv4("93.184.216.34", port: 443),
            salt: Data(repeating: 2, count: 32),
            timestamp: Date(timeIntervalSince1970: 1_715_000_000),
            padding: Data([0xbb])
        )

        XCTAssertEqual(request.cipher, "2022-blake3-aes-256-gcm")
        XCTAssertEqual(request.addressFrameHex, "015db8d82201bb")
        XCTAssertEqual(request.openBytes.count, 32 + 11 + 16 + 10 + 16)
    }

    func testShadowsocks2022ChaCha20Poly1305BuildsClientStreamHeader() throws {
        let credential = "2022-blake3-chacha20-poly1305:\(Data((0..<32).map(UInt8.init)).base64EncodedString())"
        let request = try ShadowsocksStreamRequest(
            credential: credential,
            destination: .host("example.com", port: 443),
            salt: Data(repeating: 3, count: 32),
            timestamp: Date(timeIntervalSince1970: 1_715_000_000),
            padding: Data([0xcc])
        )

        XCTAssertEqual(request.cipher, "2022-blake3-chacha20-poly1305")
        XCTAssertEqual(request.addressFrameHex, "030b6578616d706c652e636f6d01bb")
        XCTAssertEqual(request.openBytes.count, 32 + 11 + 16 + 18 + 16)
    }

    func testShadowsocksRegistryRecognizesApproved2022Blake3Methods() throws {
        XCTAssertTrue(try ShadowsocksCipher.supportsKnownCredential("2022-blake3-aes-128-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"))
        XCTAssertTrue(try ShadowsocksCipher.supportsKnownCredential("2022-blake3-aes-256-gcm:\(Data((0..<32).map(UInt8.init)).base64EncodedString())"))
        XCTAssertTrue(try ShadowsocksCipher.supportsKnownCredential("2022-blake3-chacha20-poly1305:\(Data((0..<32).map(UInt8.init)).base64EncodedString())"))
        XCTAssertTrue(try ShadowsocksCipher.supportsKnownCredential("aes-256-gcm:pass"))
    }

    func testShadowsocksLocalProxySupportAdvertisesFullyImplementedMethods() {
        XCTAssertTrue(ShadowsocksStreamRequest.supportsCredential("aes-256-gcm:pass"))
        XCTAssertTrue(ShadowsocksStreamRequest.supportsCredential("2022-blake3-aes-128-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"))
        XCTAssertTrue(ShadowsocksStreamRequest.supportsCredential("2022-blake3-aes-256-gcm:\(Data((0..<32).map(UInt8.init)).base64EncodedString())"))
        XCTAssertTrue(ShadowsocksStreamRequest.supportsCredential("2022-blake3-chacha20-poly1305:\(Data((0..<32).map(UInt8.init)).base64EncodedString())"))
        XCTAssertFalse(ShadowsocksStreamRequest.supportsCredential("2022-blake3-aes-192-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"))
    }

    func testShadowsocksRejectsUnknown2022Blake3Methods() throws {
        XCTAssertFalse(try ShadowsocksCipher.supportsKnownCredential("2022-blake3-aes-192-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"))
        XCTAssertFalse(try ShadowsocksCipher.supportsKnownCredential("2022-blake3-chacha8-poly1305:\(Data((0..<32).map(UInt8.init)).base64EncodedString())"))
    }

    func testShadowsocks2022CredentialValidationRejectsWrongSecretLength() throws {
        XCTAssertFalse(try ShadowsocksCipher.supportsKnownCredential("2022-blake3-aes-128-gcm:short"))
        XCTAssertFalse(try ShadowsocksCipher.supportsKnownCredential("2022-blake3-aes-256-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"))
        XCTAssertFalse(try ShadowsocksCipher.supportsKnownCredential("2022-blake3-chacha20-poly1305:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"))
    }

    func testShadowsocks2022CodecConstructorsRejectWrongSecretLength() throws {
        let credential = "2022-blake3-aes-128-gcm:\(Data((0..<15).map(UInt8.init)).base64EncodedString())"

        XCTAssertThrowsError(try ShadowsocksStreamRequest(
            credential: credential,
            destination: .host("example.com", port: 80),
            salt: Data(repeating: 1, count: 16)
        )) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid shadowsocks 2022 key"))
        }
        XCTAssertThrowsError(try ShadowsocksAEADStreamEncoder(credential: credential, salt: Data(repeating: 1, count: 16))) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid shadowsocks 2022 key"))
        }
        XCTAssertThrowsError(try ShadowsocksAEADStreamDecoder(credential: credential, salt: Data(repeating: 1, count: 16))) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid shadowsocks 2022 key"))
        }
    }

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

        let officialHashVectors = [
            1024: "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7",
            1025: "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444",
            2048: "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a",
            2049: "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030"
        ]
        for (inputLength, expectedHash) in officialHashVectors {
            let input = Data((0..<inputLength).map { UInt8($0 % 251) })
            XCTAssertEqual(InternalBLAKE3.hash(input, outputByteCount: 32).hexString, expectedHash)
        }
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

        let officialDeriveKeyVectors = [
            1024: "7356cd7720d5b66b6d0697eb3177d9f8d73a4a5c5e968896eb6a689684302706",
            1025: "effaa245f065fbf82ac186839a249707c3bddf6d3fdda22d1b95a3c970379bcb",
            2048: "7b2945cb4fef70885cc5d78a87bf6f6207dd901ff239201351ffac04e1088a23",
            2049: "2ea477c5515cc3dd606512ee72bb3e0e758cfae7232826f35fb98ca1bcbdf273"
        ]
        for (inputLength, expectedDerivedKey) in officialDeriveKeyVectors {
            let material = Data((0..<inputLength).map { UInt8($0 % 251) })
            XCTAssertEqual(InternalBLAKE3.deriveKey(context: context, material: material, outputByteCount: 32).hexString, expectedDerivedKey)
        }
    }

    func testShadowsocksStreamRequestRejectsInvalidCredential() {
        XCTAssertThrowsError(try ShadowsocksStreamRequest(
            credential: "aes-256-gcm",
            destination: .host("apple.com", port: 443),
            salt: Data(repeating: 1, count: 32)
        )) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid shadowsocks credential"))
        }
    }

    func testShadowsocksStreamRequestRejectsInvalidSalt() {
        XCTAssertThrowsError(try ShadowsocksStreamRequest(
            credential: "aes-256-gcm:pass",
            destination: .host("apple.com", port: 443),
            salt: Data(repeating: 1, count: 31)
        )) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid shadowsocks salt"))
        }
    }

    func testShadowsocksAEADStreamCodecEncryptsAndDecryptsPayloadChunks() throws {
        var encoder = try ShadowsocksAEADStreamEncoder(credential: "aes-256-gcm:pass", salt: Data(repeating: 4, count: 32))
        var decoder = try ShadowsocksAEADStreamDecoder(credential: "aes-256-gcm:pass", salt: Data(repeating: 4, count: 32))
        let firstPlaintext = Data("GET / HTTP/1.1\r\n".utf8)
        let secondPlaintext = Data("Host: apple.com\r\n\r\n".utf8)

        let firstCiphertext = try encoder.encrypt(firstPlaintext)
        let secondCiphertext = try encoder.encrypt(secondPlaintext)

        XCTAssertNotEqual(firstCiphertext.suffix(firstPlaintext.count), firstPlaintext)
        XCTAssertEqual(try decoder.decrypt(firstCiphertext), firstPlaintext)
        XCTAssertEqual(try decoder.decrypt(secondCiphertext), secondPlaintext)
    }

    func testShadowsocksAEADStreamDecoderBuffersFragmentedFrames() throws {
        var encoder = try ShadowsocksAEADStreamEncoder(credential: "aes-256-gcm:pass", salt: Data(repeating: 5, count: 32))
        var decoder = try ShadowsocksAEADStreamDecoder(credential: "aes-256-gcm:pass", salt: Data(repeating: 5, count: 32))
        let ciphertext = try encoder.encrypt(Data("fragmented payload".utf8))
        let splitIndex = ciphertext.index(ciphertext.startIndex, offsetBy: 5)

        XCTAssertNil(try decoder.appendAndDecrypt(ciphertext[..<splitIndex]))
        XCTAssertEqual(try decoder.appendAndDecrypt(ciphertext[splitIndex...]), Data("fragmented payload".utf8))
    }

    func testShadowsocksAEADStreamRejectsWrongCredential() throws {
        var encoder = try ShadowsocksAEADStreamEncoder(credential: "aes-256-gcm:pass", salt: Data(repeating: 6, count: 32))
        var decoder = try ShadowsocksAEADStreamDecoder(credential: "aes-256-gcm:wrong", salt: Data(repeating: 6, count: 32))
        let ciphertext = try encoder.encrypt(Data("secret".utf8))

        XCTAssertThrowsError(try decoder.decrypt(ciphertext))
    }

    func testShadowsocksAEADStreamEncoderCanContinueAfterOpenFrameNonces() throws {
        var encoder = try ShadowsocksAEADStreamEncoder(credential: "aes-256-gcm:pass", salt: Data(repeating: 7, count: 32), initialNonce: 2)
        var decoder = try ShadowsocksAEADStreamDecoder(credential: "aes-256-gcm:pass", salt: Data(repeating: 7, count: 32), initialNonce: 2)
        let frame = try encoder.encrypt(Data("after-open".utf8))

        XCTAssertEqual(try decoder.decrypt(frame), Data("after-open".utf8))
    }

    func testShadowsocks2022StreamCodecRoundTripsApprovedMethods() throws {
        let credentials = [
            "2022-blake3-aes-128-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())",
            "2022-blake3-aes-256-gcm:\(Data((0..<32).map(UInt8.init)).base64EncodedString())",
            "2022-blake3-chacha20-poly1305:\(Data((0..<32).map(UInt8.init)).base64EncodedString())"
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

    func testShadowsocks2022DecoderBuffersFragmentedFrames() throws {
        let credential = "2022-blake3-aes-128-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"
        let salt = Data(repeating: 9, count: 16)
        var encoder = try ShadowsocksAEADStreamEncoder(credential: credential, salt: salt, initialNonce: 2)
        var decoder = try ShadowsocksAEADStreamDecoder(credential: credential, salt: salt, initialNonce: 2)
        let ciphertext = try encoder.encrypt(Data("fragmented ss2022 payload".utf8))
        let splitIndex = ciphertext.index(ciphertext.startIndex, offsetBy: 7)

        XCTAssertNil(try decoder.appendAndDecrypt(ciphertext[..<splitIndex]))
        XCTAssertEqual(try decoder.appendAndDecrypt(ciphertext[splitIndex...]), Data("fragmented ss2022 payload".utf8))
    }

    func testShadowsocks2022ResponseDecoderConsumesServerHeaderBeforePayloadFrames() throws {
        let credential = "2022-blake3-aes-128-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"
        let requestSalt = Data(repeating: 1, count: 16)
        let responseSalt = Data(repeating: 2, count: 16)
        let parsed = try ShadowsocksStreamRequest.parseCredential(credential)
        let cipher = try XCTUnwrap(ShadowsocksCipher.lookup(method: parsed.method))
        let subkey = try cipher.deriveSubkey(password: parsed.password, salt: responseSalt)
        var responseHeader = Data([1])
        responseHeader.append(contentsOf: [0, 0, 0, 0, 102, 72, 110, 128])
        responseHeader.append(requestSalt)
        responseHeader.append(contentsOf: [0, 5])
        let encryptedHeader = try cipher.seal(responseHeader, using: subkey, nonceValue: 0)
        let encryptedFirstPayload = try cipher.seal(Data("hello".utf8), using: subkey, nonceValue: 1)
        let nextFrame = try cipher.seal(Data([0, 5]), using: subkey, nonceValue: 2) + cipher.seal(Data("again".utf8), using: subkey, nonceValue: 3)
        var decoder = try ShadowsocksAEADStreamDecoder(credential: credential, salt: responseSalt, requestSalt: requestSalt)

        let payloads = try decoder.appendAndDecryptAvailable(encryptedHeader + encryptedFirstPayload + nextFrame)

        XCTAssertEqual(payloads, [Data("hello".utf8), Data("again".utf8)])
    }

    func testVMessOpenRequestBuildsStableMetadataAndPayload() throws {
        let request = try VMessOpenRequest(
            userID: "00000000-0000-0000-0000-000000000001",
            destination: .host("apple.com", port: 443)
        )

        XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
        XCTAssertEqual(request.security, "auto")
        XCTAssertEqual(request.alterID, 0)
        XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "vmess-foundation:host:apple.com:443:auto:0")
        XCTAssertEqual(request.metadata["vmessUserIDPresent"], "true")
        XCTAssertEqual(request.metadata["vmessDestination"], "host:apple.com:443")
        XCTAssertEqual(request.metadata["vmessSecurity"], "auto")
        XCTAssertEqual(request.metadata["vmessAlterID"], "0")
        XCTAssertNil(request.metadata["vmessUserID"])
        XCTAssertFalse(request.openBytes.contains(Data("00000000-0000-0000-0000-000000000001".utf8)))
    }

    func testVMessOpenRequestRejectsInvalidUserID() {
        XCTAssertThrowsError(try VMessOpenRequest(userID: "not-a-uuid", destination: .host("apple.com", port: 443))) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid vmess user id"))
        }
    }

    func testVLESSOpenRequestBuildsCredentialSafeMetadataAndPayload() throws {
        let request = try VLESSOpenRequest(
            userID: "00000000-0000-0000-0000-000000000002",
            destination: .host("apple.com", port: 443)
        )

        XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
        XCTAssertEqual(request.security, "none")
        XCTAssertEqual(request.flow, "")
        XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "vless-foundation:host:apple.com:443:none:")
        XCTAssertEqual(request.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(request.metadata["vlessUserID"])
        XCTAssertEqual(request.metadata["vlessDestination"], "host:apple.com:443")
        XCTAssertEqual(request.metadata["vlessSecurity"], "none")
        XCTAssertEqual(request.metadata["vlessFlow"], "")
        XCTAssertFalse(request.openBytes.contains(Data("00000000-0000-0000-0000-000000000002".utf8)))
    }

    func testVLESSOpenRequestRejectsInvalidUserID() {
        XCTAssertThrowsError(try VLESSOpenRequest(userID: "not-a-uuid", destination: .host("apple.com", port: 443))) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("invalid vless user id"))
        }
    }

    func testTrojanOpenRequestBuildsCredentialSafeMetadataAndPayload() throws {
        let request = try TrojanOpenRequest(
            password: "secret-password",
            destination: .host("apple.com", port: 443),
            serverName: "trojan.example.com"
        )

        XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
        XCTAssertEqual(request.serverName, "trojan.example.com")
        XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "trojan-foundation:host:apple.com:443:trojan.example.com")
        XCTAssertEqual(request.metadata["trojanPasswordPresent"], "true")
        XCTAssertNil(request.metadata["trojanPassword"])
        XCTAssertEqual(request.metadata["trojanDestination"], "host:apple.com:443")
        XCTAssertEqual(request.metadata["trojanServerName"], "trojan.example.com")
        XCTAssertFalse(request.openBytes.contains(Data("secret-password".utf8)))
    }

    func testTrojanOpenRequestRejectsEmptyPassword() {
        XCTAssertThrowsError(try TrojanOpenRequest(password: "   ", destination: .host("apple.com", port: 443))) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("missing trojan password"))
        }
    }

    func testHysteria2OpenRequestBuildsCredentialSafeMetadataAndPayload() throws {
        let request = try Hysteria2OpenRequest(
            authentication: "hysteria-secret",
            destination: .host("apple.com", port: 443),
            sni: " hysteria.example.com ",
            obfuscation: "obfs-secret"
        )

        XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
        XCTAssertEqual(request.sni, "hysteria.example.com")
        XCTAssertTrue(request.obfuscationPresent)
        XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "hysteria2-foundation:host:apple.com:443:hysteria.example.com:auth-present:true")
        XCTAssertEqual(request.metadata["hysteria2AuthPresent"], "true")
        XCTAssertEqual(request.metadata["hysteria2Destination"], "host:apple.com:443")
        XCTAssertEqual(request.metadata["hysteria2SNI"], "hysteria.example.com")
        XCTAssertEqual(request.metadata["hysteria2ObfsPresent"], "true")
        XCTAssertFalse(request.openBytes.contains(Data("hysteria-secret".utf8)))
        XCTAssertFalse(request.openBytes.contains(Data("obfs-secret".utf8)))
    }

    func testHysteria2OpenRequestRejectsEmptyAuthenticationSecret() {
        XCTAssertThrowsError(try Hysteria2OpenRequest(authentication: "   ", destination: .host("apple.com", port: 443))) { error in
            XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("missing hysteria2 authentication"))
        }
    }

    func testTUICOpenRequestBuildsCredentialSafeMetadataAndPayload() throws {
        let request = try TUICOpenRequest(
            credential: "00000000-0000-0000-0000-000000000003:tuic-password",
            destination: .host("apple.com", port: 443),
            sni: " tuic.example.com "
        )

        XCTAssertEqual(request.destinationDescription, "host:apple.com:443")
        XCTAssertEqual(request.sni, "tuic.example.com")
        XCTAssertEqual(String(data: request.openBytes, encoding: .utf8), "tuic-foundation:host:apple.com:443:tuic.example.com:uuid-present:password-present")
        XCTAssertEqual(request.metadata["tuicUUIDPresent"], "true")
        XCTAssertEqual(request.metadata["tuicPasswordPresent"], "true")
        XCTAssertEqual(request.metadata["tuicDestination"], "host:apple.com:443")
        XCTAssertEqual(request.metadata["tuicSNI"], "tuic.example.com")
        XCTAssertNil(request.metadata["tuicUUID"])
        XCTAssertNil(request.metadata["tuicPassword"])
        XCTAssertFalse(request.openBytes.contains(Data("00000000-0000-0000-0000-000000000003".utf8)))
        XCTAssertFalse(request.openBytes.contains(Data("tuic-password".utf8)))
    }

    func testTUICOpenRequestRejectsInvalidCredentials() {
        let cases: [(String, ProxyProtocolError)] = [
            ("not-a-uuid:tuic-password", .invalidConfiguration("invalid tuic uuid")),
            ("00000000-0000-0000-0000-000000000003:", .invalidConfiguration("missing tuic password")),
            ("00000000-0000-0000-0000-000000000003", .invalidConfiguration("invalid tuic credential"))
        ]

        for (credential, expectedError) in cases {
            XCTAssertThrowsError(try TUICOpenRequest(credential: credential, destination: .host("apple.com", port: 443))) { error in
                XCTAssertEqual(error as? ProxyProtocolError, expectedError)
            }
        }
    }

    func testEstablishedProxyConnectionStoresNodeIDAndDestination() {
        let connection = EstablishedProxyConnection(
            nodeID: NodeID(rawValue: "node-1"),
            destination: .host("apple.com", port: 443)
        )

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
    }

    func testUnsupportedProxyAdapterFailsWithRequestedProtocol() async {
        let node = makeNode(protocolType: .tuic, transport: .quic)
        let adapter = UnsupportedProxyAdapter(protocolType: .tuic)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.tuic))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHysteria2ProxyAdapterOpensQUICTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .quic)
        let adapter = Hysteria2ProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .hysteria2, transport: .quic, credentialAccount: "hysteria-secret")
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .quic)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "hysteria2")
        XCTAssertEqual(transport.requests.first?.metadata["hysteria2AuthPresent"], "true")
        XCTAssertEqual(transport.requests.first?.metadata["hysteria2Destination"], "host:apple.com:443")
        let payload = transport.requests.first?.initialPayload ?? Data()
        XCTAssertEqual(String(data: payload, encoding: .utf8), "hysteria2-foundation:host:apple.com:443:example.com:auth-present:false")
        XCTAssertFalse(payload.contains(Data("hysteria-secret".utf8)))
    }

    func testHysteria2ProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
        let cases: [(ProxyNode, ProxyProtocolError)] = [
            (makeNode(protocolType: .vmess, transport: .quic, credentialAccount: "hysteria-secret"), .unsupportedProtocol(.vmess)),
            (makeNode(protocolType: .hysteria2, transport: .tcp, credentialAccount: "hysteria-secret"), .unsupportedTransport(.tcp)),
            (makeNode(protocolType: .hysteria2, transport: .quic, serverHost: "   ", credentialAccount: "hysteria-secret"), .invalidConfiguration("missing hysteria2 server host")),
            (makeNode(protocolType: .hysteria2, transport: .quic, serverPort: 0, credentialAccount: "hysteria-secret"), .invalidConfiguration("invalid hysteria2 server port")),
            (makeNode(protocolType: .hysteria2, transport: .quic, credentialAccount: "   "), .invalidConfiguration("missing hysteria2 authentication"))
        ]

        for (node, expectedError) in cases {
            let transport = RecordingTransportAdapter(transport: .quic)
            let adapter = Hysteria2ProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
            do {
                _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
                XCTFail("Expected Hysteria2 validation failure")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(transport.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testTUICProxyAdapterOpensQUICTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .quic)
        let adapter = TUICProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .tuic, transport: .quic, credentialAccount: "00000000-0000-0000-0000-000000000003:tuic-password")
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .quic)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "tuic")
        XCTAssertEqual(transport.requests.first?.metadata["tuicUUIDPresent"], "true")
        XCTAssertEqual(transport.requests.first?.metadata["tuicPasswordPresent"], "true")
        XCTAssertEqual(transport.requests.first?.metadata["tuicDestination"], "host:apple.com:443")
        let payload = transport.requests.first?.initialPayload ?? Data()
        XCTAssertEqual(String(data: payload, encoding: .utf8), "tuic-foundation:host:apple.com:443:example.com:uuid-present:password-present")
        XCTAssertFalse(payload.contains(Data("00000000-0000-0000-0000-000000000003".utf8)))
        XCTAssertFalse(payload.contains(Data("tuic-password".utf8)))
    }

    func testTUICProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
        let cases: [(ProxyNode, ProxyProtocolError)] = [
            (makeNode(protocolType: .hysteria2, transport: .quic, credentialAccount: "00000000-0000-0000-0000-000000000003:tuic-password"), .unsupportedProtocol(.hysteria2)),
            (makeNode(protocolType: .tuic, transport: .tcp, credentialAccount: "00000000-0000-0000-0000-000000000003:tuic-password"), .unsupportedTransport(.tcp)),
            (makeNode(protocolType: .tuic, transport: .quic, serverHost: "   ", credentialAccount: "00000000-0000-0000-0000-000000000003:tuic-password"), .invalidConfiguration("missing tuic server host")),
            (makeNode(protocolType: .tuic, transport: .quic, serverPort: 0, credentialAccount: "00000000-0000-0000-0000-000000000003:tuic-password"), .invalidConfiguration("invalid tuic server port")),
            (makeNode(protocolType: .tuic, transport: .quic, credentialAccount: "not-a-uuid:tuic-password"), .invalidConfiguration("invalid tuic uuid")),
            (makeNode(protocolType: .tuic, transport: .quic, credentialAccount: "00000000-0000-0000-0000-000000000003:"), .invalidConfiguration("missing tuic password"))
        ]

        for (node, expectedError) in cases {
            let transport = RecordingTransportAdapter(transport: .quic)
            let adapter = TUICProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
            do {
                _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
                XCTFail("Expected TUIC validation failure")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(transport.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testNoopProxyAdapterRemainsUnsupportedAlias() async {
        let node = makeNode(protocolType: .hysteria2, transport: .quic)
        let adapter = NoopProxyAdapter()
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.hysteria2))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProxyProtocolErrorDescriptionsAreStableAndCredentialSafe() {
        let errors: [(ProxyProtocolError, String)] = [
            (.invalidConfiguration("missing server host"), "Invalid configuration"),
            (.dnsFailed("example.com"), "DNS failed"),
            (.tcpConnectFailed("connection refused"), "TCP connect failed"),
            (.tlsHandshakeFailed("certificate rejected"), "TLS handshake failed"),
            (.authenticationFailed("method rejected"), "Authentication failed"),
            (.unsupportedTransport(.quic), "Unsupported transport: quic"),
            (.unsupportedProtocol(.tuic), "Unsupported protocol: tuic"),
            (.protocolHandshakeFailed("bad response"), "Protocol handshake failed"),
            (.quicHandshakeFailed("timeout"), "QUIC handshake failed"),
            (.udpUnsupported, "UDP unsupported"),
            (.remoteClosed, "Remote closed"),
            (.timeout, "Timeout")
        ]

        for (error, description) in errors {
            XCTAssertEqual(error.description, description)
            XCTAssertFalse(error.description.contains("secret"))
            XCTAssertFalse(error.description.contains("password"))
            XCTAssertFalse(error.description.contains("token"))
        }
    }

    func testProxyProtocolErrorDescriptionsRedactSensitiveAssociatedStrings() {
        let errors: [ProxyProtocolError] = [
            .invalidConfiguration("uri=ss://password=secret-token@example.com"),
            .dnsFailed("password=secret-token"),
            .tcpConnectFailed("token=secret-token"),
            .tlsHandshakeFailed("password=secret-token"),
            .authenticationFailed("password=secret-token"),
            .protocolHandshakeFailed("password=secret-token"),
            .quicHandshakeFailed("password=secret-token")
        ]

        for error in errors {
            XCTAssertFalse(error.description.contains("password"))
            XCTAssertFalse(error.description.contains("secret"))
            XCTAssertFalse(error.description.contains("token"))
        }
    }

    func testProxyAdapterRegistryReturnsRegisteredAdapter() async throws {
        let adapter = RecordingProxyAdapter(protocolType: .trojan)
        let registry = ProxyAdapterRegistry(adapters: [adapter])
        let selected = registry.adapter(for: .trojan)
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        let connection = try await selected.connect(request: request)

        XCTAssertEqual(selected.supportedProtocol, .trojan)
        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
    }

    func testProxyAdapterRegistryFallsBackToUnsupportedAdapter() async {
        let registry = ProxyAdapterRegistry(adapters: [])
        let selected = registry.adapter(for: .vless)
        let request = ProxyRequest(node: makeNode(protocolType: .vless, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await selected.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vless))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProxyAdapterRegistryUsesLastRegisteredAdapterForDuplicates() async throws {
        let first = RecordingProxyAdapter(protocolType: .vmess, connectionNodeID: NodeID(rawValue: "first"))
        let second = RecordingProxyAdapter(protocolType: .vmess, connectionNodeID: NodeID(rawValue: "second"))
        let registry = ProxyAdapterRegistry(adapters: [first, second])
        let selected = registry.adapter(for: .vmess)
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        let connection = try await selected.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "second"))
    }

    func testTransportBackedProxyAdapterOpensNodeTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .grpc)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .trojan, transport: .grpc)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .grpc)
        XCTAssertEqual(transport.requests.first?.tls?.enabled, true)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "trojan")
        XCTAssertEqual(transport.requests.first?.metadata["destination"], "host:apple.com:443")
    }

    func testTransportBackedProxyAdapterRejectsProtocolMismatchBeforeOpeningTransport() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vmess))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVMessProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .vmess, transport: .tcp, credentialAccount: "00000000-0000-0000-0000-000000000001")
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "vmess")
        XCTAssertEqual(transport.requests.first?.metadata["vmessUserIDPresent"], "true")
        XCTAssertNil(transport.requests.first?.metadata["vmessUserID"])
        XCTAssertEqual(transport.requests.first?.metadata["vmessDestination"], "host:apple.com:443")
        XCTAssertEqual(String(data: transport.requests.first?.initialPayload ?? Data(), encoding: .utf8), "vmess-foundation:host:apple.com:443:auto:0")
        XCTAssertFalse((transport.requests.first?.initialPayload ?? Data()).contains(Data("00000000-0000-0000-0000-000000000001".utf8)))
    }

    func testVMessProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVMessProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
        let cases: [(ProxyNode, ProxyProtocolError)] = [
            (makeNode(protocolType: .vmess, transport: .tcp, serverHost: "   ", credentialAccount: "00000000-0000-0000-0000-000000000001"), .invalidConfiguration("missing vmess server host")),
            (makeNode(protocolType: .vmess, transport: .tcp, serverPort: 0, credentialAccount: "00000000-0000-0000-0000-000000000001"), .invalidConfiguration("invalid vmess server port")),
            (makeNode(protocolType: .vmess, transport: .tcp, credentialAccount: "not-a-uuid"), .invalidConfiguration("invalid vmess user id")),
            (makeNode(protocolType: .vmess, transport: .quic, credentialAccount: "00000000-0000-0000-0000-000000000001"), .unsupportedTransport(.quic))
        ]

        for (node, expectedError) in cases {
            let transport = RecordingTransportAdapter(transport: .tcp)
            let adapter = VMessProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
            do {
                _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
                XCTFail("Expected VMess validation failure")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(transport.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testVLESSProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let node = makeNode(protocolType: .vless, transport: .tcp, credentialAccount: "00000000-0000-0000-0000-000000000002")
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "vless")
        XCTAssertEqual(transport.requests.first?.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(transport.requests.first?.metadata["vlessUserID"])
        XCTAssertEqual(transport.requests.first?.metadata["vlessDestination"], "host:apple.com:443")
        XCTAssertEqual(String(data: transport.requests.first?.initialPayload ?? Data(), encoding: .utf8), "vless-foundation:host:apple.com:443:none:")
        XCTAssertFalse((transport.requests.first?.initialPayload ?? Data()).contains(Data("00000000-0000-0000-0000-000000000002".utf8)))
    }

    func testVLESSProxyAdapterOpensRealityTCPTransportWithCredentialSafePayload() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let reality = RealityOptions(publicKey: "reality-public-key", shortID: "abc123", spiderX: "/")
        let tls = TLSOptions(enabled: true, serverName: "reality.example.com", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: reality)
        let node = makeNode(protocolType: .vless, transport: .tcp, tls: tls, credentialAccount: "00000000-0000-0000-0000-000000000002")
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.tls, tls)
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "vless")
        XCTAssertEqual(transport.requests.first?.metadata["vlessUserIDPresent"], "true")
        XCTAssertNil(transport.requests.first?.metadata["vlessUserID"])
        let payload = transport.requests.first?.initialPayload ?? Data()
        XCTAssertEqual(String(data: payload, encoding: .utf8), "vless-foundation:host:apple.com:443:none:")
        XCTAssertFalse(payload.contains(Data("00000000-0000-0000-0000-000000000002".utf8)))
        XCTAssertFalse(payload.contains(Data("reality-public-key".utf8)))
    }

    func testVLESSProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVLESSProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
        let cases: [(ProxyNode, ProxyProtocolError)] = [
            (makeNode(protocolType: .vless, transport: .tcp, serverHost: "   ", credentialAccount: "00000000-0000-0000-0000-000000000002"), .invalidConfiguration("missing vless server host")),
            (makeNode(protocolType: .vless, transport: .tcp, serverPort: 0, credentialAccount: "00000000-0000-0000-0000-000000000002"), .invalidConfiguration("invalid vless server port")),
            (makeNode(protocolType: .vless, transport: .tcp, credentialAccount: "not-a-uuid"), .invalidConfiguration("invalid vless user id")),
            (makeNode(protocolType: .vless, transport: .quic, credentialAccount: "00000000-0000-0000-0000-000000000002"), .unsupportedTransport(.quic))
        ]

        for (node, expectedError) in cases {
            let transport = RecordingTransportAdapter(transport: .tcp)
            let adapter = VLESSProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
            do {
                _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
                XCTFail("Expected VLESS validation failure")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(transport.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testTrojanProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TrojanProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let tls = TLSOptions(enabled: true, serverName: "trojan.example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let node = makeNode(protocolType: .trojan, transport: .tcp, tls: tls, credentialAccount: "secret-password")
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.tls, tls)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "trojan")
        XCTAssertEqual(transport.requests.first?.metadata["trojanPasswordPresent"], "true")
        XCTAssertNil(transport.requests.first?.metadata["trojanPassword"])
        XCTAssertEqual(transport.requests.first?.metadata["trojanDestination"], "host:apple.com:443")
        XCTAssertEqual(transport.requests.first?.metadata["trojanServerName"], "trojan.example.com")
        XCTAssertEqual(String(data: transport.requests.first?.initialPayload ?? Data(), encoding: .utf8), "trojan-foundation:host:apple.com:443:trojan.example.com")
        XCTAssertFalse((transport.requests.first?.initialPayload ?? Data()).contains(Data("secret-password".utf8)))
    }

    func testTrojanProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TrojanProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .vmess, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.vmess))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTrojanProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen() async {
        let cases: [(ProxyNode, ProxyProtocolError)] = [
            (makeNode(protocolType: .trojan, transport: .tcp, serverHost: "   ", credentialAccount: "secret-password"), .invalidConfiguration("missing trojan server host")),
            (makeNode(protocolType: .trojan, transport: .tcp, serverPort: 0, credentialAccount: "secret-password"), .invalidConfiguration("invalid trojan server port")),
            (makeNode(protocolType: .trojan, transport: .tcp, credentialAccount: "   "), .invalidConfiguration("missing trojan password")),
            (makeNode(protocolType: .trojan, transport: .quic, credentialAccount: "secret-password"), .unsupportedTransport(.quic))
        ]

        for (node, expectedError) in cases {
            let transport = RecordingTransportAdapter(transport: .tcp)
            let adapter = TrojanProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
            do {
                _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))
                XCTFail("Expected Trojan validation failure")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedError)
                XCTAssertEqual(transport.requests, [])
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testProtocolFoundationAdaptersOpenWebSocketTransport() async throws {
        try await assertProtocolFoundationAdaptersOpen(transport: .webSocket)
    }

    func testProtocolFoundationAdaptersOpenHTTP2Transport() async throws {
        try await assertProtocolFoundationAdaptersOpen(transport: .http2)
    }

    func testProtocolFoundationAdaptersOpenGRPCTransport() async throws {
        try await assertProtocolFoundationAdaptersOpen(transport: .grpc)
    }

    private func assertProtocolFoundationAdaptersOpen(transport transportType: TransportType) async throws {
        let cases: [(ProxyProtocolType, String)] = [
            (.vmess, "00000000-0000-0000-0000-000000000001"),
            (.vless, "00000000-0000-0000-0000-000000000002"),
            (.trojan, "secret-password")
        ]

        for (protocolType, credentialAccount) in cases {
            let transport = RecordingTransportAdapter(transport: transportType)
            let registry = TransportAdapterRegistry(adapters: [transport])
            let adapter: any ProxyAdapter
            switch protocolType {
            case .vmess:
                adapter = VMessProxyAdapter(transportRegistry: registry)
            case .vless:
                adapter = VLESSProxyAdapter(transportRegistry: registry)
            case .trojan:
                adapter = TrojanProxyAdapter(transportRegistry: registry)
            default:
                XCTFail("Unexpected protocol type")
                return
            }
            let node = makeNode(protocolType: protocolType, transport: transportType, credentialAccount: credentialAccount)

            _ = try await adapter.connect(request: ProxyRequest(node: node, destination: .host("apple.com", port: 443)))

            XCTAssertEqual(transport.requests.count, 1)
            XCTAssertEqual(transport.requests.first?.transport, transportType)
            XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], protocolType.rawValue)
        }
    }

    func testTransportBackedProxyAdapterOmitsDisabledTLS() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = TransportBackedProxyAdapter(protocolType: .trojan, transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp, tls: .disabled), destination: .ipv4("93.184.216.34", port: 443))

        _ = try await adapter.connect(request: request)

        XCTAssertNil(transport.requests.first?.tls)
        XCTAssertEqual(transport.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
    }

    func testShadowsocksProxyAdapterRejectsProtocolMismatchBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported protocol")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedProtocol(.trojan))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsEmptyServerHostBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, serverHost: "   "), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("missing shadowsocks server host"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsInvalidServerPortBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, serverPort: 0), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("invalid shadowsocks server port"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsEmptyCredentialAccountBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, credentialAccount: "   "), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected invalid configuration")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .invalidConfiguration("missing shadowsocks credential account"))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRejectsNonTCPTransportBeforeTransportOpen() async {
        let transport = RecordingTransportAdapter(transport: .grpc)
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: [transport]))
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .grpc), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected unsupported transport")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .unsupportedTransport(.grpc))
            XCTAssertEqual(transport.requests, [])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterReportsSupportedProtocol() {
        let adapter = ShadowsocksProxyAdapter(transportRegistry: TransportAdapterRegistry(adapters: []))

        XCTAssertEqual(adapter.supportedProtocol, .shadowsocks)
    }

    func testShadowsocksProxyAdapterOpensTCPTransportAndReturnsProxyConnection() async throws {
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [transport]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.host, "example.com")
        XCTAssertEqual(transport.requests.first?.port, 443)
        XCTAssertEqual(transport.requests.first?.transport, .tcp)
        XCTAssertEqual(transport.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(transport.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(transport.requests.first?.metadata["shadowsocksCipher"], "aes-256-gcm")
        XCTAssertEqual(transport.requests.first?.metadata["shadowsocksAddressFrameHex"], "03096170706c652e636f6d01bb")
        XCTAssertEqual(transport.requests.first?.metadata["shadowsocksStreamOpenHex"]?.count, 158)
        XCTAssertEqual(transport.requests.first?.initialPayload?.count, 79)
    }

    func testShadowsocksProxyAdapterUsesMethodSpecificSaltLength() async throws {
        let credential = "2022-blake3-aes-128-gcm:\(Data((0..<16).map(UInt8.init)).base64EncodedString())"
        let transport = RecordingTransportAdapter(transport: .tcp)
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [transport]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: credential)
        )
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp), destination: .host("apple.com", port: 443))

        _ = try await adapter.connect(request: request)

        XCTAssertEqual(transport.requests.first?.metadata["shadowsocksCipher"], "2022-blake3-aes-128-gcm")
        XCTAssertEqual(transport.requests.first?.initialPayload?.count, 16 + 11 + 16 + 16 + 16)
    }

    func testTransportBackedProxyAdapterMapsTransportErrorsToProtocolErrors() async {
        let cases: [(TransportError, ProxyProtocolError)] = [
            (.invalidConfiguration("secret invalid"), .invalidConfiguration("transport invalid")),
            (.dnsFailed("secret host"), .dnsFailed("transport dns failed")),
            (.tcpConnectFailed("password refused"), .tcpConnectFailed("transport tcp connect failed")),
            (.tlsHandshakeFailed("token rejected"), .tlsHandshakeFailed("transport tls handshake failed")),
            (.unsupportedTransport(.quic), .unsupportedTransport(.quic)),
            (.quicHandshakeFailed("secret timeout"), .quicHandshakeFailed("transport quic handshake failed")),
            (.remoteClosed, .remoteClosed),
            (.timeout, .timeout)
        ]

        for (transportError, expectedProtocolError) in cases {
            let adapter = TransportBackedProxyAdapter(
                protocolType: .trojan,
                transportRegistry: TransportAdapterRegistry(adapters: [FailingTransportAdapter(transport: .tcp, error: transportError)])
            )
            let request = ProxyRequest(node: makeNode(protocolType: .trojan, transport: .tcp), destination: .host("apple.com", port: 443))

            do {
                _ = try await adapter.connect(request: request)
                XCTFail("Expected protocol error")
            } catch let error as ProxyProtocolError {
                XCTAssertEqual(error, expectedProtocolError)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testShadowsocksProxyAdapterPropagatesMappedTransportFailure() async {
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [FailingTransportAdapter(transport: .tcp, error: .tcpConnectFailed("password refused"))]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected mapped transport failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tcpConnectFailed("transport tcp connect failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterRoutesEnabledTLSThroughSelectorTLSChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [selector]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: nil, reality: nil)
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp, tls: tls)
        let request = ProxyRequest(node: node, destination: .host("apple.com", port: 443), metadata: ["packetID": "packet-1"])

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, ProxyDestination.host("apple.com", port: 443))
        XCTAssertEqual(plain.requests, [])
        XCTAssertEqual(tlsChild.requests.count, 1)
        XCTAssertEqual(tlsChild.requests.first?.host, "example.com")
        XCTAssertEqual(tlsChild.requests.first?.port, 443)
        XCTAssertEqual(tlsChild.requests.first?.transport, .tcp)
        XCTAssertEqual(tlsChild.requests.first?.tls, tls)
        XCTAssertEqual(tlsChild.requests.first?.metadata["packetID"], "packet-1")
        XCTAssertEqual(tlsChild.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(tlsChild.requests.first?.metadata["destination"], "host:apple.com:443")
    }

    func testShadowsocksProxyAdapterRoutesDisabledTLSThroughSelectorPlainChild() async throws {
        let plain = RecordingTransportAdapter(transport: .tcp)
        let tlsChild = RecordingTransportAdapter(transport: .tcp)
        let selector = TCPTLSTransportAdapter(plain: plain, tls: tlsChild)
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [selector]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let node = makeNode(protocolType: .shadowsocks, transport: .tcp, tls: .disabled)
        let request = ProxyRequest(node: node, destination: .ipv4("93.184.216.34", port: 443))

        let connection = try await adapter.connect(request: request)

        XCTAssertEqual(connection.nodeID, NodeID(rawValue: "node-1"))
        XCTAssertEqual(connection.destination, .ipv4("93.184.216.34", port: 443))
        XCTAssertEqual(plain.requests.count, 1)
        XCTAssertEqual(plain.requests.first?.host, "example.com")
        XCTAssertEqual(plain.requests.first?.port, 443)
        XCTAssertEqual(plain.requests.first?.transport, .tcp)
        XCTAssertNil(plain.requests.first?.tls)
        XCTAssertEqual(plain.requests.first?.metadata["proxyProtocol"], "shadowsocks")
        XCTAssertEqual(plain.requests.first?.metadata["destination"], "ipv4:93.184.216.34:443")
        XCTAssertEqual(tlsChild.requests, [])
    }

    func testShadowsocksProxyAdapterMapsSelectorTLSChildFailure() async {
        let selector = TCPTLSTransportAdapter(
            plain: RecordingTransportAdapter(transport: .tcp),
            tls: FailingTransportAdapter(transport: .tcp, error: .tlsHandshakeFailed("tls refused"))
        )
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [selector]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil)
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, tls: tls), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected mapped TLS failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tlsHandshakeFailed("transport tls handshake failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShadowsocksProxyAdapterMapsSelectorPlainChildFailure() async {
        let selector = TCPTLSTransportAdapter(
            plain: FailingTransportAdapter(transport: .tcp, error: .tcpConnectFailed("plain refused")),
            tls: RecordingTransportAdapter(transport: .tcp)
        )
        let adapter = ShadowsocksProxyAdapter(
            transportRegistry: TransportAdapterRegistry(adapters: [selector]),
            credentialResolver: StaticShadowsocksCredentialResolver(credential: "aes-256-gcm:pass")
        )
        let request = ProxyRequest(node: makeNode(protocolType: .shadowsocks, transport: .tcp, tls: .disabled), destination: .host("apple.com", port: 443))

        do {
            _ = try await adapter.connect(request: request)
            XCTFail("Expected mapped plain failure")
        } catch let error as ProxyProtocolError {
            XCTAssertEqual(error, .tcpConnectFailed("transport tcp connect failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeNode(
        protocolType: ProxyProtocolType,
        transport: TransportType,
        tls: TLSOptions = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: [], fingerprint: nil, reality: nil),
        serverHost: String = "example.com",
        serverPort: Int = 443,
        credentialAccount: String = "node-1"
    ) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo Node",
            protocolType: protocolType,
            serverHost: serverHost,
            serverPort: serverPort,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: credentialAccount),
            transport: transport,
            tls: tls,
            udpPolicy: .disabled
        )
    }

    private struct RecordingProxyAdapter: ProxyAdapter {
        let supportedProtocol: ProxyProtocolType
        let connectionNodeID: NodeID

        init(protocolType: ProxyProtocolType, connectionNodeID: NodeID = NodeID(rawValue: "node-1")) {
            self.supportedProtocol = protocolType
            self.connectionNodeID = connectionNodeID
        }

        func connect(request: ProxyRequest) async throws -> any ProxyConnection {
            EstablishedProxyConnection(nodeID: connectionNodeID, destination: request.destination)
        }
    }
}

private struct StaticShadowsocksCredentialResolver: ShadowsocksCredentialResolver {
    let credential: String

    func credential(for reference: CredentialReference) throws -> String {
        credential
    }
}

private final class RecordingTransportAdapter: TransportAdapter, @unchecked Sendable {
    let supportedTransport: TransportType
    private let lock = NSLock()
    private var storedRequests: [TransportRequest] = []

    var requests: [TransportRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    init(transport: TransportType) {
        self.supportedTransport = transport
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        record(request)
        return EstablishedTransportConnection(host: request.host, port: request.port, transport: request.transport)
    }

    private func record(_ request: TransportRequest) {
        lock.lock()
        defer { lock.unlock() }
        storedRequests.append(request)
    }
}

private struct FailingTransportAdapter: TransportAdapter {
    let supportedTransport: TransportType
    let error: TransportError

    init(transport: TransportType, error: TransportError) {
        self.supportedTransport = transport
        self.error = error
    }

    func open(request: TransportRequest) async throws -> any TransportConnection {
        throw error
    }
}

fileprivate extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
