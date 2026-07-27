import SwiftData
import SwiftUI
import UIKit

struct SubstanceDetailView: View {
    /// The library substance backing this view. Pushed as a **lightweight shell**
    /// (the batch projection's hot fields — name, category, routes/doses,
    /// durations, half-life, aliases) so the header and dose/duration card render
    /// instantly off the navigation push; ``upgradeToFullRecord()`` then resolves
    /// the heavy detail-only fields (mechanism, chemistry identifiers, molar mass,
    /// medical info, protocol dosing, peptide) in a `.task` and swaps them in, so
    /// those sections reveal progressively. Overrides are layered on reactively
    /// via `substance`, so personalizations show on entry and update live.
    @State private var baseSubstance: Substance
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appNavigator) private var navigator
    @Query private var historyEntries: [DoseEntry]
    @Query private var favorites: [FavoriteSubstance]
    @Query private var inventoryItems: [InventoryItem]

    @State private var customStore = CustomSubstanceStore.shared

    /// Holding the @Observable profile store as @State (rather than reading
    /// `UserProfileStore.shared.disclosureTier` via a plain computed) is what makes
    /// SwiftUI re-render this view when the user changes the tier in Settings.
    @State private var profileStore = UserProfileStore.shared

    /// Async-loaded, store-backed detail data (provenance, receptor bindings, PK,
    /// metabolism, history aggregates). Filled in the `.task` blocks below so each
    /// section reveals as its data resolves.
    @State private var model = SubstanceDetailModel()

    /// The route the dose/duration card is showing. `nil` defaults to the
    /// substance's default route (resolved by ``RouteResolution``).
    @State private var selectedRoute: RouteOfAdministration?

    /// The salt/ester form the dose card is showing (Magnesium, Lithium).
    /// `nil` defaults to the active route's first form.
    @State private var selectedSaltForm: String?

    /// The stereoisomer code the dose card is showing (`nil` = racemic default).
    @State private var selectedIsomer: String?

    /// The plain-language help sheet shown from a card header's (i) button.
    @State private var glossaryTopic: PharmacologyGlossarySheet.Topic?
    /// Contraindications & cautions disclosure, owned here so it survives while
    /// ``MedicalInfoSection`` is re-created; the section reads it as a binding.
    @State private var cautionsExpanded = false
    /// Drives the push to the grouped "All effects" screen from the Effects
    /// header's "Show All" (a header NavigationLink isn't reliably hittable).
    @State private var showAllEffects = false
    /// Drives the push to the full Inventory list from the stock card's "Show All".
    @State private var showAllInventory = false
    /// Presents the "Share Substance" sheet (colorful specimen card + detail picker).
    @State private var showShareSheet = false

    init(substance: Substance) {
        _baseSubstance = State(initialValue: substance)
        let name = substance.name
        _historyEntries = Query(
            filter: #Predicate<DoseEntry> { entry in
                entry.substance == name
            },
            sort: \DoseEntry.timestamp,
            order: .reverse,
        )
    }

    /// The user's personal override for this substance, if any (keyed by canonical name).
    private var personalOverride: CustomSubstanceEntry? {
        customStore.first(whereName: baseSubstance.name)
    }

    /// The substance with any personal override applied — display name, dose
    /// ladder, duration, and half-life. Used throughout the view so the detail
    /// reflects the user's customizations and updates live when they change.
    private var substance: Substance {
        personalOverride.map { baseSubstance.applyingOverride(from: $0) } ?? baseSubstance
    }

    private var profile: UserProfile {
        profileStore.disclosureTier
    }

    private var policy: DisclosurePolicy {
        .init(profile: profile)
    }

    /// First-hand Erowid reports show on the pushed "All effects" screen, gated
    /// to recreational / dual-use compounds where such reports exist.
    private var showsErowidReports: Bool {
        substance.displayClass == .recreational || substance.displayClass == .dualUse
    }

    // MARK: - Route resolution

    /// The route/salt/isomer cascade, resolved from the current picks. Shared by
    /// the dose card and the toolbar share action.
    private var routes: RouteResolution {
        RouteResolution(
            substance: substance,
            selectedRoute: selectedRoute,
            selectedSaltForm: selectedSaltForm,
            selectedIsomer: selectedIsomer,
        )
    }

    private var routeSelection: Binding<RouteOfAdministration> {
        Binding(
            get: { routes.activeSubstanceRoute?.route ?? substance.defaultRoute },
            set: { newRoute in
                selectedRoute = newRoute
                // Reset the salt to the new route's default unless it carries
                // the same form (salt is a sub-dimension of route).
                let forms = routes.presentableRoutes.first { $0.route == newRoute }?.saltForms ?? []
                if let current = selectedSaltForm, !forms.contains(where: { $0.saltForm == current }) {
                    selectedSaltForm = nil
                }
                // Keep the isomer across the route change if the new route offers
                // it, else fall back to the racemic default.
                if let current = selectedIsomer, !forms.contains(where: { $0.isomer == current }) {
                    selectedIsomer = nil
                }
            },
        )
    }

    /// Reads the active variant (the user's pick or the route's default) so the
    /// picker highlights the right form even when `selectedSaltForm` is still
    /// `nil` ("track the default"); writing records the explicit pick.
    private var saltSelection: Binding<String?> {
        Binding(
            get: { routes.activeDoseVariant.flatMap(\.saltForm) ?? routes.activeSaltForms.first.flatMap(\.saltForm) },
            set: { selectedSaltForm = $0 },
        )
    }

    /// Reads the active variant's isomer (so it tracks the racemic default until
    /// an explicit pick), writes the selection.
    private var isomerSelection: Binding<String?> {
        Binding(
            get: { routes.activeDoseVariant?.isomer ?? selectedIsomer },
            set: { selectedIsomer = $0 },
        )
    }

    // MARK: - Favorites & sharing

    private var isFavorite: Bool {
        Array(favorites).isFavorite(substance.name)
    }

    private func toggleFavorite() {
        FavoriteService.toggle(substance: substance.name, substanceUID: substance.substanceUID, in: modelContext)
        try? modelContext.save()
    }

    /// Resolve the full per-field record (mechanism, chemistry identifiers, molar
    /// mass, indications/contraindications, protocol dosing, peptide profile) and
    /// swap it in. Runs off the push in a `.task`; the hot header/dose fields
    /// already render from the shell, and the full record carries the same name,
    /// routes, and category, so only the heavy sections pop in. No-op when the
    /// canonical row can't be resolved (keeps the shell).
    private func upgradeToFullRecord() {
        if let full = SubstanceLibrary.lookup(baseSubstance.name) {
            baseSubstance = full
        }
    }

    /// Cheap content fingerprint of the dose history — membership plus the
    /// amounts the aggregates depend on, so an in-place edit invalidates too.
    private var historySignature: Int {
        var hasher = Hasher()
        for entry in historyEntries {
            hasher.combine(entry.persistentModelID)
            hasher.combine(entry.amount)
        }
        return hasher.finalize()
    }

    var body: some View {
        List {
            SubstanceDetailLayout(
                substance: substance,
                model: model,
                policy: policy,
                profile: profile,
                routes: routes,
                routeSelection: routeSelection,
                saltSelection: saltSelection,
                isomerSelection: isomerSelection,
                historyEntries: historyEntries,
                inventoryItems: inventoryItems,
                selectedSaltForm: selectedSaltForm,
                personalNotes: personalOverride?.notes,
                showAllEffects: $showAllEffects,
                showAllInventory: $showAllInventory,
                cautionsExpanded: $cautionsExpanded,
                onGlossary: { glossaryTopic = $0 },
            )
            .listRowBackground(CardBackground())
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(substance.displayTitle)
        // The layout draws its own 40pt title inside the header byline, so the
        // bar keeps only the compact title (a `.large` one would print it twice).
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showAllEffects) {
            EffectsAndIntensityView(substanceName: substance.name, showsExperienceReports: showsErowidReports)
        }
        .sheet(item: $glossaryTopic) { topic in
            PharmacologyGlossarySheet(topic: topic)
        }
        .sheet(isPresented: $showShareSheet) {
            SubstanceShareSheet(substance: substance, route: routes.activeSubstanceRoute)
        }
        .navigationDestination(isPresented: $showAllInventory) {
            InventoryListView()
        }
        .toolbar { toolbarContent }
        .task(id: TaskKey(substanceName: substance.name, profile: profile)) {
            model.load(substanceName: substance.name, policy: policy)
        }
        .task(id: baseSubstance.name) {
            // Upgrade the pushed shell to the full resolved record off the push.
            upgradeToFullRecord()
        }
        .task(id: historySignature) {
            model.rebuildHistoryStats(from: historyEntries)
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Share drug info")
        }
        // Share and the overflow menu share one glass platter (no separator).
        ToolbarItem(placement: .topBarTrailing) {
            // Everything that isn't Share lives in one overflow menu (Apple's Files-app pattern) —
            // four bar buttons was a button too many. Favorite, Personalize, and the detail-level
            // (tier) switcher all fold in here; the tier choices render as an inline checkmark list.
            Menu {
                Button {
                    toggleFavorite()
                } label: {
                    Label(
                        isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: isFavorite ? "star.slash" : "star",
                    )
                }

                Section {
                    Button {
                        navigator.present(.personalizeSubstance(name: baseSubstance.name))
                    } label: {
                        Label(
                            personalOverride != nil ? "Edit Personalization…" : "Personalize Substance…",
                            systemImage: "slider.horizontal.3",
                        )
                    }
                    if let override = personalOverride {
                        Button(role: .destructive) {
                            customStore.delete(override)
                        } label: {
                            Label("Reset Personalization", systemImage: "arrow.uturn.backward")
                        }
                    }
                }

                Section("Detail level") {
                    Picker("Detail level", selection: Binding(
                        get: { profile },
                        set: { profileStore.setDisclosureTier($0) },
                    )) {
                        ForEach(UserProfile.allCases) { tier in
                            Label(tier.displayName, systemImage: tier.icon).tag(tier)
                        }
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("More")
        }
    }

    private struct TaskKey: Hashable {
        let substanceName: String
        let profile: UserProfile
    }

    /// Compact numeric formatter for chemistry values: drops a trailing `.0`
    /// (so `45.0` → `45`) but keeps real decimals (`2.34` → `2.34`). Shared with
    /// the pharmacology rows in `Components`.
    static func chemNumber(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%g", value)
    }
}
