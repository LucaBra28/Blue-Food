import PhotosUI
import SwiftUI

struct CropItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum CropShape { case circle, roundedSquare }

/// Lädt das gewählte Foto (auf max. 2048 px verkleinert) für den Zuschnitt.
@MainActor
func loadUIImage(from item: PhotosPickerItem?) async -> UIImage? {
    guard let item, let data = try? await item.loadTransferable(type: Data.self),
          let image = UIImage(data: data) else { return nil }
    let longest = max(image.size.width, image.size.height)
    guard longest > 2048 else { return image }
    let scale = 2048 / longest
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
}

/// Bild verschieben und zoomen; liefert einen quadratischen JPEG-Ausschnitt.
struct ImageCropperView: View {
    let image: UIImage
    var shape: CropShape = .circle
    var onDone: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let maxZoom: CGFloat = 6

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let side = min(geo.size.width - 40, 360)
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: displaySize(side).width, height: displaySize(side).height)
                        .offset(offset)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    overlay(side: side, in: geo.size)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onAppear { lastSide = side }
                .onChange(of: side) { _, new in lastSide = new }
                .gesture(dragGesture(side: side).simultaneously(with: magnifyGesture(side: side)))
                .overlay(alignment: .bottom) { zoomSlider(side: side) }
            }
            .background(Color.black)
            .navigationTitle("Bild anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { finish() }.bold()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Geometrie

    @State private var lastSide: CGFloat = 320

    private func baseScale(_ side: CGFloat) -> CGFloat { side / min(image.size.width, image.size.height) }

    private func displaySize(_ side: CGFloat) -> CGSize {
        let s = baseScale(side) * zoom
        return CGSize(width: image.size.width * s, height: image.size.height * s)
    }

    private func clamped(_ o: CGSize, side: CGFloat, zoom z: CGFloat) -> CGSize {
        let s = baseScale(side) * z
        let maxX = max(0, (image.size.width * s - side) / 2)
        let maxY = max(0, (image.size.height * s - side) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    // MARK: Gesten

    private func dragGesture(side: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { v in
                lastSide = side
                offset = clamped(CGSize(width: committedOffset.width + v.translation.width,
                                        height: committedOffset.height + v.translation.height), side: side, zoom: zoom)
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func magnifyGesture(side: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { v in
                lastSide = side
                zoom = min(max(committedZoom * v.magnification, 1), maxZoom)
                offset = clamped(offset, side: side, zoom: zoom)
            }
            .onEnded { _ in committedZoom = zoom; committedOffset = offset }
    }

    private func zoomSlider(side: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
            Slider(value: Binding(get: { zoom }, set: { newValue in
                lastSide = side
                zoom = newValue; committedZoom = newValue
                offset = clamped(offset, side: side, zoom: newValue); committedOffset = offset
            }), in: 1...maxZoom)
            .accessibilityLabel("Zoom")
            Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 24)
        .padding(.horizontal, 20)
    }

    // MARK: Overlay

    private func overlay(side: CGFloat, in size: CGSize) -> some View {
        let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        return ZStack {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addPath(cropPath(rect))
            }
            .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
            cropPath(rect).stroke(.white.opacity(0.9), lineWidth: 1.5)
        }
    }

    private func cropPath(_ rect: CGRect) -> Path {
        switch shape {
        case .circle: Path(ellipseIn: rect)
        case .roundedSquare: Path(roundedRect: rect, cornerRadius: rect.width * 0.24, style: .continuous)
        }
    }

    // MARK: Ergebnis

    private func finish() {
        let side = lastSide
        let out = min(1024, max(256, min(image.size.width, image.size.height) / zoom))
        let factor = out / side
        let d = displaySize(side)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format)
        let data = renderer.jpegData(withCompressionQuality: 0.85) { _ in
            image.draw(in: CGRect(x: (side / 2 + offset.width - d.width / 2) * factor,
                                  y: (side / 2 + offset.height - d.height / 2) * factor,
                                  width: d.width * factor, height: d.height * factor))
        }
        onDone(data)
        dismiss()
    }
}
