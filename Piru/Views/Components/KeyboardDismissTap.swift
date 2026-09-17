import SwiftUI

extension View {
    /// A tap anywhere outside the focused text field dismisses the keyboard.
    /// Attached once at the root: the recognizer lives on the host window, so it
    /// covers every screen and every sheet presented in it.
    ///
    /// The decimal pad has no return key and the app hosts no keyboard toolbar,
    /// so tapping away is the only way to put the keyboard down — every field
    /// commits its value live per keystroke, so dismissing is the whole job.
    func dismissesKeyboardOnTap() -> some View {
        #if canImport(UIKit)
            background { KeyboardDismissTap() }
        #else
            self
        #endif
    }
}

#if canImport(UIKit)
    import UIKit

    /// Installs a tap recognizer on the host window that resigns the keyboard on a
    /// tap outside the focused field.
    ///
    /// Why window-level (not a SwiftUI `onTapGesture`): a sheet's empty region —
    /// the tall gap below a short staged card when the keyboard is up — lies
    /// *outside* the laid-out content, where a content-attached gesture never
    /// fires. A window recognizer sees every tap in the presentation, sheets
    /// included, since UIKit presents them in the same window.
    ///
    /// `cancelsTouchesInView = false` lets the tap still reach whatever it hit, so
    /// buttons/steppers/menus keep working; the delegate declines taps that land in
    /// a text input (`UITextField`/`UITextView`, which back SwiftUI's fields) so
    /// *re-tapping a field* doesn't immediately blur it. The keyboard itself sits
    /// in its own window, so its keys never reach the recognizer.
    struct KeyboardDismissTap: UIViewRepresentable {
        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIView(context: Context) -> InstallerView {
            let view = InstallerView()
            view.isUserInteractionEnabled = false
            view.coordinator = context.coordinator
            return view
        }

        func updateUIView(_: InstallerView, context _: Context) {}

        static func dismantleUIView(_: InstallerView, coordinator: Coordinator) {
            coordinator.detach()
        }

        /// Installs/removes the recognizer as it actually enters and leaves a
        /// window — `didMoveToWindow` is the reliable hook (the window is not yet
        /// attached inside `makeUIView`).
        final class InstallerView: UIView {
            weak var coordinator: Coordinator?
            override func didMoveToWindow() {
                super.didMoveToWindow()
                if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
            }
        }

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            private weak var window: UIWindow?
            private weak var recognizer: UITapGestureRecognizer?

            func attach(to window: UIWindow) {
                guard self.recognizer == nil else { return }
                let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
                tap.cancelsTouchesInView = false
                tap.delegate = self
                window.addGestureRecognizer(tap)
                self.window = window
                self.recognizer = tap
            }

            func detach() {
                if let recognizer { window?.removeGestureRecognizer(recognizer) }
                recognizer = nil
                window = nil
            }

            @objc
            private func handleTap() {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil,
                )
            }

            /// Let scroll views and sheet pans run alongside this tap.
            func gestureRecognizer(
                _: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
            ) -> Bool {
                true
            }

            /// Don't fire when the tap lands in a text input — that tap is the user
            /// (re)focusing a field, and dismissing would fight it.
            func gestureRecognizer(
                _: UIGestureRecognizer, shouldReceive touch: UITouch,
            ) -> Bool {
                !Self.landsInTextInput(touch.view)
            }

            /// Whether `view` or any ancestor is a text input. A SwiftUI `TextField`
            /// hands the touch to a subview of its backing `UITextField`, so the
            /// walk goes all the way up rather than checking the hit view alone.
            static func landsInTextInput(_ view: UIView?) -> Bool {
                var view = view
                while let current = view {
                    if current is UITextField || current is UITextView { return true }
                    view = current.superview
                }
                return false
            }
        }
    }
#endif
