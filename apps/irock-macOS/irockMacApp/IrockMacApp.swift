import IrockAppFeature
import SwiftUI

@main
struct IrockMacApp: App {
    init() {
        MacOSPackagedSelfTestHarness.shared.startIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private final class MacOSPackagedSelfTestHarness: @unchecked Sendable {
    static let shared = MacOSPackagedSelfTestHarness()

    private var viewModel: AppViewModel?

    func startIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let uri = Self.selfTestURI(from: environment) else {
            return
        }

        Task { @MainActor in
            do {
                let model = AppViewModel(
                    nodes: [],
                    localProxyController: MacOSLocalProxyController(),
                    userModeTunController: DisabledUserModeTunController(),
                    userModeTunAuthorizationController: DisabledUserModeTunAuthorizationController()
                )
                _ = try model.importURI(uri)
                let endpoint = try model.startLocalProxyMode()
                self.viewModel = model
                fputs("IROCK_SELF_TEST_READY socks=\(endpoint.host):\(endpoint.socksPort) http=\(endpoint.host):\(endpoint.httpPort)\n", stderr)
            } catch {
                fputs("IROCK_SELF_TEST_FAILED \(Self.safeFailureDescription(error))\n", stderr)
            }
        }
    }

    private static func selfTestURI(from environment: [String: String]) -> String? {
        if let uri = trimmed(environment["IROCK_SELF_TEST_URI"]), !uri.isEmpty {
            return uri
        }
        guard let host = trimmed(environment["IROCK_TROJAN_TEST_HOST"]), !host.isEmpty,
              let password = trimmed(environment["IROCK_TROJAN_TEST_PASSWORD"]), !password.isEmpty else {
            return nil
        }
        let port = trimmed(environment["IROCK_TROJAN_TEST_PORT"]).flatMap(Int.init) ?? 443
        guard (1...65_535).contains(port) else { return nil }
        let sni = trimmed(environment["IROCK_TROJAN_TEST_SNI"]).flatMap { $0.isEmpty ? nil : $0 } ?? host
        var components = URLComponents()
        components.scheme = "trojan"
        components.host = host
        components.port = port
        components.user = password
        components.queryItems = [
            URLQueryItem(name: "sni", value: sni),
            URLQueryItem(name: "allowInsecure", value: allowsInsecure(environment["IROCK_TROJAN_TEST_ALLOW_INSECURE"]) ? "1" : "0")
        ]
        components.fragment = "Trojan Self Test"
        return components.url?.absoluteString
    }

    private static func allowsInsecure(_ value: String?) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": true
        default: false
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func safeFailureDescription(_ error: Error) -> String {
        String(describing: type(of: error))
    }
}
