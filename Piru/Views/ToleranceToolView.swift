import SwiftData
import SwiftUI

/// The **Tolerance** tool (pharmacology axis). It replays the dose log through ``ToleranceStore`` and
/// renders **one card per mechanism class** (Opioids, Stimulants, Dissociatives, …) — the load-bearing
/// design claim that tolerance is *per-mechanism*, never one universal "tolerance %", and never a
/// per-raw-receptor card (see `Specs/tolerance-tool-audit-and-redesign.md`).
///
/// ## Layout
/// - **Needs attention** — safety-critical classes (opioid reset-after-break, GABA dependence) pinned
///   to the top regardless of magnitude.
/// - **Active tolerance** — the remaining engaged classes, ranked by a single ``ClassTolerance/severity``.
/// - **Can't predict yet** — logged substances the model can't score for missing PK, surfaced honestly
///   so a class never silently reads "rested" (the heavy-kratom → "Opioids recovered" trap).
///
/// ## One visual language
/// Each card carries a single state word (Rested → Depleted) + a warm "how affected" bar (more fill =
/// more affected, always), with the meaningful numbers (sensitivity / load, recovery, within-session
/// redose) as separate labelled facets. Every figure is badged ``ConfidenceTier`` — "predicted (model,
/// confidence)", never "measured" — and gated on body weight.
struct ToleranceToolView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var entries: [DoseEntry]

    @State private var tolerance = ToleranceStore.shared
    @State private var profile = UserProfileStore.shared

    var body: some View {
        List {
            Group {
                aboutSection

                let groups = groupedRows
                if groups.attention.isEmpty, groups.active.isEmpty, tolerance.incompleteDataSubstances.isEmpty {
                    emptyState
                } else {
                    section(title: "Needs attention", systemImage: "exclamationmark.triangle.fill", tint: .orange, rows: groups.attention)
                    section(title: "Active tolerance", systemImage: nil, tint: .secondary, rows: groups.active)
                    incompleteDataSection
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appNavigationBar("Tolerance")
        // Lazy replay: the 18-month integration runs only while this tool is open, and re-runs when
        // the dose log or body weight changes — kept off the launch / dose-write hot path.
        .task(id: recomputeSignature) { await tolerance.recompute(from: entries) }
    }

    // MARK: - Recompute trigger

    private var recomputeSignature: String {
        "\(entries.count)|\(entries.first?.timestamp.timeIntervalSince1970 ?? 0)|\(profile.effectiveWeightKg)"
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let snapshot: ClassTolerance
        let params: ReceptorClasses.Parameters
        var id: ReceptorClasses.ReceptorClass {
            snapshot.receptorClass
        }
        /// The slow availability axis is a valid effect multiplier only for some classes; otherwise the
        /// honest slow readout is the bounded load.
        var usesLoad: Bool {
            !params.usesEffectMultiplier
        }
        var isSafetyCritical: Bool {
            switch params.safetyAxis {
            case .resetOverdose, .dependenceKindling: true
            default: false
            }
        }
    }

    private var groupedRows: (attention: [Row], active: [Row]) {
        let rows = tolerance.states.values.compactMap { snap -> Row? in
            let p = ReceptorClasses.parameters(for: snap.receptorClass)
            let interesting = (1 - snap.availability) > 0.03
                || snap.load > 0.02
                || (p.hasAcutePool && (1 - snap.acute) > 0.03)
            guard interesting else { return nil }
            return Row(snapshot: snap, params: p)
        }
        .sorted { $0.snapshot.severity > $1.snapshot.severity }

        return (rows.filter(\.isSafetyCritical), rows.filter { !$0.isSafetyCritical })
    }

    // MARK: - About / header

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Predicted, not measured", systemImage: "function")
                    .font(.subheadline.weight(.semibold))
                Text("These are model predictions of how repeated use changes each receptor's responsiveness — never a measurement. Tolerance is shown per mechanism, because one universal \u{201C}tolerance %\u{201D} is wrong for some classes (stimulants especially).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                if profile.isWeightEstimated {
                    Label("Based on an estimated \(Int(UserProfileStore.defaultWeightKg)) kg body weight — set yours in Settings for accuracy.", systemImage: "scalemass")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .padding(.vertical, 4)

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

    // MARK: - Sections

    @ViewBuilder
    private func section(title: LocalizedStringKey, systemImage: String?, tint: Color, rows: [Row]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { card($0) }
            } header: {
                Label {
                    Text(title)
                } icon: {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(tint) }
                }
                .font(.footnote.weight(.semibold))
            }
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

            severityBar(row)

            facets(row)

            if let note = safetyNote(for: row) {
                Divider()
                Label {
                    Text(note).font(.caption).foregroundStyle(Theme.secondaryLabel)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }

            Text(confidenceLine(row))
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, 6)
    }

    private func cardHeader(_ row: Row) -> some View {
        let snap = row.snapshot
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(snap.receptorClass.displayName)
                    .font(.headline)
                Spacer()
                Text(stateWord(row))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(severityColor(row).opacity(0.18), in: Capsule())
                    .foregroundStyle(severityColor(row))
            }
            if !snap.contributors.isEmpty {
                Text(listPhrase(snap.contributors))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    // MARK: - Severity bar (one semantic: more fill = more affected)

    private func severityBar(_ row: Row) -> some View {
        let value = row.snapshot.severity
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(severityColor(row))
                    .frame(width: max(4, geo.size.width * min(1, max(0.02, value))))
            }
        }
        .frame(height: 8)
    }

    // MARK: - Facets

    @ViewBuilder
    private func facets(_ row: Row) -> some View {
        let snap = row.snapshot
        HStack(alignment: .top, spacing: 18) {
            if row.params.hasAcutePool, (1 - snap.acute) > 0.03 {
                facet(key: "Right now (redose)") {
                    Text("lands ~\(pct(snap.acute))% as strong")
                }
            }
            if row.usesLoad {
                facet(key: "Recovery-state load") {
                    Text(loadWord(snap.load))
                }
            } else {
                facet(key: "Sensitivity") {
                    Text("~\(pct(snap.availability))% of rested")
                }
            }
            facet(key: "If you stop now") {
                Text(recoveryValue(row))
            }
        }
    }

    private func facet(key: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .textCase(.uppercase)
            value()
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recoveryValue(_ row: Row) -> LocalizedStringResource {
        let snap = row.snapshot
        if row.usesLoad {
            guard let mins = PDModel.loadDecayMinutes(from: snap.load, to: 0.1, tauMinutes: row.params.tauLoadMinutes), mins > 0 else {
                return "cleared"
            }
            return "\(durationPhrase(minutes: mins))"
        }
        guard let mins = PDModel.recoveryMinutes(from: snap.availability, to: 0.9, tauMinutes: row.params.tauSlowMinutes), mins > 0 else {
            return "nearly rested"
        }
        return "\(durationPhrase(minutes: mins))"
    }

    // MARK: - Safety axis

    private func safetyNote(for row: Row) -> LocalizedStringResource? {
        switch row.params.safetyAxis {
        case .resetOverdose:
            "After a break your opioid tolerance drops — the dose that felt fine before can stop your breathing. Hypoxia is sudden, with no warning. Restart low, and keep naloxone accessible to someone who's with you."
        case .dependenceKindling:
            "Repeated GABA depressant use builds dependence; abrupt stops after heavy use can be dangerous. Taper rather than quitting cold."
        case .stimulantLoad, .serotonergicLoad, .cumulativeToxicity, .hppd, .none:
            nil
        }
    }

    private func confidenceLine(_ row: Row) -> LocalizedStringResource {
        let conf = row.snapshot.confidence.label
        if row.usesLoad {
            return "\(conf) · a recovery-state indicator, not a dose multiplier"
        }
        return "\(conf)"
    }

    // MARK: - Wording / colour

    private func stateWord(_ row: Row) -> LocalizedStringResource {
        switch row.snapshot.severity {
        case ..<0.15: "Rested"
        case ..<0.4: "Mild"
        case ..<0.6: "Moderate"
        case ..<0.85: "Heavy"
        default: "Depleted"
        }
    }

    private func severityColor(_ row: Row) -> Color {
        switch row.snapshot.severity {
        case ..<0.15: .green
        case ..<0.4: Color(red: 0.6, green: 0.78, blue: 0.35)
        case ..<0.6: .yellow
        case ..<0.85: .orange
        default: .red
        }
    }

    private func loadWord(_ load: Double) -> LocalizedStringResource {
        switch load {
        case ..<0.15: "Low"
        case ..<0.4: "Moderate"
        default: "High"
        }
    }

    // MARK: - Formatting

    private func pct(_ value: Double) -> Int {
        Int((min(1, max(0, value)) * 100).rounded())
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

    /// "A, B and C" style join for the contributor list.
    private func listPhrase(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names)
    }
}
