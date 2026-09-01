import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// Orchestrates a scanned barcode payload into a resolved substance: GS1 parse →
/// GTIN/UPC → openFDA → alias match. The OCR path is resolved directly by
/// ``LabelMatcher``; this covers the network-backed barcode path only.
enum ScanResolver {
    static func resolveBarcode(_ payload: String) async -> ResolvedDrug? {
        // GS1 DataMatrix / GS1-128 with a GTIN Application Identifier.
        if let gtin = GS1Parser.parse(payload).gtin,
           let product = await NDCResolver.lookup(gtin: gtin),
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
        if let upc, let product = await NDCResolver.lookup(upc: upc),
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
    /// What the scan is for. `.log` resolves one item to a dose to stage;
    /// `.identify` gathers everything in frame into a ``BoxReading`` for the
    /// box-identification result screen (and the inventory add form).
    enum Mode {
        case log
        case identify
    }

    enum Phase {
        case scanning
        case resolving
        case resolved(ResolvedDrug)
        /// No substance matched. `canSearch` is true for OCR text (offer manual
        /// search with `text`), false for an unrecognized barcode.
        case noMatch(text: String, canSearch: Bool)
        /// Identify mode: what has been read so far. `barcodeKnown` when a
        /// barcode in frame resolved against the bundled registry.
        case reading(BoxReading, barcodeKnown: Bool)
    }

    let mode: Mode
    private(set) var phase: Phase = .scanning

    /// Identify mode: transcripts keyed by the recognized region, so a region
    /// whose text sharpens over frames replaces its earlier reading.
    private var transcripts: [UUID: String] = [:]
    private var transcriptOrder: [UUID] = []
    private var barcodes: [String] = []
    private var barcodeKnown = false

    init(mode: Mode = .log) {
        self.mode = mode
    }

    /// Identify mode: the reading gathered so far.
    var reading: BoxReading {
        BoxReading(texts: transcriptOrder.compactMap { transcripts[$0] }, barcodes: barcodes)
    }

    /// Barcodes already attempted, so a barcode lingering in frame resolves once.
    private var seenBarcodes: Set<String> = []

    /// OCR transcripts already auto-checked, so a name lingering in frame is
    /// tried once (and a wrong auto-match isn't re-surfaced after "Scan Again").
    private var seenTexts: Set<String> = []

    /// A tapped item: resolve a barcode over the network, or OCR text locally. An
    /// explicit tap always resolves — even a barcode the auto-handler already
    /// tried — so it isn't a dead spot after "Scan Again".
    func handleTap(on item: RecognizedItem) {
        if mode == .identify {
            gather([item])
            return
        }
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
    /// in" path. Text auto-surfaces only on a **high-confidence** (exact alias)
    /// match, so pointing at a name the library knows fills in without a tap;
    /// anything fuzzier waits for a deliberate tap (`handleTap` runs the full
    /// cascade), since every frame surfaces many regions and a guess must not
    /// present itself.
    func autoHandle(_ items: [RecognizedItem]) {
        if mode == .identify {
            gather(items)
            return
        }
        guard case .scanning = phase else { return }
        for case let .barcode(barcode) in items {
            if let payload = barcode.payloadStringValue, seenBarcodes.insert(payload).inserted {
                resolveBarcode(payload)
                return
            }
        }
        for case let .text(text) in items {
            let transcript = text.transcript
            guard seenTexts.insert(transcript).inserted else { continue }
            if let resolved = LabelMatcher.resolve(ocrText: transcript, highConfidenceOnly: true) {
                phase = .resolved(resolved)
                return
            }
        }
    }

    func resumeScanning() {
        phase = .scanning
    }

    /// Identify mode: fold recognized items into the reading. A barcode the
    /// bundled registry knows marks the reading as barcode-backed; the caller
    /// (`LabelScannerView`) then hands the reading over without a tap.
    private func gather(_ items: [RecognizedItem]) {
        for item in items {
            switch item {
            case let .barcode(barcode):
                guard let payload = barcode.payloadStringValue, !barcodes.contains(payload) else { continue }
                barcodes.append(payload)
                if SubstanceStore.shared.productCode(forBarcode: payload) != nil {
                    barcodeKnown = true
                }
            case let .text(text):
                let transcript = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else { continue }
                if transcripts[item.id] == nil { transcriptOrder.append(item.id) }
                transcripts[item.id] = transcript
            @unknown default:
                continue
            }
        }
        phase = .reading(reading, barcodeKnown: barcodeKnown)
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
/// result card. In log mode, resolving to a substance hands a ``ResolvedDrug``
/// back to QuickLog; in identify mode, everything read off the box is handed
/// over as a ``BoxReading`` — on a registry-known barcode without a tap,
/// otherwise when the user taps Identify.
struct LabelScannerView: View {
    /// Called with a resolved substance to stage in QuickLog, then the scanner
    /// dismisses.
    var onResolved: (ResolvedDrug) -> Void = { _ in }
    /// Called with OCR text the user chose to search manually.
    var onSearch: (String) -> Void = { _ in }
    /// Identify mode: called with what was read, then the scanner dismisses.
    var onCapture: ((BoxReading) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var model: LabelScanModel
    @State private var cameraStatus: CameraStatus = .checking

    private enum CameraStatus { case checking, authorized, denied }

    /// The logging scanner: one label → one staged dose.
    init(onResolved: @escaping (ResolvedDrug) -> Void, onSearch: @escaping (String) -> Void) {
        self.onResolved = onResolved
        self.onSearch = onSearch
        _model = State(initialValue: LabelScanModel(mode: .log))
    }

    /// The identify scanner: the whole box → a reading.
    init(onCapture: @escaping (BoxReading) -> Void) {
        self.onCapture = onCapture
        _model = State(initialValue: LabelScanModel(mode: .identify))
    }

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
                onCapture: { reading in
                    onCapture?(reading)
                    dismiss()
                },
            )
            .padding()
        }
        .onChange(of: barcodeKnown) { _, known in
            // A registry hit is the "point and it fills in" moment — no tap needed.
            if known, let onCapture {
                onCapture(model.reading)
                dismiss()
            }
        }
    }

    private var barcodeKnown: Bool {
        if case let .reading(_, known) = model.phase { return known }
        return false
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

        /// A text region's transcript refines over frames; re-run auto-handling so
        /// a name that only becomes an exact match once it sharpens still surfaces
        /// without a tap. Cheap: `autoHandle` returns immediately once resolved and
        /// dedupes transcripts it has already checked.
        func dataScanner(
            _: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems _: [RecognizedItem],
        ) {
            model.autoHandle(updatedItems)
        }
    }
}
