import AppKit
import QuickLook
import SwiftUI

struct ZoomSourceView: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view) }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}

enum ImageQuickLook {
    @MainActor
    static func present(url: URL, from _: NSView?) {
        NSWorkspace.shared.open(url)
    }
}
