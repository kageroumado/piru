import Testing
import Foundation
@testable import Piru

@Suite("SubstanceDeduplicator")
struct SubstanceDeduplicatorTests {

    // MARK: - Helpers

    private func makeSubstance(
        name: String,
        aliases: [String] = [],
        category: SubstanceCategory = .other,
        halfLifeMinutes: Double? = nil,
        toleranceInfo: ToleranceInfo? = nil,
        routes: [SubstanceRoute] = [],
        effects: [String] = [],
        subjectiveEffects: [SubjectiveEffect] = [],
        sources: [String] = []
    ) -> Substance {
        Substance(
            name: name,
            aliases: aliases,
            category: category,
            defaultRoute: routes.first?.route ?? .oral,
            routes: routes,
            effects: effects,
            subjectiveEffects: subjectiveEffects,
            toleranceInfo: toleranceInfo,
            halfLifeMinutes: halfLifeMinutes,
            sources: sources
        )
    }

    private func makeRoute(
        _ route: RouteOfAdministration = .oral,
        threshold: Double? = 10,
        light: ClosedRange<Double>? = 10...20,
        common: ClosedRange<Double>? = 20...40,
        strong: ClosedRange<Double>? = 40...60,
        heavy: Double? = 60
    ) -> SubstanceRoute {
        SubstanceRoute(
            route: route,
            unit: "mg",
            doses: DoseRange(threshold: threshold, light: light, common: common, strong: strong, heavy: heavy)
        )
    }

    // MARK: - normalizeName

    @Test("Normalizes to lowercase")
    func normalizeLowercase() {
        #expect(SubstanceDeduplicator.normalizeName("Caffeine") == "caffeine")
    }

    @Test("Strips hyphens")
    func normalizeStripHyphens() {
        #expect(SubstanceDeduplicator.normalizeName("alpha-PVP") == "alphapvp")
    }

    @Test("Strips spaces and punctuation")
    func normalizeStripsPunctuation() {
        #expect(SubstanceDeduplicator.normalizeName("N,N-DMT") == "nndmt")
    }

    @Test("Strips parentheses and apostrophes")
    func normalizeStripsParens() {
        #expect(SubstanceDeduplicator.normalizeName("(R)-Ketamine") == "rketamine")
    }

    @Test("Converts Greek letters to ASCII")
    func normalizeGreekLetters() {
        #expect(SubstanceDeduplicator.normalizeName("α-PVP") == "alphapvp")
        #expect(SubstanceDeduplicator.normalizeName("β-Alanine") == "betaalanine")
        #expect(SubstanceDeduplicator.normalizeName("γ-GBL") == "gammagbl")
        #expect(SubstanceDeduplicator.normalizeName("δ-9-THC") == "delta9thc")
    }

    @Test("Already normalized name is unchanged")
    func normalizeIdempotent() {
        let name = "caffeine"
        #expect(SubstanceDeduplicator.normalizeName(name) == name)
    }

    // MARK: - saltStripped

    @Test("Strips common salt suffixes")
    func stripsCommonSalts() {
        #expect(SubstanceDeduplicator.saltStripped("amphetaminehydrochloride") == "amphetamine")
        #expect(SubstanceDeduplicator.saltStripped("morphinesulfate") == "morphine")
        #expect(SubstanceDeduplicator.saltStripped("sertralinehcl") == "sertraline")
    }

    @Test("Strips multiple chained suffixes")
    func stripsChainedSuffix() {
        // e.g. "dextroamphetaminesulfatemonohydrate"
        let result = SubstanceDeduplicator.saltStripped("dextroamphetaminesulfatemonohydrate")
        #expect(result == "dextroamphetamine")
    }

    @Test("Does not strip if result would be empty")
    func doesNotStripToEmpty() {
        // "sodium" itself should not become empty
        let result = SubstanceDeduplicator.saltStripped("sodium")
        #expect(!result.isEmpty)
    }

    @Test("No-op for names without salt suffixes")
    func noSaltSuffix() {
        #expect(SubstanceDeduplicator.saltStripped("caffeine") == "caffeine")
    }

    // MARK: - knownAliases

    @Test("MDMA maps bidirectionally")
    func mdmaAlias() {
        #expect(SubstanceDeduplicator.knownAliases["mdma"] == "34methylenedioxymethamphetamine")
        #expect(SubstanceDeduplicator.knownAliases["34methylenedioxymethamphetamine"] == "mdma")
    }

    @Test("Paracetamol/Acetaminophen maps bidirectionally")
    func paracetamolAlias() {
        #expect(SubstanceDeduplicator.knownAliases["paracetamol"] == "acetaminophen")
        #expect(SubstanceDeduplicator.knownAliases["acetaminophen"] == "paracetamol")
    }

    @Test("Alcohol/Ethanol maps bidirectionally so oral-ethanol data merges with alcohol")
    func alcoholEthanolAlias() {
        #expect(SubstanceDeduplicator.knownAliases["alcohol"] == "ethanol")
        #expect(SubstanceDeduplicator.knownAliases["ethanol"] == "alcohol")
    }

    @Test("Known aliases map contains expected entries")
    func knownAliasesContainsExpected() {
        let aliases = SubstanceDeduplicator.knownAliases
        // Verify key abbreviations exist
        #expect(aliases["lsd"] != nil)
        #expect(aliases["mdma"] != nil)
        #expect(aliases["thc"] != nil)
        #expect(aliases["ghb"] != nil)
        #expect(aliases["dmt"] != nil)
        #expect(aliases["dxm"] != nil)
        #expect(aliases["pcp"] != nil)
        // Verify bidirectional pairs
        #expect(aliases["paracetamol"] == "acetaminophen")
        #expect(aliases["acetaminophen"] == "paracetamol")
        #expect(aliases["adrenaline"] == "epinephrine")
        #expect(aliases["epinephrine"] == "adrenaline")
    }

    // MARK: - dataScore

    @Test("Empty substance scores zero")
    func emptyScoreZero() {
        let s = makeSubstance(name: "Empty")
        #expect(SubstanceDeduplicator.dataScore(s) == 0)
    }

    @Test("Half-life adds 3 points")
    func halfLifeScore() {
        let s = makeSubstance(name: "Test", halfLifeMinutes: 300)
        #expect(SubstanceDeduplicator.dataScore(s) == 3)
    }

    @Test("Tolerance adds 2 points")
    func toleranceScore() {
        let tol = ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "moderate")
        let s = makeSubstance(name: "Test", toleranceInfo: tol)
        #expect(SubstanceDeduplicator.dataScore(s) == 2)
    }

    @Test("Route with doses adds 3 points per route")
    func routeDoseScore() {
        let route = makeRoute()
        let s = makeSubstance(name: "Test", routes: [route])
        let score = SubstanceDeduplicator.dataScore(s)
        // Route with threshold/light/common: 3 (dose) + 0 (no duration) = 3, plus 0 (no effects)
        #expect(score >= 3)
    }

    @Test("Effects add 2 points")
    func effectsScore() {
        let s = makeSubstance(name: "Test", effects: ["euphoria"])
        #expect(SubstanceDeduplicator.dataScore(s) == 2)
    }

    @Test("Aliases add to score")
    func aliasesScore() {
        let s = makeSubstance(name: "Test", aliases: ["A", "B", "C"])
        #expect(SubstanceDeduplicator.dataScore(s) == 3)
    }

    @Test("Rich substance scores high")
    func richSubstanceHighScore() {
        let tol = ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid")
        let route = makeRoute()
        let s = makeSubstance(
            name: "MDMA",
            aliases: ["Molly", "Ecstasy"],
            halfLifeMinutes: 240,
            toleranceInfo: tol,
            routes: [route],
            effects: ["euphoria", "empathy"],
            subjectiveEffects: [SubjectiveEffect(name: "Love", description: "warmth")]
        )
        let score = SubstanceDeduplicator.dataScore(s)
        // halfLife(3) + tolerance(2) + route doses(3) + effects(2) + subjectiveEffects(2) + aliases(2) = 14
        #expect(score >= 12)
    }

    // MARK: - mergeSubstances

    @Test("Merge keeps higher-scored substance as primary")
    func mergePrefersHigherScore() {
        let rich = makeSubstance(name: "Caffeine", halfLifeMinutes: 300, effects: ["wakefulness"])
        let sparse = makeSubstance(name: "Caffeine")
        let merged = SubstanceDeduplicator.mergeSubstances(rich, sparse)
        #expect(merged.halfLifeMinutes == 300)
        #expect(merged.effects.contains("wakefulness"))
    }

    @Test("Merge combines aliases")
    func mergeCombinesAliases() {
        let a = makeSubstance(name: "MDMA", aliases: ["Molly"])
        let b = makeSubstance(name: "MDMA", aliases: ["Ecstasy", "XTC"])
        let merged = SubstanceDeduplicator.mergeSubstances(a, b)
        #expect(merged.aliases.contains("Molly"))
        #expect(merged.aliases.contains("Ecstasy"))
        #expect(merged.aliases.contains("XTC"))
    }

    @Test("Merge combines sources")
    func mergeCombinesSources() {
        let a = makeSubstance(name: "Test", sources: ["TripSit"])
        let b = makeSubstance(name: "Test", sources: ["PsychonautWiki"])
        let merged = SubstanceDeduplicator.mergeSubstances(a, b)
        #expect(merged.sources.contains("TripSit"))
        #expect(merged.sources.contains("PsychonautWiki"))
    }

    @Test("Merge prefers shorter non-salt name")
    func mergePrefersShorterName() {
        let long = makeSubstance(name: "Amphetamine Sulfate", halfLifeMinutes: 600)
        let short = makeSubstance(name: "Amphetamine")
        // Give long a higher score so it would be primary, but name should still be shorter
        let merged = SubstanceDeduplicator.mergeSubstances(long, short)
        #expect(merged.name == "Amphetamine")
    }

    @Test("Merge adds secondary routes not in primary")
    func mergeAddsNewRoutes() {
        let oralRoute = makeRoute(.oral)
        let ivRoute = makeRoute(.intravenous, threshold: 5, light: 5...10, common: 10...20, strong: 20...30, heavy: 30)
        let a = makeSubstance(name: "Test", routes: [oralRoute])
        let b = makeSubstance(name: "Test", routes: [ivRoute])
        let merged = SubstanceDeduplicator.mergeSubstances(a, b)
        #expect(merged.routes.count == 2)
    }

    @Test("Merge preserves duration when the other source wins on doses")
    func mergePreservesDurationAcrossSources() {
        // Mirrors DXM's merge path: TripSit supplies duration but no usable
        // doses (mg/kg-scaled → empty), DailyMed supplies real doses in a
        // clinical unit but no pharmacokinetics. Whichever side wins the
        // dose score, duration must survive.
        let duration = DurationProfile(
            onset: DurationRange(min: 30, max: 60),
            comeup: DurationRange(min: 30, max: 60),
            peak: DurationRange(min: 120, max: 240),
            offset: DurationRange(min: 120, max: 240),
            afterglow: DurationRange(min: 240, max: 720),
            total: DurationRange(min: 360, max: 600)
        )
        let durationOnlyRoute = SubstanceRoute(
            route: .oral,
            unit: "mg",
            doses: DoseRange(),
            duration: duration
        )
        let dosesOnlyRoute = SubstanceRoute(
            route: .oral,
            unit: "mL",
            doses: DoseRange(threshold: 15, light: 15...30, common: 30...60, strong: 60...120, heavy: 120),
            duration: nil
        )
        let tripSit = makeSubstance(name: "Dextromethorphan", routes: [durationOnlyRoute], sources: ["TripSit"])
        let dailyMed = makeSubstance(name: "Dextromethorphan", routes: [dosesOnlyRoute], sources: ["DailyMed"])

        let mergedA = SubstanceDeduplicator.mergeSubstances(tripSit, dailyMed)
        let mergedB = SubstanceDeduplicator.mergeSubstances(dailyMed, tripSit)

        // Whichever side was primary, the merged oral route keeps the duration.
        #expect(mergedA.routes.first?.duration?.total?.min == 360)
        #expect(mergedB.routes.first?.duration?.total?.min == 360)
    }

    @Test("Merge combines effects without duplicates")
    func mergeCombinesEffects() {
        let a = makeSubstance(name: "Test", effects: ["euphoria", "alertness"])
        let b = makeSubstance(name: "Test", effects: ["euphoria", "empathy"])
        let merged = SubstanceDeduplicator.mergeSubstances(a, b)
        #expect(merged.effects.contains("euphoria"))
        #expect(merged.effects.contains("alertness"))
        #expect(merged.effects.contains("empathy"))
        // "euphoria" should not appear twice
        #expect(merged.effects.filter { $0.lowercased() == "euphoria" }.count == 1)
    }

    // MARK: - deduplicatedMerge

    @Test("Dedup merges exact name match")
    func dedupExactName() {
        let a = makeSubstance(name: "Caffeine", halfLifeMinutes: 300)
        let b = makeSubstance(name: "Caffeine", effects: ["alertness"])
        let result = SubstanceDeduplicator.deduplicatedMerge(existing: [a], incoming: [b])
        #expect(result.count == 1)
        #expect(result[0].halfLifeMinutes == 300)
        #expect(result[0].effects.contains("alertness"))
    }

    @Test("Dedup merges case-insensitive match")
    func dedupCaseInsensitive() {
        let a = makeSubstance(name: "caffeine")
        let b = makeSubstance(name: "CAFFEINE", halfLifeMinutes: 300)
        let result = SubstanceDeduplicator.deduplicatedMerge(existing: [a], incoming: [b])
        #expect(result.count == 1)
    }

    @Test("Dedup merges by known alias")
    func dedupByKnownAlias() {
        let a = makeSubstance(name: "Paracetamol", halfLifeMinutes: 180)
        let b = makeSubstance(name: "Acetaminophen", effects: ["pain relief"])
        let result = SubstanceDeduplicator.deduplicatedMerge(existing: [a], incoming: [b])
        #expect(result.count == 1)
    }

    @Test("Dedup merges by salt stripping")
    func dedupBySaltStrip() {
        let a = makeSubstance(name: "Morphine")
        let b = makeSubstance(name: "Morphine Sulfate", halfLifeMinutes: 180)
        let result = SubstanceDeduplicator.deduplicatedMerge(existing: [a], incoming: [b])
        #expect(result.count == 1)
    }

    @Test("Dedup adds new substances")
    func dedupAddsNew() {
        let a = makeSubstance(name: "Caffeine")
        let b = makeSubstance(name: "Aspirin")
        let result = SubstanceDeduplicator.deduplicatedMerge(existing: [a], incoming: [b])
        #expect(result.count == 2)
    }

    @Test("Dedup result is sorted alphabetically")
    func dedupSorted() {
        let substances = [
            makeSubstance(name: "Zolpidem"),
            makeSubstance(name: "Aspirin"),
            makeSubstance(name: "Melatonin"),
        ]
        let result = SubstanceDeduplicator.deduplicatedMerge(existing: [], incoming: substances)
        #expect(result[0].name == "Aspirin")
        #expect(result[1].name == "Melatonin")
        #expect(result[2].name == "Zolpidem")
    }

    @Test("Dedup matches by alias in existing")
    func dedupMatchesByAlias() {
        let a = makeSubstance(name: "MDMA", aliases: ["Molly", "Ecstasy"])
        let b = makeSubstance(name: "Molly", halfLifeMinutes: 240)
        let result = SubstanceDeduplicator.deduplicatedMerge(existing: [a], incoming: [b])
        #expect(result.count == 1)
        #expect(result[0].halfLifeMinutes == 240 || result[0].name == "MDMA")
    }

    @Test("Dedup handles empty inputs")
    func dedupEmptyInputs() {
        #expect(SubstanceDeduplicator.deduplicatedMerge(existing: [], incoming: []).isEmpty)
        let a = makeSubstance(name: "Caffeine")
        #expect(SubstanceDeduplicator.deduplicatedMerge(existing: [a], incoming: []).count == 1)
        #expect(SubstanceDeduplicator.deduplicatedMerge(existing: [], incoming: [a]).count == 1)
    }
}
