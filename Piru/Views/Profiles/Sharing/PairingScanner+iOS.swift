import SwiftUI
import Vision
import VisionKit

/// The camera, reading QR codes until one is a Piru pairing link.
struct PairingScannerSheet: View {
    let onScan: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    PairingScanner(onScan: onScan)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Scanner Unavailable",
                        systemImage: "camera",
                        description: Text("Point the Camera app at their code instead. It opens in Piru."),
                    )
                }
            }
            .navigationTitle("Scan Their Code")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

private struct PairingScanner: UIViewControllerRepresentable {
    let onScan: (URL) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true,
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_: DataScannerViewController, context _: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator _: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (URL) -> Void
        private var done = false

        init(onScan: @escaping (URL) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_: DataScannerViewController, didAdd items: [RecognizedItem], allItems _: [RecognizedItem]) {
            guard !done else { return }
            for case let .barcode(barcode) in items {
                guard let text = barcode.payloadStringValue, let url = URL(string: text),
                      PairingCode(url: url) != nil else { continue }
                done = true
                onScan(url)
                return
            }
        }
    }
}
