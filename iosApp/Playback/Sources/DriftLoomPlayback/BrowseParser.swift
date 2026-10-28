// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// YouTube's response containers change independently of the playback extractor.
/// Keep this parser isolated and cover renderer variations with offline fixtures.
enum BrowseParser {
    typealias Object = [String: Any]

    static func initialData(in html: String) throws -> Object {
        for marker in ["var ytInitialData", "window[\"ytInitialData\"]", "ytInitialData"] {
            guard let range = html.range(of: marker) else { continue }
            var suffix = html[range.upperBound...].drop(while: { $0.isWhitespace })
            guard suffix.first == "=" else { continue }
            suffix = suffix.dropFirst().drop(while: { $0.isWhitespace })
            guard suffix.first == "{" else { continue }
            var depth = 0, quoted = false, escaped = false
            for index in suffix.indices {
                let char = suffix[index]
                if quoted {
                    if escaped { escaped = false }
                    else if char == "\\" { escaped = true }
                    else if char == "\"" { quoted = false }
                } else if char == "\"" { quoted = true }
                else if char == "{" { depth += 1 }
                else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        let data = Data(suffix[...index].utf8)
                        guard let root = try JSONSerialization.jsonObject(with: data) as? Object else { break }
                        return root
                    }
                }
            }
        }
        throw BrowseError.unsupportedResponse
    }

    static func clientVersion(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\"INNERTUBE_CLIENT_VERSION\"\\s*:\\s*\"([^\"]+)\""),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    static func page(_ root: Object, fallbackTitle: String, clientVersion: String?, isSearch: Bool, isRelated: Bool = false, isMix: Bool = false, locale: ContentLocale = .current()) throws -> BrowsePage {
        if let alerts = root["alerts"] as? [Object] {
            for alert in alerts {
                if let renderer = alert["alertRenderer"] as? Object, renderer["type"] as? String == "ERROR" {
                    throw BrowseError.unavailable(text(renderer["text"]))
                }
            }
        }
        let content: Any
        if let contents = root["contents"] as? Object {
            if let search = contents["twoColumnSearchResultsRenderer"] as? Object {
                content = search["primaryContents"] ?? [:]
            } else if let watch = contents["twoColumnWatchNextResults"] as? Object {
                if isMix { content = (watch["playlist"] as? Object)?["playlist"] ?? [:] }
                else { content = (watch["secondaryResults"] as? Object)?["secondaryResults"] ?? [:] }
            } else if let browse = contents["twoColumnBrowseResultsRenderer"] as? Object,
                      let tabs = browse["tabs"] as? [Object] {
                let renderers = tabs.compactMap { $0["tabRenderer"] as? Object }
                content = (renderers.first(where: { $0["selected"] as? Bool == true })
                    ?? renderers.first(where: { $0["content"] != nil }))?["content"] ?? [:]
            } else { throw BrowseError.unsupportedResponse }
        } else if let commands = root["onResponseReceivedCommands"] ?? root["onResponseReceivedActions"] ?? root["onResponseReceivedEndpoints"] {
            content = commands
        } else { throw BrowseError.unsupportedResponse }
        var items: [BrowseItem] = [], continuation: String?
        walk(content, items: &items, continuation: &continuation)
        var seen = Set<String>()
        items = items.filter { seen.insert($0.id).inserted }
        let metadata = root["metadata"] as? Object
        let channel = metadata?["channelMetadataRenderer"] as? Object
        let playlist = metadata?["playlistMetadataRenderer"] as? Object
        let title = (channel?["title"] ?? playlist?["title"]) as? String ?? fallbackTitle
        let next = continuation.flatMap { token in
            clientVersion.map { BrowseCursor(token: token, clientVersion: $0, isSearch: isSearch, isRelated: isRelated || isMix, locale: locale) }
        }
        let browseContents = ((root["contents"] as? Object)?["twoColumnBrowseResultsRenderer"] as? Object)
        let tabs = (browseContents?["tabs"] as? [Object] ?? []).compactMap {
            (($0["tabRenderer"] as? Object)?["title"] as? String).flatMap(ChannelTab.init(rawValue:))
        }
        let header = channel.map { BrowseHeader(description: $0["description"] as? String ?? "",
                                               thumbnail: image(in: $0["avatar"] ?? [:]), tabs: tabs) }
        return BrowsePage(title: title, items: items, next: next, header: header)
    }

    /// The "Show more" lists of a kiosk page's shelves, in page order.
    static func shelfLinks(_ root: Object) -> [BrowseShelf] {
        var shelves: [BrowseShelf] = []
        func visit(_ value: Any) {
            if let values = value as? [Any] { values.forEach(visit); return }
            guard let object = value as? Object else { return }
            for key in ["richShelfRenderer", "shelfRenderer"] {
                if let shelf = object[key] as? Object, let browse = (shelf["endpoint"] as? Object)?["browseEndpoint"] as? Object,
                   let id = browse["browseId"] as? String {
                    let link = BrowseShelf(browseID: id, params: browse["params"] as? String)
                    if !shelves.contains(link) { shelves.append(link) }
                    return
                }
            }
            for key in object.keys.sorted() where key != "header" && key != "topbar" { visit(object[key]!) }
        }
        visit(root["contents"] ?? [:])
        return shelves
    }

    static func visitorData(_ root: Object) -> String? {
        ((root["responseContext"] as? Object)?["visitorData"] as? String)
            ?? (((root["responseContext"] as? Object)?["webResponseContextExtensionData"] as? Object)?["ytConfigData"] as? Object)?["visitorData"] as? String
    }

    /// A channel's Videos tab as uploads with their relative times ("3h ago"), for when its RSS feed fails.
    static func channelUploads(_ root: Object) -> (channel: String, uploads: [(item: BrowseItem, age: String)]) {
        let channel = ((root["metadata"] as? Object)?["channelMetadataRenderer"] as? Object)?["title"] as? String ?? ""
        var uploads: [(BrowseItem, String)] = []
        func visit(_ value: Any) {
            if let values = value as? [Any] { values.forEach(visit); return }
            guard let object = value as? Object else { return }
            if let lockup = object["lockupViewModel"] as? Object {
                let metadata = (lockup["metadata"] as? Object)?["lockupMetadataViewModel"] as? Object
                let rows = ((metadata?["metadata"] as? Object)?["contentMetadataViewModel"] as? Object)?["metadataRows"] as? [Object] ?? []
                let parts = rows.flatMap { $0["metadataParts"] as? [Object] ?? [] }.map { text($0["text"]) }
                if let item = item(lockup, renderer: "lockupViewModel"), item.kind == .video, let age = parts.last(where: { $0.contains("ago") }) {
                    uploads.append((item, age))
                }
                return
            }
            if let renderer = (object["videoRenderer"] ?? object["gridVideoRenderer"]) as? Object {
                let age = text(renderer["publishedTimeText"])
                if let item = item(renderer, renderer: "videoRenderer"), !age.isEmpty { uploads.append((item, age)) }
                return
            }
            for key in object.keys.sorted() where !["menu", "trackingParams", "navigationEndpoint"].contains(key) { visit(object[key]!) }
        }
        visit(root)
        return (channel, uploads)
    }

    private static func walk(_ value: Any, items: inout [BrowseItem], continuation: inout String?) {
        if let values = value as? [Any] {
            for value in values { walk(value, items: &items, continuation: &continuation) }
        } else if let object = value as? Object {
            if object.keys.contains(where: { $0.lowercased().contains("adslot") || $0.hasPrefix("promoted") }) { return }
            for key in ["videoRenderer", "gridVideoRenderer", "compactVideoRenderer", "playlistVideoRenderer", "playlistPanelVideoRenderer", "channelRenderer",
                        "playlistRenderer", "gridPlaylistRenderer", "compactPlaylistRenderer", "shortsLockupViewModel", "reelItemRenderer", "lockupViewModel"] {
                if let renderer = object[key] as? Object {
                    if let item = item(renderer, renderer: key) { items.append(item) }
                    return // Never collect nested menu or playback-preview endpoints as results.
                }
            }
            if let renderer = object["continuationItemRenderer"] as? Object {
                continuation = firstString(in: renderer, key: "token") ?? continuation
                return
            }
            // Arrays define display order; a wrapper's property order has no visual meaning.
            for key in object.keys.sorted() where !["menu", "trackingParams", "navigationEndpoint", "adPlacements"].contains(key) {
                walk(object[key]!, items: &items, continuation: &continuation)
            }
        }
    }

    private static func item(_ object: Object, renderer: String) -> BrowseItem? {
        guard object["isPlayable"] as? Bool != false else { return nil }
        let kind: BrowseItem.Kind
        let id: String
        let title: String
        var subtitle = "", duration: String?, channelID: String?, playlistSeed: String?
        if renderer == "shortsLockupViewModel" {
            kind = .video
            guard let contentID = firstString(in: object["onTap"] ?? [:], key: "videoId") else { return nil }
            id = contentID
            let overlay = object["overlayMetadata"] as? Object
            title = text(overlay?["primaryText"])
            subtitle = text(overlay?["secondaryText"])
            duration = "Short"
        } else if renderer == "lockupViewModel" {
            switch object["contentType"] as? String {
            case "LOCKUP_CONTENT_TYPE_VIDEO": kind = .video
            case "LOCKUP_CONTENT_TYPE_PLAYLIST", "LOCKUP_CONTENT_TYPE_PODCAST": kind = .playlist
            default: return nil
            }
            guard let contentID = object["contentId"] as? String else { return nil }
            id = contentID
            if kind == .playlist {
                playlistSeed = firstString(in: object["rendererContext"] ?? object, key: "videoId")
            }
            let metadata = (object["metadata"] as? Object)?["lockupMetadataViewModel"] as? Object
            title = text(metadata?["title"])
            let rows = ((metadata?["metadata"] as? Object)?["contentMetadataViewModel"] as? Object)?["metadataRows"] as? [Object]
            if let firstRow = rows?.first, let parts = firstRow["metadataParts"] as? [Object] {
                subtitle = parts.map { text($0["text"]) }.filter { !$0.isEmpty }.joined(separator: " · ")
                channelID = firstString(in: firstRow, key: "browseId").flatMap { $0.hasPrefix("UC") ? $0 : nil }
            }
            duration = kind == .video ? firstString(in: object["contentImage"] ?? [:], key: "text") : nil
        } else {
            kind = renderer.lowercased().contains("channel") ? .channel : (renderer.lowercased().contains("playlist") && !["playlistVideoRenderer", "playlistPanelVideoRenderer"].contains(renderer) ? .playlist : .video)
            guard let contentID = object[kind == .video ? "videoId" : kind == .channel ? "channelId" : "playlistId"] as? String else { return nil }
            id = contentID; title = text(object["title"] ?? object["headline"])
            let byline = object["ownerText"] ?? object["shortBylineText"] ?? object["longBylineText"]
            subtitle = text(byline)
            channelID = firstString(in: byline ?? [:], key: "browseId").flatMap { $0.hasPrefix("UC") ? $0 : nil }
            duration = text(object["lengthText"])
            if subtitle.isEmpty { subtitle = text(object["subscriberCountText"] ?? object["videoCountText"]) }
        }
        guard !title.isEmpty, id.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil else { return nil }
        if kind == .video, (try? VideoRequest(input: id)) == nil { return nil }
        let thumbnail = image(in: object["thumbnail"] ?? object["thumbnails"] ?? object["contentImage"] ?? object["thumbnailViewModel"] ?? [:])
        return BrowseItem(contentID: id, kind: kind, title: title, subtitle: subtitle,
                          thumbnail: thumbnail, duration: duration?.isEmpty == false ? duration : nil, channelID: channelID, playlistSeed: playlistSeed)
    }

    private static func image(in value: Any) -> URL? {
        if let array = value as? [Any] { return array.reversed().compactMap { image(in: $0) }.first }
        guard let object = value as? Object else { return nil }
        if let string = object["url"] as? String,
           let url = URL(string: string.hasPrefix("//") ? "https:" + string : string), url.scheme == "https" { return url }
        for key in object.keys.sorted() {
            if let image = image(in: object[key]!) { return image }
        }
        return nil
    }

    private static func firstString(in value: Any, key: String) -> String? {
        if let object = value as? Object {
            if let string = object[key] as? String, !string.isEmpty { return string }
            for name in object.keys.sorted() {
                if let string = firstString(in: object[name]!, key: key) { return string }
            }
        } else if let array = value as? [Any] {
            for value in array { if let string = firstString(in: value, key: key) { return string } }
        }
        return nil
    }

    private static func text(_ value: Any?) -> String {
        guard let object = value as? Object else { return value as? String ?? "" }
        if let simple = (object["simpleText"] ?? object["content"]) as? String { return simple }
        return (object["runs"] as? [Object])?.compactMap { $0["text"] as? String }.joined() ?? ""
    }
}
