import Foundation

enum AnalyticsMetric: String, CaseIterable, Identifiable {
    case downloads = "Downloads"
    case data = "Data"
    case speed = "Speed"

    var id: String { rawValue }
}

enum AnalyticsRange: Equatable {
    case today
    case days(Int)
    case custom(Date, Date)
}

struct AnalyticsPoint: Identifiable {
    let date: Date
    let value: Double
    let label: String

    var id: Date { date }
}

struct AnalyticsSummary {
    let completedCount: Int
    let startedCount: Int
    let totalBytes: Int64
    let averageSpeed: Double?
    let peakSpeed: Double?
    let lowSpeed: Double?
    let successRate: Double?
    let averageDuration: TimeInterval?
    let mostActiveDate: Date?
}

struct DownloadAnalytics {
    private struct Bounds {
        let start: Date
        let endExclusive: Date
        let calendar: Calendar
    }

    static func summarize(records: [DownloadRecord], samples: [DownloadSample], range: AnalyticsRange, calendar: Calendar = .current) -> AnalyticsSummary {
        let bounds = makeBounds(range, calendar: calendar)
        let matching = records.filter { record in
            let date = record.completedAt ?? record.startedAt ?? record.createdAt
            return bounds.start <= date && date < bounds.endExclusive
        }
        let startedRecords = records.filter { record in
            guard record.startedAt != nil || record.state == .completed || record.state == .failed else { return false }
            let date = record.startedAt ?? record.createdAt
            return bounds.start <= date && date < bounds.endExclusive
        }
        let started = startedRecords.count
        let completed = matching.filter { $0.state == .completed }.count
        let totalBytes = matching.reduce(Int64(0)) { $0 + observedBytes(for: $1) }
        let activeSamples = samples.filter { sample in
            bounds.start <= sample.timestamp && sample.timestamp < bounds.endExclusive && sample.speed > 0
        }
        let samplesByRecord = Dictionary(grouping: samples.filter { bounds.start <= $0.timestamp && $0.timestamp < bounds.endExclusive }, by: \.recordID)
        let observedPairs = samplesByRecord.values.flatMap { values in
            let ordered = values.sorted { $0.timestamp < $1.timestamp }
            return ordered.indices.dropFirst().compactMap { index -> (Int64, TimeInterval)? in
                let previous = ordered[index - 1]
                let sample = ordered[index]
                guard previous.speed > 0, sample.speed > 0 else { return nil }
                let interval = sample.timestamp.timeIntervalSince(previous.timestamp)
                guard interval <= 2.5 else { return nil }
                let bytes = sample.downloadedBytes - previous.downloadedBytes
                guard bytes >= 0 else { return nil }
                return (bytes, interval)
            }
        }
        let observedBytes = observedPairs.reduce(Int64(0)) { $0 + $1.0 }
        let observedTime = observedPairs.reduce(0.0) { $0 + $1.1 }
        let speeds = activeSamples.map(\.speed)
        let durations = matching.compactMap { record -> TimeInterval? in
            guard let start = record.startedAt, let end = record.completedAt else { return nil }
            return max(0, end.timeIntervalSince(start))
        }
        let mostActiveDate = dailyCounts(records: matching, calendar: bounds.calendar).max { $0.value < $1.value }?.key

        return AnalyticsSummary(
            completedCount: completed,
            startedCount: started,
            totalBytes: totalBytes,
            averageSpeed: observedTime > 0 ? Double(observedBytes) / observedTime : nil,
            peakSpeed: speeds.max(),
            lowSpeed: speeds.min(),
            successRate: started > 0 ? Double(startedRecords.filter { $0.state == .completed }.count) / Double(started) : nil,
            averageDuration: durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count),
            mostActiveDate: mostActiveDate
        )
    }

    static func points(records: [DownloadRecord], samples: [DownloadSample], range: AnalyticsRange, metric: AnalyticsMetric, calendar: Calendar = .current) -> [AnalyticsPoint] {
        let bounds = makeBounds(range, calendar: calendar)
        let buckets = bucketIntervals(for: bounds)
        return buckets.compactMap { interval in
            let bucket = interval.0
            let next = interval.1
            let recordsInBucket = records.filter { record in
                let date = record.completedAt ?? record.startedAt ?? record.createdAt
                return bounds.start <= date && date < bounds.endExclusive && bucket <= date && date < next
            }
            switch metric {
            case .downloads:
                return AnalyticsPoint(date: bucket, value: Double(recordsInBucket.count), label: label(for: bucket, bounds: bounds))
            case .data:
                let bytes = recordsInBucket.reduce(Int64(0)) { $0 + observedBytes(for: $1) }
                return AnalyticsPoint(date: bucket, value: Double(bytes), label: label(for: bucket, bounds: bounds))
            case .speed:
                let values = samples.filter { bucket <= $0.timestamp && $0.timestamp < next && $0.speed > 0 }.map(\.speed)
                guard !values.isEmpty else { return nil }
                return AnalyticsPoint(date: bucket, value: values.reduce(0, +) / Double(values.count), label: label(for: bucket, bounds: bounds))
            }
        }
    }

    private static func makeBounds(_ range: AnalyticsRange, calendar: Calendar) -> Bounds {
        let now = Date()
        switch range {
        case .today:
            let start = calendar.startOfDay(for: now)
            return Bounds(start: start, endExclusive: calendar.date(byAdding: .day, value: 1, to: start)!, calendar: calendar)
        case .days(let count):
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            let start = calendar.date(byAdding: .day, value: -(max(1, count) - 1), to: calendar.startOfDay(for: now))!
            return Bounds(start: start, endExclusive: end, calendar: calendar)
        case .custom(let start, let end):
            let normalizedStart = calendar.startOfDay(for: min(start, end))
            let normalizedEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end)))!
            return Bounds(start: normalizedStart, endExclusive: normalizedEnd, calendar: calendar)
        }
    }

    private static func bucketIntervals(for bounds: Bounds) -> [(Date, Date)] {
        let span = bounds.endExclusive.timeIntervalSince(bounds.start)
        let component: Calendar.Component = span <= 2 * 86_400 ? .hour : span <= 45 * 86_400 ? .day : .weekOfYear
        var intervals: [(Date, Date)] = []
        var date = aligned(bounds.start, component: component, calendar: bounds.calendar)
        while date < bounds.endExclusive {
            let next = bounds.calendar.date(byAdding: component, value: 1, to: date) ?? bounds.endExclusive
            intervals.append((max(date, bounds.start), min(next, bounds.endExclusive)))
            date = next
        }
        return intervals
    }

    private static func aligned(_ date: Date, component: Calendar.Component, calendar: Calendar) -> Date {
        switch component {
        case .hour: return calendar.date(bySetting: .minute, value: 0, of: date) ?? date
        case .day: return calendar.startOfDay(for: date)
        default: return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    private static func label(for date: Date, bounds: Bounds) -> String {
        let span = bounds.endExclusive.timeIntervalSince(bounds.start)
        return date.formatted(span <= 2 * 86_400 ? .dateTime.hour() : .dateTime.month(.abbreviated).day())
    }

    private static func dailyCounts(records: [DownloadRecord], calendar: Calendar) -> [Date: Int] {
        Dictionary(grouping: records) { calendar.startOfDay(for: $0.completedAt ?? $0.startedAt ?? $0.createdAt) }.mapValues(\.count)
    }

    private static func observedBytes(for record: DownloadRecord) -> Int64 {
        record.state == .completed ? max(record.downloadedBytes, record.totalBytes) : max(0, record.downloadedBytes)
    }
}

enum AnalyticsBreakdown: String, CaseIterable, Identifiable {
    case fileType = "File type"
    case sourceDomain = "Source domain"
    var id: String { rawValue }
}

struct AnalyticsWorkspaceFilter: Equatable {
    var range: AnalyticsRange = .days(7)
    var fileTypes: Set<String> = []
    var statuses: Set<String> = []
    var domains: Set<String> = []
    var selectedBucket: Date?
    var breakdown: AnalyticsBreakdown = .fileType
}

struct AnalyticsDelta {
    let absolute: Double
    let percentage: Double?
}

struct AnalyticsBreakdownValue: Identifiable {
    let label: String
    let value: Double
    var id: String { label }
}

struct AnalyticsWorkspaceSnapshot {
    let records: [DownloadRecord]
    let summary: AnalyticsSummary
    let previousSummary: AnalyticsSummary
    let deltas: [String: AnalyticsDelta]
    let breakdown: [AnalyticsBreakdownValue]
    let speedMedian: Double?
    let speedValues: [Double]
    let csv: String
}

extension DownloadAnalytics {
    static func sourceDomain(for record: DownloadRecord) -> String {
        guard let host = record.url?.host, !host.isEmpty else { return "Local file" }
        return host.lowercased()
    }

    static func workspaceSnapshot(records: [DownloadRecord], samples: [DownloadSample], filter: AnalyticsWorkspaceFilter, calendar: Calendar = .current) -> AnalyticsWorkspaceSnapshot {
        let bounds = makeBounds(filter.range, calendar: calendar)
        func matches(_ record: DownloadRecord, bounds: Bounds, includeBucket: Bool) -> Bool {
            let date = record.completedAt ?? record.startedAt ?? record.createdAt
            guard bounds.start <= date && date < bounds.endExclusive else { return false }
            if includeBucket, let selectedBucket = filter.selectedBucket {
                let span = bounds.endExclusive.timeIntervalSince(bounds.start)
                let component: Calendar.Component = span <= 2 * 86_400 ? .hour : span <= 45 * 86_400 ? .day : .weekOfYear
                let next = calendar.date(byAdding: component, value: 1, to: selectedBucket) ?? bounds.endExclusive
                guard selectedBucket <= date && date < next else { return false }
            }
            guard filter.fileTypes.isEmpty || filter.fileTypes.contains(record.fileType) else { return false }
            guard filter.domains.isEmpty || filter.domains.contains(sourceDomain(for: record)) else { return false }
            guard filter.statuses.isEmpty || filter.statuses.contains(statusGroup(for: record)) else { return false }
            return true
        }
        let filtered = records.filter { matches($0, bounds: bounds, includeBucket: true) }
        let filteredIDs = Set(filtered.map(\.id))
        let summary = summarize(records: filtered, samples: samples.filter { filteredIDs.contains($0.recordID) }, range: filter.range, calendar: calendar)
        let priorRange = previousRange(for: filter.range, calendar: calendar)
        let previousRecords = records.filter { matches($0, bounds: makeBounds(priorRange, calendar: calendar), includeBucket: false) }
        let previousIDs = Set(previousRecords.map(\.id))
        let previousSummary = summarize(records: previousRecords, samples: samples.filter { previousIDs.contains($0.recordID) }, range: priorRange, calendar: calendar)
        var deltas: [String: AnalyticsDelta] = [
            "downloads": delta(Double(summary.completedCount), Double(previousSummary.completedCount)),
            "data": delta(Double(summary.totalBytes), Double(previousSummary.totalBytes))
        ]
        if let current = summary.averageSpeed, let previous = previousSummary.averageSpeed { deltas["averageSpeed"] = delta(current, previous) }
        if let current = summary.successRate, let previous = previousSummary.successRate { deltas["successRate"] = delta(current, previous) }
        let breakdownKey: (DownloadRecord) -> String = filter.breakdown == .fileType ? { $0.fileType } : { sourceDomain(for: $0) }
        let breakdown = Dictionary(grouping: filtered, by: breakdownKey)
            .map { AnalyticsBreakdownValue(label: $0.key, value: Double($0.value.reduce(Int64(0)) { $0 + observedBytes(for: $1) })) }
            .sorted { $0.value > $1.value }
        let ids = filteredIDs
        let speedValues = samples.filter { ids.contains($0.recordID) && bounds.start <= $0.timestamp && $0.timestamp < bounds.endExclusive && $0.speed > 0 }.map(\.speed)
        let sortedSpeeds = speedValues.sorted()
        let speedMedian = sortedSpeeds.isEmpty ? nil : sortedSpeeds.count % 2 == 0 ? (sortedSpeeds[sortedSpeeds.count / 2 - 1] + sortedSpeeds[sortedSpeeds.count / 2]) / 2 : sortedSpeeds[sortedSpeeds.count / 2]
        return AnalyticsWorkspaceSnapshot(records: filtered, summary: summary, previousSummary: previousSummary, deltas: deltas, breakdown: breakdown, speedMedian: speedMedian, speedValues: speedValues, csv: csv(records: filtered, samples: samples))
    }

    private static func statusGroup(for record: DownloadRecord) -> String {
        if record.state == .downloading || record.state == .queued { return "In progress" }
        return record.state.label
    }

    private static func delta(_ current: Double, _ previous: Double) -> AnalyticsDelta {
        AnalyticsDelta(absolute: current - previous, percentage: previous == 0 ? nil : (current - previous) / abs(previous))
    }

    private static func previousRange(for range: AnalyticsRange, calendar: Calendar) -> AnalyticsRange {
        let bounds = makeBounds(range, calendar: calendar)
        let days = max(1, calendar.dateComponents([.day], from: bounds.start, to: bounds.endExclusive).day ?? 1)
        let end = bounds.start.addingTimeInterval(-0.001)
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: end)) ?? end.addingTimeInterval(-Double(days) * 86_400)
        return .custom(start, end)
    }

    private static func csv(records: [DownloadRecord], samples: [DownloadSample]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "date,file_name,file_type,source_domain,status,bytes_received,duration_seconds,average_speed_bytes_per_second"
        let rows = records.map { record in
            let date = formatter.string(from: record.completedAt ?? record.startedAt ?? record.createdAt)
            let duration = record.startedAt.flatMap { start in record.completedAt.map { max(0, $0.timeIntervalSince(start)) } }.map { String(format: "%.2f", $0) } ?? ""
            let speeds = samples.filter { $0.recordID == record.id && $0.speed > 0 }.map(\.speed)
            let averageSpeed = speeds.isEmpty ? "" : String(format: "%.2f", speeds.reduce(0, +) / Double(speeds.count))
            return [date, record.fileName, record.fileType, sourceDomain(for: record), statusGroup(for: record), String(observedBytes(for: record)), duration, averageSpeed].map(csvField).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
