import SwiftUI
import Charts
import AppKit

struct AnalyticsDashboardView: View {
    @EnvironmentObject private var manager: DownloadManager
    let onAdd: () -> Void
    @State private var rangePreset = "7 days"
    @State private var metric: AnalyticsMetric = .downloads
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
    @State private var customEnd = Date()

    private let presets = ["Today", "7 days", "30 days", "Custom"]

    private var range: AnalyticsRange {
        switch rangePreset {
        case "Today": return .today
        case "30 days": return .days(30)
        case "Custom": return .custom(customStart, customEnd)
        default: return .days(7)
        }
    }

    private var summary: AnalyticsSummary { DownloadAnalytics.summarize(records: manager.records, samples: manager.samples, range: range) }
    private var points: [AnalyticsPoint] { DownloadAnalytics.points(records: manager.records, samples: manager.samples, range: range, metric: metric) }
    private var recentRecords: [DownloadRecord] {
        manager.records
            .filter { record in
                let date = record.completedAt ?? record.startedAt ?? record.createdAt
                return date >= rangeStart && date <= rangeEnd
            }
            .sorted { ($0.completedAt ?? $0.startedAt ?? $0.createdAt) > ($1.completedAt ?? $1.startedAt ?? $1.createdAt) }
            .prefix(8)
            .map { $0 }
    }

    private var rangeStart: Date {
        switch range {
        case .today: return Calendar.current.startOfDay(for: .now)
        case .days(let count): return Calendar.current.date(byAdding: .day, value: -(max(1, count) - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
        case .custom(let start, _): return Calendar.current.startOfDay(for: min(start, customEnd))
        }
    }

    private var rangeEnd: Date {
        switch range {
        case .today, .days: return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))?.addingTimeInterval(-0.001) ?? .now
        case .custom(_, let end): return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(customStart, end)))?.addingTimeInterval(-0.001) ?? end
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                kpis
                HStack(alignment: .top, spacing: 18) {
                    chartCard
                    insightCard
                        .frame(width: 250)
                }
                activityCard
            }
            .padding(28)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Overview").font(.largeTitle.bold())
                Text("Your download activity at a glance").foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Range", selection: $rangePreset) { ForEach(presets, id: \.self, content: Text.init) }
                .pickerStyle(.segmented)
                .frame(width: 330)
            Picker("Metric", selection: $metric) { ForEach(AnalyticsMetric.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.menu)
            Button("Add download", systemImage: "plus", action: onAdd)
        }
        .overlay(alignment: .bottomTrailing) {
            if rangePreset == "Custom" {
                HStack {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                }
                .font(.caption)
                .padding(.top, 54)
            }
        }
    }

    private var kpis: some View {
        HStack(spacing: 14) {
            MetricCard(title: "Completed", value: "\(summary.completedCount)", caption: "of \(summary.startedCount) started", icon: "checkmark.circle.fill", tint: .green)
            MetricCard(title: "Data downloaded", value: byteString(summary.totalBytes), caption: "in selected period", icon: "externaldrive.fill", tint: .blue)
            MetricCard(title: "Average speed", value: speedString(summary.averageSpeed), caption: "active transfer time", icon: "gauge.with.dots.needle.67percent", tint: .orange)
            MetricCard(title: "Peak speed", value: speedString(summary.peakSpeed), caption: "best observed", icon: "arrow.up.right", tint: .purple)
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.rawValue).font(.headline)
                    Text(rangePreset == "Today" ? "Hourly activity" : "Activity over time").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(rangeLabel).font(.caption).foregroundStyle(.secondary)
            }
            if points.isEmpty {
                VStack(spacing: 10) {
                    ContentUnavailableView(metric == .speed ? "No speed samples yet" : "No downloads yet", systemImage: "chart.xyaxis.line", description: Text("Start a download to build your history."))
                    Button("Add download", action: onAdd)
                }
                    .frame(height: 250)
            } else {
                Chart(points) { point in
                    AreaMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                        .foregroundStyle(.blue.gradient.opacity(0.35))
                    LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) }
                .frame(height: 250)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance").font(.headline)
            InsightRow(label: "Low speed", value: speedString(summary.lowSpeed))
            InsightRow(label: "Success rate", value: summary.successRate.map { "\(Int($0 * 100))%" } ?? "—")
            InsightRow(label: "Avg. duration", value: durationString(summary.averageDuration))
            InsightRow(label: "Most active", value: summary.mostActiveDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
            Divider()
            Text("Speed values use active transfer samples only, so idle time doesn’t pull your average down.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Recent activity").font(.headline); Spacer(); Text("\(recentRecords.count) items").font(.caption).foregroundStyle(.secondary) }
            if recentRecords.isEmpty {
                Text("No downloads in this period.").foregroundStyle(.secondary).padding(.vertical, 18)
            } else {
                ForEach(recentRecords) { record in
                    HStack(spacing: 12) {
                        Image(systemName: record.state == .completed ? "checkmark.circle.fill" : record.state == .failed ? "exclamationmark.circle.fill" : "arrow.down.circle.fill")
                            .foregroundStyle(record.state == .failed ? .red : record.state == .completed ? .green : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.fileName).lineLimit(1)
                            Text(record.fileType).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(byteString(record.totalBytes > 0 ? record.totalBytes : record.downloadedBytes)).foregroundStyle(.secondary)
                        Text(record.state.label).font(.caption).foregroundStyle(record.state == .failed ? .red : .secondary).frame(width: 84, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    if record.id != recentRecords.last?.id { Divider() }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var rangeLabel: String {
        switch rangePreset { case "Today": return "Today"; case "30 days": return "Last 30 days"; case "Custom": return "Custom range"; default: return "Last 7 days" }
    }

    private func byteString(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func speedString(_ speed: Double?) -> String { guard let speed else { return "—" }; return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s" }
    private func durationString(_ duration: TimeInterval?) -> String { guard let duration else { return "—" }; return duration < 60 ? "\(Int(duration))s" : "\(Int(duration / 60))m \(Int(duration.truncatingRemainder(dividingBy: 60)))s" }
}

private struct MetricCard: View {
    let title: String; let value: String; let caption: String; let icon: String; let tint: Color
    var body: some View { VStack(alignment: .leading, spacing: 11) { HStack { Image(systemName: icon).foregroundStyle(tint); Spacer() }; Text(value).font(.title2.bold()); Text(title).font(.subheadline); Text(caption).font(.caption).foregroundStyle(.secondary) }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
}

private struct InsightRow: View {
    let label: String; let value: String
    var body: some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium) } }
}
