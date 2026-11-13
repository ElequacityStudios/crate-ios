import SwiftUI

/// JIT, memory and logs, then the stand-ins for what isn't wired in yet.
struct SettingsScreen: View {
    @Environment(MachineStore.self) private var store

    @AppStorage(SettingsKey.stubJITEnabled) private var jitEnabled = false
    @AppStorage(SettingsKey.jitMethod) private var jitMethod = JITMethod.standard.rawValue
    @AppStorage(SettingsKey.jitAtLaunch) private var jitAtLaunch = true
    @AppStorage(SettingsKey.codeRegionMB) private var codeRegionMB = CodeRegion.standard

    @State private var memory = MemoryReport()
    @State private var logURL: URL?
    @State private var turningOnJIT = false

    var body: some View {
        NavigationStack {
            Form {
                jitSection
                memorySection
                logsSection
                previewSection
            }
            .navigationTitle("Settings")
            .task { await refreshMemory() }
            .onAppear { logURL = LogExport.prepare() }
        }
    }

    // MARK: - JIT

    private var jitSection: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(jitEnabled ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 9, height: 9)
                    Text(jitEnabled ? "On" : "Off")
                }
            }
            if !jitEnabled {
                Button(action: turnOnJIT) {
                    HStack {
                        Label("Turn On JIT", systemImage: "bolt.fill")
                        if turningOnJIT {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(turningOnJIT)
            }
            Picker("Method", selection: $jitMethod) {
                ForEach(JITMethod.allCases) { method in
                    Text(method.title).tag(method.rawValue)
                }
            }
            .pickerStyle(.menu)
            Toggle("Turn on JIT when Crate opens", isOn: $jitAtLaunch)
            Picker("Code region", selection: $codeRegionMB) {
                ForEach(CodeRegion.choices, id: \.self) { mb in
                    Text("\(mb) MB").tag(mb)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("JIT")
        } footer: {
            Text("Crate needs JIT to run a VM. The code region is the memory set aside for translated code, claimed once per launch, so a change applies the next time Crate opens.")
        }
    }

    // MARK: - Memory

    private var memorySection: some View {
        Section {
            LabeledContent("Increased memory limit",
                           value: memory.hasIncreasedLimit ? "Yes" : "No")
            LabeledContent("Most Crate can claim") {
                Text(memory.limit.map(Format.memory) ?? "Not reported")
                    .monospacedDigit()
            }
            LabeledContent("Free for Crate now") {
                Text(memory.available.map(Format.memory) ?? "Not reported")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            LabeledContent("Memory in this iPhone") {
                Text(Format.memory(memory.physical))
                    .monospacedDigit()
            }
        } header: {
            Text("Memory")
        } footer: {
            Text(memoryFooter)
        }
    }

    private var memoryFooter: String {
        if memory.available == nil {
            return "The Simulator has no memory limit, so iOS reports nothing here. On an iPhone these come from iOS and update every few seconds."
        }
        return "A VM's memory comes out of what Crate can claim. iOS sets that limit; the increased-memory-limit entitlement raises it."
    }

    /// Re-reads the figures every few seconds while Settings is on screen.
    private func refreshMemory() async {
        while !Task.isCancelled {
            withAnimation { memory = MemoryReport() }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    // MARK: - Logs

    private var logsSection: some View {
        Section {
            if let logURL {
                ShareLink(item: logURL) {
                    Label("Export Logs", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Logs")
        } footer: {
            Text("Shares a file with what Crate and the VM engine logged this launch, for a bug report.")
        }
    }

    // MARK: - UI preview

    /// STUB controls, for seeing every state of the UI before the parts behind
    /// it exist. Remove once JIT and installs are real.
    private var previewSection: some View {
        Section {
            Toggle("JIT is on", isOn: $jitEnabled)
            Button("Restore Sample VMs") { store.restoreSamples() }
            Button("Remove All VMs", role: .destructive) { store.removeAll() }
        } header: {
            Text("UI Preview")
        } footer: {
            Text("Stand-ins for parts that aren't wired in yet. Relaunch Crate with JIT on to see the default VM boot.")
        }
    }

    /// STUB: pretends the selected method turned JIT on.
    private func turnOnJIT() {
        turningOnJIT = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            turningOnJIT = false
            withAnimation { jitEnabled = true }
        }
    }
}
