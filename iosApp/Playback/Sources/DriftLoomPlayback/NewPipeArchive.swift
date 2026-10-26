// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import zlib

/// Read only named members into memory. Never extract archive paths or deserialize Java preferences.
enum NewPipeArchive {
    static func database(_ data: Data) throws -> Data {
        let found = try members(data, limits: ["newpipe.db": 100_000_000, "driftloom.db": 100_000_000])
        guard found.count <= 1, let database = found.values.first, database.starts(with: Data("SQLite format 3\0".utf8)) else {
            throw BrowseError.unavailable("This ZIP doesn't contain a supported NewPipe database backup.")
        }
        return database
    }
    /// The JSON preferences NewPipe 0.27+ writes next to the database, if present.
    static func preferences(_ data: Data) throws -> Data? {
        try members(data, limits: ["preferences.json": 2_000_000])["preferences.json"]
    }
    /// Each requested member at most once, size-limited and CRC-checked.
    static func members(_ data: Data, limits: [String: Int]) throws -> [String: Data] {
        try members(data, limit: { limits[$0] })
    }
    /// Members whose name `limit` returns a size limit for (nil skips the member).
    static func members(_ data: Data, limit: (String) -> Int?) throws -> [String: Data] {
        guard data.count <= 50_000_000, data.count >= 22 else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ size: Int) throws -> Int {
            guard offset >= 0, offset <= bytes.count - size else { throw CocoaError(.fileReadCorruptFile) }
            return (0..<size).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) }
        }
        let minimum = max(0, bytes.count - 65_557)
        var endOffset: Int?
        for position in stride(from: bytes.count - 22, through: minimum, by: -1) {
            if (try? number(position, 4)) == 0x06054b50,
               let commentLength = try? number(position + 20, 2), position + 22 + commentLength == bytes.count {
                endOffset = position; break
            }
        }
        guard let end = endOffset else { throw CocoaError(.fileReadCorruptFile) }
        guard try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw CocoaError(.fileReadCorruptFile) }
        let count = try number(end + 10, 2), central = try number(end + 16, 4)
        guard count > 0, count <= 1000, central < end else { throw CocoaError(.fileReadCorruptFile) }
        var offset = central, found: [String: Data] = [:]
        for _ in 0..<count {
            guard try number(offset, 4) == 0x02014b50 else { throw CocoaError(.fileReadCorruptFile) }
            let flags = try number(offset + 8, 2), method = try number(offset + 10, 2)
            let crc = try number(offset + 16, 4), size = try number(offset + 20, 4), expanded = try number(offset + 24, 4)
            let nameLength = try number(offset + 28, 2), extra = try number(offset + 30, 2), comment = try number(offset + 32, 2)
            let local = try number(offset + 42, 4), nameStart = offset + 46
            guard nameStart <= bytes.count - nameLength else { throw CocoaError(.fileReadCorruptFile) }
            let name = String(bytes: bytes[nameStart..<(nameStart + nameLength)], encoding: .utf8)
            offset = nameStart + nameLength + extra + comment
            guard offset <= end else { throw CocoaError(.fileReadCorruptFile) }
            guard let name, let limit = limit(name) else { continue }
            guard found[name] == nil, flags & 1 == 0, (method == 0 || method == 8), expanded > 0, expanded <= limit,
                  try number(local, 4) == 0x04034b50 else { throw CocoaError(.fileReadCorruptFile) }
            let localNameLength = try number(local + 26, 2), localExtra = try number(local + 28, 2)
            let start = local + 30 + localNameLength + localExtra
            guard start <= central - size else { throw CocoaError(.fileReadCorruptFile) }
            let compressed = Data(bytes[start..<(start + size)])
            let output: Data
            if method == 0 {
                guard size == expanded else { throw CocoaError(.fileReadCorruptFile) }
                output = compressed
            } else {
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw CocoaError(.fileReadCorruptFile) }
                defer { inflateEnd(&stream) }
                var decoded = Data(count: expanded)
                let result = compressed.withUnsafeBytes { source in decoded.withUnsafeMutableBytes { destination -> Int32 in
                    stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
                    stream.avail_in = uInt(size)
                    stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress
                    stream.avail_out = uInt(expanded)
                    return inflate(&stream, Z_FINISH)
                } }
                guard result == Z_STREAM_END, stream.total_out == expanded, stream.avail_in == 0 else { throw CocoaError(.fileReadCorruptFile) }
                output = decoded
            }
            let actual = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(output.count)) }
            guard UInt32(actual) == UInt32(crc) else { throw CocoaError(.fileReadCorruptFile) }
            found[name] = output
        }
        return found
    }
}
