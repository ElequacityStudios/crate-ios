import SwiftUI

/// One VM's settings, from its card's menu. So far only how its screen sits on
/// iPhone Duo, so the menu offers it only there.
struct MachineSettingsSheet: View {
    let machine: Machine

    @Environment(MachineStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Full Width in Landscape", isOn: fullWidth)
                } header: {
                    Text("Display")
                } footer: {
                    Text("With iPhone Duo open in landscape, the desktop runs under the toolbar to the edge of the screen, the toolbar's buttons over it. Off, it stops beside them.")
                }
            }
            .navigationTitle("\(machine.name) Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Saved as it changes, from the store's copy: the sheet's own may be stale.
    private var fullWidth: Binding<Bool> {
        Binding(
            get: { current.isFullWidthInLandscape },
            set: { on in
                var changed = current
                changed.fullWidthInLandscape = on
                store.update(changed)
            })
    }

    private var current: Machine {
        store.machines.first { $0.id == machine.id } ?? machine
    }
}
