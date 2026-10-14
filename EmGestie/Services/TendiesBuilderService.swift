import Foundation
import UIKit

/// Builds `.tendies` PosterBoard bundles locally (Nugget-compatible layout).
///
/// A `.tendies` file is just a zip archive. Nugget / Pocket Poster expect:
/// ```
///   poster.jpg | poster.png | poster.heic   (required visual asset)
///   motion.mov                              (optional)
///   metadata.json                           (title, size, provenance)
/// ```
///
/// This builder uses a dependency-free stored (uncompressed) zip writer so it
/// works sandboxed on iOS — no `/usr/bin/zip`, no jailbreak, no XNU needed.
/// The existing hand-off in `TendiesApplyService` (Share / Pocket Poster)
/// is still how the file gets installed; iOS 26/27 has no silent-install API.
enum TendiesBuilderService {
    struct TendiesMetadata: Codable {
        var title: String
        var width: Int
        var height: Int
        var kind: String
        var createdAt: Date
        var generator: String
        var version: Int
    }

    enum BuildError: LocalizedError {
        case noAsset
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noAsset: return "This poster has no image to package."
            case .writeFailed: return "Could not write the .tendies file."
            }
        }
    }

    /// Packages `poster`'s image (+ optional motion) into a `.tendies` file
    /// inside `PosterFileStore.postersDirectory`. Returns the stored filename.
    /// Caller is responsible for assigning `poster.tendiesFilename` + saving.
    @discardableResult
    static func buildTendies(for poster: Poster) throws -> String {
        guard let imageURL = PosterFileStore.imageURL(for: poster),
              let imageData = try? Data(contentsOf: imageURL) else {
            throw BuildError.noAsset
        }
        let ext = imageURL.pathExtension.lowercased().isEmpty ? "jpg" : imageURL.pathExtension.lowercased()
        let metadata = TendiesMetadata(
            title: poster.title,
            width: poster.width,
            height: poster.height,
            kind: poster.kindRaw,
            createdAt: Date(),
            generator: "EmGestie",
            version: 1
        )
        let metadataData = (try? JSONEncoder().encode(metadata)) ?? Data()
        var entries: [(name: String, data: Data)] = [
            ("poster.\(ext)", imageData),
            ("metadata.json", metadataData),
        ]
        if let videoURL = PosterFileStore.videoURL(for: poster),
           let videoData = try? Data(contentsOf: videoURL) {
            entries.append(("motion.mov", videoData))
        }
        let zipData = MinimalZip.create(entries: entries)

        let safeBase = sanitize(postersTitle: poster.title)
        let filename = "\(safeBase)-\(UUID().uuidString.prefix(8)).tendies"
        let dest = PosterFileStore.postersDirectory.appendingPathComponent(filename)
        do {
            try zipData.write(to: dest, options: [.atomic])
        } catch {
            throw BuildError.writeFailed
        }
        // Remove any previous bundle so a poster holds at most one.
        if let old = poster.tendiesFilename, old != filename {
            PosterFileStore.remove(filename: old)
        }
        return filename
    }

    /// Best-effort read of `metadata.json` from our own (stored) bundles.
    /// Returns nil for foreign/deflated zips — caller keeps verbatim import.
    static func readMetadata(from url: URL) -> TendiesMetadata? {
        guard let data = try? Data(contentsOf: url),
              let entries = try? MinimalZip.readStoredEntries(from: data),
              let meta = entries["metadata.json"] else { return nil }
        return try? JSONDecoder().decode(TendiesMetadata.self, from: meta)
    }

    private static func sanitize(postersTitle title: String) -> String {
        let base = title.isEmpty ? "poster" : title
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var out = ""
        for scalar in base.unicodeScalars {
            out.append(allowed.contains(scalar) ? Character(scalar) : "-")
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if out.isEmpty { out = "poster" }
        return String(out.prefix(40))
    }
}

// MARK: - Minimal stored-zip writer/reader (no Compression dependency)

/// Minimal zip handling: writes `stored` (method 0) entries and reads them
/// back. Deflated entries from third-party tools are skipped on read.
enum MinimalZip {
    static func create(entries: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        var offset: UInt32 = 0
        let now = dosDateTime(Date())

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            // Local file header
            out.appendUInt32(0x0403_4B50)
            out.appendUInt16(20) // version needed
            out.appendUInt16(0) // flags
            out.appendUInt16(0) // method: stored
            out.appendUInt16(now.time)
            out.appendUInt16(now.date)
            out.appendUInt32(crc)
            out.appendUInt32(size)
            out.appendUInt32(size)
            out.appendUInt16(UInt16(nameData.count))
            out.appendUInt16(0) // extra len
            out.append(nameData)
            out.append(entry.data)

            // Central directory record
            central.appendUInt32(0x0201_4B50)
            central.appendUInt16(20) // made by
            central.appendUInt16(20) // needed
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(now.time)
            central.appendUInt16(now.date)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0) // disk
            central.appendUInt16(0) // int attr
            central.appendUInt32(0) // ext attr
            central.appendUInt32(offset)
            central.append(nameData)

            offset += UInt32(30 + nameData.count + entry.data.count)
        }
        let centralOffset = offset
        let centralSize = UInt32(central.count)
        out.append(central)
        // End of central directory
        out.appendUInt32(0x0605_4B50)
        out.appendUInt16(0)
        out.appendUInt16(0)
        out.appendUInt16(UInt16(entries.count))
        out.appendUInt16(UInt16(entries.count))
        out.appendUInt32(centralSize)
        out.appendUInt32(centralOffset)
        out.appendUInt16(0)
        return out
    }

    static func readStoredEntries(from data: Data) throws -> [String: Data] {
        var result: [String: Data] = [:]
        var cursor = 0
        while cursor + 30 <= data.count {
            let sig = data.uint32LE(at: cursor)
            guard sig == 0x0403_4B50 else { break }
            let method = data.uint16LE(at: cursor + 8)
            let nameLen = Int(data.uint16LE(at: cursor + 26))
            let extraLen = Int(data.uint16LE(at: cursor + 28))
            let size = Int(data.uint32LE(at: cursor + 18))
            let headerEnd = cursor + 30 + nameLen + extraLen
            guard headerEnd >= 0, headerEnd + size <= data.count else { break }
            let nameData = data[cursor + 30 ..< cursor + 30 + nameLen]
            // Only stored entries can be read without an inflater.
            if method == 0, let name = String(data: nameData, encoding: .utf8) {
                result[name] = data[headerEnd ..< headerEnd + size]
            }
            cursor = headerEnd + size
        }
        return result
    }

    // MARK: helpers

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let y = max(1980, c.year ?? 1980) - 1980
        let time = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        let dosDate = UInt16((y << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        return (time, dosDate)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[idx]
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) == 1 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()
}

private extension Data {
    mutating func appendUInt16(_ v: UInt16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendUInt32(_ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
