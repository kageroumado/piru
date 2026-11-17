// PairingView's scanner on Android, standing in for Piru/Views/Profiles/Sharing/PairingScanner+iOS.swift:
// the same `PairingScannerSheet(onScan:)`, reading QR codes until one is a Piru pairing link.
// The camera and the QR reading are Skip/AndroidQRScanner.kt (CameraX and ZXing). Scan asks for
// the camera when it opens; a refusal says so and offers the app's settings, and the scanner
// checks again when Piru returns to the foreground.

import SkipBridge
import SkipFuse
import SwiftUI

/// Receives the camera's answers from Kotlin. One scanner is open at a time, so each kind holds
/// a single handler.
/* SKIP @bridge */ public final class AndroidCameraResults: @unchecked Sendable {
    /* SKIP @bridge */ public static let shared = AndroidCameraResults()

    var onAccess: ((Bool) -> Void)?
    var onScan: ((String) -> Void)?
    var onFailure: (() -> Void)?

    private init() {}

    /* SKIP @bridge */ public func didRequestAccess(_ granted: Bool) {
        onAccess?(granted)
    }

    /* SKIP @bridge */ public func didScan(_ text: String) {
        onScan?(text)
    }

    /* SKIP @bridge */ public func didFail() {
        onFailure?()
    }
}

/// Calls into Skip/AndroidQRScanner.kt.
enum AndroidCamera {
    private static var kotlin: AnyDynamicObject? {
        try? AnyDynamicObject(forStaticsOfClassName: "piru.module.AndroidCamera")
    }

    static var hasCamera: Bool {
        (try? kotlin?.hasCamera() as Bool?) == true
    }

    static var isAuthorized: Bool {
        (try? kotlin?.isAuthorized() as Bool?) == true
    }

    static func requestAccess() -> Bool {
        (try? kotlin?.requestAccess() as Bool?) == true
    }
}

struct PairingScannerSheet: View {
    let onScan: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: ScannerState = .asking
    @State private var scanned = false

    enum ScannerState: Equatable {
        case asking
        case scanning
        case denied
        case noCamera
        case failed
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .asking:
                    ProgressView()
                case .scanning:
                    // Below the bar, so Cancel stays visible over the camera.
                    ComposeView {
                        try! AnyDynamicObject(className: "piru.module.AndroidQRScannerComposer")
                    }
                case .denied:
                    ContentUnavailableView {
                        Label("Camera Off", systemImage: "camera")
                    } description: {
                        Text("Allow Piru to use the camera in Settings to scan their code.")
                    } actions: {
                        Button("Open Settings") { openPlatformSettings() }
                    }
                case .noCamera:
                    ContentUnavailableView(
                        "Scanner Unavailable",
                        systemImage: "camera",
                        description: Text("This phone has no camera. Let them scan your code, then send you a session."),
                    )
                case .failed:
                    ContentUnavailableView(
                        "Scanner Unavailable",
                        systemImage: "camera",
                        description: Text("The camera could not be started."),
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Scan Their Code")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .task { start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, state == .denied { start() }
        }
        .onDisappear {
            AndroidCameraResults.shared.onAccess = nil
            AndroidCameraResults.shared.onScan = nil
            AndroidCameraResults.shared.onFailure = nil
        }
    }

    private func start() {
        let results = AndroidCameraResults.shared
        results.onScan = { text in
            guard !scanned, let url = URL(string: text), PairingCode(url: url) != nil else { return }
            scanned = true
            onScan(url)
        }
        results.onFailure = { state = .failed }
        guard AndroidCamera.hasCamera else {
            state = .noCamera
            return
        }
        if AndroidCamera.isAuthorized {
            state = .scanning
            return
        }
        results.onAccess = { granted in
            state = granted ? .scanning : .denied
        }
        if !AndroidCamera.requestAccess() {
            state = .denied
        }
    }
}
