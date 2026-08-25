import SwiftUI

/// **Dose & duration** — the ladder, the curve, and the phase table.
///
/// Keep this card and the Effects section separate: merging them into one
/// dial-driven card strands the Effects section with nothing but a source line
/// and leaves the per-band **frequency** data ("most reported at this dose")
/// nowhere to live. Each does the job it is shaped for. **Here: the grid**,
/// five tiers side by side, which is how you read a reference and compare tiers
/// against each other. **In Effects: the dial**, which is how you ask "what
/// does *this* dose feel like" and get an answer that changes as you drag. One
/// scale, two questions, two instruments.
struct DoseEffectsCard: View {
    let unit: String
    let doses: DoseRange?
    let duration: DurationProfile?
    var releaseWindow: String?
    var elementalFraction: Double?
    var showsDoseLadder = true
    var showsDuration = true
    var regimeLabel: DoseContext = .unknown
    var accent: Color = Theme.accent
    /// Category used to shape the drawn curve, via
    /// ``DurationProfile/fillingMissingPhases(for:)``. `nil` draws the raw phases.
    ///
    /// The curve and the numeric trio deliberately read from *different*
    /// profiles. The trio is a reference table and must stay verbatim source
    /// data. The curve is a shape, and a source that publishes only `onset` and
    /// `total` gives it no shape at all — `phaseBoundaries` then sums the
    /// present phases and collapses a 12 h profile into a ~1 h spike that
    /// contradicts the "12 h" printed directly beneath it. Measured against the
    /// bundled DB, 453 of 1,397 resolved route-profiles diverged. So the curve
    /// fills, and only the trio stays raw.
    var curveCategory: SubstanceCategory?
    /// The dose text for the tier the user is looking at, published upward so the
    /// card's own Log button can name it ("Log 50–100 mg") — the action belongs to
    /// this card, and it should say which number it is about to log.
    var selectedDoseText: Binding<String?>?

    /// Tier the user tapped, overriding the model's reference tier. Card-local
    /// and deliberately not persisted — it answers "what does Strong mean here?"
    /// in the moment, and should read as Common again next visit.
    @State private var selected: Int?
    /// The phase table grows in place rather than unfolding a disclosure.
    @State private var phasesExpanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasDosage: Bool {
        showsDoseLadder && (doses?.hasAnyValue ?? false)
    }
    private var hasDuration: Bool {
        showsDuration && duration != nil
    }

    private var tiers: DoseTierStripModel? {
        doses.map { DoseTierStripModel(doses: $0, unit: unit) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasDosage {
                doseBlock
            }
            if hasDuration, let duration {
                if hasDosage { Divider() }
                durationBlock(duration)
            }
            if let releaseWindow {
                if hasDosage || hasDuration { Divider() }
                releaseBlock(releaseWindow)
            }
        }
        .padding(.vertical, 4)
        .onAppear { publishSelection() }
        .onChange(of: selected) { publishSelection() }
    }

    /// Push the current tier's dose text to the parent. Nil when the substance has
    /// no ladder — the button then falls back to a plain "Log this".
    private func publishSelection() {
        guard let binding = selectedDoseText else { return }
        guard let tiers, hasDosage else {
            binding.wrappedValue = nil
            return
        }
        let index = min(max(selected ?? tiers.selectedID, 0), 4)
        binding.wrappedValue = tiers.tier(index)?.fullValue
    }

    // MARK: - Dose (the tier grid)

    private var doseBlock: some View {
        let tiers = self.tiers
        let activeTier = tiers.map { min(max(selected ?? $0.selectedID, 0), 4) }
        return VStack(alignment: .leading, spacing: 14) {
            if let tiers, let activeTier, let selectedTier = tiers.tier(activeTier) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedTier.name)
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 8)
                    Text(selectedTier.fullValue)
                        .font(.system(.title2, design: .rounded).weight(.heavy).monospacedDigit())
                }
                .accessibilityElement(children: .combine)
                // Without an identity the two Texts cross-fade into each other
                // on tap, which reads as a glitch rather than a value change.
                .id(activeTier)
                .transition(.opacity)
            }

            // The grid, not the dial. The dial lives in Effects, where the
            // question it answers ("what does this dose feel like?") is asked —
            // here the five tiers are a *reference*, read at a glance and
            // compared against each other, which a table does better than an arc.
            if let tiers, let activeTier {
                DoseTierStrip(tiers: tiers, selectedID: activeTier, accent: accent) { id in
                    withAnimation(.snappy(duration: 0.18)) { selected = id }
                }
            }

            if regimeLabel == .recreational { regimeBadge }

            if let elementalFraction {
                Label {
                    Text("\(Int((elementalFraction * 100).rounded()))% elemental", comment: "Elemental fraction of a salt")
                } icon: {
                    Image(systemName: "atom").imageScale(.small)
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            }

            if let doses { disclaimer(for: doses) }
        }
    }

    private var regimeBadge: some View {
        Label {
            Text("Recreational doses — not a prescribed amount")
        } icon: {
            Image(systemName: "person.fill.questionmark").imageScale(.small)
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryLabel)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func disclaimer(for doses: DoseRange) -> some View {
        if unit.localizedCaseInsensitiveContains("THC") {
            THCContentNote()
        } else {
            switch doses.dosingPrecision(unit: unit) {
            case .critical: VolumetricDosingDisclaimer()
            case .recommended: PreciseScaleNote()
            case .none: EmptyView()
            }
        }
    }

    // MARK: - Duration (curve + growing phase table)

    @ViewBuilder
    private func durationBlock(_ duration: DurationProfile) -> some View {
        let curveProfile = curveCategory.map { duration.fillingMissingPhases(for: $0) } ?? duration
        let boundaries = curveProfile.phaseBoundaries
        VStack(alignment: .leading, spacing: 10) {
            if DurationCurveView.canRender(boundaries) {
                DurationCurveView(boundaries: boundaries, accent: accent)
                    // Equal optical padding: the curve's baseline sits on the
                    // bottom inset and its peak clears the top by the same
                    // amount, so the plate doesn't read as top-heavy.
                    .padding(.vertical, 9)
                    .frame(height: 92)
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemFill), in: Self.curveShape)
                    .clipShape(Self.curveShape)
            }
            phaseTable(duration)
        }
    }

    private static let curveShape = RoundedRectangle(cornerRadius: 12)

    /// Phases beyond onset/peak/total: come-up, offset, afterglow.
    private func foldedPhases(_ duration: DurationProfile) -> Bool {
        duration.comeup != nil || duration.offset != nil || duration.afterglow != nil
    }

    /// The trio, which **grows into** the full phase table on tap rather than
    /// unfolding a separate disclosure below itself. One surface, two depths.
    private func phaseTable(_ duration: DurationProfile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                trioCell("Onset", duration.onset)
                trioDivider
                trioCell("Peak", duration.peak ?? duration.comeup)
                trioDivider
                trioCell("Total", duration.total ?? duration.offset)
            }

            if foldedPhases(duration) {
                if phasesExpanded {
                    VStack(spacing: 8) {
                        DurationPhaseRows(duration: duration)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                    }
                }
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        phasesExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(phasesExpanded ? "Fewer" : "All phases")
                        Image(systemName: phasesExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var trioDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 40)
    }

    private func trioCell(_ name: LocalizedStringKey, _ range: DurationRange?) -> some View {
        VStack(spacing: 3) {
            Text(range.map { Self.compactDuration($0) } ?? "—")
                .font(.system(.headline, design: .rounded).weight(.heavy).monospacedDigit())
            Text(name)
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase).tracking(0.5)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// Compact duration like "~30–45m", "~1.5–2.5h", or "~1–4h". One unit for the
    /// whole range: a range that reaches into hours renders both bounds in hours,
    /// so a straddling total reads "~1–4h" rather than a mixed "~60m–4h".
    static func compactDuration(_ range: DurationRange) -> String {
        if range.max >= 120 {
            func hours(_ minutes: Double) -> String {
                let h = (minutes / 60 * 2).rounded() / 2
                return h == h.rounded() ? "\(Int(h))" : String(format: "%.1f", h)
            }
            let lo = hours(range.min), hi = hours(range.max)
            return lo == hi ? "~\(lo)h" : "~\(lo)–\(hi)h"
        }
        let lo = Int(range.min.rounded()), hi = Int(range.max.rounded())
        return lo == hi ? "~\(lo)m" : "~\(lo)–\(hi)m"
    }

    // MARK: - Release window (extended-release)

    private func releaseBlock(_ window: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Duration of action")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                Text(window)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
