import SwiftUI
import SwiftData

// MARK: - App

@main
struct PiruApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: DoseEntry.self, SubstanceColor.self, UserColor.self,
                DailyDoseItem.self, FavoriteSubstance.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
