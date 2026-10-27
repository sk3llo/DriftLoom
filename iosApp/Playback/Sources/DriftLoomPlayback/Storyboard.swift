// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// YouTube's seek-bar preview frames: sprite sheets of small frames laid out in a grid.
/// Parsed from the player response's `storyboards.playerStoryboardSpecRenderer.spec`:
/// "<url with $L and $N>|<level 0>|<level 1>|…", each level "width#height#count#columns#rows#intervalMs#name#signature".
public struct Storyboard: Equatable, Sendable {
    public struct Level: Equatable, Sendable {
        public let width: Int, height: Int, count: Int, columns: Int, rows: Int
        /// Milliseconds between frames; 0 means the frames span the whole video evenly.
        public let interval: Int
        let template: String, name: String, signature: String
    }
    public struct Frame: Equatable, Sendable {
        public let sheet: URL
        /// The frame's position inside the sheet, in pixels.
        public let x: Int, y: Int, width: Int, height: Int
    }
    public let levels: [Level]

    public init?(spec: String) {
        let parts = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.count <= 10, let base = URL(string: parts[0].replacingOccurrences(of: "$L", with: "0").replacingOccurrences(of: "$N", with: "x")),
              base.scheme == "https", base.host?.hasSuffix("ytimg.com") == true else { return nil }
        levels = parts.dropFirst().enumerated().compactMap { index, raw in
            let fields = raw.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 8, let width = Int(fields[0]), let height = Int(fields[1]), let count = Int(fields[2]),
                  let columns = Int(fields[3]), let rows = Int(fields[4]), let interval = Int(fields[5]),
                  (1...1280).contains(width), (1...720).contains(height), (1...100_000).contains(count),
                  (1...50).contains(columns), (1...50).contains(rows), interval >= 0 else { return nil }
            let template = parts[0].replacingOccurrences(of: "$L", with: String(index))
            return Level(width: width, height: height, count: count, columns: columns, rows: rows, interval: interval,
                         template: template, name: fields[6], signature: fields[7])
        }
        guard !levels.isEmpty else { return nil }
    }

    /// The level whose frames are closest to `width` pixels wide without being smaller, else the largest.
    public func level(forWidth width: Int) -> Level {
        levels.filter { $0.width >= width }.min { $0.width < $1.width } ?? levels.max { $0.width < $1.width }!
    }

    /// The preview frame for a playback time.
    public func frame(at seconds: Double, duration: Double, width: Int = 160) -> Frame? {
        let level = level(forWidth: width)
        guard seconds.isFinite, duration.isFinite, duration > 0, level.count > 0 else { return nil }
        let index: Int
        if level.interval > 0 { index = Int(max(0, seconds) * 1000) / level.interval }
        else { index = Int(max(0, min(seconds, duration)) / duration * Double(level.count - 1)) }
        let frame = min(index, level.count - 1), perSheet = level.columns * level.rows
        let sheet = frame / perSheet, cell = frame % perSheet
        // "$M" in the level name is the sheet number; "default" names the only sheet.
        let name = level.name.replacingOccurrences(of: "$M", with: String(sheet))
        var text = level.template.replacingOccurrences(of: "$N", with: name)
        if !level.signature.isEmpty { text += (text.contains("?") ? "&" : "?") + "sigh=" + level.signature }
        guard let url = URL(string: text), url.scheme == "https", url.host?.hasSuffix("ytimg.com") == true else { return nil }
        return Frame(sheet: url, x: (cell % level.columns) * level.width, y: (cell / level.columns) * level.height,
                     width: level.width, height: level.height)
    }
}
