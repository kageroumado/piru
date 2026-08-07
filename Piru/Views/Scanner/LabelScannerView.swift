import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// Orchestrates a scanned barcode payload into a resolved substance: GS1 parse →
/// GTIN/UPC → openFDA → alias match. The OCR path is resolved directly by
/// ``LabelMatcher``; this covers the network-backed barcode path only.
enum ScanResolver {
    static func resolveBarcode(_ payload: String) async -> ResolvedDrug? {
        let resolver = NDCResolver()

        // GS1 DataMatrix / GS1-128 with a GTIN Application Identifier.
        if let gtin = GS1Parser.parse(payload).gtin,
           let product = await resolver.lookup(gtin: gtin),
           let resolved = LabelMatcher.resolve(product: product) {
            return resolved
        }

        // Plain retail barcodes: UPC-A (12) or a UPC-A wrapped in an EAN-13 (a
        // leading zero). The label endpoint takes the raw 12 digits.
        let digits = payload.filter(\.isNumber)
        let upc: String? = switch digits.count {
        case 12: digits
        case 13 where digits.first == "0": String(digits.dropFirst())
        default: nil
        }
        if let upc, let product = await resolver.lookup(upc: upc),
           let resolved = LabelMatcher.resolve(product: product) {
            return resolved
        }
        return nil
    }
}

/// Drives the scanner UI: what the live camera has recognized and how it resolved.
@Observable
@MainActor
final class LabelScanModel {
    enum Phase {
        case scanning
        case resolving
        case resolved(ResolvedDrug)
        /// No substance matched. `canSearch` is true for OCR text (offer manual
        /// search with `text`), false for an unrecognized barcode.
        case noMatch(text: String, canSearch: Bool)
    }

    private(set) var phase: Phase = .scanning

    /// Barcodes already attempted, so a barcode lingering in frame resolves once.
    private var seenBarcodes: Set<String> = []

    /// A tapped item: resolve a barcode over the network, or OCR text locally. An
    /// explicit tap always resolves — even a barcode the auto-handler already
    /// tried — so it isn't a dead spot after "Scan Again".
    func handleTap(on item: RecognizedItem) {
        if case .resolving = phase { return }
        switch item {
        case let .barcode(barcode):
            if let payload = barcode.payloadStringValue {
                seenBarcodes.insert(payload)
                resolveBarcode(payload)
            }
        case let .text(text):
            resolveText(text.transcript)
        @unknown default:
            break
        }
    }

    /// First appearance of any barcode auto-resolves it — the "point and it fills
    /// in" path. Text waits for a tap, since every frame surfaces many regions.
    func autoHandle(_ items: [RecognizedItem]) {
        guard case .scanning = phase else { return }
        for case let .barcode(barcode) in items {
            if let payload = barcode.payloadStringValue, seenBarcodes.insert(payload).inserted {
                resolveBarcode(payload)
                return
            }
        }
    }

    func resumeScanning() {
        phase = .scanning
    }

    private func resolveBarcode(_ payload: String) {
        phase = .resolving
        Task {
            if let resolved = await ScanResolver.resolveBarcode(payload) {
                phase = .resolved(resolved)
            } else {
                phase = .noMatch(text: "", canSearch: false)
            }
        }
    }

    private func resolveText(_ text: String) {
        if let resolved = LabelMatcher.resolve(ocrText: text) {
            phase = .resolved(resolved)
        } else {
            phase = .noMatch(text: LabelMatcher.bestCandidate(in: text), canSearch: true)
        }
    }
}

/// Full-screen live label scanner. Presents the VisionKit camera and a floating
/// result card; resolving to a substance hands a ``ResolvedDrug`` back to QuickLog.
struct LabelScannerView: View {
    /// Called with a resolved substance to stage in QuickLog, then the scanner
    /// dismisses.
    let onResolved: (ResolvedDrug) -> Void
    /// Called with OCR text the user chose to search manually.
    let onSearch: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = LabelScanModel()
    @State private var cameraStatus: CameraStatus = .checking

    private enum CameraStatus { case checking, authorized, denied }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if DataScannerViewController.isSupported, DataScannerViewController.isAvailable, cameraStatus == .authorized {
                DataScannerRepresentable(model: model)
                    .ignoresSafeArea()
                overlay
            } else if cameraStatus == .checking {
                ProgressView().tint(.white)
            } else {
                unavailableView
            }
        }
        .task { await requestCameraIfNeeded() }
    }

    private var overlay: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .tint(.white)
                .accessibilityLabel("Close scanner")
            }
            .padding()

            Spacer()

            ScanResultCard(
                phase: model.phase,
                onAdd: { resolved in
                    onResolved(resolved)
                    dismiss()
                },
                onSearch: { text in
                    onSearch(text)
                    dismiss()
                },
                onRescan: { model.resumeScanning() },
            )
            .padding()
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label(
                cameraStatus == .denied ? "Camera Access Needed" : "Scanning Unavailable",
                systemImage: "camera.fill",
            )
        } description: {
            Text(cameraStatus == .denied
                ? "Enable camera access in Settings to scan medication labels."
                : "Label scanning isn't available on this device.")
        } actions: {
            if cameraStatus == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Done") { dismiss() }
        }
        .preferredColorScheme(.dark)
    }

    private func requestCameraIfNeeded() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraStatus = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraStatus = granted ? .authorized : .denied
        default:
            cameraStatus = .denied
        }
    }
}

/// Hosts a `DataScannerViewController` running text + barcode recognition in one
/// camera session.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let model: LabelScanModel

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.dataMatrix, .ean13, .ean8, .upce, .code128, .gs1DataBar]),
                .text(),
            ],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true,
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !context.coordinator.isScanning {
            context.coordinator.isScanning = true
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator _: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let model: LabelScanModel
        var isScanning = false

        init(model: LabelScanModel) {
            self.model = model
        }

        func dataScanner(_: DataScannerViewController, didTapOn item: RecognizedItem) {
            model.handleTap(on: item)
        }

        func dataScanner(
            _: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems _: [RecognizedItem],
        ) {
            model.autoHandle(addedItems)
        }
    }
}
