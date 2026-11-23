// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import XCTest
import YouTubeKit
@testable import DriftLoomPlayback

final class AudioTrackTests: XCTestCase {
    private let originalURL = URL(string: "https://a.googlevideo.com/ru")!, dubURL = URL(string: "https://a.googlevideo.com/en")!
    private var original: AudioTrack { AudioTrack(id: "ru", isOriginal: true, isAutomaticDub: false, url: originalURL) }
    private var dub: AudioTrack { AudioTrack(id: "en-US", isOriginal: false, isAutomaticDub: true, url: dubURL) }

    func testSwitchingReplacesTheSeparateAudioOfAVideo() {
        var video = ResolvedVideo(title: "x", streamURL: URL(string: "https://a.googlevideo.com/video")!, usesHLS: false, audioURL: originalURL)
        video.audioTracks = [original, dub]; video.audioTrackID = original.id
        let switched = video.with(audioTrack: dub)
        XCTAssertEqual(switched.streamURL, video.streamURL)
        XCTAssertEqual(switched.audioURL, dubURL)
        XCTAssertEqual(switched.audioTrackID, "en-US")
        XCTAssertEqual(switched.audioTracks, [original, dub])
    }
    func testSwitchingReplacesTheStreamOfAudioOnlyPlayback() {
        var audio = ResolvedVideo(title: "x", streamURL: originalURL, usesHLS: false)
        audio.audioTracks = [original, dub]
        let switched = audio.with(audioTrack: dub)
        XCTAssertEqual(switched.streamURL, dubURL)
        XCTAssertNil(switched.audioURL)
    }
    func testUnknownTrackIsIgnored() {
        let video = ResolvedVideo(title: "x", streamURL: originalURL, usesHLS: false)
        XCTAssertEqual(video.with(audioTrack: dub).streamURL, originalURL)
    }
    func testNamesMarkTheOriginalAndAutomaticDubs() {
        XCTAssertTrue(original.name.contains("("), original.name)
        XCTAssertTrue(dub.name.contains("("), dub.name)
        XCTAssertFalse(AudioTrack(id: "de", isOriginal: false, isAutomaticDub: false, url: original.url).name.contains("("))
    }
    func testStreamsListEveryLanguageOnceWithTheOriginalFirst() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DRIFTLOOM_LIVE"] == nil, "Live YouTube check; set DRIFTLOOM_LIVE=1")
        let streams = try await YouTube(videoID: "0e3GPea1Tyg", methods: [.local]).streams
        let tracks = streams.audioTracks
        XCTAssertGreaterThan(tracks.count, 1)
        XCTAssertEqual(tracks.first?.isOriginal, true)
        XCTAssertEqual(tracks.filter(\.isOriginal).count, 1)
        XCTAssertEqual(Set(tracks.map(\.id)).count, tracks.count)
        XCTAssertFalse(streams.withoutDubs.contains(where: \.isDubbedAudio))
    }
    @MainActor func testHLSPlaysTheOriginalAudioByDefaultAndSwitches() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DRIFTLOOM_LIVE"] == nil, "Live YouTube check; set DRIFTLOOM_LIVE=1")
        let session = PlaybackSession()
        session.player.isMuted = true
        defer { session.stop() }
        session.open("0e3GPea1Tyg")
        for _ in 0..<160 where session.audioTracks.isEmpty { try await Task.sleep(nanoseconds: 250_000_000) }
        XCTAssertGreaterThan(session.audioTracks.count, 1)
        XCTAssertEqual(session.audioTracks.first?.isOriginal, true)
        XCTAssertEqual(session.selectedAudioTrackID, session.audioTracks.first?.id)
        let item = try XCTUnwrap(session.player.currentItem)
        let loaded = try await item.asset.loadMediaSelectionGroup(for: .audible)
        let group = try XCTUnwrap(loaded)
        XCTAssertEqual(item.currentMediaSelection.selectedMediaOption(in: group).map { AudioTrack(option: $0).id }, session.audioTracks.first?.id)
        let dub = try XCTUnwrap(session.audioTracks.first { !$0.isOriginal })
        session.selectAudioTrack(dub)
        XCTAssertEqual(session.selectedAudioTrackID, dub.id)
        XCTAssertEqual(item.currentMediaSelection.selectedMediaOption(in: group).map { AudioTrack(option: $0).id }, dub.id)
    }
}
