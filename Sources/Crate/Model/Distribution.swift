import SwiftUI

/// The kind of operating system a VM runs. Only Linux installs today; the other
/// two are here so the UI has somewhere to put them when they arrive.
enum OSFamily: String, Codable, CaseIterable, Identifiable {
    case linux
    case macOS
    case windows

    var id: Self { self }

    var title: String {
        switch self {
        case .linux: "Linux"
        case .macOS: "macOS"
        case .windows: "Windows"
        }
    }
}

/// An operating system Crate knows how to install: what it is called and how it
/// is drawn. A ``Machine`` is one installed copy of one of these.
struct Distribution: Identifiable, Hashable {
    let id: String
    let name: String
    let family: OSFamily
    /// Tints a VM's screenshot area. A system colour, so it has dark and
    /// increased-contrast variants; not red (destructive actions) or blue (the
    /// accent, which means "tappable"): pink for Debian's red, indigo for
    /// Arch's blue.
    let color: Color

    static let debian = Distribution(id: "debian", name: "Debian", family: .linux, color: .pink)
    static let arch = Distribution(id: "arch", name: "Arch Linux", family: .linux, color: .indigo)

    static let all: [Distribution] = [.debian, .arch]

    static func named(_ id: String) -> Distribution {
        all.first { $0.id == id } ?? .debian
    }
}
