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
    /// The letter on the badge. Distribution logos are trademarks, so the badge
    /// is a monogram in the distribution's colour rather than the logo itself.
    let monogram: String
    /// A system colour, so it has dark and increased-contrast variants. Not
    /// red (destructive actions) or blue (the accent, which means "tappable"),
    /// and dark enough for a white letter: pink for Debian's red, indigo for
    /// Arch's blue.
    let color: Color

    static let debian = Distribution(
        id: "debian", name: "Debian", family: .linux, monogram: "D", color: .pink)
    static let arch = Distribution(
        id: "arch", name: "Arch Linux", family: .linux, monogram: "A", color: .indigo)

    static let all: [Distribution] = [.debian, .arch]

    static func named(_ id: String) -> Distribution {
        all.first { $0.id == id } ?? .debian
    }
}

/// A distribution's monogram badge, used wherever a VM is named.
struct DistributionBadge: View {
    let distribution: Distribution
    var size: CGFloat = 40

    var body: some View {
        Text(distribution.monogram)
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(distribution.color.gradient,
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}
