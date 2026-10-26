// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import DriftLoomPlayback
import Foundation

@main
struct BrowseProbe {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.contains("--charts") {
            let page = try await YouTubeChartsClient().music(locale: ContentLocale())
            guard !page.items.isEmpty, page.items.allSatisfy({ $0.kind == .video }), page.next == nil else { throw BrowseError.unavailable("Expected a verified music chart") }
            print("PASS: official YouTube chart returned \(page.items.count) videos in published order")
            return
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        if CommandLine.arguments.contains("--soundcloud") {
            let client = YouTubeBrowsingClient()
            func check(_ name: String, _ page: BrowsePage) throws -> BrowsePage {
                guard !page.items.isEmpty else { throw BrowseError.unavailable("SoundCloud \(name) returned nothing") }
                print("PASS: SoundCloud \(name) items=\(page.items.count) more=\(page.next != nil) first=\(page.items[0].kind) \(page.items[0].title.prefix(40))")
                return page
            }
            let tracks = try check("track search", try await client.page(for: .soundCloudSearch("lofi hip hop", .tracks)))
            _ = try check("next page", try await client.nextPage(try XCTUnwrapOrThrow(tracks.next)))
            let users = try check("user search", try await client.page(for: .soundCloudSearch("lofi", .users)))
            let playlists = try check("playlist search", try await client.page(for: .soundCloudSearch("lofi", .playlists)))
            _ = try check("mixed search", try await client.page(for: .soundCloudSearch("lofi", .all)))
            var userPage: BrowsePage?
            for user in users.items.prefix(6) where userPage == nil {
                if let page = try? await client.page(for: user.destination!), !page.items.isEmpty { userPage = page }
            }
            _ = try check("user", try XCTUnwrapOrThrow(userPage))
            _ = try check("playlist", try await client.page(for: playlists.items[0].destination!))
            _ = try check("related", try await client.page(for: .related(tracks.items[0].contentID)))
            _ = try check("trending", try await client.page(for: .soundCloudTrending))
            let details = try await YouTubeDiscussionClient().details(videoID: tracks.items[0].contentID)
            print("PASS: SoundCloud details plays=\(details.views) date=\(details.date) comments=\(details.comments != nil)")
            if let cursor = details.comments {
                let page = try await YouTubeDiscussionClient().comments(cursor)
                print("PASS: SoundCloud comments=\(page.comments.count) more=\(page.next != nil)")
            }
            let feed = try await YouTubeFeedClient().videos(channelID: try XCTUnwrapOrThrow(userPage?.items.first?.channelID))
            print("PASS: SoundCloud feed entries=\(feed.count) newest=\(feed.map(\.published).max().map { "\($0)" } ?? "-")")
            let resolved = try await SoundCloudClient.shared.resolve(URL(string: tracks.items[0].webURL!.absoluteString)!)
            print("PASS: SoundCloud link resolves to \(resolved.contentID) == \(tracks.items[0].contentID)")
            print("TRACK: \(tracks.items[0].contentID)")
            return
        }
        if CommandLine.arguments.contains("--kiosks") {
            for kiosk in YouTubeKiosk.allCases {
                do {
                    let page = try await YouTubeBrowsingClient().page(for: .kiosk(kiosk))
                    let kinds = Dictionary(grouping: page.items, by: \.kind).mapValues(\.count)
                    print((page.items.isEmpty ? "EMPTY" : "PASS") + ": \(kiosk.rawValue) title=\(page.title) items=\(page.items.count) \(kinds) more=\(page.next != nil)")
                    if let first = page.items.first { print("    first: \(first.kind) \(first.title.prefix(60))") }
                } catch { print("FAIL: \(kiosk.rawValue): \(error.localizedDescription)") }
            }
            return
        }
        if CommandLine.arguments.contains("--suggestions") {
            let suggestions = try await YouTubeSuggestionsClient().suggestions(for: "newpipe", locale: ContentLocale())
            guard !suggestions.isEmpty else { throw BrowseError.unavailable("Expected search suggestions") }
            print("PASS: \(suggestions.count) nonempty YouTube search suggestions")
            return
        }
        if CommandLine.arguments.contains("--advanced-search") {
            let page = try await YouTubeBrowsingClient().page(for: .advancedSearch("swift programming", SearchOptions(type: .videos, order: .views, date: .year, duration: .short)))
            guard !page.items.isEmpty, page.items.allSatisfy({ $0.kind == .video }) else { throw BrowseError.unavailable("Advanced search returned no matching videos") }
            print("PASS: combined date, duration, type and sort filters returned \(page.items.count) videos")
            return
        }
        if CommandLine.arguments.contains("--comments") {
            let client = YouTubeDiscussionClient()
            let details = try await client.details(videoID: "11-9ZaYiTPE")
            guard let cursor = details.comments else { throw BrowseError.unavailable("Expected comments continuation") }
            let page = try await client.comments(cursor)
            guard !page.comments.isEmpty, page.comments.allSatisfy({ !$0.text.isEmpty }) else { throw BrowseError.unavailable("Expected readable comments") }
            print("PASS: video details and \(page.comments.count) comments")
            if let replyCursor = page.comments.compactMap(\.replies).first {
                let replies = try await client.comments(replyCursor)
                guard !replies.comments.isEmpty else { throw BrowseError.unavailable("Expected readable replies") }
                print("PASS: \(replies.comments.count) replies")
            }
            return
        }
        let client = YouTubeBrowsingClient()
        let query = CommandLine.arguments.dropFirst().first ?? "NDLS404 SENSOJI"
        let page = try await client.page(for: .search(query))
        guard let video = page.items.first(where: { $0.kind == .video }) else {
            throw BrowseError.unavailable("Search returned no videos")
        }
        print("PASS: search returned \(page.items.count) results")
        if let cursor = page.next {
            let next = try await client.nextPage(cursor)
            guard !next.items.isEmpty else { throw BrowseError.unavailable("Empty continuation") }
            print("PASS: pagination returned \(next.items.count) results")
        }
        if let channel = page.items.first(where: { $0.kind == .channel })?.contentID ?? video.channelID {
            let channelPage = try await client.page(for: .channel(channel))
            guard !channelPage.items.isEmpty else { throw BrowseError.unavailable("Channel returned no videos") }
            print("PASS: channel returned \(channelPage.items.count) results")
            if CommandLine.arguments.contains("--feed") {
                let feed = try await YouTubeFeedClient().videos(channelID: channel)
                guard !feed.isEmpty else { throw BrowseError.unavailable("Channel feed returned no videos") }
                print("PASS: subscription feed returned \(feed.count) dated videos")
            }
        }
        if CommandLine.arguments.contains("--filters") {
            for filter in SearchFilter.allCases where filter != .all {
                let filtered = try await client.page(for: .filteredSearch(query, filter))
                let expected: BrowseItem.Kind = filter == .videos ? .video : filter == .channels ? .channel : .playlist
                guard !filtered.items.isEmpty, filtered.items.allSatisfy({ $0.kind == expected }) else {
                    throw BrowseError.unavailable("Search filter did not return the expected result kind: \(filter.rawValue)")
                }
                print("PASS: \(filter.rawValue) filter returned \(filtered.items.count) matching items")
            }
        }
        if let playlist = page.items.first(where: { $0.kind == .playlist && $0.contentID.hasPrefix("PL") }) {
            let playlistPage = try await client.page(for: .playlist(playlist.contentID))
            guard !playlistPage.items.isEmpty else { throw BrowseError.unavailable("Playlist returned no videos") }
            print("PASS: playlist returned \(playlistPage.items.count) results")
        }
        if let mix = page.items.first(where: { $0.contentID.hasPrefix("RD") }), let route = mix.destination {
            let mixPage = try await client.page(for: route)
            guard !mixPage.items.isEmpty else { throw BrowseError.unavailable("Mix returned no videos") }
            print("PASS: mix returned \(mixPage.items.count) results")
        }
        let related = try await client.page(for: .related(video.contentID))
        guard !related.items.isEmpty else { throw BrowseError.unavailable("No related videos") }
        print("PASS: related videos returned \(related.items.count) results")
        if let cursor = related.next {
            let next = try await client.nextPage(cursor)
            guard !next.items.isEmpty else { throw BrowseError.unavailable("Empty related continuation") }
            print("PASS: related pagination returned \(next.items.count) results")
        }
        if CommandLine.arguments.contains("--play") {
            let playback = PlaybackSession()
            playback.player.isMuted = true
            playback.open(video.contentID)
            for _ in 0..<90 {
                try await Task.sleep(for: .seconds(1))
                if case let .failed(message) = playback.phase { throw BrowseError.unavailable(message) }
                if playback.player.currentTime().seconds >= 3 {
                    playback.stop()
                    print("PASS: search result opened and advanced in native playback")
                    return
                }
            }
            playback.stop()
            throw BrowseError.unavailable("Search result playback timed out")
        }
    }
}

private struct MissingValue: Error {}
private func XCTUnwrapOrThrow<T>(_ value: T?) throws -> T { guard let value else { throw MissingValue() }; return value }
