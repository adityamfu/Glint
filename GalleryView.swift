import Photos
import SwiftUI

struct GalleryView: View {
    @Environment(PhotoLibrary.self) private var library
    @AppStorage("columns") private var columns = 3
    var source: Source = .all
    @State private var selecting = false

    var body: some View {
        let listing = library.listing(source)
        NavigationStack {
            AssetGrid(sections: listing.sections, items: listing.items,
                      showSize: library.sort.isBySize || library.sizeFilter != .any,
                      selecting: $selecting) { summary(listing) }
                .navigationTitle(source.title)
                .toolbar { toolbar }
        }
    }

    // MARK: Ringkasan & chip

    private func summary(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(listing.items.count.formatted(.number.locale(idLocale))) item · \(listing.totalBytes.fileSize)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let p = library.scanProgress {
                ProgressView(value: p) { Text("Memindai ukuran & sumber… \(Int(p * 100))%").font(.caption2) }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if library.mediaFilter != .all { chip(library.mediaFilter.title) { library.mediaFilter = .all } }
                    if library.sizeFilter != .any { chip(library.sizeFilter.title) { library.sizeFilter = .any } }
                    if library.sort != .newest { chip(library.sort.title) { library.sort = .newest } }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private func chip(_ title: String, reset: @escaping () -> Void) -> some View {
        Button(action: reset) {
            Label(title, systemImage: "xmark")
                .labelStyle(TrailingIconLabel())
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.fill.secondary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var library = library
        ToolbarItem(placement: .topBarLeading) {
            if selecting {
                Button("Batal") { selecting = false }
            } else {
                Menu {
                    Picker("Kolom", selection: $columns) {
                        ForEach([3, 4, 5], id: \.self) { Text("\($0) kolom").tag($0) }
                    }
                } label: {
                    Image(systemName: "square.grid.3x3")
                }
            }
        }
        if !selecting {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Section("Urutkan") {
                        Picker("Urutkan", selection: $library.sort) {
                            ForEach(SortOption.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Section("Filter") {
                        Picker("Filter", selection: $library.mediaFilter) {
                            ForEach(MediaFilter.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                        }
                        Picker(selection: $library.sizeFilter) {
                            ForEach(SizeFilter.allCases) { Text($0.title).tag($0) }
                        } label: {
                            Label("Ukuran minimum", systemImage: "internaldrive")
                        }
                        .pickerStyle(.menu)
                    }
                    Picker(selection: $library.grouping) {
                        ForEach(Grouping.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Kelompokkan", systemImage: "calendar")
                    }
                    .pickerStyle(.menu)
                    .disabled(library.sort.isBySize)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                Button("Pilih") { selecting = true }
            }
        }
    }
}

/// Grid aset + mode pilih + detail + share. Dipakai Galeri dan isi Album.
struct AssetGrid<Header: View>: View {
    let sections: [MediaSection]
    let items: [PHAsset]
    var albumID: String?       // diisi saat menampilkan isi album
    var showSize = false
    @Binding var selecting: Bool
    @ViewBuilder var header: Header

    @Environment(PhotoLibrary.self) private var library
    @AppStorage("columns") private var columns = 3
    @State private var width: CGFloat = 390
    @State private var selection: Set<String> = []
    @State private var opened: PHAsset?
    @State private var share: ShareItems?
    @State private var exporting = false
    @State private var addToAlbum: AssetIDs?
    @Namespace private var zoom

    private var side: CGFloat { (width - CGFloat(columns - 1) * 2) / CGFloat(columns) }

    var body: some View {
        ScrollView {
            header
            if items.isEmpty {
                ContentUnavailableView("Tidak ada item", systemImage: "photo.on.rectangle")
            } else {
                grid
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
        .toolbar(selecting ? .hidden : .visible, for: .tabBar)
        .onChange(of: selecting) { if !selecting { selection = [] } }
        .fullScreenCover(item: $opened) { DetailView(items: items, startID: $0.localIdentifier, zoom: zoom) }
        .sheet(item: $share) { ShareSheet(urls: $0.urls) }
        .sheet(item: $addToAlbum) { AlbumPicker(assetIDs: $0.ids) { selecting = false } }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: columns),
                  spacing: 2, pinnedViews: .sectionHeaders) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.assets) { asset in
                        ThumbnailView(asset: asset, side: side,
                                      selected: selecting ? selection.contains(asset.localIdentifier) : nil,
                                      sizeText: showSize ? library.sizes[asset.localIdentifier]?.fileSize : nil,
                                      interaction: CellInteraction(tap: { tap(asset) },
                                                                   open: { opened = asset },
                                                                   menu: { menu(for: asset) }))
                            .matchedTransitionSource(id: asset.localIdentifier, in: zoom)
                    }
                } header: {
                    if section.date != nil { sectionHeader(section) }
                }
            }
        }
    }

    private func tap(_ asset: PHAsset) {
        guard selecting else { opened = asset; return }
        if selection.remove(asset.localIdentifier) == nil { selection.insert(asset.localIdentifier) }
    }

    private func menu(for asset: PHAsset) -> [UIMenuElement] {
        let id = asset.localIdentifier
        var items: [UIMenuElement] = [
            UIAction(title: asset.isFavorite ? "Hapus dari Favorit" : "Favorit",
                     image: UIImage(systemName: asset.isFavorite ? "heart.slash" : "heart")) { _ in
                Task { await library.setFavorite(id, !asset.isFavorite) }
            },
            UIAction(title: "Bagikan", image: UIImage(systemName: "square.and.arrow.up")) { _ in shareAssets([asset]) },
            UIAction(title: "Tambah ke Album", image: UIImage(systemName: "rectangle.stack.badge.plus")) { _ in
                addToAlbum = AssetIDs(ids: [id])
            },
        ]
        if let albumID {
            items.append(UIAction(title: "Keluarkan dari Album", image: UIImage(systemName: "minus.circle")) { _ in
                Task { await library.remove([id], from: albumID) }
            })
        }
        items.append(UIAction(title: "Hapus", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            Task { await library.delete([id]) }
        })
        return items
    }

    private func shareAssets(_ assets: [PHAsset]) {
        Task {
            exporting = true
            let urls = await library.exportFiles(assets)
            exporting = false
            if !urls.isEmpty { share = ShareItems(urls: urls) }
        }
    }

    private func sectionHeader(_ section: MediaSection) -> some View {
        let style: Date.FormatStyle = library.grouping == .day
            ? .dateTime.weekday(.wide).day().month(.wide).year()
            : .dateTime.month(.wide).year()
        let ids = section.assets.map(\.localIdentifier)
        let anyPicked = selecting && ids.contains(where: selection.contains)
        let allPicked = anyPicked && ids.allSatisfy(selection.contains)
        return HStack {
            Text(section.date?.formatted(style.locale(idLocale)) ?? "").font(.subheadline.weight(.semibold))
            Spacer()
            if anyPicked {
                Button(allPicked ? "Batalkan" : "Pilih Semua") {
                    if allPicked { selection.subtract(ids) } else { selection.formUnion(ids) }
                }
                .font(.caption.weight(.semibold))
            } else {
                Text("\(ids.count) item").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var selectionBar: some View {
        let chosen = items.filter { selection.contains($0.localIdentifier) }
        let ids = chosen.map(\.localIdentifier)
        let bytes = chosen.reduce(Int64(0)) { $0 + library.size($1) }
        return HStack(spacing: 20) {
            Button { shareAssets(chosen) } label: {
                if exporting { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
            }
            .disabled(exporting)
            Button { addToAlbum = AssetIDs(ids: ids) } label: { Image(systemName: "rectangle.stack.badge.plus") }
            Spacer()
            VStack(spacing: 0) {
                Text("\(chosen.count) dipilih").font(.headline)
                Text(bytes.fileSize).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let albumID {
                Button {
                    Task { if await library.remove(ids, from: albumID) { selecting = false } }
                } label: { Image(systemName: "minus.circle") }
            }
            Button(role: .destructive) {
                Task { if await library.delete(ids) { selecting = false } }
            } label: { Image(systemName: "trash") }
        }
        .disabled(chosen.isEmpty)
        .font(.title3)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct AssetIDs: Identifiable {
    let id = UUID()
    let ids: [String]
}

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.imageScale(.small) }
    }
}
