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
