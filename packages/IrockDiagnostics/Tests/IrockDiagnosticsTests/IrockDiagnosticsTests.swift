import XCTest
import IrockCore
import IrockProtocols
import IrockRouting
import IrockTransport
@testable import IrockDiagnostics

final class IrockDiagnosticsTests: XCTestCase {
    func testRingLogKeepsNewestEntries() {
        var log = RingConnectionLog(capacity: 2)
        log.append(ConnectionLogEntry(message: "first"))
        log.append(ConnectionLogEntry(message: "second"))
        log.append(ConnectionLogEntry(message: "third"))

        XCTAssertEqual(log.entries.map(\.message), ["second", "third"])
    }

    func testDiagnosticTaxonomyMapsProtocolTransportRoutingAndRuntimeFailuresSafely() {
        let diagnostics: [(UserFacingDiagnostic, String)] = [
            (.protocolFailure(.authenticationFailed("password token leaked")), "Proxy adapter failed: Authentication failed"),
            (.transportFailure(.tcpConnectFailed("secret host refused")), "Transport failed: TCP connect failed"),
            (.routingFailure(.unsupportedAction(line: 7, action: "SECRET_TOKEN")), "Routing rules invalid at line 7: unsupported action"),
            (.runtimeStoreUnavailable, "Runtime store unavailable"),
            (.runtimeSnapshotUnavailable, "Runtime snapshot unavailable"),
            (.packetBatchFailed, "Packet batch failed"),
            (.statusLoadFailed, "Runtime status unavailable"),
            (.logLoadFailed, "Runtime logs unavailable"),
            (.snapshotPublishFailed, "Runtime snapshot publish failed")
        ]

        for (diagnostic, message) in diagnostics {
            let actualMessage = UserFacingDiagnostics.message(for: diagnostic)

            XCTAssertEqual(actualMessage, message)
            XCTAssertFalse(actualMessage.contains("password"))
            XCTAssertFalse(actualMessage.contains("token"))
            XCTAssertFalse(actualMessage.contains("secret"))
            XCTAssertFalse(actualMessage.contains("SECRET_TOKEN"))
        }
    }
}
