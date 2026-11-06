import PhotosUI
import SwiftUI

enum ImageProcessing {
    /// Schneidet mittig quadratisch zu, skaliert auf höchstens `maxSide` Pixel und liefert JPEG.
    static func squareJPEG(from data: Data, maxSide: CGFloat = 1024) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let shortSide = min(image.size.width, image.size.height)
        guard shortSide > 0 else { return nil }
        let target = min(maxSide, shortSide)
        let scale = target / shortSide
        let w = image.size.width * scale, h = image.size.height * scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        return renderer.jpegData(withCompressionQuality: 0.82) { _ in
            image.draw(in: CGRect(x: (target - w) / 2, y: (target - h) / 2, width: w, height: h))
        }
    }
}

/// Lädt das gewählte Foto, bereitet es auf und übergibt das JPEG.
@MainActor
func loadSquareJPEG(from item: PhotosPickerItem?) async -> Data? {
    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return nil }
    return ImageProcessing.squareJPEG(from: data)
}

/// Rundes Profilbild mit Initialen als Ersatz.
struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(.tint.opacity(0.18))
            if let initial = name.trimmingCharacters(in: .whitespaces).first {
                Text(String(initial).uppercased()).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.tint)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(.tint)
            }
        }
    }
}

/// Abgerundetes Listenbild mit Symbol als Ersatz.
struct ListImageView: View {
    let url: URL?
    var isShared = false
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(.tint.opacity(0.15))
            Image(systemName: isShared ? "person.2.fill" : "cart.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.tint)
        }
    }
}
