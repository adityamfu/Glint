import Photos
import PhotosUI
import SwiftUI

struct AlbumsView: View {
    @Environment(PhotoLibrary.self) private var library
    @State private var creating = false
    @State private var renaming = false
    @State private var renameID = ""
    @State private var name = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.albums.isEmpty {
                    ContentUnavailableView("Belum ada album", systemImage: "rectangle.stack",
                                           description: Text("Ketuk + untuk membuat album."))
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(library.albums) { album in
                        NavigationLink(value: album.id) { AlbumCell(album: album) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    name = album.title; renameID = album.id; renaming = true
                                } label: { Label("Ganti Nama", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    Task { await library.deleteAlbum(album.id) }
                                } label: { Label("Hapus Album", systemImage: "trash") }
                            }
                    }
                }
                .padding()
            }
            .navigationTitle("Album")
            .navigationDestination(for: String.self) { AlbumDetailView(albumID: $0) }
            .toolbar {
                Button { name = ""; creating = true } label: { Image(systemName: "plus") }
            }
            .nameAlert("Album Baru", isPresented: $creating, name: $name) { n in
                Task { await library.createAlbum(n) }
            }
            .nameAlert("Ganti Nama", isPresented: $renaming, name: $name) { n in
                Task { await library.renameAlbum(renameID, to: n) }
            }
        }
    }
}

private struct AlbumCell: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let cover = album.assets.lastObject {
                    ThumbnailView(asset: cover, side: 180)
                } else {
                    Color(.secondarySystemFill)
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundStyle(.secondary) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(album.title).font(.subheadline.weight(.medium)).lineLimit(1)
            Text("\(album.assets.count)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AlbumDetailView: View {
    let albumID: String
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var selecting = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var renaming = false
    @State private var name = ""

    var body: some View {
        if let album = library.albums.first(where: { $0.id == albumID }) {
            let assets = album.assets.objects(at: IndexSet(integersIn: 0..<album.assets.count))
            AssetGrid(sections: [MediaSection(id: "all", date: nil, assets: assets)], items: assets,
                      albumID: albumID, selecting: $selecting) {
                Text("\(assets.count) item")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
            .navigationTitle(album.title)
            .navigationBarBackButtonHidden(selecting)
            .toolbar {
                if selecting {
                    ToolbarItem(placement: .topBarTrailing) { Button("Batal") { selecting = false } }
                } else {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        // Picker sistem dengan library penuh → itemIdentifier = localIdentifier aset.
                        PhotosPicker(selection: $picked, photoLibrary: .shared()) { Image(systemName: "plus") }
                        Menu {
                            Button {
                                name = album.title; renaming = true
                            } label: { Label("Ganti Nama", systemImage: "pencil") }
                            Button(role: .destructive) {
                                Task { if await library.deleteAlbum(albumID) { dismiss() } }
                            } label: { Label("Hapus Album", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        Button("Pilih") { selecting = true }
                    }
                }
            }
            .onChange(of: picked) {
                let ids = picked.compactMap(\.itemIdentifier)
                guard !ids.isEmpty else { return }
                picked = []
                Task { await library.add(ids, to: albumID) }
            }
            .nameAlert("Ganti Nama", isPresented: $renaming, name: $name) { n in
                Task { await library.renameAlbum(albumID, to: n) }
            }
        } else {
            ContentUnavailableView("Album tidak ditemukan", systemImage: "rectangle.stack")
        }
    }
}

/// Sheet "Tambah ke Album" dari mode pilih / context menu.
struct AlbumPicker: View {
    let assetIDs: [String]
    let done: () -> Void
    @Environment(PhotoLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Button { name = ""; creating = true } label: { Label("Album Baru…", systemImage: "plus") }
                ForEach(library.albums) { album in
                    Button {
                        Task { await library.add(assetIDs, to: album.id); finish() }
                    } label: {
                        HStack {
                            Group {
                                if let cover = album.assets.lastObject {
                                    ThumbnailView(asset: cover, side: 44)
                                } else {
                                    Color(.secondarySystemFill)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading) {
                                Text(album.title)
                                Text("\(album.assets.count)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Tambah ke Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
            }
            .nameAlert("Album Baru", isPresented: $creating, name: $name) { n in
                Task { await library.createAlbum(n, with: assetIDs); finish() }
            }
        }
    }

    private func finish() {
        done()
        dismiss()
    }
}

extension View {
    func nameAlert(_ title: String, isPresented: Binding<Bool>, name: Binding<String>,
                   onSave: @escaping (String) -> Void) -> some View {
        alert(title, isPresented: isPresented) {
            TextField("Nama album", text: name).autocorrectionDisabled()
            Button("Batal", role: .cancel) {}
            Button("Simpan") {
                let n = name.wrappedValue.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { onSave(n) }
            }
        }
    }
}
