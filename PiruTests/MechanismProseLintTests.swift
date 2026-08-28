import Foundation
import Testing
@testable import Piru

/// Renders the Pharmacology card as plain text, the way the UI composes it, so prose can be
/// audited against what the reader can already see beside it.
///
/// The card is not one block of text: a summary and description sit above a receptor panel with
/// per-target actions and concentrations, a downstream-signalling note, and a pharmacokinetics
/// section. A description that restates any of that spends the reader's attention twice and, worse,
/// gives a sentence the authority of the measured row it is paraphrasing. 7-hydroxymitragynine's
/// entry was written with "partial agonist, EC₅₀ 34.5 nM, Emax 47% of DAMGO, G protein-biased" —
/// every clause of which the card was already rendering as a chip, an axis, a row and a
/// downstream line.
struct MechanismCardText {
    let name: String
    let summary: String
    let description: String
    /// "MOR · partialAgonist · Kᵢ 47.0 nM" per rendered receptor row.
    let receptorRows: [String]
    /// Concentrations and durations the card shows in its own fields — the values prose must not
    /// restate. Kept as strings because that is how a reader meets them.
    let shownValues: [String]

    @MainActor
    static func render(for substance: Substance) -> MechanismCardText? {
        guard let moa = MechanismOfActionDatabase.resolvedMechanism(
            dbMechanism: substance.mechanismOfAction, category: substance.category,
        ) else { return nil }
        let store = SubstanceStore.shared
        let hits = store.bindings(forSubstanceName: substance.name)

        var rows: [String] = []
        var values: [String] = []
        for hit in hits {
            var line = "\(hit.target) · \(hit.action)"
            for (label, value) in [("Ki", hit.kiNm), ("EC50", hit.ec50Nm), ("IC50", hit.ic50Nm)] {
                guard let value else { continue }
                line += " · \(label) \(value) nM"
                values.append("\(value)")
            }
            rows.append(line)
        }
        for route in store.pharmacokinetics(forSubstanceName: substance.name) {
            for value in [route.halfLifeMin, route.tmaxMin, route.bioavailabilityPct] {
                if let value { values.append("\(value)") }
            }
        }
        return MechanismCardText(
            name: substance.name, summary: moa.summary, description: moa.description,
            receptorRows: rows, shownValues: values,
        )
    }

    /// The whole card as one string — what a reader takes in.
    var plainText: String {
        ([summary, description] + receptorRows).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// Lints the hand-written mechanism prose against the card it appears on.
///
/// Both rules exist because the app already says the thing. A measured value belongs in the row
/// built to carry it — with its unit, its species badge and its citation link — not in a sentence
/// where it arrives unsourced and cannot be compared against anything.
@Suite("Mechanism prose lint")
struct MechanismProseLintTests {
    /// A description longer than this is doing more than describing a mechanism. The corpus median
    /// is 371 characters and the 99th percentile is 662, so this flags outliers rather than
    /// imposing a house length.
    static let maxDescriptionLength = 700

    /// A number carrying one of these units is a datum the app has a dedicated field for. A bare
    /// ratio ("roughly tenfold more potent", "2× the affinity") is not — that is a comparison,
    /// which is exactly the kind of claim prose is for.
    static let measurementPattern = try! NSRegularExpression(
        pattern: #"(?<![\w.])\d[\d,]*(\.\d+)?\s*(nM|µM|μM|pM|mM|nmol|mg/kg|mg/day|mg\b|hours\b|hour\b|\bh\b|min\b)"#,
    )

    /// The 26 curated descriptions that predate this lint. Each carries a value into prose that
    /// the app has a field built for — an affinity that belongs in `bindings`, a half-life or
    /// Tmax that belongs in `pk_routes`, a dose that belongs in a ladder — and in most cases the
    /// substance has **no** such row, so the number is not a duplicate but a datum filed in the
    /// one place it cannot be sourced, compared or badged.
    ///
    /// Waived, not accepted: the list exists so new prose cannot join them, and emptying it is
    /// the point of having it. Tracked in `Specs/found-defects.md`; move the value into its field
    /// rather than deleting the sentence.
    static let knownOffenders: Set<String> = [
        "1D-LSD", "2-Me-PiHP", "4\'-DMA-7,8-DHF", "AC-262536", "BAM-15", "Bretazenil",
        "Enclomiphene", "Fluoprazolam", "Heroin", "Letrozole", "MPT", "Methadone", "Mirabegron",
        "NB-5-MeO-DALT", "NB-5-MeO-MiPT", "Naltrexone", "RAD-140", "RU58841", "S-23", "S4",
        "SLU-PP-332", "SR-9011", "Tadalafil", "Tesofensine", "Thozalinone", "Xanomeline",
    ]

    /// The waiver list may only shrink. A name that stops offending must leave it, or the list
    /// quietly becomes a place to hide a regression under a name that was already there.
    @Test
    @MainActor
    func `Every waived description still needs its waiver`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        var stale: [String] = []
        for name in Self.knownOffenders {
            guard let substance = SubstanceStore.shared.lookup(name),
                  let card = MechanismCardText.render(for: substance) else { continue }
            let text = card.description as NSString
            let range = NSRange(location: 0, length: text.length)
            if Self.measurementPattern.firstMatch(in: card.description, range: range) == nil {
                stale.append(name)
            }
        }
        let report = stale.sorted().joined(separator: ", ")
        #expect(stale.isEmpty, "fixed — remove from knownOffenders: \(report)")
    }

    @Test
    @MainActor
    func `No mechanism description restates a value the card already shows`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        var offenders: [String] = []
        for name in SubstanceStore.shared.allNames {
            guard let substance = SubstanceStore.shared.lookup(name),
                  let card = MechanismCardText.render(for: substance),
                  !card.description.isEmpty,
                  !Self.knownOffenders.contains(substance.name) else { continue }
            let text = card.description as NSString
            let matches = Self.measurementPattern.matches(
                in: card.description, range: NSRange(location: 0, length: text.length),
            )
            if let first = matches.first {
                offenders.append("\(substance.name): “\(text.substring(with: first.range))” — "
                    + "belongs in a row, not the prose")
            }
        }
        let report = offenders.prefix(12).joined(separator: "\n")
        #expect(offenders.isEmpty, "\(offenders.count) offender(s):\n\(report)")
    }

    @Test
    @MainActor
    func `No mechanism description outgrows the card it sits on`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        var tooLong: [String] = []
        for name in SubstanceStore.shared.allNames {
            guard let substance = SubstanceStore.shared.lookup(name),
                  let card = MechanismCardText.render(for: substance) else { continue }
            if card.description.count > Self.maxDescriptionLength {
                tooLong.append("\(substance.name): \(card.description.count) chars")
            }
        }
        let report = tooLong.prefix(12).joined(separator: "\n")
        #expect(tooLong.isEmpty, "\(tooLong.count) over \(Self.maxDescriptionLength):\n\(report)")
    }
}
