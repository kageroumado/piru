import SwiftUI

/// The redesigned Dose & Duration card (proto10): a big selected-tier readout, a
/// **tier disc strip** whose discs grow and warm across the five dose tiers
/// (sharing the intensity gauge's green→gold→red ramp so the strip and the dial
/// read on one scale), an **effect-over-time curve** for the route, and the
/// onset/peak/total figures beneath it.
///
/// This replaces the old label↔value text ladder + vertical duration list. It's
/// the single most-consulted thing on the screen, so it leads with the numbers a
/// user actually wants at a glance rather than a reference table.
struct DoseDurationCard: View {
    let route: RouteOfAdministration
    let unit: String
    let doses: DoseRange?
    let duration: DurationProfile?
    /// Long-acting release window (`DurationOfAction.formattedWindow`), if any —
    /// shown in place of the acute curve for extended-release compounds.
    var releaseWindow: String?
    /// Elemental mass fraction of the selected salt, shown as a small note.
    var elementalFraction: Double?
    var showsDoseLadder = true
    var showsDuration = true
    /// When `.recreational`, the ladder is badged as such. Set only for compounds
    /// that also have a clinical dose (see the caller) — elsewhere every ladder is
    /// recreational and saying so adds nothing.
    var regimeLabel: DoseContext = .unknown
    var accent: Color = Theme.accent
    /// Category used to shape the drawn curve, via
    /// ``DurationProfile/fillingMissingPhases(for:)``. `nil` draws the raw phases.
    ///
    /// The curve and the numeric trio deliberately read from *different* profiles.
    /// The trio is a reference table and must stay verbatim source data. The curve
    /// is a shape, and a source that publishes only `onset` and `total` gives it no
    /// shape at all — `phaseBoundaries` then sums the present phases and collapses
    /// a 12 h profile into a ~1 h spike that contradicts the "12 h" printed
    /// directly beneath it. The journal always filled those phases in; the card
    /// did not, so the same dose drew two different curves depending on which
    /// screen you were on. Measured against the bundled DB, 453 of 1397 resolved
    /// route-profiles diverged. Now both fill, and only the trio stays raw.
    var curveCategory: SubstanceCategory?

    /// Tier the user tapped in the strip, overriding the model's reference tier.
    /// Card-local and deliberately not persisted — it answers "what does Strong
    /// mean here?" in the moment, and should read as Common again next visit.
    @State private var tappedTierID: Int?

    private var hasDosage: Bool {
        showsDoseLadder && (doses?.hasAnyValue ?? false)
    }
    private var hasDuration: Bool {
        showsDuration && duration != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if hasDosage, let doses {
                doseBlock(doses)
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
    }

    // MARK: - Dose

    private func doseBlock(_ doses: DoseRange) -> some View {
        let tiers = DoseTierStripModel(doses: doses, unit: unit)
        // The strip's own reference tier (Common, or the nearest present one) is
        // the starting point; tapping a disc overrides it for this card only.
        let activeID = tappedTierID ?? tiers.selectedID
        return VStack(alignment: .leading, spacing: 14) {
            if let selected = tiers.tier(activeID) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selected.name)
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 8)
                    Text(selected.fullValue)
                        .font(.system(.title2, design: .rounded).weight(.heavy).monospacedDigit())
                }
                .accessibilityElement(children: .combine)
                // Without an identity the two Texts cross-fade into each other
                // on tap, which reads as a glitch rather than a value change.
                .id(activeID)
                .transition(.opacity)
            }

            DoseTierStrip(tiers: tiers, selectedID: activeID, accent: accent) { id in
                withAnimation(.snappy(duration: 0.18)) { tappedTierID = id }
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

            disclaimer(for: doses)
        }
    }

    /// Names the regime for a compound that has two of them, so a number is not
    /// mistaken for the clinical dose someone was prescribed.
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

    // MARK: - Duration (curve + trio)

    @ViewBuilder
    private func durationBlock(_ duration: DurationProfile) -> some View {
        // Curve from the filled profile, trio and disclosure from the raw one —
        // see `curveCategory`.
        let curveProfile = curveCategory.map { duration.fillingMissingPhases(for: $0) } ?? duration
        let boundaries = curveProfile.phaseBoundaries
        VStack(alignment: .leading, spacing: 12) {
            Text("Effect over time · \(route.localizedName)")
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)

            if DurationCurveView.canRender(boundaries) {
                DurationCurveView(boundaries: boundaries, accent: accent)
                    // Inset the plot so the curve's endpoints and the fill's
                    // baseline sit inside the straight edges — drawn to the full
                    // bounds they land in the corner radius and read as bleeding
                    // out of the card. The clip is the backstop.
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
                    .frame(height: 92)
                    .background(Color(.tertiarySystemFill), in: Self.curveShape)
                    .clipShape(Self.curveShape)
            }

            phaseTrio(duration)
            phaseDisclosure(duration)
        }
    }

    private static let curveShape = RoundedRectangle(cornerRadius: 12)

    /// Phases the trio can't show: come-up, offset, afterglow. The trio is the
    /// glance layer (onset · peak · total); this is the depth layer, collapsed.
    private func hasFoldedPhases(_ duration: DurationProfile) -> Bool {
        duration.comeup != nil || duration.offset != nil || duration.afterglow != nil
    }

    @ViewBuilder
    private func phaseDisclosure(_ duration: DurationProfile) -> some View {
        if hasFoldedPhases(duration) {
            DisclosureGroup {
                VStack(spacing: 8) {
                    DurationPhaseRows(duration: duration)
                }
                .padding(.top, 8)
            } label: {
                Text("All phases")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .tint(Theme.secondaryLabel)
        }
    }

    private func phaseTrio(_ duration: DurationProfile) -> some View {
        HStack(spacing: 0) {
            trioCell("Onset", duration.onset)
            trioDivider
            trioCell("Peak", duration.peak ?? duration.comeup)
            trioDivider
            trioCell("Total", duration.total ?? duration.offset)
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
}

// MARK: - Tier strip model

/// The five dose tiers resolved for display: a short value (unit stripped, for the
/// disc strip), a full value (with unit, for the big readout), the tier name, and
/// which tier is the "reference" (Common, or the nearest present tier).
struct DoseTierStripModel {
    struct Tier: Identifiable {
        let id: Int // 0 threshold … 4 heavy
        let name: LocalizedStringKey
        let shortValue: String?
        let fullValue: String?
    }

    let tiers: [Tier]
    let selectedID: Int

    private static let names: [LocalizedStringKey] = ["Threshold", "Light", "Common", "Strong", "Heavy"]

    init(doses: DoseRange, unit: String) {
        let full = EffectsIntensityModel.bandDoseText(from: doses, unit: unit)
        tiers = (0 ... 4).map { index in
            let value = full[index]
            return Tier(
                id: index,
                name: Self.names[index],
                shortValue: value.map { Self.stripUnit($0, unit: unit) },
                fullValue: value,
            )
        }
        // Reference tier: Common if present, else the nearest present tier to it.
        let present = tiers.filter { $0.fullValue != nil }.map(\.id)
        selectedID = present.contains(2) ? 2 : (present.min(by: { abs($0 - 2) < abs($1 - 2) }) ?? 2)
    }

    var selected: (name: LocalizedStringKey, fullValue: String)? {
        tier(selectedID)
    }

    /// The named tier, if it carries a value — a tier the source didn't supply
    /// has nothing to headline, so the caller keeps whatever it was showing.
    func tier(_ id: Int) -> (name: LocalizedStringKey, fullValue: String)? {
        guard let tier = tiers.first(where: { $0.id == id }), let value = tier.fullValue else { return nil }
        return (tier.name, value)
    }

    private static func stripUnit(_ text: String, unit: String) -> String {
        text.replacingOccurrences(of: " \(unit)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Tier disc strip

/// Five equal columns — a filled disc that grows and warms across the tiers, the
/// short value, and the uppercase tier name. The selected (reference) column is
/// tinted with the accent so it reads as "this is the number above."
struct DoseTierStrip: View {
    let tiers: DoseTierStripModel
    /// Which column reads as "this is the number above" — owned by the parent so
    /// tapping a disc can retarget the headline.
    var selectedID: Int?
    var accent: Color = Theme.accent
    /// Tapping a tier that has a value. Tiers the source left empty aren't
    /// selectable: there is no number to promote.
    var onSelect: ((Int) -> Void)?

    /// Disc diameters per tier — a single glyph family that grows threshold→heavy.
    private static let diameters: [CGFloat] = [7, 10, 13, 15, 18]
    /// The gauge's ramp, threshold gray → heavy red. One of three encodings of
    /// dose intensity that have been folded into the shared `dose` scale; this
    /// one's hues were the ones kept, since it was the most deliberately
    /// designed of the three.
    private static let colors: [Color] = [
        .Dose.Threshold.accent, .Dose.Light.accent, .Dose.Common.accent,
        .Dose.Strong.accent, .Dose.Heavy.accent,
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tiers.tiers) { tier in
                let isSelected = tier.id == (selectedID ?? tiers.selectedID)
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Self.colors[tier.id])
                            .frame(width: Self.diameters[tier.id], height: Self.diameters[tier.id])
                    }
                    .frame(height: 18)
                    Text(tier.shortValue ?? "—")
                        .font(.footnote.weight(isSelected ? .bold : .semibold).monospacedDigit())
                        .foregroundStyle(tier.shortValue == nil ? Theme.secondaryLabel : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(tier.name)
                        .font(.system(size: 8, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.3)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? accent.opacity(0.12) : Color(.tertiarySystemFill)),
                )
                // The value + name Texts combine into "Threshold, 30" without a
                // custom label (which would mint a generic "%@, %@" catalog key);
                // the selected tier reads as selected via the trait.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityAddTraits(tier.fullValue != nil ? .isButton : [])
                // `contentShape` so the whole column is the target, not just the
                // glyphs — and so the tap is consumed here rather than falling
                // through to the enclosing disclosure, which is what made tapping
                // a dose tier expand "All phases" instead.
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    guard tier.fullValue != nil else { return }
                    onSelect?(tier.id)
                }
            }
        }
    }
}
