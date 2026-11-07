import Photos

let idLocale = Locale(identifier: "id_ID")

extension Int64 {
    var fileSize: String { formatted(.byteCount(style: .file).locale(idLocale)) }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}

enum SortOption: String, CaseIterable, Identifiable {
    case newest, oldest, largest, smallest
    var id: Self { self }
    var isBySize: Bool { self == .largest || self == .smallest }
    var title: String {
        switch self {
        case .newest: "Terbaru"
        case .oldest: "Terlama"
        case .largest: "Ukuran terbesar"
        case .smallest: "Ukuran terkecil"
        }
    }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all, photo, video, screenshot, live, favorite
    var id: Self { self }
    var title: String {
        switch self {
        case .all: "Semua"
        case .photo: "Foto"
        case .video: "Video"
        case .screenshot: "Screenshot"
        case .live: "Live Photo"
        case .favorite: "Favorit"
        }
    }
    var icon: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .photo: "photo"
        case .video: "video"
        case .screenshot: "camera.viewfinder"
        case .live: "livephoto"
        case .favorite: "heart"
        }
    }
    func matches(_ a: PHAsset) -> Bool {
        switch self {
        case .all: true
        case .photo: a.mediaType == .image
        case .video: a.mediaType == .video
        case .screenshot: a.mediaSubtypes.contains(.photoScreenshot)
        case .live: a.mediaSubtypes.contains(.photoLive)
        case .favorite: a.isFavorite
        }
    }
}

enum SizeFilter: String, CaseIterable, Identifiable {
    case any, mb5, mb20, mb100
    var id: Self { self }
    var minBytes: Int64 {
        switch self {
        case .any: 0
        case .mb5: 5_000_000
        case .mb20: 20_000_000
        case .mb100: 100_000_000
        }
    }
    var title: String {
        switch self {
        case .any: "Semua ukuran"
        case .mb5: "> 5 MB"
        case .mb20: "> 20 MB"
        case .mb100: "> 100 MB"
        }
    }
}

enum Grouping: String, CaseIterable, Identifiable {
    case day, month
    var id: Self { self }
    var title: String { self == .day ? "Hari" : "Bulan" }
}

struct MediaSection: Identifiable {
    let id: String
    let date: Date?   // nil = tanpa header (sort ukuran)
    var assets: [PHAsset]
}

struct Album: Identifiable {
    let id: String
    let title: String
    let assets: PHFetchResult<PHAsset>   // urutan asli album
}

enum Source: CaseIterable {
    case all, camera, other
    var title: String {
        switch self {
        case .all: "Glint"
        case .camera: "Kamera"
        case .other: "Lainnya"
        }
    }
}

struct Listing {
    var items: [PHAsset] = []
    var sections: [MediaSection] = []
    var totalBytes: Int64 = 0
}
