import Photos
import SwiftUI

struct ThumbnailView: View {
    let asset: PHAsset
    let side: CGFloat
    var selected: Bool?   // nil = bukan mode pilih
    var sizeText: String? // tampil saat sort/filter ukuran aktif
    var interaction: CellInteraction?

    @Environment(PhotoLibrary.self) private var library
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                badge(VStack(alignment: .trailing, spacing: 0) {
                    if asset.mediaType == .video { Text(duration) }
                    if let sizeText { Text(sizeText) }
                })
            }
            .overlay(alignment: .bottomLeading) {
                if asset.isFavorite { badge(Image(systemName: "heart.fill")) }
            }
            .overlay(alignment: .topLeading) {
                if asset.mediaSubtypes.contains(.photoLive) { badge(Image(systemName: "livephoto")) }
            }
            .overlay(alignment: .topTrailing) {
                if let selected {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.title3)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .overlay { if selected == true { Color.white.opacity(0.25) } }
            .contentShape(Rectangle())
            .overlay {
                if let interaction {
                    ContextMenuOverlay(image: image, aspect: aspect, interaction: interaction,
                                       preview: { PreviewImage(asset: asset, library: library) })
                }
            }
            .onAppear {
                let px = CGSize(width: side * scale, height: side * scale)
                requestID = library.requestImage(for: asset, size: px) { image = $0 }
            }
            .onDisappear {
                if let requestID { library.imageManager.cancelImageRequest(requestID) }
            }
    }

    private var aspect: CGFloat { CGFloat(asset.pixelWidth) / CGFloat(max(asset.pixelHeight, 1)) }

    private var duration: String {
        Duration.seconds(asset.duration).formatted(.time(pattern: asset.duration >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }


    private func badge(_ content: some View) -> some View {
        content
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 2)
            .padding(4)
    }
}

/// Pratinjau saat thumbnail ditekan lama.
struct PreviewImage: View {
    let asset: PHAsset
    let library: PhotoLibrary
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(CGFloat(asset.pixelWidth) / CGFloat(max(asset.pixelHeight, 1)), contentMode: .fit)
            .frame(width: 360)
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipped()
            .task { library.requestImage(for: asset, size: CGSize(width: 1080, height: 1080), mode: .aspectFit) { image = $0 } }
    }
}

struct CellInteraction {
    let tap: () -> Void
    let open: () -> Void            // tap pada pratinjau
    let menu: () -> [UIMenuElement]
}

/// Context menu versi UIKit: SwiftUI `.contextMenu` belum bisa menangani tap pada pratinjau.
struct ContextMenuOverlay<Preview: View>: UIViewRepresentable {
    let image: UIImage?
    let aspect: CGFloat
    let interaction: CellInteraction
    let preview: () -> Preview

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped)))
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: ContextMenuOverlay?

        @objc func tapped() { parent?.interaction.tap() }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let parent else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: {
                let vc = UIHostingController(rootView: parent.preview())
                vc.preferredContentSize = CGSize(width: 360, height: 360 / parent.aspect)
                return vc
            }, actionProvider: { _ in UIMenu(children: parent.interaction.menu()) })
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                                    animator: UIContextMenuInteractionCommitAnimating) {
            animator.preferredCommitStyle = .dismiss
            let open = parent?.interaction.open
            animator.addCompletion { open?() }
        }

        // Overlay transparan, jadi animasi angkat/turun pakai gambar thumbnail.
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
                                    highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            targeted(interaction.view)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configuration: UIContextMenuConfiguration,
                                    dismissalPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            targeted(interaction.view)
        }

        private func targeted(_ view: UIView?) -> UITargetedPreview? {
            guard let view, let image = parent?.image else { return nil }
            let iv = UIImageView(image: image)
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.frame = view.bounds
            return UITargetedPreview(view: iv, parameters: UIPreviewParameters(),
                                     target: UIPreviewTarget(container: view, center: CGPoint(x: view.bounds.midX, y: view.bounds.midY)))
        }
    }
}
