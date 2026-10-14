import Foundation
import UIKit

/// Best-effort "Apply" for `.tendies` PosterBoard bundles.
///
/// There is no public iOS 26 / 27 API that installs a PosterBoard
/// wallpaper silently. The supported path is handing the `.tendies`
/// file to a tool that understands it (Nugget / Pocket Poster) or
/// sharing it to Files / AirDrop.
///
/// This service:
/// - opens `pocketposter://download?url=<remote-tendies-url>` when available
/// - otherwise falls back to the system Share sheet ( caller presents ShareLink )
enum TendiesApplyService {
    /// Remote-URL hand-off used by cowabun.ga on iOS.
    static func pocketPosterURL(remoteURL: URL) -> URL? {
        var comps = URLComponents(string: "pocketposter://download")
        comps?.queryItems = [URLQueryItem(name: "url", value: remoteURL.absoluteString)]
        return comps?.url
    }

    static func canOpenPocketPoster() -> Bool {
        guard let probe = URL(string: "pocketposter://") else { return false }
        return UIApplication.shared.canOpenURL(probe)
    }

    /// Try to open Pocket Poster with the *remote* tendies URL.
    /// Returns true if the open was attempted.
    @MainActor
    @discardableResult
    static func applyViaPocketPoster(remoteURL: URL) -> Bool {
        guard let target = pocketPosterURL(remoteURL: remoteURL) else { return false }
        guard UIApplication.shared.canOpenURL(target) else { return false }
        UIApplication.shared.open(target)
        return true
    }

    /// Remote URL recorded on an imported Poster (`mercuryDescriptor = "source: <url>"`).
    static func remoteURL(for poster: Poster) -> URL? {
        guard let descriptor = poster.mercuryDescriptor,
              let range = descriptor.range(of: "https://"),
              let url = URL(string: String(descriptor[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return url
    }

    /// Delete the downloaded `.tendies` file and clear the reference.
    /// Returns true if a file was removed.
    @MainActor
    @discardableResult
    static func removeTendies(from poster: Poster) -> Bool {
        guard poster.tendiesFilename != nil else { return false }
        PosterFileStore.remove(filename: poster.tendiesFilename)
        poster.tendiesFilename = nil
        return true
    }
}
