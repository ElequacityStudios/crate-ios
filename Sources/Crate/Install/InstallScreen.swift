import SwiftUI

/// Pick a system image and a memory limit, then install it.
struct InstallScreen: View {
    @Environment(MachineStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    let onShowHome: () -> Void

    @State private var selectedID = CatalogImage.catalog[0].id
    @AppStorage(SettingsKey.installMemoryGB) private var memoryGB = 6
    @State private var install = InstallProgress.idle
    @State private var installTask: Task<Void, Never>?
    @State private var confirmingCancel = false

    private let memoryChoices = [4, 6, 8]

    private var selected: CatalogImage {
        CatalogImage.catalog.first { $0.id == selectedID } ?? CatalogImage.catalog[0]
    }

    /// Nil when iOS doesn't say, in which case Install stays available.
    private var freeBytes: Int64? { Format.freeDiskBytes() }

    private var hasRoom: Bool {
        freeBytes.map { $0 >= selected.installedBytes } ?? true
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

                // At the accessibility text sizes a pinned bar would cover half
                // the screen, so Install scrolls with the list instead.
                if typeSize.isAccessibilitySize {
                    Section {
                        installControls
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Install Vms")
            .safeAreaInset(edge: .bottom) {
                if !typeSize.isAccessibilitySize {
                    installControls
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                        .background(.bar)
                }
            }
            .onChange(of: selectedID) {
                // A finished install belongs to the image it was for.
                if case .done = install { install = .idle }
            }
            .alert(install.cancelTitle(for: selected), isPresented: $confirmingCancel) {
                Button(install.cancelButton, role: .destructive, action: cancel)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(install.cancelMessage(for: selected))
            }
        }
    }

    private var memoryFooter: String {
        var text = "The most memory the VM may use. You can change it later."
        if let limit = MemoryReport().limit, UInt64(memoryGB) << 30 > limit {
            text += " Crate can only claim \(Format.memory(limit)) on this iPhone, so the VM gets less."
        }
        return text
    }

    // MARK: - Install controls

    @ViewBuilder
    private var installControls: some View {
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
                .disabled(!hasRoom)
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
                        Button("Cancel") { confirmingCancel = true }
                    }
                    ProgressView(value: fraction)
                    Text(install.detail(for: selected))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            case .done(let image):
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("\(image.name) is installed")
                            .font(.headline)
                        Text("It's on Home, ready to start.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Go to Home") {
                        install = .idle
                        onShowHome()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }
        }
    }

    private var spaceNeeded: String {
        guard let free = freeBytes else {
            return "Needs \(Format.bytes(selected.installedBytes)) of storage"
        }
        if !hasRoom {
            return "Free up \(Format.bytes(selected.installedBytes - free)) to install \(selected.name)."
        }
        return "Needs \(Format.bytes(selected.installedBytes)) of storage · \(Format.bytes(free)) available"
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
            // Finished while "Stop Download?" was up: nothing left to stop.
            confirmingCancel = false
            withAnimation { install = .done(image) }
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
    case done(CatalogImage)

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

    // Cancelling throws the download away, so it's confirmed first.

    func cancelTitle(for image: CatalogImage) -> String {
        switch self {
        case .installing: "Stop Installing \(image.name)?"
        default: "Stop Downloading \(image.name)?"
        }
    }

    var cancelButton: String {
        switch self {
        case .installing: "Stop Installing"
        default: "Stop Download"
        }
    }

    func cancelMessage(for image: CatalogImage) -> String {
        switch self {
        case .downloading(let fraction):
            let done = Int64(Double(image.downloadBytes) * fraction)
            return "The \(Format.bytes(done)) downloaded so far is discarded."
        default:
            return "The download is discarded, and starts over next time."
        }
    }
}

/// One downloadable image: badge, name with the version beside it, and a check
/// when selected. At the accessibility text sizes the text goes under the
/// badge, so the name has the row's full width.
struct CatalogRow: View {
    let image: CatalogImage
    let isSelected: Bool
    let isInstalled: Bool
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onSelect) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            DistributionBadge(distribution: image.distribution, size: 44)
                            Spacer(minLength: 0)
                            checkmark
                        }
                        text
                    }
                } else {
                    HStack(spacing: 14) {
                        DistributionBadge(distribution: image.distribution, size: 44)
                        text
                        Spacer(minLength: 0)
                        checkmark
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            let nameAndVersion = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            nameAndVersion {
                Text(image.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                Text(image.version)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            Text(details)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
    }

    /// "Xfce · 1.5 GB", and "· Installed" once there's a copy on Home.
    private var details: String {
        var parts = [image.desktop, Format.bytes(image.downloadBytes)]
        if isInstalled { parts.append("Installed") }
        return parts.joined(separator: " · ")
    }

    private var checkmark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
    }
}
