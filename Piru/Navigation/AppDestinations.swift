import SwiftData
import SwiftUI

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
        case let .session(id):
            if let session = lookupSession(id: id) {
                SessionDetailView(session: session)
            }

        case let .entry(timestamp, id):
            // Look up the entry by its stable id, falling back to the ±2s
            // timestamp window for id-less routes (pre-V4 payloads, Live
            // Activity links). If the entry has been deleted since the route
            // was pushed, render nothing — the stack will typically pop the
            // dead route on next interaction.
            if let entry = lookupEntry(id: id, near: timestamp) {
                EntryDetailView(entry: entry)
            }

        case let .rampDown(timestamp, id):
            // Resolve the entry like `.entry`, then re-derive the duration
            // profile the same way EntryDetailView gates its link — if either
            // is gone, render nothing.
            if let entry = lookupEntry(id: id, near: timestamp),
               let substance = SubstanceLibrary.lookupByNameOrAlias(entry.substance),
               let duration = substance.resolveDuration(for: entry.route) {
                RampDownView(entry: entry, duration: duration)
            }

        case .comedownGuide:
            ComedownGuideView()

        case let .substance(name):
            // Push a **lightweight shell** (the warm batch projection's hot
            // fields) so the detail header + dose card render instantly off the
            // push; `SubstanceDetailView` then resolves the heavy detail-only
            // fields — mechanism, chemistry identifiers, molar mass, peptide
            // profile, per-route protocol dosing — in a `.task` off the push.
            //
            // The shell is only available once the batch cache is warm (the
            // common case after browsing); otherwise fall back to the full
            // resolve, which also gates the not-found state. If a *stored* name
            // no longer resolves to a canonical substance (renamed/merged since
            // it was saved — e.g. "Magnesium" was split into specific salts),
            // show an explicit not-found state rather than a blank screen. Alias
            // fallback is deliberately avoided: some aliases are polluted
            // ("magnesium" → Salicylic acid), so it would mis-resolve.
            if let shell = SubstanceLibrary.shell(name) {
                SubstanceDetailView(substance: shell)
            } else if let substance = SubstanceLibrary.lookup(name) {
                SubstanceDetailView(substance: substance)
            } else {
                ContentUnavailableView(
                    "Substance Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("“\(name)” isn’t in the library anymore. It may have been renamed or merged."),
                )
            }

        case let .libraryCategory(category):
            SubstanceCategoryListView(title: category.browseTitle, category: category)

        case let .libraryTag(tag):
            SubstanceCategoryListView(title: LibraryFamily.tagTitle(tag), tag: tag)

        case .libraryFavorites:
            SubstanceCategoryListView(title: "Favorites", category: nil)

        case let .tool(tool):
            toolView(for: tool)
                .navigationTitle(Text(tool.name))
                .navigationBarTitleDisplayMode(.inline)

        case let .insight(insight):
            insightView(for: insight)
                .navigationBarTitleDisplayMode(.inline)

        case let .insightGroup(group):
            InsightGroupView(group: group)
                .navigationTitle(group.title)
                .navigationBarTitleDisplayMode(.inline)

        case .myMeds:
            MyMedsHubView()

        case let .medDetail(identityKey, sortOrder):
            // If the med was deleted since the route was pushed, render
            // nothing — the stack pops the dead route on next interaction.
            if let item = lookupMed(identityKey: identityKey, sortOrder: sortOrder) {
                MedDetailView(item: item)
            }

        case let .substanceData(name, section):
            SubstanceDataPageView(name: name, section: section)
        }
    }

    @ViewBuilder
    private func insightView(for insight: Insight) -> some View {
        switch insight {
        case .adherence: AdherenceView().navigationTitle("Adherence")
        case .usage: UsageStatsView().navigationTitle("Usage")
        case .tolerance: ToleranceToolView().navigationTitle("Tolerance")
        case .inSystem: InYourSystemView().navigationTitle("In Your System")
        case .bodyLoad: BodyLoadView().navigationTitle("In Your Body")
        }
    }

    @ViewBuilder
    private func toolView(for tool: Tool) -> some View {
        switch tool {
        case .interactions: InteractionCheckerView()
        case .calculator: HalfLifeCalculatorView()
        case .volumetric: VolumetricDosingView()
        case .recovery: ComedownGuideView()
        case .pharma: PharmaTableView()
        case .ceiling: CeilingEffectToolView()
        case .benzoEquivalence: BenzoEquivalenceToolView()
        case .opioidEquivalence: OpioidEquivalenceToolView()
        case .toleranceInfo: ToleranceExplainerView()
        case .inventory: InventoryListView()
        case .effectSandbox: EffectSandboxView()
        case .steadyState: SteadyStateView()
        }
    }

    /// `identityKey` is computed (not a stored attribute), so this filters in
    /// memory — the meds list is small by construction. `sortOrder`
    /// disambiguates same-identity schedules; identity-only is the fallback
    /// when a reorder happened between push and render.
    private func lookupMed(identityKey: String, sortOrder: Int) -> DailyDoseItem? {
        let items = (try? modelContext.fetch(FetchDescriptor<DailyDoseItem>())) ?? []
        return items.first { $0.identityKey == identityKey && $0.sortOrder == sortOrder }
            ?? items.first { $0.identityKey == identityKey }
    }

    private func lookupSession(id: UUID) -> Session? {
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Resolve an entry by its stable `id` first; for id-less routes (pre-V4
    /// payloads, the Live Activity's timestamp-only deep links) — or if the id
    /// no longer matches (store replaced by a restore) — fall back to the
    /// legacy ±2 s timestamp window.
    private func lookupEntry(id: UUID?, near timestamp: Date) -> DoseEntry? {
        if let id {
            var descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let entry = try? modelContext.fetch(descriptor).first {
                return entry
            }
        }
        let lower = timestamp.addingTimeInterval(-2)
        let upper = timestamp.addingTimeInterval(2)
        var descriptor = FetchDescriptor<DoseEntry>(
            predicate: #Predicate { $0.timestamp >= lower && $0.timestamp <= upper },
        )
        descriptor.sortBy = [SortDescriptor(\.timestamp)]
        return try? modelContext.fetch(descriptor).first
    }
}
