import SwiftUI

/// Adaptive cell with Liquid Glass badge overlay (iOS 26+).
struct PosterCell: View {
    var poster: Poster
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(9 / 19.5, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Label(poster.kind.label, systemImage: poster.kind.systemImage)
                    if poster.isFavorite {
                        Image(systemName: "heart.fill")
                    }
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .glassBadge()

                Text(poster.title)
                    .font(.footnote.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .glassBadge()
            }
            .padding(8)
        }
        .task(id: poster.id) {
            image = PosterFileStore.loadImage(for: poster)
        }
    }
}

/// Backwards-compatible "glass badge": real Liquid Glass on iOS 26+,
/// ultra-thin material on anything older (e.g. future-proofing for 27 API drift).
struct GlassBadgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.tint(.black.opacity(0.25)), in: .capsule)
                .foregroundStyle(.white)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.primary)
        }
    }
}

extension View {
    func glassBadge() -> some View {
        modifier(GlassBadgeModifier())
    }
}
