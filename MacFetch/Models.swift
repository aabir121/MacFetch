import Foundation
import SwiftData

enum DownloadPreferences {
    static let downloadLocationKey = "downloadLocationPath"
    static let rateLimitKey = "downloadRateLimit"
    static let maxConnectionsKey = "downloadMaxConnections"

    static var defaultFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    static var downloadFolder: URL {
        guard let path = UserDefaults.standard.string(forKey: downloadLocationKey), !path.isEmpty else {
            return defaultFolder
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

enum DownloadRateLimit: Identifiable {
    case unlimited
    case kilobytes(Double)
    case megabytes(Double)

    static let presets: [DownloadRateLimit] = [
        .kilobytes(500), .kilobytes(650), .kilobytes(700), .kilobytes(750), .kilobytes(800),
        .kilobytes(850), .kilobytes(900), .kilobytes(950), .megabytes(1), .megabytes(2), .megabytes(5)
    ]

    var id: String { title }
    var bytesPerSecond: Double? {
        switch self {
        case .unlimited: return nil
        case .kilobytes(let value): return Double(value) * 1_000
        case .megabytes(let value): return Double(value) * 1_000_000
        }
    }
    var title: String {
        switch self {
        case .unlimited: return "Unlimited"
        case .kilobytes(let value): return String(format: "%.0fKB/sec", value)
        case .megabytes(let value): return String(format: "%.2fMB/sec", value)
        }
    }
    var storedValue: Double { bytesPerSecond ?? 0 }

    init(storedValue: Double) {
        guard storedValue > 0 else { self = .unlimited; return }
        if storedValue >= 1_000_000 { self = .megabytes(max(0.01, storedValue / 1_000_000)) }
        else { self = .kilobytes(max(1, storedValue / 1_000)) }
    }
}

enum DownloadState: String, Codable, CaseIterable {
    case queued, downloading, paused, completed, failed, cancelled

    var label: String {
        switch self { case .queued: return "Queued"; case .downloading: return "Downloading"; case .paused: return "Paused"; case .completed: return "Completed"; case .failed: return "Failed"; case .cancelled: return "Cancelled" }
    }
}

@Model
final class DownloadRecord {
    @Attribute(.unique) var id: UUID
    var urlString: String
    var fileName: String
    var destinationPath: String
    var stateRaw: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var peakSpeed: Double?
    var errorMessage: String?

    init(url: URL, destination: URL, fileName: String? = nil) {
        id = UUID(); urlString = url.absoluteString
        self.fileName = fileName ?? url.lastPathComponent.nilIfEmpty ?? "download"
        destinationPath = destination.path; stateRaw = DownloadState.queued.rawValue
        totalBytes = 0; downloadedBytes = 0; createdAt = .now
        startedAt = nil; completedAt = nil; peakSpeed = nil
    }

    var url: URL? { URL(string: urlString) }
    var destinationURL: URL { URL(fileURLWithPath: destinationPath) }
    var state: DownloadState { get { DownloadState(rawValue: stateRaw) ?? .queued } set { stateRaw = newValue.rawValue } }
    var progress: Double { totalBytes > 0 ? min(1, Double(downloadedBytes) / Double(totalBytes)) : 0 }
    var fileType: String {
        let extensionName = URL(fileURLWithPath: fileName).pathExtension
        return extensionName.isEmpty ? "Other" : extensionName.uppercased()
    }
}

@Model
final class DownloadSample {
    @Attribute(.unique) var id: UUID
    var recordID: UUID
    var timestamp: Date
    var downloadedBytes: Int64
    var speed: Double
    var stateRaw: String

    init(recordID: UUID, timestamp: Date = .now, downloadedBytes: Int64, speed: Double, state: DownloadState) {
        id = UUID()
        self.recordID = recordID
        self.timestamp = timestamp
        self.downloadedBytes = downloadedBytes
        self.speed = speed
        stateRaw = state.rawValue
    }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
