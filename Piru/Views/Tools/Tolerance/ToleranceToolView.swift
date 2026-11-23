import SwiftData
import SwiftUI

/// The **Tolerance** tool (pharmacology axis). It replays the dose log through ``ToleranceStore`` and
/// renders **one card per mechanism class** (Opioids, Stimulants, Dissociatives, …), on the design
/// claim that tolerance is *per-mechanism*, never one universal "tolerance %", and never a
/// per-raw-receptor card.
///
/// ## Layout (Stage H)
/// A single flat list of cards — no "Needs attention"/"Active" headers. Safety-critical classes (opioid
/// reset-after-break, GABA dependence, the adrenergic discontinuation-rebound hosts) sort to the top,
/// then the rest by ``ClassTolerance/severity``. A "Can't predict yet" section surfaces logged
/// substances the model can't score (missing PK), so a class never silently reads "rested" (the
/// heavy-kratom → "Opioids recovered" trap).
///
/// ## One visual language per card
/// A family-color dot + tier-aware class name + a tolerance-level capsule; a five-segment gauge of how
/// much of a normal dose you'd still feel; a one-sentence lede; a linear recovery chart (sensitivity vs
/// days, starting at the current level); and a trimmed one-sentence safety note where the class has one.
/// Every series is named by its plain class name; ``UserProfile`` adds the receptor to each card's title
/// (Curious) along with contributor chips. The section subviews live alongside this file.
struct ToleranceToolView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var entries: [DoseEntry]

    @State private var tolerance = ToleranceStore.shared
    @State private var profile = UserProfileStore.shared

    /// What sits **below** the always-on combined recovery chart — mechanism cards or per-substance
    /// rows. Chosen from the toolbar menu; the combined chart shows in both.
    @State private var detailMode: ToleranceDetailMode = .perReceptor

    /// Per-substance rows whose full dose history is expanded (keyed by logged substance name).
    @State private var expandedSubstances: Set<String> = []

    var body: some View {
        List {
            Group {
                if rows.isEmpty, tolerance.incompleteDataSubstances.isEmpty {
                    ToleranceEmptyState()
                } else {
                    // The combined recovery chart is the always-on hero — a small card that fits in
                    // either mode; the detail below it is what the options menu switches.
                    ToleranceCombinedRecoverySection(
                        series: recoverySeries(),
                        axisDays: sharedAxisDays,
                        windowDays: sharedRecoveryWindowMinutes / 1_440,
                    )
                    switch detailMode {
                    case .perReceptor:
                        ForEach(rows) { row in
                            Section {
                                ToleranceCard(row: row, tier: tier)
                                // Effect-selective classes (GABA, α2δ) link out to the receptor/subtype
                                // explanation rather than carrying the education on the card itself.
                                if !row.snapshot.effectShifts.isEmpty {
                                    NavigationLink {
                                        ToleranceExplainerView()
                                    } label: {
                                        Label("Why these effects differ", systemImage: "questionmark.circle")
                                            .font(.subheadline)
                                    }
                                }
                                if row.snapshot.receptorClass == .gaba {
                                    GABALoadingCard(
                                        entries: entries,
                                        contributors: row.snapshot.contributors,
                                        color: row.familyColor,
                                    )
                                }
                            }
                        }
                    case .perSubstance:
                        TolerancePerSubstanceSection(
                            groups: substanceGroups,
                            isReplayRunning: tolerance.perSubstanceStates.isEmpty && !rows.isEmpty,
                            expandedSubstances: $expandedSubstances,
                        )
                    }
                    ToleranceIncompleteDataSection(names: tolerance.incompleteDataSubstances)
                }
                ToleranceHowItWorksCard()
            }
            .listRowBackground(CardBackground())
        }
        .insetGroupedListStyle()
        .themedPage()
        .appNavigationBar("Modeled Tolerance", showsOverflow: false)
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

    private var recomputeSignature: String {
        // The log revision catches edits to existing doses, which count + newest
        // timestamp alone would miss.
        "\(DoseLogService.shared.revision)|\(entries.count)|\(profile.effectiveWeightKg)"
    }

    // MARK: - Toolbar

    /// One menu, the glyph the other Insights screens use for theirs: what the list below the chart shows,
    /// and the app-wide detail level, each a named row showing its current value.
    @ToolbarContentBuilder
    private var optionsButton: some ToolbarContent {
        ToolbarItem(placement: .platformTopBarTrailing) {
            Menu {
                Picker("Show", selection: $detailMode) {
                    ForEach(ToleranceDetailMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                Picker("Detail Level", selection: tierBinding) {
                    ForEach(UserProfile.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
            } label: {
                Label("Display Options", systemImage: "line.3.horizontal.decrease")
            }
        }
    }

    private var tierBinding: Binding<UserProfile> {
        Binding(get: { tier }, set: { profile.setDisclosureTier($0) })
    }

    // MARK: - Rows (per-mechanism)

    /// Flat, safety-first ordering: the safety-critical classes (sorted by severity) lead, then the rest
    /// by severity. A safety-critical class is shown even when its right-shift is negligible (the
    /// adrenergic rebound hosts) so its discontinuation warning is never dropped.
    private var rows: [ToleranceRow] {
        let all = tolerance.states.values.compactMap { snapshot -> ToleranceRow? in
            let params = ReceptorClasses.parameters(for: snapshot.receptorClass)
            let row = ToleranceRow(snapshot: snapshot, params: params)
            guard snapshot.severity > ToleranceRow.minimumCardSeverity || row.isSafetyCritical else { return nil }
            return row
        }
        let critical = all.filter(\.isSafetyCritical).sorted { $0.snapshot.severity > $1.snapshot.severity }
        let rest = all.filter { !$0.isSafetyCritical }.sorted { $0.snapshot.severity > $1.snapshot.severity }
        return critical + rest
    }

    // MARK: - Per-substance groups

    /// Group the dose log by substance and attach each to **all** the mechanisms it drives — using the
    /// substance's **alone** tolerance (its own doses replayed in isolation), so a card shows *that
    /// substance's own contribution*, not the joint class number that amphetamine would dominate. Ordered
    /// most-toleranced first.
    private var substanceGroups: [ToleranceSubstanceGroup] {
        // Bucket every logged dose under its substance (entries arrive most-recent-first).
        var dosesByName: [String: [DoseEntry]] = [:]
        for entry in entries {
            dosesByName[entry.substance, default: []].append(entry)
        }

        return tolerance.perSubstanceStates.compactMap { name, classStates -> ToleranceSubstanceGroup? in
            let doses = dosesByName[name] ?? []
            let classes = classStates.values.sorted { $0.severity > $1.severity }
            guard !doses.isEmpty, !classes.isEmpty else { return nil }
            return ToleranceSubstanceGroup(
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

    // MARK: - Combined recovery chart data

    /// Mechanisms worth plotting on the shared axis: meaningfully toleranced (same `severity > 0.03`
    /// gate as the cards, so a class can never be a card yet missing from the chart), sorted by severity
    /// so the deepest reset is read first. Rested mechanisms would be flat lines pinned to the top —
    /// clutter — so they're omitted.
    private var recoveryRows: [ToleranceRow] {
        rows.filter { $0.snapshot.severity > 0.03 }
            .sorted { $0.snapshot.severity > $1.snapshot.severity }
    }

    /// The shared X window (minutes) — the widest per-row recovery window, capped at 60 days: past that
    /// a deep tail is a flat line, and the chart pans sideways in three-week pages anyway.
    private var sharedRecoveryWindowMinutes: Double {
        let widest = recoveryRows.map(\.recoveryWindowMinutes).max() ?? 0
        return min(max(widest, Self.minimumSharedWindowMinutes), Self.maximumSharedWindowMinutes)
    }

    private static let maximumSharedWindowMinutes: Double = 60 * 1_440
    private static let minimumSharedWindowMinutes: Double = 120

    private func recoverySeries() -> [ToleranceRecoverySeries] {
        let window = sharedRecoveryWindowMinutes
        // One sample per day of a long window, so a three-week page still bends.
        let sampleCount = max(28, Int(window / 1_440) + 1)
        return recoveryRows.map { row in
            ToleranceRecoverySeries(
                id: row.snapshot.receptorClass,
                legendKey: String(reflecting: row.snapshot.receptorClass),
                name: row.snapshot.receptorClass.casualName,
                color: row.familyColor,
                points: row.recoveryCurve(overMinutes: window, sampleCount: sampleCount),
            )
        }
    }

    /// Day ticks across the shared window — `now` at the origin, then four evenly-spaced gridlines to
    /// the window edge, or one a week once the window is long enough to pan.
    private var sharedAxisDays: [Double] {
        let windowDays = sharedRecoveryWindowMinutes / 1_440
        if windowDays > ToleranceCombinedRecoveryChart.visibleDays * 1.05 {
            return Array(stride(from: 0, through: windowDays, by: 7))
        }
        return [0, windowDays * 0.25, windowDays * 0.5, windowDays * 0.75, windowDays]
    }
}

// MARK: - Family color (SwiftUI-only — kept out of the pure ReceptorClasses table)

extension ReceptorClasses.ReceptorClass {
    /// The card's identity color for this mechanism family — the dot, gauge fill, capsule tint, and
    /// recovery line. The color identifies the *class*; the level is carried by the bar's fill, never by
    /// a red/green severity ramp. Lives here (not in `ReceptorClasses`) so the engine stays free of a
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
        case .alpha2Delta: Color(red: 0.40, green: 0.60, blue: 0.80)
        case .unknown: .gray
        }
    }
}
