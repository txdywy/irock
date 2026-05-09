import XCTest
@testable import IrockDiagnostics

final class IrockDiagnosticsTests: XCTestCase {
    func testRingLogKeepsNewestEntries() {
        var log = RingConnectionLog(capacity: 2)
        log.append(ConnectionLogEntry(message: "first"))
        log.append(ConnectionLogEntry(message: "second"))
        log.append(ConnectionLogEntry(message: "third"))

        XCTAssertEqual(log.entries.map(\.message), ["second", "third"])
    }
}
