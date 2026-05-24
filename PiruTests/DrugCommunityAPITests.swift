import Testing
import Foundation
@testable import Piru

@Suite("DrugCommunityAPI")
struct DrugCommunityAPITests {

    // MARK: - Dose range parsing

    @Test("Parses a basic en-dash dose range")
    func dashRange() {
        let block = DrugCommunityAPI.Response.DoseRanges(
            threshold: "15\u{2013}25 mg",
            light: "25\u{2013}40 mg",
            common: "40\u{2013}70 mg",
            strong: "70\u{2013}100 mg",
            heavy: "100+ mg"
        )
        let range = DrugCommunityAPI.parseDoseRange(block)
        #expect(range.threshold == 15)
        #expect(range.light?.lowerBound == 25)
        #expect(range.light?.upperBound == 40)
        #expect(range.common?.lowerBound == 40)
        #expect(range.common?.upperBound == 70)
        #expect(range.strong?.lowerBound == 70)
        #expect(range.strong?.upperBound == 100)
        #expect(range.heavy == 100)
    }

    @Test("Handles a regular hyphen-separated range")
    func plainHyphen() {
        let block = DrugCommunityAPI.Response.DoseRanges(
            threshold: "1-3 mg",
            light: nil,
            common: "5-10 mg",
            strong: nil,
            heavy: nil
        )
        let range = DrugCommunityAPI.parseDoseRange(block)
        #expect(range.threshold == 1)
        #expect(range.common?.lowerBound == 5)
        #expect(range.common?.upperBound == 10)
    }

    @Test("Empty/nil block returns empty range")
    func emptyBlock() {
        #expect(DrugCommunityAPI.parseDoseRange(nil).threshold == nil)
        let empty = DrugCommunityAPI.Response.DoseRanges(
            threshold: nil, light: nil, common: nil, strong: nil, heavy: nil
        )
        #expect(DrugCommunityAPI.parseDoseRange(empty).threshold == nil)
    }

    @Test("Decimal values parse")
    func decimal() {
        let block = DrugCommunityAPI.Response.DoseRanges(
            threshold: "0.5 mg",
            light: "1.5\u{2013}3 mg",
            common: nil,
            strong: nil,
            heavy: nil
        )
        let range = DrugCommunityAPI.parseDoseRange(block)
        #expect(range.threshold == 0.5)
        #expect(range.light?.lowerBound == 1.5)
        #expect(range.light?.upperBound == 3)
    }

    // MARK: - Duration curve

    @Test("Duration curve converts hours → minutes")
    func durationCurve() {
        let curve = DrugCommunityAPI.Response.DurationCurve(
            total_duration: .init(min: 4, max: 6, start: nil, end: nil),
            onset: .init(min: nil, max: nil, start: 0.08, end: 0.25),
            peak: .init(min: nil, max: nil, start: 0.5, end: 1.5),
            offset: .init(min: nil, max: nil, start: 1.5, end: 4),
            after_effects: .init(min: nil, max: nil, start: 4, end: 6)
        )
        guard let profile = DrugCommunityAPI.makeDurationProfile(from: curve) else {
            Issue.record("Expected a profile")
            return
        }
        #expect(profile.total?.min == 240)        // 4 h × 60
        #expect(profile.total?.max == 360)        // 6 h × 60
        #expect(profile.onset?.min == 0.08 * 60)
        #expect(profile.peak?.max == 90)          // 1.5 h × 60
    }

    @Test("All-nil curve produces nil profile")
    func emptyCurve() {
        let curve = DrugCommunityAPI.Response.DurationCurve(
            total_duration: nil, onset: nil, peak: nil, offset: nil, after_effects: nil
        )
        #expect(DrugCommunityAPI.makeDurationProfile(from: curve) == nil)
    }

    // MARK: - Half-life parsing

    @Test("Half-life with explicit hours")
    func halfLifeHours() {
        #expect(DrugCommunityAPI.parseHalfLifeMinutes("3-6 h") == 180)
        #expect(DrugCommunityAPI.parseHalfLifeMinutes("4 hours") == 240)
    }

    @Test("Half-life with explicit minutes")
    func halfLifeMinutes() {
        #expect(DrugCommunityAPI.parseHalfLifeMinutes("30 minutes") == 30)
    }

    @Test("Half-life with days")
    func halfLifeDays() {
        #expect(DrugCommunityAPI.parseHalfLifeMinutes("2 days") == 2880.0)
    }

    @Test("Half-life unknown returns nil")
    func halfLifeUnknown() {
        #expect(DrugCommunityAPI.parseHalfLifeMinutes(nil) == nil)
        #expect(DrugCommunityAPI.parseHalfLifeMinutes("") == nil)
    }

    // MARK: - Name list

    @Test("Bundle resource loads")
    func nameListLoads() {
        #expect(DrugCommunityAPI.allNames.count > 100)
        // Sanity-check a couple of known entries (extracted at integration time).
        #expect(DrugCommunityAPI.allNames.contains { $0.contains("DMXE") || $0.contains("Deoxymethoxetamine") })
    }
}
