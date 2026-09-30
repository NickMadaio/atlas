import Compression
import Foundation

/// A read-only reader for the ZIP container that .docx and .pptx files are.
///
/// Small on purpose: it finds named entries and inflates them, and does
/// nothing else. Every offset that comes out of the file is bounds-checked
/// before use — an attachment is a file from outside Atlas, and a malformed
/// one must fail rather than read past the end of the buffer.
struct ZipArchive {
    private let data: Data
    private let entries: [String: Entry]

    private struct Entry {
        let localHeaderOffset: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let method: UInt16
    }

    enum Failure: Error {
        case notAZipFile
        case malformed
        case unsupportedCompression
        case tooLarge
    }

    /// Refuses anything implausible for a lecture handout, which also bounds
    /// how much work a hostile file can cause.
    static let maximumEntrySize = 64 * 1_024 * 1_024

    init(url: URL) throws {
        let loaded = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(data: loaded)
    }

    init(data: Data) throws {
        self.data = data
        entries = try Self.readCentralDirectory(data)
    }

    var entryNames: [String] { Array(entries.keys) }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    /// Entry names matching a prefix, in the order the caller sorts them.
    func names(withPrefix prefix: String) -> [String] {
        entries.keys.filter { $0.hasPrefix(prefix) }
    }

    func data(for name: String) throws -> Data {
        guard let entry = entries[name] else { throw Failure.malformed }
        guard entry.uncompressedSize <= Self.maximumEntrySize else { throw Failure.tooLarge }

        // The local header repeats the name and extra-field lengths, and only
        // those are trustworthy for finding where the bytes actually start.
        let headerStart = entry.localHeaderOffset
        guard let signature = data.readUInt32(at: headerStart), signature == 0x0403_4b50,
              let nameLength = data.readUInt16(at: headerStart + 26),
              let extraLength = data.readUInt16(at: headerStart + 28) else {
            throw Failure.malformed
        }

        let payloadStart = headerStart + 30 + Int(nameLength) + Int(extraLength)
        let payloadEnd = payloadStart + entry.compressedSize
        guard payloadStart >= 0, payloadEnd <= data.count, payloadStart <= payloadEnd else {
            throw Failure.malformed
        }
        let payload = data.subdata(in: payloadStart..<payloadEnd)

        switch entry.method {
        case 0:
            return payload
        case 8:
            return try Self.inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw Failure.unsupportedCompression
        }
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        guard data.count > 22 else { throw Failure.notAZipFile }

        // The end-of-central-directory record sits at the end, after a comment
        // of unknown length, so it is found by scanning backwards.
        let searchFloor = max(0, data.count - 22 - 65_535)
        var eocd: Int?
        var cursor = data.count - 22
        while cursor >= searchFloor {
            if data.readUInt32(at: cursor) == 0x0605_4b50 { eocd = cursor; break }
            cursor -= 1
        }
        guard let eocd,
              let entryCount = data.readUInt16(at: eocd + 10),
              let directorySize = data.readUInt32(at: eocd + 12),
              let directoryOffset = data.readUInt32(at: eocd + 16) else {
            throw Failure.notAZipFile
        }

        var start = Int(directoryOffset)
        let end = start + Int(directorySize)
        guard start >= 0, end <= data.count else { throw Failure.malformed }

        var found: [String: Entry] = [:]
        for _ in 0..<Int(entryCount) {
            guard start + 46 <= end,
                  data.readUInt32(at: start) == 0x0201_4b50,
                  let method = data.readUInt16(at: start + 10),
                  let compressedSize = data.readUInt32(at: start + 20),
                  let uncompressedSize = data.readUInt32(at: start + 24),
                  let nameLength = data.readUInt16(at: start + 28),
                  let extraLength = data.readUInt16(at: start + 30),
                  let commentLength = data.readUInt16(at: start + 32),
                  let headerOffset = data.readUInt32(at: start + 42) else {
                throw Failure.malformed
            }

            let nameStart = start + 46
            let nameEnd = nameStart + Int(nameLength)
            guard nameEnd <= end else { throw Failure.malformed }
            let name = String(decoding: data.subdata(in: nameStart..<nameEnd), as: UTF8.self)

            // ZIP64 parks the real sizes in the extra field; a lecture handout
            // that needs it is out of scope, and guessing would be worse.
            guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF else {
                throw Failure.tooLarge
            }

            found[name] = Entry(
                localHeaderOffset: Int(headerOffset),
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                method: method
            )
            start = nameEnd + Int(extraLength) + Int(commentLength)
        }
        return found
    }

    /// ZIP stores raw DEFLATE, which is what COMPRESSION_ZLIB decodes here.
    private static func inflate(_ payload: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        // A little headroom: some writers round the stated size.
        let capacity = min(Self.maximumEntrySize, expectedSize + 1_024)
        var output = Data(count: capacity)

        let written: Int = try output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else {
                throw Failure.malformed
            }
            return payload.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, capacity,
                    sourceBase, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw Failure.malformed }
        return output.prefix(written)
    }
}

private extension Data {
    /// Little-endian reads that return nil rather than trapping when the file
    /// is shorter than its own offsets claim.
    func readUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func readUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }
}
