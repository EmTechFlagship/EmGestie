import Foundation
import SwiftData

/// A wallpaper poster that can be previewed and handed off to
/// the system PosterBoard (Lock Screen gallery) via Photos / Files.
@Model
final class Poster {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String
    var imageFilename: String?
    var videoFilename: String?
    var thumbnailFilename: String?
    var creationDate: Date
    var isFavorite: Bool
    var tagsRaw: String
    var sourceRaw: String
    var width: Int
    var height: Int
    var notes: String

    // Optional PosterBoard / Mercury bundle metadata, preserved on import.
    var mercuryDescriptor: String?
    /// Local `.tendies` PosterBoard bundle (Nugget format), if downloaded/imported.
    var tendiesFilename: String?

    init(
        id: UUID = UUID(),
        title: String,
        kind: PosterKind = .image,
        imageFilename: String? = nil,
        videoFilename: String? = nil,
        thumbnailFilename: String? = nil,
        creationDate: Date = Date(),
        isFavorite: Bool = false,
        tags: [String] = [],
        source: PosterSource = .imported,
        width: Int = 0,
        height: Int = 0,
        notes: String = "",
        mercuryDescriptor: String? = nil,
        tendiesFilename: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.imageFilename = imageFilename
        self.videoFilename = videoFilename
        self.thumbnailFilename = thumbnailFilename
        self.creationDate = creationDate
        self.isFavorite = isFavorite
        self.tagsRaw = tags.joined(separator: ",")
        self.sourceRaw = source.rawValue
        self.width = width
        self.height = height
        self.notes = notes
        self.mercuryDescriptor = mercuryDescriptor
        self.tendiesFilename = tendiesFilename
    }

    var kind: PosterKind {
        get { PosterKind(rawValue: kindRaw) ?? .image }
        set { kindRaw = newValue.rawValue }
    }

    var source: PosterSource {
        get { PosterSource(rawValue: sourceRaw) ?? .imported }
        set { sourceRaw = newValue.rawValue }
    }

    var tags: [String] {
        get {
            tagsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set { tagsRaw = newValue.joined(separator: ",") }
    }
}

enum PosterKind: String, Codable, CaseIterable, Identifiable {
    case image
    case live
    case motion
    case depth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .image: return "Still"
        case .live: return "Live"
        case .motion: return "Motion"
        case .depth: return "Depth"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .live: return "livephoto"
        case .motion: return "film"
        case .depth: return "square.stack.3d.up"
        }
    }
}

enum PosterSource: String, Codable, CaseIterable {
    case bundled
    case imported
    case mercury
    case posterboard
}
