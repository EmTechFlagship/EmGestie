import Foundation
import UIKit
import UniformTypeIdentifiers

/// Handles `.posterboard`, `.mercury`, `.tendies`, `.wallpaper`, `.zip` plus
/// plain images / videos.
///
/// `.tendies` (Nugget PosterBoard bundles) are stored verbatim — iOS has no
/// built-in unzip, so the file is kept for Share / Pocket Poster hand-off
/// and its preview image is used for display.
/// Bundle layout we accept (all optional except one visual asset):
/// ```
///   MyWallpaper.posterboard/
///     poster.jpg | poster.heic | poster.png
///     motion.mov / live.mov (optional)
///     metadata.json | Info.plist | mercury.json (optional, preserved verbatim)
/// ```
/// Plain `.zip` files with the same layout are unarchived automatically (macOS only).
enum PosterImportService {
    static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff"
    ]
    static let supportedVideoExtensions: Set<String> = [
        "mov", "mp4", "m4v"
    ]
    static let bundleExtensions: Set<String> = [
        "posterboard", "mercury", "wallpaper", "pboard", "tendies"
    ]
    static let metadataFilenames: Set<String> = [
        "metadata.json", "mercury.json", "poster.json", "info.plist", "manifest.json"
    ]

    struct ImportedPoster {
        var title: String
        var kind: PosterKind
        var source: PosterSource
        var imageFilename: String? = nil
        var videoFilename: String? = nil
        var tendiesFilename: String? = nil
        var width: Int = 0
        var height: Int = 0
        var descriptor: String? = nil
        var tags: [String] = []
    }

    /// Import a security-scoped URL (from fileImporter / drag & drop).
    static func importFile(at url: URL) throws -> ImportedPoster {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            return try importZip(at: url)
        }
        if ext == "tendies" {
            return try importTendiesFile(at: url)
        }
        if bundleExtensions.contains(ext) {
            return try importBundle(at: url)
        }
        return try importSingleFile(at: url)
    }

    // MARK: - Single files

    static func importSingleFile(at url: URL) throws -> ImportedPoster {
        let ext = url.pathExtension.lowercased()
        let base = url.deletingPathExtension().lastPathComponent
        if supportedImageExtensions.contains(ext) {
            guard let filename = PosterFileStore.copy(from: url) else {
                throw ImportError.copyFailed
            }
            let size = imageSize(at: PosterFileStore.url(for: filename))
            return ImportedPoster(
                title: base.isEmpty ? "Imported poster" : base,
                kind: .image,
                source: .imported,
                imageFilename: filename,
                width: Int(size.width), height: Int(size.height),
                tags: []
            )
        }
        if supportedVideoExtensions.contains(ext) {
            guard let filename = PosterFileStore.copy(from: url) else {
                throw ImportError.copyFailed
            }
            return ImportedPoster(
                title: base.isEmpty ? "Imported motion" : base,
                kind: .motion,
                source: .imported,
                videoFilename: filename,
                width: 0, height: 0,
                tags: ["motion"]
            )
        }
        throw ImportError.unsupportedType(ext)
    }

    // MARK: - Bundles

    /// `.tendies` files are Nugget PosterBoard bundles (zip-based).
    /// Kept verbatim for Share / Nugget / Pocket Poster hand-off.
    static func importTendiesFile(at url: URL) throws -> ImportedPoster {
        guard let filename = PosterFileStore.copy(from: url, fileExtension: "tendies") else {
            throw ImportError.copyFailed
        }
        let base = url.deletingPathExtension().lastPathComponent
        // Prefer embedded metadata when this is one of our own bundles.
        if let storedURL = PosterFileStore.url(for: filename),
           let meta = TendiesBuilderService.readMetadata(from: storedURL) {
            return ImportedPoster(
                title: meta.title.isEmpty ? base : meta.title,
                kind: .image,
                source: .posterboard,
                tendiesFilename: filename,
                width: meta.width, height: meta.height,
                descriptor: "tendies bundle: \(url.lastPathComponent)",
                tags: ["apple", "posterboard", "tendies"]
            )
        }
        return ImportedPoster(
            title: base.isEmpty ? "Apple wallpaper" : base,
            kind: .image,
            source: .posterboard,
            tendiesFilename: filename,
            width: 0, height: 0,
            descriptor: "tendies bundle: \(url.lastPathComponent)",
            tags: ["apple", "posterboard", "tendies"]
        )
    }

    static func importBundle(at url: URL) throws -> ImportedPoster {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            // Single-file with bundle extension, e.g. `foo.mercury` that is an image.
            return try importSingleFile(at: url)
        }
        let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        let ext = url.pathExtension.lowercased()
        let source: PosterSource = ext == "mercury" ? .mercury : .posterboard
        let title = url.deletingPathExtension().lastPathComponent

        var imageFile: URL?
        var videoFile: URL?
        var descriptorText: String?

        for file in contents {
            let name = file.lastPathComponent.lowercased()
            let fext = file.pathExtension.lowercased()
            if metadataFilenames.contains(name) {
                descriptorText = (try? String(contentsOf: file, encoding: .utf8)) ?? descriptorText
            } else if supportedImageExtensions.contains(fext), imageFile == nil {
                imageFile = file
            } else if supportedVideoExtensions.contains(fext), videoFile == nil {
                videoFile = file
            }
        }
        // Fall back: first file of any kind.
        if imageFile == nil { imageFile = contents.first }

        guard imageFile != nil || videoFile != nil else {
            throw ImportError.emptyBundle
        }

        var imageFilename: String?
        var videoFilename: String?
        var width = 0, height = 0
        if let imageFile {
            imageFilename = PosterFileStore.copy(from: imageFile)
            let size = imageSize(at: PosterFileStore.url(for: imageFilename))
            width = Int(size.width); height = Int(size.height)
        }
        if let videoFile {
            videoFilename = PosterFileStore.copy(from: videoFile)
        }

        let kind: PosterKind = videoFilename != nil ? .motion : .image
        return ImportedPoster(
            title: title.isEmpty ? "Imported bundle" : title,
            kind: kind,
            source: source,
            imageFilename: imageFilename,
            videoFilename: videoFilename,
            width: width, height: height,
            descriptor: descriptorText,
            tags: [source == .mercury ? "mercury" : "posterboard"]
        )
    }

    static func importZip(at url: URL) throws -> ImportedPoster {
        #if os(macOS)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("posterboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", url.path, "-d", tmp.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ImportError.unzipFailed }

        let fm = FileManager.default
        let top = (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        // If zip contains a single directory, descend into it.
        if top.count == 1, (try? top[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return try importBundle(at: top[0])
        }
        // Otherwise treat tmp as the bundle root.
        return try importBundle(at: tmp)
        #else
        // iOS devices have no /usr/bin/unzip: keep the archive verbatim
        // for Share / Nugget hand-off.
        guard let filename = PosterFileStore.copy(from: url, fileExtension: "zip") else {
            throw ImportError.copyFailed
        }
        let base = url.deletingPathExtension().lastPathComponent
        return ImportedPoster(
            title: base.isEmpty ? "Wallpaper archive" : base,
            kind: .image,
            source: .posterboard,
            tendiesFilename: filename,
            descriptor: "zip archive: \(url.lastPathComponent)",
            tags: ["posterboard", "zip"]
        )
        #endif
    }

    // MARK: - Helpers

    static func importImageData(_ data: Data, suggestedName: String?) throws -> ImportedPoster {
        let ext = imageExtension(for: data) ?? "jpg"
        guard let filename = PosterFileStore.save(data: data, fileExtension: ext) else {
            throw ImportError.copyFailed
        }
        let size = imageSize(at: PosterFileStore.url(for: filename))
        return ImportedPoster(
            title: suggestedName ?? "Imported poster",
            kind: .image,
            source: .imported,
            imageFilename: filename,
            width: Int(size.width), height: Int(size.height),
            tags: []
        )
    }

    private static func imageSize(at url: URL?) -> CGSize {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return .zero }
        let w = (props[kCGImagePropertyPixelWidth] as? Double) ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? Double) ?? 0
        return CGSize(width: w, height: h)
    }

    private static func imageExtension(for data: Data) -> String? {
        // Minimal magic-byte sniffing.
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.count > 12 {
            let ftyp = String(bytes: data[4..<12], encoding: .ascii) ?? ""
            if ftyp.contains("heic") { return "heic" }
            if ftyp.contains("heif") || ftyp.contains("mif1") { return "heif" }
            if ftyp.contains("mp42") || ftyp.contains("isom") { return "mp4" }
        }
        return nil
    }

    enum ImportError: LocalizedError {
        case unsupportedType(String)
        case copyFailed
        case emptyBundle
        case unzipFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let ext):
                return ext.isEmpty
                    ? "Unsupported file type."
                    : "Unsupported file type “.\(ext)”. Use an image, video, .posterboard, .mercury or .zip."
            case .copyFailed: return "Could not copy the file into PosterBoard."
            case .emptyBundle: return "Bundle contains no image or video."
            case .unzipFailed: return "Could not unzip the archive."
            }
        }
    }
}

extension Data {
    func starts(with bytes: [UInt8]) -> Bool {
        guard count >= bytes.count else { return false }
        return prefix(bytes.count).elementsEqual(bytes)
    }
}
