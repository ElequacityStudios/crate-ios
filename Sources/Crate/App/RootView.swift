import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case home
    case install
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .install: "Install"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .install: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }
}

/// The three tabs, and the running VM over them.
struct RootView: View {
    @Environment(MachineStore.self) private var store
    @AppStorage(SettingsKey.stubJITEnabled) private var jitEnabled = false

    @State private var tab: AppTab
    @State private var running: Machine?
    @State private var didLaunch = false
    @State private var fold = FoldSignals()
    private let forceRail: Bool

    init(firstTab: AppTab, forceRail: Bool = false) {
        _tab = State(initialValue: firstTab)
        self.forceRail = forceRail
    }

    /// The tabs go in a column on the right whenever the Duo is open in
    /// portrait, so they stay where they are when it's closed. Closed (and open
    /// in landscape) the system puts its own tab bar in that column; open in
    /// portrait it would put it at the bottom, so Crate draws the column itself.
    private var usesRail: Bool {
        forceRail || (fold.hasHinge && fold.verticalEdge == nil)
    }

    var body: some View {
        HStack(spacing: 0) {
            tabs
            if usesRail {
                TabRail(selection: $tab)
            }
        }
        .readFoldSignals($fold)
        .fullScreenCover(item: $running) { machine in
            MachineScreen(machine: machine)
        }
        .task { bootDefaultAtLaunch() }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: .home) {
                HomeScreen(
                    onStart: { running = $0 },
                    onInstall: { tab = .install })
                .toolbar(usesRail ? .hidden : .automatic, for: .tabBar)
            }
            Tab(AppTab.install.title, systemImage: AppTab.install.systemImage, value: .install) {
                InstallScreen(onShowHome: { tab = .home })
                    .toolbar(usesRail ? .hidden : .automatic, for: .tabBar)
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: .settings) {
                SettingsScreen()
                    .toolbar(usesRail ? .hidden : .automatic, for: .tabBar)
            }
        }
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
