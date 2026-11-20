import SwiftUI

/// The schedule choice offered for a med: a recurring cadence, or as-needed
/// (PRN). The model keeps as-needed as a separate axis from `DoseFrequency`
/// (`isAsNeeded`); the add form and the detail screen fold the two into one
/// picker so the schedule stays one decision.
enum MedScheduleChoice: Hashable {
    case frequency(DoseFrequency)
    case asNeeded
}

/// The Specific Days chips: one toggle per weekday, `selection` holding
/// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    private static let weekdaySymbols: [(index: Int, short: String, full: String)] = {
        let cal = Calendar.current
        return (1 ... 7).map { ($0, cal.shortWeekdaySymbols[$0 - 1], cal.weekdaySymbols[$0 - 1]) }
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Days")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.sm) {
                ForEach(Self.weekdaySymbols, id: \.index) { day in
                    let isSelected = selection.contains(day.index)
                    Button {
                        if isSelected {
                            selection.remove(day.index)
                        } else {
                            selection.insert(day.index)
                        }
                    } label: {
                        Text(String(day.short.prefix(2)))
                            .font(.caption.weight(.semibold))
                            .selectableChip(isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    // Cancels the chip's hit-target frame back to the visible
                    // circle so the row's layout is unchanged.
                    .padding(-5)
                    .accessibilityLabel(day.full)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
