// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import CoreVideo
import XCTest
@testable import DriftLoomPlayback

/// Writes a silent-picture H.264 video without audio and an AAC audio file without video,
/// matching the shape of YouTube's separate adaptive streams.
enum MediaFixtures {
    static func videoOnly(seconds: Int, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? PlaybackError.noPlayableStream }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 10) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw PlaybackError.noPlayableStream }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 7 % 255), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? PlaybackError.noPlayableStream }
    }

    static func audioOnly(seconds: Int, to url: URL) async throws {
        let wav = url.deletingPathExtension().appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        var data = Data()
        func word(_ value: UInt32, _ bytes: Int) { for index in 0..<bytes { data.append(UInt8((value >> (index * 8)) & 255)) } }
        let samples = UInt32(seconds * 44100 * 2)
        data.append(Data("RIFF".utf8)); word(36 + samples, 4); data.append(Data("WAVEfmt ".utf8)); word(16, 4)
        word(1, 2); word(1, 2); word(44100, 4); word(88200, 4); word(2, 2); word(16, 2)
        data.append(Data("data".utf8)); word(samples, 4); data.append(Data(repeating: 0, count: Int(samples)))
        try data.write(to: wav)
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: wav), presetName: AVAssetExportPresetAppleM4A) else {
            throw PlaybackError.noPlayableStream
        }
        session.outputURL = url; session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else { throw session.error ?? PlaybackError.noPlayableStream }
    }
}

private actor MergedResolver: StreamResolving {
    let video: URL, audio: URL
    init(video: URL, audio: URL) { self.video = video; self.audio = audio }
    func resolve(_ request: VideoRequest) async throws -> ResolvedVideo {
        ResolvedVideo(title: "Merged fixture", streamURL: video, usesHLS: false, audioURL: audio)
    }
}

final class MergedMediaTests: XCTestCase {
    private var directory: URL!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    func testCompositionCombinesBothStreamsAndTrimsToTheShorter() async throws {
        let video = directory.appendingPathComponent("video.mp4"), audio = directory.appendingPathComponent("audio.m4a")
        try await MediaFixtures.videoOnly(seconds: 3, to: video)
        try await MediaFixtures.audioOnly(seconds: 2, to: audio)
        let composition = try await MergedMedia.composition(video: video, audio: audio)
        let videoTracks = try await composition.loadTracks(withMediaType: .video)
        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        XCTAssertEqual(videoTracks.count, 1); XCTAssertEqual(audioTracks.count, 1)
        let duration = try await composition.load(.duration)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.1)
    }

    func testCompositionRejectsAStreamWithoutTheExpectedTrack() async throws {
        let video = directory.appendingPathComponent("video.mp4"), audio = directory.appendingPathComponent("audio.m4a")
        try await MediaFixtures.videoOnly(seconds: 1, to: video)
        try await MediaFixtures.audioOnly(seconds: 1, to: audio)
        do { _ = try await MergedMedia.composition(video: audio, audio: video); XCTFail("Swapped streams must not combine") } catch {}
    }

    func testExportWritesOnePlayableFileWithBothTracks() async throws {
        let video = directory.appendingPathComponent("video.mp4"), audio = directory.appendingPathComponent("audio.m4a")
        let output = directory.appendingPathComponent("merged.mp4")
        try await MediaFixtures.videoOnly(seconds: 2, to: video)
        try await MediaFixtures.audioOnly(seconds: 2, to: audio)
        try await MergedMedia.export(video: video, audio: audio, to: output)
        let asset = AVURLAsset(url: output)
        let playable = try await asset.load(.isPlayable)
        let videoTracks = try await asset.loadTracks(withMediaType: .video), audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        XCTAssertTrue(playable); XCTAssertEqual(videoTracks.count, 1); XCTAssertEqual(audioTracks.count, 1)
        XCTAssertEqual(duration.seconds, 2, accuracy: 0.15)
    }

    @MainActor
    func testSessionPlaysSeparateVideoAndAudioTogether() async throws {
        let video = directory.appendingPathComponent("video.mp4"), audio = directory.appendingPathComponent("audio.m4a")
        try await MediaFixtures.videoOnly(seconds: 4, to: video)
        try await MediaFixtures.audioOnly(seconds: 4, to: audio)
        let session = PlaybackSession(resolver: MergedResolver(video: video, audio: audio))
        session.player.isMuted = true
        session.open("dQw4w9WgXcQ")
        for _ in 0..<150 where session.phase != .playing { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(session.phase, .playing)
        let asset = try XCTUnwrap(session.player.currentItem?.asset as? AVComposition)
        XCTAssertEqual(asset.tracks(withMediaType: .audio).count, 1)
        XCTAssertEqual(asset.tracks(withMediaType: .video).count, 1)
        XCTAssertEqual(session.video?.audioURL, audio)
        session.stop()
    }
}

final class TransferPartsTests: XCTestCase {
    func testPartDescriptionsRoundTripAndRejectUnknownParts() {
        let transfer = UUID().uuidString + ":" + UUID().uuidString
        let video = TransferParts.description(transfer, part: TransferParts.video)
        XCTAssertEqual(TransferParts.base(video), transfer); XCTAssertEqual(TransferParts.part(video), "video")
        XCTAssertEqual(TransferParts.base(transfer), transfer); XCTAssertNil(TransferParts.part(transfer))
        XCTAssertNil(TransferParts.part(transfer + "#subtitles")); XCTAssertNil(TransferParts.base(nil))
    }
    func testCombinedProgressWeightsVideoAndStaysInRange() {
        XCTAssertEqual(TransferParts.combined([:]), 0)
        XCTAssertEqual(TransferParts.combined(["video": 1, "audio": 1]), 1, accuracy: 0.0001)
        XCTAssertEqual(TransferParts.combined(["audio": 1]), 0.15, accuracy: 0.0001)
        XCTAssertGreaterThan(TransferParts.combined(["video": 0.5]), TransferParts.combined(["audio": 0.5]))
    }
    @MainActor func testRecordsValidatePartPathsAndOlderJobsDecode() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let library = DownloadLibrary(fileURL: file)
        var record = DownloadRecord(item: BrowseItem(contentID: "dQw4w9WgXcQ", kind: .video, title: "Video"),
                                    choice: DownloadChoice(id: "merged-137-140", name: "Video · 1080p (separate audio)", kind: .merged))
        XCTAssertNil(try JSONDecoder().decode(DownloadRecord.self, from: JSONEncoder().encode(record)).partPaths)
        record.partPaths = ["video": "../escape.mp4"]
        XCTAssertFalse(library.add(record))
        record.partPaths = ["subtitles": "Library/Application Support/DriftLoom/Media/a.mp4"]
        XCTAssertFalse(library.add(record))
        record.partPaths = ["video": "Library/Application Support/DriftLoom/Media/a.video.part.mp4"]
        XCTAssertTrue(library.add(record))
        XCTAssertEqual(DownloadLibrary(fileURL: file).records.first?.partPaths?["video"], "Library/Application Support/DriftLoom/Media/a.video.part.mp4")
    }
}
