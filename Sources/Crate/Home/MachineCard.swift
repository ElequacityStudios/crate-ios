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
                    .frame(maxWidth: wide ? geometry.size.width * 0.52 : .infinity)
                details
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            MachineSpecs(machine: machine)
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(machine.name)
                        .font(.title2.bold())
                    Text(machine.versionLabel)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text("\(machine.distribution.family.title) · \(machine.architecture)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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

    private let columns = [GridItem(.flexible(), spacing: 6),
                           GridItem(.flexible(), spacing: 6),
                           GridItem(.flexible(), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            SpecTile(title: "CPUs", systemImage: "cpu", value: "\(machine.cpuCount) cores")
            SpecTile(title: "Memory", systemImage: "memorychip", value: "\(machine.memoryGB) GB")
            SpecTile(title: "Disk", systemImage: "internaldrive",
                     value: "\(machine.diskUsedGB.formatted(.number.precision(.fractionLength(1)))) of \(machine.diskGB) GB")
            SpecTile(title: "Desktop", systemImage: "macwindow", value: machine.desktop)
            SpecTile(title: "Display", systemImage: "display", value: machine.display)
            SpecTile(title: "Last used", systemImage: "clock", value: Format.relative(machine.lastStarted))
        }
    }
}

struct SpecTile: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
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
