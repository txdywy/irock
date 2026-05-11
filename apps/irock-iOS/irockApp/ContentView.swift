import IrockAppFeature
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel(nodes: [])

    var body: some View {
        IrockRootView(viewModel: viewModel)
    }
}
