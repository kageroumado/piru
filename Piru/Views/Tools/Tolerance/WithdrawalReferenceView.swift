import Foundation
import SwiftData
import SwiftUI

/// Benzodiazepine (GABA-class) discontinuation reference: the relapse / rebound / withdrawal taxonomy
/// and the population onset/peak timing bands, framed around the user's **own modeled clearance**. The
/// "since your last dose" reading is driven by ``ToleranceStore``'s combined GABA-A occupancy curve
/// (metabolite tails included) — so it says whether the drug is still on board (withdrawal not yet
/// begun) rather than dropping a calendar day-count onto a fixed band. The taxonomy is NAV26 §5.3
/// and Table 3 (Navarrete et al. 2026, Int J Mol Sci 27:1430); the peak-timing windows are Rickels
/// 1990's measured arms and come from `withdrawal_timing_bands`, whose rows carry their own
/// provenance. The two sources are credited separately because the page used to credit NAV26 for
/// windows it does not contain.
struct WithdrawalReferenceView: View {
    /// The GABA-class substances the user actually logged (the card's `contributors`), used to pick
    /// which timing band(s) apply.
    let contributors: [String]
    /// The most recent GABA-class dose, or `nil` if none is datable — drives the "since your last
    /// dose" day count.
    let lastDoseDate: Date?
    /// Per-drug **metabolite-extended** half-life (minutes), keyed by contributor name: the slowest of
    /// the parent's own half-life and its foldable active metabolites'. Absent keys fall back to the
    /// parent-half-life classification for the population bands below.
    var effectiveHalfLifeMinutes: [String: Double] = [:]

    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]

    /// Forward GABA-A load relative to the user's recent peak (metabolite-aware), loaded off main. `nil`
    /// while the first sample is still computing. Relative, not absolute occupancy — benzodiazepine
    /// occupancy saturates, so an absolute reading pins near 100% for many half-lives after the last dose.
    @State private var loadTrail: [(date: Date, load: Double)]?

    /// Below this fraction of the recent peak the drug is treated as essentially cleared — the point the
    /// withdrawal onset actually keys off (symptoms follow clearance, not the calendar).
    private static let presenceFloor = 0.10

    var body: some View {
        List {
            Group {
                Section {
                    Text("Three things people call \"withdrawal\" that behave differently, and roughly when each starts for drugs like the ones you've logged.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }

                if let sinceLastDose {
                    sinceLastDoseSection(sinceLastDose)
                }

                Section("Three kinds of \"withdrawal\"") {
                    ForEach(Self.taxonomy) { entry in
                        TaxonomyRow(entry: entry)
                    }
                }

                Section {
                    ForEach(userBands) { band in
                        TimingRow(band: band, isYours: true)
                    }
                    ForEach(otherBands) { band in
                        TimingRow(band: band, isYours: false)
                    }
                } header: {
                    Text("When it peaks")
                } footer: {
                    Text("From a trial that stopped 57 people abruptly after a year or more of daily use and assessed them every day. Longer-acting drugs peak later because the drug is still leaving your system; active metabolites (diazepam, chlordiazepoxide, clonazepam) push it later still. When symptoms *start* is not shown because no source survives checking — the figures in circulation land at or after the measured peak, which cannot be right.")
                }

                Section {
                    Label {
                        Text("A model of your dose log, not medical advice. Stopping a benzodiazepine abruptly after regular use can cause seizures.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://doi.org/10.1001/archpsyc.1990.01810220015002")!) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Peak timing: Rickels K, et al. Long-term therapeutic use of benzodiazepines. I. Effects of abrupt discontinuation. Arch Gen Psychiatry. 1990;47(10):899-907.")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Text("doi:10.1001/archpsyc.1990.01810220015002")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
                    }
                    Link(destination: URL(string: "https://doi.org/10.3390/ijms27031430")!) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Symptom groups and drug classes: Navarrete F, et al. Benzodiazepine Dependence: Clinical and Molecular Aspects, Preventive Strategies and Therapeutic Approaches. Int J Mol Sci. 2026;27(3):1430.")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Text("doi:10.3390/ijms27031430")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .listRowBackground(CardBackground())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .appNavigationBar("If You Stop")
        .task(id: DoseLogService.shared.revision) {
            loadTrail = await ToleranceStore.shared.loadTrail(for: .gaba, from: allEntries)
        }
    }

    // MARK: - Since last dose

    /// The user's own clearance readout: whether the drug is still on board (so withdrawal hasn't
    /// begun) or has cleared (so any symptoms now are the course, not the drug leaving) — driven by the
    /// modeled occupancy curve, not a calendar day-count against a fixed population band.
    private func sinceLastDoseSection(_ days: Int) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(daysPhrase(days))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    PredictionCapsule()
                }
                Text(occupancyStatePhrase)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Since your last dose")
        }
    }

    /// Whole days since the last GABA dose (0 = today), or `nil` when no dose is datable.
    private var sinceLastDose: Int? {
        guard let lastDoseDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lastDoseDate, to: .now).day ?? 0
        return max(0, days)
    }

    private func daysPhrase(_ days: Int) -> String {
        switch days {
        case 0: String(localized: "Less than a day")
        case 1: String(localized: "1 day")
        default: String(localized: "\(days) days")
        }
    }

    /// Modeled GABA-A load right now as a fraction of the user's recent peak (first sample of the
    /// forward trail), or `nil` while it is still loading.
    private var loadNow: Double? {
        loadTrail?.first?.load
    }

    /// The first future moment the modeled load falls below ``presenceFloor`` — when the drug itself
    /// has essentially left and the withdrawal onset window actually opens. `nil` if already cleared.
    private var windowOpensDate: Date? {
        guard let now = loadNow, now >= Self.presenceFloor else { return nil }
        return loadTrail?.first { $0.load < Self.presenceFloor }?.date
    }

    /// Load-driven placement sentence. Load is relative to the user's recent peak, not absolute
    /// occupancy, so it clears honestly — benzodiazepine occupancy itself saturates and would not.
    private var occupancyStatePhrase: String {
        guard let now = loadNow else {
            return String(localized: "Estimating how much is still in your system…")
        }
        if now >= Self.presenceFloor {
            let percent = Int((now * 100).rounded())
            if let opens = windowOpensDate {
                let d = max(0, Calendar.current.dateComponents([.day], from: .now, to: opens).day ?? 0)
                let inPhrase = d == 0 ? String(localized: "under a day") : String(localized: "\(d) days")
                return String(localized: "Your modeled GABA-A load is still about \(percent)% of your recent peak — the drug is still clearing, so withdrawal hasn't started. On your current clearance it drops into the onset range in about \(inPhrase).")
            }
            return String(localized: "Your modeled GABA-A load is still about \(percent)% of your recent peak — the drug is still clearing, so withdrawal hasn't started yet.")
        }
        return String(localized: "Your modeled GABA-A load has essentially cleared — past the point where the drug itself is still leaving your system. The bands below say when symptoms tend to follow.")
    }

    // MARK: - Bands

    /// The population bands and acting-class floors, read once and held by the store.
    private var reference: WithdrawalReference {
        SubstanceStore.shared.withdrawalReference()
    }

    /// The distinct timing bands the user's logged drugs fall into, longest-acting first (so the
    /// governing/most-cautious band reads at the top).
    private var userBands: [TimingBand] {
        let reference = reference
        let classes = Set(contributors.map {
            reference.classify(name: $0, effectiveHalfLifeMinutes: effectiveHalfLifeMinutes[$0])
        })
        return reference.bands.filter { classes.contains($0.actingClass) }
    }

    /// The bands none of the user's drugs fall into — shown dimmed for completeness/context.
    private var otherBands: [TimingBand] {
        let shown = Set(userBands.map(\.actingClass))
        return reference.bands.filter { !shown.contains($0.actingClass) }
    }
}

// MARK: - Prediction capsule

/// The small "Prediction" pill marking a modeled (not measured) readout — the house provenance mark
/// the tolerance surfaces carry.
struct PredictionCapsule: View {
    var body: some View {
        Text("Prediction")
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.secondaryLabel.opacity(0.14), in: Capsule())
            .accessibilityLabel("Prediction from a model")
    }
}

// MARK: - Row views

private struct TimingRow: View {
    let band: TimingBand
    let isYours: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(band.actingClass.title)
                    .font(.subheadline.weight(.semibold))
                if isYours {
                    Text("your drugs")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
            }
            if let peak = band.peakPhrase {
                Text("Worst around \(peak)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Text(band.actingClass.examples)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(isYours ? 1 : 0.55)
    }
}

private struct TaxonomyRow: View {
    let entry: TaxonomyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.name)
                .font(.subheadline.weight(.semibold))
            Text(entry.what)
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            Text(entry.timing)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct TaxonomyEntry: Identifiable {
    let name: LocalizedStringResource
    let what: LocalizedStringResource
    let timing: LocalizedStringResource

    var id: String {
        String(localized: name)
    }
}

private extension WithdrawalReferenceView {
    static let taxonomy: [TaxonomyEntry] = [
        TaxonomyEntry(
            name: "Relapse",
            what: "The original symptoms return — the thing the drug was treating comes back.",
            timing: "Gradual onset, persists until treated.",
        ),
        TaxonomyEntry(
            name: "Rebound",
            what: "The original symptoms return, briefly stronger than before.",
            timing: "Onset 1–2 days, time-limited (days).",
        ),
        TaxonomyEntry(
            name: "Withdrawal",
            what: "New symptoms the drug wasn't treating — insomnia, tremor, and, after regular use, seizure risk.",
            timing: "2–4 weeks, with a protracted tail in some people.",
        ),
    ]
}
