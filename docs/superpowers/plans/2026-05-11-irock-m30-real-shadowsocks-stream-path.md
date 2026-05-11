# M30 Real Shadowsocks Stream Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development while implementing this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic, testable Shadowsocks Alpha AEAD TCP stream-open path for `aes-256-gcm` behind the existing proxy/transport seams.

**Architecture:** Keep platform networking in transport/platform layers and add protocol framing in `IrockProtocols`. `ShadowsocksProxyAdapter` will build salt + encrypted length/payload stream-open metadata before delegating to the existing `TransportAdapterRegistry`.

**Tech Stack:** Swift 5.10, SwiftPM, XCTest, Foundation/CryptoKit from shared packages.

---

## Files

- Modify: `packages/IrockProtocols/Sources/IrockProtocols/IrockProtocols.swift`
- Modify: `packages/IrockProtocols/Tests/IrockProtocolsTests/IrockProtocolsTests.swift`
- Create/Update: `docs/superpowers/specs/2026-05-11-irock-m30-real-shadowsocks-stream-path-design.md`
- Create/Update: `docs/superpowers/plans/2026-05-11-irock-m30-real-shadowsocks-stream-path.md`

## Task 1: Shadowsocks stream request contract

- [x] **Step 1: Write failing tests**

Add tests in `IrockProtocolsTests` that call `ShadowsocksStreamRequest` directly and assert:

```swift
let request = try ShadowsocksStreamRequest(
    credential: "aes-256-gcm:pass",
    destination: .host("apple.com", port: 443),
    salt: Data(repeating: 1, count: 32)
)
XCTAssertEqual(request.cipher, "aes-256-gcm")
XCTAssertEqual(request.metadata["shadowsocksCipher"], "aes-256-gcm")
XCTAssertEqual(request.addressFrameHex, "03096170706c652e636f6d01bb")
XCTAssertEqual(request.openBytes.count, 79)
```

- [x] **Step 2: Verify red**

Run: `swift test --filter IrockProtocolsTests/testShadowsocksStreamRequestBuildsAES256GCMHostOpenBytes`

Expected: FAIL because `ShadowsocksStreamRequest` does not exist.

- [x] **Step 3: Implement minimal stream request**

Add `ShadowsocksStreamRequest` with credential parsing, address-frame encoding, deterministic open bytes, and metadata.

- [x] **Step 4: Verify green**

Run: `swift test --filter IrockProtocolsTests/testShadowsocksStreamRequestBuildsAES256GCMHostOpenBytes`

Expected: PASS.

## Task 2: Destination variants and validation

- [x] **Step 1: Write failing tests**

Add tests for IPv4 frame marker `01`, IPv6 frame marker `04`, unsupported method rejection, and invalid credential rejection.

- [x] **Step 2: Verify red**

Run: `swift test --filter IrockProtocolsTests/ShadowsocksStreamRequest`

Expected: FAIL for unsupported validation/destination coverage until implementation is complete.

- [x] **Step 3: Implement validation coverage**

Complete strict parsing for `method:password`, destination host/port validation, IPv4/IPv6 byte parsing, and nonce count validation.

- [x] **Step 4: Verify green**

Run: `swift test --filter IrockProtocolsTests/ShadowsocksStreamRequest`

Expected: PASS.

## Task 3: Adapter metadata integration

- [x] **Step 1: Write failing adapter test**

Update `testShadowsocksProxyAdapterOpensTCPTransportAndReturnsProxyConnection` to use credential `aes-256-gcm:pass` and assert metadata includes `shadowsocksCipher`, `shadowsocksAddressFrameHex`, and `shadowsocksStreamOpenHex`.

- [x] **Step 2: Verify red**

Run: `swift test --filter IrockProtocolsTests/testShadowsocksProxyAdapterOpensTCPTransportAndReturnsProxyConnection`

Expected: FAIL because adapter does not add Shadowsocks stream metadata yet.

- [x] **Step 3: Wire adapter**

Make `ShadowsocksProxyAdapter.connect(request:)` build a stream request before transport open and merge stream metadata into `TransportRequest.metadata`.

- [x] **Step 4: Verify green**

Run: `swift test --filter IrockProtocolsTests/testShadowsocksProxyAdapterOpensTCPTransportAndReturnsProxyConnection`

Expected: PASS.

## Task 4: Full verification

- [x] Run `swift test --filter IrockProtocolsTests` and expect PASS.
- [x] Run `swift test` and expect PASS.
- [x] Run `xcodebuild -project apps/irock-iOS/irock.xcodeproj -scheme irockApp -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` and expect BUILD SUCCEEDED.
- [x] Run a platform import scan over `packages` and expect no `Network`, `NetworkExtension`, `UIKit`, `AppKit`, or `Security` imports.
- [x] Update this plan with execution status.
