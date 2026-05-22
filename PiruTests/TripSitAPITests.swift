import Foundation
import Testing
@testable import Piru

@Suite("TripSitAPI")
struct TripSitAPITests {

    // MARK: - Helpers

    private func decodeDrug(_ json: String) throws -> TripSitAPI.TripSitDrug {
        try JSONDecoder().decode(TripSitAPI.TripSitDrug.self, from: Data(json.utf8))
    }

    // MARK: - Per-route duration parsing

    @Test("Multi-route durations are parsed per-route, not globally")
    func multiRouteDurations() throws {
        let drug = try decodeDrug("""
        {
            "name": "2c-b",
            "pretty_name": "2C-B",
            "categories": ["psychedelic"],
            "properties": {
                "onset": "Oral: 20-75 minutes | Insufflated: 1-10 minutes",
                "duration": "Oral: 4-8 hours | Insufflated: 2-4 hours"
            },
            "formatted_dose": {
                "Oral": {"Threshold": "5mg", "Light": "10-15mg", "Common": "15-25mg"},
                "Insufflated": {"Threshold": "2mg", "Light": "5-10mg", "Common": "10-20mg"}
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)

        let oralDuration = substance.duration(for: .oral)
        let insuffDuration = substance.duration(for: .insufflation)

        // Oral total should be 4-8 hours (240-480 minutes)
        #expect(oralDuration?.total?.min == 240)
        #expect(oralDuration?.total?.max == 480)

        // Insufflated total should be 2-4 hours (120-240 minutes)
        #expect(insuffDuration?.total?.min == 120)
        #expect(insuffDuration?.total?.max == 240)

        // Oral onset should be 20-75 minutes
        #expect(oralDuration?.onset?.min == 20)
        #expect(oralDuration?.onset?.max == 75)

        // Insufflated onset should be 1-10 minutes
        #expect(insuffDuration?.onset?.min == 1)
        #expect(insuffDuration?.onset?.max == 10)

        // Durations should be DIFFERENT (the whole point of this fix)
        #expect(oralDuration?.total?.midpoint != insuffDuration?.total?.midpoint)
    }

    @Test("Simple duration (no route prefix) applies as fallback to all routes")
    func simpleDurationFallback() throws {
        let drug = try decodeDrug("""
        {
            "name": "test",
            "properties": {
                "onset": "30-60 minutes",
                "duration": "4-8 hours"
            },
            "formatted_dose": {
                "Oral": {"Common": "100mg"},
                "Insufflated": {"Common": "50mg"}
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)

        let oralDuration = substance.duration(for: .oral)
        let insuffDuration = substance.duration(for: .insufflation)

        // Both routes should get the same fallback duration
        #expect(oralDuration?.total?.min == 240)
        #expect(oralDuration?.total?.max == 480)
        #expect(insuffDuration?.total?.min == 240)
        #expect(insuffDuration?.total?.max == 480)

        // Both routes should get the same fallback onset
        #expect(oralDuration?.onset?.min == 30)
        #expect(insuffDuration?.onset?.min == 30)
    }

    @Test("Mixed format with missing colon parses both routes")
    func mixedFormatNoColon() throws {
        let drug = try decodeDrug("""
        {
            "name": "test",
            "properties": {
                "duration": "Oral: 6-12 hours | Insufflated 2-5 hours."
            },
            "formatted_dose": {
                "Oral": {"Common": "50mg"},
                "Insufflated": {"Common": "25mg"}
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)

        let oralDuration = substance.duration(for: .oral)
        let insuffDuration = substance.duration(for: .insufflation)

        // Oral: 6-12 hours = 360-720 minutes
        #expect(oralDuration?.total?.min == 360)
        #expect(oralDuration?.total?.max == 720)

        // Insufflated: 2-5 hours = 120-300 minutes
        #expect(insuffDuration?.total?.min == 120)
        #expect(insuffDuration?.total?.max == 300)
    }

    @Test("Plugged route maps to rectal")
    func pluggedMapsToRectal() throws {
        let drug = try decodeDrug("""
        {
            "name": "test",
            "properties": {
                "onset": "Oral: 20-75 minutes | Plugged: 5-20 minutes",
                "duration": "Oral: 4-8 hours | Plugged: 3-5 hours"
            },
            "formatted_dose": {
                "Oral": {"Common": "20mg"},
                "Rectal": {"Common": "15mg"}
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)

        let rectalDuration = substance.duration(for: .rectal)

        // "Plugged: 3-5 hours" should map to rectal route = 180-300 minutes
        #expect(rectalDuration?.total?.min == 180)
        #expect(rectalDuration?.total?.max == 300)

        // "Plugged: 5-20 minutes" onset
        #expect(rectalDuration?.onset?.min == 5)
        #expect(rectalDuration?.onset?.max == 20)
    }

    @Test("mg/kg-scaled doses produce route with empty doses but preserved duration")
    func kgScaledDosesKeepDuration() throws {
        // Mirrors TripSit's DXM payload: doses are body-weight-scaled, but
        // duration is still a usable per-route pharmacokinetic profile.
        let drug = try decodeDrug("""
        {
            "name": "dxm",
            "pretty_name": "Dextromethorphan",
            "categories": ["dissociative"],
            "properties": {
                "onset": "Oral: 30-60 minutes",
                "duration": "Oral: 4-8 hours"
            },
            "formatted_dose": {
                "Oral": {
                    "Light": "1.5-2.5mg/kg",
                    "Common": "2.5-7.5mg/kg",
                    "Strong": "7.5-15mg/kg"
                }
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)

        // Route is preserved (not silently dropped)
        #expect(substance.routes.contains { $0.route == .oral })

        // Doses are intentionally empty — the mg/kg values would be dangerously
        // misinterpreted as absolute mg. A per-substance override supplies them.
        let oral = substance.routes.first { $0.route == .oral }
        #expect(oral?.doses.threshold == nil)
        #expect(oral?.doses.light == nil)
        #expect(oral?.doses.common == nil)

        // Duration survives — this is the whole point of the fix.
        let duration = substance.duration(for: .oral)
        #expect(duration?.total?.min == 240)
        #expect(duration?.total?.max == 480)
        #expect(duration?.onset?.min == 30)
        #expect(duration?.onset?.max == 60)
    }

    @Test("Route with onset but no duration still produces a profile")
    func onsetOnlyRoute() throws {
        let drug = try decodeDrug("""
        {
            "name": "test",
            "properties": {
                "onset": "Oral: 30-60 minutes | Insufflated: 5-10 minutes"
            },
            "formatted_dose": {
                "Oral": {"Common": "100mg"},
                "Insufflated": {"Common": "50mg"}
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)

        // Both routes should have duration profiles (with estimated totals)
        #expect(substance.duration(for: .oral) != nil)
        #expect(substance.duration(for: .insufflation) != nil)

        // Onsets should differ
        #expect(substance.duration(for: .oral)?.onset?.min == 30)
        #expect(substance.duration(for: .insufflation)?.onset?.min == 5)
    }

    // MARK: - Mixed-unit dose parsing

    @Test("Mixed mass units across dose levels normalise to the smallest unit")
    func mixedUnitsNormaliseToSmallest() throws {
        // Mirrors TripSit's aspirin payload: Threshold/Light/Common in mg,
        // Heavy in g. Without normalisation, heavy=1.6 (numeric) would label
        // any normal aspirin dose as Heavy.
        let drug = try decodeDrug("""
        {
            "name": "aspirin",
            "categories": ["analgesic"],
            "properties": {
                "duration": "4-8 hours"
            },
            "formatted_dose": {
                "Oral": {
                    "Threshold": "50mg",
                    "Light": "75mg-81mg",
                    "Common": "325mg-650mg",
                    "Heavy": "1.6g"
                }
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)
        let oral = substance.routes.first { $0.route == .oral }!
        #expect(oral.unit == "mg")
        #expect(oral.doses.threshold == 50)
        #expect(oral.doses.light?.upperBound == 81)
        #expect(oral.doses.common?.upperBound == 650)
        #expect(oral.doses.heavy == 1600)  // 1.6g converted to mg
        // A standard 325 mg dose should classify as Common, not Heavy.
        #expect(oral.doses.level(for: 325) == .common)
    }

    @Test("All-mg levels keep mg as the unit (no false normalisation)")
    func allMgLevelsKeepMg() throws {
        let drug = try decodeDrug("""
        {
            "name": "caffeine",
            "formatted_dose": {
                "Oral": {
                    "Threshold": "20mg",
                    "Light": "20-50mg",
                    "Common": "50-150mg",
                    "Heavy": "400mg"
                }
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)
        let oral = substance.routes.first { $0.route == .oral }!
        #expect(oral.unit == "mg")
        #expect(oral.doses.heavy == 400)
    }

    @Test("Non-mass units (units/drinks/hits) pass through unchanged")
    func nonMassUnitsPassThrough() throws {
        let drug = try decodeDrug("""
        {
            "name": "alcohol",
            "formatted_dose": {
                "Oral": {
                    "Light": "1-2units",
                    "Common": "2-4units",
                    "Heavy": "5-6units"
                }
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)
        let oral = substance.routes.first { $0.route == .oral }!
        #expect(oral.unit == "units")
        #expect(oral.doses.heavy == 5)
    }

    // MARK: - Route timing without dose data

    @Test("Routes with duration but no dose data still produce a timed route")
    func timingOnlyRouteIsMaterialised() throws {
        // TripSit's cannabis payload publishes durations for both Smoked and
        // Oral but dose data only for Smoked. Without the fix, the Oral
        // duration is parsed and then discarded, and Substance.resolveDuration
        // falls back to the smoked timeline for any oral dose.
        let drug = try decodeDrug("""
        {
            "name": "cannabis",
            "categories": ["psychedelic", "depressant"],
            "properties": {
                "onset": "Smoked: 1-10 minutes | Oral: 30-120 minutes",
                "duration": "Smoked: 1-4 hours | Oral: 4-10 hours"
            },
            "formatted_dose": {
                "Smoked": {
                    "Light": "10-20mg",
                    "Common": "20-60mg",
                    "Strong": "60-100mg"
                }
            }
        }
        """)
        let substance = TripSitAPI.toSubstance(drug)

        // Both routes should be present.
        #expect(substance.routes.contains { $0.route == .inhalation })
        #expect(substance.routes.contains { $0.route == .oral })

        // Smoked timing is its own, not borrowed from oral.
        let smoked = substance.duration(for: .inhalation)
        #expect(smoked?.total?.min == 60)   // 1 hour
        #expect(smoked?.total?.max == 240)  // 4 hours
        #expect(smoked?.onset?.min == 1)

        // Oral timing is the slower edibles profile.
        let oral = substance.duration(for: .oral)
        #expect(oral?.total?.min == 240)    // 4 hours
        #expect(oral?.total?.max == 600)    // 10 hours
        #expect(oral?.onset?.min == 30)
    }
}
