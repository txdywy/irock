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
        guard let uri = ProcessInfo.processInfo.environment["IROCK_SELF_TEST_URI"], !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

    private static func safeFailureDescription(_ error: Error) -> String {
        String(describing: type(of: error))
    }
}
