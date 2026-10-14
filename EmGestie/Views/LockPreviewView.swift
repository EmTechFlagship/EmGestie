import SwiftUI

/// iOS 26-style Lock / Home Screen mock so users can judge a wallpaper
/// before handing it to PosterBoard via Photos.
struct LockPreviewView: View {
    var poster: Poster
    var mode: PreviewMode
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .frame(width: 300, height: 620)
                .overlay {
                    ZStack {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 300, height: 620)
                                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        }
                        // Home-screen dim + fake icons.
                        if mode == .home {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.35)],
                                startPoint: .top, endPoint: .bottom
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                            VStack {
                                Spacer()
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                                    ForEach(0..<8, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 44, height: 44)
                                    }
                                }
                                .padding(.bottom, 60)
                                .padding(.horizontal, 24)
                            }
                        }

                        VStack {
                            if mode == .lock {
                                Text(formattedDate)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .padding(.top, 48)
                                Text("9:41")
                                    .font(.system(size: 72, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                // Glass lock actions (iOS 26 look).
                                HStack(spacing: 100) {
                                    glassCircle(icon: "flashlight.off.fill")
                                    glassCircle(icon: "camera.fill")
                                }
                                .padding(.bottom, 28)
                            }
                        }
                    }
                }

            // Device frame.
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(.secondary.opacity(0.4), lineWidth: 6)
                .frame(width: 312, height: 632)
        }
        .task(id: poster.id) {
            image = PosterFileStore.loadImage(for: poster)
        }
    }

    private func glassCircle(icon: String) -> some View {
        Group {
            if #available(iOS 26, *) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular.tint(.black.opacity(0.35)), in: .circle)
            } else {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}

/// Step-by-step hand-off to the system PosterBoard (no public install API on iOS 26/27).
struct WallpaperGuideView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("iPhone / iPad — via Photos") {
                    guideRow(1, "In PosterBoard, tap Save on your poster.")
                    guideRow(2, "Lock your device, then touch and hold the Lock Screen.")
                    guideRow(3, "Tap ＋ → Photos and pick the saved wallpaper.")
                    guideRow(4, "Pinch to crop, tap Add → Set as Wallpaper Pair.")
                }
                Section("Tips") {
                    guideRow("◍", "Live / Motion (.mov) posters: save the still to Photos; iOS animates it on the Lock Screen when available.")
                    guideRow("◍", ".posterboard / .mercury bundles import the still + motion pair and preserve their descriptor, viewable in Details.")
                    guideRow("◍", "Use AirDrop / Share to move wallpapers between iPhone and iPad, then repeat the steps above.")
                }
                Section("Why not one-tap?") {
                    Text("Apple provides no public API to install Lock Screen posters on iOS 26 or 27. Saving to Photos and adding via the system gallery is the supported path.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Set as Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func guideRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.secondary.opacity(0.15), in: Circle())
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    private func guideRow(_ bullet: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(bullet).font(.headline).frame(width: 28)
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
