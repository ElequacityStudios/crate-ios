import Foundation

/// How Crate gets JIT turned on for itself.
enum JITMethod: String, CaseIterable, Identifiable {
    case builtInStikJIT
    case stikDebug

    var id: Self { self }

    var title: String {
        switch self {
        case .builtInStikJIT: "Built-in StikJIT"
        case .stikDebug: "StikDebug"
        }
    }

    static let standard = Self.builtInStikJIT
}

/// The settings Crate keeps in UserDefaults, by key, so every `@AppStorage`
/// that reads one spells it the same way.
enum SettingsKey {
    static let jitMethod = "jit.method"
    static let jitAtLaunch = "jit.turnOnAtLaunch"
    static let codeRegionMB = "jit.codeRegionMB"
    static let installMemoryGB = "install.memoryGB"

    /// STUB: whether JIT is on. Real JIT is a property of the running process,
    /// asked of the kernel at launch; until that is wired in, this flag stands in
    /// for it so both launch paths can be seen. Settings > UI Preview flips it.
    static let stubJITEnabled = "stub.jitEnabled"
}

/// Sizes offered for the JIT code region, in MB. It is claimed once per launch,
/// so a change applies the next time Crate opens.
enum CodeRegion {
    static let choices = [128, 256, 384, 512, 768, 1024]
    static let standard = 384
}
