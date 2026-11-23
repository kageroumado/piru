import SwiftUI

/// Pure route/salt/isomer resolution derived from the substance and the user's
/// current picks. A value type so both the detail view (for the toolbar share
/// action) and ``DoseDurationSection`` resolve the active route from one place
/// without duplicating the cascade.
struct RouteResolution {
    let substance: Substance
    let selectedRoute: RouteOfAdministration?
    let selectedSaltForm: String?
    let selectedIsomer: String?

    private var displayClass: CompoundDisplayClass {
        substance.displayClass
    }

    /// Whether the acute duration timeline should be shown for this compound.
    var durationVisible: Bool {
        displayClass.showsDuration && !(displayClass == .otc && substance.durationImplausible)
    }

    var showsDoseLadder: Bool {
        displayClass.showsDoseLadder
    }

    /// Routes with something worth showing — a dose ladder, an acute duration,
    /// or a long-acting release window. These populate the route picker.
    var presentableRoutes: [SubstanceRoute] {
        substance.routes.filter { route in
            (displayClass.showsDoseLadder && route.doses.hasAnyValue)
                || (route.duration != nil && durationVisible)
                || route.durationOfAction != nil
        }
    }

    /// The route currently driving the dose/duration card: the user's pick when
    /// it's still valid, otherwise the default route, otherwise the first.
    var activeSubstanceRoute: SubstanceRoute? {
        if let selectedRoute, let match = presentableRoutes.first(where: { $0.route == selectedRoute }) {
            return match
        }
        return presentableRoutes.first { $0.route == substance.defaultRoute } ?? presentableRoutes.first
    }

    /// Dose-form variants offered by the active route — drives the browse-time
    /// salt/isomer pickers.
    var activeSaltForms: [DoseVariant] {
        activeSubstanceRoute?.saltForms ?? []
    }

    /// Distinct real salt labels on the active route (the racemic/isomer variants
    /// carry no salt, so they're excluded). Drives the salt picker's visibility.
    var activeSaltLabels: [String] {
        var seen = Set<String>()
        return activeSaltForms.compactMap(\.saltForm).filter { seen.insert($0).inserted }
    }

    /// The dose-form variant driving the dose card, matched on BOTH axes: the
    /// user's picked salt (or the route's default salt) and the picked isomer (or
    /// the racemic default). Falls back gracefully so a single-axis substance
    /// resolves from whichever axis it has. `nil` when the route has no variants.
    var activeDoseVariant: DoseVariant? {
        let forms = activeSaltForms
        guard !forms.isEmpty else { return nil }
        let salt = selectedSaltForm ?? forms.compactMap(\.saltForm).first
        let isomer = selectedIsomer
        return forms.first { $0.saltForm == salt && $0.isomer == isomer }
            ?? forms.first { $0.isomer == isomer }
            ?? forms.first
    }

    /// The named isomer options for the active route (racemic first). Empty when
    /// the substance has no isomer axis, so the picker stays hidden.
    var activeIsomerOptions: [IsomerPicker.Option] {
        guard let route = activeSubstanceRoute?.route else { return [] }
        return substance.isomerOptions(for: route).map {
            IsomerPicker.Option(code: $0.code, displayName: $0.displayName)
        }
    }
}

/// Dose ladder + duration for the selected route, behind a segmented route
/// switcher when more than one route applies. Surfaced near the top of the
/// detail view, the primary thing people open a substance for. One card per
/// route, so a multi-route compound reads in a single screenful.
struct DoseDurationSection: View {
    let routes: RouteResolution
    @Binding var routeSelection: RouteOfAdministration
    @Binding var saltSelection: String?
    @Binding var isomerSelection: String?
    let provenance: SubstanceStore.SubstanceProvenance?
    /// Holds the per-route source counts, so the compare row costs one query
    /// per route rather than one per body pass.
    let model: SubstanceDetailModel

    /// The branded formulation whose duration envelope redraws the curve, or `nil`
    /// for the substance's own default curve. Card-local: it answers "how long does
    /// Concerta run?" in the moment and resets to the default next visit — or to
    /// the brand the page was opened on (a search for "Concerta").
    @State private var selectedBrandProduct: String?

    init(
        routes: RouteResolution,
        routeSelection: Binding<RouteOfAdministration>,
        saltSelection: Binding<String?>,
        isomerSelection: Binding<String?>,
        provenance: SubstanceStore.SubstanceProvenance?,
        model: SubstanceDetailModel,
        initialBrand: String? = nil,
    ) {
        self.routes = routes
        _routeSelection = routeSelection
        _saltSelection = saltSelection
        _isomerSelection = isomerSelection
        self.provenance = provenance
        self.model = model
        _selectedBrandProduct = State(
            initialValue: Self.preselectedBrand(initialBrand, substanceUID: routes.substance.substanceUID),
        )
    }

    /// The Branded formulations row to open on for `brand`: the catalog's own
    /// spelling, matched case-insensitively so a hand-typed deep link still
    /// lands. `nil` (the default curve) for a brand with no authored duration,
    /// which has no row to select.
    static func preselectedBrand(_ brand: String?, substanceUID: String?) -> String? {
        guard let brand, let substanceUID else { return nil }
        return SubstanceLibrary.brandProducts(forUID: substanceUID)
            .first { $0.name.caseInsensitiveCompare(brand) == .orderedSame }
            .flatMap { SubstanceLibrary.productDuration(for: $0.name) != nil ? $0.name : nil }
    }

    private var substance: Substance {
        routes.substance
    }

    /// The substance's branded products that carry an authored duration envelope
    /// (`product_durations`) — the options for the Branded formulations picker.
    /// Empty unless the acute timeline is shown, so an implausible-duration or
    /// no-duration compound never surfaces the section.
    private var brandedDurations: [BrandedDurationOption] {
        guard routes.durationVisible, let uid = substance.substanceUID else { return [] }
        return SubstanceLibrary.brandProducts(forUID: uid).compactMap { brand in
            guard let duration = SubstanceLibrary.productDuration(for: brand.name) else { return nil }
            return BrandedDurationOption(
                name: brand.name, isExtendedRelease: brand.isExtendedRelease, duration: duration,
            )
        }
    }

    var body: some View {
        if let route = routes.activeSubstanceRoute {
            let salt = routes.activeDoseVariant
            let baseDuration = routes.durationVisible ? (salt?.duration ?? route.duration) : nil
            // A selected brand's envelope redraws the curve; the dose ladder below
            // is untouched — doses are the substance's own, never branded here.
            let options = brandedDurations
            let effectiveDuration = selectedBrandProduct
                .flatMap { name in options.first { $0.name == name }?.duration } ?? baseDuration
            Section {
                if routes.presentableRoutes.count > 1 {
                    RouteChips(
                        routes: routes.presentableRoutes,
                        activeRoute: route.route,
                        onSelect: { routeSelection = $0 },
                    )
                    // Edge to edge: the chips are a scrolling rail, and inset
                    // from the card's margins they read as a row that has
                    // stopped short rather than one that continues off-screen.
                    // The lead-in padding lives inside the scroll content, so
                    // the first chip still lines up with the card's text.
                    .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
                }
                if routes.activeSaltLabels.count > 1 {
                    SaltPicker(
                        forms: routes.activeSaltLabels,
                        selection: $saltSelection,
                        style: .formRow,
                    )
                    .listRowSeparator(.hidden)
                }
                if routes.activeIsomerOptions.count > 1 {
                    IsomerPicker(
                        options: routes.activeIsomerOptions,
                        selection: $isomerSelection,
                        style: .formRow,
                    )
                    .listRowSeparator(.hidden)
                }

                // One row per card+footer — see the layout rationale on
                // `SourceAttributionRow` in SubstanceDetailSupport.swift.
                VStack(alignment: .leading, spacing: 0) {
                    DoseEffectsCard(
                        unit: salt?.unit ?? route.unit,
                        doses: salt?.doses ?? route.doses,
                        duration: effectiveDuration,
                        releaseWindow: route.durationOfAction?.formattedWindow,
                        elementalFraction: salt?.elementalFraction,
                        showsDoseLadder: routes.showsDoseLadder,
                        showsDuration: routes.durationVisible,
                        // Only worth saying on a compound that ALSO has a clinical
                        // dose — for a purely recreational substance every ladder is
                        // recreational and the label is noise. Here it stops a
                        // quetiapine or mirtazapine figure being read as the dose
                        // someone was prescribed.
                        regimeLabel: substance.displayClass == .dualUse || substance.displayClass == .medicalRx
                            ? route.doseContext : .unknown,
                        accent: substance.category.color,
                        // Lets the card shape its curve the same way the journal does.
                        // Without it the two disagreed for ~a third of the library.
                        curveCategory: substance.category,
                    )
                    sourceRows(for: route)

                    // The action belongs to this card. Floating below it as its own
                    // full-width slab, it broke the card rhythm — every other thing
                    // on the screen is a card, and this was a pink bar sitting on
                    // the page between two of them. Inside, under the sources, it
                    // reads as "…and here is what you do with this".
                    // A full section gap above it: the action is set apart from
                    // the reference lines it follows, not stacked onto them.
                    RecordEntryButton(substanceName: substance.name)
                        .padding(.top, Spacing.xxxl)
                }
                .listRowSeparator(.hidden)
            }

            if !options.isEmpty {
                BrandedFormulationsSection(
                    options: options,
                    selection: $selectedBrandProduct,
                    accent: substance.category.color,
                )
            }
        }
    }

    /// One attribution line on the card's source list.
    private struct Attribution {
        let slug: String
        let label: LocalizedStringResource
        let field: SubstanceStore.AttributableField
    }

    /// Dose + duration usually share a source (and a deep link), so they
    /// collapse to a single line when they match.
    private func attributions(for route: SubstanceRoute) -> [Attribution] {
        let sources = provenance?.routesBySource[route.route]
        let doseSlug = routes.showsDoseLadder && route.doses.hasAnyValue ? sources?.doseSource : nil
        let durSlug = routes.durationVisible && route.duration != nil ? sources?.durationSource : nil
        if let doseSlug, doseSlug == durSlug {
            return [Attribution(slug: doseSlug, label: "Dose & Duration", field: .dose(route.route))]
        }
        return [
            doseSlug.map { Attribution(slug: $0, label: "Dose data", field: .dose(route.route)) },
            durSlug.map { Attribution(slug: $0, label: "Duration data", field: .duration(route.route)) },
        ].compactMap(\.self)
    }

    @ViewBuilder
    private func sourceRows(for route: SubstanceRoute) -> some View {
        let lines = attributions(for: route)
        // The sources disagree, often materially — meth's oral "Common" runs
        // 10–20 mg to one source and 15–30 to another. The card has to pick one;
        // the compare link says so and shows the spread rather than letting the
        // chosen number read as the only number. Pointless at one source, and
        // counting the total rather than the *others* keeps the string plural
        // in every case it can appear, so it needs no plural rule.
        let sourceCount = lines.isEmpty
            ? 0 : model.comparisonSourceCount(substanceName: substance.name, route: route.route)
        let compare = sourceCount > 1
            ? CompareSourcesLink(substanceName: substance.name, route: route.route, sourceCount: sourceCount)
            : nil
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            if index == lines.count - 1, let compare {
                // The link rides on the last source line when both fit, and
                // drops to its own line on the label column when they don't.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                        attributionRow(line, fillsWidth: false)
                        compare
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        attributionRow(line, fillsWidth: true)
                        HStack(spacing: SourceAttributionRow.glyphSpacing) {
                            SourceAttributionGlyph().hidden()
                            compare
                            Spacer(minLength: 0)
                        }
                        .padding(.top, SourceAttributionRow.topGap)
                    }
                }
            } else {
                attributionRow(line, fillsWidth: true)
            }
        }
    }

    private func attributionRow(_ line: Attribution, fillsWidth: Bool) -> SourceAttributionRow {
        SourceAttributionRow(
            slug: line.slug, label: line.label,
            deepLink: SubstanceSourceLinks.deepLink(line.slug, substance: substance),
            substanceName: substance.name, field: line.field,
            fillsWidth: fillsWidth,
        )
    }
}

/// "Compare all N sources ›" — the entry point to ``DoseSourceComparisonView``.
private struct CompareSourcesLink: View {
    let substanceName: String
    let route: RouteOfAdministration
    let sourceCount: Int

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        Button {
            navigator.present(.doseSources(substance: substanceName, route: route))
        } label: {
            HStack(spacing: Spacing.xs) {
                Text("Compare all \(sourceCount) sources", comment: "Opens the dose-source comparison")
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.vertical, SourceAttributionRow.lineVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal capsule selector for routes — replaces the segmented/menu picker.
/// Reads clearly even with many routes (it scrolls) and the active route is
/// unmistakable.
struct RouteChips: View {
    let routes: [SubstanceRoute]
    let activeRoute: RouteOfAdministration
    let onSelect: (RouteOfAdministration) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(routes, id: \.route) { r in
                    let isOn = activeRoute == r.route
                    Button {
                        onSelect(r.route)
                    } label: {
                        Text(r.route.localizedName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, Spacing.md)
                            .background(
                                skinChipShape().fill(isOn ? Theme.accent : Color.platformTertiarySystemFill),
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }
}

/// Opens an entry form for the selected substance.
private struct RecordEntryButton: View {
    let substanceName: String
    @Environment(\.appNavigator) private var navigator

    var body: some View {
        Button {
            navigator.present(.quickLog(routine: nil, prefillSubstance: substanceName))
        } label: {
            Text("Record an entry")
                .font(.piru(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
        }
        .skinButtonStyle(.prominent)
        .tint(Theme.accent)
    }
}
