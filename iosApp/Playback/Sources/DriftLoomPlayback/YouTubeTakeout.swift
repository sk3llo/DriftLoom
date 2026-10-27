// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// YouTube subscriptions exported with Google Takeout: the export ZIP, its subscriptions.csv,
/// or the older subscriptions.json. Like NewPipe, only subscriptions are imported.
enum YouTubeTakeout {
    static let url = URL(string: "https://takeout.google.com/takeout/custom/youtube")!
    private static let channelPattern = "^UC[A-Za-z0-9_-]{22}$"

    /// The subscriptions in a Takeout ZIP. Folder and file names are translated ("Abos.csv"), so every
    /// CSV is read and only rows shaped like subscriptions count.
    static func plan(zip data: Data) throws -> LibraryImportPlan {
        guard data.count <= 50_000_000 else {
            throw BrowseError.unavailable(L("This ZIP is too large. Export only YouTube subscriptions from Takeout, or choose the subscriptions.csv file inside it."))
        }
        let files = try NewPipeArchive.members(data) { $0.lowercased().hasSuffix(".csv") ? 5_000_000 : nil }
        let best = files.values.compactMap { String(data: $0, encoding: .utf8) }.map(subscriptions).max { $0.count < $1.count } ?? []
        guard !best.isEmpty else {
            throw BrowseError.unavailable(L("This ZIP has no YouTube subscriptions. In Takeout, include \"subscriptions\" in the YouTube export."))
        }
        return plan(best, skipped: 0)
    }
    static func plan(csv text: String) throws -> LibraryImportPlan {
        let rows = csvRows(text)
        let channels = subscriptions(in: text)
        guard !channels.isEmpty else { throw BrowseError.unavailable(L("This CSV doesn't contain YouTube subscriptions from Takeout.")) }
        // Everything except the header row and accepted rows was unusable.
        return plan(channels, skipped: max(0, rows.filter { $0.contains { !$0.isEmpty } }.count - 1 - channels.count))
    }
    /// Takeout's older JSON: [{"snippet": {"resourceId": {"channelId"}, "title", "thumbnails"}}].
    static func plan(json data: Data) throws -> LibraryImportPlan? {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], items.count <= 50_000,
              items.contains(where: { $0["snippet"] != nil }) else { return nil }
        var channels: [BrowseItem] = [], skipped = 0, seen = Set<String>()
        for item in items {
            let snippet = item["snippet"] as? [String: Any]
            guard let id = (snippet?["resourceId"] as? [String: Any])?["channelId"] as? String,
                  id.range(of: channelPattern, options: .regularExpression) != nil else { skipped += 1; continue }
            let thumbnail = ((snippet?["thumbnails"] as? [String: Any])?["default"] as? [String: Any])?["url"] as? String
            if seen.insert(id).inserted {
                channels.append(BrowseItem(contentID: id, kind: .channel, title: title(snippet?["title"] as? String),
                                           thumbnail: thumbnail.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }))
            }
        }
        guard !channels.isEmpty else { throw BrowseError.unavailable(L("This JSON doesn't contain YouTube subscriptions.")) }
        return plan(channels, skipped: skipped)
    }

    private static func plan(_ channels: [BrowseItem], skipped: Int) -> LibraryImportPlan {
        var library = LibraryDocument()
        library.subscriptions = channels.map { LibraryRecord(item: $0, date: Date(timeIntervalSince1970: 0)) }
        return LibraryImportPlan(summary: L("Merge \(channels.count) YouTube subscriptions from Google Takeout."),
                                 warnings: [L("Only subscriptions are imported from Takeout; playlists and watch history aren't.")]
                                    + (skipped == 0 ? [] : [L("\(skipped) rows that aren't YouTube channels will be skipped.")]),
                                 library: library, playlists: PlaylistDocument())
    }
    private static func title(_ value: String?) -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? L("YouTube channel") : String(text.prefix(500))
    }

    /// Rows of "Channel Id,Channel Url,Channel Title" (headers are translated) whose URL names the same channel.
    static func subscriptions(in text: String) -> [BrowseItem] {
        var seen = Set<String>()
        return csvRows(text).compactMap { row -> BrowseItem? in
            guard row.count >= 2 else { return nil }
            let id = row[0].trimmingCharacters(in: .whitespaces)
            guard id.range(of: channelPattern, options: .regularExpression) != nil,
                  let url = URLComponents(string: row[1].trimmingCharacters(in: .whitespaces)),
                  ["http", "https"].contains(url.scheme ?? ""), ["www.youtube.com", "youtube.com"].contains(url.host ?? ""),
                  url.path == "/channel/" + id, seen.insert(id).inserted else { return nil }
            return BrowseItem(contentID: id, kind: .channel, title: title(row.count > 2 ? row[2] : nil))
        }
    }
    /// RFC 4180 rows: quoted fields may contain commas, quotes ("") and line breaks.
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var characters = text.hasPrefix("\u{FEFF}") ? Substring(text.dropFirst()) : Substring(text)
        while let character = characters.popFirst() {
            if quoted {
                if character == "\"" {
                    if characters.first == "\"" { field.append("\""); characters.removeFirst() } else { quoted = false }
                } else { field.append(character) }
                continue
            }
            switch character {
            case "\"": quoted = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); rows.append(row); row = []; field = ""
                guard rows.count <= 100_000 else { return rows }
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
