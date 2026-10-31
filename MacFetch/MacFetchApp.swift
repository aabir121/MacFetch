import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main struct MacFetchApp: App {
    private let container: ModelContainer
    @StateObject private var manager: DownloadManager
    @AppStorage("confirmCapturedDownloads") private var confirmCapturedDownloads = true
    @State private var pendingDownload: PendingDownload?
    @Environment(\.openWindow) private var openWindow

    init() { let schema = Schema([DownloadRecord.self, DownloadSample.self]); let container = try! ModelContainer(for: schema); self.container = container; _manager = StateObject(wrappedValue: DownloadManager(context: container.mainContext)) }

    var body: some Scene {
        WindowGroup("MacFetch", id: "main") {
            ContentView()
                .environmentObject(manager)
                .onOpenURL { handleIncomingURL($0) }
                .alert(item: $pendingDownload) { pending in
                    Alert(
                        title: Text("Confirm download"),
                        message: Text("MacFetch captured \(pending.fileName). Start downloading it?"),
                        primaryButton: .default(Text("Download")) {
                            manager.add(url: pending.url, destinationFolder: ContentView.downloadsFolder, fileName: pending.fileName)
                        },
                        secondaryButton: .cancel()
                    )
                }
        }.modelContainer(container)
        MenuBarExtra("MacFetch", systemImage: "arrow.down.circle") {
            MenuBarDownloadsView(manager: manager, openWindow: openWindow)
        }
        .menuBarExtraStyle(.window)
        .environmentObject(manager)
        Settings { SettingsView() }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "macfetch", url.host == "add", let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let value = components.queryItems?.first(where: { $0.name == "url" })?.value, let downloadURL = URL(string: value), ["http", "https"].contains(downloadURL.scheme) else { return }
        let fileName = components.queryItems?.first(where: { $0.name == "filename" })?.value.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nilIfEmpty } ?? downloadURL.lastPathComponent.nilIfEmpty ?? "download"
        if confirmCapturedDownloads {
            pendingDownload = PendingDownload(url: downloadURL, fileName: fileName)
        } else {
            manager.add(url: downloadURL, destinationFolder: ContentView.downloadsFolder, fileName: fileName)
        }
    }
}

struct PendingDownload: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
}

struct SettingsView: View {
    @AppStorage("confirmCapturedDownloads") private var confirmCapturedDownloads = true
    @AppStorage(DownloadPreferences.downloadLocationKey) private var downloadLocationPath = DownloadPreferences.defaultFolder.path
    @State private var showingFolderPicker = false

    var body: some View {
        Form {
            Section("Chrome capture") {
                Toggle("Ask before downloading captured files", isOn: $confirmCapturedDownloads)
                Text("When enabled, MacFetch asks for confirmation after Chrome hands it a download URL. Disable this to start captured downloads automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Downloads") {
                HStack {
                    Text("Location")
                    Spacer()
                    Text(downloadLocationPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Choose Folder…") { showingFolderPicker = true }
                    Button("Reset") { downloadLocationPath = DownloadPreferences.defaultFolder.path }
                }
                Text("New downloads will be saved here. Existing downloads keep their current destination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let folder = urls.first {
                downloadLocationPath = folder.path
            }
        }
    }
}

struct MenuBarDownloadsView: View {
    @ObservedObject var manager: DownloadManager
    let openWindow: OpenWindowAction

    private var activeRecords: [DownloadRecord] {
        manager.records.filter { $0.state == .downloading || $0.state == .queued || $0.state == .paused }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
        Button("Open MacFetch") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
        Divider()

        if activeRecords.isEmpty {
            Text("No active downloads")
        } else {
            Text("Active downloads (\(activeRecords.count))")
                .font(.headline)
            ForEach(activeRecords) { record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.tint)
                        Text(record.fileName)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(record.fileName)
                        Spacer()
                        Text(record.state.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: record.progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(width: 300)
                    HStack {
                        Text("\(Int(record.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if record.state == .downloading {
                            Button { manager.pause(record) } label: {
                                Image(systemName: "pause.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Pause download")
                        } else if record.state == .paused || record.state == .queued {
                            Button { manager.start(record) } label: {
                                Image(systemName: "play.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Resume download")
                        }
                        Button(role: .destructive) { manager.cancel(record) } label: {
                            Image(systemName: "stop.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop download")
                    }
                }
                .padding(7)
                .frame(width: 320, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }

        Divider()
        Text("Speed: \(ByteCountFormatter.string(fromByteCount: Int64(manager.totalSpeed), countStyle: .file))/s")
            .foregroundStyle(.secondary)
        Button("Open Downloads") { NSWorkspace.shared.open(ContentView.downloadsFolder) }
        Divider()
        Button("Quit MacFetch") { NSApp.terminate(nil) }
        }
    .frame(width: 340)
    .padding(12)
    }
}
