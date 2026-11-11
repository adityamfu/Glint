import MapKit
import Photos
import SwiftUI

struct InfoSheet: View {
    let asset: PHAsset
    @Environment(PhotoLibrary.self) private var library

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Tanggal", value: asset.creationDate?.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(idLocale)) ?? "-")
                    LabeledContent("Jam", value: asset.creationDate?.formatted(.dateTime.hour().minute().second().locale(idLocale)) ?? "-")
                    LabeledContent("Jenis", value: kind)
                    LabeledContent("Ukuran file", value: library.sizes[asset.localIdentifier].map(\.fileSize) ?? "Menghitung…")
                    LabeledContent("Resolusi", value: "\(asset.pixelWidth) × \(asset.pixelHeight)")
                    if asset.mediaType == .video {
                        LabeledContent("Durasi", value: Duration.seconds(asset.duration).formatted(.time(pattern: .hourMinuteSecond)))
                    }
                }
                if let coord = asset.location?.coordinate {
                    Section("Lokasi") {
                        Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1500, longitudinalMeters: 1500))) {
                            Marker("", coordinate: coord)
                        }
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                        LabeledContent("Koordinat", value: String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                    }
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var kind: String {
        if asset.mediaType == .video { return "Video" }
        if asset.mediaSubtypes.contains(.photoScreenshot) { return "Screenshot" }
        if asset.mediaSubtypes.contains(.photoLive) { return "Live Photo" }
        return "Foto"
    }
}
