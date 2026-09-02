import SwiftUI

/// The Journal timeline's display preferences, persisted in the app-group
/// defaults under the keys the rest of the app already reads.
///
/// A `DynamicProperty` rather than an `@Observable` model, because every key
/// here is *also* read through `@AppStorage` elsewhere — the pushed timeline
/// screen, the session detail, Journal and Health settings, the onboarding
/// health step. A model holding cached copies would go stale the moment one of
/// those wrote to the store; nesting the wrappers keeps each read live while
/// collapsing seven declarations on the view into one.
struct TimelinePreferences: DynamicProperty {
    /// Points per hour multiplier for the vertical strip.
    @AppStorage("timelineZoom", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    var zoom = 1.0

    /// Collapse the empty stretches between clusters.
    @AppStorage("timelineCompression", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    var compressGaps = true

    /// Draw the modeled concentration curves behind the bubbles.
    @AppStorage("timelinePKCurves", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    var pkCurves = false

    /// Show the hour axis down the left edge.
    @AppStorage("timelineShowsAxis", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    var showsAxis = true

    /// How much of a dose each bubble spells out.
    @AppStorage("timelineBubbleStyle", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    var bubbleStyle = TimelineBubbleStyle.full

    /// Overlay heart rate from HealthKit.
    @AppStorage("showSessionVitals", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    var showsVitals = false

    /// The day cards' redose-stacking preference. Read here so the timeline
    /// prewarm computes geometry under the same key the cards look up.
    @AppStorage("stackRedoses", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    var stackRedoses = true

    /// The options the timeline layout is keyed on — folded into the rebuild
    /// key so a display change re-lays the strip and nothing else does.
    var layoutSignature: String {
        "\(zoom)|\(compressGaps)|\(pkCurves)|\(showsAxis)|\(bubbleStyle.rawValue)|\(showsVitals)"
    }
}
