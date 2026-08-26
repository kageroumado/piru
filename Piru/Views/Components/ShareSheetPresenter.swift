import SwiftUI
import UIKit

/// Presents a `UIActivityViewController` imperatively from the top-most view
/// controller — avoids the nested-SwiftUI-`.sheet` jank when sharing from within
/// an already-presented sheet. Reusable hoist of the presenter that lived
/// privately in `SubstanceLibraryView`, generalized to arbitrary share items.
enum ShareSheetPresenter {
    @MainActor
    static func present(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let root = scene.keyWindow?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
