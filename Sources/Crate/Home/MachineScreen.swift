import SwiftUI

/// A VM, full screen. With JIT on it boots in crate and shows either its screen
/// or its console, a terminal on the serial port, with a switch between them
/// in the top bar. Without JIT it offers to turn it on.
struct MachineScreen: View {
    let machine: Machine

    @Environment(MachineStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(JITSession.self) private var jit
    @Environment(MachineRunner.self) private var runner
    @AppStorage(SettingsKey.jitMethod) private var jitMethod = JITMethod.standard.rawValue

    @State private var confirmingStop = false
    @State private var showing = Showing.display
    @State private var showsKeyboard = false
    @State private var hasPicture = false

    /// The VM's screen, or its console.
    enum Showing: Hashable {
        case display
        case console
    }
    /// Debug builds pretending JIT is on have no code region to run in: they
    /// walk through a pretend boot instead.
    @State private var pretendRunning = false

    private var isThisMachine: Bool { runner.machineID == machine.id }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: jit.isOn) { boot() }
        .sheet(isPresented: Bindable(jit).showingSetup) {
            JITSetupView()
                .environment(jit)
                .preferredColorScheme(nil)
        }
    }

    private var isRunning: Bool {
        (isThisMachine && runner.isRunning) || pretendRunning
    }

    /// Stop, confirmed, while the VM runs, since it loses whatever its guest
    /// hasn't saved; Close otherwise.
    private var topBar: some View {
        HStack {
            if isRunning {
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
                    Button("Stop VM", role: .destructive) { stop() }
                } message: {
                    Text("Anything not saved in \(machine.name) is lost.")
                }
                if jit.region != nil {
                    switcher
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
        .padding(.vertical, 8)
    }

    /// Screen or console, and the keyboard while the screen shows.
    @ViewBuilder
    private var switcher: some View {
        Picker("Show", selection: $showing) {
            Label("Display", systemImage: "display").tag(Showing.display)
            Label("Terminal", systemImage: "apple.terminal").tag(Showing.console)
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .fixedSize()
        if showing == .display {
            Button(showsKeyboard ? "Hide Keyboard" : "Show Keyboard",
                   systemImage: showsKeyboard ? "keyboard.chevron.compact.down" : "keyboard") {
                showsKeyboard.toggle()
            }
            .labelStyle(.iconOnly)
            .font(.headline)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !jit.isOn {
            centered { needsJIT }
        } else if jit.region == nil {
            pretendBoot
        } else if isThisMachine {
            switch runner.phase {
            case .idle, .starting, .running:
                if showing == .display {
                    DisplayView(bridge: runner.display, showsKeyboard: $showsKeyboard, hasPicture: $hasPicture)
                        .overlay {
                            if !hasPicture {
                                VStack(spacing: 12) {
                                    ProgressView().controlSize(.large)
                                    Text("Starting the desktop…")
                                        .font(.headline)
                                    Text("The terminal shows the boot.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                } else {
                    ConsoleView(bridge: runner.console)
                }
            case .stopped(let message):
                centered { ended(message, failed: false) }
            case .failed(let message):
                centered { ended(message, failed: true) }
            }
        } else if runner.isRunning {
            centered {
                Text("Another VM is running. Stop it first: crate runs one VM at a time.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        } else {
            centered { ProgressView().controlSize(.large) }
        }
    }

    private func centered(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: 380)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var needsJIT: some View {
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func ended(_ message: String, failed: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: failed ? "exclamationmark.triangle.fill" : "power")
                .font(.system(size: 40))
                .foregroundStyle(failed ? .orange : .secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                boot()
            } label: {
                Label("Start Again", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    /// Debug builds pretending JIT is on: the screenshot and a pretend boot.
    private var pretendBoot: some View {
        ZStack {
            MachineScreenshot(machine: machine)
                .aspectRatio(4 / 3, contentMode: .fit)
                .padding()
                .opacity(pretendRunning ? 1 : 0.3)
                .blur(radius: pretendRunning ? 0 : 6)
            if !pretendRunning {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Starting \(machine.name)…")
                        .font(.headline)
                }
            }
        }
    }

    private func boot() {
        guard jit.isOn else { return }
        guard let region = jit.region else {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { pretendRunning = true }
            }
            return
        }
        // Already running this VM (the screen reopened), or another one.
        guard !runner.isRunning else { return }
        runner.start(machine, region: region)
        store.markStarted(machine)
    }

    private func stop() {
        if pretendRunning {
            pretendRunning = false
            dismiss()
            return
        }
        runner.stop()
    }
}
