import SwiftUI

/// How far the Journal's pinned header is folded, driven by the timeline's
/// scrolling the way Safari folds its address bar: scrolling down folds it by
/// the distance scrolled, scrolling up from anywhere unfolds it by the same
/// amount, and a scroll that comes to rest between the two settles to the
/// nearer one.
///
/// Owned by ``EntryListView`` and read only by the header, so a scroll tick
/// invalidates the header alone. It lives above the `safeAreaBar` content
/// because that content is re-created as the navigation bar collapses, which
/// would reset any `@State` inside it.
@MainActor
@Observable
final class JournalHeaderFold {
    /// 0 is the full card, 1 the one-row form.
    private(set) var progress: CGFloat = 0

    /// The two forms' natural heights, reported by the header as it lays
    /// out. Their difference is the scrolling that takes the header from full
    /// to folded.
    @ObservationIgnored var fullHeight: CGFloat = 160
    @ObservationIgnored var foldedHeight: CGFloat = 44

    private var foldDistance: CGFloat {
        max(40, fullHeight - foldedHeight)
    }

    /// The scroll phase the last offset change arrived in. Only a finger or
    /// its momentum moves the fold, so a programmatic scroll (the opening
    /// scroll to Now) and the content shifting under a changed inset leave it.
    @ObservationIgnored var phase: ScrollPhase = .idle

    func scrolled(by delta: CGFloat) {
        guard delta != 0, movesFold(delta: delta) else { return }
        let next = min(1, max(0, progress + delta / foldDistance))
        if next != progress {
            progress = next
        }
    }

    func phaseChanged(to newPhase: ScrollPhase) {
        phase = newPhase
        if newPhase == .idle {
            settle()
        }
    }

    /// Animates to whichever end is nearer.
    func settle() {
        guard progress > 0, progress < 1 else { return }
        let target: CGFloat = progress < 0.5 ? 0 : 1
        withAnimation(.smooth(duration: 0.3)) { progress = target }
    }

    func unfold() {
        withAnimation(.smooth(duration: 0.35)) { progress = 0 }
    }

    func reset() {
        if progress != 0 {
            progress = 0
        }
    }

    private func movesFold(delta: CGFloat) -> Bool {
        switch phase {
        case .tracking, .interacting, .decelerating: true
        // Scroll to top (a status-bar tap) unfolds on its way up.
        case .animating: delta < 0
        // A Mac scroll wheel reports no phase.
        case .idle: Self.idleScrollMovesFold
        @unknown default: false
        }
    }

    #if os(macOS)
        private static let idleScrollMovesFold = true
    #else
        private static let idleScrollMovesFold = false
    #endif
}

extension View {
    /// Feeds this scroll view's travel into `fold`. A no-op when `fold` is nil.
    func drivesHeaderFold(_ fold: JournalHeaderFold?) -> some View {
        modifier(HeaderFoldScrollTracker(fold: fold))
    }
}

private struct HeaderFoldScrollTracker: ViewModifier {
    let fold: JournalHeaderFold?

    /// The scroll offset clamped to the scrollable range, so rubber-banding
    /// past either end moves nothing, and the top inset it was clamped
    /// against. Mid-list the offset holds still as the header's height moves
    /// the inset, so only the finger's travel changes it.
    private struct Sample: Equatable {
        let offset: CGFloat
        let topInset: CGFloat
    }

    func body(content: Content) -> some View {
        if let fold {
            content
                .onScrollGeometryChange(for: Sample.self) { geometry in
                    let top = -geometry.contentInsets.top
                    let bottom = max(top, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
                    return Sample(offset: min(max(geometry.contentOffset.y, top), bottom), topInset: geometry.contentInsets.top)
                } action: { old, new in
                    // At the top the offset follows the inset as the header
                    // resizes; only travel past the inset's own shift counts.
                    let insetShift = new.topInset - old.topInset
                    let atTop = old.offset <= -old.topInset + 0.5
                    fold.scrolled(by: new.offset - old.offset + (atTop ? insetShift : 0))
                }
                .onScrollPhaseChange { _, newPhase in
                    fold.phaseChanged(to: newPhase)
                }
        } else {
            content
        }
    }
}

/// Lays the header's full and folded forms over each other at the top and
/// takes a height between theirs, `progress` of the way to the folded one.
/// Animatable, so a settle animates the height along with the fades.
struct HeaderFoldLayout: Layout {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let natural = ProposedViewSize(width: proposal.width, height: nil)
        let sizes = subviews.map { $0.sizeThatFits(natural) }
        guard let full = sizes.first else { return .zero }
        let folded = sizes.count > 1 ? sizes[1] : full
        let width = proposal.width ?? max(full.width, folded.width)
        return CGSize(width: width, height: full.height + (folded.height - full.height) * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

/// The header's two forms morphing on one progress value: the full form fades
/// out, the folded row fades in over it, and the height between them follows
/// ``HeaderFoldLayout``. The two share their title's position, so the title
/// holds still while the rest folds away beneath it. Only this
/// view reads the progress; `full` and `folded` are built by the caller and
/// are left alone by a scroll tick.
struct HeaderFoldStack<Full: View, Folded: View>: View {
    let fold: JournalHeaderFold
    @ViewBuilder let full: Full
    @ViewBuilder let folded: Folded

    var body: some View {
        let progress = fold.progress
        // One cross-fade over the middle of the fold, at complementary
        // opacities, so the shared title never fades far.
        let fade = min(1, max(0, (progress - 0.2) / 0.6))
        HeaderFoldLayout(progress: progress) {
            full
                .opacity(1 - fade)
                .allowsHitTesting(progress < 0.5)
                .accessibilityHidden(progress >= 0.5)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fold.fullHeight = $0 }
            folded
                .opacity(fade)
                .allowsHitTesting(progress >= 0.5)
                .accessibilityHidden(progress < 0.5)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fold.foldedHeight = $0 }
        }
        .clipped()
    }
}
