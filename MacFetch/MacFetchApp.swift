import SwiftUI
import SwiftData

@main struct MacFetchApp: App {
    private let container: ModelContainer
    @StateObject private var manager: DownloadManager
    @AppStorage("confirmCapturedDownloads") private var confirmCapturedDownloads = true
    @State private var pendingDownload: PendingDownload?
    @Environment(\.openWindow) private var openWindow

    init() { let schema = Schema([DownloadRecord.self]); let container = try! ModelContainer(for: schema); self.container = container; _manager = StateObject(wrappedValue: DownloadManager(context: container.mainContext)) }

    var body: some Scene {
        WindowGroup("MacFetch", id: "main") {
            ContentView()
                .environmentObject(manager)
                .onOpenURL { handleIncomingURL($0) }
                .alert(item: $pendingDownload) { pending in
                    Alert(
                        title: Text("Confirm download"),
                        message: Text("MacFetch captured \(pending.url.lastPathComponent.nilIfEmpty ?? "this file"). Start downloading it?"),
                        primaryButton: .default(Text("Download")) {
                            manager.add(url: pending.url, destinationFolder: ContentView.downloadsFolder)
                        },
                        secondaryButton: .cancel()
                    )
                }
        }.modelContainer(container)
        MenuBarExtra("MacFetch", systemImage: "arrow.down.circle") {
            MenuBarDownloadsView(manager: manager, openWindow: openWindow)
        }.environmentObject(manager)
        Settings { SettingsView() }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "macfetch", url.host == "add", let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let value = components.queryItems?.first(where: { $0.name == "url" })?.value, let downloadURL = URL(string: value), ["http", "https"].contains(downloadURL.scheme) else { return }
        if confirmCapturedDownloads {
            pendingDownload = PendingDownload(url: downloadURL)
        } else {
            manager.add(url: downloadURL, destinationFolder: ContentView.downloadsFolder)
        }
    }
}

struct PendingDownload: Identifiable {
    let id = UUID()
    let url: URL
}

struct SettingsView: View {
    @AppStorage("confirmCapturedDownloads") private var confirmCapturedDownloads = true

    var body: some View {
        Form {
            Section("Chrome capture") {
                Toggle("Ask before downloading captured files", isOn: $confirmCapturedDownloads)
                Text("When enabled, MacFetch asks for confirmation after Chrome hands it a download URL. Disable this to start captured downloads automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }
}

struct MenuBarDownloadsView: View {
    @ObservedObject var manager: DownloadManager
    let openWindow: OpenWindowAction

    private var activeRecords: [DownloadRecord] {
        manager.records.filter { $0.state == .downloading || $0.state == .queued || $0.state == .paused }
    }

    var body: some View {
        Button("Open MacFetch") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
        Divider()

        if activeRecords.isEmpty {
            Text("No active downloads")
        } else {
            Text("Active downloads (\(activeRecords.count))")
                .font(.headline)
            ForEach(activeRecords) { record in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(record.fileName)
                            .lineLimit(1)
                        Spacer()
                        Text(record.state.label)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: record.progress)
                    HStack {
                        Text("\(Int(record.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if record.state == .downloading {
                            Button("Pause") { manager.pause(record) }
                        } else if record.state == .paused || record.state == .queued {
                            Button("Resume") { manager.start(record) }
                        }
                        Button("Stop", role: .destructive) { manager.cancel(record) }
                    }
                }
                .padding(.vertical, 3)
            }
        }

        Divider()
        Text("Speed: \(ByteCountFormatter.string(fromByteCount: Int64(manager.totalSpeed), countStyle: .file))/s")
            .foregroundStyle(.secondary)
        Button("Open Downloads") { NSWorkspace.shared.open(ContentView.downloadsFolder) }
        Divider()
        Button("Quit MacFetch") { NSApp.terminate(nil) }
    }
}
