import Foundation
import Testing
@testable import Piru

@Suite("Dose time presets")
struct DoseTimePresetsTests {
    @Test
    func `parse reads a comma-joined list`() {
        #expect(DoseTimeDefaults.parse("15,30,60,120") == [15, 30, 60, 120])
    }

    @Test
    func `parse preserves user order rather than sorting`() {
        #expect(DoseTimeDefaults.parse("60,15,300") == [60, 15, 300])
    }

    @Test
    func `parse tolerates whitespace`() {
        #expect(DoseTimeDefaults.parse(" 15 , 30 ,60 ") == [15, 30, 60])
    }

    @Test
    func `parse falls back to defaults for empty or garbled input`() {
        #expect(DoseTimeDefaults.parse("") == DoseTimeDefaults.defaultChoices)
        #expect(DoseTimeDefaults.parse("abc,,-") == DoseTimeDefaults.defaultChoices)
    }

    @Test
    func `parse drops out-of-range values`() {
        // 0 and 2000 (> 24h) are out of range; 45 survives.
        #expect(DoseTimeDefaults.parse("0,45,2000") == [45])
    }

    @Test
    func `format round-trips through parse`() {
        let choices = [10, 90, 600]
        #expect(DoseTimeDefaults.parse(DoseTimeDefaults.format(choices)) == choices)
    }

    @Test
    func `defaultRaw matches defaultChoices`() {
        #expect(DoseTimeDefaults.parse(DoseTimeDefaults.defaultRaw) == DoseTimeDefaults.defaultChoices)
    }

    @Test
    func `offsetLabel keeps whole hours in hours and leftover minutes in minutes`() {
        #expect(TrayTime.offsetLabel(minutes: 30) == "30 min ago")
        #expect(TrayTime.offsetLabel(minutes: 60) == "1h ago")
        #expect(TrayTime.offsetLabel(minutes: 120) == "2h ago")
        // 90 min must not round down to a wrong "1h ago".
        #expect(TrayTime.offsetLabel(minutes: 90) == "90 min ago")
    }
}
