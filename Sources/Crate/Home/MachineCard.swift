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

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height * 1.25
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                : AnyLayout(VStackLayout(spacing: 14))
            layout {
                MachineScreenshot(machine: machine)
                    .overlay(alignment: .topTrailing) { starButton.padding(10) }
                    .frame(maxWidth: wide ? geometry.size.width * 0.48 : .infinity)
                if wide {
                    // Landscape on the closed Duo leaves the details about 200 pt,
                    // too short for the whole grid; it then shrinks to one row,
                    // and failing that to one line of figures.
                    ViewThatFits(in: .vertical) {
                        details(specs: MachineSpecs(machine: machine))
                        details(specs: MachineSpecs(machine: machine, rows: 1))
                        details(specs: MachineSpecLine(machine: machine))
                    }
                } else {
                    details(specs: MachineSpecs(machine: machine))
                }
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private func details(specs: some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            specs
            Spacer(minLength: 0)
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

    private var header: some View {
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
            Menu {
                Button(isDefault ? "Remove as Default" : "Make Default",
                       systemImage: isDefault ? "star.slash" : "star",
                       action: onToggleDefault)
                Button("Edit Settings…", systemImage: "slider.horizontal.3") {}
                    .disabled(true)
                Divider()
                Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.fill.tertiary, in: Circle())
            }
            .accessibilityLabel("More")
        }
    }

    /// The star: filled and labelled on the default VM, a plain outline otherwise.
    private var starButton: some View {
        Button(action: onToggleDefault) {
            HStack(spacing: 5) {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundStyle(isDefault ? .yellow : .white)
                if isDefault {
                    Text("Default")
                        .foregroundStyle(.white)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, isDefault ? 12 : 0)
            .frame(minWidth: 36, minHeight: 36)
            .background(.black.opacity(0.45), in: Capsule())
        }
        .buttonStyle(.plain)
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

    private let columns = [GridItem(.flexible(), spacing: 6),
                           GridItem(.flexible(), spacing: 6),
                           GridItem(.flexible(), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
