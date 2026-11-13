import SwiftUI

/// One installed VM: its screenshot, what it is, how it's configured, and Start.
///
/// Tall cards stack the screenshot over the details; a card wider than it is
/// tall (landscape, or the Duo opened flat) puts them side by side.
struct MachineCard: View {
    let machine: Machine
    let isDefault: Bool
    let onStart: () -> Void
    let onToggleDefault: () -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // At the accessibility text sizes the card grows to fit its text
                // (HomeScreen stops fixing its height): held to 75% of the
                // screen, the details would crush the screenshot and spill out.
                VStack(spacing: 14) {
                    screenshot
                        .aspectRatio(16 / 10, contentMode: .fit)
                    details(specs: MachineSpecs(machine: machine), wide: false)
                }
                .padding(14)
            } else {
                sized
            }
        }
        // Secondary on the page's primary grouped background, as the HIG's
        // colour hierarchy has it.
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var screenshot: some View {
        MachineScreenshot(machine: machine)
            .overlay(alignment: .topTrailing) { starButton.padding(10) }
    }

    /// The card at the size HomeScreen gives it.
    private var sized: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height * 1.25
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                : AnyLayout(VStackLayout(spacing: 14))
            layout {
                screenshot
                    .frame(maxWidth: wide ? geometry.size.width * 0.48 : .infinity)
                if wide {
                    // Landscape on the closed Duo leaves the details about 200 pt,
                    // too short for the whole grid; it then shrinks to one row,
                    // and failing that to one line of figures.
                    ViewThatFits(in: .vertical) {
                        details(specs: MachineSpecs(machine: machine), wide: true)
                        details(specs: MachineSpecs(machine: machine, rows: 1), wide: true)
                        details(specs: MachineSpecLine(machine: machine), wide: true)
                    }
                } else {
                    details(specs: MachineSpecs(machine: machine), wide: false)
                }
            }
            .padding(14)
        }
    }

    /// Side by side, Start sits at the bottom of the details column; stacked,
    /// the screenshot above takes all the spare height instead.
    private func details(specs: some View, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            specs
            if wide {
                Spacer(minLength: 0)
            }
            Button(action: onStart) {
                Label("Start", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    /// Badge, name and version, and the More menu. At the accessibility text
    /// sizes the name and version go under the badge, so they have the card's
    /// full width.
    @ViewBuilder
    private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    DistributionBadge(distribution: machine.distribution, size: 44)
                    Spacer(minLength: 0)
                    moreMenu
                }
                Text(machine.name)
                    .font(.title2.bold())
                Text("\(machine.versionLabel) · \(machine.distribution.family.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 12) {
                DistributionBadge(distribution: machine.distribution, size: 44)
                // The version beside the name when there's room, under it when not.
                ViewThatFits(in: .horizontal) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(machine.name)
                                .font(.title2.bold())
                            Text(machine.versionLabel)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(machine.distribution.family.title) · \(machine.architecture)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(machine.name)
                            .font(.title2.bold())
                            .minimumScaleFactor(0.7)
                        Text("\(machine.versionLabel) · \(machine.distribution.family.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                moreMenu
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(isDefault ? "Remove as Default" : "Make Default",
                   systemImage: isDefault ? "star.slash" : "star",
                   action: onToggleDefault)
            Button("Edit Settings…", systemImage: "slider.horizontal.3") {}
                .disabled(true)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            // Monochrome: the card's screenshot is colourful enough, and the
            // accent colour is kept for Start.
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.fill.tertiary, in: Circle())
        }
        .tint(.primary)
        // A control, not content: it stays a control's size at the largest
        // text sizes, as tab titles do.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("More")
    }

    /// The star: filled and labelled on the default VM, a plain outline otherwise.
    ///
    /// It sits on the screenshot, which is content, so it uses a standard
    /// material rather than Liquid Glass; dark, so it reads the same over any
    /// screenshot in either appearance.
    private var starButton: some View {
        Button(action: onToggleDefault) {
            HStack(spacing: 5) {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundStyle(isDefault ? AnyShapeStyle(.yellow) : AnyShapeStyle(.primary))
                if isDefault {
                    Text("Default")
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, isDefault ? 14 : 0)
            .frame(minWidth: 44, minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel(isDefault ? "Default VM. Remove as default" : "Make default")
    }
}

/// The VM's last screen, or a stand-in before it has one.
struct MachineScreenshot: View {
    let machine: Machine

    var body: some View {
        // The colour sets the size and the image fills it, so a screenshot of any
        // shape crops to the card instead of resizing it.
        Rectangle()
            .fill(machine.distribution.color.gradient.opacity(0.35))
            .overlay {
                if let name = machine.screenshot {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 10) {
                        DistributionBadge(distribution: machine.distribution, size: 56)
                        Text("No screenshot yet")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityLabel("\(machine.name) screenshot")
    }
}

/// The VM's configuration as a grid of small tiles.
struct MachineSpecs: View {
    let machine: Machine
    /// One row is CPUs, memory and disk; two add desktop, display and last used.
    var rows = 2

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Three across, or two at the accessibility text sizes, where three
    /// columns would truncate every value.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading),
              count: typeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            SpecTile(title: "CPUs", systemImage: "cpu", value: "\(machine.cpuCount) cores")
            SpecTile(title: "Memory", systemImage: "memorychip", value: "\(machine.memoryGB) GB")
            SpecTile(title: "Disk", systemImage: "internaldrive",
                     value: "\(machine.diskUsedGB.formatted(.number.precision(.fractionLength(1)))) of \(machine.diskGB) GB")
            if rows > 1 {
                SpecTile(title: "Desktop", systemImage: "macwindow", value: machine.desktop)
                SpecTile(title: "Display", systemImage: "display", value: machine.display)
                SpecTile(title: "Last used", systemImage: "clock", value: Format.relative(machine.lastStarted))
            }
        }
    }
}

/// The figures on one line, for a card too short for ``MachineSpecs``.
struct MachineSpecLine: View {
    let machine: Machine

    var body: some View {
        Text("\(Image(systemName: "cpu")) \(machine.cpuCount)   \(Image(systemName: "memorychip")) \(machine.memoryGB) GB   \(Image(systemName: "internaldrive")) \(machine.diskGB) GB   \(Image(systemName: "macwindow")) \(machine.desktop)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

struct SpecTile: View {
    let title: String
    let systemImage: String
    let value: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Just the icon when the tile is too narrow for its title.
            ViewThatFits(in: .horizontal) {
                Label(title, systemImage: systemImage)
                Image(systemName: systemImage)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Text(value)
                .font(.footnote.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(0.75)
        }
        // No box of its own: the card is the box, and the HIG groups within
        // one by alignment and spacing rather than boxes inside it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
