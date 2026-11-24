import SwiftData
import SwiftUI

/// The **Tolerance** tool (pharmacology axis). It replays the dose log through ``ToleranceStore`` and
/// renders **one card per mechanism class** (Opioids, Stimulants, Dissociatives, …), on the design
/// claim that tolerance is *per-mechanism*, never one universal "tolerance %", and never a
/// per-raw-receptor card.
///
/// ## Layout
/// The overview chart leads: every plotted mechanism's curve from now, with no further dosing, on one
/// time axis and one value axis (``ToleranceChartFrame``) that every card's chart shares. Below it, a
/// flat list of cards in one order, which the overview's key follows: safety-critical classes (opioid
/// reset-after-break, GABA dependence, the adrenergic discontinuation-rebound hosts) first, then the
/// rest by ``ClassTolerance/severity``. Classes that read near baseline fold into one line, and a
/// "Not modeled" section names logged substances the model can't score (missing PK), so a class never
/// silently reads "rested" (the heavy-kratom → "Opioids recovered" trap).
///
/// ## One visual language per card
/// A family-color dot + tier-aware class name with the modeled level beside it; the date the class
/// reads near baseline; contributor chips (Curious); the segmented bar or the effect ladder; the
/// recovery chart; and a trimmed one-sentence safety note where the class has one. The level is one
/// quantity everywhere: how much less a usual dose does than with no tolerance, in percent.
struct ToleranceToolView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var entries: [DoseEntry]
    @Query(sort: \DailyDoseItem.sortOrder) private var medItems: [DailyDoseItem]

    @State private var tolerance = ToleranceStore.shared
    @State private var profile = UserProfileStore.shared

    /// What sits **below** the always-on combined recovery chart — mechanism cards or per-substance
    /// rows. Chosen from the toolbar menu; the combined chart shows in both.
    @State private var detailMode: ToleranceDetailMode = .perReceptor

    /// Per-substance rows whose full dose history is expanded (keyed by logged substance name).
    @State private var expandedSubstances: Set<String> = []

    /// The replay has run for the log on screen, so an empty result is the model's answer.
    @State private var hasReplayed = false

    var body: some View {
        let rows = rows
        let plotted = rows.filter { $0.snapshot.severity > Self.minimumPlottedSeverity }
        let projections = tolerance.projections
        let frame = ToleranceChartFrame(rows: plotted, projections: projections)
        let series = plotted.map { ToleranceRecoverySeries(row: $0, tier: tier, frame: frame, projection: projections[$0.id]) }
        let nearBaseline = nearBaselineItems
        List {
            Group {
                if rows.isEmpty, nearBaseline.isEmpty, tolerance.incompleteDataSubstances.isEmpty {
                    if hasReplayed || entries.isEmpty {
                        ToleranceEmptyState(hasEntries: !entries.isEmpty)
                    }
                } else {
                    // The combined recovery chart is the always-on hero; the detail below it is what
                    // the options menu switches.
                    if !series.isEmpty {
                        ToleranceCombinedRecoverySection(series: series, frame: frame)
                    }
                    switch detailMode {
                    case .perReceptor:
                        ForEach(rows) { row in
                            Section {
                                ToleranceCard(
                                    row: row, tier: tier,
                                    series: series.first { $0.id == row.id }, frame: frame,
                                )
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
                        ToleranceNearBaselineSection(items: nearBaseline)
                    case .perSubstance:
                        TolerancePerSubstanceSection(
                            groups: substanceGroups,
                            tier: tier,
                            projections: tolerance.perSubstanceProjections,
                            isReplayRunning: tolerance.perSubstanceStates.isEmpty && !tolerance.states.isEmpty,
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
        // Lazy replay: the year-long integration runs only while this tool is open, and re-runs when
        // the dose log or body weight changes — kept off the launch / dose-write hot path. The schedule
        // signature is in the id too, so editing a My Meds item refreshes the projection (the inner
        // `recompute` no-ops when only the schedule changed).
        .task(id: "\(recomputeSignature)|\(scheduleSignature)") {
            await tolerance.recompute(from: entries)
            hasReplayed = true
            await tolerance.recomputeProjections(from: entries, scheduledMeds: scheduledMeds)
        }
        // The per-substance "alone" replay is heavier still (one replay per substance), so it runs only
        // once the per-substance view is actually selected — the default per-mechanism view never pays.
        // Its projections follow, seeded from the alone snapshot it just filled.
        .task(id: perSubstanceTaskID) {
            guard detailMode == .perSubstance else { return }
            await tolerance.recomputePerSubstance(from: entries)
            await tolerance.recomputeProjections(from: entries, scheduledMeds: scheduledMeds)
        }
        #if DEBUG
        .task { detailMode = ScreenshotTour.takeStagedChart(\.toleranceMode) ?? detailMode }
        #endif
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

    /// The scheduled My Meds the projection replays forward: items that are not as-needed and whose
    /// amount converts to milligrams (a non-mass unit like IU can't drive an occupancy curve). There is
    /// no archived flag — an item removed from My Meds is deleted, so presence here *is* "active".
    private var scheduledMeds: [ToleranceStore.ScheduledMedSnapshot] {
        medItems.compactMap(ToleranceStore.scheduledMed(from:))
    }

    /// Changes when a My Meds schedule edit would change the projection, so the replay task re-runs.
    private var scheduleSignature: String {
        scheduledMeds.map {
            "\($0.substance):\($0.doseMg):\($0.frequency.rawValue):\($0.intervalDays):\($0.frequencyDays):\($0.reminderTimesMinutes):\($0.startDate.timeIntervalSinceReferenceDate)"
        }.joined(separator: "|")
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
    /// by severity. A safety-critical class with a note to carry is shown even when its right-shift is
    /// negligible (the adrenergic rebound hosts) so its discontinuation warning is never dropped.
    private var rows: [ToleranceRow] {
        let all = allRows.filter(\.earnsCard)
        let critical = all.filter(\.isSafetyCritical).sorted { $0.snapshot.severity > $1.snapshot.severity }
        let rest = all.filter { !$0.isSafetyCritical }.sorted { $0.snapshot.severity > $1.snapshot.severity }
        return critical + rest
    }

    private var allRows: [ToleranceRow] {
        tolerance.states.values.map { snapshot in
            ToleranceRow(snapshot: snapshot, params: ReceptorClasses.parameters(for: snapshot.receptorClass))
        }
    }

    /// The classes without a card that still read above zero, highest first, each as its name and level
    /// ("Adenosine (caffeine) 4%"): the near-baseline line's content.
    private var nearBaselineItems: [String] {
        allRows
            .filter { !$0.earnsCard && $0.snapshot.severity >= ToleranceRow.minimumListedSeverity }
            .sorted { $0.snapshot.severity > $1.snapshot.severity }
            .map { row in
                let name = String(localized: toleranceClassName(row.snapshot.receptorClass, tier: tier))
                return "\(name) \(tolerancePercentText(row.snapshot.severity * 100))"
            }
    }

    /// Lowest level a card's class is plotted at: under it the line would lie on the axis.
    private static let minimumPlottedSeverity = 0.03

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
