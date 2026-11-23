import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Piru

@Suite("TimelineOpeningTarget")
@MainActor
struct TimelineOpeningTargetTests {
    private func slice(day: Int, nowY: CGFloat?, height: CGFloat) -> TimelineDayLayout {
        TimelineDayLayout(
            date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
            isToday: nowY != nil,
            style: .init(showsAxis: true, bubbleStyle: .full, pkMode: false),
            showsLiveEdge: nowY != nil,
            breakAbove: 0,
            fadesAxisBelow: false,
            cardGroups: [],
            envelopes: [],
            series: [],
            doseDots: [],
            connectors: [],
            noteMarks: [],
            milestones: [],
            wordState: nil,
            heartRate: [],
            hourTicks: [],
            nowY: nowY,
            mapHeight: height,
            totalHeight: height,
        )
    }

    /// Where Now lands on screen for a target: the slice's top sits at a·(V − H).
    private func nowOnScreen(_ target: TimelineOpeningTarget, nowY: CGFloat, sliceHeight: CGFloat, viewport: CGFloat) -> CGFloat {
        target.anchor.y * (viewport - sliceHeight) + nowY
    }

    @Test
    func `Now far down a tall slice lands a third of the way down the screen`() throws {
        let days = [slice(day: 2, nowY: 1_400, height: 3_000), slice(day: 1, nowY: nil, height: 2_000)]
        let target = try #require(TimelineOpeningTarget.resolve(days, viewportHeight: 900))
        #expect(target.id == days[0].id)
        let onScreen = nowOnScreen(target, nowY: 1_400, sliceHeight: 3_000, viewport: 900)
        #expect(abs(onScreen - 900 * TimelineOpeningTarget.screenFraction) < 0.5)
    }

    @Test
    func `A list splits the Now slice so its lower row opens with Now a third of the way down`() throws {
        // A long-acting dose: ~13 h of projection above Now on a short screen
        // under the pinned meds card.
        let days = [slice(day: 2, nowY: 1_640, height: 2_200), slice(day: 1, nowY: nil, height: 2_000)]
        let viewport: CGFloat = 418
        let split = try #require(TimelineOpeningTarget.split(days, viewportHeight: viewport))
        #expect(split.id == days[0].id)
        // The lower row's top is at the screen's top, so Now sits nowY − y down.
        #expect(abs((1_640 - split.y) - viewport * TimelineOpeningTarget.screenFraction) < 1)
    }

    @Test
    func `Nothing active leaves the slice whole`() {
        let days = [slice(day: 2, nowY: 40, height: 1_200)]
        #expect(TimelineOpeningTarget.split(days, viewportHeight: 418) == nil)
    }

    @Test
    func `An unmeasured screen leaves the slice whole`() {
        let days = [slice(day: 2, nowY: 1_400, height: 3_000)]
        #expect(TimelineOpeningTarget.split(days, viewportHeight: 0) == nil)
    }

    @Test
    func `Now near the top opens the strip at its top`() {
        let days = [slice(day: 2, nowY: 60, height: 3_000)]
        #expect(TimelineOpeningTarget.resolve(days, viewportHeight: 900) == nil)
    }

    @Test
    func `A strip without Now opens at its top`() {
        let days = [slice(day: 2, nowY: nil, height: 3_000)]
        #expect(TimelineOpeningTarget.resolve(days, viewportHeight: 900) == nil)
    }

    @Test
    func `The anchor stays inside the slice`() throws {
        let days = [slice(day: 2, nowY: 590, height: 600)]
        let target = try #require(TimelineOpeningTarget.resolve(days, viewportHeight: 900))
        #expect((0 ... 1).contains(target.anchor.y))
    }
}
