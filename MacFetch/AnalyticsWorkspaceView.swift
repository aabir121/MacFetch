import SwiftUI
import Charts
import AppKit

struct AnalyticsWorkspaceView: View {
    @EnvironmentObject private var manager: DownloadManager
    let onOpenRecord: (DownloadRecord) -> Void
    let onExport: (String) -> Void
    @State private var filter = AnalyticsWorkspaceFilter()
    @State private var rangePreset = "7 days"
    @State private var selectedDate: Date?
    @State private var selectedRecordID: UUID?
    @State private var showCustomRange = false
    @State private var showComparison = true
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
    @State private var customEnd = Date()

    private var range: AnalyticsRange {
        switch rangePreset { case "Today": return .today; case "30 days": return .days(30); case "Custom": return .custom(customStart, customEnd); default: return .days(7) }
    }
    private var snapshot: AnalyticsWorkspaceSnapshot {
        var current = filter; current.range = range
        return DownloadAnalytics.workspaceSnapshot(records: manager.records, samples: manager.samples, filter: current)
    }
    private var typeOptions: [String] { Array(Set(manager.records.map(\.fileType))).sorted() }
    private var domainOptions: [String] { Array(Set(manager.records.map { DownloadAnalytics.sourceDomain(for: $0) })).sorted() }
    private let statuses = ["Completed", "Failed", "Cancelled", "Paused", "In progress"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                filterRail
                kpis
                HStack(alignment: .top, spacing: 16) { volumeCard; speedCard }
                HStack(alignment: .top, spacing: 16) { outcomesCard; breakdownCard }
                activityTable
            }
            .padding(24)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedDate) { _, value in filter.selectedBucket = value }
        .onChange(of: rangePreset) { _, _ in selectedDate = nil }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) { Text("Analytics").font(.largeTitle.bold()); Text("Slice your download history and find the patterns").foregroundStyle(.secondary) }
            Spacer()
            Picker("Range", selection: $rangePreset) { ForEach(["Today", "7 days", "30 days", "Custom"], id: \.self, content: Text.init) }.pickerStyle(.segmented).frame(width: 330)
            Toggle("Compare", isOn: $showComparison).toggleStyle(.switch)
            Button("Export CSV", systemImage: "square.and.arrow.up") { onExport(snapshot.csv) }
        }
        .overlay(alignment: .bottomTrailing) {
            if rangePreset == "Custom" { HStack { DatePicker("From", selection: $customStart, displayedComponents: .date); DatePicker("To", selection: $customEnd, displayedComponents: .date) }.font(.caption).padding(.top, 52) }
        }
    }

    private var filterRail: some View {
        HStack(spacing: 8) {
            filterMenu(title: "File type", options: typeOptions, selection: $filter.fileTypes)
            filterMenu(title: "Status", options: statuses, selection: $filter.statuses)
            filterMenu(title: "Source", options: domainOptions, selection: $filter.domains)
            Picker("Breakdown", selection: $filter.breakdown) { ForEach(AnalyticsBreakdown.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
            if filter.selectedBucket != nil { Button("Selected day", systemImage: "xmark.circle.fill") { selectedDate = nil }.buttonStyle(.borderless) }
            if !filter.fileTypes.isEmpty || !filter.statuses.isEmpty || !filter.domains.isEmpty || filter.selectedBucket != nil { Button("Clear filters") { filter.fileTypes.removeAll(); filter.statuses.removeAll(); filter.domains.removeAll(); selectedDate = nil }.buttonStyle(.borderless).foregroundStyle(.secondary) }
            Spacer()
            Text("\(snapshot.records.count) records").font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func filterMenu(title: String, options: [String], selection: Binding<Set<String>>) -> some View {
        Menu { ForEach(options, id: \.self) { option in Button { if selection.wrappedValue.contains(option) { selection.wrappedValue.remove(option) } else { selection.wrappedValue.insert(option) } } label: { Label(option, systemImage: selection.wrappedValue.contains(option) ? "checkmark" : "") } } } label: { Label(selection.wrappedValue.isEmpty ? title : "\(title) (\(selection.wrappedValue.count))", systemImage: "line.3.horizontal.decrease.circle") }
    }

    private var kpis: some View {
        HStack(spacing: 12) {
            workspaceMetric("Downloads", "\(snapshot.summary.completedCount)", showComparison ? snapshot.deltas["downloads"] : nil, icon: "arrow.down.circle.fill", color: .blue, deltaFormatter: { String(format: "%+.0f", $0) })
            workspaceMetric("Data", ByteCountFormatter.string(fromByteCount: snapshot.summary.totalBytes, countStyle: .file), showComparison ? snapshot.deltas["data"] : nil, icon: "externaldrive.fill", color: .purple, deltaFormatter: { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) })
            workspaceMetric("Avg speed", speed(snapshot.summary.averageSpeed), showComparison ? snapshot.deltas["averageSpeed"] : nil, icon: "gauge.with.dots.needle.67percent", color: .orange, deltaFormatter: { speed($0) })
            workspaceMetric("Success rate", snapshot.summary.successRate.map { "\(Int($0 * 100))%" } ?? "—", showComparison ? snapshot.deltas["successRate"] : nil, icon: "checkmark.seal.fill", color: .green, deltaFormatter: { String(format: "%+.1f pts", $0 * 100) })
        }
    }

    private func workspaceMetric(_ title: String, _ value: String, _ delta: AnalyticsDelta?, icon: String, color: Color, deltaFormatter: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 7) { HStack { Image(systemName: icon).foregroundStyle(color); Spacer(); deltaLabel(delta, formatter: deltaFormatter) }; Text(value).font(.title2.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func deltaLabel(_ delta: AnalyticsDelta?, formatter: @escaping (Double) -> String) -> some View { Group { if let delta { Text("\(formatter(delta.absolute)) · \(delta.percentage.map { $0 == 0 ? "0%" : String(format: "%+.0f%%", $0 * 100) } ?? "New")").font(.caption.bold()).foregroundStyle(delta.absolute >= 0 ? .green : .red) } else { Text("—").font(.caption).foregroundStyle(.secondary) } } }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volume over time").font(.headline)
            let points = DownloadAnalytics.points(records: snapshot.records, samples: manager.samples, range: range, metric: .data)
            Chart(points) { point in AreaMark(x: .value("Date", point.date), y: .value("Data", point.value)).foregroundStyle(.purple.gradient.opacity(0.3)); LineMark(x: .value("Date", point.date), y: .value("Data", point.value)).foregroundStyle(.purple) }
                .chartXSelection(value: $selectedDate)
                .frame(height: 210)
            Text("Click a point to filter the table to that day.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var speedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speed distribution").font(.headline)
            HStack(spacing: 14) { speedStat("Average", snapshot.summary.averageSpeed); speedStat("Median", snapshot.speedMedian); speedStat("Peak", snapshot.summary.peakSpeed); speedStat("Low", snapshot.summary.lowSpeed) }
            if snapshot.speedValues.isEmpty { ContentUnavailableView("No speed history", systemImage: "waveform.path.ecg", description: Text("Speed metrics appear after active downloads.")) } else { Chart(Array([snapshot.summary.averageSpeed, snapshot.speedMedian, snapshot.summary.peakSpeed, snapshot.summary.lowSpeed].compactMap { $0 }.enumerated()), id: \.offset) { item in BarMark(x: .value("Metric", item.offset), y: .value("Bytes/s", item.element)) }.frame(height: 140) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func speedStat(_ label: String, _ value: Double?) -> some View { VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption).foregroundStyle(.secondary); Text(speed(value)).font(.headline) } }

    private var outcomesCard: some View {
        let values = ["Completed", "Failed", "Cancelled", "Paused", "In progress"].map { label in (label, Double(snapshot.records.filter { statusLabel($0) == label }.count)) }
        return VStack(alignment: .leading, spacing: 10) { Text("Outcomes").font(.headline); Chart(values, id: \.0) { item in BarMark(x: .value("Status", item.0), y: .value("Records", item.1)).foregroundStyle(item.0 == "Failed" ? .red : .blue) }.frame(height: 190) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) { Text("Breakdown by \(filter.breakdown.rawValue.lowercased())").font(.headline); ForEach(snapshot.breakdown.prefix(6)) { item in Button { if filter.breakdown == .fileType { filter.fileTypes = [item.label] } else { filter.domains = [item.label] } } label: { HStack { Text(item.label); Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(item.value), countStyle: .file)).foregroundStyle(.secondary) } }.buttonStyle(.plain).padding(.vertical, 5) } }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var activityTable: some View {
        VStack(alignment: .leading, spacing: 10) { Text("Filtered activity").font(.headline); if snapshot.records.isEmpty { ContentUnavailableView("No matching downloads", systemImage: "line.3.horizontal.decrease.circle", description: Text("Clear a filter or choose a wider range.")) } else { Table(snapshot.records, selection: $selectedRecordID) { TableColumn("Date") { record in Text((record.completedAt ?? record.startedAt ?? record.createdAt).formatted(date: .abbreviated, time: .shortened)) }; TableColumn("File") { record in Text(record.fileName).lineLimit(1) }; TableColumn("Type") { record in Text(record.fileType) }; TableColumn("Source") { record in Text(DownloadAnalytics.sourceDomain(for: record)).lineLimit(1) }; TableColumn("Status") { record in Text(statusLabel(record)) }; TableColumn("Received") { record in Text(ByteCountFormatter.string(fromByteCount: observedBytes(record), countStyle: .file)) }; TableColumn("Duration") { record in Text(duration(record)) }; TableColumn("Avg speed") { record in Text(speed(averageSpeed(record))) } }.frame(minHeight: 250).onChange(of: selectedRecordID) { _, id in if let id, let record = snapshot.records.first(where: { $0.id == id }) { onOpenRecord(record); selectedRecordID = nil } } } }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusLabel(_ record: DownloadRecord) -> String { record.state == .downloading || record.state == .queued ? "In progress" : record.state.label }
    private func observedBytes(_ record: DownloadRecord) -> Int64 { record.state == .completed ? max(record.downloadedBytes, record.totalBytes) : max(0, record.downloadedBytes) }
    private func speed(_ value: Double?) -> String { guard let value else { return "—" }; return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file) + "/s" }
    private func averageSpeed(_ record: DownloadRecord) -> Double? { let values = manager.samples.filter { $0.recordID == record.id && $0.speed > 0 }.map(\.speed); return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    private func duration(_ record: DownloadRecord) -> String { guard let start = record.startedAt, let end = record.completedAt else { return "—" }; return "\(Int(end.timeIntervalSince(start)))s" }
}
