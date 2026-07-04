import ActivityKit
import SwiftUI
import WidgetKit

struct PiruLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PiruActivityAttributes.self) { context in
            let url = Self.deepLinkURL(for: context.state.activeSubstances)
            LockScreenView(context: context)
                .widgetURL(url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                        .widgetURL(Self.deepLinkURL(for: context.state.activeSubstances))
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
        }
    }

    /// Build a deep link URL based on the active substances.
    /// Single entry → links to that specific dose; multiple → links to the day view.
    private static func deepLinkURL(for substances: [ActiveSubstanceState]) -> URL {
        if substances.count == 1, let sub = substances.first {
            let ts = Int(sub.doseTimestamp.timeIntervalSince1970)
            return URL(string: "piru://entry/\(ts)")!
        } else {
            return URL(string: "piru://day")!
        }
    }
}

// MARK: - Preview Fixtures

#if DEBUG

    extension PiruActivityAttributes {
        static var preview: PiruActivityAttributes {
            PiruActivityAttributes(startTime: .now)
        }
    }

    extension PiruActivityAttributes.ContentState {
        private static func caffeine(minutesAgo: Double) -> ActiveSubstanceState {
            ActiveSubstanceState(
                substanceName: "Caffeine",
                colorHex: "66CCFF",
                doseTimestamp: .now.addingTimeInterval(-minutesAgo * 60),
                amount: 120,
                unit: "mg",
                route: "oral",
                onsetEndMinutes: 10,
                comeupEndMinutes: 45,
                peakEndMinutes: 150,
                offsetEndMinutes: 320,
                afterglowEndMinutes: nil,
                totalMinutes: 320,
                doseIntensity: 0.6,
                tachyphylaxis: 0.3,
            )
        }

        private static func theanine(minutesAgo: Double) -> ActiveSubstanceState {
            ActiveSubstanceState(
                substanceName: "L-Theanine",
                colorHex: "AAFF99",
                doseTimestamp: .now.addingTimeInterval(-minutesAgo * 60),
                amount: 200,
                unit: "mg",
                route: "oral",
                onsetEndMinutes: 20,
                comeupEndMinutes: 40,
                peakEndMinutes: 120,
                offsetEndMinutes: 240,
                afterglowEndMinutes: nil,
                totalMinutes: 240,
                doseIntensity: 0.5,
            )
        }

        private static func ibuprofen(minutesAgo: Double) -> ActiveSubstanceState {
            ActiveSubstanceState(
                substanceName: "Ibuprofen",
                colorHex: "FFAACC",
                doseTimestamp: .now.addingTimeInterval(-minutesAgo * 60),
                amount: 400,
                unit: "mg",
                route: "oral",
                onsetEndMinutes: 20,
                comeupEndMinutes: 45,
                peakEndMinutes: 120,
                offsetEndMinutes: 360,
                afterglowEndMinutes: nil,
                totalMinutes: 360,
                doseIntensity: 0.55,
            )
        }

        /// Just dosed — onset, progress ring near empty.
        static var justDosed: Self {
            PiruActivityAttributes.ContentState(
                activeSubstances: [caffeine(minutesAgo: 8)],
                lastUpdated: .now,
            )
        }

        /// Mid-session, single substance — around peak.
        static var midSession: Self {
            PiruActivityAttributes.ContentState(
                activeSubstances: [caffeine(minutesAgo: 150)],
                lastUpdated: .now,
            )
        }

        /// Multiple substances — exercises header chips, gradient ring, stacked curves.
        static var multiSubstance: Self {
            PiruActivityAttributes.ContentState(
                activeSubstances: [
                    caffeine(minutesAgo: 100),
                    theanine(minutesAgo: 100),
                    ibuprofen(minutesAgo: 30),
                ],
                lastUpdated: .now,
            )
        }

        /// Near the end of the session — progress ring almost full.
        static var windingDown: Self {
            PiruActivityAttributes.ContentState(
                activeSubstances: [caffeine(minutesAgo: 290)],
                lastUpdated: .now,
            )
        }
    }

    // MARK: - Previews

    #Preview("Lock Screen", as: .content, using: PiruActivityAttributes.preview) {
        PiruLiveActivity()
    } contentStates: {
        PiruActivityAttributes.ContentState.justDosed
        PiruActivityAttributes.ContentState.midSession
        PiruActivityAttributes.ContentState.multiSubstance
        PiruActivityAttributes.ContentState.windingDown
    }

    #Preview("Island Expanded", as: .dynamicIsland(.expanded), using: PiruActivityAttributes.preview) {
        PiruLiveActivity()
    } contentStates: {
        PiruActivityAttributes.ContentState.justDosed
        PiruActivityAttributes.ContentState.midSession
        PiruActivityAttributes.ContentState.multiSubstance
        PiruActivityAttributes.ContentState.windingDown
    }

    #Preview("Island Compact", as: .dynamicIsland(.compact), using: PiruActivityAttributes.preview) {
        PiruLiveActivity()
    } contentStates: {
        PiruActivityAttributes.ContentState.justDosed
        PiruActivityAttributes.ContentState.midSession
        PiruActivityAttributes.ContentState.multiSubstance
        PiruActivityAttributes.ContentState.windingDown
    }

    #Preview("Island Minimal", as: .dynamicIsland(.minimal), using: PiruActivityAttributes.preview) {
        PiruLiveActivity()
    } contentStates: {
        PiruActivityAttributes.ContentState.justDosed
        PiruActivityAttributes.ContentState.midSession
        PiruActivityAttributes.ContentState.multiSubstance
        PiruActivityAttributes.ContentState.windingDown
    }

#endif
