import Foundation

struct TransferMetrics { var bytes: Int64 = 0; var speed: Double = 0; var eta: TimeInterval? }

actor SegmentDownloader {
    private let session: URLSession
    init() { session = URLSession(configuration: .default) }

    func probe(_ url: URL) async throws -> (size: Int64, ranged: Bool) {
        var head = URLRequest(url: url); head.httpMethod = "HEAD"; head.timeoutInterval = 30
        let headResponse = try? await session.data(for: head)
        let headHTTP = headResponse?.1 as? HTTPURLResponse
        let headSize = headHTTP?.expectedContentLength ?? -1
        var request = URLRequest(url: url); request.setValue("bytes=0-0", forHTTPHeaderField: "Range"); request.timeoutInterval = 30
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        var iterator = bytes.makeAsyncIterator(); _ = try await iterator.next()
        if let range = http.value(forHTTPHeaderField: "Content-Range"), let slash = range.lastIndex(of: "/"), let size = Int64(range[range.index(after: slash)...]) { return (size, http.statusCode == 206) }
        return (headSize > 0 ? headSize : http.expectedContentLength, false)
    }

    func download(url: URL, destination: URL, connections: Int, onStarted: @escaping @Sendable (Int64) async -> Void, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let info = try await probe(url)
        await onStarted(info.size)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !info.ranged || info.size <= 0 || connections == 1 { try await stream(url: url, to: destination, range: nil, onProgress: onProgress); return }
        let count = min(max(1, connections), 32), chunk = max(1, info.size / Int64(count))
        let folder = destination.deletingLastPathComponent().appendingPathComponent(".macfetch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                let start = Int64(index) * chunk, end = index == count - 1 ? info.size - 1 : start + chunk - 1
                group.addTask { try await self.stream(url: url, to: folder.appendingPathComponent("segment-\(index)"), range: start...end, onProgress: onProgress) }
            }
            try await group.waitForAll()
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        for index in 0..<count {
            let input = try FileHandle(forReadingFrom: folder.appendingPathComponent("segment-\(index)")); defer { try? input.close() }
            while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { try output.write(contentsOf: data) }
        }
    }

    private func stream(url: URL, to destination: URL, range: ClosedRange<Int64>?, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        var request = URLRequest(url: url); request.timeoutInterval = 60
        if let range { request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode), range == nil || http.statusCode == 206 else { throw URLError(.badServerResponse) }
        if let range, let contentRange = http.value(forHTTPHeaderField: "Content-Range"), !contentRange.hasPrefix("bytes \(range.lowerBound)-\(range.upperBound)/") { throw URLError(.cannotParseResponse) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination); defer { try? handle.close() }
        var buffer = Data(); buffer.reserveCapacity(1024 * 1024); var written: Int64 = 0
        for try await byte in bytes { buffer.append(byte); if buffer.count >= 1024 * 1024 { try handle.write(contentsOf: buffer); written += Int64(buffer.count); onProgress(Int64(buffer.count)); buffer.removeAll(keepingCapacity: true) } }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer); written += Int64(buffer.count); onProgress(Int64(buffer.count)) }
        if let range, written != range.upperBound - range.lowerBound + 1 { throw URLError(.cannotParseResponse) }
    }
}
