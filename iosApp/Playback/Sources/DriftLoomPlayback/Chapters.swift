// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct VideoChapter: Equatable, Sendable {
    public let start: Double
    public let title: String
    public init(start: Double, title: String) { self.start = start; self.title = title }
    /// The start as written in descriptions: 4:02 or 1:02:03.
    public var timestamp: String {
        let value = Int(start)
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Chapters from a description's timestamps, following YouTube's rule: at least three, the first at 0:00,
/// in ascending order and at least 10 seconds apart. Otherwise there are none, as on YouTube.
public enum VideoChapters {
    private static let timestamp = #"(?:(\d{1,2}):)?(\d{1,2}):(\d{2})"#
    private static let leading = try! NSRegularExpression(pattern: #"^\s*[\[(]?"# + timestamp + #"[\])]?\s*[-–—:|·.]?\s*(.+?)\s*$"#)
    private static let trailing = try! NSRegularExpression(pattern: #"^\s*(.+?)\s*[-–—:|·]?\s*[\[(]?"# + timestamp + #"[\])]?\s*$"#)

    public static func parse(_ description: String, duration: Double? = nil) -> [VideoChapter] {
        var chapters: [VideoChapter] = []
        for line in description.split(whereSeparator: \.isNewline).prefix(2000) {
            guard let chapter = chapter(in: String(line)) else { continue }
            if chapters.isEmpty, chapter.start != 0 { continue }
            if let last = chapters.last, chapter.start <= last.start { continue }
            chapters.append(chapter)
        }
        if let duration, duration > 0 { chapters.removeAll { $0.start >= duration } }
        let spaced = zip(chapters, chapters.dropFirst()).allSatisfy { $1.start - $0.start >= 10 }
        guard chapters.count >= 3, chapters.first?.start == 0, spaced else { return [] }
        return chapters
    }

    /// The chapter playing at `time`.
    public static func index(at time: Double, in chapters: [VideoChapter]) -> Int? {
        chapters.lastIndex { $0.start <= time }
    }

    private static func chapter(in line: String) -> VideoChapter? {
        let range = NSRange(line.startIndex..., in: line)
        if let match = leading.firstMatch(in: line, range: range) {
            return make(line, match, hours: 1, minutes: 2, seconds: 3, title: 4)
        }
        if let match = trailing.firstMatch(in: line, range: range) {
            return make(line, match, hours: 2, minutes: 3, seconds: 4, title: 1)
        }
        return nil
    }
    private static func make(_ line: String, _ match: NSTextCheckingResult, hours: Int, minutes: Int, seconds: Int, title: Int) -> VideoChapter? {
        func group(_ index: Int) -> String? { Range(match.range(at: index), in: line).map { String(line[$0]) } }
        guard let m = group(minutes).flatMap(Int.init), let s = group(seconds).flatMap(Int.init), s < 60,
              let name = group(title)?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name.count <= 200 else { return nil }
        let h = group(hours).flatMap(Int.init) ?? 0
        if h > 0, m >= 60 { return nil }
        return VideoChapter(start: Double(h * 3600 + m * 60 + s), title: name)
    }
}
