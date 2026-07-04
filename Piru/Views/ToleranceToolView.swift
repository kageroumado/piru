import Charts
import SwiftData
import SwiftUI

/// The **Tolerance** tool (pharmacology axis). It replays the dose log through ``ToleranceStore`` and
/// renders **one card per mechanism class** (Opioids, Stimulants, Dissociatives, …) — the load-bearing
/// design claim that tolerance is *per-mechanism*, never one universal "tolerance %", and never a
/// per-raw-receptor card (see `Specs/tolerance-tool-audit-and-redesign.md`).
///
/// ## Layout (Stage H)
/// A single flat list of cards — no "Needs attention"/"Active" headers. Safety-critical classes (opioid
/// reset-after-break, GABA dependence, the adrenergic discontinuation-rebound hosts) sort to the top,
/// then the rest by ``ClassTolerance/severity``. A "Can't predict yet" section surfaces logged
/// substances the model can't score (missing PK), so a class never silently reads "rested" (the
/// heavy-kratom → "Opioids recovered" trap).
///
/// ## One visual language per card
/// A family-colour dot + tier-aware class name + a tolerance-level capsule; a five-segment gauge of how
/// much of a normal dose you'd still feel; a one-sentence lede; a linear recovery chart (sensitivity vs
/// days, starting at the current level); a trimmed one-sentence safety note where the class has one; and
/// — for the Pharma Nerd tier — confidence, the shift factor, and the engaged layers. Density scales
/// with ``UserProfile`` (Casual → Curious → Pharma Nerd).
struct ToleranceToolView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var entries: [DoseEntry]

    @State private var tolerance = ToleranceStore.shared
    @State private var profile = UserProfileStore.shared

    /// What sits **below** the always-on combined recovery chart — mechanism cards or per-substance
    /// rows. Chosen from the Mail-style options menu; the combined chart shows in both.
    @State private var detailMode: ToleranceDetailMode = .perReceptor

    /// Drives the Mail-style options popover anchored on the single toolbar button.
    @State private var showsOptions = false

    /// Per-substance rows whose full dose history is expanded (keyed by logged substance name).
    @State private var expandedSubstances: Set<String> = []

    var body: some View {
        List {
            Group {
                banner
                howItWorksCard

                if rows.isEmpty, tolerance.incompleteDataSubstances.isEmpty {
                    emptyState
                } else {
                    // The combined recovery chart is the always-on hero — a small card that fits in
                    // either mode; the detail below it is what the options menu switches.
                    combinedRecoverySection
                    switch detailMode {
                    case .perReceptor:
                        ForEach(rows) { row in
                            Section { card(row) }
                        }
                    case .perSubstance:
                        perSubstanceSection
                    }
                    incompleteDataSection
                }
            }
            .listRowBackground(CardBackground())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appNavigationBar("Tolerance", showsOverflow: false)
        .toolbar {
            optionsButton
        }
        // Lazy replay: the 90-day integration runs only while this tool is open, and re-runs when
        // the dose log or body weight changes — kept off the launch / dose-write hot path.
        .task(id: recomputeSignature) { await tolerance.recompute(from: entries) }
        // The per-substance "alone" replay is heavier still (one replay per substance), so it runs only
        // once the per-substance view is actually selected — the default per-mechanism view never pays.
        .task(id: perSubstanceTaskID) {
            guard detailMode == .perSubstance else { return }
            await tolerance.recomputePerSubstance(from: entries)
        }
    }

    /// Task id for the per-substance replay: recomputes when the log/weight changes *or* when the user
    /// switches into the per-substance view (so entering it triggers the first replay).
    private var perSubstanceTaskID: String {
        "\(detailMode == .perSubstance)|\(recomputeSignature)"
    }

    private var tier: UserProfile {
        profile.disclosureTier
    }

    // MARK: - Recompute trigger

    private var recomputeSignature: String {
        "\(entries.count)|\(entries.first?.timestamp.timeIntervalSince1970 ?? 0)|\(profile.effectiveWeightKg)"
    }

    // MARK: - Toolbar

    /// The single, Mail-style options button: one glyph opening a popover that carries both the
    /// display-mode thumbnail picker and the detail-tier list. Replaces the old pair of toolbar
    /// controls (View-as switcher + tier menu) and the app overflow menu (dropped here — Settings/Help
    /// are root-level, redundant on a pushed tool screen).
    @ToolbarContentBuilder
    private var optionsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showsOptions = true
            } label: {
                // The current tier's glyph, so the button both opens the menu and advertises the active
                // detail level (leaf / heart / atom) rather than a generic ellipsis.
                Image(systemName: tier.icon)
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Display options")
            .popover(isPresented: $showsOptions) {
                ToleranceOptionsMenu(mode: $detailMode, tier: tierBinding)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var tierBinding: Binding<UserProfile> {
        Binding(get: { tier }, set: { profile.setDisclosureTier($0) })
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let snapshot: ClassTolerance
        let params: ReceptorClasses.Parameters
        var id: ReceptorClasses.ReceptorClass {
            snapshot.receptorClass
        }

        /// Classes pinned to the top of the flat list — the reset-overdose, dependence-kindling, and
        /// adrenergic discontinuation-rebound hosts. They lead regardless of how faint the right-shift is.
        var isSafetyCritical: Bool {
            switch params.safetyAxis {
            case .resetOverdose, .dependenceKindling, .alpha2Rebound, .betaRebound: true
            default: false
            }
        }
    }

    /// Minimum severity for a non-safety class to earn a card — the "No tolerance" / "Mild" bucket
    /// boundary (``bucket(_:)``: rested at responseFraction ≥ 0.90 ⇒ severity ≤ 0.10). Below it a card
    /// would render while labelling itself "No tolerance" and quoting a "fades in under an hour"
    /// recovery, which is noise — it's how a drug with only trace activity at the class's target (e.g.
    /// amphetamine's weak SERT release) slipped into the chart. Safety-critical classes bypass it.
    private static let minimumCardSeverity = 0.10

    /// Flat, safety-first ordering: the safety-critical classes (sorted by severity) lead, then the rest
    /// by severity. A safety-critical class is shown even when its right-shift is negligible (the
    /// adrenergic rebound hosts) so its discontinuation warning is never dropped.
    private var rows: [Row] {
        let all = tolerance.states.values.compactMap { snapshot -> Row? in
            let params = ReceptorClasses.parameters(for: snapshot.receptorClass)
            let row = Row(snapshot: snapshot, params: params)
            guard snapshot.severity > Self.minimumCardSeverity || row.isSafetyCritical else { return nil }
            return row
        }
        let critical = all.filter(\.isSafetyCritical).sorted { $0.snapshot.severity > $1.snapshot.severity }
        let rest = all.filter { !$0.isSafetyCritical }.sorted { $0.snapshot.severity > $1.snapshot.severity }
        return critical + rest
    }

    // MARK: - Banner

    private var banner: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Predicted", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(bannerSubtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 4)
        }
    }

    /// Model + body-weight provenance folded into one sentence (the weight clause only when it's the
    /// population default, so a user who set their own weight doesn't see the nudge).
    private var bannerSubtitle: LocalizedStringResource {
        profile.isWeightEstimated
            ? "Model estimates from your dose log, assuming a \(Int(UserProfileStore.defaultWeightKg)) kg body weight — set yours in Settings."
            : "Model estimates from your dose log and your body weight."
    }

    private var howItWorksCard: some View {
        Section {
            NavigationLink {
                ToleranceExplainerView()
            } label: {
                Label("How tolerance works", systemImage: "book")
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Nothing to show yet", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                Text("Log a few doses and your predicted tolerance shows up here. Anything you haven't taken recently counts as no tolerance.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var incompleteDataSection: some View {
        let names = tolerance.incompleteDataSubstances
        if !names.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Can't predict yet", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                    Text("Logged, but missing the pharmacokinetics the model needs — so it's blind here, which is not the same as no tolerance. \(listPhrase(names)).")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Card

    private func card(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(row)

            if tier != .casual, !row.snapshot.contributors.isEmpty {
                contributorChips(row)
            }

            toleranceBar(row)

            if let lede = lede(row) {
                Text(lede)
                    .font(.subheadline)
            }

            recoveryChart(row)

            safetyNotes(row)

            if tier == .pharmaNerd {
                nerdFooter(row)
            }
        }
        .padding(.vertical, 6)
    }

    private func cardHeader(_ row: Row) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(familyColor(row))
                .frame(width: 9, height: 9)
            Text(className(for: row.snapshot.receptorClass))
                .font(.headline)
            Spacer(minLength: 8)
            Text("Predicted")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.14), in: Capsule())
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func contributorChips(_ row: Row) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(row.snapshot.contributors, id: \.self) { name in
                    Text(CustomSubstanceStore.shared.displayName(for: name))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(familyColor(row).opacity(0.14), in: Capsule())
                        .foregroundStyle(familyColor(row))
                }
            }
        }
    }

    // MARK: - Tolerance bar (segmented, part-to-whole: how toleranced you are, and from which layer)

    /// One coloured segment of the tolerance bar — a recovery layer's *attributed share* of the
    /// overall right-shift. `widthFraction` is already the fraction of the **full track** this band
    /// fills (overall severity × the band's ln-shift share), so the segments laid end-to-end fill the
    /// bar to the overall tolerance level and split it by where that tolerance comes from.
    private struct ToleranceBand: Identifiable {
        let id: Int
        let label: LocalizedStringResource
        let widthFraction: Double
        let color: Color
    }

    /// Decompose a class's tolerance into up to three timescale bands — **tachyphylaxis** (the acute
    /// same-session/same-day pool), **tolerance** (the days-scale adaptive baseline shift, plus the
    /// slow serotonin-synthesis pool for entactogens), and **deep** (months-scale entrenchment) —
    /// ordered fast → slow. Each band's width is the overall severity apportioned by its share of the
    /// summed ln-shift `ln S = Σ sₗ` (the additive latent behind the saturating gauge), so a faint
    /// contributor draws a faint sliver and the whole bar reads as the overall tolerance.
    private func bands(_ row: Row) -> [ToleranceBand] {
        let snapshot = row.snapshot
        let totalShift = snapshot.sAcute + snapshot.sAdaptive + snapshot.sDeep + snapshot.sSynthesis
        guard totalShift > 0 else { return [] }
        let severity = max(0, min(1, snapshot.severity))
        let family = familyColor(row)
        let raw: [(LocalizedStringResource, Double, Color)] = [
            ("Tachyphylaxis", snapshot.sAcute, family.opacity(0.5)),
            ("Tolerance", snapshot.sAdaptive + snapshot.sSynthesis, family.opacity(0.82)),
            ("Deep", snapshot.sDeep, family),
        ]
        return raw.enumerated().compactMap { index, band in
            let (label, shift, color) = band
            guard shift > 0 else { return nil }
            return ToleranceBand(id: index, label: label, widthFraction: severity * shift / totalShift, color: color)
        }
    }

    private func toleranceBar(_ row: Row) -> some View {
        let bandList = bands(row)
        let multiBand = bandList.count > 1
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    HStack(spacing: multiBand ? 1.5 : 0) {
                        ForEach(bandList) { band in
                            Rectangle()
                                .fill(band.color)
                                .frame(width: max(0, geo.size.width * band.widthFraction))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)

            if tier != .casual {
                HStack(spacing: 10) {
                    if multiBand {
                        ForEach(bandList) { band in
                            HStack(spacing: 4) {
                                Circle().fill(band.color).frame(width: 7, height: 7)
                                Text(band.label)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Text(toleranceWord(row.snapshot.responseFraction))
                        .foregroundStyle(familyColor(row))
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(toleranceWord(row.snapshot.responseFraction)))
    }

    // MARK: - Lede

    /// The card's one-line summary — **only** when it adds something the gauge doesn't already show.
    /// The plain level (mild / high / …) is read off the gauge, so a generic "Mild tolerance — your
    /// usual dose does a little less" would just restate it; those return `nil`. MDMA-type synthesis
    /// and the adrenergic rebound hosts carry real extra information, so they keep a line.
    private func lede(_ row: Row) -> LocalizedStringResource? {
        let snapshot = row.snapshot
        switch snapshot.receptorClass {
        case .alpha2Agonist, .betaBlocker:
            return "Little tolerance builds — the thing to watch is stopping suddenly."
        case .serotonergicReleaser where snapshot.sSynthesis > 0.05:
            return "Suppresses the enzyme that makes serotonin, so recovery takes weeks, not days."
        default:
            return nil
        }
    }

    /// The tolerance level in words — not shown as a card line (the gauge shows it), but used as the
    /// gauge's VoiceOver label so screen-reader users get the level without reading five bars.
    private func toleranceWord(_ responseFraction: Double) -> LocalizedStringResource {
        switch bucket(responseFraction) {
        case .rested: "No tolerance"
        case .mild: "Mild tolerance"
        case .moderate: "Moderate tolerance"
        case .high: "High tolerance"
        case .veryHigh: "Very high tolerance"
        }
    }

    // MARK: - Recovery chart (linear, gridded, starts at the current level, days)

    @ViewBuilder
    private func recoveryChart(_ row: Row) -> some View {
        // Skip when essentially rested (nothing to plot) or when the recovery window is under a couple
        // of hours — too short to plot without a degenerate, repeated-tick axis.
        if row.snapshot.severity > 0.03, recoveryWindowMinutes(row) >= 120 {
            let points = recoveryCurve(row, overMinutes: recoveryWindowMinutes(row))
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Days", point.day),
                            y: .value("Tolerance", point.percent),
                        )
                        .foregroundStyle(familyColor(row))
                        .interpolationMethod(.monotone)
                    }
                    if let start = points.first {
                        PointMark(
                            x: .value("Days", start.day),
                            y: .value("Tolerance", start.percent),
                        )
                        .foregroundStyle(familyColor(row))
                        .symbolSize(45)
                    }
                }
                .chartYScale(domain: 0 ... 100)
                .chartYAxis {
                    AxisMarks(values: [0, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let percent = value.as(Int.self) {
                                Text(percent >= 100 ? "high" : "low")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xAxisDays(row)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let days = value.as(Double.self) {
                                Text(axisDayLabel(days: days))
                            }
                        }
                    }
                }
                .frame(height: 92)

                Text(chartCaption(row))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    private struct ChartPoint: Identifiable {
        let id: Int
        let day: Double
        let percent: Double
    }

    /// Forward-decay the engaged layers over `[0, window]` and convert each `S(t)` to a **tolerance
    /// percentage** — the curve starts at the **current** tolerance (t = 0) and *descends* toward 0 as
    /// the layers relax, matching the bar's orientation (full = strong tolerance). Uses the same
    /// saturating ``PDModel/responseFraction`` with the class's mechanism-aware cap (§5 — ½ for
    /// release/reuptake proxies, uncapped for agonists) as the gauge, so the graph and the bar can never
    /// disagree — the old inline `0.999_999` clamp pinned high-occupancy stimulants
    /// at a flat 100% "sensitivity", reading as *no* tolerance while the bar showed moderate. Shared by
    /// the per-card chart and the combined chart, so the sampling math lives in exactly one place.
    private func recoveryCurve(_ row: Row, overMinutes window: Double, sampleCount: Int = 24) -> [ChartPoint] {
        let snapshot = row.snapshot
        let params = row.params
        let span = max(window, 1)
        return (0 ..< sampleCount).map { index in
            let minutes = span * Double(index) / Double(sampleCount - 1)
            let shift = exp(
                snapshot.sAcute * exp(-minutes / params.tauAcuteMinutes)
                    + snapshot.sAdaptive * exp(-minutes / params.tauAdaptiveMinutes)
                    + snapshot.sDeep * exp(-minutes / params.tauDeepMinutes)
                    + snapshot.sSynthesis * exp(-minutes / params.tauSynthesisMinutes),
            )
            let tolerance = 1 - PDModel.responseFraction(
                shiftFactor: shift, representativeOccupancy: snapshot.representativeOccupancy,
                occupancyCap: snapshot.receptorClass.gaugeOccupancyCap,
            )
            return ChartPoint(id: index, day: minutes / 1_440, percent: max(0, min(100, tolerance * 100)))
        }
    }

    private func xAxisDays(_ row: Row) -> [Double] {
        // The real recovery window (the chart only renders for windows ≥ 2 h, so this is > 0).
        let windowDays = recoveryWindowMinutes(row) / 1_440
        return [0, windowDays * 0.25, windowDays * 0.5, windowDays * 0.75, windowDays]
    }

    private func chartCaption(_ row: Row) -> LocalizedStringResource {
        let minutes = max(recoveryMinutes(row, toTolerance: 0.10) ?? 0, 0)
        let phrase = durationPhrase(minutes: minutes)
        if row.snapshot.sDeep > 0.05 {
            return "Most of it fades in \(phrase) if you stop now — the deep part takes months."
        }
        return "Most of it fades in \(phrase) if you stop now."
    }

    /// Recovery window `W` (minutes) for the chart's X axis — time for tolerance to fade to ~5% if
    /// dosing stops now, capped at 180 days so the deep months-scale tail stays readable.
    private func recoveryWindowMinutes(_ row: Row) -> Double {
        let minutes = recoveryMinutes(row, toTolerance: 0.05) ?? 0
        return min(max(minutes, 0), 180 * 1_440)
    }

    /// Minutes for **tolerance** to decay to `target` (∈ [0,1]) if dosing stops now. Tolerance is
    /// `1 − responseFraction`, so the target response fraction is `1 − target`; inverting the saturating
    /// gauge (with the class's mechanism-aware cap, exactly as ``PDModel/responseFraction``) gives the
    /// shift `S` at which that response is reached, then all four layers decay on their own time-constants
    /// to it. The cap must match the curve/bar or the axis span and the plotted line would disagree.
    private func recoveryMinutes(_ row: Row, toTolerance target: Double) -> Double? {
        let snapshot = row.snapshot
        // Match the gauge's mechanism-aware cap (§5): capped at ½ for release/reuptake proxies, uncapped
        // (just shy of 1 to avoid a divide-by-zero) for agonists — so the axis span never disagrees with
        // the plotted line or the bar.
        let cap = snapshot.receptorClass.gaugeOccupancyCap ?? 0.999_999
        let occupancy = min(cap, max(0, snapshot.representativeOccupancy))
        let ratio = occupancy / (1 - occupancy)
        let responseTarget = max(0.000_001, 1 - target)
        let targetShift = max(1, (ratio + 1) / responseTarget - ratio)
        let layers = [
            (s: snapshot.sAcute, tau: row.params.tauAcuteMinutes),
            (s: snapshot.sAdaptive, tau: row.params.tauAdaptiveMinutes),
            (s: snapshot.sDeep, tau: row.params.tauDeepMinutes),
            (s: snapshot.sSynthesis, tau: row.params.tauSynthesisMinutes),
        ]
        return PDModel.shiftDecayMinutes(layers: layers, toShift: targetShift)
    }

    // MARK: - Safety notes (one sentence each, trimmed)

    private struct SafetyNote: Identifiable {
        let id: Int
        let text: LocalizedStringResource
        let tint: Color
        let systemImage: String
    }

    @ViewBuilder
    private func safetyNotes(_ row: Row) -> some View {
        let notes = safetyNoteData(row)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notes) { note in
                    Label {
                        Text(note.text)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    } icon: {
                        Image(systemName: note.systemImage)
                            .foregroundStyle(note.tint)
                    }
                }
            }
        }
    }

    private func safetyNoteData(_ row: Row) -> [SafetyNote] {
        var notes: [SafetyNote] = []
        let snapshot = row.snapshot

        func add(
            _ text: LocalizedStringResource,
            tint: Color = .orange,
            image: String = "exclamationmark.triangle.fill",
        ) {
            notes.append(SafetyNote(id: notes.count, text: text, tint: tint, systemImage: image))
        }

        // Reset-overdose / dependence warnings are about losing built-up tolerance, so they only make
        // sense once there is some — suppress them on a rested card. Adrenergic rebound is the whole
        // point of those (faint-tolerance) cards, so it always shows.
        let hasTolerance = bucket(snapshot.responseFraction) != .rested
        switch row.params.safetyAxis {
        case .resetOverdose:
            if hasTolerance {
                add("After a break, tolerance drops fast — a dose that felt fine before can stop your breathing. Restart low.")
            }
        case .dependenceKindling:
            if hasTolerance {
                add("Heavy regular use builds dependence — stopping abruptly can be dangerous. Taper.")
            }
        case .alpha2Rebound:
            add("Don't stop α₂-agonists cold after regular use — blood pressure can rebound. Taper.")
        case .betaRebound:
            add("Don't stop beta-blockers cold after regular use — heart rate and blood pressure can rebound. Taper.")
        default:
            break
        }

        // §6: stimulant cardiovascular is two mechanisms. Lead with the in-session hazard (safety-critical,
        // always) — the acute pressor doesn't tolerize, so chasing a faded high stacks fresh spikes. The
        // chronic line is calm and shows only once the chronic (adaptive) endpoint is actually engaged, so
        // it never implies dangerous cumulative load for a light/therapeutic user.
        if snapshot.safetyEndpointKind == .cardiovascular {
            add("Within a session the high fades faster than the strain on your heart — chasing it with more stacks onto a blood-pressure spike that hasn't eased. Space your doses.")
            if let cardiovascular = snapshot.safetyShiftFactor, cardiovascular > 1.05 {
                add(
                    "With regular use, your resting heart rate and blood pressure tend to settle over weeks.",
                    tint: Theme.secondaryLabel, image: "clock.arrow.circlepath",
                )
            }
        }

        if tier != .casual, snapshot.sDeep > 0.05 {
            add(
                "Heavy chronic use has shifted your baseline; the deepest part recovers over months.",
                tint: Theme.secondaryLabel, image: "clock.arrow.circlepath",
            )
        }

        return notes
    }

    // MARK: - Pharma Nerd footer

    private func nerdFooter(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(confidenceAndShift(row))
            Text(engagedLayers(row))
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryLabel)
    }

    private func confidenceAndShift(_ row: Row) -> LocalizedStringResource {
        let shift = String(format: "%.1f", row.snapshot.shiftFactor)
        return "\(String(localized: row.snapshot.confidence.label)) · S ≈ \(shift)×"
    }

    private func engagedLayers(_ row: Row) -> LocalizedStringResource {
        let snapshot = row.snapshot
        var names: [String] = []
        if snapshot.sAcute > 0.01 { names.append(String(localized: "acute")) }
        if snapshot.sAdaptive > 0.01 { names.append(String(localized: "adaptive")) }
        if snapshot.sDeep > 0.01 { names.append(String(localized: "deep")) }
        if snapshot.sSynthesis > 0.01 { names.append(String(localized: "synthesis")) }
        let joined = names.isEmpty ? String(localized: "none") : ListFormatter.localizedString(byJoining: names)
        return "Engaged layers: \(joined)"
    }

    // MARK: - Tier-aware wording / colour

    private func className(for receptorClass: ReceptorClasses.ReceptorClass) -> LocalizedStringResource {
        switch tier {
        case .casual: receptorClass.casualName
        case .harmReduction: receptorClass.displayName
        case .pharmaNerd: receptorClass.scientificName
        }
    }

    private func familyColor(_ row: Row) -> Color {
        row.snapshot.receptorClass.familyColor
    }

    /// Five tolerance buckets keyed on the response fraction — drives both the capsule word and the
    /// generic lede.
    private enum ToleranceBucket {
        case rested
        case mild
        case moderate
        case high
        case veryHigh
    }

    private func bucket(_ responseFraction: Double) -> ToleranceBucket {
        switch responseFraction {
        case 0.90...: .rested
        case 0.70 ..< 0.90: .mild
        case 0.50 ..< 0.70: .moderate
        case 0.30 ..< 0.50: .high
        default: .veryHigh
        }
    }

    // MARK: - Formatting

    /// A compact X-axis tick label. Ticks sit at 0·W … 1·W in quarter-window steps, so a coarse
    /// (whole-hour / whole-day) unit collides on adjacent ticks for short windows — the "1h · 2h · 2h"
    /// bug. Each magnitude drops to the next-finer unit (minutes < 2 h, hours < 4 d, days < 4 wk) so
    /// neighbouring ticks always round apart; the load-bearing recovery copy is the caption below.
    private func axisDayLabel(days: Double) -> String {
        let value = max(0, days)
        if value <= 0 { return String(localized: "now") }
        let hours = value * 24
        if hours < 2 {
            let mins = max(5, Int((hours * 60 / 5).rounded()) * 5)
            return String(localized: "\(mins)m")
        }
        if value < 4 { return String(localized: "\(Int(hours.rounded()))h") }
        if value < 28 { return String(localized: "\(Int(value.rounded()))d") }
        if value < 120 { return String(localized: "\(Int((value / 7).rounded()))wk") }
        return String(localized: "\(Int((value / 30).rounded()))mo")
    }

    private func durationPhrase(minutes: Double) -> String {
        let hours = minutes / 60
        let days = hours / 24
        if days >= 60 { return String(localized: "~\(Int((days / 30).rounded())) months") }
        if days >= 14 { return String(localized: "~\(Int((days / 7).rounded())) weeks") }
        if days >= 1.5 { return String(localized: "~\(Int(days.rounded())) days") }
        if hours >= 1 { return String(localized: "~\(Int(hours.rounded())) hours") }
        return String(localized: "under an hour")
    }

    /// "A, B and C" style join for the contributor / incomplete-data lists.
    private func listPhrase(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names)
    }

    // MARK: - Per-substance rows

    /// One logged substance's tolerance readout: **every** mechanism class it drives (MDMA touches
    /// DAT/NET, SERT and 5-HT2A, each with its own level), highest-severity first, plus its dose
    /// history. Only substances the model actually scored appear — the "can't predict yet" set stays in
    /// ``incompleteDataSection``.
    private struct SubstanceGroup: Identifiable {
        let name: String
        let displayName: String
        let doses: [DoseEntry]
        /// The mechanism classes this substance contributes to, sorted by severity (worst first).
        let classes: [ClassTolerance]
        var id: String {
            name
        }

        /// The substance's worst mechanism — drives the leading dot's colour and the list ordering.
        var topSeverity: Double {
            classes.first?.severity ?? 0
        }
    }

    /// Group the dose log by substance and attach each to **all** the mechanisms it drives — using the
    /// substance's **alone** tolerance (its own doses replayed in isolation), so a card shows *that
    /// substance's own contribution*, not the joint class number that amphetamine would dominate. Ordered
    /// most-toleranced first.
    private var substanceGroups: [SubstanceGroup] {
        // Bucket every logged dose under its substance (entries arrive most-recent-first).
        var dosesByName: [String: [DoseEntry]] = [:]
        for entry in entries {
            dosesByName[entry.substance, default: []].append(entry)
        }

        return tolerance.perSubstanceStates.compactMap { name, classStates -> SubstanceGroup? in
            let doses = dosesByName[name] ?? []
            let classes = classStates.values.sorted { $0.severity > $1.severity }
            guard !doses.isEmpty, !classes.isEmpty else { return nil }
            return SubstanceGroup(
                name: name,
                displayName: CustomSubstanceStore.shared.displayName(for: name),
                doses: doses,
                classes: classes,
            )
        }
        .sorted { lhs, rhs in
            lhs.topSeverity != rhs.topSeverity
                ? lhs.topSeverity > rhs.topSeverity
                : (lhs.doses.first?.timestamp ?? .distantPast) > (rhs.doses.first?.timestamp ?? .distantPast)
        }
    }

    @ViewBuilder
    private var perSubstanceSection: some View {
        let groups = substanceGroups
        if groups.isEmpty {
            Section {
                if tolerance.perSubstanceStates.isEmpty, !rows.isEmpty {
                    // The per-substance replay is still running (first entry into this view).
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Calculating each substance's contribution…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Log a few doses and each substance's tolerance shows up here.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.vertical, 4)
                }
            }
        } else {
            Section {
                Label("Each card is that substance's own contribution. Mechanisms are shared, so your overall level (the chart above, or By mechanism) can be higher.", systemImage: "person.fill.viewfinder")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.vertical, 4)
            }
            ForEach(groups) { group in
                Section { substanceCard(group) }
            }
        }
    }

    private func substanceCard(_ group: SubstanceGroup) -> some View {
        let topColor = group.classes.first?.receptorClass.familyColor ?? .secondary
        let expanded = expandedSubstances.contains(group.name)
        let total = group.doses.count
        // Expanded view caps at the latest 20 — a heavy caffeine log runs to hundreds of rows, which
        // would bury the rest of the list.
        let cap = min(total, Self.expandedDoseLimit)
        let shown = expanded ? Array(group.doses.prefix(cap)) : Array(group.doses.prefix(3))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(topColor).frame(width: 9, height: 9)
                Text(group.displayName)
                    .font(.headline)
                Spacer(minLength: 8)
            }

            // Every mechanism this substance drives, each with its own level and family-coloured bar.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(group.classes) { snapshot in
                    mechanismRow(snapshot)
                }
            }

            Divider()

            VStack(spacing: 8) {
                ForEach(shown) { entry in
                    doseRow(entry)
                    if entry.id != shown.last?.id { Divider() }
                }
            }

            if total > 3 {
                Button {
                    toggleExpanded(group.name)
                } label: {
                    Text(collapsedLabel(total: total, expanded: expanded))
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
    }

    /// One mechanism line inside a per-substance card: the class name + its tolerance word, over a slim
    /// family-coloured level bar.
    private func mechanismRow(_ snapshot: ClassTolerance) -> some View {
        let color = snapshot.receptorClass.familyColor
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(className(for: snapshot.receptorClass))
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(toleranceWord(snapshot.responseFraction))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(color)
                        .frame(width: max(0, geo.size.width * min(1, max(0, snapshot.severity))))
                }
            }
            .frame(height: 7)
        }
    }

    /// One dose in a per-substance card — the Your-History row layout (amount + route on the left, the
    /// timestamp on the right) so the two screens read identically.
    private func doseRow(_ entry: DoseEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.amount.doseFormatted) \(entry.unit)")
                    .font(.subheadline)
                Text(entry.route.localizedName)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    /// Most doses shown when a per-substance card is expanded — enough to see the recent pattern
    /// without a hundreds-row wall.
    private static let expandedDoseLimit = 20

    /// The expand/collapse button's label: "Show less" when open, otherwise "Show all N doses" (when
    /// they all fit) or "Show 20 latest doses" (when the log is capped).
    private func collapsedLabel(total: Int, expanded: Bool) -> LocalizedStringResource {
        if expanded { return "Show less" }
        return total > Self.expandedDoseLimit
            ? "Show \(Self.expandedDoseLimit) latest doses"
            : "Show all \(total) doses"
    }

    private func toggleExpanded(_ name: String) {
        if expandedSubstances.contains(name) {
            expandedSubstances.remove(name)
        } else {
            expandedSubstances.insert(name)
        }
    }

    // MARK: - Combined recovery chart (always shown)

    /// One mechanism's recovery trajectory plus the legend metadata that names it.
    private struct RecoverySeries: Identifiable {
        let id: ReceptorClasses.ReceptorClass
        let legendKey: String
        let name: LocalizedStringResource
        let color: Color
        let points: [ChartPoint]
        let recoveryPhrase: String
        let severity: Double
    }

    /// Mechanisms worth plotting on the shared axis: meaningfully toleranced (same `severity > 0.03`
    /// gate as the cards, so a class can never be a card yet missing from the chart), sorted
    /// by severity so the deepest reset is read first. Rested mechanisms would be flat lines pinned to
    /// the top — clutter — so they're omitted.
    private var recoveryRows: [Row] {
        rows.filter { $0.snapshot.severity > 0.03 }
            .sorted { $0.snapshot.severity > $1.snapshot.severity }
    }

    /// The shared X window (minutes) — the widest per-row recovery window, capped at 60 days so a
    /// months-scale deep tail doesn't flatten the fast mechanisms into a single line at the bottom.
    private var sharedRecoveryWindowMinutes: Double {
        let widest = recoveryRows.map(recoveryWindowMinutes).max() ?? 0
        return min(max(widest, Self.minimumSharedWindowMinutes), Self.maximumSharedWindowMinutes)
    }

    private static let maximumSharedWindowMinutes: Double = 60 * 1_440
    private static let minimumSharedWindowMinutes: Double = 120

    /// True when at least one mechanism's natural recovery window exceeds the shared cap — the chart is
    /// then showing only the first 60 days, which the caption notes.
    private var recoveryWindowIsClipped: Bool {
        (recoveryRows.map(recoveryWindowMinutes).max() ?? 0) > Self.maximumSharedWindowMinutes
    }

    private func recoverySeries() -> [RecoverySeries] {
        let window = sharedRecoveryWindowMinutes
        return recoveryRows.map { row in
            let recoveryMinutesTo90 = max(recoveryMinutes(row, toTolerance: 0.10) ?? 0, 0)
            return RecoverySeries(
                id: row.snapshot.receptorClass,
                legendKey: String(reflecting: row.snapshot.receptorClass),
                name: className(for: row.snapshot.receptorClass),
                color: familyColor(row),
                points: recoveryCurve(row, overMinutes: window, sampleCount: 28),
                recoveryPhrase: durationPhrase(minutes: recoveryMinutesTo90),
                severity: row.snapshot.severity,
            )
        }
    }

    /// Linear day ticks across the shared window — `now` at the origin, four evenly-spaced gridlines to
    /// the window edge.
    private var sharedAxisDays: [Double] {
        let windowDays = sharedRecoveryWindowMinutes / 1_440
        return [0, windowDays * 0.25, windowDays * 0.5, windowDays * 0.75, windowDays]
    }

    private var combinedRecoverySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recovery if you stop now")
                    .font(.headline)

                let series = recoverySeries()
                if series.isEmpty {
                    Text("Everything's rested — nothing recovering right now.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                } else {
                    CombinedRecoveryChart(
                        series: series,
                        axisDays: sharedAxisDays,
                        dayLabel: { axisDayLabel(days: $0) },
                    )
                    recoveryLegend(series)
                    Text(combinedRecoveryCaption)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func recoveryLegend(_ series: [RecoverySeries]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(series) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 9, height: 9)
                    Text(item.name)
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 8)
                    // Already a resolved, localized phrase from `durationPhrase` — show verbatim so it
                    // isn't re-looked-up as a catalog key.
                    Text(verbatim: item.recoveryPhrase)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    private var combinedRecoveryCaption: LocalizedStringResource {
        recoveryWindowIsClipped
            ? "Each line is a mechanism's tolerance fading — a steeper drop means a faster reset. Showing the first 60 days."
            : "Each line is a mechanism's tolerance fading — a steeper drop means a faster reset."
    }

    // MARK: - Detail mode

    /// What the options menu shows **below** the always-on combined recovery chart: per-mechanism
    /// **cards** or per-substance **rows**. The combined chart shows in both; this only switches the
    /// detail. Each case carries the caption its thumbnail shows in the picker.
    enum ToleranceDetailMode: CaseIterable, Identifiable {
        case perReceptor
        case perSubstance

        var id: Self {
            self
        }

        var title: LocalizedStringResource {
            switch self {
            case .perReceptor: "By mechanism"
            case .perSubstance: "By substance"
            }
        }
    }

    // MARK: - Options menu (Mail-style popover)

    /// The single toolbar button's popover, modelled on Mail's view-options menu: a thumbnail picker
    /// for the display mode across the top (two line-art phones with a radio each), a divider, then the
    /// detail-tier checklist. Selecting keeps the popover open, so mode and tier can both be changed in
    /// one visit.
    private struct ToleranceOptionsMenu: View {
        @Binding var mode: ToleranceDetailMode
        @Binding var tier: UserProfile

        var body: some View {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(ToleranceDetailMode.allCases) { option in
                        modeColumn(option)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                Divider()

                VStack(spacing: 0) {
                    ForEach(UserProfile.allCases) { option in
                        Button {
                            tier = option
                        } label: {
                            tierRow(option)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: 280)
        }

        private func modeColumn(_ option: ToleranceDetailMode) -> some View {
            let selected = mode == option
            return Button {
                mode = option
            } label: {
                VStack(spacing: 8) {
                    PhoneThumbnail(mode: option, selected: selected)
                        .frame(width: 72, height: 148) // aspect 0.486 — the iPhone 17 bezel
                    Text(option.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    radio(selected: selected)
                        .frame(width: 22, height: 22)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(option.title))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }

        private func radio(selected: Bool) -> some View {
            ZStack {
                if selected {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
                }
            }
        }

        private func tierRow(_ option: UserProfile) -> some View {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(tier == option ? 1 : 0)
                    .frame(width: 16)
                Image(systemName: option.icon)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
                Text(option.displayName)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
    }

    /// A line-art iPhone silhouette drawn in a single colour (accent when selected, grey otherwise),
    /// its screen sketched with the mode — stacked cards for **By mechanism**, list rows for **By
    /// substance**. Proportions are taken from the Apple iPhone 17 bezel (aspect ≈ 0.485, continuous
    /// corners) so it reads as a phone rather than an arbitrary rectangle. No image assets.
    private struct PhoneThumbnail: View {
        let mode: ToleranceDetailMode
        let selected: Bool

        var body: some View {
            Canvas { context, size in
                let color: Color = selected ? Theme.accent : .secondary
                let line = max(1.6, size.width * 0.03)

                // Phone body — inset so the stroke sits fully inside the frame. Corner radius 0.16·width
                // (the measured iPhone 17 corner extent, continuous), not a pill.
                let body = CGRect(x: line, y: line, width: size.width - line * 2, height: size.height - line * 2)
                let bodyPath = Path(roundedRect: body, cornerRadius: size.width * 0.16, style: .continuous)
                context.stroke(bodyPath, with: .color(color), lineWidth: line)

                // The Dynamic Island floats inside the screen near the top (a display cutout, not part of
                // the frame): centre ≈ 0.05·height down, a ~3.4:1 pill — the measured iPhone 17 geometry.
                let islandW = body.width * 0.32
                let islandH = body.height * 0.045
                let island = CGRect(
                    x: body.midX - islandW / 2,
                    y: body.minY + body.height * 0.052 - islandH / 2,
                    width: islandW, height: islandH,
                )
                context.fill(Path(roundedRect: island, cornerRadius: islandH / 2), with: .color(color))

                // Content sits below the island with even side margins and a matching bottom inset, so it
                // never touches the frame — and both modes share the same top edge.
                let sideInset = body.width * 0.13
                let contentTop = island.maxY + body.height * 0.04
                let content = CGRect(
                    x: body.minX + sideInset,
                    y: contentTop,
                    width: body.width - sideInset * 2,
                    height: body.maxY - body.height * 0.06 - contentTop,
                )
                let tint = color.opacity(0.5)
                switch mode {
                case .perReceptor: drawCards(context, in: content, color: tint)
                case .perSubstance: drawRows(context, in: content, color: tint)
                }
            }
        }

        /// Three stacked card bars.
        private func drawCards(_ context: GraphicsContext, in rect: CGRect, color: Color) {
            let count = 3
            let gap = rect.height * 0.14
            let h = (rect.height - gap * CGFloat(count - 1)) / CGFloat(count) * 0.6
            for i in 0 ..< count {
                let y = rect.minY + CGFloat(i) * (h + gap)
                let bar = CGRect(x: rect.minX, y: y, width: rect.width, height: h)
                context.fill(Path(roundedRect: bar, cornerRadius: h * 0.28), with: .color(color))
            }
        }

        /// Four list rows: a leading dot + a line each. Rows are laid top-down with the same gap model as
        /// the cards, so the first row begins at `rect.minY` — matching the cards' top padding.
        private func drawRows(_ context: GraphicsContext, in rect: CGRect, color: Color) {
            let count = 4
            let gap = rect.height * 0.12
            let rowH = (rect.height - gap * CGFloat(count - 1)) / CGFloat(count)
            let dot = min(rect.width * 0.15, rowH)
            let lineH = max(2, rowH * 0.42)
            for i in 0 ..< count {
                let cy = rect.minY + CGFloat(i) * (rowH + gap) + rowH / 2
                context.fill(Path(ellipseIn: CGRect(x: rect.minX, y: cy - dot / 2, width: dot, height: dot)), with: .color(color))
                let lineRect = CGRect(x: rect.minX + dot * 1.6, y: cy - lineH / 2, width: rect.width - dot * 1.6, height: lineH)
                context.fill(Path(roundedRect: lineRect, cornerRadius: lineH / 2), with: .color(color))
            }
        }
    }

    // MARK: - Combined recovery chart view

    /// The shared-axis recovery chart: one family-coloured ``LineMark`` series per mechanism, each
    /// anchored by a "now" ``PointMark`` at its current level, on a linear days X axis (gridlines) and a
    /// 0–100% Y axis (gridlines at 0/50/100). Family colours are applied per series with a manual legend
    /// rendered by the parent, so each line keeps its exact family hue.
    private struct CombinedRecoveryChart: View {
        let series: [RecoverySeries]
        let axisDays: [Double]
        let dayLabel: (Double) -> String

        var body: some View {
            Chart(series) { item in
                ForEach(item.points) { point in
                    LineMark(
                        x: .value("Days", point.day),
                        y: .value("Tolerance", point.percent),
                        series: .value("Mechanism", item.legendKey),
                    )
                    .foregroundStyle(item.color)
                    .interpolationMethod(.monotone)
                }
                if let start = item.points.first {
                    PointMark(
                        x: .value("Days", start.day),
                        y: .value("Tolerance", start.percent),
                    )
                    .foregroundStyle(item.color)
                    .symbolSize(40)
                }
            }
            .chartYScale(domain: 0 ... 100)
            .chartYAxis {
                AxisMarks(values: [0, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Int.self) {
                            Text(percent >= 100 ? "high" : "low")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: axisDays) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let days = value.as(Double.self) {
                            Text(dayLabel(days))
                        }
                    }
                }
            }
            .frame(height: 160)
        }
    }
}

// MARK: - Family colour (SwiftUI-only — kept out of the pure ReceptorClasses table)

extension ReceptorClasses.ReceptorClass {
    /// The card's identity colour for this mechanism family — the dot, gauge fill, capsule tint, and
    /// recovery line. The colour identifies the *class*; the tolerance level is carried by the word, not
    /// by a red/green severity ramp. Lives here (not in `ReceptorClasses`) so the engine stays free of a
    /// SwiftUI import.
    var familyColor: Color {
        switch self {
        case .psychedelic5HT2A: Color(red: 0.56, green: 0.27, blue: 0.79)
        case .muOpioid: .red
        case .catecholamineStimulant: .orange
        case .serotonergicReleaser: Color(red: 1.0, green: 0.18, blue: 0.33)
        case .gaba: .blue
        case .nmdaAntagonist: .cyan
        case .cannabinoidCB1: .green
        case .adenosine: Color(red: 0.64, green: 0.52, blue: 0.37)
        case .nicotinic: Color(red: 0.60, green: 0.55, blue: 0.35)
        case .alpha2Agonist, .betaBlocker: Color(red: 0.88, green: 0.32, blue: 0.29)
        case .unknown: .gray
        }
    }
}
