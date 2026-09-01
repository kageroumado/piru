import SwiftUI

/// One logged dose on the vertical timeline — a Liquid Glass bubble floating
/// over the curve lane. Full style stacks the name over dose + route chip;
/// compact puts name and dose on one line and drops the chip. The trailing
/// readout is the effect's phase progress (the same bar the dose hero and the
/// Active Now card draw) in effect mode, and the elimination percentage in
/// body-load mode.
struct TimelineDoseBubble: View {
    let item: TimelineDayLayout.CardItem
    let style: TimelineBubbleStyle
    /// Body-load mode: the trailing readout is what remains in the body.
    let pkMode: Bool
    let onTap: () -> Void

    static let cornerRadius: CGFloat = 14

    /// The bubble's width on the strip, per style.
    static func width(for style: TimelineBubbleStyle) -> CGFloat {
        switch style {
        case .full: 236
        case .compact: 224
        }
    }

    static func height(for style: TimelineBubbleStyle) -> CGFloat {
        switch style {
        case .full: 58
        case .compact: 40
        }
    }

    private var isActive: Bool {
        (item.remainingFraction ?? 0) > 0.03
    }

    private var displayName: String {
        CustomSubstanceStore.shared.displayName(for: item.entry.substance)
    }

    private var doseText: String {
        "\(item.entry.amount.doseFormatted) \(item.entry.unit)"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                switch style {
                case .full: fullLeading
                case .compact: compactLeading
                }

                Spacer(minLength: 4)

                trailingReadout

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.height(for: style))
            .contentShape(.rect)
            .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
    }

    private var fullLeading: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? item.color : item.color.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(verbatim: doseText)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                    ROAPill(route: item.entry.route, size: .compact)
                }
            }
        }
    }

    private var compactLeading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(verbatim: doseText)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var trailingReadout: some View {
        if pkMode {
            if let remaining = item.remainingFraction, isActive {
                Text("\(Int(remaining * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(item.color)
            }
        } else if let state = item.state {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let now = context.date
                let end = state.doseTimestamp.addingTimeInterval(state.totalMinutes * 60)
                if now >= state.doseTimestamp, now < end {
                    DosePhaseProgressBar(state: state, now: now, style: .compact)
                }
            }
        }
    }
}
