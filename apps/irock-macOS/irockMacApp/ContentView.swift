import IrockAppFeature
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = Self.makeViewModel()

    var body: some View {
        IrockRootView(viewModel: viewModel)
    }

    private static func makeViewModel() -> AppViewModel {
        do {
            let stores = try MacOSAppGroupRuntimeStoreResolver().makeRuntimeStoreBundle()
            return AppViewModel(
                nodes: [],
                runtimeSnapshotStore: stores.snapshotStore,
                runtimeStatusStore: stores.statusStore,
                runtimeLogStore: stores.logStore
            )
        } catch {
            return AppViewModel(nodes: [])
        }
    }
}
