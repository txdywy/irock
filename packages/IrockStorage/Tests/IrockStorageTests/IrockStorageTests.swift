import XCTest
import IrockCore
@testable import IrockStorage

final class IrockStorageTests: XCTestCase {
    func testSnapshotStoreRoundTripsRuntimeSnapshotInMemory() throws {
        let node = ProxyNode(
            id: NodeID(rawValue: "node-1"),
            name: "Demo SS",
            protocolType: .shadowsocks,
            serverHost: "127.0.0.1",
            serverPort: 8388,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: "node-1"),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
        let snapshot = RuntimeSnapshot(id: SnapshotID(rawValue: "snapshot-1"), selectedNode: node, routeMode: .globalProxy, logLevel: .user)
        let store = InMemoryRuntimeSnapshotStore()

        XCTAssertNil(try store.load())

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
    }
}
