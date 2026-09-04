import SwiftUI

#if canImport(UIKit)
    import UIKit

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

#elseif canImport(AppKit)
    import AppKit

    enum ShareSheetPresenter {
        @MainActor
        static func present(_ items: [Any]) {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first,
                  let contentView = window.contentView
            else { return }
            let picker = NSSharingServicePicker(items: items)
            let rect = CGRect(
                x: contentView.bounds.midX,
                y: contentView.bounds.midY,
                width: 0, height: 0,
            )
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
    }
#endif
