import Foundation
import UIKit

/// File-backed storage for poster assets.
///
/// Posters keep only filenames in SwiftData. Binary data lives in:
///   Application Support/Posters/<uuid>.<ext>
///
/// This keeps the store small and makes ShareLink / Photo saves cheap.
enum PosterFileStore {
    static var postersDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Posters", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        return postersDirectory.appendingPathComponent(filename)
    }

    static func imageURL(for poster: Poster) -> URL? {
        url(for: poster.imageFilename) ?? url(for: poster.thumbnailFilename)
    }

    static func videoURL(for poster: Poster) -> URL? {
        url(for: poster.videoFilename)
    }

    static func tendiesURL(for poster: Poster) -> URL? {
        url(for: poster.tendiesFilename)
    }

    @discardableResult
    static func save(data: Data, fileExtension: String) -> String? {
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let url = postersDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: [.atomic])
            return filename
        } catch {
            return nil
        }
    }

    @discardableResult
    static func copy(from sourceURL: URL, fileExtension: String? = nil) -> String? {
        let ext = fileExtension ?? sourceURL.pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "dat" : ext
        let filename = "\(UUID().uuidString).\(safeExt)"
        let dest = postersDirectory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return filename
        } catch {
            return nil
        }
    }

    static func remove(filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: postersDirectory.appendingPathComponent(filename))
    }

    static func removeAll(for poster: Poster) {
        remove(filename: poster.imageFilename)
        remove(filename: poster.videoFilename)
        remove(filename: poster.thumbnailFilename)
        remove(filename: poster.tendiesFilename)
    }

    static func totalBytes() -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: postersDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var total = 0
        for url in urls {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        return total
    }

    static func loadImage(for poster: Poster) -> UIImage? {
        guard let url = imageURL(for: poster) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
