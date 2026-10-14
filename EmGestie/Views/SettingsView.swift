import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var posters: [Poster]
    @State private var storageBytes: Int = 0
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    LabeledContent("Posters", value: "\(posters.count)")
                    LabeledContent("Favorites", value: "\(posters.filter(\.isFavorite).count)")
                    LabeledContent("Storage", value: ByteCountFormatter.string(fromByteCount: Int64(storageBytes), countStyle: .file))
                }

                Section("Wallpaper") {
                    Button("How to install wallpapers") { showGuide = true }
                    Text("Supports iPhone and iPad on iOS 26 and iOS 27 (same binary; deployment target iOS 26.0).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Formats") {
                    Text("Still: JPG · PNG · HEIC · HEIF · WebP\nMotion: MOV · MP4\nBundles: .posterboard · .mercury · .wallpaper · .zip (poster image + optional motion + metadata.json)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Danger zone") {
                    Button("Delete all posters", role: .destructive) {
                        for poster in posters {
                            PosterFileStore.removeAll(for: poster)
                            modelContext.delete(poster)
                        }
                        try? modelContext.save()
                        storageBytes = 0
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Designer", value: "Liquid Glass · SwiftUI · SwiftData")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showGuide) {
                WallpaperGuideView()
                    .presentationDetents([.medium, .large])
            }
            .task {
                storageBytes = PosterFileStore.totalBytes()
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}
