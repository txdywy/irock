import IrockAppFeature
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = Self.makeViewModel()

    var body: some View {
        IrockRootView(viewModel: viewModel)
            .frame(minWidth: 980, minHeight: 680)
    }

    private static func makeViewModel() -> AppViewModel {
        do {
            let stores = try MacOSAppGroupRuntimeStoreResolver().makeRuntimeStoreBundle()
            return AppViewModel(
                nodes: [],
                runtimeSnapshotStore: stores.snapshotStore,
                runtimeStatusStore: stores.statusStore,
                runtimeLogStore: stores.logStore,
                localProxyController: MacOSLocalProxyController(),
                userModeTunController: MacOSUserModeTunController(runtimeStores: stores),
                userModeTunAuthorizationController: MacOSUserModeTunAuthorizationController()
            )
        } catch {
            return AppViewModel(nodes: [], localProxyController: MacOSLocalProxyController(), userModeTunController: MacOSUserModeTunController(), userModeTunAuthorizationController: MacOSUserModeTunAuthorizationController())
        }
    }
}
