import Testing
import Foundation
@testable import Piru

/// Verifies the per-substance overlay used when a user has a custom entry for
/// a substance the bundled library also knows about — the scenario that broke
/// after the multi-source DB merge dropped runtime PsychonautWiki fetches.
/// The bundled DB ships substances like 2-MMC with dose ranges but no
/// duration data; without this overlay the timeline silently demotes those
/// entries to marker dots.
@Suite("Substance custom overlay")
@MainActor
struct SubstanceCustomOverlayTests {

    private static func libraryStub() -> Substance {
        Substance(
            name: "2-MMC",
            aliases: ["2 mmc", "2mmc"],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [
                SubstanceRoute(
                    route: .oral, unit: "mg",
                    doses: DoseRange(light: 20...50, common: 50...100, strong: 100...150),
                    duration: nil
                ),
                SubstanceRoute(
                    route: .insufflation, unit: "mg",
                    doses: DoseRange(light: 5...15, common: 15...30, strong: 30...60),
                    duration: nil
                ),
            ],
            effects: ["stimulation", "euphoria"],
            halfLifeMinutes: 90,
            sources: ["tripsit"],
            tags: ["cathinone", "research-chemical"]
        )
    }

    private static func customDuration() -> DurationProfile {
        DurationProfile(
            onset: DurationRange(min: 10, max: 20),
            comeup: DurationRange(min: 15, max: 30),
            peak: DurationRange(min: 60, max: 90),
            offset: DurationRange(min: 60, max: 90),
            afterglow: nil,
            total: DurationRange(min: 180, max: 240)
        )
    }

    @Test("No-op when custom has no duration")
    func noOpWithoutDuration() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(name: "2-MMC", defaultRoute: .oral, duration: nil)
        let result = library.applyingOverride(from: custom)
        #expect(result.routes.count == 2)
        #expect(result.routes.allSatisfy { $0.duration == nil })
        #expect(!result.sources.contains(CustomSubstanceEntry.userDefinedSource))
    }

    @Test("Custom duration replaces matching route's duration")
    func overlaysMatchingRoute() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(
            name: "2-MMC", defaultRoute: .oral, duration: Self.customDuration()
        )
        let result = library.applyingOverride(from: custom)

        let oral = result.routes.first { $0.route == .oral }
        #expect(oral?.duration?.peak?.midpoint == 75)
        #expect(oral?.doses.common == 50...100, "Library dose range preserved")

        let insufflation = result.routes.first { $0.route == .insufflation }
        #expect(insufflation?.duration == nil, "Non-matching route untouched")
    }

    @Test("Adds a new route when library has none for the custom's defaultRoute")
    func addsMissingRoute() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(
            name: "2-MMC", defaultRoute: .sublingual, unit: "mg", duration: Self.customDuration()
        )
        let result = library.applyingOverride(from: custom)

        #expect(result.routes.count == 3)
        #expect(result.routes.contains { $0.route == .sublingual })
        let sublingual = result.routes.first { $0.route == .sublingual }
        #expect(sublingual?.duration?.peak?.midpoint == 75)
    }

    @Test("Preserves library category, half-life, effects, tags")
    func preservesOtherFields() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(
            name: "2-MMC", defaultRoute: .oral, duration: Self.customDuration()
        )
        let result = library.applyingOverride(from: custom)
        #expect(result.category == .stimulant)
        #expect(result.halfLifeMinutes == 90)
        #expect(result.effects == ["stimulation", "euphoria"])
        #expect(result.tags == ["cathinone", "research-chemical"])
    }

    @Test("Appends user-defined source attribution")
    func appendsUserDefinedSource() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(
            name: "2-MMC", defaultRoute: .oral, duration: Self.customDuration()
        )
        let result = library.applyingOverride(from: custom)
        #expect(result.sources.contains(CustomSubstanceEntry.userDefinedSource))
        #expect(result.sources.contains("tripsit"))
    }

    @Test("Source attribution not duplicated when applied twice")
    func sourceAttributionIdempotent() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(
            name: "2-MMC", defaultRoute: .oral, duration: Self.customDuration()
        )
        let once = library.applyingOverride(from: custom)
        let twice = once.applyingOverride(from: custom)
        #expect(twice.sources.filter { $0 == CustomSubstanceEntry.userDefinedSource }.count == 1)
    }

    @Test("Display-name override sets displayTitle, keeps canonical name")
    func displayNameOverride() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(name: "2-MMC", displayName: "joint", defaultRoute: .oral)
        let result = library.applyingOverride(from: custom)
        #expect(result.name == "2-MMC", "Canonical identity unchanged")
        #expect(result.displayTitle == "joint")
        #expect(result.sources.contains(CustomSubstanceEntry.userDefinedSource))
    }

    @Test("Blank display name does not override")
    func blankDisplayNameIgnored() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(name: "2-MMC", displayName: "   ", defaultRoute: .oral)
        let result = library.applyingOverride(from: custom)
        #expect(result.displayTitle == "2-MMC")
    }

    @Test("Dose-range override replaces matching route's doses")
    func doseOverride() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(
            name: "2-MMC", defaultRoute: .oral, unit: "mg",
            doses: DoseRange(threshold: 10, light: 25...60, common: 60...120, strong: 120...180, heavy: 200)
        )
        let result = library.applyingOverride(from: custom)
        let oral = result.routes.first { $0.route == .oral }
        #expect(oral?.doses.common == 60...120, "Custom dose range applied")
        #expect(oral?.doses.threshold == 10)
        let insufflation = result.routes.first { $0.route == .insufflation }
        #expect(insufflation?.doses.common == 15...30, "Non-matching route's doses untouched")
    }

    @Test("Half-life override replaces library half-life")
    func halfLifeOverride() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(name: "2-MMC", defaultRoute: .oral, halfLifeMinutes: 200)
        let result = library.applyingOverride(from: custom)
        #expect(result.halfLifeMinutes == 200)
    }

    @Test("Empty override is a true no-op")
    func emptyOverrideNoOp() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(name: "2-MMC", defaultRoute: .oral)
        let result = library.applyingOverride(from: custom)
        #expect(result.halfLifeMinutes == 90)
        #expect(result.displayTitle == "2-MMC")
        #expect(!result.sources.contains(CustomSubstanceEntry.userDefinedSource))
    }

    @Test("Pre-1.4 entries decode with nil overrides (backward compatible)")
    func backwardCompatibleDecode() throws {
        // Simulate a pre-1.4 stored entry by encoding a modern one and stripping
        // the fields added in v1.4 — decoding must tolerate their absence.
        let modern = CustomSubstanceEntry(name: "Foo", category: .stimulant, defaultRoute: .oral, unit: "mg")
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(modern)) as! [String: Any]
        for key in ["displayName", "doses", "halfLifeMinutes"] { obj.removeValue(forKey: key) }
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let entry = try JSONDecoder().decode(CustomSubstanceEntry.self, from: legacy)
        #expect(entry.name == "Foo")
        #expect(entry.displayName == nil)
        #expect(entry.doses == nil)
        #expect(entry.halfLifeMinutes == nil)
    }

    @Test("resolvedDisplayName prefers the personal label")
    func resolvedDisplayNameHelper() {
        #expect(CustomSubstanceEntry(name: "THC", displayName: "joint").resolvedDisplayName == "joint")
        #expect(CustomSubstanceEntry(name: "THC").resolvedDisplayName == "THC")
        #expect(CustomSubstanceEntry(name: "THC", displayName: "  ").resolvedDisplayName == "THC")
    }

    @Test("ActiveSubstanceState.from succeeds for the overlaid substance")
    func activeStateBuildsFromOverlaid() {
        let library = Self.libraryStub()
        let custom = CustomSubstanceEntry(
            name: "2-MMC", defaultRoute: .oral, duration: Self.customDuration()
        )
        let overlaid = library.applyingOverride(from: custom)
        let entry = DoseEntry(
            substance: "2-MMC", amount: 100, unit: "mg", route: .oral, timestamp: .now
        )
        let state = ActiveSubstanceState(
            name: entry.substance,
            colorHex: "FFAACC",
            timestamp: entry.timestamp,
            amount: entry.amount,
            unit: entry.unit,
            routeDisplayName: entry.route.displayName,
            duration: overlaid.resolveDuration(for: entry.route),
            doseIntensity: 0.6
        )
        #expect(state != nil, "Overlaid duration should produce a renderable curve state")
        #expect(state?.totalMinutes ?? 0 > 0)
    }
}
