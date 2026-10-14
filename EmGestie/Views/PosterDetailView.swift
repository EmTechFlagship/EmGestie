import SwiftUI
import SwiftData

struct PosterDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var poster: Poster

    @State private var previewMode: PreviewMode = .lock
    @State private var showGuide = false
    @State private var statusMessage: String?
    @State private var isSaving = false
    @State private var isBuildingTendies = false
    @State private var titleDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LockPreviewView(poster: poster, mode: previewMode)

                Picker("Preview", selection: $previewMode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                glassActionBar

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                detailForm
            }
            .padding(.vertical)
        }
        .navigationTitle(poster.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    poster.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Label("Favorite", systemImage: poster.isFavorite ? "heart.fill" : "heart")
                }
            }
        }
        .sheet(isPresented: $showGuide) {
            WallpaperGuideView()
                .presentationDetents([.medium, .large])
        }
        .onAppear { titleDraft = poster.title }
    }

    // MARK: - Actions

    private var glassActionBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task { await saveToPhotos() }
                } label: {
                    Label(isSaving ? "Saving…" : "Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.glassProminent)
                .disabled(isSaving)

                Button {
                    showGuide = true
                } label: {
                    Label("Set Wallpaper", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.glass)

                if let url = shareURL {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.glass)
                }
            }
            if PosterFileStore.tendiesURL(for: poster) != nil {
                VStack(spacing: 8) {
                    Button {
                        applyTendies()
                    } label: {
                        Label("Apply Tendies", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)

                    Button(role: .destructive) {
                        removeTendies()
                    } label: {
                        Label("Remove Tendies", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    HStack(spacing: 12) {
                        if let tendiesURL = PosterFileStore.tendiesURL(for: poster) {
                            ShareLink(item: tendiesURL) {
                                Label(".tendies file", systemImage: "doc.zipper")
                            }
                            .buttonStyle(.glass)
                        }
                        if let pocketURL = pocketPosterRemoteURL {
                            Link(destination: pocketURL) {
                                Label("Pocket Poster", systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .font(.subheadline)
                    Text("Applying hands the .tendies to Pocket Poster / Nugget. iOS 26/27 has no API for silent install.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if PosterFileStore.imageURL(for: poster) != nil {
                VStack(spacing: 8) {
                    Button {
                        buildTendies()
                    } label: {
                        Label(isBuildingTendies ? "Building…" : "Build .tendies", systemImage: "hammer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isBuildingTendies)
                    Text("Packages this poster as a .tendies bundle for Nugget / Pocket Poster hand-off.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var pocketPosterRemoteURL: URL? {
        guard let remote = TendiesApplyService.remoteURL(for: poster) else { return nil }
        return TendiesApplyService.pocketPosterURL(remoteURL: remote)
    }

    private func applyTendies() {
        if let remote = TendiesApplyService.remoteURL(for: poster),
           TendiesApplyService.applyViaPocketPoster(remoteURL: remote) {
            statusMessage = "Opening Pocket Poster to apply “\(poster.title)”…"
        } else {
            statusMessage = "Pocket Poster not found. Use Share → .tendies file to send it to Nugget, Files or AirDrop."
        }
    }

    private func removeTendies() {
        if TendiesApplyService.removeTendies(from: poster) {
            try? modelContext.save()
            statusMessage = "Removed the .tendies file. The preview stays in your Library."
        } else {
            statusMessage = "No .tendies file to remove."
        }
    }

    private func buildTendies() {
        isBuildingTendies = true
        defer { isBuildingTendies = false }
        do {
            let filename = try TendiesBuilderService.buildTendies(for: poster)
            poster.tendiesFilename = filename
            try? modelContext.save()
            statusMessage = "Built .tendies bundle. Share it to Nugget, Files or AirDrop to install."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var shareURL: URL? {
        PosterFileStore.imageURL(for: poster) ?? PosterFileStore.videoURL(for: poster)
    }

    private var detailForm: some View {
        VStack(spacing: 12) {
            TextField("Title", text: $titleDraft, onCommit: {
                poster.title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                try? modelContext.save()
            })
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                InfoTile(title: "Kind", value: poster.kind.label, icon: poster.kind.systemImage)
                InfoTile(title: "Source", value: poster.source.rawValue.capitalized, icon: "tray.and.arrow.down")
                InfoTile(title: "Size", value: poster.width > 0 ? "\(poster.width)×\(poster.height)" : "—", icon: "ruler")
                InfoTile(title: "Tags", value: poster.tags.joined(separator: ", ").isEmpty ? "—" : poster.tags.joined(separator: ", "), icon: "tag")
            }
            .padding(.horizontal)

            if let descriptor = poster.mercuryDescriptor, !descriptor.isEmpty {
                DisclosureGroup("Mercury / PosterBoard descriptor") {
                    ScrollView {
                        Text(descriptor)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
                .padding(.horizontal)
            }

            Button("Delete poster", role: .destructive) {
                PosterFileStore.removeAll(for: poster)
                modelContext.delete(poster)
                try? modelContext.save()
                dismiss()
            }
            .padding(.top, 8)
        }
    }

    private func saveToPhotos() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoLibraryService.savePoster(poster)
            statusMessage = "Saved to Photos. Open the Lock Screen gallery (long-press) → ＋ → Photos to install it."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

enum PreviewMode: String, CaseIterable, Identifiable {
    case lock, home

    var id: String { rawValue }
    var label: String {
        switch self {
        case .lock: return "Lock Screen"
        case .home: return "Home Screen"
        }
    }
}

struct InfoTile: View {
    var title: String
    var value: String
    var icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
