// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Foundation
import YouTubeKit

/// One language of a video's audio: the original, or a dub (the uploader's or YouTube's automatic one).
public struct AudioTrack: Identifiable, Hashable, Sendable {
    /// The language code YouTube tags the stream with, for example "ru" or "en-US".
    public let id: String
    public let isOriginal: Bool
    public let isAutomaticDub: Bool
    /// The separate audio stream; nil for a rendition inside an HLS stream, which the player item selects.
    public let url: URL?
    public var name: String {
        let language = Locale.current.localizedString(forIdentifier: id) ?? Locale.current.localizedString(forLanguageCode: id) ?? id
        if isOriginal { return L("\(language) (original)") }
        return isAutomaticDub ? L("\(language) (auto-dubbed)") : language
    }
}

extension AudioTrack {
    /// YouTube's HLS audio renditions are named like "Русский - dubbed" or "American English - original";
    /// AVFoundation keeps that NAME as the title metadata and shows a localized language as `displayName`.
    init(option: AVMediaSelectionOption) {
        let title = AVMetadataItem.metadataItems(from: option.commonMetadata, filteredByIdentifier: .commonIdentifierTitle).first?.stringValue
        let label = (title ?? option.displayName).lowercased()
        id = option.extendedLanguageTag ?? option.locale?.identifier ?? option.displayName
        isOriginal = label.hasSuffix("original"); isAutomaticDub = label.contains("auto"); url = nil
    }
    static func ordered(_ tracks: [AudioTrack]) -> [AudioTrack] {
        tracks.sorted { ($0.isOriginal ? 0 : 1, $0.name) < ($1.isOriginal ? 0 : 1, $1.name) }
    }
}

extension YouTubeKit.Stream {
    /// Dubbed audio is only used when chosen; the original (or the only) track is the default everywhere.
    var isDubbedAudio: Bool { audioContent.map { $0 != "original" } ?? false }
}

extension Array where Element == YouTubeKit.Stream {
    /// Streams without dubbed audio, as YouTubeKit returned them before dubs were kept.
    var withoutDubs: [YouTubeKit.Stream] { filter { !$0.isDubbedAudio && !$0.isDynamicRangeCompressed } }

    /// The highest-bitrate AAC stream of each audio language, original first; empty for single-language videos.
    var audioTracks: [AudioTrack] {
        var best: [String: YouTubeKit.Stream] = [:]
        for stream in self where !stream.includesVideoTrack && stream.isNativelyPlayable && stream.fileExtension == .m4a && !stream.isDynamicRangeCompressed {
            guard let language = stream.audioLanguage, !language.isEmpty, language.count <= 20 else { continue }
            if let current = best[language], (current.bitrate ?? 0) >= (stream.bitrate ?? 0) { continue }
            best[language] = stream
        }
        guard best.count > 1 else { return [] }
        return AudioTrack.ordered(best.map { language, stream in
            AudioTrack(id: language, isOriginal: stream.audioContent == "original", isAutomaticDub: stream.audioContent == "dubbed-auto", url: stream.url)
        })
    }
}
