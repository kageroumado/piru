import SwiftUI
import SwiftData

/// Resolves a `PushRoute` to its destination view. Apply once per
/// `NavigationStack` so the entire app's push routes are registered in
/// one place.
///
/// ```swift
/// NavigationStack(path: navigator.pathBinding(for: .journal)) {
///     JournalRoot()
/// }
/// .withAppDestinations()
/// ```
struct AppDestinationsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: PushRoute.self) { route in
            PushRouteView(route: route)
        }
    }
}

extension View {
    /// Register the navigator's `PushRoute` destinations on this stack.
    func withAppDestinations() -> some View {
        modifier(AppDestinationsModifier())
    }
}

/// Render a `PushRoute` as its underlying screen.
///
/// Identifier-based routes (entries, substances) look up the underlying
/// model on render — this is what makes routes a pure value type
/// (Codable, Hashable) without holding a SwiftData object reference.
private struct PushRouteView: View {
    let route: PushRoute

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch route {
        case .day(let date):
            DayDetailView(date: date)

        case .entry(let timestamp):
            // Look up the entry by timestamp (±2s, matching the deep-link
            // semantics in SheetRouteView). If the entry has been deleted
            // since the route was pushed, render nothing — the stack will
            // typically pop the dead route on next interaction.
            if let entry = lookupEntry(at: timestamp) {
                EntryDetailView(entry: entry)
            } else {
                EmptyView()
            }

        case .substance(let name):
            if let substance = SubstanceLibrary.all.first(where: { $0.name == name }) {
                SubstanceDetailView(substance: substance)
            } else {
                EmptyView()
            }

        case .libraryCategory(let category):
            SubstanceCategoryListView(title: category.displayName, category: category)

        case .libraryFavorites:
            SubstanceCategoryListView(title: "Favorites", category: nil)

        case .tool(let tool):
            toolView(for: tool)
                .navigationTitle(Text(tool.name))
                .navigationBarTitleDisplayMode(.inline)

        case .insight(let insight):
            insightView(for: insight)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func insightView(for insight: Insight) -> some View {
        switch insight {
        case .adherence: AdherenceView().navigationTitle("Adherence")
        case .usage: UsageStatsView().navigationTitle("Usage")
        }
    }

    @ViewBuilder
    private func toolView(for tool: Tool) -> some View {
        switch tool {
        case .interactions: InteractionCheckerView()
        case .calculator: HalfLifeCalculatorView()
        case .volumetric: VolumetricDosingView()
        case .recovery: ComedownGuideView()
        case .pharma: AdvancedSearchView()
        }
    }

    private func lookupEntry(at timestamp: Date) -> DoseEntry? {
        let lower = timestamp.addingTimeInterval(-2)
        let upper = timestamp.addingTimeInterval(2)
        var descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        return try? modelContext.fetch(descriptor).first
    }
}
