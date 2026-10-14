import Foundation

/// Loads the bundled Apple catalog (snapshot of cowabun.ga `#apple-wallpapers`)
/// and downloads `.tendies` PosterBoard bundles into app storage.
enum AppleWallpaperService {
    static func loadBundled() -> [AppleWallpaper] {
        guard let url = Bundle.main.url(forResource: "apple-wallpapers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([AppleWallpaper].self, from: data)
        else { return [] }
        return items.sorted { $0.id > $1.id }
    }

    /// Downloads a `.tendies` bundle to Application Support/Posters.
    /// Returns the local file URL. Throws URLError / file errors.
    static func downloadTendies(for wallpaper: AppleWallpaper) async throws -> URL {
        guard let remote = wallpaper.downloadURL else { throw URLError(.badURL) }
        let (tmpURL, _) = try await URLSession.shared.download(from: remote)
        let safeName = wallpaper.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(safeName)-\(wallpaper.id).tendies"
        let dest = PosterFileStore.postersDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        return dest
    }

    /// Downloads the preview PNG so an imported Poster has a local thumbnail.
    static func downloadPreview(for wallpaper: AppleWallpaper) async throws -> String? {
        guard let remote = wallpaper.previewURL else { return nil }
        let (data, _) = try await URLSession.shared.data(from: remote)
        return PosterFileStore.save(data: data, fileExtension: "png")
    }
}
