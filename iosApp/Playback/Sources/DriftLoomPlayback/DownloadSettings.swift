// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum DownloadNetwork: String, CaseIterable, Identifiable, Codable, Sendable {
    case wifiOnly = "Wi-Fi only", any = "Wi-Fi and mobile data"
    public var id: String { rawValue }
    public func permits(connected: Bool, cellular: Bool) -> Bool { connected && (self == .any || !cellular) }
    public func configure(_ configuration: URLSessionConfiguration) {
        configuration.allowsCellularAccess = self == .any
        configuration.waitsForConnectivity = true
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
    }
}

public struct DownloadStorageUsage: Equatable, Sendable {
    public var bytes: Int64 = 0
    public var files = 0
    public var incomplete = false
    public init() {}
}

public enum DownloadStorage {
    /// Measure only supplied media roots, ignore symlinks, and bound traversal. Never modifies files.
    public static func measure(_ roots: [URL], limit: Int = 100_000) async -> DownloadStorageUsage {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        var result = DownloadStorageUsage(), visited = Set<String>(), examined = 0
        func count(_ url: URL) throws {
            guard visited.insert(url.standardizedFileURL.path).inserted else { return }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isRegularFile == true else { return }
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard bytes >= 0, result.bytes <= Int64.max - bytes else { result.incomplete = true; return }
            result.bytes += bytes; result.files += 1
        }
        for root in roots {
            guard !Task.isCancelled, examined < limit else { result.incomplete = true; break }
            do {
                let values = try root.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true else { continue }
                if values.isRegularFile == true { examined += 1; try count(root); continue }
                guard values.isDirectory == true else { continue }
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), errorHandler: { _, _ in result.incomplete = true; return true }) else {
                    result.incomplete = true; continue
                }
                for case let url as URL in enumerator {
                    guard !Task.isCancelled, examined < limit else { result.incomplete = true; break }
                    examined += 1
                    do { try count(url) } catch { result.incomplete = true }
                }
            } catch { result.incomplete = true }
        }
        return result
    }
}
