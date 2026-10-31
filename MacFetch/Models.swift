import Foundation
import SwiftData

enum DownloadPreferences {
    static let downloadLocationKey = "downloadLocationPath"

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
