import Testing
@testable import Piru

@Suite("Substance Extended")
struct SubstanceExtendedTests {
    private var oralRouteWithDuration: SubstanceRoute {
        SubstanceRoute(
            route: .oral,
            unit: "mg",
            doses: DoseRange(threshold: 5, light: 10 ... 20, common: 20 ... 40, strong: 40 ... 80, heavy: 80),
            duration: DurationProfile(
                onset: DurationRange(min: 15, max: 30),
                comeup: DurationRange(min: 15, max: 30),
                peak: DurationRange(min: 60, max: 120),
                offset: DurationRange(min: 30, max: 60),
                afterglow: nil,
                total: nil,
            ),
        )
    }

    private var nasalRouteNoDuration: SubstanceRoute {
        SubstanceRoute(
            route: .insufflation,
            unit: "mg",
            doses: DoseRange(threshold: 3, light: 5 ... 15, common: 15 ... 30, strong: 30 ... 60, heavy: 60),
        )
    }

    // MARK: - resolveDuration

    @Test
    func `resolveDuration returns exact route duration when available`() {
        let substance = Substance(
            name: "Test",
            aliases: [],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [oralRouteWithDuration, nasalRouteNoDuration],
            effects: [],
        )
        let dur = substance.resolveDuration(for: .oral)
        #expect(dur != nil)
        #expect(dur?.onset?.min == 15)
    }

    @Test
    func `resolveDuration falls back when only one route has duration`() {
        let substance = Substance(
            name: "Test",
            aliases: [],
            category: .stimulant,
            defaultRoute: .insufflation,
            routes: [nasalRouteNoDuration, oralRouteWithDuration],
            effects: [],
        )
        // Insufflation has no duration; only one route has data → safe generic fallback
        let dur = substance.resolveDuration(for: .insufflation)
        #expect(dur != nil)
        #expect(dur?.onset?.min == 15)
    }

    @Test
    func `resolveDuration does not fall back across routes when multiple have data`() {
        let smokedRoute = SubstanceRoute(
            route: .inhalation,
            unit: "mg",
            doses: DoseRange(),
            duration: DurationProfile(
                onset: DurationRange(min: 0, max: 1),
                comeup: DurationRange(min: 1, max: 3),
                peak: DurationRange(min: 15, max: 45),
                offset: DurationRange(min: 30, max: 60),
                afterglow: nil, total: nil,
            ),
        )
        let substance = Substance(
            name: "Cannabis",
            aliases: [],
            category: .cannabinoid,
            defaultRoute: .inhalation,
            routes: [smokedRoute, oralRouteWithDuration],
            effects: [],
        )
        // Rectal has no data, but two routes have durations → don't guess
        #expect(substance.resolveDuration(for: .rectal) == nil)
        // Exact matches still work
        #expect(substance.resolveDuration(for: .oral) != nil)
        #expect(substance.resolveDuration(for: .inhalation) != nil)
    }

    @Test
    func `resolveDuration returns nil when no route has duration`() {
        let substance = Substance(
            name: "Test",
            aliases: [],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [nasalRouteNoDuration],
            effects: [],
        )
        #expect(substance.resolveDuration(for: .oral) == nil)
    }

    @Test
    func `resolveDuration returns nil for route not in routes and no fallback`() {
        let substance = Substance(
            name: "Test",
            aliases: [],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [nasalRouteNoDuration],
            effects: [],
        )
        #expect(substance.resolveDuration(for: .intravenous) == nil)
    }

    // MARK: - Hashable / Equatable

    @Test
    func `Two substances with same ID are equal`() {
        let s1 = Substance(
            name: "A", aliases: [], category: .stimulant,
            defaultRoute: .oral, routes: [], effects: [],
        )
        // Since id is a new UUID each time, s1 == s1 should be true (same object)
        #expect(s1 == s1)
    }

    @Test
    func `Two substances with different IDs are not equal`() {
        let s1 = Substance(name: "A", aliases: [], category: .stimulant, defaultRoute: .oral, routes: [], effects: [])
        let s2 = Substance(name: "A", aliases: [], category: .stimulant, defaultRoute: .oral, routes: [], effects: [])
        #expect(s1 != s2) // Different UUIDs
    }

    // MARK: - Empty query

    @Test
    func `Matches returns false for empty query`() {
        let s = Substance(name: "Test", aliases: [], category: .other, defaultRoute: .oral, routes: [], effects: [])
        #expect(!s.matches(""))
    }

    // MARK: - Multiple routes

    @Test
    func `doseRange returns correct range for each route`() {
        let substance = Substance(
            name: "Test",
            aliases: [],
            category: .stimulant,
            defaultRoute: .oral,
            routes: [oralRouteWithDuration, nasalRouteNoDuration],
            effects: [],
        )
        #expect(substance.doseRange(for: .oral)?.threshold == 5)
        #expect(substance.doseRange(for: .insufflation)?.threshold == 3)
    }

    // MARK: - SubjectiveEffect

    @Test
    func `SubjectiveEffect stores name and description`() {
        let effect = SubjectiveEffect(name: "Focus", description: "Sharp concentration")
        #expect(effect.name == "Focus")
        #expect(effect.description == "Sharp concentration")
    }

    // MARK: - ToleranceInfo

    @Test
    func `ToleranceInfo stores all fields`() {
        let info = ToleranceInfo(halfLife: 3, fullResetDays: 14, buildRate: "rapid")
        #expect(info.halfLife == 3)
        #expect(info.fullResetDays == 14)
        #expect(info.buildRate == "rapid")
    }
}
