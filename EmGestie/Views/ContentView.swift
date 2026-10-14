import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var searchText = ""

    var body: some View {
        TabView {
            Tab("Apple", systemImage: "apple.logo") {
                AppleWallpapersView()
            }
            Tab("Library", systemImage: "rectangle.on.rectangle") {
                PosterGridView(searchText: searchText, favoritesOnly: false)
            }
            Tab("Import", systemImage: "square.and.arrow.down") {
                ImportView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
        .searchable(text: $searchText, prompt: "Search library")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Poster.self, inMemory: true)
}
