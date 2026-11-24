import CoreGraphics
import Foundation
import Testing
@testable import Piru

@Suite("TimelineGutterLabels")
struct TimelineGutterLabelsTests {
    // MARK: - Frames

    @Test
    func `Frames touching within the gap collide`() {
        let a = TimelineGutterLabels.Frame(center: 100, height: 12)
        let b = TimelineGutterLabels.Frame(center: 113, height: 12) // 1 pt apart, gap is 6
        #expect(a.collides(with: b))
        #expect(b.collides(with: a))
    }

    @Test
    func `Frames separated by more than the gap are clear`() {
        let a = TimelineGutterLabels.Frame(center: 100, height: 12)
        let b = TimelineGutterLabels.Frame(center: 120, height: 12) // 8 pt apart
        #expect(!a.collides(with: b))
    }

    // MARK: - Dose capsules vs Now and each other

    @Test
    func `Capsules clear of each other and of Now sit at their doses`() {
        let centers = TimelineGutterLabels.doseLabelCenters(doseYs: [100, 140, 200], nowY: 40)
        #expect(centers == [100, 140, 200])
    }

    @Test
    func `A capsule on the newer one is stacked just under it`() {
        // 22 pt capsules with a 2 pt gap: the second sits 24 pt under the first.
        let centers = TimelineGutterLabels.doseLabelCenters(doseYs: [100, 115], nowY: nil)
        #expect(centers == [100, 124])
    }

    @Test
    func `A capsule too far from its dot once stacked is left off and takes no room`() {
        // 104 → pushed to 124 is 20 pt off its dot, past the 11 pt limit; the
        // next one stacks under the first, not the dropped one.
        let centers = TimelineGutterLabels.doseLabelCenters(doseYs: [100, 104, 120], nowY: nil)
        #expect(centers[0] == 100)
        #expect(centers[1] == nil)
        #expect(centers[2] == 124)
    }

    @Test
    func `The newest dose under Now is pushed clear of the Now tag rather than hidden`() {
        // Now's frame ends at 51; with the 6 pt gap a capsule starts at 57 → center 68.
        let centers = TimelineGutterLabels.doseLabelCenters(doseYs: [60, 200], nowY: 40)
        #expect(centers == [68, 200])
    }

    @Test
    func `A dose on the Now tag is left off`() {
        let centers = TimelineGutterLabels.doseLabelCenters(doseYs: [40, 44, 120], nowY: 40)
        #expect(centers == [nil, nil, 120])
    }

    @Test
    func `No two drawn capsules overlap`() {
        let doseYs: [CGFloat] = [60, 75, 89, 110, 131, 152, 180, 181, 230]
        let drawn = TimelineGutterLabels.doseLabelCenters(doseYs: doseYs, nowY: 40).compactMap(\.self)
        for (a, b) in zip(drawn, drawn.dropFirst()) {
            #expect(b - a >= TimelineGutterLabels.doseLabelHeight + TimelineGutterLabels.doseStackGap)
        }
        for (y, center) in zip(doseYs, TimelineGutterLabels.doseLabelCenters(doseYs: doseYs, nowY: 40)) {
            guard let center else { continue }
            #expect(center - y >= 0 && center - y <= TimelineGutterLabels.maximumDoseLabelDrift)
        }
    }

    @Test
    func `Every one-line mark shares the recipe's height`() {
        #expect(TimelineGutterLabels.hourLabelHeight == TimelineGutterMarkMetrics.singleLineHeight)
        #expect(TimelineGutterLabels.doseLabelHeight == TimelineGutterMarkMetrics.singleLineHeight)
        #expect(TimelineGutterLabels.nowLabelHeight == TimelineGutterMarkMetrics.singleLineHeight)
        #expect(TimelineGutterLabels.dayTagHeight == TimelineGutterMarkMetrics.twoLineHeight)
    }

    // MARK: - Hour labels vs everything above them

    @Test
    func `An hour label on the Now tag is suppressed`() {
        #expect(!TimelineGutterLabels.hourLabelFits(y: 40, doseYs: [], nowY: 40))
        #expect(!TimelineGutterLabels.hourLabelFits(y: 52, doseYs: [], nowY: 40))
    }

    @Test
    func `An hour label on a dose capsule is suppressed`() {
        #expect(!TimelineGutterLabels.hourLabelFits(y: 200, doseYs: [206], nowY: nil))
        // 22/2 + 22/2 + 6 = 28 → 27 pt away still touches.
        #expect(!TimelineGutterLabels.hourLabelFits(y: 227, doseYs: [200], nowY: nil))
    }

    @Test
    func `An hour label clear of both draws`() {
        #expect(TimelineGutterLabels.hourLabelFits(y: 200, doseYs: [240], nowY: 40))
        // 22/2 + 22/2 + 6 = 28 → 28 pt away is clear.
        #expect(TimelineGutterLabels.hourLabelFits(y: 228, doseYs: [200], nowY: nil))
    }

    @Test
    func `An hour label under the day tag is suppressed`() {
        // The tag reserves the top 44 pt; a 22 pt label needs its top edge
        // 6 pt below that → center ≥ 61.
        #expect(!TimelineGutterLabels.hourLabelFits(y: 50, doseYs: [], nowY: nil, reservedTop: 44))
        #expect(!TimelineGutterLabels.hourLabelFits(y: 60, doseYs: [], nowY: nil, reservedTop: 44))
        #expect(TimelineGutterLabels.hourLabelFits(y: 61, doseYs: [], nowY: nil, reservedTop: 44))
    }
}

@Suite("TimelineDayHeader")
struct TimelineDayHeaderTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test
    func `The date line carries the year only when it isn't this year's`() {
        let english = Locale(identifier: "en_US")
        let now = date(2026, 10, 12)
        let thisYear = TimelineDayHeader.dateText(date(2026, 10, 11), now: now, calendar: calendar, locale: english)
        #expect(!thisYear.contains("2026"))
        let ahead = TimelineDayHeader.dateText(date(2028, 10, 11), now: now, calendar: calendar, locale: english)
        #expect(ahead.contains("2028"))
        let behind = TimelineDayHeader.dateText(date(2025, 12, 31), now: now, calendar: calendar, locale: english)
        #expect(behind.contains("2025"))
    }
}
