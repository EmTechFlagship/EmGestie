import SwiftUI
import SwiftData

/// Apple Mercury / PosterBoard wallpaper cards.
/// Source: https://cowabun.ga/wallpapers#apple-wallpapers
/// No feed — just a card grid. Tapping Get downloads the `.tendies`
/// and imports it into Library automatically. Imported cards flip to
/// Apply Tendies / Remove Tendies.
struct AppleWallpapersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Poster.creationDate, order: .reverse) private var posters: [Poster]
    @State private var wallpapers: [AppleWallpaper] = AppleWallpaperService.loadBundled()
    @State private var searchText = ""
    @State private var deviceFilter: DeviceFilter = .all
    @State private var busyID: Int?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Apple wallpapers",
                        systemImage: "photo.on.rectangle",
                        description: Text("Try a different search or filter.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 250), spacing: 16)], spacing: 16) {
                            ForEach(filtered) { wallpaper in
                                let imported = importedPoster(for: wallpaper)
                                AppleWallpaperCard(
                                    wallpaper: wallpaper,
                                    isBusy: busyID == wallpaper.id,
                                    imported: imported != nil,
                                    onGet: { Task { await downloadAndImport(wallpaper) } },
                                    onApply: { applyTendies(wallpaper, poster: imported) },
                                    onRemove: { removeTendies(wallpaper, poster: imported) }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Apple Wallpapers")
            .searchable(text: $searchText, prompt: "Search iPhone, iPad, iOS")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Device", selection: $deviceFilter) {
                        ForEach(DeviceFilter.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            Text("Source: cowabun.ga · Nugget wallpapers · .tendies PosterBoard bundles")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
        }
    }

    private var filtered: [AppleWallpaper] {
        wallpapers.filter { w in
            switch deviceFilter {
            case .all: break
            case .iphone: guard w.isIPhone && !w.isIPad else { return false }
            case .ipad: guard w.isIPad else { return false }
            }
            guard !searchText.isEmpty else { return true }
            let q = searchText.lowercased()
            return w.name.lowercased().contains(q)
                || (w.description ?? "").lowercased().contains(q)
        }
    }

    private func importedPoster(for wallpaper: AppleWallpaper) -> Poster? {
        posters.first { $0.mercuryDescriptor == "source: \(wallpaper.url)" && $0.tendiesFilename != nil }
    }

    /// Download `.tendies` + preview, then auto-import into Library as a Poster.
    @MainActor
    private func downloadAndImport(_ wallpaper: AppleWallpaper) async {
        if importedPoster(for: wallpaper) != nil {
            statusMessage = "“\(wallpaper.name)” is already in your Library."
            return
        }
        busyID = wallpaper.id
        defer { busyID = nil }
        do {
            let tendiesURL = try await AppleWallpaperService.downloadTendies(for: wallpaper)
            let previewFilename = try? await AppleWallpaperService.downloadPreview(for: wallpaper)
            let storedTendies = PosterFileStore.copy(from: tendiesURL, fileExtension: "tendies")
            try? FileManager.default.removeItem(at: tendiesURL)
            let poster = Poster(
                title: wallpaper.name,
                kind: .image,
                imageFilename: previewFilename,
                thumbnailFilename: previewFilename,
                tags: ["apple", "posterboard", "tendies"],
                source: .posterboard,
                notes: wallpaper.description ?? "",
                mercuryDescriptor: "source: \(wallpaper.url)",
                tendiesFilename: storedTendies
            )
            modelContext.insert(poster)
            try? modelContext.save()
            statusMessage = "Imported “\(wallpaper.name)” to Library (.tendies saved)."
        } catch {
            statusMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func applyTendies(_ wallpaper: AppleWallpaper, poster: Poster?) {
        guard let remote = wallpaper.downloadURL else {
            statusMessage = "No download URL for “\(wallpaper.name)”."
            return
        }
        if TendiesApplyService.applyViaPocketPoster(remoteURL: remote) {
            statusMessage = "Opening Pocket Poster to apply “\(wallpaper.name)”…"
        } else {
            statusMessage = "Pocket Poster not found. Open Library → “\(wallpaper.name)” → Share the .tendies to Nugget / Files."
        }
    }

    @MainActor
    private func removeTendies(_ wallpaper: AppleWallpaper, poster: Poster?) {
        guard let poster else {
            statusMessage = "Nothing to remove."
            return
        }
        PosterFileStore.removeAll(for: poster)
        modelContext.delete(poster)
        try? modelContext.save()
        statusMessage = "Removed “\(wallpaper.name)” (.tendies deleted from Library)."
    }

    enum DeviceFilter: String, CaseIterable, Identifiable {
        case all, iphone, ipad
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .iphone: return "iPhone"
            case .ipad: return "iPad"
            }
        }
    }
}

/// Single Mercury / PosterBoard card.
struct AppleWallpaperCard: View {
    var wallpaper: AppleWallpaper
    var isBusy: Bool
    var imported: Bool
    var onGet: () -> Void
    var onApply: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: wallpaper.previewURL) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.secondary.opacity(0.12))
                            .aspectRatio(9 / 16, contentMode: .fit)
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(9 / 16, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.secondary.opacity(0.12))
                            .aspectRatio(9 / 16, contentMode: .fit)
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color.secondary.opacity(0.1)
                }
            }

            HStack(spacing: 6) {
                Text(wallpaper.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if imported {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if let req = wallpaper.requirement {
                Text(req)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassBadge()
            }

            Text(imported ? "Imported · .tendies in Library" : "PosterBoard · .tendies")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if imported {
                Button(action: onApply) {
                    Label("Apply Tendies", systemImage: "wand.and.stars")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(isBusy)
                Button(action: onRemove) {
                    Label("Remove Tendies", systemImage: "trash")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(.red)
                .disabled(isBusy)
            } else {
                HStack(spacing: 8) {
                    Button(action: onGet) {
                        Label(isBusy ? "Adding…" : "Get", systemImage: "square.and.arrow.down")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isBusy)

                    if let pocketURL = wallpaper.pocketPosterURL {
                        Link(destination: pocketURL) {
                            Label("Pocket Poster", systemImage: "arrow.up.forward.app")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
        .padding(10)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    AppleWallpapersView()
        .modelContainer(for: Poster.self, inMemory: true)
}
