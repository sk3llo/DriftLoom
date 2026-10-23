// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import DriftLoomPlayback
import Foundation

@main
struct BrowseProbe {
    @MainActor
    static func main() async throws {
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
