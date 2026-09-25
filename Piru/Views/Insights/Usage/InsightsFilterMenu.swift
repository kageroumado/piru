import SwiftUI

/// The toolbar filter shared by Usage and Modeled Levels: a time-range picker,
/// any screen-specific pickers, and a row opening ``SubstanceFilterSheet``.
///
/// The screen owns the range, the substance selection and the sheet; this view
/// is only the menu and its glyph.
struct InsightsFilterMenu<Extra: View>: View {
    @Binding var range: UsageTimeRange
    /// How many substances the filter keeps, 0 for all.
    let selectedCount: Int
    /// Whether there are enough substances for the substance row to mean anything.
    let offersSubstances: Bool
    let showSubstances: () -> Void
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        Menu {
            Picker("Time Range", selection: $range) {
                ForEach(UsageTimeRange.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            extra()
            if offersSubstances {
                Button(action: showSubstances) {
                    // No leading icon (the pickers above carry none) and a
                    // trailing ellipsis — the HIG signal for a row that opens
                    // further UI (here, the substance-filter sheet) before it
                    // takes effect, rather than toggling a value inline.
                    Text(verbatim: substancesMenuLabel + "\u{2026}")
                }
            }
        } label: {
            label
        }
    }

    /// The toolbar glyph. `line.3.horizontal.decrease` has no `.fill` variant and
    /// a Menu button can't be tinted, so the active state is carried by a
    /// selected-count badge beside the glyph rather than a color or fill swap.
    @ViewBuilder
    private var label: some View {
        if selectedCount > 0 {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(verbatim: "\(selectedCount)")
            }
            .accessibilityLabel(Text("Filter"))
            .accessibilityValue(Text("Substances (\(selectedCount))"))
        } else {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
    }

    /// The substance-picker menu row: the count when a subset is active, else "all".
    private var substancesMenuLabel: String {
        selectedCount > 0
            ? String(localized: "Substances (\(selectedCount))")
            : String(localized: "All Substances")
    }
}

extension InsightsFilterMenu where Extra == EmptyView {
    init(
        range: Binding<UsageTimeRange>,
        selectedCount: Int,
        offersSubstances: Bool,
        showSubstances: @escaping () -> Void,
    ) {
        self.init(
            range: range,
            selectedCount: selectedCount,
            offersSubstances: offersSubstances,
            showSubstances: showSubstances,
            extra: { EmptyView() },
        )
    }
}
