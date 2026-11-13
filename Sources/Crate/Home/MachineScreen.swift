import SwiftUI

/// PLACEHOLDER for a running VM. The VM's display will fill this screen; for now
/// it shows the screenshot and a fake boot.
struct MachineScreen: View {
    let machine: Machine

    @Environment(MachineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(JITSession.self) private var jit
    @AppStorage(SettingsKey.jitMethod) private var jitMethod = JITMethod.standard.rawValue

    @State private var phase = Phase.starting
    @State private var confirmingStop = false

    enum Phase {
        case needsJIT
        case starting
        case running
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MachineScreenshot(machine: machine)
                .aspectRatio(4 / 3, contentMode: .fit)
                .padding()
                .opacity(phase == .running ? 1 : 0.3)
                .blur(radius: phase == .running ? 0 : 6)
            status
        }
        .overlay(alignment: .top) { topBar }
        .preferredColorScheme(.dark)
        .task(id: jit.isOn) { await boot() }
        .sheet(isPresented: Bindable(jit).showingSetup) {
            JITSetupView()
                .environment(jit)
                .preferredColorScheme(nil)
        }
    }

    /// Close before the VM runs; Stop, confirmed, once it does, since stopping
    /// a running VM loses whatever its guest hasn't saved.
    private var topBar: some View {
        HStack {
            if phase == .running {
                Button {
                    confirmingStop = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .confirmationDialog("Stop \(machine.name)?", isPresented: $confirmingStop,
                                    titleVisibility: .visible) {
                    Button("Stop VM", role: .destructive) { dismiss() }
                } message: {
                    Text("Anything not saved in \(machine.name) is lost.")
                }
            } else {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
            }
            Spacer()
            Text("\(machine.name) \(machine.version)")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .needsJIT:
            VStack(spacing: 14) {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.yellow)
                Text("JIT Is Off")
                    .font(.title2.bold())
                Text("crate needs JIT to run \(machine.name). Turn it on, then the VM starts.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await jit.turnOn(JITMethod(rawValue: jitMethod) ?? .standard) }
                } label: {
                    if jit.isTurningOn {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Turn On JIT", systemImage: "bolt.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(jit.isTurningOn)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding()
        case .starting:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Starting \(machine.name)…")
                    .font(.headline)
            }
        case .running:
            VStack {
                Spacer()
                Text("Placeholder: the VM's display goes here")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom)
            }
        }
    }

    private func boot() async {
        guard jit.isOn else {
            phase = .needsJIT
            return
        }
        phase = .starting
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        withAnimation { phase = .running }
        store.markStarted(machine)
    }
}
