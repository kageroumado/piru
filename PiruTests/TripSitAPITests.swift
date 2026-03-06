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
}
