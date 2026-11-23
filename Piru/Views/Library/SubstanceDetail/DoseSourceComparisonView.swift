import SwiftUI

/// Every source's dose ladder for one route, on one scale, and every source's
/// duration phases.
///
/// The dose card resolves a single ladder by source priority and shows one set of
/// numbers, which hides how far the sources spread. Here each source gets a row:
/// its tiers as a bar on a scale all the rows share, and the figures under a
/// legend that names each tier's color. Durations spread the same way, so each
/// source's phases sit on a line under its figures; a source with durations and
/// no ladder gets a row of its own below.
///
/// Reached by tapping the source line under the dose card. Read-only: changing
/// which source wins is a global preference (Settings → Source Priority), and
/// silently rewriting it from a substance screen would change every other
/// substance too.
struct DoseSourceComparisonView: View {
    let substanceName: String
    let route: RouteOfAdministration
    let accent: Color

    @State private var ladders: [SubstanceStore.SourceDoseLadder] = []
    @State private var durations: [SourceDurationProfile] = []
    @Environment(\.appNavigator) private var navigator

    /// Share of the bar kept past the largest figure, so the open-ended Heavy
    /// tier that starts there still has a span to be drawn in.
    private static let heavyHeadroom = 0.12

    /// Where every bar ends: the largest number any source names, plus the Heavy
    /// headroom. One scale for all rows — the whole point is that the bars are
    /// comparable.
    private var scaleMax: Double {
        let values = ladders.flatMap { ladder -> [Double] in
            let d = ladder.doses
            return [
                d.threshold,
                d.light?.upperBound,
                d.common?.upperBound,
                d.strong?.upperBound,
                d.heavy,
            ].compactMap(\.self)
        }
        return max(values.max() ?? 1, 0.0001) / (1 - Self.heavyHeadroom)
    }

    /// The unit every ladder shares, or nil when the sources state different ones.
    private var sharedUnit: String? {
        let units = Set(ladders.map(\.unit))
        return units.count == 1 ? units.first : nil
    }

    var body: some View {
        NavigationStack {
            List {
                if !ladders.isEmpty { doseSection }
                durationSection
                Section {
                    Button {
                        navigator.present(.sourcePriority)
                    } label: {
                        Label("Source Priority", systemImage: "list.number")
                    }
                }
            }
            .navigationTitle(Text("Sources"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        navigator.dismiss()
                    }
                }
            }
        }
        .task(id: substanceName) {
            ladders = SubstanceStore.shared.doseLadders(forSubstanceName: substanceName, route: route)
            durations = SubstanceStore.shared.durationProfiles(forSubstanceName: substanceName, route: route)
        }
    }

    private var doseSection: some View {
        Section {
            DoseTierLegend()
            ForEach(ladders) { ladder in
                LadderRow(
                    ladder: ladder,
                    duration: durations.first { $0.sourceSlug == ladder.sourceSlug }?.duration,
                    scaleMax: scaleMax,
                    accent: accent,
                    showsUnit: sharedUnit == nil,
                )
            }
        } header: {
            if let sharedUnit {
                Text("\(route.localizedName) · \(sharedUnit) · \(ladders.count) sources")
            } else {
                Text("\(route.localizedName) · \(ladders.count) sources")
            }
        } footer: {
            // This footer says how to read the bars and nothing else. Do not add
            // a sentence explaining why the ladders differ — nothing in the
            // data records who a source measured or what for, so any such
            // reason is invented. "These sources disagree" is equally
            // unsupported: for many substances the ladders above are
            // identical. The reader can see the numbers.
            Text(
                "Every bar is drawn on the same scale. Piru shows the source you rank highest.",
                comment: "Dose source comparison footer",
            )
        }
    }

    /// Sources that state durations for this route but no dose ladder: their
    /// phases have no ladder row to sit under, so they get rows of their own.
    private var durationOnly: [SourceDurationProfile] {
        let withLadder = Set(ladders.map(\.sourceSlug))
        return durations.filter { !withLadder.contains($0.sourceSlug) }
    }

    @ViewBuilder
    private var durationSection: some View {
        if !durationOnly.isEmpty {
            Section {
                ForEach(durationOnly) { profile in
                    DurationSourceRow(profile: profile, accent: accent)
                }
            } header: {
                Text("Duration")
            }
        }
    }
}

/// One source's phases on a line, each phase it states named before its span:
/// "Onset 20–70m · Peak 2–3.5h · Total 3–6h". A phase the source leaves out is
/// left out here too.
private struct DurationPhaseLine: View {
    let duration: DurationProfile

    static func parts(_ duration: DurationProfile) -> [String] {
        let phases = DosePhase.allCases.compactMap { phase in
            phase.range(in: duration).map { "\(String(localized: phase.name)) \($0.compactString)" }
        }
        let total = duration.total.map { "\(String(localized: "Total")) \($0.compactString)" }
        return phases + [total].compactMap(\.self)
    }

    var body: some View {
        Text(verbatim: Self.parts(duration).joined(separator: " · "))
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The five tiers a ladder names, in order, and how one ladder states each.
private enum DoseTierColumn {
    static let tiers: [DoseLevel] = [.threshold, .light, .common, .strong, .heavy]

    /// A tier as the source gives it: a single figure for the open-ended ends, a
    /// range for the three between, nil where the source says nothing.
    static func text(for tier: DoseLevel, in doses: DoseRange) -> String? {
        func range(_ r: ClosedRange<Double>?) -> String? {
            r.map { "\($0.lowerBound.doseFormatted)–\($0.upperBound.doseFormatted)" }
        }
        return switch tier {
        case .sub: nil
        case .threshold: doses.threshold?.doseFormatted
        case .light: range(doses.light)
        case .common: range(doses.common)
        case .strong: range(doses.strong)
        case .heavy: doses.heavy.map { "\($0.doseFormatted)+" }
        }
    }
}

/// Five equal columns, one per tier. The legend and every source row lay their
/// cells out through this, so a number always sits under its tier's name.
private struct DoseTierColumns<Cell: View>: View {
    @ViewBuilder let cell: (DoseLevel) -> Cell

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            ForEach(DoseTierColumn.tiers, id: \.self) { tier in
                cell(tier).frame(maxWidth: .infinity)
            }
        }
    }
}

/// Which color is which tier: a swatch over each tier's name, in ladder order.
private struct DoseTierLegend: View {
    var body: some View {
        DoseTierColumns { tier in
            VStack(spacing: Spacing.xs) {
                Capsule()
                    .fill(tier.swiftUIColor)
                    .frame(height: 4)
                Text(tier.displayName)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityHidden(true)
    }
}

/// One source: its name, the five tiers drawn as a stacked bar on the shared
/// scale, each tier's figures under the legend's matching column, and the
/// durations the same source states for the route.
private struct LadderRow: View {
    let ladder: SubstanceStore.SourceDoseLadder
    /// This source's phases for the route; nil when it states none.
    let duration: DurationProfile?
    let scaleMax: Double
    let accent: Color
    /// Set when the sources state different units, so each row has to name its own.
    let showsUnit: Bool

    /// Tier spans as `(startFraction, endFraction, color)` on the shared scale.
    /// A tier a source didn't supply simply contributes nothing, so a sparse
    /// ladder reads as sparse rather than as a different shape.
    private var segments: [(start: Double, end: Double, color: Color)] {
        let d = ladder.doses
        var out: [(Double, Double, Color)] = []
        func add(_ lower: Double?, _ upper: Double?, _ tier: DoseLevel) {
            guard let lower, let upper, upper > lower else { return }
            out.append((lower / scaleMax, upper / scaleMax, tier.swiftUIColor))
        }
        if let t = d.threshold, let lightLower = d.light?.lowerBound ?? d.common?.lowerBound {
            add(t, max(lightLower, t), .threshold)
        }
        add(d.light?.lowerBound, d.light?.upperBound, .light)
        add(d.common?.lowerBound, d.common?.upperBound, .common)
        add(d.strong?.lowerBound, d.strong?.upperBound, .strong)
        if let heavy = d.heavy {
            add(heavy, scaleMax, .heavy)
        }
        return out
    }

    private static let barHeight: CGFloat = 10

    /// Tiers meet edge to edge, so only the ladder's two outer ends are rounded;
    /// every joint between tiers is square.
    private func segmentShape(at index: Int) -> UnevenRoundedRectangle {
        let radius = Self.barHeight / 2
        return UnevenRoundedRectangle(
            topLeadingRadius: index == 0 ? radius : 0,
            bottomLeadingRadius: index == 0 ? radius : 0,
            bottomTrailingRadius: index == segments.count - 1 ? radius : 0,
            topTrailingRadius: index == segments.count - 1 ? radius : 0,
        )
    }

    private var displayName: String {
        SourceNameLine.displayName(forSlug: ladder.sourceSlug)
    }

    /// "Threshold 5, Light 5–15, …" — the row's figures, spoken with their tiers.
    private var spokenLadder: String {
        DoseTierColumn.tiers.compactMap { tier in
            DoseTierColumn.text(for: tier, in: ladder.doses).map { "\(String(localized: tier.displayName)) \($0)" }
        }
        .joined(separator: ", ") + " \(ladder.unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                SourceNameLine(name: displayName, isActive: ladder.isActive, accent: accent)
                Spacer(minLength: 8)
                if showsUnit {
                    Text(verbatim: ladder.unit)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.platformTertiarySystemFill)
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        segmentShape(at: index)
                            .fill(segment.color)
                            .frame(width: max(2, geo.size.width * (segment.end - segment.start)))
                            .offset(x: geo.size.width * segment.start)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: Self.barHeight)

            DoseTierColumns { tier in
                Text(verbatim: DoseTierColumn.text(for: tier, in: ladder.doses) ?? "—")
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            if let duration {
                DurationPhaseLine(duration: duration)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(displayName))
        .accessibilityValue(Text(verbatim: spokenRow))
    }

    private var spokenRow: String {
        guard let duration else { return spokenLadder }
        return ([spokenLadder] + DurationPhaseLine.parts(duration)).joined(separator: ", ")
    }
}

/// A source's name, with the "In use" badge on the one the card shows.
private struct SourceNameLine: View {
    let name: String
    let isActive: Bool
    let accent: Color

    /// The source's human name, not its slug — the same resolution the
    /// attribution rows use, so "psychonautwiki" reads as "PsychonautWiki".
    static func displayName(forSlug slug: String) -> String {
        AppSources.slugToName[slug] ?? SubstanceStore.shared.sourceDisplayName(forSlug: slug)
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(name)
                .sectionLabel()
            if isActive {
                Text("In use", comment: "Badge on the source currently supplying the dose ladder")
                    .font(.caption2.weight(.bold))
                    .textCase(CapsuleChipSize.compact.wordCase)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7).padding(.vertical, Spacing.xxs)
                    .background(accent.opacity(Theme.Opacity.tint), in: skinChipShape())
            }
        }
    }
}

/// A source with durations and no dose ladder: its name and its phase line.
private struct DurationSourceRow: View {
    let profile: SourceDurationProfile
    let accent: Color

    private var displayName: String {
        SourceNameLine.displayName(forSlug: profile.sourceSlug)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SourceNameLine(name: displayName, isActive: profile.isActive, accent: accent)
            DurationPhaseLine(duration: profile.duration)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(displayName))
        .accessibilityValue(Text(verbatim: DurationPhaseLine.parts(profile.duration).joined(separator: ", ")))
    }
}
