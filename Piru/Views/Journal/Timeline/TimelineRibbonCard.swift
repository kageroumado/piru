import SwiftData
import SwiftUI

/// The Journal feed's compact "now" ribbon: the last ~24 h of the continuous
/// timeline in a ~72 pt card, right edge just past now. Tap opens the
/// full-screen scrubbable ribbon (``PushRoute/timelineRibbon``). The host only
/// renders it when there are recent doses (see ``hasRecentDoses(_:now:)``) —
/// no dead chrome on a quiet journal.
struct TimelineRibbonCard: View {
    let entries: [DoseEntry]
    let colors: [SubstanceColor]

    @Environment(\.appNavigator) private var navigator
    @State private var model = TimelineRibbonModel()

    private static let ribbonHeight: CGFloat = 72
    /// Snapshot input window: doses up to 72 h back — a curve is capped at 48 h,
    /// so nothing older can reach into the ribbon's 24 h + projection span.
    private static let inputWindow: TimeInterval = 72 * 3_600

    /// Cheap early-exit gate for the host: any acute (non-background) dose in
    /// the last 24 h. `entries` must be newest-first (the Journal query is).
    static func hasRecentDoses(_ entries: [DoseEntry], now: Date = .now) -> Bool {
        let cutoff = now.addingTimeInterval(-24 * 3_600)
        for entry in entries {
            if entry.timestamp < cutoff { return false }
            if !entry.isBackgroundMed { return true }
        }
        return false
    }

    /// Content fingerprint of the ribbon's inputs — drives the rebuild task on
    /// edits, not just adds/removes (mirrors the Journal's signatures).
    private var signature: Int {
        var hasher = Hasher()
        let cutoff = Date.now.addingTimeInterval(-Self.inputWindow)
        for entry in entries {
            guard entry.timestamp >= cutoff else { break }
            hasher.combine(entry.timestamp)
            hasher.combine(entry.substance)
            hasher.combine(entry.amount)
            hasher.combine(entry.unit)
            hasher.combine(entry.route)
            hasher.combine(entry.isBackgroundMed)
        }
        for color in colors {
            hasher.combine(color.substance)
            hasher.combine(color.hexColor)
        }
        return hasher.finalize()
    }

    var body: some View {
        TimelineRibbonView(
            model: model,
            tileWidth: 150,
            height: Self.ribbonHeight,
            compact: true,
            historyLimit: 24 * 3_600,
        )
        // The compact card is a static preview: its inner horizontal
        // ScrollView would otherwise swallow every touch, so the card-level
        // tap that opens the full timeline never fired (the "I can't click
        // it" bug). Interaction — scroll + scrub — lives on the full screen.
        .allowsHitTesting(false)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(8)
        }
        .themeCard()
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            navigator.push(.timelineRibbon)
        }
        .task(id: signature) {
            let cutoff = Date.now.addingTimeInterval(-Self.inputWindow)
            let recent = Array(entries.prefix { $0.timestamp >= cutoff })
            await model.rebuild(entries: recent, colors: colors)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Dose timeline"))
        .accessibilityHint(Text("Opens the full timeline."))
        .accessibilityAddTraits(.isButton)
    }
}
