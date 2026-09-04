import SwiftData
import SwiftUI

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
    @Environment(\.colorScheme) private var colorScheme
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
    /// ``SafetySection`` is re-created; the section reads it as a binding.
    @State private var cautionsExpanded = false
    /// Drives the push to the grouped "All effects" screen from the Effects
    /// header's "Show All" (a header NavigationLink isn't reliably hittable).
    @State private var showAllEffects = false
    /// Presents the "Share Substance" sheet (colorful specimen card + detail picker).
    @State private var showShareSheet = false
    /// Whether the header's 40pt display title is still on screen. The bar title
    /// cross-fades in as it leaves, so the name is never printed twice at rest —
    /// `.inline` alone draws the bar title at every offset, including zero.
    @State private var headerTitleVisible = true

    /// Scroll distance at which the bar takes over the title: the header's 4pt
    /// top inset plus the 40pt display line. A name that wraps to two lines
    /// hands over while its second line is still passing under the bar, which
    /// reads as slightly eager rather than wrong.
    private static let titleHandoffOffset: CGFloat = 44

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
        if let full = SubstanceLibrary.resolveFull(baseSubstance.name) {
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
                overview: substance.overview,
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
                cautionsExpanded: $cautionsExpanded,
                onGlossary: { glossaryTopic = $0 },
            )
            .listRowBackground(CardBackground())
        }
        // The list's default top inset sits the title ~55pt under the bar. A
        // system large title sits right beneath it, and this screen's first row
        // *is* that title, so the inset only reads as a gap.
        .contentMargins(.top, 0, for: .scrollContent)
        // Deriving a `Bool` (not the raw offset) means the action fires only on
        // the handoff itself, not on every scroll frame.
        //
        // Tracks the scroll offset rather than the title row's own visibility:
        // the List builds rows lazily, so once the header is recycled it stops
        // reporting anything at all and an `onScrollVisibilityChange` on it
        // never delivers the `false` that would reveal the bar title.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > Self.titleHandoffOffset
        } action: { _, scrolledPastTitle in
            headerTitleVisible = !scrolledPastTitle
        }
        .scrollContentBackground(.hidden)
        // The skeleton belongs to the *screen*, not to the header row. Drawn
        // inside the row it was clipped by the row's bounds — a molecule sliced
        // off mid-bond reads as a rendering bug rather than a watermark. Here it
        // sits behind the whole list and simply runs off the trailing edge.
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                Theme.background
                if let structure = model.moleculeStructure {
                    MoleculeWatermark(structure: structure)
                        .frame(width: 260, height: 260)
                        .opacity(colorScheme == .dark ? 0.12 : 0.07)
                        .offset(x: 78, y: 4)
                }
            }
            .ignoresSafeArea()
        }
        // Still set, so a screen pushed from here gets the right back-button
        // label; the bar's *rendered* title is the principal item below, which
        // is the only way to gate it on scroll position.
        .navigationTitle(substance.displayTitle)
        .inlineNavigationTitle()
        .navigationDestination(isPresented: $showAllEffects) {
            EffectsAndIntensityView(substanceName: substance.name, showsExperienceReports: showsErowidReports)
        }
        .sheet(item: $glossaryTopic) { topic in
            PharmacologyGlossarySheet(topic: topic)
        }
        .sheet(isPresented: $showShareSheet) {
            SubstanceShareSheet(substance: substance, route: routes.activeSubstanceRoute)
        }
        .toolbar { toolbarContent }
        .task(id: TaskKey(substanceName: substance.name, profile: profile)) {
            model.load(substanceName: substance.name, category: substance.category, policy: policy)
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
        // Hidden while the header's display title is on screen, so the name
        // isn't printed twice; fades in once that title scrolls away. Kept in
        // the accessibility tree throughout — VoiceOver users navigate by the
        // bar title and shouldn't lose it to a scroll position.
        ToolbarItem(placement: .principal) {
            Text(substance.displayTitle)
                .cardTitle()
                .lineLimit(1)
                .opacity(headerTitleVisible ? 0 : 1)
                .animation(.easeInOut(duration: 0.18), value: headerTitleVisible)
                .accessibilityHidden(false)
        }
        ToolbarItem(placement: .platformTopBarTrailing) {
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Share drug info")
        }
        // Share and the overflow menu share one glass platter (no separator).
        ToolbarItem(placement: .platformTopBarTrailing) {
            // Everything that isn't Share lives in one overflow menu (Apple's Files-app pattern) —
            // four bar buttons was a button too many. Favorite, Personalize, and the detail-level
            // (tier) switcher all fold in here; the tier choices render as an inline checkmark list.
            Menu {
                // Logging is also a button under the dose card — this is the
                // "I already know what I want" path, reachable without scrolling
                // back up. Two bar buttons is the ceiling, so it lives here
                // rather than becoming a third.
                Button {
                    navigator.present(.quickLog(routine: nil, prefillSubstance: substance.name))
                } label: {
                    Label("Log a Dose", systemImage: "plus.circle")
                }

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
