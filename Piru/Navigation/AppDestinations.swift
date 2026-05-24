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
            let lower = timestamp.addingTimeInterval(-2)
            let upper = timestamp.addingTimeInterval(2)
            let descriptor = FetchDescriptor<DoseEntry>(
                predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper }
            )
            if let entry = try? modelContext.fetch(descriptor).first {
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
            SubstanceCategoryListView(title: category.rawValue, category: category)

        case .libraryFavorites:
            SubstanceCategoryListView(title: "Favorites", category: nil)
        }
    }
}
