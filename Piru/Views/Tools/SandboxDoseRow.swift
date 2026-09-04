import SwiftUI

/// One dose as a standard list row: a full-width name button, a labeled slider,
/// and system `Picker`/`Stepper` controls. Every target clears the 44pt minimum,
/// and each control says what it does rather than relying on a bare glyph.
/// Removing and re-planning live in the row's context menu and swipe actions,
/// where iOS users already look for them.
struct SandboxDoseRow: View {
    @Binding var row: EffectSandboxModel.Row
    let onPickSubstance: () -> Void
    let onSetRoute: (RouteOfAdministration) -> Void
    /// Reports whether the dose thumb is currently held, so the screen can
    /// suspend the back-swipe for the duration.
    let onThumbHeldChange: (Bool) -> Void

    private var scale: SandboxDoseScale {
        SandboxDoseScale(substance: row.substance, route: row.route, unit: row.unit, amount: row.amount)
    }

    /// Slider writes go through the scale so a drag lands on a clean detent — the
    /// engine gets 22.5 mg, never 22.499999999999996.
    private var amountBinding: Binding<Double> {
        let scale = scale
        return Binding(
            get: { min(row.amount, scale.upperBound) },
            set: { row.amount = scale.snap($0) },
        )
    }

    private var routeBinding: Binding<RouteOfAdministration> {
        Binding(get: { row.route }, set: { onSetRoute($0) })
    }

    private var readout: String {
        "\(row.amount.doseFormatted) \(row.unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            nameButton
            if row.substance != nil {
                doseControl
                Picker(selection: routeBinding) {
                    ForEach(RouteOfAdministration.allCases) { route in
                        Text(route.localizedName).tag(route)
                    }
                } label: {
                    Text("Route")
                }
                .pickerStyle(.menu)
                Stepper(value: $row.hours, in: 0 ... 24, step: 0.5) {
                    LabeledContent {
                        Text(SandboxDoseRow.timeText(row.hours))
                            .monospacedDigit()
                    } label: {
                        Text("Taken")
                    }
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private var nameButton: some View {
        Button(action: onPickSubstance) {
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(Color(hex: row.colorHex))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(row.substance == nil ? String(localized: "Choose substance") : row.displayName)
                    .cardTitle()
                    .foregroundStyle(row.substance == nil ? Theme.secondaryLabel : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .frame(minHeight: 32)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Substance")
        .accessibilityValue(row.substance == nil ? Text("None") : Text(verbatim: row.displayName))
        .accessibilityHint("Choose a different substance")
    }

    private var doseControl: some View {
        let scale = scale
        let level = scale.level(for: row.amount)
        return VStack(spacing: Spacing.xxs) {
            HStack(spacing: Spacing.sm) {
                Text("Dose")
                    .foregroundStyle(Theme.secondaryLabel)
                Spacer(minLength: 4)
                Text(readout)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(level?.labelColor ?? .primary)
                if let level {
                    Text(level.displayName)
                        .captionSecondary()
                }
            }
            Slider(value: amountBinding, in: 0 ... scale.upperBound, step: scale.step) { editing in
                onThumbHeldChange(editing)
            }
            .tint(Color(hex: row.colorHex))
            .background(alignment: .leading) { tierTicks(scale) }
            // `minimumDistance: 0` fires on touch-down, before any movement — the
            // back-swipe has to be suspended *before* the pan is recognized, so
            // `onEditingChanged` alone is too late.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onThumbHeldChange(true) }
                    .onEnded { _ in onThumbHeldChange(false) },
            )
            .accessibilityLabel("Dose")
            .accessibilityValue(readout)
        }
    }

    /// Faint marks where the ladder's tiers fall, each in its tier's color, so the
    /// track reads as the substance's own ladder rather than an arbitrary 0-to-max.
    private func tierTicks(_ scale: SandboxDoseScale) -> some View {
        GeometryReader { proxy in
            ForEach(scale.tierMarks) { mark in
                Capsule()
                    .fill(mark.level.labelColor.opacity(0.75))
                    .frame(width: 2, height: 7)
                    .offset(x: proxy.size.width * mark.fraction, y: proxy.size.height / 2 + 8)
            }
        }
        // The track is inset by roughly the thumb's half-width, so the ticks must
        // be too or they drift off the tier boundaries they mark.
        .padding(.horizontal, 11)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// "At start" / "30 min later" / "1 h 30 m later" — a bare "start" said
    /// nothing about what the number meant.
    static func timeText(_ hours: Double) -> String {
        guard hours > 0 else { return String(localized: "At start") }
        let totalMinutes = Int((hours * 60).rounded())
        let wholeHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if wholeHours == 0 { return String(localized: "\(minutes) min later") }
        if minutes == 0 { return String(localized: "\(wholeHours) h later") }
        return String(localized: "\(wholeHours) h \(minutes) m later")
    }
}
