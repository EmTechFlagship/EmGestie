import Foundation

/// Apple Mercury / PosterBoard wallpaper entry.
/// Source: https://cowabun.ga/wallpapers#apple-wallpapers
/// (Nugget `wallpapers-apple.json`, `.tendies` PosterBoard bundles).
struct AppleWallpaper: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var description: String?
    var url: String
    var preview: String

    var downloadURL: URL? { URL(string: url) }
    var previewURL: URL? { URL(string: preview) }

    /// `pocketposter://download?url=<tendies>` — same deep link the site uses on iOS.
    var pocketPosterURL: URL? {
        guard let downloadURL else { return nil }
        var comps = URLComponents(string: "pocketposter://download")
        comps?.queryItems = [URLQueryItem(name: "url", value: downloadURL.absoluteString)]
        return comps?.url
    }

    var isIPhone: Bool { name.lowercased().contains("iphone") || name.lowercased().hasPrefix("ios") }
    var isIPad: Bool { name.lowercased().contains("ipad") }

    var requirement: String? {
        guard let description, !description.isEmpty else { return nil }
        return description
    }
}
