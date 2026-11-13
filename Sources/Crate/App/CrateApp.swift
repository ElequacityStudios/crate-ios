import SwiftUI

@main
struct CrateApp: App {
    @State private var store: MachineStore
    private let firstTab: AppTab

    init() {
        let options = LaunchOptions.parse(ProcessInfo.processInfo.arguments)
        options.applyToDefaults()
        let store = MachineStore()
        if options.empty { store.removeAll() }
        if options.samples { store.restoreSamples() }
        _store = State(initialValue: store)
        firstTab = options.tab ?? .home
    }

    var body: some Scene {
        WindowGroup {
            RootView(firstTab: firstTab)
                .environment(store)
        }
    }
}

/// Launch arguments for looking at one state of the UI without tapping to it,
/// e.g. `xcrun simctl launch booted com.amendez.crate --tab=install --jit=off`.
struct LaunchOptions {
    var tab: AppTab?
    var jit: Bool?
    var empty = false
    var samples = false

    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        for argument in arguments.dropFirst() {
            switch argument {
            case "--tab=home": options.tab = .home
            case "--tab=install": options.tab = .install
            case "--tab=settings": options.tab = .settings
            case "--jit=on": options.jit = true
            case "--jit=off": options.jit = false
            case "--empty": options.empty = true
            case "--samples": options.samples = true
            default: break
            }
        }
        return options
    }

    func applyToDefaults() {
        if let jit { UserDefaults.standard.set(jit, forKey: SettingsKey.stubJITEnabled) }
    }
}
