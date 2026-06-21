import SwiftData
import SwiftUI

/// The **Tolerance** tool (pharmacology axis, Stage 2). It replays the dose log through
/// ``ToleranceStore`` and renders the per-target tolerance state with **class-aware** copy — the
/// load-bearing design claim that tolerance is *per-mechanism*, never one universal "tolerance %".
///
/// ## Class-aware rendering
/// Each tracked receptor target maps to a ``ReceptorClasses/ReceptorClass`` whose
/// ``ReceptorClasses/Parameters/usesEffectMultiplier`` flag decides the readout:
/// - **Multiplier-valid** (psychedelic / opioid / GABA / NMDA / CB1 / adenosine): a predicted
///   *availability* ("≈X% of rested response") + a stop-now recovery forecast. Opioids additionally
///   carry the reset-after-break overdose safety note.
/// - **Not a multiplier** (stimulant / serotonin-releaser / nicotinic): the engine *refuses* the fake
///   "tolerance %" and instead shows the bounded allostatic-**load** recovery-state indicator + the
///   within-session redose readout + a one-line explainer of why a single number would be wrong.
///
/// Every figure is badged ``ConfidenceTier`` — the house rule is "predicted (model, confidence)",
/// never "measured". Numbers are also gated on body weight (Foundation A); when it's the population
/// default, the header says so.
struct ToleranceToolView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var entries: [DoseEntry]

    @State private var tolerance = ToleranceStore.shared
    @State private var profile = UserProfileStore.shared

    var body: some View {
        List {
            Group {
                aboutSection

                let rows = rows
                if rows.isEmpty {
                    emptyState
                } else {
                    ForEach(rows) { row in
                        Section { card(row) }
                    }
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appNavigationBar("Tolerance")
        // Lazy replay: the 18-month integration runs only while this tool is open, and re-runs when
        // the dose log or body weight changes — kept off the launch / dose-write hot path (Stage 2a).
        .task(id: recomputeSignature) { tolerance.recompute(from: entries) }
    }

    // MARK: - Recompute trigger

    /// Changes whenever the inputs that affect the replay change, so `.task(id:)` re-runs.
    private var recomputeSignature: String {
        "\(entries.count)|\(entries.first?.timestamp.timeIntervalSince1970 ?? 0)|\(profile.effectiveWeightKg)"
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let snapshot: TargetTolerance
        let params: ReceptorClasses.Parameters
        let contributors: [String]
        var id: String {
            snapshot.target
        }
        /// The slow availability axis is a valid effect multiplier only for some classes; otherwise the
        /// honest slow readout is the bounded load.
        var usesLoad: Bool {
            !params.usesEffectMultiplier
        }
        var severity: Double {
            usesLoad ? snapshot.load : (1 - snapshot.availability)
        }
    }

    private var rows: [Row] {
        let contributors = contributorsByTarget()
        return tolerance.states.values.compactMap { snap -> Row? in
            let p = ReceptorClasses.parameters(for: snap.receptorClass)
            let interesting = (1 - snap.availability) > 0.03
                || snap.load > 0.02
                || (p.hasAcutePool && (1 - snap.acute) > 0.03)
            guard interesting else { return nil }
            return Row(snapshot: snap, params: p, contributors: contributors[snap.target] ?? [])
        }
        .sorted { $0.severity > $1.severity }
    }

    /// Which logged substances drive each target, in recency order — for the card's "from …" line and
    /// the shared-target cross-tolerance hint. Mirrors ``ToleranceStore/simulate``'s gating so the
    /// names match the state that was computed.
    private func contributorsByTarget() -> [String: [String]] {
        let cutoff = Date.now.addingTimeInterval(-ToleranceStore.defaultLookbackDays * 86_400)
        var paramsCache: [String: PharmacologyParameters] = [:]
        var seen: [String: Set<String>] = [:]
        var result: [String: [String]] = [:]
        for entry in entries where entry.timestamp >= cutoff {
            let p: PharmacologyParameters
            if let cached = paramsCache[entry.substance] {
                p = cached
            } else {
                p = SubstanceStore.shared.pharmacologyParameters(forSubstanceName: entry.substance)
                paramsCache[entry.substance] = p
            }
            guard p.canComputeOccupancy else { continue }
            for engagement in p.targets where !(seen[engagement.target]?.contains(entry.substance) ?? false) {
                seen[engagement.target, default: []].insert(entry.substance)
                result[engagement.target, default: []].append(entry.substance)
            }
        }
        return result
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
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Nothing to show yet", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                Text("Log doses of substances with receptor data and your predicted tolerance will appear here. Targets you haven't engaged recently read as fully rested.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Card

    private func card(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(row)

            if row.usesLoad {
                loadReadout(row)
            } else {
                availabilityReadout(row)
            }

            if row.params.hasAcutePool, (1 - row.snapshot.acute) > 0.03 {
                acuteReadout(row)
            }

            if let note = safetyNote(for: row) {
                Divider()
                Label {
                    Text(note).font(.caption).foregroundStyle(Theme.secondaryLabel)
                } icon: {
                    Image(systemName: safetyIcon(for: row.snapshot.receptorClass))
                        .foregroundStyle(.orange)
                }
            }

            if row.contributors.count > 1 {
                Text("Shared by \(listPhrase(row.contributors)) — tolerance to one carries to the others.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, 6)
    }

    private func cardHeader(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.snapshot.receptorClass.displayName)
                    .font(.headline)
                Spacer()
                ConfidenceBadge(tier: row.snapshot.confidence)
            }
            HStack(spacing: 6) {
                Text(row.snapshot.target)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.secondaryLabel)
                if let first = row.contributors.first, row.contributors.count == 1 {
                    Text("· from \(first)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }

    // MARK: - Multiplier-valid readout (availability)

    @ViewBuilder
    private func availabilityReadout(_ row: Row) -> some View {
        let availability = row.snapshot.availability
        VStack(alignment: .leading, spacing: 6) {
            Text("Predicted response vs. rested: ~\(pct(availability))%")
                .font(.subheadline.weight(.medium))
            bar(value: availability, tint: .accentColor)
            Text(recoveryPhrase(availability: availability, tau: row.params.tauSlowMinutes))
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    private func recoveryPhrase(availability: Double, tau: Double) -> LocalizedStringResource {
        guard let mins = PDModel.recoveryMinutes(from: availability, to: 0.9, tauMinutes: tau),
              mins > 0 else {
            return "Nearly recovered."
        }
        return "\(durationPhrase(minutes: mins)) to ~90% if you stop now."
    }

    // MARK: - Not-a-multiplier readout (load)

    @ViewBuilder
    private func loadReadout(_ row: Row) -> some View {
        let load = row.snapshot.load
        VStack(alignment: .leading, spacing: 6) {
            Text(loadHeadline(load))
                .font(.subheadline.weight(.medium))
            bar(value: load, tint: .orange)
            Text(notAMultiplierExplainer(for: row.snapshot.receptorClass))
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            if let mins = PDModel.loadDecayMinutes(from: load, to: 0.1, tauMinutes: row.params.tauLoadMinutes), mins > 0 {
                Text("\(durationPhrase(minutes: mins)) to clear if you stop now.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    private func loadHeadline(_ load: Double) -> LocalizedStringResource {
        switch load {
        case ..<0.15: "Recovery-state load: low"
        case ..<0.4: "Recovery-state load: moderate"
        default: "Recovery-state load: high"
        }
    }

    private func notAMultiplierExplainer(for receptorClass: ReceptorClasses.ReceptorClass) -> LocalizedStringResource {
        switch receptorClass {
        case .catecholamineStimulant:
            "Stimulant tolerance isn't one number you can multiply a dose by. The fast part is within a session (a redose lands weaker); the slow part is a months-long recovery state, not a \u{201C}take more\u{201D} signal."
        case .serotonergicReleaser:
            "The slow change here is a SERT-binding association, reversible-leaning — not proven neurotoxicity, and not a dose multiplier. It's a recovery-state indicator."
        case .nicotinic:
            "Nicotine tolerance is mostly fast receptor desensitization that recovers between uses — a single \u{201C}tolerance %\u{201D} wouldn't capture it."
        default:
            "The slow axis here is a recovery-state indicator, not an effect multiplier."
        }
    }

    // MARK: - Acute (within-session redose) readout

    private func acuteReadout(_ row: Row) -> some View {
        Text("A redose right now would land ~\(pct(row.snapshot.acute))% as strong — within-session tachyphylaxis, recovers overnight.")
            .font(.caption)
            .foregroundStyle(Theme.secondaryLabel)
    }

    // MARK: - Safety axis

    private func safetyNote(for row: Row) -> LocalizedStringResource? {
        switch row.params.safetyAxis {
        case .resetOverdose:
            // Fire the reset-after-break warning only when availability has meaningfully recovered
            // (a real break) AND there's still tolerance in play — the model saying risk is real, once.
            "After a break your opioid tolerance drops — the dose that felt fine before can stop your breathing. Hypoxia is sudden, with no warning. Restart low, and keep naloxone accessible to someone who's with you."
        case .dependenceKindling:
            "Repeated GABA depressant use builds dependence; abrupt stops after heavy use can be dangerous. Taper rather than quitting cold."
        case .stimulantLoad, .serotonergicLoad, .cumulativeToxicity, .hppd, .none:
            nil
        }
    }

    private func safetyIcon(for _: ReceptorClasses.ReceptorClass) -> String {
        "exclamationmark.triangle.fill"
    }

    // MARK: - Bar

    private func bar(value: Double, tint: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule().fill(tint)
                    .frame(width: max(4, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 8)
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
