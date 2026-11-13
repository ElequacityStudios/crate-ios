import SwiftUI

/// Pick a system image and a memory limit, then install it.
struct InstallScreen: View {
    @Environment(MachineStore.self) private var store

    let onShowHome: () -> Void

    @State private var selectedID = CatalogImage.catalog[0].id
    @AppStorage(SettingsKey.installMemoryGB) private var memoryGB = 6
    @State private var install = InstallProgress.idle
    @State private var installTask: Task<Void, Never>?

    private let memoryChoices = [4, 6, 8]

    private var selected: CatalogImage {
        CatalogImage.catalog.first { $0.id == selectedID } ?? CatalogImage.catalog[0]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(CatalogImage.catalog) { image in
                        CatalogRow(
                            image: image,
                            isSelected: image.id == selectedID,
                            isInstalled: store.isInstalled(image)
                        ) {
                            selectedID = image.id
                        }
                    }
                } header: {
                    Text("Linux")
                }
                .disabled(install.isBusy)

                Section {
                    Picker("Memory limit", selection: $memoryGB) {
                        ForEach(memoryChoices, id: \.self) { gb in
                            Text("\(gb) GB").tag(gb)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Memory Limit")
                } footer: {
                    Text(memoryFooter)
                }
                .disabled(install.isBusy)
            }
            .navigationTitle("Install Vms")
            .safeAreaInset(edge: .bottom) { installBar }
        }
    }

    private var memoryFooter: String {
        var text = "The most memory the VM may use. You can change it later."
        if let limit = MemoryReport().limit, UInt64(memoryGB) << 30 > limit {
            text += " Crate can only claim \(Format.memory(limit)) on this iPhone, so the VM gets less."
        }
        return text
    }

    // MARK: - Install bar

    private var installBar: some View {
        VStack(spacing: 8) {
            switch install {
            case .idle:
                Button(action: start) {
                    Label("Install \(selected.name)", systemImage: "arrow.down.circle.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                Text(spaceNeeded)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .downloading(let fraction), .installing(let fraction):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(install.title(for: selected))
                            .font(.headline)
                        Spacer()
                        Button("Cancel", role: .cancel, action: cancel)
                    }
                    ProgressView(value: fraction)
                    Text(install.detail(for: selected))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            case .done:
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("\(selected.name) is installed")
                            .font(.headline)
                        Text("It's on Home, ready to start.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show") {
                        install = .idle
                        onShowHome()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.bar)
    }

    private var spaceNeeded: String {
        var text = "Needs \(Format.bytes(selected.installedBytes)) of storage"
        if let free = Format.freeDiskBytes() {
            text += " · \(Format.bytes(free)) available"
        }
        return text
    }

    // MARK: - Fake install

    /// STUB: walks a progress bar over a few seconds, then adds the VM to Home.
    private func start() {
        let image = selected
        let memory = memoryGB
        installTask = Task {
            for step in 0...40 {
                install = .downloading(Double(step) / 40)
                try? await Task.sleep(for: .milliseconds(90))
                if Task.isCancelled { return }
            }
            for step in 0...10 {
                install = .installing(Double(step) / 10)
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { return }
            }
            store.add(image.machine(memoryGB: memory))
            withAnimation { install = .done }
        }
    }

    private func cancel() {
        installTask?.cancel()
        installTask = nil
        install = .idle
    }
}

/// Where a fake install has got to.
enum InstallProgress: Equatable {
    case idle
    case downloading(Double)
    case installing(Double)
    case done

    var isBusy: Bool {
        switch self {
        case .downloading, .installing: true
        case .idle, .done: false
        }
    }

    func title(for image: CatalogImage) -> String {
        switch self {
        case .downloading: "Downloading \(image.name)…"
        case .installing: "Installing \(image.name)…"
        case .idle, .done: ""
        }
    }

    func detail(for image: CatalogImage) -> String {
        switch self {
        case .downloading(let fraction):
            let done = Int64(Double(image.downloadBytes) * fraction)
            return "\(Format.bytes(done)) of \(Format.bytes(image.downloadBytes))"
        case .installing:
            return "Unpacking the disk image"
        case .idle, .done:
            return ""
        }
    }
}

/// One downloadable image: badge, name with the version beside it, and a check
/// when selected.
struct CatalogRow: View {
    let image: CatalogImage
    let isSelected: Bool
    let isInstalled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                DistributionBadge(distribution: image.distribution, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(image.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .layoutPriority(1)
                        Text(image.version)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(image.desktop) · \(Format.bytes(image.downloadBytes))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if isInstalled {
                            Text("Installed")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.fill.tertiary, in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
