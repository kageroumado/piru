import SwiftUI
import UIKit

// MARK: - Back-swipe arbitration

struct BackSwipeSuspender: UIViewRepresentable {
    let isSuspended: Bool

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        let suspended = isSuspended
        DispatchQueue.main.async {
            uiView.enclosingNavigationController?.interactivePopGestureRecognizer?.isEnabled = !suspended
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator _: ()) {
        uiView.enclosingNavigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}

extension UIView {
    var enclosingNavigationController: UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let nav = current as? UINavigationController { return nav }
            if let controller = current as? UIViewController, let nav = controller.navigationController { return nav }
            responder = current.next
        }
        return nil
    }
}
