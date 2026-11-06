import SwiftUI
import VisionKit

struct BarcodeScannerView: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerRepresentable { code in
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        finish(code)
                    }
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        Text("Halte die Kamera auf den Barcode")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 32)
                    }
                } else {
                    Form {
                        Section {
                            Text("Der Kamera-Scanner ist hier nicht verfügbar. Prüfe, ob BuyFood die Kamera nutzen darf, oder gib den Barcode von Hand ein.")
                                .foregroundStyle(.secondary)
                        }
                        Section("Barcode eingeben") {
                            TextField("z. B. 4001234567890", text: $manualCode)
                                .keyboardType(.numberPad)
                            Button("Artikel suchen") { finish(manualCode) }
                                .disabled(manualCode.filter(\.isNumber).count < 8)
                        }
                    }
                }
            }
            .navigationTitle("Barcode scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }

    private func finish(_ code: String) {
        dismiss()
        onCode(code)
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .itf14])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        DispatchQueue.main.async { try? vc.startScanning() }
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let barcode) in addedItems {
                if let payload = barcode.payloadStringValue, !payload.isEmpty {
                    done = true
                    scanner.stopScanning()
                    onCode(payload)
                    return
                }
            }
        }
    }
}
