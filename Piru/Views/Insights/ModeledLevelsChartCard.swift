import SwiftUI

/// The Modeled Levels card on the In Your Body screen: the body-load lanes and
/// their scrub readout. Which lanes it draws is ``ModeledLevelsFilter``'s, edited
/// from the screen's toolbar; with no pick, a closing row says how many of the
/// trail's substances are drawn and shows the rest.
struct ModeledLevelsChartCard: View {
    let trail: BodyLoadTrail
    let range: UsageTimeRange
    let filter: ModeledLevelsFilter

    @State private var selectedDate: Date?

    var body: some View {
        let markers = filter.markers(trail.series)
        let chartSeries = filter.chartSeries(trail.series)
        let total = filter.substanceCount(trail.series)
        let drawn = filter.substanceCount(chartSeries)
        UsageSectionCard(title: Text("Modeled levels over time"), subtitle: rangeSubtitle) {
            if chartSeries.isEmpty {
                Text("None of the chosen substances have a modeled curve in this range")
                    .captionSecondary()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.xxl)
            } else {
                BodyLoadChart(series: chartSeries, markers: markers, dates: trail.dates, selectedDate: $selectedDate)
                if let selectedDate {
                    BodyLoadReadout(series: chartSeries, markers: markers, date: selectedDate)
                }
                if !filter.isFiltering, drawn < total {
                    HStack {
                        Text("Showing \(drawn) of \(total)")
                            .captionSecondary()
                        Spacer()
                        Button("Show All") { filter.showAll(trail.series) }
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .onChange(of: range) { selectedDate = nil }
        #if DEBUG
            .task { selectedDate = ScreenshotTour.takeStagedSelection(.modeledLevels) ?? selectedDate }
        #endif
    }

    /// The range the toolbar chose, printed under the title.
    private var rangeSubtitle: LocalizedStringKey {
        if let days = range.days {
            "Last \(days) Days"
        } else {
            "All Time"
        }
    }
}
