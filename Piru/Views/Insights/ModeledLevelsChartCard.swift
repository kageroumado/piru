import SwiftUI

/// The Modeled Levels card on the In Your Body screen: the body-load lanes and
/// their scrub readout. Which lanes it draws is ``ModeledLevelsFilter``'s, edited
/// from the screen's toolbar.
struct ModeledLevelsChartCard: View {
    let trail: BodyLoadTrail
    let range: UsageTimeRange
    let filter: ModeledLevelsFilter

    @State private var selectedDate: Date?

    var body: some View {
        let markers = filter.markers(trail.series)
        let chartSeries = filter.chartSeries(trail.series)
        UsageSectionCard(title: "Modeled levels over time") {
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
            }
        }
        .onChange(of: range) { selectedDate = nil }
    }
}
