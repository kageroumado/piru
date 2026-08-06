import SwiftUI
import WidgetKit

@main
struct PiruWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayMedsWidget()
        TodaySummaryWidget()
        RecentDoseWidget()
        InventoryWidget()
        NextDoseWidget()
    }
}
