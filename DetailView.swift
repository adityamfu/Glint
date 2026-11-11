import AVKit
import Photos
import SwiftUI

struct DetailView: View {
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String?
    @State private var isZoomed = false
    @State private var infoAsset: PHAsset?
    @State private var share: ShareItems?
    @State private var exporting = false
    @State private var bars = EdgeInsets()

    let items: [PHAsset]   // urutan halaman = urutan grid asal
    let zoom: Namespace.ID

    init(items: [PHAsset], startID: String, zoom: Namespace.ID) {
        self.items = items
        _currentID = State(initialValue: startID)
        self.zoom = zoom
    }

    private var current: PHAsset? { items.first { $0.localIdentifier == currentID } }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { asset in
                        MediaPage(asset: asset, isZoomed: $isZoomed, bars: bars)
                            .containerRelativeFrame([.horizontal, .vertical])
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollDisabled(isZoomed)
            .scrollIndicators(.hidden)
            // Halaman membentang ke balik bar; video butuh tinggi bar supaya kontrol & filmstrip tidak tertutup.
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { bars = $0 }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(current?.creationDate?.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(idLocale)) ?? "")
            .toolbar { toolbar }
            // Gelap hanya di layar ini; preferredColorScheme bocor ke seluruh window setelah ditutup.
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .sheet(item: $infoAsset) { InfoSheet(asset: $0) }
            .sheet(item: $share) { ShareSheet(urls: $0.urls) }
        }
        // Zoom transition bawaan iOS 18: animasi dari/ke thumbnail + tarik dari mana saja untuk menutup.
        .navigationTransition(.zoom(sourceID: currentID ?? "", in: zoom))
        .interactiveDismissDisabled(isZoomed)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                guard let a = current else { return }
                Task { await library.setFavorite(a.localIdentifier, !a.isFavorite) }
            } label: {
                Image(systemName: current?.isFavorite == true ? "heart.fill" : "heart")
            }
            Spacer()
            Button { infoAsset = current } label: { Image(systemName: "info.circle") }
            Spacer()
            Button {
                guard let a = current else { return }
                Task {
                    exporting = true
                    let urls = await library.exportFiles([a])
                    exporting = false
                    if !urls.isEmpty { share = ShareItems(urls: urls) }
                }
            } label: {
                if exporting { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
            }
            .disabled(exporting)
            Spacer()
            Button(role: .destructive) { Task { await deleteCurrent() } } label: { Image(systemName: "trash") }
        }
    }

    private func deleteCurrent() async {
        guard let i = items.firstIndex(where: { $0.localIdentifier == currentID }) else { return }
        let next = i + 1 < items.count ? items[i + 1] : (i > 0 ? items[i - 1] : nil)
        guard await library.delete([items[i].localIdentifier]) else { return }
        if let next { currentID = next.localIdentifier } else { dismiss() }
    }
}

private struct MediaPage: View {
    let asset: PHAsset
    @Binding var isZoomed: Bool
    let bars: EdgeInsets
    @Environment(PhotoLibrary.self) private var library
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                // Kontrol bawaan VideoPlayer (termasuk ±10 detik) tetap ada; filmstrip di bawahnya.
                VStack(spacing: 10) {
                    VideoPlayer(player: player)
                    Filmstrip(player: player)
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                }
                .padding(.top, bars.top)
                .padding(.bottom, bars.bottom)
            } else if let image {
                if asset.mediaType == .video {
                    Image(uiImage: image).resizable().scaledToFit().overlay { ProgressView() }
                } else {
                    ZoomableImage(image: image, isZoomed: $isZoomed)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: asset.localIdentifier) {
            library.requestImage(for: asset, size: CGSize(width: 2400, height: 2400), mode: .aspectFit) { image = $0 }
            if asset.mediaType == .video, let item = await library.playerItem(for: asset) {
                player = AVPlayer(playerItem: item)
            }
        }
        .onDisappear { player?.pause() }
    }
}

/// Deretan cuplikan frame video seperti di Photos; geser untuk pindah posisi.
private struct Filmstrip: View {
    let player: AVPlayer
    @State private var frames: [UIImage] = []
    private let count = 12

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(frames.indices, id: \.self) { i in
                            Image(uiImage: frames[i])
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width / CGFloat(count), height: geo.size.height)
                                .clipped()
                        }
                    }
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 3, height: geo.size.height + 8)
                        .shadow(radius: 2)
                        .offset(x: geo.size.width * progress - 1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                guard let d = duration else { return }
                player.pause()
                let f = min(max(v.location.x / geo.size.width, 0), 1)
                player.seek(to: CMTimeMultiplyByFloat64(d, multiplier: f),
                            toleranceBefore: .zero, toleranceAfter: CMTime(value: 1, timescale: 10))
            })
        }
        .frame(height: 44)
        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task { await loadFrames() }
    }

    private var duration: CMTime? {
        guard let d = player.currentItem?.duration, d.isNumeric, d.seconds > 0 else { return nil }
        return d
    }

    private var progress: CGFloat {
        guard let d = duration else { return 0 }
        return CGFloat(min(max(player.currentTime().seconds / d.seconds, 0), 1))
    }

    private func loadFrames() async {
        guard let asset = player.currentItem?.asset,
              let d = try? await asset.load(.duration), d.seconds > 0 else { return }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 120, height: 120)
        let times = (0..<count).map { CMTime(seconds: d.seconds * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [UIImage] = []
        for await result in gen.images(for: times) {
            if let cg = try? result.image { images.append(UIImage(cgImage: cg)) }
        }
        frames = images
    }
}

private struct ZoomableImage: View {
    let image: UIImage
    @Binding var isZoomed: Bool
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = min(max(lastScale * $0.magnification, 1), 6) }
                    .onEnded { _ in settle() }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { offset = CGSize(width: lastOffset.width + $0.translation.width,
                                                 height: lastOffset.height + $0.translation.height) }
                    .onEnded { _ in lastOffset = offset },
                including: scale > 1 ? .all : .subviews
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { scale = scale > 1 ? 1 : 2.5 }
                settle()
            }
            .onDisappear { scale = 1; settle() }
    }

    private func settle() {
        lastScale = scale
        if scale <= 1 {
            withAnimation(.snappy) { offset = .zero }
            lastOffset = .zero
        }
        isZoomed = scale > 1
    }
}

struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
