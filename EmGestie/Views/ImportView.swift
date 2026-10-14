import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            List {
                Section("Add wallpapers") {
                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: 10,
                        matching: .any(of: [.images, .videos, .livePhotos])
                    ) {
                        Label("Choose from Photos", systemImage: "photo.badge.plus")
                    }
                    .onChange(of: photoItems) { _, _ in
                        Task { await importPhotoPickerItems() }
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Import file or bundle…", systemImage: "folder.badge.plus")
                    }

                    Text("Images, videos, .posterboard, .mercury, .wallpaper and .zip bundles. On iPad you can also drag files directly onto the Browse grid.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("How installing works") {
                    Text("PosterBoard stages wallpapers locally. Tap a poster → Save to add it to Photos, then install it from the system Lock Screen gallery (long-press → ＋ → Photos).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isImporting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Importing…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(isError ? .red : .secondary)
                    }
                }
            }
            .navigationTitle("Import")
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: true
            ) { result in
                Task { await importFileImporterResult(result) }
            }
        }
    }

    private var allowedTypes: [UTType] {
        var types: [UTType] = [.image, .movie, .data, .zip, .folder]
        for ext in ["posterboard", "mercury", "wallpaper", "pboard", "tendies"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }

    // MARK: - Photos picker

    @MainActor
    private func importPhotoPickerItems() async {
        guard !photoItems.isEmpty else { return }
        isImporting = true
        defer {
            isImporting = false
            photoItems = []
        }
        var count = 0
        for item in photoItems {
            do {
                // Prefer image data; fall back to video file URL.
                if let data = try await item.loadTransferable(type: Data.self),
                   let imported = try? PosterImportService.importImageData(data, suggestedName: "Photos import") {
                    insert(imported)
                    count += 1
                    continue
                }
                if let url = try await item.loadTransferable(type: URL.self),
                   let imported = try? PosterImportService.importFile(at: url) {
                    insert(imported)
                    count += 1
                }
            } catch {
                setMessage("One item failed: \(error.localizedDescription)", error: true)
            }
        }
        if count > 0 { setMessage("Imported \(count) poster\(count == 1 ? "" : "s").", error: false) }
    }

    // MARK: - File importer

    @MainActor
    private func importFileImporterResult(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            setMessage(error.localizedDescription, error: true)
        case .success(let urls):
            isImporting = true
            defer { isImporting = false }
            var count = 0
            for url in urls {
                do {
                    let imported = try PosterImportService.importFile(at: url)
                    insert(imported)
                    count += 1
                } catch {
                    setMessage(error.localizedDescription, error: true)
                }
            }
            if count > 0 { setMessage("Imported \(count) poster\(count == 1 ? "" : "s").", error: false) }
        }
    }

    @MainActor
    private func insert(_ imported: PosterImportService.ImportedPoster) {
        let poster = Poster(
            title: imported.title,
            kind: imported.kind,
            imageFilename: imported.imageFilename,
            videoFilename: imported.videoFilename,
            thumbnailFilename: imported.imageFilename,
            tags: imported.tags,
            source: imported.source,
            width: imported.width,
            height: imported.height,
            mercuryDescriptor: imported.descriptor,
            tendiesFilename: imported.tendiesFilename
        )
        modelContext.insert(poster)
        try? modelContext.save()
    }

    @MainActor
    private func setMessage(_ text: String, error: Bool) {
        message = text
        isError = error
    }
}
