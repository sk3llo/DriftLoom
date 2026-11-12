// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Immutable files let the share extension hand links to the app without opening it.
/// Each link has its own file, so saving another link cannot overwrite a pending one.
public struct SharedLinkInbox {
    public enum InboxError: Error { case unsupportedLink }
    public struct Entry: Codable, Equatable, Identifiable {
        public let id: UUID
        public let url: URL
        public let createdAt: Date
    }

    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    /// Empty for free-account sideloading; PAL enables this with matching App Group entitlements.
    public static func configured(bundle: Bundle = .main) -> SharedLinkInbox? {
#if os(iOS)
        guard let group = bundle.object(forInfoDictionaryKey: "DriftLoomSharedAppGroup") as? String,
              group.hasPrefix("group."), !group.contains("$("),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return SharedLinkInbox(directory: container.appendingPathComponent("SharedLinks", isDirectory: true))
#else
        return nil
#endif
    }

    @discardableResult
    public func save(_ url: URL) throws -> Entry {
        guard SharedLink.isSupported(url), url.absoluteString.count <= 4096 else { throw InboxError.unsupportedLink }
        let entry = Entry(id: UUID(), url: url, createdAt: Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entry).write(to: file(for: entry.id), options: .atomic)
        return entry
    }

    /// Reading does not consume a link. "Later" and app termination preserve it.
    public func next() throws -> Entry? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        return files.compactMap { file -> Entry? in
            guard file.pathExtension == "json", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16_384,
                  let data = try? Data(contentsOf: file), let entry = try? JSONDecoder().decode(Entry.self, from: data),
                  entry.id == id, SharedLink.isSupported(entry.url), entry.url.absoluteString.count <= 4096 else { return nil }
            return entry
        }.min { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    public func remove(_ entry: Entry) throws {
        try FileManager.default.removeItem(at: file(for: entry.id))
    }

    private func file(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}
