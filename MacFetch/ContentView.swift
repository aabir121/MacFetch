import SwiftUI
import UniformTypeIdentifiers
import Charts
import AppKit

struct ContentView: View {
    @EnvironmentObject private var manager: DownloadManager
    @State private var section = "All"
    @State private var showingAnalyticsRecord = false
    @State private var showingDownloadDetail = false
    @State private var selected: DownloadRecord?
    @State private var selectedIDs = Set<UUID>()
    @State private var showingAdd = false
    @State private var search = ""
    @State private var typeFilter = "All types"
    @State private var sortOption = "Newest first"
    @State private var showingCustomRateLimit = false
    private let filters = ["All", "Downloading", "Queued", "Paused", "Completed", "Failed"]

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Overview", systemImage: "chart.xyaxis.line").tag("Overview")
                Label("Analytics", systemImage: "chart.bar.xaxis").tag("Analytics")
                Section("Downloads") {
                    ForEach(filters, id: \.self) { item in Label(item, systemImage: icon(item)).tag(item) }
                }
            }
                .navigationTitle("MacFetch")
                .safeAreaInset(edge: .bottom) { VStack(alignment: .leading) { Text("Total speed").font(.caption).foregroundStyle(.secondary); Text(ByteCountFormatter.string(fromByteCount: Int64(manager.totalSpeed), countStyle: .file) + "/s").font(.headline) }.frame(maxWidth: .infinity, alignment: .leading).padding() }
        } detail: {
            if section == "Overview" {
                AnalyticsDashboardView(onAdd: { showingAdd = true })
                    .navigationTitle("Overview")
            } else if section == "Analytics" {
                AnalyticsWorkspaceView(onOpenRecord: { selected = $0; showingAnalyticsRecord = true }, onExport: exportCSV)
                    .navigationTitle("Analytics")
            } else {
                VStack(spacing: 0) {
                HStack {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                    .keyboardShortcut("n")
                    .help("Add URL")
                    if !selectedIDs.isEmpty {
                        Text("\(selectedIDs.count)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help("\(selectedIDs.count) selected")
                        Menu {
                            Button("Pause") { manager.pause(records(for: selectedIDs)) }
                            Button("Resume") { manager.resume(records(for: selectedIDs)) }
                            Button("Stop", role: .destructive) { manager.cancel(records(for: selectedIDs)) }
                            Divider()
                            Button("Remove", role: .destructive) {
                                manager.remove(records(for: selectedIDs))
                                selectedIDs.removeAll()
                                selected = nil
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Bulk actions for selected downloads")
                    }
                    Spacer()
                    Menu {
                        Button("All types") { typeFilter = "All types" }
                        ForEach(typeOptions, id: \.self) { type in
                            Button(type) { typeFilter = type }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Filter by file type: \(typeFilter)")
                    Menu {
                        Button("Newest first") { sortOption = "Newest first" }
                        Button("Oldest first") { sortOption = "Oldest first" }
                        Button("Type A–Z") { sortOption = "Type A–Z" }
                        Button("Name A–Z") { sortOption = "Name A–Z" }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Sort: \(sortOption)")
                    Menu {
                        Button("Unlimited") { manager.setRateLimit(.unlimited) }
                        Divider()
                        ForEach(DownloadRateLimit.presets) { limit in
                            Button(limit.title) { manager.setRateLimit(limit) }
                        }
                        Divider()
                        Button("Custom…") { showingCustomRateLimit = true }
                    } label: {
                        Label(manager.rateLimit.title, systemImage: "gauge.with.dots.needle.67percent")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Transfer rate limit")
                    TextField("Search", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 80, idealWidth: 190, maxWidth: 220)
                }.padding()
                HStack(spacing: 0) {
                    Table(filtered, selection: $selectedIDs) {
                        TableColumn("State") { record in Text(record.state.label).foregroundStyle(stateColor(record)) }
                        TableColumn("Filename") { record in Text(record.fileName).lineLimit(1) }
                        TableColumn("Progress") { record in ProgressView(value: record.progress).frame(minWidth: 90) }
                        TableColumn("Size") { record in Text(sizeText(record)) }
                        TableColumn("Speed") { record in Text(speedText(record)) }
                        TableColumn("Elapsed Time") { record in Text(elapsedText(record)) }
                        TableColumn("Estimated…") { record in Text(etaText(record)) }
                        TableColumn("Type") { record in Text(record.fileType).foregroundStyle(.secondary) }
                    }
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let record = filtered.first(where: { ids.contains($0.id) }) {
                            Button("Show Details", systemImage: "chart.xyaxis.line") { selected = record; showingDownloadDetail = true }
                        }
                        Divider()
                        Button("Pause") { manager.pause(records(for: ids)) }
                        Button("Resume") { manager.resume(records(for: ids)) }
                        Button("Stop", role: .destructive) { manager.cancel(records(for: ids)) }
                    }
                    if showingDownloadDetail, let selected {
                        Divider()
                        VStack(alignment: .leading, spacing: 0) {
                            HStack { Text("Details").font(.headline); Spacer(); Button("Close", systemImage: "xmark") { showingDownloadDetail = false }.buttonStyle(.borderless) }.padding()
                            DetailView(record: selected).environmentObject(manager)
                        }
                        .frame(width: 360)
                    }
                }
                }
                .frame(minWidth: 820, minHeight: 420)
                .navigationTitle(section)
            }
        }
        .sheet(isPresented: $showingAdd) { AddDownloadView() }
        .onDrop(of: [.url], isTargeted: nil) { providers in for provider in providers { _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in manager.add(url: url, destinationFolder: Self.downloadsFolder) } } } }; return true }
        .sheet(isPresented: $showingAnalyticsRecord) { if let selected { DetailView(record: selected).environmentObject(manager).frame(width: 520, height: 520) } }
        .sheet(isPresented: $showingCustomRateLimit) { CustomRateLimitView(current: manager.rateLimit) { manager.setRateLimit($0); showingCustomRateLimit = false } }
    }
    private var typeOptions: [String] { Array(Set(manager.records.map(\.fileType))).sorted() }
    private var filtered: [DownloadRecord] {
        let matching = manager.records.filter {
            (section == "All" || $0.state.label == section) &&
            (typeFilter == "All types" || $0.fileType == typeFilter) &&
            (search.isEmpty || $0.fileName.localizedCaseInsensitiveContains(search))
        }
        switch sortOption {
        case "Oldest first": return matching.sorted { $0.createdAt < $1.createdAt }
        case "Type A–Z": return matching.sorted { $0.fileType.localizedStandardCompare($1.fileType) == .orderedAscending }
        case "Name A–Z": return matching.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        default: return matching.sorted { $0.createdAt > $1.createdAt }
        }
    }
    private func records(for ids: Set<UUID>) -> [DownloadRecord] { manager.records.filter { ids.contains($0.id) } }
    private func stateColor(_ record: DownloadRecord) -> Color { record.state == .completed ? .green : record.state == .failed ? .red : record.state == .paused ? .orange : .secondary }
    private func sizeText(_ record: DownloadRecord) -> String { ByteCountFormatter.string(fromByteCount: max(record.totalBytes, record.downloadedBytes), countStyle: .file) }
    private func speedText(_ record: DownloadRecord) -> String {
        let values = manager.samples.filter { $0.recordID == record.id && $0.speed > 0 }.map(\.speed)
        guard !values.isEmpty else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(values.reduce(0, +) / Double(values.count)), countStyle: .file) + "/s"
    }
    private func elapsedText(_ record: DownloadRecord) -> String {
        guard let start = record.startedAt else { return "—" }
        let end = record.completedAt ?? .now
        return formatDuration(end.timeIntervalSince(start))
    }
    private func etaText(_ record: DownloadRecord) -> String {
        guard record.totalBytes > 0, record.downloadedBytes < record.totalBytes, let start = record.startedAt else { return "—" }
        let elapsed = max(0.1, Date().timeIntervalSince(start)); let speed = Double(record.downloadedBytes) / elapsed
        guard speed > 0 else { return "—" }
        return formatDuration(Double(record.totalBytes - record.downloadedBytes) / speed)
    }
    private func formatDuration(_ seconds: TimeInterval) -> String { seconds < 60 ? String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) : String(format: "%02d:%02d:%02d", Int(seconds) / 3600, (Int(seconds) / 60) % 60, Int(seconds) % 60) }
    private func icon(_ name: String) -> String { ["All":"tray.full", "Downloading":"arrow.down.circle", "Queued":"clock", "Paused":"pause.circle", "Completed":"checkmark.circle", "Failed":"exclamationmark.circle" ][name] ?? "tray" }
    static var downloadsFolder: URL { DownloadPreferences.downloadFolder }

    private func exportCSV(_ csv: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "macfetch-analytics.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csv.data(using: .utf8)?.write(to: url)
        }
    }
}

struct DownloadGroup: Identifiable {
    let title: String
    let records: [DownloadRecord]
    var id: String { title.isEmpty ? "all" : title }
}

struct DownloadRow: View {
    @EnvironmentObject private var manager: DownloadManager; let record: DownloadRecord; @Binding var selected: DownloadRecord?
    var body: some View { HStack { Image(systemName: record.state == .completed ? "doc.fill" : record.state == .failed ? "exclamationmark.circle" : "arrow.down.doc").font(.title2).foregroundStyle(record.state == .failed ? Color.red : Color.accentColor); VStack(alignment: .leading) { Text(record.fileName).lineLimit(1).help(record.fileName); if record.state == .downloading || record.state == .queued || record.state == .paused { ProgressView(value: record.progress) }; Text("\(Int(record.progress * 100))% • \(record.state.label)").font(.caption).foregroundStyle(record.state == .failed ? Color.red : Color.secondary); if let errorMessage = record.errorMessage, record.state == .failed { Text(errorMessage).font(.caption2).foregroundStyle(Color.red).lineLimit(2) } }; Spacer(); if record.state == .downloading { Button("Pause", systemImage: "pause.fill") { manager.pause(record) }.buttonStyle(.borderless) } else if record.state == .paused || record.state == .queued { Button("Start", systemImage: "play.fill") { manager.start(record) }.buttonStyle(.borderless) } else if record.state == .failed { Button("Retry", systemImage: "arrow.clockwise") { manager.retry(record) }.buttonStyle(.borderless) } }.padding(.vertical, 6).contentShape(Rectangle()).onTapGesture { selected = record }.contextMenu { if record.state == .completed { Button("Reveal in Finder") { manager.reveal(record) }; Button("Open") { manager.open(record) } }; if record.state == .failed || record.state == .paused { Button("Retry") { manager.retry(record) } }; if record.state == .downloading { Button("Cancel", role: .destructive) { manager.cancel(record) } }; Button("Remove from list", role: .destructive) { manager.remove(record) } } }
}

struct AddDownloadView: View {
    @EnvironmentObject private var manager: DownloadManager; @Environment(\.dismiss) private var dismiss; @State private var text = ""
    var body: some View { VStack(alignment: .leading, spacing: 16) { Text("Add download").font(.title2); TextField("https://example.com/file.zip", text: $text); HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Download") { if let url = URL(string: text), ["http", "https"].contains(url.scheme) { manager.add(url: url, destinationFolder: ContentView.downloadsFolder); dismiss() } }.keyboardShortcut(.defaultAction) } }.padding(24).frame(width: 440) }
}

struct CustomRateLimitView: View {
    @Environment(\.dismiss) private var dismiss
    let current: DownloadRateLimit
    let onSave: (DownloadRateLimit) -> Void
    @State private var value: String
    @State private var unit = "MB/sec"

    init(current: DownloadRateLimit, onSave: @escaping (DownloadRateLimit) -> Void) {
        self.current = current; self.onSave = onSave
        let bytes = current.bytesPerSecond ?? 1_000_000
        _value = State(initialValue: bytes >= 1_000_000 ? String(format: "%.2f", bytes / 1_000_000) : String(format: "%.0f", bytes / 1_000))
        _unit = State(initialValue: bytes >= 1_000_000 ? "MB/sec" : "KB/sec")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom rate limit").font(.title2.bold())
            HStack {
                TextField("1.00", text: $value).textFieldStyle(.roundedBorder)
                Picker("Unit", selection: $unit) { Text("KB/sec").tag("KB/sec"); Text("MB/sec").tag("MB/sec") }.labelsHidden()
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func save() {
        guard let number = Double(value), number > 0 else { return }
        let limit = unit == "MB/sec" ? DownloadRateLimit.megabytes(max(0.01, number)) : DownloadRateLimit.kilobytes(max(1, number))
        onSave(limit); dismiss()
    }
}

struct DetailView: View { @EnvironmentObject private var manager: DownloadManager; let record: DownloadRecord; var body: some View { VStack(alignment: .leading, spacing: 18) { Label(record.fileName, systemImage: record.state == .failed ? "exclamationmark.circle" : "arrow.down.doc").font(.title2); if record.state != .failed && record.state != .cancelled { ProgressView(value: record.progress) }; HStack { metric("Progress", "\(Int(record.progress * 100))%"); metric("Status", record.state.label); metric("Size", ByteCountFormatter.string(fromByteCount: record.totalBytes, countStyle: .file)) }; if let errorMessage = record.errorMessage, record.state == .failed { Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled) }; Chart(Array(manager.speedSamples.enumerated()), id: \.offset) { item in LineMark(x: .value("Time", item.offset), y: .value("Speed", item.element)) }.frame(height: 180).chartYAxisLabel("Bytes/s"); Spacer() }.padding() }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline) } }
}
