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

    var body: some View {
        List {
            Group {
                banner
                howItWorksCard

                if rows.isEmpty, tolerance.incompleteDataSubstances.isEmpty {
                    emptyState
                } else {
                    ForEach(rows) { row in
                        Section { card(row) }
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
        .toolbar { tierMenu }
        // Lazy replay: the 90-day integration runs only while this tool is open, and re-runs when
        // the dose log or body weight changes — kept off the launch / dose-write hot path.
        .task(id: recomputeSignature) { await tolerance.recompute(from: entries) }
    }

    private var tier: UserProfile { profile.disclosureTier }

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

    // MARK: - Rows

    private struct Row: Identifiable {
        let snapshot: ClassTolerance
        let params: ReceptorClasses.Parameters
        var id: ReceptorClasses.ReceptorClass { snapshot.receptorClass }

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
                Text("Log doses of substances with receptor data and your predicted tolerance will appear here. Mechanisms you haven't engaged recently read as fully rested.")
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
                    Text("Logged, but missing the pharmacokinetics the model needs — so it's blind here, **not** \u{201C}rested\u{201D}. \(listPhrase(names)).")
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

            Text(lede(row))
                .font(.subheadline)

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
    }

    // MARK: - Lede

    private func lede(_ row: Row) -> LocalizedStringResource {
        let snapshot = row.snapshot
        switch snapshot.receptorClass {
        case .alpha2Agonist, .betaBlocker:
            return "Little tolerance builds — the thing to watch is stopping suddenly."
        case .serotonergicReleaser where snapshot.sSynthesis > 0.05:
            return "Suppresses the enzyme that makes serotonin, so recovery takes weeks, not days."
        default:
            break
        }
        switch bucket(snapshot.responseFraction) {
        case .rested: return "No tolerance — a normal dose lands as expected."
        case .mild: return "Mild tolerance — a normal dose lands a little weaker."
        case .moderate: return "Moderate tolerance — a normal dose does noticeably less."
        case .high: return "High tolerance — your usual dose does much less."
        case .veryHigh: return "Very high tolerance — your usual dose does little."
        }
    }

    // MARK: - Recovery chart (linear, gridded, starts at the current level, days)

    @ViewBuilder
    private func recoveryChart(_ row: Row) -> some View {
        // Skip when essentially rested (a flat line at the top) or when the recovery window is under a
        // couple of hours — too short to plot without a degenerate, repeated-tick axis.
        if row.snapshot.responseFraction < 0.97, recoveryWindowMinutes(row) >= 120 {
            let points = recoveryCurve(row)
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

    /// Forward-decay the engaged layers over `[0, W]` and convert each `S(t)` to a response fraction —
    /// the curve starts at the **current** level (t = 0) and rises toward 1.0 as tolerance relaxes.
    private func recoveryCurve(_ row: Row) -> [ChartPoint] {
        let snapshot = row.snapshot
        let params = row.params
        let occupancy = min(0.999_999, max(0, snapshot.representativeOccupancy))
        let ratio = occupancy / (1 - occupancy)
        let window = max(recoveryWindowMinutes(row), 1)
        let sampleCount = 24
        return (0 ..< sampleCount).map { index in
            let minutes = window * Double(index) / Double(sampleCount - 1)
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
        case rested, mild, moderate, high, veryHigh
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
