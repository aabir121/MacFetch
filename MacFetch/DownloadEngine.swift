import Foundation

struct TransferMetrics: Sendable {
    var bytes: Int64 = 0
    var speed: Double = 0
    var eta: TimeInterval?
}

struct SegmentSnapshot: Identifiable, Sendable {
    let id: UUID
    let start: Int64
    let end: Int64
    let completed: Int64
    let active: Bool

    var rangeLength: Int64 { end - start + 1 }
    var progress: Double { rangeLength > 0 ? min(1, Double(completed) / Double(rangeLength)) : 1 }
}

struct DownloadConnectionSnapshot: Sendable {
    let activeConnections: Int
    let targetConnections: Int
    let segments: [SegmentSnapshot]
}

private struct PersistedSegment: Codable, Sendable {
    let id: UUID
    let start: Int64
    var end: Int64
    var completed: Int64
    var active: Bool
}

private struct SegmentLedger: Codable, Sendable {
    let size: Int64
    var segments: [PersistedSegment]
}

private struct DownloadThrottleError: Error {}

private actor RangeCoordinator {
    private let totalSize: Int64
    private let maxConnections: Int
    private let ledgerURL: URL
    private var segments: [PersistedSegment]
    private var targetConnections: Int
    private var activeCount = 0
    private var speedSamples: [Double] = []

    init(size: Int64, maxConnections: Int, ledgerURL: URL) throws {
        totalSize = size
        self.maxConnections = min(32, max(1, maxConnections))
        self.ledgerURL = ledgerURL
        targetConnections = min(8, self.maxConnections)

        if let data = try? Data(contentsOf: ledgerURL),
           let saved = try? JSONDecoder().decode(SegmentLedger.self, from: data),
           saved.size == size,
           !saved.segments.isEmpty {
            segments = saved.segments.map {
                var segment = $0
                segment.active = false
                return segment
            }
        } else {
            segments = [PersistedSegment(id: UUID(), start: 0, end: size - 1, completed: 0, active: false)]
        }
    }

    func claim() throws -> PersistedSegment? {
        guard activeCount < targetConnections else { return nil }
        guard let index = largestUnfinishedIndex() else { return nil }
        let length = remaining(at: index)
        let minimumSplit = max(Int64(256 * 1024), totalSize / Int64(maxConnections * 16))
        if length > minimumSplit * 2 {
            let original = segments[index]
            let nextStart = original.start + original.completed
            let splitLength = max(minimumSplit, length / 2)
            let splitEnd = nextStart + splitLength - 1
            segments[index].end = splitEnd
            segments.append(PersistedSegment(id: UUID(), start: splitEnd + 1, end: original.end, completed: 0, active: false))
        }

        guard let claimIndex = largestUnfinishedIndex() else { return nil }
        segments[claimIndex].active = true
        activeCount += 1
        try persist()
        return segments[claimIndex]
    }

    func progress(id: UUID, completed: Int64) throws -> [SegmentSnapshot] {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return snapshot() }
        let maximum = segments[index].end - segments[index].start + 1
        segments[index].completed = min(maximum, max(0, completed))
        try persist()
        return snapshot()
    }

    func finish(id: UUID, speed: Double, throttled: Bool) throws -> DownloadConnectionSnapshot {
        if let index = segments.firstIndex(where: { $0.id == id }) {
            segments[index].completed = segments[index].end - segments[index].start + 1
            segments[index].active = false
        }
        activeCount = max(0, activeCount - 1)
        observe(speed: speed, throttled: throttled)
        try persist()
        return snapshotState()
    }

    func release(id: UUID, throttled: Bool = false) throws -> DownloadConnectionSnapshot {
        if let index = segments.firstIndex(where: { $0.id == id }) { segments[index].active = false }
        activeCount = max(0, activeCount - 1)
        if throttled { observe(speed: 1, throttled: true) }
        try persist()
        return snapshotState()
    }

    func snapshotState() -> DownloadConnectionSnapshot {
        DownloadConnectionSnapshot(activeConnections: activeCount, targetConnections: targetConnections, segments: snapshot())
    }

    func isComplete() -> Bool { segments.allSatisfy { $0.completed >= $0.end - $0.start + 1 } }

    private func largestUnfinishedIndex() -> Int? {
        segments.indices
            .filter { !segments[$0].active && remaining(at: $0) > 0 }
            .max { remaining(at: $0) < remaining(at: $1) }
    }

    private func remaining(at index: Int) -> Int64 { segments[index].end - segments[index].start + 1 - segments[index].completed }

    private func snapshot() -> [SegmentSnapshot] {
        segments.sorted { $0.start < $1.start }.map {
            SegmentSnapshot(id: $0.id, start: $0.start, end: $0.end, completed: $0.completed, active: $0.active)
        }
    }

    private func observe(speed: Double, throttled: Bool) {
        guard speed.isFinite, speed > 0 else { return }
        speedSamples.append(speed)
        if speedSamples.count > 8 { speedSamples.removeFirst() }
        if throttled {
            targetConnections = max(1, targetConnections - 2)
        } else if speedSamples.count >= 4 {
            let previous = speedSamples.dropLast().suffix(3).reduce(0, +) / 3
            if speed < previous * 0.65 {
                targetConnections = max(1, targetConnections - 1)
            } else if speed >= previous * 0.95 && targetConnections < maxConnections {
                targetConnections += 1
            }
        }
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(SegmentLedger(size: totalSize, segments: segments))
        try data.write(to: ledgerURL, options: .atomic)
    }
}

actor SegmentDownloader {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 32
        session = URLSession(configuration: configuration)
    }

    func probe(_ url: URL) async throws -> (size: Int64, ranged: Bool) {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 30
        let headResponse = try? await session.data(for: head).1 as? HTTPURLResponse
        let headSize = headResponse?.expectedContentLength ?? -1

        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 30
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        var iterator = bytes.makeAsyncIterator()
        _ = try await iterator.next()
        if let range = http.value(forHTTPHeaderField: "Content-Range"),
           let slash = range.lastIndex(of: "/"),
           let size = Int64(range[range.index(after: slash)...]) {
            return (size, http.statusCode == 206)
        }
        return (headSize > 0 ? headSize : http.expectedContentLength, false)
    }

    func download(
        url: URL,
        destination: URL,
        connections: Int,
        rateLimit: Double?,
        onStarted: @escaping @Sendable (Int64) async -> Void,
        onProgress: @escaping @Sendable (Int64) async -> Void,
        onConnections: @escaping @Sendable (DownloadConnectionSnapshot) async -> Void
    ) async throws {
        let info = try await probe(url)
        await onStarted(info.size)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let limiter = rateLimit.map { DownloadRateLimiter(bytesPerSecond: $0) }

        if !info.ranged || info.size <= 0 || connections == 1 {
            _ = try await stream(url: url, destination: destination, range: nil, expectedBytes: info.size, offset: 0, limiter: limiter, onProgress: onProgress)
            return
        }

        let ledgerURL = URL(fileURLWithPath: destination.path + ".macfetch.json")
        let coordinator = try RangeCoordinator(size: info.size, maxConnections: connections, ledgerURL: ledgerURL)
        if !FileManager.default.fileExists(atPath: destination.path) { FileManager.default.createFile(atPath: destination.path, contents: nil) }
        let output = try FileHandle(forWritingTo: destination)
        try output.truncate(atOffset: UInt64(info.size))
        try output.close()

        await onConnections(await coordinator.snapshotState())
        let workerCount = min(32, max(1, connections))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                group.addTask {
                    while !Task.isCancelled {
                        guard let segment = try await coordinator.claim() else {
                            if await coordinator.isComplete() { return }
                            try await Task.sleep(for: .milliseconds(80))
                            continue
                        }
                        let remainingStart = segment.start + segment.completed
                        let range = remainingStart...segment.end
                        let started = ContinuousClock.now
                        do {
                            let received = try await self.stream(
                                url: url,
                                destination: destination,
                                range: range,
                                expectedBytes: Int64(range.count),
                                offset: remainingStart,
                                limiter: limiter,
                                onProgress: { bytes in
                                    let snapshots = try? await coordinator.progress(id: segment.id, completed: segment.completed + bytes)
                                    await onProgress(bytes)
                                    if let snapshots {
                                        let state = await coordinator.snapshotState()
                                        await onConnections(DownloadConnectionSnapshot(activeConnections: state.activeConnections, targetConnections: state.targetConnections, segments: snapshots))
                                    }
                                }
                            )
                            let elapsedDuration = started.duration(to: ContinuousClock.now)
                            let elapsed = max(0.001, Double(elapsedDuration.components.seconds) + Double(elapsedDuration.components.attoseconds) / 1e18)
                            await onConnections(try await coordinator.finish(id: segment.id, speed: Double(received) / elapsed, throttled: false))
                        } catch is CancellationError {
                            _ = try? await coordinator.release(id: segment.id)
                            throw CancellationError()
                        } catch {
                            let throttled = error is DownloadThrottleError || (error as? URLError)?.code == .cannotConnectToHost || (error as? URLError)?.code == .timedOut || (error as? URLError)?.code == .networkConnectionLost
                            _ = try? await coordinator.release(id: segment.id, throttled: throttled)
                            if !throttled { throw error }
                            try await Task.sleep(for: .milliseconds(250))
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        guard await coordinator.isComplete() else { throw URLError(.cannotParseResponse) }
        try? FileManager.default.removeItem(at: ledgerURL)
    }

    private func stream(
        url: URL,
        destination: URL,
        range: ClosedRange<Int64>?,
        expectedBytes: Int64,
        offset: Int64,
        limiter: DownloadRateLimiter?,
        onProgress: @escaping @Sendable (Int64) async -> Void
    ) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if let range { request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range") }

        if range != nil {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if [408, 429, 502, 503, 504].contains(http.statusCode) { throw DownloadThrottleError() }
            guard http.statusCode == 206 else { throw URLError(.badServerResponse) }
            if let range, let contentRange = http.value(forHTTPHeaderField: "Content-Range"), !contentRange.hasPrefix("bytes \(range.lowerBound)-\(range.upperBound)/") { throw URLError(.cannotParseResponse) }
            guard Int64(data.count) == expectedBytes else { throw URLError(.cannotParseResponse) }
            let handle = try FileHandle(forWritingTo: destination)
            try handle.seek(toOffset: UInt64(offset))
            defer { try? handle.close() }
            var written: Int64 = 0
            while written < expectedBytes {
                let next = min(Int64(1024 * 1024), expectedBytes - written)
                let chunk = data.subdata(in: Int(written)..<Int(written + next))
                await limiter?.acquire(bytes: next)
                try handle.write(contentsOf: chunk)
                await onProgress(next)
                written += next
            }
            return written
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if [408, 429, 502, 503, 504].contains(http.statusCode) { throw DownloadThrottleError() }
        guard (200..<400).contains(http.statusCode), range == nil || http.statusCode == 206 else { throw URLError(.badServerResponse) }
        if let range, let contentRange = http.value(forHTTPHeaderField: "Content-Range"), !contentRange.hasPrefix("bytes \(range.lowerBound)-\(range.upperBound)/") { throw URLError(.cannotParseResponse) }

        if !FileManager.default.fileExists(atPath: destination.path) { FileManager.default.createFile(atPath: destination.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: destination)
        if range == nil { try handle.truncate(atOffset: 0) }
        try handle.seek(toOffset: UInt64(offset))
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1024 * 1024)
        var received: Int64 = 0
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                buffer.append(byte)
                received += 1
                if buffer.count >= 1024 * 1024 {
                    let size = Int64(buffer.count)
                    await limiter?.acquire(bytes: size)
                    try handle.write(contentsOf: buffer)
                    await onProgress(size)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        } catch {
            if received != expectedBytes { throw error }
        }
        if !buffer.isEmpty {
            let size = Int64(buffer.count)
            await limiter?.acquire(bytes: size)
            try handle.write(contentsOf: buffer)
            await onProgress(size)
        }
        guard received == expectedBytes else { throw URLError(.cannotParseResponse) }
        return received
    }
}

actor DownloadRateLimiter {
    private let bytesPerSecond: Double
    private var nextAvailable = ContinuousClock.now

    init(bytesPerSecond: Double) { self.bytesPerSecond = max(1, bytesPerSecond) }

    func acquire(bytes: Int64) async {
        let duration = Duration.seconds(Double(bytes) / bytesPerSecond)
        let now = ContinuousClock.now
        let start = max(now, nextAvailable)
        nextAvailable = start + duration
        if start > now { try? await Task.sleep(for: start - now) }
    }
}
