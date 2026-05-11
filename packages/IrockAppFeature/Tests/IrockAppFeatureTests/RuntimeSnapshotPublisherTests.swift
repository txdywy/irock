import XCTest
import IrockCore
import IrockStorage
@testable import IrockAppFeature

final class RuntimeSnapshotPublisherTests: XCTestCase {
    func testPublisherSavesSnapshotAndReturnsPublishedID() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)
        let node = makeNode(id: "node-1", name: "Demo")

        let result = publisher.publish(selectedNode: node, routeMode: .globalProxy, logLevel: .user)

        guard case let .published(snapshotID) = result else {
            return XCTFail("Expected published result")
        }
        XCTAssertTrue(snapshotID.rawValue.hasPrefix("snapshot-"))
        XCTAssertEqual(try store.load()?.selectedNode, node)
    }

    func testPublisherReturnsMissingSelectedNodeWithoutSaving() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)

        let result = publisher.publish(selectedNode: nil, routeMode: .ruleBased, logLevel: .user)

        XCTAssertEqual(result, .missingSelectedNode)
        XCTAssertNil(try store.load())
    }

    func testPublisherWritesRouteModeAndLogLevelIntoSnapshot() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)

        _ = publisher.publish(selectedNode: makeNode(id: "node-1", name: "Demo"), routeMode: .direct, logLevel: .debug)

        let snapshot = try XCTUnwrap(store.load())
        XCTAssertEqual(snapshot.routeMode, .direct)
        XCTAssertEqual(snapshot.logLevel, .debug)
    }

    func testPublisherReturnsStorageFailedWhenStoreThrows() {
        let publisher = RuntimeSnapshotPublisher(store: FailingRuntimeSnapshotStore())

        let result = publisher.publish(selectedNode: makeNode(id: "node-1", name: "Demo"), routeMode: .ruleBased, logLevel: .user)

        guard case let .storageFailed(message) = result else {
            return XCTFail("Expected storageFailed result")
        }
        XCTAssertEqual(message, "Runtime snapshot publish failed")
        XCTAssertFalse(message.contains("write failed"))
    }

    func testPublisherSavesRoutingRuleManifest() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)
        let manifest = RuntimeRoutingRuleManifest(
            version: 1,
            rules: [RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct)]
        )

        _ = publisher.publish(
            selectedNode: makeNode(id: "node-1", name: "Demo"),
            routeMode: .ruleBased,
            logLevel: .user,
            routingRuleManifest: manifest
        )

        XCTAssertEqual(try store.load()?.routingRuleManifest, manifest)
    }

    func testPublisherDefaultsToEmptyRoutingRuleManifest() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let publisher = RuntimeSnapshotPublisher(store: store)

        _ = publisher.publish(selectedNode: makeNode(id: "node-1", name: "Demo"), routeMode: .ruleBased, logLevel: .user)

        XCTAssertEqual(try store.load()?.routingRuleManifest, .empty)
    }

    private func makeNode(id: String, name: String) -> ProxyNode {
        ProxyNode(
            id: NodeID(rawValue: id),
            name: name,
            protocolType: .trojan,
            serverHost: "example.com",
            serverPort: 443,
            credentialReference: CredentialReference(keychainService: "com.irock.nodes", account: id),
            transport: .tcp,
            tls: .disabled,
            udpPolicy: .disabled
        )
    }
}

private struct FailingRuntimeSnapshotStore: RuntimeSnapshotStore {
    func save(_ snapshot: RuntimeSnapshot) throws {
        throw FailingStoreError.writeFailed
    }

    func load() throws -> RuntimeSnapshot? {
        nil
    }
}

private enum FailingStoreError: Error, CustomStringConvertible {
    case writeFailed

    var description: String {
        "write failed"
    }
}
