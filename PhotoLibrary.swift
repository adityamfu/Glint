import Photos
import SwiftUI

@MainActor @Observable
final class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver {
    var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var listings: [Source: Listing] = [:]
    private(set) var albums: [Album] = []
    private(set) var sizes: [String: Int64] = [:]
    private(set) var cameraIDs: Set<String> = []   // hasil jepretan app Kamera iPhone ini
    private(set) var scanProgress: Double?          // nil = tidak sedang memindai

    var sort = SortOption(rawValue: UserDefaults.standard.string(forKey: "sort") ?? "") ?? .newest {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "sort"); apply() }
    }
    var mediaFilter = MediaFilter(rawValue: UserDefaults.standard.string(forKey: "filter") ?? "") ?? .all {
        didSet { UserDefaults.standard.set(mediaFilter.rawValue, forKey: "filter"); apply() }
    }
    var sizeFilter = SizeFilter(rawValue: UserDefaults.standard.string(forKey: "sizeFilter") ?? "") ?? .any {
        didSet { UserDefaults.standard.set(sizeFilter.rawValue, forKey: "sizeFilter"); apply() }
    }
    var grouping = Grouping(rawValue: UserDefaults.standard.string(forKey: "grouping") ?? "") ?? .day {
        didSet { UserDefaults.standard.set(grouping.rawValue, forKey: "grouping"); apply() }
    }

    @ObservationIgnored let imageManager = PHCachingImageManager()
    @ObservationIgnored private var all: [PHAsset] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var registered = false

    func size(_ a: PHAsset) -> Int64 { sizes[a.localIdentifier] ?? 0 }
    func listing(_ source: Source) -> Listing { listings[source] ?? Listing() }

    // MARK: Akses & fetch

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized, !registered else { return }
        registered = true
        PHPhotoLibrary.shared().register(self)
        reload()
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.reload() }
    }

    // ponytail: refetch penuh tiap perubahan; cukup cepat untuk puluhan ribu aset, pakai changeDetails kalau terasa lambat
    private func reload() {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: opts)
        all = result.objects(at: IndexSet(integersIn: 0..<result.count))
        var list: [Album] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil).enumerateObjects { c, _, _ in
            list.append(Album(id: c.localIdentifier, title: c.localizedTitle ?? "Tanpa Nama",
                              assets: PHAsset.fetchAssets(in: c, options: nil)))
        }
        albums = list
        apply()
        scan()
    }

    private func apply() {
        var list = all.filter(mediaFilter.matches)
        if sizeFilter != .any { list = list.filter { size($0) > sizeFilter.minBytes } }
        switch sort {
        case .newest: break
        case .oldest: list.reverse()
        case .largest: list.sort { size($0) > size($1) }
        case .smallest: list.sort { size($0) < size($1) }
        }
        var out: [Source: Listing] = [:]
        for source in Source.allCases {
            let items = switch source {
            case .all: list
            case .camera: list.filter { cameraIDs.contains($0.localIdentifier) }
            case .other: list.filter { !cameraIDs.contains($0.localIdentifier) }
            }
            out[source] = Listing(items: items, sections: makeSections(items), totalBytes: total(items))
        }
        listings = out
    }

    private func total(_ items: [PHAsset]) -> Int64 { items.reduce(0) { $0 + size($1) } }

    private func makeSections(_ items: [PHAsset]) -> [MediaSection] {
        guard !sort.isBySize else { return [MediaSection(id: "all", date: nil, assets: items)] }
        let cal = Calendar.current
        var result: [MediaSection] = []
        for a in items {
            let d = a.creationDate ?? .distantPast
            let key = grouping == .day
                ? cal.startOfDay(for: d)
                : cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
            if result.last?.date == key {
                result[result.count - 1].assets.append(a)
            } else {
                result.append(MediaSection(id: key.description, date: key, assets: [a]))
            }
        }
        return result
    }

    // MARK: Pindai ukuran file & sumber

    private func scan() {
        guard scanTask == nil else { return }
        let ids = all.map(\.localIdentifier).filter { sizes[$0] == nil }
        guard !ids.isEmpty else { return }
        scanProgress = 0
        scanTask = Task {
            let batch = 300
            for start in stride(from: 0, to: ids.count, by: batch) {
                let chunk = Array(ids[start..<min(start + batch, ids.count)])
                let result = await Task.detached(priority: .utility) { Self.scan(chunk) }.value
                for (id, info) in result {
                    sizes[id] = info.size
                    if info.camera { cameraIDs.insert(id) }
                }
                scanProgress = Double(start + chunk.count) / Double(ids.count)
                // Sort ukuran baru diterapkan di akhir supaya grid tidak lompat-lompat saat di-scroll.
                if !sort.isBySize { apply() } else {
                    for (k, l) in listings { listings[k]?.totalBytes = total(l.items) }
                }
            }
            scanProgress = nil
            scanTask = nil
            apply()
            scan()   // tangkap aset yang masuk selama memindai
        }
    }

    nonisolated private static func scan(_ ids: [String]) -> [String: (size: Int64, camera: Bool)] {
        var out: [String: (size: Int64, camera: Bool)] = [:]
        // Data impor hanya tersedia kalau di-prefetch (opsi privat, dicek dulu supaya aman).
        let opts = PHFetchOptions()
        if opts.responds(to: NSSelectorFromString("setFetchPropertySets:")) {
            opts.setValue(Set(["PHAssetPropertySetImport"]), forKey: "fetchPropertySets")
        }
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: opts).enumerateObjects { a, _, _ in
            let res = PHAssetResource.assetResources(for: a)
            let main = res.first { $0.type == .photo || $0.type == .video } ?? res.first
            let by = importedBy(a)
            out[a.localIdentifier] = ((main?.value(forKey: "fileSize") as? Int64) ?? 0, by == 1 || by == 2)
        }
        return out
    }

    /// API privat: `importProperties.importedBy` (1 = kamera belakang, 2 = kamera depan app Kamera bawaan).
    /// Dicek dengan `responds(to:)` supaya tidak crash kalau Apple mengubahnya; nil = tidak diketahui → "Lainnya".
    nonisolated private static func importedBy(_ a: PHAsset) -> Int? {
        guard a.responds(to: NSSelectorFromString("importProperties")),
              let p = a.value(forKey: "importProperties") as? NSObject,
              p.responds(to: NSSelectorFromString("importedBy")) else { return nil }
        return p.value(forKey: "importedBy") as? Int
    }

    // MARK: Gambar & video

    @discardableResult
    func requestImage(for asset: PHAsset, size: CGSize, mode: PHImageContentMode = .aspectFill,
                      _ handler: @escaping @MainActor @Sendable (UIImage) -> Void) -> PHImageRequestID {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .fast
        return imageManager.requestImage(for: asset, targetSize: size, contentMode: mode, options: opts) { @Sendable image, _ in
            guard let image else { return }
            Task { @MainActor in handler(image) }
        }
    }

    func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        let opts = PHVideoRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .automatic
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: opts) { @Sendable item, _ in
                cont.resume(returning: item)
            }
        }
    }

    // MARK: Aksi

    /// false juga saat user menekan "Jangan Izinkan" di dialog konfirmasi iOS.
    @discardableResult
    private func change(_ block: @escaping @Sendable () -> Void) async -> Bool {
        (try? await PHPhotoLibrary.shared().performChanges(block)) != nil
    }

    @discardableResult
    func delete(_ ids: [String]) async -> Bool {
        await change { PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)) }
    }

    func setFavorite(_ id: String, _ value: Bool) async {
        await change {
            guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
            PHAssetChangeRequest(for: a).isFavorite = value
        }
    }

    // MARK: Album

    func createAlbum(_ title: String, with assetIDs: [String] = []) async {
        await change {
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            if !assetIDs.isEmpty { req.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)) }
        }
    }

    func renameAlbum(_ id: String, to title: String) async {
        await change { Self.albumRequest(id)?.title = title }
    }

    @discardableResult
    func deleteAlbum(_ id: String) async -> Bool {
        await change {
            PHAssetCollectionChangeRequest.deleteAssetCollections(
                PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil))
        }
    }

    func add(_ assetIDs: [String], to albumID: String) async {
        await change { Self.albumRequest(albumID)?.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)) }
    }

    @discardableResult
    func remove(_ assetIDs: [String], from albumID: String) async -> Bool {
        await change { Self.albumRequest(albumID)?.removeAssets(PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)) }
    }

    nonisolated private static func albumRequest(_ id: String) -> PHAssetCollectionChangeRequest? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
            .flatMap { PHAssetCollectionChangeRequest(for: $0) }
    }

    /// Salin file asli (versi edit jika ada) ke folder temp untuk dibagikan.
    func exportFiles(_ assets: [PHAsset]) async -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true
        var urls: [URL] = []
        for (i, asset) in assets.enumerated() {
            let res = PHAssetResource.assetResources(for: asset)
            guard let r = res.first(where: { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo })
                    ?? res.first(where: { $0.type == .photo || $0.type == .video }) else { continue }
            var url = dir.appending(path: r.originalFilename)
            if FileManager.default.fileExists(atPath: url.path()) { url = dir.appending(path: "\(i)-\(r.originalFilename)") }
            if (try? await PHAssetResourceManager.default().writeData(for: r, toFile: url, options: opts)) != nil {
                urls.append(url)
            }
        }
        return urls
    }
}
