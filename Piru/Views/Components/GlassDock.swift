import SwiftUI
import UIKit

// MARK: - Metrics

/// Shared geometry for every dock face. One contract so the pinned bottom
/// control (search field, Log button) sits at an *identical* position in
/// each face and the faces morph into one another instead of jumping.
enum GlassDockMetrics {
    /// The floating-sheet inset: 8pt off the screen sides and bottom, like a
    /// native partial-detent sheet on iOS 26.
    static let edgeInset: CGFloat = 8
    /// Content insets for full faces — horizontal 16, top 12, bottom 8.
    static let contentInsets = EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16)
    /// One height for the pinned bottom control in every face.
    static let controlHeight: CGFloat = 48
    /// Breathing room between the control and the glass platter's edge in
    /// the bare face (Maps' collapsed-bar look).
    static let bareInset: CGFloat = 6
    /// Half the bare face's height (48pt control + 6pt platter inset each
    /// side) — the radius that makes the glass platter a capsule around it.
    static var bareRadius: CGFloat {
        (controlHeight + bareInset * 2) / 2
    }
}

// MARK: - Glass Dock

/// The screen's single bottom surface, styled like a native detented sheet —
/// full-width, top-rounded, glass bleeding under the home indicator — but
/// driven by the caller's own state machine: native child sheets can't morph
/// between faces and never grant programmatic keyboard focus. With nothing
/// to show but a lone control (`isBare`), the glass collapses to a capsule
/// around it and grows back as content appears.
struct GlassDock<Content: View>: View {
    /// Collapsed to a bare capsule (a lone field) vs the full sheet face.
    var isBare: Bool
    var content: Content

    /// The dock's corner radius, resolved by UIKit as concentric with the
    /// screen for the glass surface's exact frame (see
    /// ``ConcentricRadiusReader``). Starts at a sane floor until the first
    /// layout pass reports the real value.
    @State private var cornerRadius: CGFloat = 24

    init(isBare: Bool, @ViewBuilder content: () -> Content) {
        self.isBare = isBare
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background {
                // One persistent glass element for every face. Bare: a
                // capsule hugging the control inside the safe area. With
                // content: the surface runs below it to 8pt above the
                // physical screen bottom, its corner radius UIKit-resolved
                // as concentric with the screen corners (54pt = display
                // radius − 8pt inset on a Pro Max) — SwiftUI's
                // ConcentricRectangle resolves against the presenting
                // sheet's container shape instead and lands on the wrong
                // radius. NOT a GlassEffectContainer: hoisting the glass
                // into a container renders it above the dock's own content,
                // washing the rows out.
                Color.clear
                    .glassEffect(
                        .regular,
                        in: .rect(
                            cornerRadius: isBare ? GlassDockMetrics.bareRadius : cornerRadius,
                            style: .continuous,
                        ),
                    )
                    .overlay {
                        ConcentricRadiusReader { radius in
                            guard !isBare, radius > 0, abs(radius - cornerRadius) > 0.5 else { return }
                            withAnimation(.snappy) { cornerRadius = radius }
                        }
                    }
                    .padding(.bottom, isBare ? 0 : GlassDockMetrics.edgeInset)
                    // The keyboard region is ignored too — with it open, the
                    // glass keeps running underneath instead of stopping 8pt
                    // above the content and letting the bottom control poke
                    // out.
                    .ignoresSafeArea(isBare ? .container : [.container, .keyboard], edges: isBare ? [] : .bottom)
            }
            // The bare capsule floats clear of whatever is below it — the
            // home indicator or an open keyboard — by the same 8pt the
            // surface uses.
            .padding(.bottom, isBare ? GlassDockMetrics.edgeInset : 0)
            .padding(.horizontal, GlassDockMetrics.edgeInset)
            // Tapping empty dock space dismisses the keyboard (buttons and
            // fields consume their own touches, so steppers keep it open).
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            // Collapsing/growing between the bare capsule and the full
            // surface always animates — otherwise the field snaps smaller
            // the moment typing starts.
            .animation(.snappy, value: isBare)
    }
}

// MARK: - Concentric Radius Reader

/// Reports the corner radius UIKit resolves as *concentric with the screen*
/// for this view's frame, via the public iOS 26 corner-configuration API.
///
/// SwiftUI's `ConcentricRectangle` resolves against the nearest SwiftUI
/// container shape — inside a sheet that's the presentation's shape, not the
/// device screen, so a bottom-floating surface gets the wrong radius. UIKit's
/// `containerConcentric` resolution walks the real view/window hierarchy, so
/// it derives the radius from the display corners. Overlay this on the glass
/// surface (same frame) and feed the reported value back as a fixed radius.
private struct ConcentricRadiusReader: UIViewRepresentable {
    var onResolve: (CGFloat) -> Void

    func makeUIView(context _: Context) -> ResolverView {
        let view = ResolverView()
        view.onResolve = onResolve
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.cornerConfiguration = .corners(radius: .containerConcentric(minimum: 0))
        return view
    }

    func updateUIView(_ uiView: ResolverView, context _: Context) {
        uiView.onResolve = onResolve
    }

    final class ResolverView: UIView {
        var onResolve: ((CGFloat) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            let radius = effectiveRadius(corner: .bottomLeft)
            // Defer out of the layout pass before touching SwiftUI state.
            DispatchQueue.main.async { [weak self] in
                self?.onResolve?(radius)
            }
        }
    }
}
