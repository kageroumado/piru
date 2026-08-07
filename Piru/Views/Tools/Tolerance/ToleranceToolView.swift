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
/// A family-color dot + tier-aware class name + a tolerance-level capsule; a five-segment gauge of how
/// much of a normal dose you'd still feel; a one-sentence lede; a linear recovery chart (sensitivity vs
/// days, starting at the current level); a trimmed one-sentence safety note where the class has one; and
/// — for the Pharma Nerd tier — confidence, the shift factor, and the engaged layers. Density scales
/// with ``UserProfile`` (Casual → Curious → Pharma Nerd). The section subviews live alongside this file.
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
                ToleranceBanner(isWeightEstimated: profile.isWeightEstimated)
                ToleranceHowItWorksCard()

                if rows.isEmpty, tolerance.incompleteDataSubstances.isEmpty {
                    ToleranceEmptyState()
                } else {
                    // The combined recovery chart is the always-on hero — a small card that fits in
                    // either mode; the detail below it is what the options menu switches.
                    ToleranceCombinedRecoverySection(
                        series: recoverySeries(),
                        axisDays: sharedAxisDays,
                        isClipped: recoveryWindowIsClipped,
                    )
                    switch detailMode {
                    case .perReceptor:
                        ForEach(rows) { row in
                            Section {
                                ToleranceCard(row: row, tier: tier)
                                if row.snapshot.receptorClass == .gaba {
                                    if row.snapshot.chronicExposure > 0.10 {
                                        NavigationLink {
                                            WithdrawalReferenceView(
                                                contributors: row.snapshot.contributors,
                                                lastDoseDate: lastDoseDate(for: row.snapshot.contributors),
                                                effectiveHalfLifeMinutes: effectiveHalfLives(for: row.snapshot.contributors),
                                            )
                                        } label: {
                                            Label("If you stop: withdrawal timing", systemImage: "calendar.badge.clock")
                                                .font(.subheadline)
                                        }
                                    }
                                    NavigationLink {
                                        InterventionLedgerView()
                                    } label: {
                                        Label("Discontinuation evidence", systemImage: "list.bullet.clipboard")
                                            .font(.subheadline)
                                    }
                                }
                            }
                        }
                    case .perSubstance:
                        TolerancePerSubstanceSection(
                            groups: substanceGroups,
                            tier: tier,
                            isReplayRunning: tolerance.perSubstanceStates.isEmpty && !rows.isEmpty,
                            expandedSubstances: $expandedSubstances,
                        )
                    }
                    ToleranceIncompleteDataSection(names: tolerance.incompleteDataSubstances)
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

    /// The most recent logged dose among a class's contributors — feeds the withdrawal card's "since
    /// your last dose" marker. `entries` is already sorted most-recent-first, so the first match wins.
    private func lastDoseDate(for contributors: [String]) -> Date? {
        let names = Set(contributors)
        return entries.first { names.contains($0.substance) }?.timestamp
    }

    /// Metabolite-extended half-life (minutes) per GABA contributor — the slowest of the parent's own
    /// half-life and its foldable active metabolites' (K.5). This is what lets the withdrawal card
    /// classify a prodrug benzo (clorazepate, ketazolam → nordazepam) as long-acting via its
    /// metabolite tail rather than its short parent (I.full).
    private func effectiveHalfLives(for contributors: [String]) -> [String: Double] {
        var out: [String: Double] = [:]
        for name in contributors {
            let params = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: name)
            let parent = params.halfLifeMinutes ?? HalfLifeDatabase.halfLife(for: name)
            let slowestMetabolite = params.metabolites.filter(\.canFold).map(\.halfLifeMinutes).max()
            if let effective = [parent, slowestMetabolite].compactMap(\.self).max() {
                out[name] = effective
            }
        }
        return out
    }

    private var recomputeSignature: String {
        "\(entries.count)|\(entries.first?.timestamp.timeIntervalSince1970 ?? 0)|\(profile.effectiveWeightKg)"
    }

    // MARK: - Toolbar

    /// The single, Mail-style options button: one glyph opening a popover that carries both the
    /// display-mode thumbnail picker and the detail-tier list.
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

    /// The shared X window (minutes) — the widest per-row recovery window, capped at 60 days so a
    /// months-scale deep tail doesn't flatten the fast mechanisms into a single line at the bottom.
    private var sharedRecoveryWindowMinutes: Double {
        let widest = recoveryRows.map(\.recoveryWindowMinutes).max() ?? 0
        return min(max(widest, Self.minimumSharedWindowMinutes), Self.maximumSharedWindowMinutes)
    }

    private static let maximumSharedWindowMinutes: Double = 60 * 1_440
    private static let minimumSharedWindowMinutes: Double = 120

    /// True when at least one mechanism's natural recovery window exceeds the shared cap — the chart is
    /// then showing only the first 60 days, which the caption notes.
    private var recoveryWindowIsClipped: Bool {
        (recoveryRows.map(\.recoveryWindowMinutes).max() ?? 0) > Self.maximumSharedWindowMinutes
    }

    private func recoverySeries() -> [ToleranceRecoverySeries] {
        let window = sharedRecoveryWindowMinutes
        return recoveryRows.map { row in
            let recoveryMinutesTo90 = max(row.recoveryMinutes(toTolerance: 0.10) ?? 0, 0)
            return ToleranceRecoverySeries(
                id: row.snapshot.receptorClass,
                legendKey: String(reflecting: row.snapshot.receptorClass),
                name: toleranceClassName(row.snapshot.receptorClass, tier: tier),
                color: row.familyColor,
                points: row.recoveryCurve(overMinutes: window, sampleCount: 28),
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
}

// MARK: - Family color (SwiftUI-only — kept out of the pure ReceptorClasses table)

extension ReceptorClasses.ReceptorClass {
    /// The card's identity color for this mechanism family — the dot, gauge fill, capsule tint, and
    /// recovery line. The color identifies the *class*; the tolerance level is carried by the word, not
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
        case .alpha2Delta: Color(red: 0.40, green: 0.60, blue: 0.80)
        case .unknown: .gray
        }
    }
}
