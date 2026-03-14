import SwiftUI
import WidgetKit

@main
struct PiruWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodaySummaryWidget()
        RecentDoseWidget()
    }
}
