import Foundation
import SwiftUI

/// Population-level reference for what benzodiazepine (GABA-class) discontinuation looks like — the
/// relapse / rebound / withdrawal taxonomy and the onset/peak timing bands, with the user's own
/// logged drugs sorted into those bands and a "days since your last dose" marker placed on the
/// window. Pure reference + day arithmetic: no per-user occupancy model (that is I.full, after the
/// metabolite simulation lands). Source: NAV26 §5.4 (Navarrete et al. 2026, Int J Mol Sci 27:1430).
struct WithdrawalReferenceView: View {
    /// The GABA-class substances the user actually logged (the card's `contributors`), used to pick
    /// which timing band(s) apply.
    let contributors: [String]
    /// The most recent GABA-class dose, or `nil` if none is datable — drives the "since your last
    /// dose" marker.
    let lastDoseDate: Date?
    /// Per-drug **metabolite-extended** half-life (minutes), keyed by contributor name (I.full): the
    /// slowest of the parent's own half-life and its foldable active metabolites'. Absent keys fall
    /// back to the parent-half-life classification. This is what lifts a prodrug like clorazepate into
    /// the long-acting band via its nordazepam tail rather than its short parent.
    var effectiveHalfLifeMinutes: [String: Double] = [:]

    var body: some View {
        List {
            Section {
                Text("What stopping looks like, at the population level — three things people call \"withdrawal\" that behave differently, and roughly when each starts for drugs like the ones you've logged. Timing is from research populations, not a prediction for you.")
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
                Text("When symptoms start")
            } footer: {
                Text("Longer-acting drugs delay onset because the drug is still leaving your system. Active metabolites (diazepam, chlordiazepoxide, clonazepam) can push the window later still.")
            }

            Section {
                Text("Not medical advice. Stopping a benzodiazepine abruptly after regular use can cause seizures. These are population timings, not a taper plan.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            Section {
                Link(destination: URL(string: "https://doi.org/10.3390/ijms27031430")!) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Navarrete F, et al. Benzodiazepine Dependence: Clinical and Molecular Aspects, Preventive Strategies and Therapeutic Approaches. Int J Mol Sci. 2026;27(3):1430.")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                        Text("doi:10.3390/ijms27031430")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("If You Stop")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Since last dose

    private func sinceLastDoseSection(_ days: Int) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(daysPhrase(days))
                    .font(.title3.weight(.semibold))
                Text(placementPhrase(days: days))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                if let band = governingBand {
                    WithdrawalOnsetBand(
                        onsetStartDays: band.onsetStartDays, peakEndDays: band.peakEndDays,
                        currentDays: Double(days),
                    )
                    .padding(.top, 2)
                    Text("Estimated from your logged doses — the window is a population range, not a prediction for you.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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

    /// Where the days-since count sits relative to the *longest-acting* logged drug's onset window —
    /// the conservative read, since the slowest drug sets when symptoms can still begin. The specific
    /// band and window are shown in "When symptoms start" below, so this stays a plain full sentence.
    private func placementPhrase(days: Int) -> LocalizedStringResource {
        guard let band = governingBand else {
            return "No half-life on file for your logged drugs, so the onset window can't be placed."
        }
        let d = Double(days)
        if d < band.onsetStartDays {
            return "Before the usual onset window for your slowest-clearing drug — symptoms, if any, would typically start later."
        }
        if d <= band.peakEndDays {
            return "Within the window when symptoms for drugs like yours typically begin and peak."
        }
        return "Past the typical peak window for your drugs — a protracted tail can still persist for weeks."
    }

    // MARK: - Bands

    /// The distinct timing bands the user's logged drugs fall into, longest-acting first (so the
    /// governing/most-cautious band reads at the top).
    private var userBands: [TimingBand] {
        let classes = Set(contributors.map {
            WithdrawalActingClass.classify(name: $0, effectiveHalfLifeMinutes: effectiveHalfLifeMinutes[$0])
        })
        return TimingBand.all.filter { classes.contains($0.actingClass) }
    }

    /// The bands none of the user's drugs fall into — shown dimmed for completeness/context.
    private var otherBands: [TimingBand] {
        let shown = Set(userBands.map(\.actingClass))
        return TimingBand.all.filter { !shown.contains($0.actingClass) }
    }

    /// The single band that governs the "since last dose" placement — the longest-acting among the
    /// user's drugs (latest onset), since that is the one whose window is still open longest.
    private var governingBand: TimingBand? {
        userBands.max { $0.actingClass.rank < $1.actingClass.rank }
    }
}

// MARK: - Acting-class classifier

/// Coarse benzodiazepine duration class for the withdrawal-onset bands. Classified by half-life
/// thresholds (12 h / 40 h) over the drug's **metabolite-extended** effective half-life (I.full): a
/// prodrug or short parent whose long-acting active metabolite dominates the tail (chlordiazepoxide,
/// clorazepate, ketazolam → nordazepam, t½ ≈ 70 h) reads as long-acting because its metabolite is.
/// The NAV26 §5.4 curated table is kept as a floor for the drugs it names, and metabolite data can
/// only *lengthen* the band, never shorten it.
nonisolated enum WithdrawalActingClass: Hashable {
    case short
    case intermediate
    case long

    /// Sort key: longer-acting ranks higher (governs the conservative onset placement).
    var rank: Int {
        switch self {
        case .short: 0
        case .intermediate: 1
        case .long: 2
        }
    }

    /// NAV26 §5.4 clinical groupings, used as a floor (a named drug is never classified *shorter* than
    /// its table entry, even if a half-life lookup would say so).
    private static let curated: [String: WithdrawalActingClass] = [
        "triazolam": .short,
        "alprazolam": .short,
        "lorazepam": .short,
        "temazepam": .intermediate,
        "oxazepam": .intermediate,
        "bromazepam": .intermediate,
        "diazepam": .long,
        "chlordiazepoxide": .long,
        "clonazepam": .long,
    ]

    /// Band from a half-life in minutes: < 12 h short, 12–40 h intermediate, > 40 h long.
    private static func band(forMinutes minutes: Double) -> WithdrawalActingClass {
        switch minutes {
        case ..<720: .short
        case 720 ..< 2_400: .intermediate
        default: .long
        }
    }

    /// The longest-acting of the NAV26 curated band and the band implied by the drug's
    /// **metabolite-extended** half-life (K.5). `effectiveHalfLifeMinutes` is the slowest of the
    /// parent's own half-life and its foldable active metabolites'; `nil` falls back to the parent's
    /// half-life alone (I.ref behavior). Metabolite data only lengthens the band, so the two sources
    /// are combined by taking the longer-acting.
    static func classify(name: String, effectiveHalfLifeMinutes: Double?) -> WithdrawalActingClass {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        let metaboliteBand = effectiveHalfLifeMinutes.map(band(forMinutes:))
        if let curatedBand = curated[key] {
            // Named in the NAV26 table: that band is the floor, upgraded only by a longer-acting
            // metabolite-extended half-life (never shortened by a parent-half-life lookup).
            return [curatedBand, metaboliteBand].compactMap(\.self).max { $0.rank < $1.rank } ?? curatedBand
        }
        // Un-curated: classify by the metabolite-extended half-life, else the parent's own.
        if let metaboliteBand { return metaboliteBand }
        return HalfLifeDatabase.halfLife(for: name).map(band(forMinutes:)) ?? .intermediate
    }
}

// MARK: - Timing band data

/// One onset/peak timing band with its display copy. Windows are in days, from NAV26 §5.4.
struct TimingBand: Identifiable {
    let actingClass: WithdrawalActingClass
    let title: LocalizedStringResource
    let examples: LocalizedStringResource
    let onsetPhrase: LocalizedStringResource
    let peakPhrase: LocalizedStringResource
    let onsetStartDays: Double
    let peakEndDays: Double

    var id: Int {
        actingClass.rank
    }

    static let all: [TimingBand] = [
        TimingBand(
            actingClass: .long,
            title: "long-acting",
            examples: "diazepam, chlordiazepoxide, clonazepam",
            onsetPhrase: "2–7 days",
            peakPhrase: "5–14 days",
            onsetStartDays: 2,
            peakEndDays: 14,
        ),
        TimingBand(
            actingClass: .intermediate,
            title: "intermediate",
            examples: "temazepam, oxazepam, bromazepam",
            onsetPhrase: "1–2 days",
            peakPhrase: "3–7 days",
            onsetStartDays: 1,
            peakEndDays: 7,
        ),
        TimingBand(
            actingClass: .short,
            title: "short-acting",
            examples: "triazolam, alprazolam, lorazepam",
            onsetPhrase: "6–24 hours",
            peakPhrase: "1–4 days",
            onsetStartDays: 0.25,
            peakEndDays: 4,
        ),
    ]
}

// MARK: - Onset band

/// A compact horizontal band placing the user's days-since-last-dose against the governing timing
/// band's onset→peak window (I.full). The colored zone is `[onsetStart, peakEnd]`; the accent marker
/// is "now". Scaled so the window and the marker both fit with a little headroom.
private struct WithdrawalOnsetBand: View {
    let onsetStartDays: Double
    let peakEndDays: Double
    let currentDays: Double

    private var total: Double {
        max(peakEndDays * 1.3, currentDays * 1.1, 1)
    }

    private func position(_ days: Double, width: CGFloat) -> CGFloat {
        CGFloat(min(days, total) / total) * width
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.secondaryLabel.opacity(0.15))
                Capsule()
                    .fill(Color.orange.opacity(0.35))
                    .frame(width: max(2, position(peakEndDays, width: width) - position(onsetStartDays, width: width)))
                    .offset(x: position(onsetStartDays, width: width))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 3)
                    .offset(x: min(position(currentDays, width: width), width - 3))
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("Estimated withdrawal onset window, with a marker for time since your last dose.")
    }
}

// MARK: - Row views

private struct TimingRow: View {
    let band: TimingBand
    let isYours: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(band.title)
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
            Text("Onset \(String(localized: band.onsetPhrase)), peak \(String(localized: band.peakPhrase))")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
            Text(band.examples)
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
