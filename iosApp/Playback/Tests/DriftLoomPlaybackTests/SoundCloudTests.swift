// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class SoundCloudParsingTests: XCTestCase {
    private let track: [String: Any] = [
        "kind": "track", "id": 417474360, "title": "Night drive", "duration": 125000, "full_duration": 185000,
        "artwork_url": "https://i1.sndcdn.com/artworks-abc-large.jpg", "permalink_url": "https://soundcloud.com/artist/night-drive",
        "user": ["id": 42, "username": "Artist", "avatar_url": "https://i1.sndcdn.com/avatars-x-large.jpg"]
    ]

    func testIDsAreServicePrefixedAndStrict() {
        XCTAssertEqual(SoundCloudID.track(5), "sc:5"); XCTAssertEqual(SoundCloudID.trackNumber("sc:5"), 5)
        XCTAssertEqual(SoundCloudID.userNumber("sc:user:42"), 42); XCTAssertEqual(SoundCloudID.playlistNumber("sc:playlist:9"), 9)
        for bad in ["sc:", "sc:0", "sc:-1", "sc:1a", "sc:user:x", "sc:１２", "sc:12345678901234567890", "5"] {
            XCTAssertNil(SoundCloudID.trackNumber(bad), bad); XCTAssertNil(SoundCloudID.userNumber(bad), bad)
        }
        XCTAssertNil(SoundCloudID.trackNumber("sc:user:42"), "A user ID is not a track")
        XCTAssertEqual(try VideoRequest(input: " sc:417474360 ").videoID, "sc:417474360")
        XCTAssertTrue(try VideoRequest(input: "sc:1").isSoundCloud)
        XCTAssertThrowsError(try VideoRequest(input: "sc:user:1"))
        XCTAssertTrue(ChannelIDs.valid("sc:user:42")); XCTAssertTrue(ChannelIDs.valid("UC" + String(repeating: "a", count: 22)))
        XCTAssertFalse(ChannelIDs.valid("sc:42"))
    }

    func testTracksUsersAndPlaylistsBecomeBrowseItems() throws {
        let item = try XCTUnwrap(SoundCloudParser.item(track))
        XCTAssertEqual(item.contentID, "sc:417474360"); XCTAssertEqual(item.kind, .video); XCTAssertEqual(item.duration, "3:05")
        XCTAssertEqual(item.channelID, "sc:user:42"); XCTAssertEqual(item.subtitle, "Artist")
        XCTAssertEqual(item.thumbnail?.absoluteString, "https://i1.sndcdn.com/artworks-abc-t500x500.jpg")
        XCTAssertEqual(item.shareURL?.absoluteString, "https://soundcloud.com/artist/night-drive")
        XCTAssertNil(item.destination)
        let user = try XCTUnwrap(SoundCloudParser.item(["kind": "user", "id": 42, "username": "Artist", "followers_count": 1200]))
        XCTAssertEqual(user.destination, .channel("sc:user:42")); XCTAssertTrue(user.subtitle.contains("followers"))
        let playlist = try XCTUnwrap(SoundCloudParser.item(["kind": "playlist", "id": 9, "title": "Mix", "track_count": 3, "user": ["username": "Artist"]]))
        XCTAssertEqual(playlist.destination, .playlist("sc:playlist:9")); XCTAssertEqual(playlist.subtitle, "Artist · 3 tracks")
        XCTAssertNil(SoundCloudParser.item(["kind": "track", "id": 1, "title": "  "]))
        XCTAssertNil(SoundCloudParser.item(["kind": "system-playlist", "id": 1, "title": "x"]))
        XCTAssertNil(SoundCloudParser.item(["kind": "track", "id": 1, "title": "x", "permalink_url": "https://evil.test/x"])?.webURL)
    }

    func testPagesFollowOnlySoundCloudAPILinksAndUnwrapCharts() throws {
        let page = try SoundCloudParser.page(["collection": [["track": track], ["kind": "user", "id": 1, "username": "U"]],
                                               "next_href": "https://api-v2.soundcloud.com/charts?offset=50"], title: "Trending")
        XCTAssertEqual(page.items.map(\.contentID), ["sc:417474360", "sc:user:1"])
        XCTAssertEqual(page.next?.clientVersion, "soundcloud")
        let hostile = try SoundCloudParser.page(["collection": [track], "next_href": "https://evil.test/next"], title: "")
        XCTAssertNil(hostile.next)
        XCTAssertThrowsError(try SoundCloudParser.page(["error": "x"], title: ""))
    }

    func testTranscodingPrefersFullLengthAACAndSkipsPreviews() {
        let snippet: [String: Any] = ["url": "a", "snipped": true, "format": ["protocol": "hls", "mime_type": "audio/mp4; codecs=\"mp4a.40.2\""]]
        let mp3: [String: Any] = ["url": "b", "snipped": false, "format": ["protocol": "hls", "mime_type": "audio/mpegurl"]]
        let aac: [String: Any] = ["url": "c", "snipped": false, "format": ["protocol": "hls", "mime_type": "audio/mp4; codecs=\"mp4a.40.2\""]]
        let opus: [String: Any] = ["url": "d", "snipped": false, "format": ["protocol": "hls", "mime_type": "audio/ogg; codecs=\"opus\""]]
        XCTAssertEqual(SoundCloudParser.bestTranscoding([snippet, mp3, aac])?["url"] as? String, "c")
        XCTAssertEqual(SoundCloudParser.bestTranscoding([snippet, opus, mp3])?["url"] as? String, "b")
        XCTAssertNil(SoundCloudParser.bestTranscoding([snippet, opus]), "Previews and Opus-only tracks aren't offered")
        let drm: [String: Any] = ["url": "e", "snipped": false, "format": ["protocol": "cbc-encrypted-hls", "mime_type": "audio/mp4; codecs=\"mp4a.40.2\""]]
        XCTAssertNil(SoundCloudParser.bestTranscoding([drm]))
        XCTAssertTrue(SoundCloudParser.unplayableReason([drm]).contains("DRM"))
        XCTAssertTrue(SoundCloudParser.unplayableReason([snippet]).contains("preview"))
        XCTAssertTrue(SoundCloudParser.unplayableReason([opus]).contains("format"))
    }

    func testClientIDDiscoveryReadsOnlyAssetScripts() {
        let html = """
        <script crossorigin src="https://a-v2.sndcdn.com/assets/0-abc.js"></script>
        <script src="https://evil.test/assets/1.js"></script><script src="https://a-v2.sndcdn.com/assets/55-9a8a.js"></script>
        """
        XCTAssertEqual(SoundCloudParser.assetScripts(in: html).map(\.lastPathComponent), ["0-abc.js", "55-9a8a.js"])
        XCTAssertEqual(SoundCloudParser.clientID(in: #"x={a:1,client_id:"AbCdEf0123456789AbCdEf0123456789",b:2}"#), "AbCdEf0123456789AbCdEf0123456789")
        XCTAssertNil(SoundCloudParser.clientID(in: #",client_id:"short""#))
        XCTAssertNil(SoundCloudParser.clientID(in: #",client_id:"has spaces and \" quotes here at all""#))
    }

    func testBrowseItemsWithoutWebLinksStillDecode() throws {
        let old = #"{"contentID":"dQw4w9WgXcQ","kind":"video","title":"Old","subtitle":""}"#
        let item = try JSONDecoder().decode(BrowseItem.self, from: Data(old.utf8))
        XCTAssertNil(item.webURL); XCTAssertEqual(item.shareURL?.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        let sc = try XCTUnwrap(SoundCloudParser.item(track))
        XCTAssertEqual(try JSONDecoder().decode(BrowseItem.self, from: JSONEncoder().encode(sc)), sc)
    }
}

@MainActor
final class SoundCloudLibraryTests: XCTestCase {
    func testSoundCloudItemsPersistEverywhereYouTubeItemsDo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let track = BrowseItem(contentID: "sc:417474360", kind: .video, title: "Night drive", channelID: "sc:user:42")
        let user = BrowseItem(contentID: "sc:user:42", kind: .channel, title: "Artist")
        let playlist = BrowseItem(contentID: "sc:playlist:9", kind: .playlist, title: "Mix")
        let library = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        _ = library.toggleSaved(track); _ = library.toggleSubscription(user)
        let reloaded = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        XCTAssertTrue(reloaded.isWritable)
        XCTAssertTrue(reloaded.isSaved("sc:417474360")); XCTAssertTrue(reloaded.isSubscribed("sc:user:42"))
        let playlists = PlaylistStore(fileURL: directory.appendingPathComponent("playlists.json"))
        let id = try XCTUnwrap(playlists.create(name: "Mixed", item: track))
        XCTAssertTrue(playlists.add(BrowseItem(contentID: "dQw4w9WgXcQ", kind: .video, title: "YouTube"), to: id))
        playlists.toggleBookmark(playlist)
        XCTAssertEqual(PlaylistStore(fileURL: directory.appendingPathComponent("playlists.json")).playlists.first?.entries.count, 2)
        XCTAssertTrue(PlaylistStore(fileURL: directory.appendingPathComponent("playlists.json")).isBookmarked("sc:playlist:9"))
        let pinned = PinnedHomeTabs(fileURL: directory.appendingPathComponent("home-tabs.json"))
        pinned.toggle(user); pinned.toggle(playlist)
        XCTAssertEqual(PinnedHomeTabs(fileURL: directory.appendingPathComponent("home-tabs.json")).tabs.count, 2)
        var groups = SubscriptionGroupDocument()
        groups.groups.append(SubscriptionGroup(id: UUID(), name: "Music", channelIDs: ["sc:user:42"]))
        XCTAssertTrue(SubscriptionGroups.valid(groups))
        let downloads = DownloadLibrary(fileURL: directory.appendingPathComponent("downloads.json"))
        XCTAssertTrue(downloads.add(DownloadRecord(item: track, choice: DownloadChoice(id: "soundcloud", name: "Audio · SoundCloud stream", kind: .audio))))
    }
    func testSoundCloudTracksOfferOneAudioFileDownloadChoice() async throws {
        let choices = try await YouTubeDownloadResolver().choices(videoID: "sc:417474360")
        XCTAssertEqual(choices.map(\.kind), [.audio])
        do { _ = try await YouTubeDownloadResolver().choices(videoID: "sc:user:1"); XCTFail("Users can't be downloaded") } catch {}
    }
}

/// Serves canned SoundCloud responses and records requests, including which client ID was used.
private final class SoundCloudStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URL] = []
    nonisolated(unsafe) static var rejectedIDs: Set<String> = []
    nonisolated(unsafe) static var scriptIDs = ["OldClientID0123456789OldClient01"]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requests.append(url)
        func reply(_ status: Int, _ body: String) {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        }
        switch url.host {
        case "soundcloud.com": reply(200, #"<script src="https://a-v2.sndcdn.com/assets/1-a.js"></script>"#)
        case "a-v2.sndcdn.com":
            let id = Self.scriptIDs.count > 1 ? Self.scriptIDs.removeFirst() : Self.scriptIDs[0]
            reply(206, ",client_id:\"\(id)\",")
        case "api-v2.soundcloud.com":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "client_id" }?.value ?? ""
            if Self.rejectedIDs.contains(id) { reply(401, "{}"); return }
            reply(200, #"{"collection":[{"kind":"track","id":7,"title":"Stubbed"}],"next_href":"https://api-v2.soundcloud.com/search/tracks?q=x&offset=20"}"#)
        default: reply(404, "")
        }
    }
    override func stopLoading() {}
}

final class SoundCloudClientTests: XCTestCase {
    func testDiscoversClientIDOnceAndRefreshesItWhenRejected() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SoundCloudStub.self]
        SoundCloudStub.requests = []; SoundCloudStub.rejectedIDs = []
        SoundCloudStub.scriptIDs = ["OldClientID0123456789OldClient01", "NewClientID0123456789NewClient01"]
        let client = SoundCloudClient(session: URLSession(configuration: configuration))
        let first = try await client.search("x", filter: .tracks)
        XCTAssertEqual(first.items.map(\.contentID), ["sc:7"])
        _ = try await client.nextPage(try XCTUnwrap(first.next))
        XCTAssertEqual(SoundCloudStub.requests.filter { $0.host == "soundcloud.com" }.count, 1, "The ID is cached between requests")
        SoundCloudStub.rejectedIDs = ["OldClientID0123456789OldClient01"]
        _ = try await client.search("y", filter: .users)
        let used = SoundCloudStub.requests.filter { $0.host == "api-v2.soundcloud.com" }.last!
        XCTAssertTrue(used.absoluteString.contains("NewClientID0123456789NewClient01"), "A rejected ID is replaced once")
        do {
            _ = try await client.nextPage(BrowseCursor(token: "https://evil.test/next", clientVersion: "soundcloud", isSearch: false))
            XCTFail("Cursors must stay on SoundCloud's API host")
        } catch {}
    }
}

private final class SegmentStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var failing: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let name = url.lastPathComponent
        let body: Data
        switch name {
        case "playlist.m3u8": body = Data("#EXTM3U\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-MAP:URI=\"init.mp4?sig=1\"\n#EXTINF:10,\ndata000.m4s?sig=1\n#EXTINF:5,\nhttps://cdn.media-streaming.soundcloud.cloud/x/data001.m4s\n#EXT-X-ENDLIST\n".utf8)
        default: body = Data(name.utf8)
        }
        let status = name == Self.failing ? 403 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SoundCloudDownloadTests: XCTestCase {
    private let base = URL(string: "https://playback.media-streaming.soundcloud.cloud/abc/aac_96k/playlist.m3u8")!
    func testPlaylistParsingResolvesRelativeLinksAndRejectsUnsafePlaylists() throws {
        let playlist = try SoundCloudDownload.parse("#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:10,\ndata000.m4s\n", base: base)
        XCTAssertEqual(playlist.map?.lastPathComponent, "init.mp4"); XCTAssertEqual(playlist.segments.map(\.lastPathComponent), ["data000.m4s"])
        XCTAssertNil(try SoundCloudDownload.parse("#EXTM3U\n#EXTINF:10,\nhttps://cf-hls-media.sndcdn.com/media/1.mp3\n", base: base).map)
        for bad in ["not a playlist", "#EXTM3U\n", "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\na.m4s\n",
                    "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nvariant.m3u8\n", "#EXTM3U\nhttps://evil.test/a.m4s\n",
                    "#EXTM3U\n#EXT-X-MAP:URI=\"https://evil.test/init.mp4\"\na.m4s\n"] {
            XCTAssertThrowsError(try SoundCloudDownload.parse(bad, base: base), bad)
        }
    }
    func testSavingJoinsMapAndSegmentsInOrderAndCleansUpOnFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SegmentStub.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        SegmentStub.failing = nil
        let file = try await SoundCloudDownload.save(playlist: base, directory: directory, baseName: "track", session: session) { _ in }
        XCTAssertEqual(file.lastPathComponent, "track.m4a")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "init.mp4data000.m4sdata001.m4s")
        SegmentStub.failing = "data001.m4s"
        do { _ = try await SoundCloudDownload.save(playlist: base, directory: directory, baseName: "broken", session: session) { _ in }; XCTFail("A refused segment must fail") }
        catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("broken.m4a").path), "Partial files are removed")
    }
}
