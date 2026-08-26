import QuickLook
import SwiftUI
import UIKit

/// A transparent overlay whose `UIView` is handed back so QuickLook can zoom its
/// open/close transition out of (and back into) the image thumbnail. Shared by
/// ``SessionShareSheet`` and ``SubstanceShareSheet``.
struct ZoomSourceView: UIViewRepresentable {
    let onResolve: (UIView) -> Void

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { onResolve(view) }
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}
}

/// Presents the session image full-screen in `QLPreviewController` — the system
/// viewer with Markup (annotate/crop), rotate, share and print — zooming out of
/// a source thumbnail, on an ultra-thin-material backdrop rather than opaque black.
enum ImageQuickLook {
    /// QuickLook holds its delegate/dataSource weakly, so retain the coordinator
    /// for the lifetime of the presentation.
    private static var coordinator: Coordinator?

    @MainActor
    static func present(url: URL, from source: UIView?) {
        guard let top = topViewController() else { return }
        let coordinator = Coordinator(url: url, sourceView: source)
        Self.coordinator = coordinator
        let controller = MaterialPreviewController()
        controller.dataSource = coordinator
        controller.delegate = coordinator
        top.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let root = scene.keyWindow?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        weak var sourceView: UIView?

        init(url: URL, sourceView: UIView?) {
            self.url = url
            self.sourceView = sourceView
        }

        func numberOfPreviewItems(in _: QLPreviewController) -> Int {
            1
        }

        func previewController(_: QLPreviewController, previewItemAt _: Int) -> any QLPreviewItem {
            url as NSURL
        }

        func previewController(_: QLPreviewController, transitionViewFor _: any QLPreviewItem) -> UIView? {
            sourceView
        }

        func previewControllerDidDismiss(_: QLPreviewController) {
            ImageQuickLook.coordinator = nil
        }
    }
}

/// A `QLPreviewController` that wears an ultra-thin material backdrop *from the
/// first frame*. QuickLook paints an opaque black background as it appears, so
/// swapping it only at present-completion lets that black flash through the zoom
/// transition. Installing the material in `viewWillAppear` — and re-clearing
/// across the first few layout passes to catch QuickLook's async content-
/// background repaint — keeps the backdrop material throughout, while the bounded
/// clear window leaves the later Markup toolbar's own chrome untouched.
private final class MaterialPreviewController: QLPreviewController {
    private static let backdropTag = 0x5170 // arbitrary, stable marker

    /// Layout passes still owed an opaque-background sweep. Seeded on appear and
    /// counted down so we only fight QuickLook during its initial layout, not for
    /// the controller's whole life (which would strip Markup chrome).
    private var pendingClears = 0

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installBackdrop()
        clearOpaqueBackgrounds(view)
        pendingClears = 4
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard pendingClears > 0 else { return }
        pendingClears -= 1
        clearOpaqueBackgrounds(view)
    }

    private func installBackdrop() {
        guard view.viewWithTag(Self.backdropTag) == nil else { return }
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.tag = Self.backdropTag
        blur.frame = view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(blur, at: 0)
    }

    /// Recursively clear every opaque backing color, skipping our own blur.
    private func clearOpaqueBackgrounds(_ view: UIView) {
        guard view.tag != Self.backdropTag else { return }
        if let backing = view.backgroundColor, backing != .clear {
            view.backgroundColor = .clear
        }
        view.subviews.forEach(clearOpaqueBackgrounds)
    }
}
