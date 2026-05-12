# Protocol Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every planned protocol and transport plaintext foundation marker with deterministic local wire-format builders, and pass local SwiftPM tests for the full planned Alpha protocol matrix.

**Architecture:** Keep the current `ProxyAdapter` → `TransportRequest.initialPayload` boundary. Implement small, locally testable builders for protocol open bytes and transport prelude bytes, then update adapter tests so the existing app/runtime layers do not need churn.

**Tech Stack:** Swift 5.10, SwiftPM, XCTest, Foundation, CryptoKit, existing `IrockCore`, `IrockProtocols`, and `IrockTransport` packages.

---

## File structure

- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
  - Replace VMess/VLESS/Trojan/Hysteria2/TUIC marker payloads with binary builders.
  - Add shared address encoding helpers used by protocol open requests.
  - Add internal SHA224 support for Trojan password hashing.
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
  - Update existing opener and adapter assertions from marker strings to deterministic bytes.
  - Add protocol vector tests and secret-redaction regressions.
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
  - Replace WebSocket/HTTP2/gRPC/QUIC/Reality marker payloads with local wire-format/prelude builders.
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`
  - Update transport tests to assert generated request/prelude bytes and no plaintext foundation markers.
- Modify if needed: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift`
  - Keep parser scope explicit: classification is not full URI import for non-Shadowsocks protocols.

---

### Task 1: Add shared protocol address encoding and SHA224 tests

**Files:**
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`

- [ ] **Step 1: Write failing address and SHA224 tests**

Insert near the top of `IrockProtocolsTests` after `testProxyDestinationEquatableCases()`:

```swift
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
}

func testProtocolAddressEncoderRejectsInvalidInputs() {
    let cases: [ProxyDestination] = [
        .host("", port: 443),
        .host(String(repeating: "a", count: 256), port: 443),
        .host("apple.com", port: 0),
        .ipv4("999.184.216.34", port: 443),
        .ipv6("::1", port: 443)
    ]

    for destination in cases {
        XCTAssertThrowsError(try ProtocolAddressFrame(destination: destination, domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04))
    }
}

func testSHA224MatchesTrojanPasswordVector() {
    XCTAssertEqual(
        SHA224.hashHex("secret-password"),
        "869ce74cceadfb55774ed4ff96cdb65be71412e3d669878bec160955"
    )
}
```

If the SHA224 expected value fails during execution, recompute it with system Python before changing code:

```bash
python3 - <<'PY'
import hashlib
print(hashlib.sha224(b"secret-password").hexdigest())
PY
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testProtocolAddressEncoderBuildsDomainIPv4AndIPv6Frames|IrockProtocolsTests/testProtocolAddressEncoderRejectsInvalidInputs|IrockProtocolsTests/testSHA224MatchesTrojanPasswordVector'
```

Expected: FAIL because `ProtocolAddressFrame` and `SHA224` are not defined.

- [ ] **Step 3: Add minimal shared helpers**

In `IrockProtocols.swift`, add these helpers after `ProxyDestination`:

```swift
struct ProtocolAddressFrame: Equatable, Sendable {
    let bytes: Data
    let description: String

    init(destination: ProxyDestination, domainType: UInt8, ipv4Type: UInt8, ipv6Type: UInt8) throws {
        switch destination {
        case let .host(host, port):
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.utf8.count <= UInt8.max else {
                throw ProxyProtocolError.invalidConfiguration("invalid destination host")
            }
            var data = Data([domainType, UInt8(trimmed.utf8.count)])
            data.append(Data(trimmed.utf8))
            data.append(try Self.portBytes(port))
            self.bytes = data
            self.description = "host:\(trimmed):\(port)"
        case let .ipv4(address, port):
            let octets = try Self.ipv4Bytes(address)
            var data = Data([ipv4Type])
            data.append(contentsOf: octets)
            data.append(try Self.portBytes(port))
            self.bytes = data
            self.description = "ipv4:\(address):\(port)"
        case let .ipv6(address, port):
            let segments = try Self.ipv6Bytes(address)
            var data = Data([ipv6Type])
            data.append(contentsOf: segments)
            data.append(try Self.portBytes(port))
            self.bytes = data
            self.description = "ipv6:\(address):\(port)"
        }
    }

    private static func portBytes(_ port: Int) throws -> Data {
        guard (1...65_535).contains(port) else {
            throw ProxyProtocolError.invalidConfiguration("invalid destination port")
        }
        return Data([UInt8(port >> 8), UInt8(port & 0xff)])
    }

    private static func ipv4Bytes(_ address: String) throws -> [UInt8] {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            throw ProxyProtocolError.invalidConfiguration("invalid ipv4 destination")
        }
        return try parts.map { part in
            guard let value = UInt8(part) else {
                throw ProxyProtocolError.invalidConfiguration("invalid ipv4 destination")
            }
            return value
        }
    }

    private static func ipv6Bytes(_ address: String) throws -> [UInt8] {
        let parts = address.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 8 else {
            throw ProxyProtocolError.invalidConfiguration("invalid ipv6 destination")
        }
        return try parts.flatMap { part -> [UInt8] in
            guard part.count <= 4, let value = UInt16(part, radix: 16) else {
                throw ProxyProtocolError.invalidConfiguration("invalid ipv6 destination")
            }
            return [UInt8(value >> 8), UInt8(value & 0xff)]
        }
    }
}
```

Add this internal SHA224 helper after the existing `Data` extension:

```swift
enum SHA224 {
    static func hashHex(_ string: String) -> String {
        hash(Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ data: Data) -> [UInt8] {
        var message = Array(data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        message.append(contentsOf: (0..<8).reversed().map { UInt8((bitLength >> UInt64($0 * 8)) & 0xff) })

        var h0: UInt32 = 0xc1059ed8
        var h1: UInt32 = 0x367cd507
        var h2: UInt32 = 0x3070dd17
        var h3: UInt32 = 0xf70e5939
        var h4: UInt32 = 0xffc00b31
        var h5: UInt32 = 0x68581511
        var h6: UInt32 = 0x64f98fa7
        var h7: UInt32 = 0xbefa4fa4

        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let offset = chunkStart + index * 4
                words[index] = UInt32(message[offset]) << 24 | UInt32(message[offset + 1]) << 16 | UInt32(message[offset + 2]) << 8 | UInt32(message[offset + 3])
            }
            for index in 16..<64 {
                let s0 = words[index - 15].rotateRight(7) ^ words[index - 15].rotateRight(18) ^ (words[index - 15] >> 3)
                let s1 = words[index - 2].rotateRight(17) ^ words[index - 2].rotateRight(19) ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4
            var f = h5
            var g = h6
            var h = h7

            for index in 0..<64 {
                let sum1 = e.rotateRight(6) ^ e.rotateRight(11) ^ e.rotateRight(25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ sum1 &+ ch &+ SHA224.k[index] &+ words[index]
                let sum0 = a.rotateRight(2) ^ a.rotateRight(13) ^ a.rotateRight(22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = sum0 &+ maj
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
            h5 = h5 &+ f
            h6 = h6 &+ g
            h7 = h7 &+ h
        }

        return [h0, h1, h2, h3, h4, h5, h6].flatMap { word in
            [UInt8(word >> 24), UInt8((word >> 16) & 0xff), UInt8((word >> 8) & 0xff), UInt8(word & 0xff)]
        }
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]
}

private extension UInt32 {
    func rotateRight(_ count: UInt32) -> UInt32 {
        (self >> count) | (self << (32 - count))
    }
}
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter 'IrockProtocolsTests/testProtocolAddressEncoderBuildsDomainIPv4AndIPv6Frames|IrockProtocolsTests/testProtocolAddressEncoderRejectsInvalidInputs|IrockProtocolsTests/testSHA224MatchesTrojanPasswordVector'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Add protocol address and SHA224 helpers"
```

---

### Task 2: Replace Trojan foundation payload with Trojan request prefix

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Replace Trojan opener tests with wire bytes**

Update `testTrojanOpenRequestBuildsCredentialSafeMetadataAndPayload()` assertions:

```swift
let expectedHash = Data("869ce74cceadfb55774ed4ff96cdb65be71412e3d669878bec160955\r\n".utf8)
let expectedAddress = Data([0x01, 0x03, 0x09]) + Data("apple.com".utf8) + Data([0x01, 0xbb, 0x0d, 0x0a])
XCTAssertEqual(request.openBytes, expectedHash + expectedAddress)
XCTAssertFalse(String(data: request.openBytes, encoding: .utf8)?.contains("trojan-foundation") == true)
```

Update `testTrojanProxyAdapterOpensTCPTransportAndReturnsProxyConnection()` payload assertion:

```swift
let payload = transport.requests.first?.initialPayload ?? Data()
XCTAssertTrue(payload.starts(with: Data("869ce74cceadfb55774ed4ff96cdb65be71412e3d669878bec160955\r\n".utf8)))
XCTAssertFalse(String(data: payload, encoding: .utf8)?.contains("trojan-foundation") == true)
XCTAssertFalse(payload.contains(Data("secret-password".utf8)))
```

- [ ] **Step 2: Run Trojan tests and verify failure**

```bash
swift test --filter 'IrockProtocolsTests/testTrojanOpenRequestBuildsCredentialSafeMetadataAndPayload|IrockProtocolsTests/testTrojanProxyAdapterOpensTCPTransportAndReturnsProxyConnection'
```

Expected: FAIL because implementation still emits `trojan-foundation`.

- [ ] **Step 3: Implement Trojan request prefix**

Replace `TrojanOpenRequest.init` openBytes assignment:

```swift
let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04)
self.destinationDescription = frame.description
self.serverName = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
var bytes = Data(SHA224.hashHex(password.trimmingCharacters(in: .whitespacesAndNewlines)).utf8)
bytes.append(Data([0x0d, 0x0a, 0x01]))
bytes.append(frame.bytes)
bytes.append(Data([0x0d, 0x0a]))
self.openBytes = bytes
```

- [ ] **Step 4: Run focused Trojan tests**

```bash
swift test --filter 'IrockProtocolsTests/testTrojanOpenRequestBuildsCredentialSafeMetadataAndPayload|IrockProtocolsTests/testTrojanProxyAdapterOpensTCPTransportAndReturnsProxyConnection|IrockProtocolsTests/testTrojanProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Implement Trojan request prefix"
```

---

### Task 3: Replace VLESS foundation payload with VLESS request header

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Update VLESS tests to assert header bytes**

Update `testVLESSOpenRequestBuildsCredentialSafeMetadataAndPayload()`:

```swift
let expected = Data([0x00])
    + Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2])
    + Data([0x00, 0x01, 0x01, 0xbb, 0x02, 0x09])
    + Data("apple.com".utf8)
XCTAssertEqual(request.openBytes, expected)
XCTAssertFalse(String(data: request.openBytes, encoding: .utf8)?.contains("vless-foundation") == true)
```

Add rejection test:

```swift
func testVLESSOpenRequestRejectsUnsupportedSecurityAndFlow() {
    XCTAssertThrowsError(try VLESSOpenRequest(userID: "00000000-0000-0000-0000-000000000002", destination: .host("apple.com", port: 443), security: "aes-128-gcm")) { error in
        XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("unsupported vless security"))
    }
    XCTAssertThrowsError(try VLESSOpenRequest(userID: "00000000-0000-0000-0000-000000000002", destination: .host("apple.com", port: 443), flow: "xtls-rprx-vision")) { error in
        XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("unsupported vless flow"))
    }
}
```

- [ ] **Step 2: Run VLESS tests and verify failure**

```bash
swift test --filter 'IrockProtocolsTests/testVLESSOpenRequestBuildsCredentialSafeMetadataAndPayload|IrockProtocolsTests/testVLESSOpenRequestRejectsUnsupportedSecurityAndFlow|IrockProtocolsTests/testVLESSProxyAdapterOpensTCPTransportAndReturnsProxyConnection'
```

Expected: FAIL because implementation still emits `vless-foundation` and accepts unsupported security/flow.

- [ ] **Step 3: Implement VLESS header**

Replace `VLESSOpenRequest.init` body after UUID/security validation with:

```swift
let uuid = try Self.uuidBytes(normalizedUserID)
let normalizedFlow = flow.trimmingCharacters(in: .whitespacesAndNewlines)
guard normalizedSecurity == "none" else {
    throw ProxyProtocolError.invalidConfiguration("unsupported vless security")
}
guard normalizedFlow.isEmpty else {
    throw ProxyProtocolError.invalidConfiguration("unsupported vless flow")
}
let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x02, ipv4Type: 0x01, ipv6Type: 0x03)
self.destinationDescription = frame.description
self.security = normalizedSecurity
self.flow = normalizedFlow
var bytes = Data([0x00])
bytes.append(contentsOf: uuid)
bytes.append(0x00)
bytes.append(0x01)
bytes.append(frame.bytes.suffix(2))
bytes.append(frame.bytes.prefix(frame.bytes.count - 2))
self.openBytes = bytes
```

Add helper in `VLESSOpenRequest`:

```swift
private static func uuidBytes(_ value: String) throws -> [UInt8] {
    guard let uuid = UUID(uuidString: value) else {
        throw ProxyProtocolError.invalidConfiguration("invalid vless user id")
    }
    let tuple = uuid.uuid
    return [tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7, tuple.8, tuple.9, tuple.10, tuple.11, tuple.12, tuple.13, tuple.14, tuple.15]
}
```

- [ ] **Step 4: Run focused VLESS tests**

```bash
swift test --filter 'IrockProtocolsTests/testVLESSOpenRequestBuildsCredentialSafeMetadataAndPayload|IrockProtocolsTests/testVLESSOpenRequestRejectsInvalidUserID|IrockProtocolsTests/testVLESSOpenRequestRejectsUnsupportedSecurityAndFlow|IrockProtocolsTests/testVLESSProxyAdapterOpensTCPTransportAndReturnsProxyConnection|IrockProtocolsTests/testVLESSProxyAdapterOpensRealityTCPTransportWithCredentialSafePayload'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Implement VLESS request header"
```

---

### Task 4: Replace VMess foundation payload with deterministic local VMess header

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Update VMess tests to assert local binary header**

Update `testVMessOpenRequestBuildsStableMetadataAndPayload()`:

```swift
XCTAssertEqual(request.openBytes.prefix(5), Data([0x01, 0x01, 0x00, 0x01, 0xbb]))
XCTAssertTrue(request.openBytes.contains(Data("apple.com".utf8)))
XCTAssertFalse(String(data: request.openBytes, encoding: .utf8)?.contains("vmess-foundation") == true)
XCTAssertFalse(request.openBytes.contains(Data("00000000-0000-0000-0000-000000000001".utf8)))
```

Add security rejection:

```swift
func testVMessOpenRequestRejectsUnsupportedSecurity() {
    XCTAssertThrowsError(try VMessOpenRequest(userID: "00000000-0000-0000-0000-000000000001", destination: .host("apple.com", port: 443), security: "rc4-md5")) { error in
        XCTAssertEqual(error as? ProxyProtocolError, .invalidConfiguration("unsupported vmess security"))
    }
}
```

- [ ] **Step 2: Run VMess tests and verify failure**

```bash
swift test --filter 'IrockProtocolsTests/testVMessOpenRequestBuildsStableMetadataAndPayload|IrockProtocolsTests/testVMessOpenRequestRejectsUnsupportedSecurity|IrockProtocolsTests/testVMessProxyAdapterOpensTCPTransportAndReturnsProxyConnection'
```

Expected: FAIL because implementation still emits `vmess-foundation` and accepts any non-empty security.

- [ ] **Step 3: Implement deterministic local VMess-shaped header**

Replace `VMessOpenRequest.init` openBytes assignment with a local binary header:

```swift
let allowedSecurity = ["auto", "none", "aes-128-gcm", "chacha20-poly1305"]
guard allowedSecurity.contains(normalizedSecurity) else {
    throw ProxyProtocolError.invalidConfiguration("unsupported vmess security")
}
let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x02, ipv4Type: 0x01, ipv6Type: 0x03)
let securityCode: UInt8
switch normalizedSecurity {
case "none": securityCode = 0x05
case "aes-128-gcm": securityCode = 0x03
case "chacha20-poly1305": securityCode = 0x04
default: securityCode = 0x00
}
self.destinationDescription = frame.description
self.security = normalizedSecurity
self.alterID = alterID
var bytes = Data([0x01, 0x01, UInt8(min(alterID, 255)), securityCode])
bytes.append(frame.bytes.suffix(2))
bytes.append(frame.bytes.prefix(frame.bytes.count - 2))
self.openBytes = bytes
```

This is intentionally named and tested as a deterministic local VMess-shaped header, not complete VMess AEAD interop.

- [ ] **Step 4: Run focused VMess tests**

```bash
swift test --filter 'IrockProtocolsTests/testVMessOpenRequestBuildsStableMetadataAndPayload|IrockProtocolsTests/testVMessOpenRequestRejectsInvalidUserID|IrockProtocolsTests/testVMessOpenRequestRejectsUnsupportedSecurity|IrockProtocolsTests/testVMessProxyAdapterOpensTCPTransportAndReturnsProxyConnection|IrockProtocolsTests/testVMessProxyAdapterRejectsInvalidConfigurationBeforeTransportOpen'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Implement local VMess request header"
```

---

### Task 5: Replace Hysteria2 and TUIC markers with binary QUIC descriptors

**Files:**
- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`

- [ ] **Step 1: Update Hysteria2/TUIC tests**

Use this expected Hysteria2 prefix in `testHysteria2OpenRequestBuildsCredentialSafeMetadataAndPayload()`:

```swift
XCTAssertEqual(request.openBytes.prefix(5), Data([0x48, 0x59, 0x32, 0x01, 0x01]))
XCTAssertTrue(request.openBytes.contains(Data("hysteria.example.com".utf8)))
XCTAssertFalse(String(data: request.openBytes, encoding: .utf8)?.contains("hysteria2-foundation") == true)
```

Use this expected TUIC prefix in `testTUICOpenRequestBuildsCredentialSafeMetadataAndPayload()`:

```swift
XCTAssertEqual(request.openBytes.prefix(5), Data([0x54, 0x55, 0x49, 0x43, 0x05]))
XCTAssertTrue(request.openBytes.contains(Data("tuic.example.com".utf8)))
XCTAssertFalse(String(data: request.openBytes, encoding: .utf8)?.contains("tuic-foundation") == true)
```

Update adapter payload assertions to check prefixes and absence of marker strings.

- [ ] **Step 2: Run Hysteria2/TUIC tests and verify failure**

```bash
swift test --filter 'IrockProtocolsTests/testHysteria2OpenRequestBuildsCredentialSafeMetadataAndPayload|IrockProtocolsTests/testTUICOpenRequestBuildsCredentialSafeMetadataAndPayload|IrockProtocolsTests/testHysteria2ProxyAdapterOpensQUICTransportAndReturnsProxyConnection|IrockProtocolsTests/testTUICProxyAdapterOpensQUICTransportAndReturnsProxyConnection'
```

Expected: FAIL because marker payloads are still emitted.

- [ ] **Step 3: Implement binary descriptors**

For Hysteria2, replace openBytes assignment with:

```swift
let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04)
let trimmedSNI = sni.trimmingCharacters(in: .whitespacesAndNewlines)
self.destinationDescription = frame.description
self.sni = trimmedSNI
self.obfuscationPresent = obfuscation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
var bytes = Data([0x48, 0x59, 0x32, 0x01, obfuscationPresent ? 0x01 : 0x00, UInt8(trimmedSNI.utf8.count)])
bytes.append(Data(trimmedSNI.utf8))
bytes.append(frame.bytes)
self.openBytes = bytes
```

For TUIC, replace openBytes assignment with:

```swift
let uuid = try Self.uuidBytes(String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines))
let frame = try ProtocolAddressFrame(destination: destination, domainType: 0x03, ipv4Type: 0x01, ipv6Type: 0x04)
let trimmedSNI = sni.trimmingCharacters(in: .whitespacesAndNewlines)
self.destinationDescription = frame.description
self.sni = trimmedSNI
var bytes = Data([0x54, 0x55, 0x49, 0x43, 0x05])
bytes.append(contentsOf: uuid)
bytes.append(UInt8(trimmedSNI.utf8.count))
bytes.append(Data(trimmedSNI.utf8))
bytes.append(frame.bytes)
self.openBytes = bytes
```

Add the same UUID tuple helper used by VLESS to `TUICOpenRequest`.

- [ ] **Step 4: Run focused QUIC protocol tests**

```bash
swift test --filter 'IrockProtocolsTests/testHysteria2OpenRequestBuildsCredentialSafeMetadataAndPayload|IrockProtocolsTests/testHysteria2OpenRequestRejectsEmptyAuthenticationSecret|IrockProtocolsTests/testTUICOpenRequestBuildsCredentialSafeMetadataAndPayload|IrockProtocolsTests/testTUICOpenRequestRejectsInvalidCredentials|IrockProtocolsTests/testHysteria2ProxyAdapterOpensQUICTransportAndReturnsProxyConnection|IrockProtocolsTests/testTUICProxyAdapterOpensQUICTransportAndReturnsProxyConnection'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift
git commit -m "Implement QUIC protocol descriptors"
```

---

### Task 6: Replace WebSocket marker with RFC6455 upgrade request

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Update WebSocket tests**

Update `testWebSocketTransportAdapterOpensUnderlyingTCPWithMetadataAndPayload()` payload assertion:

```swift
let payload = String(data: underlying.requests.first?.initialPayload ?? Data(), encoding: .utf8) ?? ""
XCTAssertTrue(payload.hasPrefix("GET /proxy HTTP/1.1\r\n"))
XCTAssertTrue(payload.contains("Host: example.com\r\n"))
XCTAssertTrue(payload.contains("Upgrade: websocket\r\n"))
XCTAssertTrue(payload.contains("Connection: Upgrade\r\n"))
XCTAssertTrue(payload.contains("Sec-WebSocket-Version: 13\r\n"))
XCTAssertTrue(payload.contains("Sec-WebSocket-Protocol: vmess\r\n"))
XCTAssertTrue(payload.contains("\r\n\r\nprotocol-open"))
XCTAssertFalse(payload.contains("websocket-foundation"))
```

Update default test to assert `GET / HTTP/1.1` and no protocol header.

- [ ] **Step 2: Run WebSocket tests and verify failure**

```bash
swift test --filter 'IrockTransportTests/testWebSocketTransportAdapterOpensUnderlyingTCPWithMetadataAndPayload|IrockTransportTests/testWebSocketTransportAdapterDefaultsPathAndHostMetadata'
```

Expected: FAIL because implementation still emits `websocket-foundation`.

- [ ] **Step 3: Implement upgrade request builder**

Replace `WebSocketOpenDescriptor.initialPayload`:

```swift
func initialPayload(appending payload: Data?) -> Data {
    var request = "GET \(path) HTTP/1.1\r\n"
    request += "Host: \(hostHeader)\r\n"
    request += "Upgrade: websocket\r\n"
    request += "Connection: Upgrade\r\n"
    request += "Sec-WebSocket-Version: 13\r\n"
    request += "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n"
    if !protocolName.isEmpty {
        request += "Sec-WebSocket-Protocol: \(protocolName)\r\n"
    }
    request += "\r\n"
    var data = Data(request.utf8)
    if let payload {
        data.append(payload)
    }
    return data
}
```

- [ ] **Step 4: Run WebSocket tests**

```bash
swift test --filter 'IrockTransportTests/testWebSocketTransportAdapterOpensUnderlyingTCPWithMetadataAndPayload|IrockTransportTests/testWebSocketTransportAdapterDefaultsPathAndHostMetadata|IrockTransportTests/testWebSocketTransportAdapterRejectsInvalidConfigurationBeforeOpeningUnderlying'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "Implement WebSocket upgrade prelude"
```

---

### Task 7: Replace HTTP/2 and gRPC markers with local wire-format preludes

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Update HTTP/2 and gRPC tests**

For HTTP/2 payload assertions:

```swift
let opened = underlying.requests.first?.initialPayload ?? Data()
XCTAssertTrue(opened.starts(with: Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))
XCTAssertTrue(opened.contains(Data("http2-path:/proxy\n".utf8)))
XCTAssertTrue(opened.contains(Data("http2-authority:example.com\n".utf8)))
XCTAssertTrue(opened.contains(Data("\nprotocol-open".utf8)))
XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("http2-foundation") == true)
```

For gRPC payload assertions:

```swift
let opened = underlying.requests.first?.initialPayload ?? Data()
XCTAssertTrue(opened.starts(with: Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)))
XCTAssertTrue(opened.contains(Data("grpc-service:/TunnelService/Connect\n".utf8)))
XCTAssertTrue(opened.contains(Data([0x00, 0x00, 0x00, 0x00, UInt8("protocol-open".utf8.count)])))
XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("grpc-foundation") == true)
```

- [ ] **Step 2: Run tests and verify failure**

```bash
swift test --filter 'IrockTransportTests/testHTTP2TransportAdapterOpensUnderlyingTCPWithMetadataAndPayload|IrockTransportTests/testGRPCTransportAdapterOpensUnderlyingTCPWithMetadataAndPayload'
```

Expected: FAIL because implementation still emits marker strings.

- [ ] **Step 3: Implement local prelude builders**

Replace `HTTP2OpenDescriptor.initialPayload`:

```swift
func initialPayload(appending payload: Data?) -> Data {
    var data = Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)
    data.append(Data("http2-authority:\(authority)\nhttp2-path:\(path)\n".utf8))
    if !protocolName.isEmpty {
        data.append(Data("http2-protocol:\(protocolName)\n".utf8))
    }
    data.append(0x0a)
    if let payload {
        data.append(payload)
    }
    return data
}
```

Replace `GRPCOpenDescriptor.initialPayload`:

```swift
func initialPayload(appending payload: Data?) -> Data {
    var data = Data("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)
    data.append(Data("grpc-authority:\(authority)\ngrpc-service:\(service)\n".utf8))
    if !protocolName.isEmpty {
        data.append(Data("grpc-protocol:\(protocolName)\n".utf8))
    }
    data.append(0x0a)
    if let payload {
        data.append(0x00)
        data.append(contentsOf: [0x00, 0x00, 0x00, UInt8(payload.count & 0xff)])
        data.append(payload)
    }
    return data
}
```

- [ ] **Step 4: Run HTTP/2 and gRPC tests**

```bash
swift test --filter 'IrockTransportTests/testHTTP2TransportAdapterOpensUnderlyingTCPWithMetadataAndPayload|IrockTransportTests/testHTTP2TransportAdapterDefaultsPathAndAuthorityMetadata|IrockTransportTests/testGRPCTransportAdapterOpensUnderlyingTCPWithMetadataAndPayload|IrockTransportTests/testGRPCTransportAdapterDefaultsServiceAndAuthorityMetadata'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "Implement HTTP2 and gRPC preludes"
```

---

### Task 8: Replace QUIC and Reality markers with binary local descriptors

**Files:**
- Modify: `packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`

- [ ] **Step 1: Update QUIC and Reality tests**

For QUIC payload:

```swift
let opened = dialer.requests.first?.initialPayload ?? Data()
XCTAssertEqual(opened.prefix(4), Data([0x51, 0x55, 0x49, 0x43]))
XCTAssertTrue(opened.contains(Data("quic.example.com".utf8)))
XCTAssertTrue(opened.contains(Data("hysteria2".utf8)))
XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("quic-foundation") == true)
```

For Reality payload:

```swift
let opened = underlying.requests.first?.initialPayload ?? Data()
XCTAssertEqual(opened.prefix(4), Data([0x52, 0x45, 0x41, 0x4c]))
XCTAssertTrue(opened.contains(Data("reality.example.com".utf8)))
XCTAssertFalse(String(data: opened, encoding: .utf8)?.contains("reality-foundation") == true)
XCTAssertFalse(opened.contains(Data("reality-public-key".utf8)))
XCTAssertFalse(opened.contains(Data("abc123".utf8)))
```

- [ ] **Step 2: Run tests and verify failure**

```bash
swift test --filter 'IrockTransportTests/testQUICTransportAdapterDialsWithMetadataAndPayload|IrockTransportTests/testRealityTransportAdapterOpensUnderlyingTCPWithCredentialSafeMetadataAndPayload'
```

Expected: FAIL because marker strings are still emitted.

- [ ] **Step 3: Implement binary descriptors**

Replace `QUICOpenDescriptor.initialPayload`:

```swift
func initialPayload(appending payload: Data?) -> Data {
    var data = Data([0x51, 0x55, 0x49, 0x43, 0x01])
    appendString(serverName, to: &data)
    appendString(protocolName, to: &data)
    appendString(alpn, to: &data)
    if let payload {
        data.append(payload)
    }
    return data
}
```

Replace `RealityOpenDescriptor.initialPayload`:

```swift
func initialPayload(appending payload: Data?) -> Data {
    var data = Data([0x52, 0x45, 0x41, 0x4c, 0x01])
    appendString(serverName, to: &data)
    data.append(shortIDPresent ? 0x01 : 0x00)
    appendString(spiderX, to: &data)
    appendString(fingerprint, to: &data)
    appendString(alpn.joined(separator: ","), to: &data)
    if let payload {
        data.append(payload)
    }
    return data
}
```

Add file-private helper near descriptor structs:

```swift
private func appendString(_ value: String, to data: inout Data) {
    let bytes = Array(value.utf8)
    data.append(UInt8(min(bytes.count, 255)))
    data.append(contentsOf: bytes.prefix(255))
}
```

- [ ] **Step 4: Run QUIC and Reality tests**

```bash
swift test --filter 'IrockTransportTests/testQUICTransportAdapterDialsWithMetadataAndPayload|IrockTransportTests/testQUICTransportAdapterDefaultsServerNameAndALPNMetadata|IrockTransportTests/testRealityTransportAdapterOpensUnderlyingTCPWithCredentialSafeMetadataAndPayload|IrockTransportTests/testRealityTransportAdapterRejectsInvalidConfigurationBeforeOpeningUnderlying'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockTransport/Sources/IrockTransport/IrockTransport.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift
git commit -m "Implement QUIC and Reality descriptors"
```

---

### Task 9: Add no-foundation regression tests and update protocol matrix coverage

**Files:**
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
- Modify: `packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift`
- Modify if needed: `packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift`

- [ ] **Step 1: Add protocol no-marker test**

Add to `IrockProtocolsTests`:

```swift
func testPlannedProtocolOpenersDoNotEmitFoundationMarkers() throws {
    let openers = [
        try VMessOpenRequest(userID: "00000000-0000-0000-0000-000000000001", destination: .host("apple.com", port: 443)).openBytes,
        try VLESSOpenRequest(userID: "00000000-0000-0000-0000-000000000002", destination: .host("apple.com", port: 443)).openBytes,
        try TrojanOpenRequest(password: "secret-password", destination: .host("apple.com", port: 443)).openBytes,
        try Hysteria2OpenRequest(authentication: "hysteria-secret", destination: .host("apple.com", port: 443)).openBytes,
        try TUICOpenRequest(credential: "00000000-0000-0000-0000-000000000003:tuic-password", destination: .host("apple.com", port: 443)).openBytes
    ]

    for bytes in openers {
        let text = String(data: bytes, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("foundation"))
    }
}
```

- [ ] **Step 2: Add transport no-marker test**

Add to `IrockTransportTests`:

```swift
func testAdvancedTransportPreludesDoNotEmitFoundationMarkers() async throws {
    let tcp = RecordingTransportAdapter(transport: .tcp)
    _ = try await WebSocketTransportAdapter(underlying: tcp).open(request: TransportRequest(host: "example.com", port: 443, transport: .webSocket))
    _ = try await HTTP2TransportAdapter(underlying: tcp).open(request: TransportRequest(host: "example.com", port: 443, transport: .http2))
    _ = try await GRPCTransportAdapter(underlying: tcp).open(request: TransportRequest(host: "example.com", port: 443, transport: .grpc))

    let quicDialer = RecordingQUICDialer()
    _ = try await QUICTransportAdapter(dialer: quicDialer).open(request: TransportRequest(host: "example.com", port: 443, transport: .quic))

    let reality = RealityOptions(publicKey: "public", shortID: "abc123", spiderX: "/")
    let tls = TLSOptions(enabled: true, serverName: "example.com", allowInsecure: false, alpn: ["h2"], fingerprint: "chrome", reality: reality)
    _ = try await RealityTransportAdapter(underlying: tcp).open(request: TransportRequest(host: "example.com", port: 443, transport: .tcp, tls: tls))

    let payloads = tcp.requests.compactMap(\.initialPayload) + quicDialer.requests.compactMap(\.initialPayload)
    for payload in payloads {
        let text = String(data: payload, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("foundation"))
    }
}
```

- [ ] **Step 3: Run regression tests and verify they pass**

```bash
swift test --filter 'IrockProtocolsTests/testPlannedProtocolOpenersDoNotEmitFoundationMarkers|IrockTransportTests/testAdvancedTransportPreludesDoNotEmitFoundationMarkers'
```

Expected: PASS.

- [ ] **Step 4: Run full test suite**

```bash
swift test
```

Expected: PASS with all tests.

- [ ] **Step 5: Commit**

```bash
git add packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift packages/IrockTransport/Tests/IrockTransportTests/IrockTransportTests.swift packages/IrockAppFeature/Tests/IrockAppFeatureTests/URIImportTests.swift
git commit -m "Cover protocol completion matrix"
```

---

### Task 10: Verify, review, push, merge, and clean git state

**Files:**
- No source files expected beyond previous tasks.

- [ ] **Step 1: Run final verification**

```bash
swift test
```

Expected: PASS.

If app or scaffold files changed unexpectedly, also run:

```bash
./scripts/build-unsigned-app.sh
```

Expected: unsigned app build succeeds.

- [ ] **Step 2: Search for remaining foundation protocol markers in source and tests**

```bash
grep -R "foundation:" packages/IrockProtocols packages/IrockTransport packages/IrockAppFeature || true
grep -R "-foundation" packages/IrockProtocols packages/IrockTransport packages/IrockAppFeature || true
```

Expected: no protocol/transport opener marker assertions remain. Historical docs may still contain foundation wording and do not block this task.

- [ ] **Step 3: Run git diff check**

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 4: Request code review**

Use an independent code-reviewer agent with this scope:

```text
Review the protocol completion branch. Focus on Swift correctness, protocol framing bugs, secret leakage, test adequacy, and whether any planned opener still emits foundation markers. Do not edit files.
```

Expected: no blocking findings. Fix any high-confidence findings in a new commit.

- [ ] **Step 5: Push branch and merge after verification**

```bash
git push -u origin feat/protocol-completion
gh pr create --title "Complete local protocol wire formats" --body "$(cat <<'EOF'
## Summary
- Replace protocol foundation marker payloads with local wire-format builders.
- Replace advanced transport marker preludes with deterministic local request/prelude bytes.
- Add regression coverage that planned protocol openers no longer emit foundation markers.

## Test plan
- [x] swift test
- [x] git diff --check
EOF
)"
gh pr merge --squash --delete-branch
```

Expected: PR is merged to `main` and remote branch deleted.

- [ ] **Step 6: Clean local git state**

```bash
git switch main
git pull --ff-only
git branch --delete feat/protocol-completion
git status --short --branch
```

Expected: on `main`, up to date with `origin/main`, clean working tree.
