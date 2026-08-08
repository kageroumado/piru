import Charts
import SwiftUI

// MARK: - Chart zoom

/// Give a dense time-series chart a fixed, horizontally scrollable window so it
/// can be read a slice at a time instead of as an unreadable comb.
///
/// `fullLength` is the chart's whole x-domain in data units (seconds for a
/// `Date` axis — its plottable stride is a `TimeInterval`); `window` is how much
/// of it to show at once. Below a domain that overflows the window the modifier
/// adds nothing, so short ranges render exactly as before.
///
/// Deliberately gesture-free. A pinch-to-zoom gesture layered onto a chart
/// inside the Usage screen's vertical `ScrollView` swallowed the page's own
/// drag — you couldn't scroll past the first such chart. `chartScrollableAxes`
/// on its own claims only horizontal drags, so a vertical swipe still scrolls
/// the page while a horizontal one pans the chart. That is the whole zoom
/// affordance here: pan a windowed view, no gesture that can fight the page.
struct ChartXScrollWindow: ViewModifier {
    let fullLength: Double
    let window: Double
    /// Where to open the scroll — the start of the initially visible window.
    /// Passing the most-recent window's start opens on the newest data, which is
    /// what a "trends" chart should lead with; `nil` opens at the oldest edge.
    var initialX: Date?

    private var overflows: Bool {
        fullLength > window * 1.05
    }

    func body(content: Content) -> some View {
        if overflows {
            content
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: window)
                .chartScrollPosition(initialX: initialX ?? Date(timeIntervalSince1970: 0))
        } else {
            content
        }
    }
}

extension View {
    /// Window a dense time chart into a horizontally scrollable slice. See
    /// ``ChartXScrollWindow``.
    func chartXScrollWindow(fullLength: Double, window: Double, initialX: Date? = nil) -> some View {
        modifier(ChartXScrollWindow(fullLength: fullLength, window: window, initialX: initialX))
    }
}

/// The default visible window for the Usage screen's scrollable time charts:
/// roughly a quarter, wide enough to read a season of shape at once and short
/// enough that a year no longer crushes into a few pixels per week.
let usageChartWindowSeconds: Double = 120 * 86_400

// MARK: - Index ↔ enum

/// Maps the plain indices the off-main aggregation works in back to the
/// main-actor enums the UI draws with. The aggregation can't hold these types
/// as dictionary keys (they're main-isolated under the target's default
/// isolation), so the boundary is crossed exactly here.
enum UsageAxes {
    static func category(_ index: Int) -> SubstanceCategory {
        let all = SubstanceCategory.allCases
        return all.indices.contains(index) ? all[index] : .other
    }

    static func route(_ index: Int) -> RouteOfAdministration {
        let all = RouteOfAdministration.allCases
        return all.indices.contains(index) ? all[index] : .other
    }

    static func doseLevel(_ index: Int) -> DoseLevel {
        switch index {
        case 0: .sub
        case 1: .threshold
        case 2: .light
        case 3: .common
        case 4: .strong
        default: .heavy
        }
    }

    /// Dose levels lightest → heaviest, the stacking order §4 draws bottom-up.
    static let doseLevelOrder: [Int] = [0, 1, 2, 3, 4, 5]
}

// MARK: - Substance labelling

/// Resolves a substance index to the name and color every section needs.
///
/// A value type carried by `let` so passing it into a subview doesn't widen
/// that subview's invalidation boundary — it changes only when the aggregation
/// or the user's color assignments change.
struct UsageSubstanceStyle {
    let substances: [UsageSubstanceRef]
    let colorMap: [String: Color]

    func name(_ index: Int) -> String {
        guard substances.indices.contains(index) else { return "—" }
        return substances[index].displayName
    }

    func color(_ index: Int) -> Color {
        guard substances.indices.contains(index) else { return Theme.accent }
        return SubstancePalette.color(for: substances[index].name, colorMap: colorMap)
    }

    func category(_ index: Int) -> SubstanceCategory {
        guard substances.indices.contains(index) else { return .other }
        return UsageAxes.category(substances[index].categoryIndex)
    }
}

// MARK: - Cards

/// The standard Usage section card: a headline, an optional one-line
/// explanation of what the section answers, and its content.
struct UsageSectionCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }
}

/// A Usage section that remembers whether it's open.
///
/// Sections 6–9 of `Specs/usage-graphs-v2.md` are secondary insights, so they
/// collapse — expanded on first visit, and the choice persists per section.
struct UsageCollapsibleCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    /// `@AppStorage` key suffix — one per section.
    let storageKey: String
    @ViewBuilder var content: () -> Content

    @AppStorage private var isExpanded: Bool

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        storageKey: String,
        defaultExpanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.storageKey = storageKey
        self.content = content
        _isExpanded = AppStorage(wrappedValue: defaultExpanded, "usageSection.\(storageKey)")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .tint(Theme.secondaryLabel)
        .padding()
        .themeCard()
    }
}

// MARK: - Category filter

/// The "All + one pill per category" filter bar shared by the heatmap and the
/// co-use list.
struct UsageCategoryFilterBar: View {
    let categories: [(categoryIndex: Int, count: Int)]
    @Binding var selection: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pill(label: Text("All"), color: Theme.accent, isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(categories, id: \.categoryIndex) { item in
                    let category = UsageAxes.category(item.categoryIndex)
                    pill(
                        label: Text(category.displayName),
                        color: category.color,
                        isSelected: selection == item.categoryIndex,
                    ) {
                        selection = selection == item.categoryIndex ? nil : item.categoryIndex
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func pill(label: Text, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                label
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.25) : Color.clear)
            .foregroundStyle(.primary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? color : Color(.quaternaryLabel)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
