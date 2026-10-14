import Foundation
import Photos
import UIKit

/// Saves poster assets to the system Photo Library so they can be picked
/// from the iOS PosterBoard gallery:
///
/// Lock Screen (long-press) → ＋ → Photos → choose saved wallpaper.
/// There is no public API to install a Lock Screen poster directly on
/// iOS 26 / 27, so this hand-off is the Apple-sanctioned path.
@MainActor
enum PhotoLibraryService {
    enum SaveError: LocalizedError {
        case noAsset
        case denied
        case failed(Error)

        var errorDescription: String? {
            switch self {
            case .noAsset: return "This poster has no image to save."
            case .denied:
                return "Photo Library access was denied. Enable it in Settings → Privacy → Photos."
            case .failed(let e): return "Could not save: \(e.localizedDescription)"
            }
        }
    }

    static func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    static func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    static func savePoster(_ poster: Poster) async throws {
        guard let url = PosterFileStore.imageURL(for: poster) else {
            throw SaveError.noAsset
        }
        var status = authorizationStatus()
        if status == .notDetermined {
            status = await requestAuthorization()
        }
        guard status == .authorized || status == .limited else {
            throw SaveError.denied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
        } catch {
            throw SaveError.failed(error)
        }
    }

    static func saveImage(_ image: UIImage) async throws {
        var status = authorizationStatus()
        if status == .notDetermined {
            status = await requestAuthorization()
        }
        guard status == .authorized || status == .limited else {
            throw SaveError.denied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            throw SaveError.failed(error)
        }
    }
}
