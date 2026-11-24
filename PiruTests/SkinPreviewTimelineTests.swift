import SwiftUI
import Testing
@testable import Piru

@MainActor
@Suite("Skin preview timeline")
struct SkinPreviewTimelineTests {
    @Test
    func `The fixed day lays out through the real builder`() async {
        let timeline = SkinPreviewTimeline()
        await timeline.prepare()
        #expect(!timeline.days.isEmpty)
        #expect(timeline.days.allSatisfy { !$0.cardGroups.isEmpty })
        #expect(timeline.days.allSatisfy { !$0.isToday })
    }

    @Test
    func `Every skin on offer renders a picture, in both schemes`() async {
        let timeline = SkinPreviewTimeline()
        await timeline.prepare()
        for skin in Skin.available {
            for dark in [false, true] {
                let picture = await timeline.snapshot(for: skin, dark: dark, scale: 2)
                #expect(picture != nil, "\(skin.rawValue), dark: \(dark)")
            }
        }
    }

    @Test
    func `Another wording lays the day out again and drops the pictures taken in the old one`() async {
        let timeline = SkinPreviewTimeline()
        let english = SkinPreviewTimeline.Wording(localization: "en", englishNames: false)
        let chinese = SkinPreviewTimeline.Wording(localization: "zh-Hans", englishNames: false)
        let englishNames = SkinPreviewTimeline.Wording(localization: "zh-Hans", englishNames: true)

        _ = await timeline.snapshot(for: .piru, dark: false, scale: 1, in: english)
        #expect(timeline.snapshotCount == 1)

        await timeline.prepare(in: chinese)
        #expect(timeline.preparedWording == chinese)
        #expect(timeline.snapshotCount == 0)
        #expect(!timeline.days.isEmpty)
        #expect(await timeline.snapshot(for: .piru, dark: false, scale: 1, in: chinese) != nil)
        #expect(timeline.snapshotCount == 1)

        await timeline.prepare(in: englishNames)
        #expect(timeline.preparedWording == englishNames)
        #expect(timeline.snapshotCount == 0)
    }

    @Test
    func `A warm-up cancelled before it starts renders nothing`() async {
        let timeline = SkinPreviewTimeline()
        await timeline.prepare()
        let warm = Task { await timeline.warm(dark: false, scale: 1) }
        warm.cancel()
        await warm.value
        #expect(timeline.snapshotCount == 0)
    }

    @Test
    func `A render leaves the app wearing what it was wearing`() async {
        let timeline = SkinPreviewTimeline()
        await timeline.prepare()
        let before = SkinStore.shared.current
        let other = Skin.available.first { $0 != before } ?? before
        _ = await timeline.snapshot(for: other, dark: false, scale: 2)
        #expect(SkinStore.shared.current == before)
        #expect(SkinStore.shared.rendering(as: other) { SkinStore.shared.current } == other)
    }
}
