import Foundation
import SwiftData
import Combine
import AppKit

@MainActor
final class DownloadManager: ObservableObject {
    @Published var records: [DownloadRecord] = []
    @Published var samples: [DownloadSample] = []
    @Published var totalSpeed: Double = 0
    @Published var speedSamples: [Double] = []
    @Published var connectionStats: [UUID: DownloadConnectionSnapshot] = [:]
    @Published private(set) var rateLimit: DownloadRateLimit
    @Published private(set) var maxConnections: Int
    var maxConcurrentDownloads = 3
    private let context: ModelContext
    private let engine = SegmentDownloader()
    private var jobs: [UUID: Task<Void, Never>] = [:]
    private var lastBytes: [UUID: Int64] = [:]
    private var lastTick = Date()
    private var lastProgressUpdate = Date.distantPast
    var activeCount: Int { jobs.count }

    init(context: ModelContext) {
        self.context = context
        let storedConnections = UserDefaults.standard.integer(forKey: DownloadPreferences.maxConnectionsKey)
        self.maxConnections = [1, 4, 8, 16, 32].contains(storedConnections) ? storedConnections : 8
        self.rateLimit = DownloadRateLimit(storedValue: UserDefaults.standard.double(forKey: DownloadPreferences.rateLimitKey))
        refresh(loadSamples: true); resumeRecoverable(); Task { await tick() }
    }
    func setRateLimit(_ limit: DownloadRateLimit) {
        rateLimit = limit
        UserDefaults.standard.set(limit.storedValue, forKey: DownloadPreferences.rateLimitKey)
    }
    func setMaxConnections(_ connections: Int) {
        maxConnections = min(32, max(1, connections))
        UserDefaults.standard.set(maxConnections, forKey: DownloadPreferences.maxConnectionsKey)
    }
    func refresh(loadSamples: Bool = false) {
        let fetched = (try? context.fetch(FetchDescriptor<DownloadRecord>(sortBy: [SortDescriptor(\DownloadRecord.createdAt)]))) ?? []
        if loadSamples { samples = (try? context.fetch(FetchDescriptor<DownloadSample>(sortBy: [SortDescriptor(\DownloadSample.timestamp)]))) ?? [] }
        var repaired = false
        for record in fetched where record.state == .failed && isCompleteOnDisk(record) {
            record.state = .completed
            record.errorMessage = nil
            repaired = true
        }
        if repaired { save() }
        records = fetched
    }
    func add(url: URL, destinationFolder: URL, fileName: String? = nil) {
        guard !records.contains(where: { $0.urlString == url.absoluteString && $0.state != .failed }) else { return }
        let resolvedFileName = fileName.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nilIfEmpty } ?? url.lastPathComponent.nilIfEmpty ?? "download"
        let record = DownloadRecord(url: url, destination: destinationFolder.appendingPathComponent(resolvedFileName), fileName: resolvedFileName); context.insert(record); save(); refresh(); startQueued()
    }
    func start(_ record: DownloadRecord) { record.state = .queued; save(); startQueued() }
    func resume(_ records: [DownloadRecord]) { records.filter { $0.state == .paused || $0.state == .queued }.forEach { $0.state = .queued }; save(); startQueued() }
    func pause(_ record: DownloadRecord) { jobs[record.id]?.cancel(); jobs[record.id] = nil; connectionStats[record.id] = nil; record.state = .paused; save(); refresh(); startQueued() }
    func pause(_ records: [DownloadRecord]) { records.filter { $0.state == .downloading }.forEach { pause($0) } }
    func cancel(_ record: DownloadRecord) { jobs[record.id]?.cancel(); jobs[record.id] = nil; connectionStats[record.id] = nil; record.state = .cancelled; save(); refresh(); startQueued() }
    func cancel(_ records: [DownloadRecord]) { records.filter { $0.state == .downloading || $0.state == .queued || $0.state == .paused }.forEach { cancel($0) } }
    func retry(_ record: DownloadRecord) { record.state = .queued; record.errorMessage = nil; record.totalBytes = 0; record.downloadedBytes = 0; record.startedAt = nil; record.completedAt = nil; record.peakSpeed = nil; save(); startQueued() }
    func remove(_ record: DownloadRecord) { jobs[record.id]?.cancel(); jobs[record.id] = nil; context.delete(record); save(); refresh(); startQueued() }
    func remove(_ records: [DownloadRecord]) { records.forEach { remove($0) } }
    func open(_ record: DownloadRecord) { NSWorkspace.shared.open(record.destinationURL) }
    func reveal(_ record: DownloadRecord) { NSWorkspace.shared.activateFileViewerSelecting([record.destinationURL]) }

    private func startQueued() {
        while jobs.count < maxConcurrentDownloads, let record = records.first(where: { $0.state == .queued && jobs[$0.id] == nil }) { run(record) }
    }
    private func run(_ record: DownloadRecord) {
        record.state = .downloading; record.startedAt = record.startedAt ?? .now; record.completedAt = nil; save(); refresh()
        jobs[record.id] = Task { [weak self] in
            guard let self, let url = record.url else { return }
            do {
                try await self.engine.download(url: url, destination: record.destinationURL, connections: self.maxConnections, rateLimit: self.rateLimit.bytesPerSecond, onStarted: { [weak self, weak record] size in await MainActor.run { guard let self, let record else { return }; record.totalBytes = size; self.save(); self.refresh() } }, onProgress: { [weak self] bytes in await MainActor.run { self?.record(record, bytes: bytes) } }, onConnections: { [weak self] snapshot in await MainActor.run { self?.connectionStats[record.id] = snapshot } })
                record.state = .completed; record.downloadedBytes = record.totalBytes; record.completedAt = .now
            } catch is CancellationError { return }
            catch {
                if self.isCompleteOnDisk(record) {
                    record.state = .completed
                    record.errorMessage = nil
                    record.completedAt = .now
                } else {
                    record.state = .failed
                    record.errorMessage = error.localizedDescription
                    record.completedAt = .now
                }
            }
            self.connectionStats[record.id] = nil
            self.save(); self.jobs[record.id] = nil; self.refresh(); self.startQueued()
        }
    }
    private func record(_ record: DownloadRecord, bytes: Int64) { record.downloadedBytes += bytes; if Date().timeIntervalSince(lastProgressUpdate) > 0.25 { lastProgressUpdate = .now; refresh() } }
    private func save() { try? context.save() }
    private func isCompleteOnDisk(_ record: DownloadRecord) -> Bool {
        guard record.totalBytes > 0, record.downloadedBytes >= record.totalBytes,
              let attributes = try? FileManager.default.attributesOfItem(atPath: record.destinationURL.path),
              let fileSize = attributes[.size] as? NSNumber else { return false }
        return fileSize.int64Value >= record.totalBytes
    }
    private func resumeRecoverable() { for record in records where record.state == .downloading { record.state = .queued }; startQueued() }
    private func tick() async { while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); let now = Date(); let elapsed = now.timeIntervalSince(lastTick); totalSpeed = elapsed > 0 ? Double(records.reduce(0) { $0 + ($1.downloadedBytes - (lastBytes[$1.id] ?? $1.downloadedBytes)) }) / elapsed : 0; speedSamples.append(totalSpeed); if speedSamples.count > 30 { speedSamples.removeFirst() }; for record in records { let previous = lastBytes[record.id] ?? record.downloadedBytes; let delta = max(0, record.downloadedBytes - previous); if record.state == .downloading { let speed = elapsed > 0 ? Double(delta) / elapsed : 0; record.peakSpeed = max(record.peakSpeed ?? 0, speed); let sample = DownloadSample(recordID: record.id, timestamp: now, downloadedBytes: record.downloadedBytes, speed: speed, state: record.state); context.insert(sample); samples.append(sample) }; lastBytes[record.id] = record.downloadedBytes }; lastTick = now; save(); refresh() } }
}
