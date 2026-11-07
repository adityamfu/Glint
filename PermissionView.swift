import Photos
import SwiftUI

struct PermissionView: View {
    let status: PHAuthorizationStatus

    var body: some View {
        ContentUnavailableView {
            Label(status == .limited ? "Akses Terbatas" : "Akses Foto Ditolak", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text(status == .limited
                 ? "Glint perlu akses ke semua foto agar bisa menampilkan dan mengelola seluruh galerimu."
                 : "Izinkan Glint mengakses foto lewat Pengaturan.")
        } actions: {
            Button("Buka Pengaturan") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
