import SwiftUI

enum AppTab: Hashable {
    case home
    case install
    case settings
}

/// The three tabs, and the running VM over them.
struct RootView: View {
    @Environment(MachineStore.self) private var store
    @AppStorage(SettingsKey.stubJITEnabled) private var jitEnabled = false

    @State private var tab: AppTab
    @State private var running: Machine?
    @State private var didLaunch = false

    init(firstTab: AppTab) {
        _tab = State(initialValue: firstTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeScreen(
                    onStart: { running = $0 },
                    onInstall: { tab = .install })
            }
            Tab("Install", systemImage: "arrow.down.circle", value: .install) {
                InstallScreen(onShowHome: { tab = .home })
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsScreen()
            }
        }
        .fullScreenCover(item: $running) { machine in
            MachineScreen(machine: machine)
        }
        .task { bootDefaultAtLaunch() }
    }

    /// The default VM boots at launch, but only when JIT is on: without it a
    /// VM can't run, so the app opens on Home instead.
    private func bootDefaultAtLaunch() {
        guard !didLaunch else { return }
        didLaunch = true
        if jitEnabled, let machine = store.defaultMachine {
            running = machine
        }
    }
}
