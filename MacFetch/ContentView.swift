import SwiftUI
import UniformTypeIdentifiers
import Charts
import AppKit

struct ContentView: View {
    @EnvironmentObject private var manager: DownloadManager
    @State private var selected: DownloadRecord?
    @State private var selectedIDs = Set<UUID>()
    @State private var filter = "All"
    @State private var showingAdd = false
    @State private var search = ""
    private let filters = ["All", "Downloading", "Queued", "Paused", "Completed", "Failed"]

    var body: some View {
        NavigationSplitView {
            List(filters, id: \.self, selection: $filter) { item in Label(item, systemImage: icon(item)).tag(item) }
                .navigationTitle("MacFetch")
                .safeAreaInset(edge: .bottom) { VStack(alignment: .leading) { Text("Total speed").font(.caption).foregroundStyle(.secondary); Text(ByteCountFormatter.string(fromByteCount: Int64(manager.totalSpeed), countStyle: .file) + "/s").font(.headline) }.frame(maxWidth: .infinity, alignment: .leading).padding() }
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Button("Add URL", systemImage: "plus") { showingAdd = true }.keyboardShortcut("n")
                    if !selectedIDs.isEmpty {
                        Text("\(selectedIDs.count) selected").foregroundStyle(.secondary)
                        Button("Pause") { manager.pause(records(for: selectedIDs)) }
                        Button("Resume") { manager.resume(records(for: selectedIDs)) }
                        Button("Stop", role: .destructive) { manager.cancel(records(for: selectedIDs)) }
                        Button("Remove", role: .destructive) {
                            manager.remove(records(for: selectedIDs))
                            selectedIDs.removeAll()
                            selected = nil
                        }
                    }
                    Spacer()
                    TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 190)
                }.padding()
                List(filtered, selection: $selectedIDs) { record in
                    DownloadRow(record: record, selected: $selected).tag(record.id)
                }.listStyle(.inset)
            }.navigationTitle(filter)
        } detail: { if let selected { DetailView(record: selected) } else { ContentUnavailableView("Select a download", systemImage: "arrow.down.circle") } }
        .sheet(isPresented: $showingAdd) { AddDownloadView() }
        .onDrop(of: [.url], isTargeted: nil) { providers in for provider in providers { _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in manager.add(url: url, destinationFolder: Self.downloadsFolder) } } } }; return true }
    }
    private var filtered: [DownloadRecord] { manager.records.filter { (filter == "All" || $0.state.label == filter) && (search.isEmpty || $0.fileName.localizedCaseInsensitiveContains(search)) } }
    private func records(for ids: Set<UUID>) -> [DownloadRecord] { manager.records.filter { ids.contains($0.id) } }
    private func icon(_ name: String) -> String { ["All":"tray.full", "Downloading":"arrow.down.circle", "Queued":"clock", "Paused":"pause.circle", "Completed":"checkmark.circle", "Failed":"exclamationmark.circle" ][name] ?? "tray" }
    static var downloadsFolder: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }
}

struct DownloadRow: View {
    @EnvironmentObject private var manager: DownloadManager; let record: DownloadRecord; @Binding var selected: DownloadRecord?
    var body: some View { HStack { Image(systemName: record.state == .completed ? "doc.fill" : record.state == .failed ? "exclamationmark.circle" : "arrow.down.doc").font(.title2).foregroundStyle(record.state == .failed ? Color.red : Color.accentColor); VStack(alignment: .leading) { Text(record.fileName).lineLimit(1); if record.state == .downloading || record.state == .queued || record.state == .paused { ProgressView(value: record.progress) }; Text("\(Int(record.progress * 100))% • \(record.state.label)").font(.caption).foregroundStyle(record.state == .failed ? Color.red : Color.secondary); if let errorMessage = record.errorMessage, record.state == .failed { Text(errorMessage).font(.caption2).foregroundStyle(Color.red).lineLimit(2) } }; Spacer(); if record.state == .downloading { Button("Pause", systemImage: "pause.fill") { manager.pause(record) }.buttonStyle(.borderless) } else if record.state == .paused || record.state == .queued { Button("Start", systemImage: "play.fill") { manager.start(record) }.buttonStyle(.borderless) } else if record.state == .failed { Button("Retry", systemImage: "arrow.clockwise") { manager.retry(record) }.buttonStyle(.borderless) } }.padding(.vertical, 6).contentShape(Rectangle()).onTapGesture { selected = record }.contextMenu { if record.state == .completed { Button("Reveal in Finder") { manager.reveal(record) }; Button("Open") { manager.open(record) } }; if record.state == .failed || record.state == .paused { Button("Retry") { manager.retry(record) } }; if record.state == .downloading { Button("Cancel", role: .destructive) { manager.cancel(record) } }; Button("Remove from list", role: .destructive) { manager.remove(record) } } }
}

struct AddDownloadView: View {
    @EnvironmentObject private var manager: DownloadManager; @Environment(\.dismiss) private var dismiss; @State private var text = ""
    var body: some View { VStack(alignment: .leading, spacing: 16) { Text("Add download").font(.title2); TextField("https://example.com/file.zip", text: $text); HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Download") { if let url = URL(string: text), ["http", "https"].contains(url.scheme) { manager.add(url: url, destinationFolder: ContentView.downloadsFolder); dismiss() } }.keyboardShortcut(.defaultAction) } }.padding(24).frame(width: 440) }
}

struct DetailView: View { @EnvironmentObject private var manager: DownloadManager; let record: DownloadRecord; var body: some View { VStack(alignment: .leading, spacing: 18) { Label(record.fileName, systemImage: record.state == .failed ? "exclamationmark.circle" : "arrow.down.doc").font(.title2); if record.state != .failed && record.state != .cancelled { ProgressView(value: record.progress) }; HStack { metric("Progress", "\(Int(record.progress * 100))%"); metric("Status", record.state.label); metric("Size", ByteCountFormatter.string(fromByteCount: record.totalBytes, countStyle: .file)) }; if let errorMessage = record.errorMessage, record.state == .failed { Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled) }; Chart(Array(manager.speedSamples.enumerated()), id: \.offset) { item in LineMark(x: .value("Time", item.offset), y: .value("Speed", item.element)) }.frame(height: 180).chartYAxisLabel("Bytes/s"); Spacer() }.padding() }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline) } }
}
