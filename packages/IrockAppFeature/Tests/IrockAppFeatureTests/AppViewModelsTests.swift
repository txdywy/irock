import XCTest
import IrockCore
import IrockStorage
@testable import IrockAppFeature

final class AppViewModelsTests: XCTestCase {
    @MainActor
    func testAppViewModelSelectsNode() {
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node])

        model.selectNode(id: NodeID(rawValue: "node-1"))

        XCTAssertEqual(model.nodeListState.selectedNodeID?.rawValue, "node-1")
        XCTAssertEqual(model.overviewState.selectedNode?.name, "Demo")
    }

    @MainActor
    func testAppViewModelImportsAndSelectsShadowsocksURI() throws {
        let model = AppViewModel(nodes: [])

        let node = try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        XCTAssertEqual(node.name, "Demo")
        XCTAssertEqual(node.protocolType, .shadowsocks)
        XCTAssertEqual(node.serverHost, "example.com")
        XCTAssertEqual(model.nodeListState.nodes, [node])
        XCTAssertEqual(model.nodeListState.selectedNodeID, node.id)
        XCTAssertEqual(model.overviewState.selectedNode, node)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("节点已导入：Demo"))
    }

    @MainActor
    func testAppViewModelImportsGenericProtocolURI() throws {
        let model = AppViewModel(nodes: [])

        let node = try model.importURI("trojan://secret-password@trojan.example.com:443?type=grpc&serviceName=%2FService%2FTun#Trojan")

        XCTAssertEqual(node.name, "Trojan")
        XCTAssertEqual(node.protocolType, .trojan)
        XCTAssertEqual(node.transport, .grpc)
        XCTAssertEqual(node.transportOptions.grpc?.service, "/Service/Tun")
        XCTAssertEqual(model.nodeListState.nodes, [node])
        XCTAssertEqual(model.nodeListState.selectedNodeID, node.id)
    }

    @MainActor
    func testAppViewModelStartsLocalProxyForImportedNode() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let controller = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: controller)
        let node = try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        let result = try model.startLocalProxyMode()

        XCTAssertEqual(result, endpoint)
        XCTAssertEqual(controller.startedNode, node)
        XCTAssertEqual(controller.startedCredential, "aes-256-gcm:pass")
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.localProxyState.endpoint, endpoint)
        XCTAssertEqual(model.localProxyState.endpoint?.socksAddress, "127.0.0.1:10808")
        XCTAssertEqual(model.localProxyState.endpoint?.httpAddress, "127.0.0.1:10809")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("本地代理已启动：SOCKS 127.0.0.1:10808，HTTP 127.0.0.1:10809"))
    }

    @MainActor
    func testAppViewModelConnectPublishesSnapshotAndStartsLocalProxyFallback() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let controller = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], runtimeSnapshotStore: store, localProxyController: controller)
        let node = try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(try store.load()?.selectedNode.id, node.id)
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("连接已就绪：SOCKS 127.0.0.1:10808，HTTP 127.0.0.1:10809"))
    }

    @MainActor
    func testAppViewModelStartsHysteria2LocalProxy() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy)
        let realm = "realm://public-token@realm.hy2.io/demo-realm?stun=stun1.example.com:3478&lport=43210"
        let node = try model.importURI("hysteria2://example-password@hy2.example.com:19991/?insecure=1&pinSHA256=example-pin&sni=hy2.example.com&realm=\(realm.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)#HY2")

        let startedEndpoint = try model.startLocalProxyMode()

        XCTAssertEqual(startedEndpoint, endpoint)
        XCTAssertEqual(localProxy.startedNode, node)
        XCTAssertEqual(localProxy.startedCredential, "example-password")
        XCTAssertEqual(localProxy.startedRealmCredential, "public-token")
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.localProxyState.endpoint, endpoint)
        XCTAssertEqual(model.localProxyState.message, "本地代理已启动：SOCKS 127.0.0.1:10808，HTTP 127.0.0.1:10809")
    }

    @MainActor
    func testAppViewModelConnectStartsHysteria2LocalProxyWithoutStartingUserModeTun() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let tunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let tun = RecordingUserModeTunController(endpoint: tunEndpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy, userModeTunController: tun)
        let node = try model.importURI("hysteria2://example-password@hy2.example.com:19991/?insecure=1&pinSHA256=example-pin&sni=hy2.example.com#HY2")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(localProxy.startedNode, node)
        XCTAssertEqual(localProxy.startedCredential, "example-password")
        XCTAssertNil(tun.startedNode)
        XCTAssertNil(tun.startedCredential)
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.localProxyState.endpoint, endpoint)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
    }

    @MainActor
    func testAppViewModelConnectStartsTrojanTCPLocalProxyWithoutStartingUserModeTun() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let tunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let tun = RecordingUserModeTunController(endpoint: tunEndpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy, userModeTunController: tun)
        let node = try model.importURI("trojan://secret-password@trojan.example.com:443?sni=trojan.example.com#Trojan")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(localProxy.startedNode, node)
        XCTAssertEqual(localProxy.startedCredential, "secret-password")
        XCTAssertNil(localProxy.startedRealmCredential)
        XCTAssertNil(tun.startedNode)
        XCTAssertNil(tun.startedCredential)
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.localProxyState.endpoint, endpoint)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
    }

    @MainActor
    func testAppViewModelConnectStartsVLESSTCPLocalProxyWithoutStartingUserModeTun() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let tunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let tun = RecordingUserModeTunController(endpoint: tunEndpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy, userModeTunController: tun)
        let node = try model.importURI("vless://00000000-0000-0000-0000-000000000002@vless.example.com:443?type=tcp&security=tls&sni=vless.example.com#VLESS")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(localProxy.startedNode, node)
        XCTAssertEqual(localProxy.startedCredential, "00000000-0000-0000-0000-000000000002")
        XCTAssertNil(localProxy.startedRealmCredential)
        XCTAssertNil(tun.startedNode)
        XCTAssertNil(tun.startedCredential)
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.localProxyState.endpoint, endpoint)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
    }

    @MainActor
    func testAppViewModelConnectStartsVMessTCPTLSLocalProxyWithoutStartingUserModeTun() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let tunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let tun = RecordingUserModeTunController(endpoint: tunEndpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy, userModeTunController: tun)
        let encoded = "eyJ2IjoiMiIsInBzIjoiVk1lc3MgVENQIiwiYWRkIjoidm1lc3MuZXhhbXBsZS5jb20iLCJwb3J0IjoiNDQzIiwiaWQiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJuZXQiOiJ0Y3AiLCJ0eXBlIjoibm9uZSIsInRscyI6InRscyIsInNuaSI6InZtZXNzLmV4YW1wbGUuY29tIn0"
        let node = try model.importURI("vmess://\(encoded)")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(localProxy.startedNode, node)
        XCTAssertEqual(localProxy.startedCredential, "00000000-0000-0000-0000-000000000001")
        XCTAssertNil(localProxy.startedRealmCredential)
        XCTAssertNil(tun.startedNode)
        XCTAssertNil(tun.startedCredential)
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.localProxyState.endpoint, endpoint)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
    }

    @MainActor
    func testAppViewModelConnectStartsVMessWebSocketTLSLocalProxyWithoutStartingUserModeTun() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let tunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let tun = RecordingUserModeTunController(endpoint: tunEndpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy, userModeTunController: tun)
        let encoded = "eyJ2IjoiMiIsInBzIjoiVk1lc3MgV1MiLCJhZGQiOiJ2bWVzcy5leGFtcGxlLmNvbSIsInBvcnQiOiI0NDMiLCJpZCI6IjAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMSIsIm5ldCI6IndzIiwidHlwZSI6Im5vbmUiLCJob3N0IjoiZWRnZS5leGFtcGxlLmNvbSIsInBhdGgiOiIvcmF5IiwidGxzIjoidGxzIiwic25pIjoidm1lc3MuZXhhbXBsZS5jb20ifQ"
        let node = try model.importURI("vmess://\(encoded)")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(localProxy.startedNode, node)
        XCTAssertEqual(localProxy.startedCredential, "00000000-0000-0000-0000-000000000001")
        XCTAssertNil(tun.startedNode)
        XCTAssertNil(tun.startedCredential)
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
    }

    @MainActor
    func testAppViewModelConnectStartsVMessHTTP2TLSLocalProxyWithoutStartingUserModeTun() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let tunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let tun = RecordingUserModeTunController(endpoint: tunEndpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy, userModeTunController: tun)
        let json = """
        {"v":"2","ps":"VMess H2","add":"vmess.example.com","port":"443","id":"00000000-0000-0000-0000-000000000001","net":"h2","type":"none","host":"edge.example.com","path":"/ray","tls":"tls","sni":"vmess.example.com"}
        """
        let encoded = Data(json.utf8).base64EncodedString()
        let node = try model.importURI("vmess://\(encoded)")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(localProxy.startedNode, node)
        XCTAssertEqual(localProxy.startedCredential, "00000000-0000-0000-0000-000000000001")
        XCTAssertNil(tun.startedNode)
        XCTAssertNil(tun.startedCredential)
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
    }

    @MainActor
    func testAppViewModelConnectStartsVMessGRPCTLSLocalProxyWithoutStartingUserModeTun() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let tunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let tun = RecordingUserModeTunController(endpoint: tunEndpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy, userModeTunController: tun)
        let json = """
        {"v":"2","ps":"VMess gRPC","add":"vmess.example.com","port":"443","id":"00000000-0000-0000-0000-000000000001","net":"grpc","type":"none","host":"edge.example.com","path":"/TunService/Connect","tls":"tls","sni":"vmess.example.com"}
        """
        let encoded = Data(json.utf8).base64EncodedString()
        let node = try model.importURI("vmess://\(encoded)")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(localProxy.startedNode, node)
        XCTAssertEqual(localProxy.startedCredential, "00000000-0000-0000-0000-000000000001")
        XCTAssertNil(tun.startedNode)
        XCTAssertNil(tun.startedCredential)
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
    }

    @MainActor
    func testAppViewModelConnectRejectsVMessPinnedTLSBeforeStartingProxy() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy)
        let encoded = "eyJ2IjoiMiIsInBzIjoiVk1lc3MgVGNwIFBpbiIsImFkZCI6InZtZXNzLmV4YW1wbGUuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoiMDAwMDAwMDAtMDAwMC0wMDAwLTAwMDAtMDAwMDAwMDAwMDAxIiwibmV0IjoidGNwIiwidHlwZSI6Im5vbmUiLCJ0bHMiOiJ0bHMiLCJzbmkiOiJ2bWVzcy5leGFtcGxlLmNvbSIsImZwIjoiY2hyb21lIn0"
        _ = try model.importURI("vmess://\(encoded)")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyFailed("当前 VMess 节点暂不支持证书固定或 Reality"))
        XCTAssertNil(localProxy.startedNode)
        XCTAssertEqual(model.localProxyState.phase, .failed)
        XCTAssertEqual(model.localProxyState.message, "当前 VMess 节点暂不支持证书固定或 Reality")
    }

    @MainActor
    func testAppViewModelConnectRejectsVLESSWithoutPlainTLSBeforeStartingProxy() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy)
        _ = try model.importURI("vless://00000000-0000-0000-0000-000000000002@vless.example.com:443?type=tcp&sni=vless.example.com#VLESS")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyFailed("当前 VLESS 节点需要 TCP+TLS 传输"))
        XCTAssertNil(localProxy.startedNode)
        XCTAssertEqual(model.localProxyState.phase, .failed)
        XCTAssertEqual(model.localProxyState.message, "当前 VLESS 节点需要 TCP+TLS 传输")
    }

    @MainActor
    func testAppViewModelConnectRejectsVLESSRealityBeforeStartingProxy() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy)
        _ = try model.importURI("vless://00000000-0000-0000-0000-000000000002@vless.example.com:443?type=tcp&security=reality&sni=vless.example.com&pbk=public-key&sid=abcd&fp=chrome#VLESS")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyFailed("当前 VLESS 节点暂不支持证书固定或 Reality"))
        XCTAssertNil(localProxy.startedNode)
        XCTAssertEqual(model.localProxyState.phase, .failed)
        XCTAssertEqual(model.localProxyState.message, "当前 VLESS 节点暂不支持证书固定或 Reality")
    }

    @MainActor
    func testAppViewModelConnectStartsLocalProxyForTUICQUICExporterPath() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let tunEndpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let tun = RecordingUserModeTunController(endpoint: tunEndpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy, userModeTunController: tun)
        let node = try model.importURI("tuic://00000000-0000-0000-0000-000000000003:tuic-password@tuic.example.com:443?sni=tuic.example.com&alpn=h3#TUIC")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(localProxy.startedNode, node)
        XCTAssertEqual(localProxy.startedCredential, "00000000-0000-0000-0000-000000000003:tuic-password")
        XCTAssertNil(tun.startedNode)
        XCTAssertNil(tun.startedCredential)
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
    }

    @MainActor
    func testAppViewModelConnectRejectsVLESSPinnedTLSBeforeStartingProxy() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let localProxy = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: localProxy)
        _ = try model.importURI("vless://00000000-0000-0000-0000-000000000002@vless.example.com:443?type=tcp&security=tls&sni=vless.example.com&fp=chrome#VLESS")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyFailed("当前 VLESS 节点暂不支持证书固定或 Reality"))
        XCTAssertNil(localProxy.startedNode)
        XCTAssertEqual(model.localProxyState.phase, .failed)
        XCTAssertEqual(model.localProxyState.message, "当前 VLESS 节点暂不支持证书固定或 Reality")
    }

    @MainActor
    func testAppViewModelConnectUnsupportedNodePreservesRunningLocalProxy() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let controller = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: controller)
        _ = try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        _ = model.connect()
        let hysteria = try model.importURI("hysteria2://example-password@hy2.example.com:19991/?insecure=1&pinSHA256=example-pin&sni=hy2.example.com#HY2")
        model.selectNode(id: hysteria.id)

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(controller.startedNode, hysteria)
        XCTAssertEqual(controller.startedCredential, "example-password")
        XCTAssertEqual(model.localProxyState.phase, .running)
        XCTAssertEqual(model.localProxyState.endpoint, endpoint)
        XCTAssertEqual(model.localProxyState.message, "本地代理已启动：SOCKS 127.0.0.1:10808，HTTP 127.0.0.1:10809")
    }

    @MainActor
    func testAppViewModelStopConnectionStopsLocalProxyAndUpdatesConnectionStatus() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let controller = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        _ = model.connect()

        model.stopConnection()

        XCTAssertEqual(model.overviewState.connectionStatus, .disconnected)
        XCTAssertEqual(model.localProxyState.phase, .stopped)
        XCTAssertEqual(model.localProxyState.endpoint, nil)
        XCTAssertTrue(controller.didStop)
    }

    @MainActor
    func testAppViewModelStopConnectionPreservesFailureWhenLocalProxyStopFails() throws {
        let localProxyController = StopThrowingLocalProxyController(endpoint: LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809))
        let tunController = RecordingUserModeTunController(endpoint: UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500))
        let model = AppViewModel(nodes: [], localProxyController: localProxyController, userModeTunController: tunController)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        _ = model.connect()
        _ = try model.startUserModeTunMode()

        model.stopConnection()

        XCTAssertEqual(model.localProxyState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
        XCTAssertEqual(model.overviewState.connectionStatus, .failed)
        XCTAssertTrue(tunController.didStop)
    }

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

    @MainActor
    func testAppViewModelConnectAllowsApprovedShadowsocks2022Methods() throws {
        let endpoint = LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809)
        let controller = RecordingLocalProxyController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], localProxyController: controller)
        try model.importShadowsocksURI("ss://MjAyMi1ibGFrZTMtYWVzLTEyOC1nY206QUFFQ0F3UUZCZ2NJQ1FvTERBME9Edz09QGV4YW1wbGUuaW52YWxpZDo0MjgxNw==#Shadowsocks-2022-example")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyStarted(endpoint))
        XCTAssertEqual(controller.startedNode?.name, "Shadowsocks-2022-example")
        XCTAssertEqual(controller.startedCredential, "2022-blake3-aes-128-gcm:AAECAwQFBgcICQoLDA0ODw==")
        XCTAssertEqual(model.localProxyState.phase, .running)
    }

    @MainActor
    func testAppViewModelConnectRejectsUnknownShadowsocks2022MethodBeforeStartingProxy() throws {
        let controller = RecordingLocalProxyController(endpoint: LocalProxyEndpoint(host: "127.0.0.1", socksPort: 10808, httpPort: 10809))
        let model = AppViewModel(nodes: [], localProxyController: controller)
        try model.importShadowsocksURI("ss://MjAyMi1ibGFrZTMtYWVzLTE5Mi1nY206QUFFQ0F3UUZCZ2NJQ1FvTERBME9Edz09QGV4YW1wbGUuaW52YWxpZDo0MjgxNw==#Unknown-2022-example")

        let result = model.connect()

        XCTAssertEqual(result, .localProxyFailed("当前 Shadowsocks 加密方法暂不支持本地代理"))
        XCTAssertNil(controller.startedNode)
        XCTAssertEqual(model.localProxyState.phase, .failed)
    }

    @MainActor
    func testAppViewModelExposesUnsignedMacGuidance() {
        let model = AppViewModel(nodes: [])

        XCTAssertTrue(model.systemProxyGuidance.enableSOCKSCommand.contains("networksetup"))
        XCTAssertTrue(model.systemProxyGuidance.enableHTTPCommand.contains("127.0.0.1 10809"))
        XCTAssertTrue(model.systemProxyGuidance.disableCommand.contains("-setsocksfirewallproxystate"))
        XCTAssertTrue(model.packetTunnelGuidance.message.contains("Apple Developer"))
        XCTAssertTrue(model.packetTunnelGuidance.userModeTunMessage.contains("root"))
    }

    @MainActor
    func testAppViewModelStartsUserModeTunForImportedNode() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let endpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let controller = RecordingUserModeTunController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], runtimeSnapshotStore: store, userModeTunController: controller)
        let node = try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        let result = try model.startUserModeTunMode()

        XCTAssertEqual(result, endpoint)
        XCTAssertEqual(controller.startedNode, node)
        XCTAssertEqual(controller.startedCredential, "aes-256-gcm:pass")
        XCTAssertEqual(try store.load()?.selectedNode.id, node.id)
        XCTAssertEqual(model.userModeTunState.phase, .running)
        XCTAssertEqual(model.userModeTunState.endpoint, endpoint)
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 已启动：utun9 10.255.0.2/1500"))
    }

    @MainActor
    func testAppViewModelExposesUserModeTunAuthorizationFailure() throws {
        let controller = ThrowingUserModeTunController(error: UserModeTunError.authorizationRequired)
        let model = AppViewModel(nodes: [], userModeTunController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        XCTAssertThrowsError(try model.startUserModeTunMode())

        XCTAssertEqual(model.userModeTunState.phase, .authorizationRequired)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 需要管理员授权")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 需要管理员授权"))
    }

    @MainActor
    func testAppViewModelRequestsUserModeTunAuthorization() throws {
        let authorization = RecordingUserModeTunAuthorizationController(result: .instructionsReady("sudo '/Applications/irockMacApp.app/Contents/MacOS/irockMacApp'"))
        let model = AppViewModel(nodes: [], userModeTunAuthorizationController: authorization)

        model.requestUserModeTunAuthorization()

        XCTAssertTrue(authorization.didRequest)
        XCTAssertEqual(model.userModeTunState.phase, .authorizationRequired)
        XCTAssertEqual(model.userModeTunState.message, "请在终端手动运行管理员启动命令：sudo '/Applications/irockMacApp.app/Contents/MacOS/irockMacApp'")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("正在请求管理员授权…"))
    }

    @MainActor
    func testAppViewModelReportsUnavailableUserModeTunAuthorization() throws {
        let authorization = RecordingUserModeTunAuthorizationController(result: .unavailable("无法打开管理员授权对话框"))
        let model = AppViewModel(nodes: [], userModeTunAuthorizationController: authorization)

        model.requestUserModeTunAuthorization()

        XCTAssertTrue(authorization.didRequest)
        XCTAssertEqual(model.userModeTunState.phase, .authorizationRequired)
        XCTAssertEqual(model.userModeTunState.message, "无法打开管理员授权对话框")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("无法打开管理员授权对话框"))
    }

    @MainActor
    func testAppViewModelRejectsUserModeTunWithoutSelectedNode() {
        let controller = RecordingUserModeTunController(endpoint: UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500))
        let model = AppViewModel(nodes: [], userModeTunController: controller)

        XCTAssertThrowsError(try model.startUserModeTunMode())

        XCTAssertNil(controller.startedNode)
        XCTAssertEqual(model.userModeTunState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.message, "请选择节点后再启动用户态 TUN")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("请选择节点后再启动用户态 TUN"))
    }

    @MainActor
    func testAppViewModelRejectsUserModeTunWithoutImportedCredential() {
        let node = makeNode(id: "node-1", name: "Manual")
        let controller = RecordingUserModeTunController(endpoint: UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500))
        let model = AppViewModel(nodes: [node], userModeTunController: controller)
        model.selectNode(id: node.id)

        XCTAssertThrowsError(try model.startUserModeTunMode())

        XCTAssertNil(controller.startedNode)
        XCTAssertEqual(model.userModeTunState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 缺少节点凭据")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 缺少节点凭据"))
    }

    @MainActor
    func testAppViewModelMapsGenericUserModeTunFailure() throws {
        let controller = ThrowingUserModeTunController(error: UserModeTunError.unavailable)
        let model = AppViewModel(nodes: [], userModeTunController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")

        XCTAssertThrowsError(try model.startUserModeTunMode()) { error in
            XCTAssertEqual(error as? UserModeTunError, .unavailable)
        }

        XCTAssertEqual(model.userModeTunState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 启动失败")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 启动失败"))
    }

    @MainActor
    func testAppViewModelStopsUserModeTun() throws {
        let endpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let controller = RecordingUserModeTunController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], userModeTunController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        _ = try model.startUserModeTunMode()

        model.stopUserModeTunMode()

        XCTAssertTrue(controller.didStop)
        XCTAssertEqual(model.userModeTunState.phase, .stopped)
        XCTAssertNil(model.userModeTunState.endpoint)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 已停止")
        XCTAssertEqual(model.overviewState.connectionStatus, .disconnected)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 已停止"))
    }

    @MainActor
    func testAppViewModelPreservesUserModeTunEndpointWhenStopFails() throws {
        let endpoint = UserModeTunEndpoint(interfaceName: "utun9", address: "10.255.0.2", gateway: "10.255.0.1", mtu: 1500)
        let controller = StopThrowingUserModeTunController(endpoint: endpoint)
        let model = AppViewModel(nodes: [], userModeTunController: controller)
        try model.importShadowsocksURI("ss://YWVzLTI1Ni1nY206cGFzcw@example.com:8388#Demo")
        _ = try model.startUserModeTunMode()

        model.stopUserModeTunMode()

        XCTAssertEqual(model.userModeTunState.phase, .failed)
        XCTAssertEqual(model.userModeTunState.endpoint, endpoint)
        XCTAssertEqual(model.userModeTunState.message, "用户态 TUN 停止失败")
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("用户态 TUN 停止失败"))
    }

    @MainActor
    func testAppViewModelAppendsBoundedLogs() {
        let model = AppViewModel(nodes: [], logLimit: 2)

        model.appendLog("first")
        model.appendLog("second")
        model.appendLog("third")

        XCTAssertEqual(model.overviewState.recentLogMessages, ["second", "third"])
    }

    @MainActor
    func testAppViewModelUpdatesRouteModeBeforePublishing() throws {
        let node = makeNode(id: "node-1", name: "Demo")
        let store = InMemoryRuntimeSnapshotStore()
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)

        model.selectNode(id: node.id)
        model.setRouteMode(.direct)
        let result = model.publishRuntimeSnapshot()

        guard case .published = result else {
            return XCTFail("Expected published result")
        }
        XCTAssertEqual(model.overviewState.routeMode, .direct)
        XCTAssertEqual(try store.load()?.routeMode, .direct)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("运行配置已发布"))
    }

    @MainActor
    func testAppViewModelPublishesDebugSnapshotWhenDebugLoggingEnabled() throws {
        let node = makeNode(id: "node-1", name: "Demo")
        let store = InMemoryRuntimeSnapshotStore()
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)

        model.selectNode(id: node.id)
        model.setDebugLoggingEnabled(true)
        _ = model.publishRuntimeSnapshot()

        XCTAssertTrue(model.settingsState.debugLoggingEnabled)
        XCTAssertEqual(try store.load()?.logLevel, .debug)
    }

    @MainActor
    func testAppViewModelLogsMissingNodeWhenPublishingWithoutSelection() {
        let model = AppViewModel(nodes: [])

        let result = model.publishRuntimeSnapshot()

        XCTAssertEqual(result, .missingSelectedNode)
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("请选择节点后再启动"))
    }

    @MainActor
    func testAppViewModelPublishesRoutingRuleManifestFromLocalText() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)
        model.selectNode(id: node.id)
        model.setRoutingRuleText("DOMAIN-SUFFIX,apple.com,DIRECT\nFINAL,PROXY")

        _ = model.publishRuntimeSnapshot()

        XCTAssertEqual(try store.load()?.routingRuleManifest, RuntimeRoutingRuleManifest(
            version: 1,
            rules: [
                RuntimeRoutingRule(kind: .domainSuffix, value: "apple.com", action: .direct),
                RuntimeRoutingRule(kind: .finalRule, value: nil, action: .proxy)
            ]
        ))
    }

    @MainActor
    func testAppViewModelPublishesEmptyManifestForCommentOnlyRules() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)
        model.selectNode(id: node.id)
        model.setRoutingRuleText("# no local rules")

        _ = model.publishRuntimeSnapshot()

        XCTAssertEqual(try store.load()?.routingRuleManifest, .empty)
    }

    @MainActor
    func testAppViewModelDoesNotPublishWhenRoutingRulesAreInvalid() throws {
        let store = InMemoryRuntimeSnapshotStore()
        let node = makeNode(id: "node-1", name: "Demo")
        let model = AppViewModel(nodes: [node], runtimeSnapshotStore: store)
        model.selectNode(id: node.id)
        model.setRoutingRuleText("DOMAIN,example.com,SECRET_TOKEN")

        let result = model.publishRuntimeSnapshot()

        guard case let .storageFailed(message) = result else {
            return XCTFail("Expected storageFailed result")
        }
        XCTAssertEqual(message, "Routing rules invalid at line 1: unsupported action")
        XCTAssertFalse(message.contains("SECRET_TOKEN"))
        XCTAssertNil(try store.load())
        XCTAssertTrue(model.overviewState.recentLogMessages.contains("Routing rules invalid at line 1: unsupported action"))
    }

    @MainActor
    func testAppViewModelRefreshesRuntimeFeedback() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let status = RuntimeConnectionStatus(
            phase: .connected,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_030),
            message: "Connected"
        )
        let log = RuntimeLogEntry(
            id: "log-1",
            timestamp: Date(timeIntervalSince1970: 1_715_000_031),
            level: .user,
            message: "Tunnel runtime connected",
            nodeID: NodeID(rawValue: "node-1"),
            phase: .connected
        )
        try statusStore.save(status)
        try logStore.append(log)
        let model = AppViewModel(nodes: [], runtimeStatusStore: statusStore, runtimeLogStore: logStore)

        let result = model.refreshRuntimeFeedback()

        XCTAssertEqual(result, .refreshed)
        XCTAssertEqual(model.runtimeConnectionStatus, status)
        XCTAssertEqual(model.runtimeLogs, [log])
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
        XCTAssertEqual(model.overviewState.recentLogMessages, ["Tunnel runtime connected"])
    }

    @MainActor
    func testAppViewModelRefreshUsesDisconnectedWhenStatusIsMissing() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let logStore = InMemoryRuntimeLogStore()
        let model = AppViewModel(nodes: [], runtimeStatusStore: statusStore, runtimeLogStore: logStore)

        let result = model.refreshRuntimeFeedback()

        XCTAssertEqual(result, .refreshed)
        XCTAssertEqual(model.runtimeConnectionStatus?.phase, .disconnected)
        XCTAssertEqual(model.overviewState.connectionStatus, .disconnected)
    }

    @MainActor
    func testAppViewModelRefreshAppliesStatusWhenLogLoadFails() throws {
        let statusStore = InMemoryRuntimeStatusStore()
        let status = RuntimeConnectionStatus(
            phase: .connected,
            selectedNodeID: NodeID(rawValue: "node-1"),
            selectedNodeName: "Demo",
            updatedAt: Date(timeIntervalSince1970: 1_715_000_032),
            message: "Connected"
        )
        try statusStore.save(status)
        let model = AppViewModel(nodes: [], runtimeStatusStore: statusStore, runtimeLogStore: ThrowingRuntimeLogStore())

        let result = model.refreshRuntimeFeedback()

        guard case .logLoadFailed(let message) = result else {
            return XCTFail("Expected logLoadFailed result")
        }
        XCTAssertEqual(message, "Runtime logs unavailable")
        XCTAssertEqual(model.runtimeConnectionStatus, status)
        XCTAssertEqual(model.overviewState.connectionStatus, .connected)
    }

    @MainActor
    func testAppViewModelRefreshReturnsStableStatusFailureMessage() {
        let model = AppViewModel(nodes: [], runtimeStatusStore: ThrowingRuntimeStatusStore())

        let result = model.refreshRuntimeFeedback()

        guard case .statusLoadFailed(let message) = result else {
            return XCTFail("Expected statusLoadFailed result")
        }
        XCTAssertEqual(message, "Runtime status unavailable")
    }

    private final class RecordingLocalProxyController: LocalProxyControlling {
        let endpoint: LocalProxyEndpoint
        private(set) var startedNode: ProxyNode?
        private(set) var startedCredential: String?
        private(set) var startedRealmCredential: String?
        private(set) var didStop = false

        init(endpoint: LocalProxyEndpoint) {
            self.endpoint = endpoint
        }

        func start(node: ProxyNode, credential: String, realmCredential: String?) throws -> LocalProxyEndpoint {
            startedNode = node
            startedCredential = credential
            startedRealmCredential = realmCredential
            return endpoint
        }

        func stop() throws {
            didStop = true
        }
    }

    private final class RecordingUserModeTunAuthorizationController: UserModeTunAuthorizationControlling {
        let result: UserModeTunAuthorizationResult
        private(set) var didRequest = false

        init(result: UserModeTunAuthorizationResult) {
            self.result = result
        }

        func requestAuthorization() -> UserModeTunAuthorizationResult {
            didRequest = true
            return result
        }
    }

    private final class RecordingUserModeTunController: UserModeTunControlling {
        let endpoint: UserModeTunEndpoint
        private(set) var startedNode: ProxyNode?
        private(set) var startedCredential: String?
        private(set) var didStop = false

        init(endpoint: UserModeTunEndpoint) {
            self.endpoint = endpoint
        }

        func start(node: ProxyNode, credential: String) throws -> UserModeTunEndpoint {
            startedNode = node
            startedCredential = credential
            return endpoint
        }

        func stop() throws {
            didStop = true
        }
    }

    private final class ThrowingLocalProxyController: LocalProxyControlling {
        func start(node: ProxyNode, credential: String, realmCredential: String?) throws -> LocalProxyEndpoint {
            throw LocalProxyError.unavailable
        }

        func stop() throws {}
    }

    private final class StopThrowingLocalProxyController: LocalProxyControlling {
        let endpoint: LocalProxyEndpoint

        init(endpoint: LocalProxyEndpoint) {
            self.endpoint = endpoint
        }

        func start(node: ProxyNode, credential: String, realmCredential: String?) throws -> LocalProxyEndpoint {
            endpoint
        }

        func stop() throws {
            throw LocalProxyError.unavailable
        }
    }

    private final class ThrowingUserModeTunController: UserModeTunControlling {
        let error: UserModeTunError

        init(error: UserModeTunError) {
            self.error = error
        }

        func start(node: ProxyNode, credential: String) throws -> UserModeTunEndpoint {
            throw error
        }

        func stop() throws {}
    }

    private final class StopThrowingUserModeTunController: UserModeTunControlling {
        let endpoint: UserModeTunEndpoint

        init(endpoint: UserModeTunEndpoint) {
            self.endpoint = endpoint
        }

        func start(node: ProxyNode, credential: String) throws -> UserModeTunEndpoint {
            endpoint
        }

        func stop() throws {
            throw UserModeTunError.unavailable
        }
    }

    private struct ThrowingRuntimeLogStore: RuntimeLogStore {
        func append(_ entry: RuntimeLogEntry) throws {}

        func loadRecent() throws -> [RuntimeLogEntry] {
            throw TestError.loadFailed
        }

        func clear() throws {}
    }

    private struct ThrowingRuntimeStatusStore: RuntimeStatusStore {
        func save(_ status: RuntimeConnectionStatus) throws {}

        func load() throws -> RuntimeConnectionStatus? {
            throw TestError.loadFailed
        }
    }

    private enum TestError: Error {
        case loadFailed
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
