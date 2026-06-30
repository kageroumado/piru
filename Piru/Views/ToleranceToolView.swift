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

    /// How the engaged mechanisms are laid out — the choice surfaced by the **View as** switcher.
    @State private var viewMode: ToleranceViewMode = .cards

    /// Drives the **View as** thumbnail popover anchored on the toolbar button.
    @State private var showsViewAsPopover = false

    var body: some View {
        List {
            Group {
                banner
                howItWorksCard

                if rows.isEmpty, tolerance.incompleteDataSubstances.isEmpty {
                    emptyState
                } else {
                    switch viewMode {
                    case .cards:
                        ForEach(rows) { row in
                            Section { card(row) }
                        }
                    case .recovery:
                        combinedRecoverySection
                    }
                    incompleteDataSection
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appNavigationBar("Tolerance")
        .toolbar {
            viewAsMenu
            tierMenu
        }
        // Lazy replay: the 90-day integration runs only while this tool is open, and re-runs when
        // the dose log or body weight changes — kept off the launch / dose-write hot path.
        .task(id: recomputeSignature) { await tolerance.recompute(from: entries) }
    }

    private var tier: UserProfile {
        profile.disclosureTier
    }

    // MARK: - Recompute trigger

    private var recomputeSignature: String {
        "\(entries.count)|\(entries.first?.timestamp.timeIntervalSince1970 ?? 0)|\(profile.effectiveWeightKg)"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var tierMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Detail level", selection: tierBinding) {
                    ForEach(UserProfile.allCases) { option in
                        Label(option.displayName, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: tier.icon)
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Detail level")
        }
    }

    private var tierBinding: Binding<UserProfile> {
        Binding(get: { tier }, set: { profile.setDisclosureTier($0) })
    }

    /// The **View as** layout switcher — a button showing the current mode's glyph that opens a
    /// thumbnail popover (one drawn preview per layout). Sits leading of the tier menu.
    @ToolbarContentBuilder
    private var viewAsMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showsViewAsPopover = true
            } label: {
                Image(systemName: viewMode.icon)
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("View as")
            .popover(isPresented: $showsViewAsPopover) {
                ViewAsSwitcher(selection: $viewMode) { showsViewAsPopover = false }
                    .presentationCompactAdaptation(.popover)
            }
        }
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

    /// Flat, safety-first ordering: the safety-critical classes (sorted by severity) lead, then the rest
    /// by severity. A safety-critical class is shown even when its right-shift is negligible (the
    /// adrenergic rebound hosts) so its discontinuation warning is never dropped.
    private var rows: [Row] {
        let all = tolerance.states.values.compactMap { snapshot -> Row? in
            let params = ReceptorClasses.parameters(for: snapshot.receptorClass)
            let row = Row(snapshot: snapshot, params: params)
            guard snapshot.severity > 0.03 || row.isSafetyCritical else { return nil }
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

            gauge(row)

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
                    Text(name)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(familyColor(row).opacity(0.14), in: Capsule())
                        .foregroundStyle(familyColor(row))
                }
            }
        }
    }

    // MARK: - Gauge (how much of a normal dose you'd still feel)

    private func gauge(_ row: Row) -> some View {
        let lit = max(0, min(5, Int((row.snapshot.responseFraction * 5).rounded(.up))))
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ForEach(0 ..< 5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index < lit ? familyColor(row) : Color.secondary.opacity(0.18))
                        .frame(height: 8)
                }
            }
            if tier != .casual {
                HStack {
                    Text("high tolerance")
                    Spacer()
                    Text("no tolerance")
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
        // Skip when essentially rested (a flat line at the top) or when the recovery window is under a
        // couple of hours — too short to plot without a degenerate, repeated-tick axis.
        if row.snapshot.responseFraction < 0.97, recoveryWindowMinutes(row) >= 120 {
            let points = recoveryCurve(row, overMinutes: recoveryWindowMinutes(row))
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Days", point.day),
                            y: .value("Sensitivity", point.percent),
                        )
                        .foregroundStyle(familyColor(row))
                        .interpolationMethod(.monotone)
                    }
                    if let start = points.first {
                        PointMark(
                            x: .value("Days", start.day),
                            y: .value("Sensitivity", start.percent),
                        )
                        .foregroundStyle(familyColor(row))
                        .symbolSize(45)
                    }
                }
                .chartYScale(domain: 0 ... 100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let percent = value.as(Int.self) {
                                Text("\(percent)%")
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
                .frame(height: 70)

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

    /// Forward-decay the engaged layers over `[0, window]` and convert each `S(t)` to a response
    /// fraction — the curve starts at the **current** level (t = 0) and rises toward 1.0 as tolerance
    /// relaxes. Shared by the per-card chart (its own recovery window) and the combined chart (a
    /// shared window across mechanisms), so the sampling math lives in exactly one place.
    private func recoveryCurve(_ row: Row, overMinutes window: Double, sampleCount: Int = 24) -> [ChartPoint] {
        let snapshot = row.snapshot
        let params = row.params
        let occupancy = min(0.999_999, max(0, snapshot.representativeOccupancy))
        let ratio = occupancy / (1 - occupancy)
        let span = max(window, 1)
        return (0 ..< sampleCount).map { index in
            let minutes = span * Double(index) / Double(sampleCount - 1)
            let shift = exp(
                snapshot.sAcute * exp(-minutes / params.tauAcuteMinutes)
                    + snapshot.sAdaptive * exp(-minutes / params.tauAdaptiveMinutes)
                    + snapshot.sDeep * exp(-minutes / params.tauDeepMinutes)
                    + snapshot.sSynthesis * exp(-minutes / params.tauSynthesisMinutes),
            )
            let responseFraction = (ratio + 1) / (ratio + shift)
            return ChartPoint(id: index, day: minutes / 1_440, percent: max(0, min(100, responseFraction * 100)))
        }
    }

    private func xAxisDays(_ row: Row) -> [Double] {
        // The real recovery window (the chart only renders for windows ≥ 2 h, so this is > 0).
        let windowDays = recoveryWindowMinutes(row) / 1_440
        return [0, windowDays * 0.25, windowDays * 0.5, windowDays * 0.75, windowDays]
    }

    private func chartCaption(_ row: Row) -> LocalizedStringResource {
        let minutes = max(recoveryMinutes(row, toResponseFraction: 0.9) ?? 0, 0)
        let phrase = durationPhrase(minutes: minutes)
        if row.snapshot.sDeep > 0.05 {
            return "Recovers to about 90% in \(phrase) if you stop now, and fully over months."
        }
        return "Recovers to about 90% in \(phrase) if you stop now."
    }

    /// Recovery window `W` (minutes) for the chart's X axis — time for sensitivity to climb back to
    /// ~95% if dosing stops now, capped at 180 days so the deep months-scale tail stays readable.
    private func recoveryWindowMinutes(_ row: Row) -> Double {
        let minutes = recoveryMinutes(row, toResponseFraction: 0.95) ?? 0
        return min(max(minutes, 0), 180 * 1_440)
    }

    /// Minutes for the total right-shift `S` to decay to the value where ``ClassTolerance/responseFraction``
    /// reaches `target` if dosing stops now (solving `(r+1)/(r+S) = target`). All four layers (acute,
    /// adaptive, deep, synthesis) decay on their own time-constants.
    private func recoveryMinutes(_ row: Row, toResponseFraction target: Double) -> Double? {
        let snapshot = row.snapshot
        let occupancy = min(0.999_999, max(0, snapshot.representativeOccupancy))
        let ratio = occupancy / (1 - occupancy)
        let targetShift = max(1, (ratio + 1) / target - ratio)
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

        if snapshot.safetyEndpointKind == .cardiovascular, snapshot.responseFraction < 0.85 {
            add("The high fades with tolerance, but the load on your heart and blood pressure doesn't.")
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

    /// A coarse, days-only X-axis tick label — compact enough for the 70 pt chart (the load-bearing
    /// recovery copy is the textual caption below the chart, not these ticks).
    private func axisDayLabel(days: Double) -> String {
        let value = max(0, days)
        if value <= 0 { return String(localized: "now") }
        if value < 1 { return String(localized: "\(max(1, Int((value * 24).rounded())))h") }
        if value >= 60 { return String(localized: "\(Int((value / 30).rounded()))mo") }
        if value >= 14 { return String(localized: "\(Int((value / 7).rounded()))wk") }
        return String(localized: "\(Int(value.rounded()))d")
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

    // MARK: - Combined recovery chart (.recovery mode)

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
            let recoveryMinutesTo90 = max(recoveryMinutes(row, toResponseFraction: 0.9) ?? 0, 0)
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
            ? "Each line is a mechanism recovering if you stop now — a steeper climb means a faster reset. Showing the first 60 days."
            : "Each line is a mechanism recovering — a steeper climb means a faster reset."
    }

    // MARK: - View mode

    /// The two ways to read the tool: per-mechanism **cards**, or every mechanism on one shared
    /// **recovery** axis. Each mode carries its own toolbar glyph and the title/subtitle the **View as**
    /// switcher shows.
    enum ToleranceViewMode: CaseIterable, Identifiable {
        case cards
        case recovery

        var id: Self {
            self
        }

        var icon: String {
            switch self {
            case .cards: "square.stack"
            case .recovery: "chart.line.uptrend.xyaxis"
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .cards: "Cards"
            case .recovery: "Recovery chart"
            }
        }

        var subtitle: LocalizedStringResource {
            switch self {
            case .cards: "One card per mechanism"
            case .recovery: "All mechanisms, one axis"
            }
        }
    }

    // MARK: - View-as switcher (thumbnail popover)

    /// The Apple-style layout picker shown in the **View as** popover: one row per ``ToleranceViewMode``
    /// with a drawn thumbnail, title + subtitle, and a checkmark on the active row.
    private struct ViewAsSwitcher: View {
        @Binding var selection: ToleranceViewMode
        let onSelect: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                ForEach(ToleranceViewMode.allCases) { mode in
                    Button {
                        selection = mode
                        onSelect()
                    } label: {
                        row(for: mode)
                    }
                    .buttonStyle(.plain)

                    if mode != ToleranceViewMode.allCases.last {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .padding(.vertical, 6)
            .frame(width: 270)
        }

        private func row(for mode: ToleranceViewMode) -> some View {
            HStack(spacing: 12) {
                ViewModeThumbnail(mode: mode)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(selection == mode ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
    }

    /// A ~46×34 drawn preview of a layout (no image assets): stacked rounded rects for **cards**, two
    /// rising polylines for the **recovery** chart.
    private struct ViewModeThumbnail: View {
        let mode: ToleranceViewMode

        var body: some View {
            RoundedRectangle(cornerRadius: 7)
                .fill(Theme.inputBackground)
                .frame(width: 46, height: 34)
                .overlay { content }
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.secondary.opacity(0.16))
                }
        }

        @ViewBuilder
        private var content: some View {
            switch mode {
            case .cards: cardsPreview
            case .recovery: recoveryPreview
            }
        }

        private var cardsPreview: some View {
            VStack(spacing: 3) {
                ForEach(0 ..< 3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent.opacity(0.55))
                        .frame(height: 5)
                }
            }
            .padding(.horizontal, 8)
        }

        private var recoveryPreview: some View {
            Canvas { context, canvasSize in
                let bottom = canvasSize.height - 5
                let right = canvasSize.width - 5
                stroke(
                    in: context,
                    from: CGPoint(x: 5, y: bottom),
                    control: CGPoint(x: canvasSize.width * 0.45, y: bottom - 3),
                    to: CGPoint(x: right, y: 7),
                    color: .orange,
                )
                stroke(
                    in: context,
                    from: CGPoint(x: 5, y: bottom),
                    control: CGPoint(x: canvasSize.width * 0.55, y: 8),
                    to: CGPoint(x: right, y: 4),
                    color: Color(red: 0.56, green: 0.27, blue: 0.79),
                )
            }
            .padding(3)
        }

        private func stroke(
            in context: GraphicsContext,
            from start: CGPoint,
            control: CGPoint,
            to end: CGPoint,
            color: Color,
        ) {
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            context.stroke(path, with: .color(color), lineWidth: 1.7)
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
                        y: .value("Sensitivity", point.percent),
                        series: .value("Mechanism", item.legendKey),
                    )
                    .foregroundStyle(item.color)
                    .interpolationMethod(.monotone)
                }
                if let start = item.points.first {
                    PointMark(
                        x: .value("Days", start.day),
                        y: .value("Sensitivity", start.percent),
                    )
                    .foregroundStyle(item.color)
                    .symbolSize(40)
                }
            }
            .chartYScale(domain: 0 ... 100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Int.self) {
                            Text("\(percent)%")
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
