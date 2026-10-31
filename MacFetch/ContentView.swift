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
    @State private var typeFilter = "All types"
    @State private var sortOption = "Newest first"
    @State private var groupOption = "None"
    private let filters = ["All", "Downloading", "Queued", "Paused", "Completed", "Failed"]

    var body: some View {
        NavigationSplitView {
            List(filters, id: \.self, selection: $filter) { item in Label(item, systemImage: icon(item)).tag(item) }
                .navigationTitle("MacFetch")
                .safeAreaInset(edge: .bottom) { VStack(alignment: .leading) { Text("Total speed").font(.caption).foregroundStyle(.secondary); Text(ByteCountFormatter.string(fromByteCount: Int64(manager.totalSpeed), countStyle: .file) + "/s").font(.headline) }.frame(maxWidth: .infinity, alignment: .leading).padding() }
        } content: {
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
                        Button("No grouping") { groupOption = "None" }
                        Button("Group by type") { groupOption = "Type" }
                        Button("Group by day") { groupOption = "Day" }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Group: \(groupOption)")
                    TextField("Search", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 80, idealWidth: 190, maxWidth: 220)
                }.padding()
                List(selection: $selectedIDs) {
                    ForEach(groups) { group in
                        if groupOption == "None" {
                            ForEach(group.records) { record in
                                DownloadRow(record: record, selected: $selected).tag(record.id)
                            }
                        } else {
                            Section(group.title) {
                                ForEach(group.records) { record in
                                    DownloadRow(record: record, selected: $selected).tag(record.id)
                                }
                            }
                        }
                    }
                }.listStyle(.inset)
            }.navigationTitle(filter)
        } detail: { if let selected { DetailView(record: selected) } else { ContentUnavailableView("Select a download", systemImage: "arrow.down.circle") } }
        .sheet(isPresented: $showingAdd) { AddDownloadView() }
        .onDrop(of: [.url], isTargeted: nil) { providers in for provider in providers { _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in manager.add(url: url, destinationFolder: Self.downloadsFolder) } } } }; return true }
    }
    private var typeOptions: [String] { Array(Set(manager.records.map(\.fileType))).sorted() }
    private var filtered: [DownloadRecord] {
        let matching = manager.records.filter {
            (filter == "All" || $0.state.label == filter) &&
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
    private var groups: [DownloadGroup] {
        guard groupOption != "None" else { return [DownloadGroup(title: "", records: filtered)] }
        if groupOption == "Type" {
            let grouped = Dictionary(grouping: filtered, by: \.fileType)
            return grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { DownloadGroup(title: $0, records: grouped[$0] ?? []) }
        }
        let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >)
            .map { DownloadGroup(title: dayKey(for: $0), records: grouped[$0] ?? []) }
    }
    private func dayKey(for date: Date) -> String { DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none) }
    private func records(for ids: Set<UUID>) -> [DownloadRecord] { manager.records.filter { ids.contains($0.id) } }
    private func icon(_ name: String) -> String { ["All":"tray.full", "Downloading":"arrow.down.circle", "Queued":"clock", "Paused":"pause.circle", "Completed":"checkmark.circle", "Failed":"exclamationmark.circle" ][name] ?? "tray" }
    static var downloadsFolder: URL { DownloadPreferences.downloadFolder }
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

struct DetailView: View { @EnvironmentObject private var manager: DownloadManager; let record: DownloadRecord; var body: some View { VStack(alignment: .leading, spacing: 18) { Label(record.fileName, systemImage: record.state == .failed ? "exclamationmark.circle" : "arrow.down.doc").font(.title2); if record.state != .failed && record.state != .cancelled { ProgressView(value: record.progress) }; HStack { metric("Progress", "\(Int(record.progress * 100))%"); metric("Status", record.state.label); metric("Size", ByteCountFormatter.string(fromByteCount: record.totalBytes, countStyle: .file)) }; if let errorMessage = record.errorMessage, record.state == .failed { Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled) }; Chart(Array(manager.speedSamples.enumerated()), id: \.offset) { item in LineMark(x: .value("Time", item.offset), y: .value("Speed", item.element)) }.frame(height: 180).chartYAxisLabel("Bytes/s"); Spacer() }.padding() }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline) } }
}
