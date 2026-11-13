import SwiftUI

/// The installed VMs, one large card each, paging vertically.
struct HomeScreen: View {
    @Environment(MachineStore.self) private var store

    let onStart: (Machine) -> Void
    let onInstall: () -> Void
    let onShowJIT: () -> Void

    @State private var deleting: Machine?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            Group {
                if store.machines.isEmpty {
                    EmptyHome(onInstall: onInstall)
                } else {
                    cards
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("My VMs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onShowJIT) {
                        JITBadge()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Install a VM", systemImage: "plus", action: onInstall)
                }
            }
            .confirmationDialog(
                "Delete \(deleting?.name ?? "")?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { machine in
                Button("Delete VM", role: .destructive) { store.delete(machine) }
            } message: { machine in
                Text("Its disk (\(Format.bytes(Int64(machine.diskUsedGB * 1e9)))) is removed from this iPhone. This can't be undone.")
            }
        }
    }

    private var cards: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(store.machines) { machine in
                    MachineCard(
                        machine: machine,
                        isDefault: store.isDefault(machine),
                        onStart: { onStart(machine) },
                        onToggleDefault: { store.toggleDefault(machine) },
                        onDelete: { deleting = machine })
                    .modifier(ViewportHeight(fraction: typeSize.isAccessibilitySize ? nil : 0.75))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.vertical, 12, for: .scrollContent)
    }
}

/// Sizes a card to a fraction of the scroll view's height, or leaves it to
/// its content when the fraction is nil.
private struct ViewportHeight: ViewModifier {
    let fraction: CGFloat?

    func body(content: Content) -> some View {
        if let fraction {
            content.containerRelativeFrame(.vertical) { height, _ in height * fraction }
        } else {
            content
        }
    }
}

/// Whether this launch has JIT: a green dot and "JIT" when it does, gray when
/// it doesn't, a spinner while it's being checked or turned on. Color is never
/// the only sign: the label says it too.
struct JITBadge: View {
    @Environment(JITSession.self) private var jit
    @ScaledMetric(relativeTo: .subheadline) private var dotSize = 8

    var body: some View {
        HStack(spacing: 6) {
            if jit.isTurningOn || jit.state == .checking {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(jit.isOn ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    .frame(width: dotSize, height: dotSize)
            }
            Text("JIT")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(jit.isOn ? .primary : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(jit.isOn ? "JIT is on" : jit.isTurningOn ? "Turning JIT on" : "JIT is off")
        .accessibilityHint("Shows JIT settings")
    }
}

/// Home with nothing installed: points at the Install tab.
struct EmptyHome: View {
    let onInstall: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No VMs Yet", systemImage: "shippingbox")
        } description: {
            Text("Install Debian or Arch Linux to get started. It downloads once, then runs right on this iPhone.")
        } actions: {
            Button(action: onInstall) {
                Label("Install a VM", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }
}
