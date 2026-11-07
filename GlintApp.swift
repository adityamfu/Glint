import SwiftUI

@main
struct GlintApp: App {
    @State private var library = PhotoLibrary()

    var body: some Scene {
        WindowGroup {
            Group {
                switch library.status {
                case .authorized:
                    TabView {
                        Tab("Galeri", systemImage: "photo.on.rectangle") { GalleryView() }
                        Tab("Kamera", systemImage: "camera") { GalleryView(source: .camera) }
                        Tab("Lainnya", systemImage: "square.and.arrow.down") { GalleryView(source: .other) }
                        Tab("Album", systemImage: "rectangle.stack") { AlbumsView() }
                    }
                case .notDetermined: ProgressView()
                default: PermissionView(status: library.status)
                }
            }
            .environment(library)
            .task { await library.requestAccess() }
        }
    }
}
