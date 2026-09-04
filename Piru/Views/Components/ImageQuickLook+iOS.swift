import QuickLook
import SwiftUI
import UIKit

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

enum ImageQuickLook {
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

private final class MaterialPreviewController: QLPreviewController {
    private static let backdropTag = 0x5170

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

    private func clearOpaqueBackgrounds(_ view: UIView) {
        guard view.tag != Self.backdropTag else { return }
        if let backing = view.backgroundColor, backing != .clear {
            view.backgroundColor = .clear
        }
        view.subviews.forEach(clearOpaqueBackgrounds)
    }
}
