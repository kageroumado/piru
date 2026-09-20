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
                #expect(timeline.snapshot(for: skin, dark: dark, scale: 2) != nil, "\(skin.rawValue), dark: \(dark)")
            }
        }
    }

    @Test
    func `A render leaves the app wearing what it was wearing`() async {
        let timeline = SkinPreviewTimeline()
        await timeline.prepare()
        let before = SkinStore.shared.current
        let other = Skin.available.first { $0 != before } ?? before
        _ = timeline.snapshot(for: other, dark: false, scale: 2)
        #expect(SkinStore.shared.current == before)
        #expect(SkinStore.shared.rendering(as: other) { SkinStore.shared.current } == other)
    }
}
