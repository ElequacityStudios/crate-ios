import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
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
    @Environment(JITSession.self) private var jit
    @AppStorage(SettingsKey.jitAtLaunch) private var jitAtLaunch = true
    @AppStorage(SettingsKey.jitMethod) private var jitMethod = JITMethod.standard.rawValue

    /// Crate reopens on the tab it was left on.
    @SceneStorage("tab") private var tab = AppTab.home
    @State private var running: Machine?
    @State private var didLaunch = false
    /// Set while the launch's own attempt to turn JIT on is under way, so the
    /// default VM boots if it works.
    @State private var bootWhenJITTurnsOn = false
    @State private var fold = FoldSignals()
    /// A tab to open on regardless, from a launch argument.
    private let launchTab: AppTab?
    private let forceRail: Bool

    init(launchTab: AppTab? = nil, forceRail: Bool = false) {
        self.launchTab = launchTab
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
        // Over the tabs; the VM screen, when it's up, shows its own.
        .sheet(isPresented: running == nil ? Bindable(jit).showingSetup : .constant(false)) {
            JITSetupView()
                .environment(jit)
        }
        .task { openLaunchTab() }
        .onChange(of: jit.state, initial: true) { launchSettled() }
        .onChange(of: jit.isOn) {
            if jit.isOn && bootWhenJITTurnsOn { bootDefault() }
        }
        .onChange(of: jit.isTurningOn) {
            if !jit.isTurningOn && !jit.isOn { bootWhenJITTurnsOn = false }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: .home) {
                HomeScreen(
                    onStart: { running = $0 },
                    onInstall: { tab = .install },
                    onShowJIT: { tab = .settings })
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

    private func openLaunchTab() {
        if let launchTab { tab = launchTab }
    }

    /// The default VM boots at launch, but only when JIT is on: without it a
    /// VM can't run, so the app stays on Home instead. Decided once, when the
    /// launch's JIT check settles. With nothing attached and "Turn on JIT when
    /// crate opens" set, it turns JIT on first, and boots if that works.
    private func launchSettled() {
        guard !didLaunch, jit.state != .checking else { return }
        didLaunch = true
        if jit.isOn {
            bootDefault()
        } else if jit.state == .off(.noDebugger), jitAtLaunch {
            bootWhenJITTurnsOn = true
            Task { await jit.turnOn(JITMethod(rawValue: jitMethod) ?? .standard, interactive: false) }
        }
    }

    private func bootDefault() {
        bootWhenJITTurnsOn = false
        guard running == nil, let machine = store.defaultMachine else { return }
        // Already there, rather than sliding up over Home.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { running = machine }
    }
}
