import XCTest
import IrockCore
import IrockStorage
@testable import IrockTunnelCore

final class TunnelRuntimeReporterTests: XCTestCase {
    func testReporterPublishesStatus() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let status = RuntimeConnectionStatus(
            phase: .connected,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_020),
            message: "Connected"
        )

        try reporter.publishStatus(status)

        XCTAssertEqual(try statusStore.load(), status)
    }

    func testReporterAppendsLogEntry() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let reporter = TunnelRuntimeReporter(statusStore: statusStore, logStore: logStore)
        let entry = RuntimeLogEntry(
            id: "log-1",
            timestamp: Date(timeIntervalSince1970: 1_715_000_021),
            level: .user,
            message: "Connected",
            nodeID: NodeID(rawValue: "node-1"),
            phase: .connected
        )

        try reporter.appendLog(entry)

        XCTAssertEqual(try logStore.loadRecent(), [entry])
    }
}
