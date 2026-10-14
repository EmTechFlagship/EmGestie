import SwiftUI
import SwiftData

struct PosterGridView: View {
    var searchText: String
    var favoritesOnly: Bool

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Poster.creationDate, order: .reverse) private var allPosters: [Poster]
    @State private var selectedKind: PosterKind?
    @State private var selectedPoster: Poster?

    private var filtered: [Poster] {
        allPosters.filter { poster in
            if favoritesOnly, !poster.isFavorite { return false }
            if let selectedKind, poster.kind != selectedKind { return false }
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return poster.title.lowercased().contains(q)
                || poster.tags.joined(separator: " ").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    EmptyPostersView(favoritesOnly: favoritesOnly)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(filtered) { poster in
                                PosterCell(poster: poster)
                                    .onTapGesture { selectedPoster = poster }
                                    .contextMenu {
                                        Button(poster.isFavorite ? "Unfavorite" : "Favorite") {
                                            poster.isFavorite.toggle()
                                            try? modelContext.save()
                                        }
                                        Button("Save to Photos") {
                                            Task { try? await PhotoLibraryService.savePoster(poster) }
                                        }
                                        Button("Delete", role: .destructive) {
                                            PosterFileStore.removeAll(for: poster)
                                            modelContext.delete(poster)
                                            try? modelContext.save()
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(favoritesOnly ? "Favorites" : "Library")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Kind", selection: $selectedKind) {
                        Text("All").tag(nil as PosterKind?)
                        ForEach(PosterKind.allCases) { kind in
                            Text(kind.label).tag(kind as PosterKind?)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
            }
            .navigationDestination(item: $selectedPoster) { poster in
                PosterDetailView(poster: poster)
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)]
    }
}

struct EmptyPostersView: View {
    var favoritesOnly: Bool

    var body: some View {
        ContentUnavailableView {
            Label(favoritesOnly ? "No favorites yet" : "No posters yet", systemImage: "photo.on.rectangle")
        } description: {
            Text(favoritesOnly
                ? "Tap the heart on any poster to pin it here."
                : "Get an Apple wallpaper above, or import an image, .tendies, .posterboard, .mercury or .zip.")
        }
    }
}
