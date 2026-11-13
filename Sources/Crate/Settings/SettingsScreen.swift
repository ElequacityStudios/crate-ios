import SwiftUI

/// JIT, memory and logs, then the stand-ins for what isn't wired in yet.
struct SettingsScreen: View {
    @Environment(MachineStore.self) private var store
    @Environment(JITSession.self) private var jit

    @AppStorage(SettingsKey.jitMethod) private var jitMethod = JITMethod.standard.rawValue
    @AppStorage(SettingsKey.jitAtLaunch) private var jitAtLaunch = true
    @AppStorage(SettingsKey.codeRegionMB) private var codeRegionMB = CodeRegion.standard

    @State private var memory = MemoryReport()
    @State private var logURL: URL?
    @State private var confirmingRemoveAll = false
    @ScaledMetric(relativeTo: .body) private var statusDotSize = 9

    var body: some View {
        NavigationStack {
            Form {
                jitSection
                memorySection
                logsSection
                #if DEBUG
                previewSection
                #endif
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
                        .fill(statusColor)
                        .frame(width: statusDotSize, height: statusDotSize)
                    Text(statusText)
                }
            }
            if !jit.isOn {
                Button {
                    Task { await jit.turnOn(JITMethod(rawValue: jitMethod) ?? .standard) }
                } label: {
                    HStack {
                        Label("Turn On JIT", systemImage: "bolt.fill")
                        if jit.isTurningOn {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(jit.isTurningOn || jit.state == .checking || jit.state == .off(.notEligible))
            }
            Picker("Method", selection: $jitMethod) {
                ForEach(JITMethod.allCases) { method in
                    Text(method.title).tag(method.rawValue)
                }
            }
            .pickerStyle(.menu)
            if selectedMethod == .builtInStikJIT {
                Button {
                    jit.showingSetup = true
                } label: {
                    LabeledContent {
                        Text(jit.isPaired ? "Paired" : "Not Set Up")
                    } label: {
                        Label("Set Up JIT", systemImage: "checklist")
                    }
                }
            }
            Toggle("Turn on JIT when crate opens", isOn: $jitAtLaunch)
            Picker("Code region", selection: $codeRegionMB) {
                ForEach(CodeRegion.choices, id: \.self) { mb in
                    Text("\(mb) MB").tag(mb)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("JIT")
        } footer: {
            Text(jitFooter)
        }
    }

    private var statusText: String {
        switch jit.state {
        case .checking: "Checking…"
        case .on(let mb): "On, \(mb) MB code region"
        case .off where jit.isOn: "Pretending On"
        case .off: "Off"
        case .failed: "Didn't Work"
        }
    }

    private var statusColor: Color {
        switch jit.state {
        case .on: .green
        case .failed: .orange
        case .off where jit.isOn: .green
        case .checking, .off: .gray
        }
    }

    private var selectedMethod: JITMethod {
        JITMethod(rawValue: jitMethod) ?? .standard
    }

    private var jitFooter: String {
        var parts: [String] = []
        if let problem = jit.problem { parts.append(problem) }
        switch selectedMethod {
        case .builtInStikJIT:
            parts.append("Built-in StikJIT needs this iPhone paired with crate and LocalDevVPN connected. Set Up JIT walks through both.")
        case .stikDebug:
            parts.append("StikDebug opens, asks you to confirm, then brings you back to crate.")
        }
        parts.append("crate needs JIT to run a VM. The code region is the memory set aside for translated code, claimed once per launch, so a change applies the next time crate opens.")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Memory

    private var memorySection: some View {
        Section {
            LabeledContent("Increased limit",
                           value: memory.hasIncreasedLimit ? "Yes" : "No")
            LabeledContent("Memory limit") {
                Text(memory.limit.map { Format.memory($0) } ?? "Not reported")
                    .monospacedDigit()
            }
            LabeledContent("Available memory") {
                Text(memory.available.map { Format.memory($0, decimals: 2) } ?? "Not reported")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            LabeledContent("Total memory") {
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
        return "A VM's memory comes out of the available memory, up to the limit iOS sets. The increased-memory-limit entitlement raises the limit."
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
            Text("Shares a file with what crate and the VM engine logged this launch, for a bug report.")
        }
    }

    // MARK: - UI preview

    /// STUB controls, for seeing every state of the UI before the parts behind
    /// it exist. Debug builds only; remove once JIT and installs are real.
    private var previewSection: some View {
        Section {
            Toggle("Pretend JIT Is On", isOn: Bindable(jit).pretending)
            Button("Restore Sample VMs") { store.restoreSamples() }
            Button("Remove All VMs", role: .destructive) { confirmingRemoveAll = true }
                .confirmationDialog("Remove all VMs?", isPresented: $confirmingRemoveAll,
                                    titleVisibility: .visible) {
                    Button("Remove All VMs", role: .destructive) { store.removeAll() }
                } message: {
                    Text("Their disks are removed from this iPhone. This can't be undone.")
                }
        } header: {
            Text("UI Preview")
        } footer: {
            Text("Stand-ins for parts that aren't wired in yet. Pretending JIT is on shows the screens that need it; relaunch to see the default VM boot.")
        }
    }
}
