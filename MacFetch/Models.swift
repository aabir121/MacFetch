import Foundation
import SwiftData

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
    var errorMessage: String?

    init(url: URL, destination: URL, fileName: String? = nil) {
        id = UUID(); urlString = url.absoluteString
        self.fileName = fileName ?? url.lastPathComponent.nilIfEmpty ?? "download"
        destinationPath = destination.path; stateRaw = DownloadState.queued.rawValue
        totalBytes = 0; downloadedBytes = 0; createdAt = .now
    }

    var url: URL? { URL(string: urlString) }
    var destinationURL: URL { URL(fileURLWithPath: destinationPath) }
    var state: DownloadState { get { DownloadState(rawValue: stateRaw) ?? .queued } set { stateRaw = newValue.rawValue } }
    var progress: Double { totalBytes > 0 ? min(1, Double(downloadedBytes) / Double(totalBytes)) : 0 }
}

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
