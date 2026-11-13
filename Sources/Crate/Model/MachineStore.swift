import Foundation
import Observation

/// The installed VMs and which one is the default.
///
/// Persisted to UserDefaults as JSON so fake installs survive a relaunch. When
/// installs are real this becomes a listing of the VMs' directories on disk.
@Observable
final class MachineStore {
    private(set) var machines: [Machine] {
        didSet { save() }
    }

    /// The VM that boots at launch when JIT is on.
    var defaultID: UUID? {
        didSet { UserDefaults.standard.set(defaultID?.uuidString, forKey: Self.defaultKey) }
    }

    private static let machinesKey = "machines"
    private static let defaultKey = "defaultMachineID"

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.machinesKey),
           let saved = try? JSONDecoder().decode([Machine].self, from: data) {
            machines = saved
            defaultID = defaults.string(forKey: Self.defaultKey).flatMap(UUID.init)
        } else {
            // First launch: the sample VMs, with Debian as the default.
            machines = Machine.samples
            defaultID = Machine.samples.first?.id
            save()
            defaults.set(defaultID?.uuidString, forKey: Self.defaultKey)
        }
    }

    var defaultMachine: Machine? {
        machines.first { $0.id == defaultID }
    }

    func isDefault(_ machine: Machine) -> Bool {
        machine.id == defaultID
    }

    /// Stars `machine`, or clears the star if it already has it.
    func toggleDefault(_ machine: Machine) {
        defaultID = isDefault(machine) ? nil : machine.id
    }

    func add(_ machine: Machine) {
        machines.append(machine)
        if defaultID == nil { defaultID = machine.id }
    }

    func delete(_ machine: Machine) {
        machines.removeAll { $0.id == machine.id }
        if isDefault(machine) { defaultID = nil }
    }

    func markStarted(_ machine: Machine) {
        guard let index = machines.firstIndex(where: { $0.id == machine.id }) else { return }
        machines[index].lastStarted = .now
    }

    func isInstalled(_ image: CatalogImage) -> Bool {
        machines.contains { $0.distributionID == image.distributionID }
    }

    /// Puts the sample VMs back, for previewing the UI.
    func restoreSamples() {
        machines = Machine.samples.map { var copy = $0; copy.id = UUID(); return copy }
        defaultID = machines.first?.id
    }

    func removeAll() {
        machines = []
        defaultID = nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(machines) {
            UserDefaults.standard.set(data, forKey: Self.machinesKey)
        }
    }
}
