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
/// detail view — the primary thing people open a substance for. One
/// consolidated card per route replaces the old two-sections-per-route stack,
/// so a multi-route compound reads in a single screenful.
struct DoseDurationSection: View {
    let routes: RouteResolution
    @Binding var routeSelection: RouteOfAdministration
    @Binding var saltSelection: String?
    @Binding var isomerSelection: String?
    let provenance: SubstanceStore.SubstanceProvenance?

    /// The dialed dose, published up from the card so the Log button can name it.
    @State private var loggableDose: String?
    @Environment(\.appNavigator) private var navigator

    private var substance: Substance {
        routes.substance
    }

    var body: some View {
        if let route = routes.activeSubstanceRoute {
            let salt = routes.activeDoseVariant
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
                        route: route.route,
                        unit: salt?.unit ?? route.unit,
                        doses: salt?.doses ?? route.doses,
                        duration: routes.durationVisible ? (salt?.duration ?? route.duration) : nil,
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
                        selectedDoseText: $loggableDose,
                    )
                    sourceRows(for: route)

                    // The action belongs to this card. Floating below it as its own
                    // full-width slab, it broke the card rhythm — every other thing
                    // on the screen is a card, and this was a pink bar sitting on
                    // the page between two of them. Inside, under the sources, it
                    // reads as "…and here is what you do with this".
                    LogThisButton(substanceName: substance.name, doseText: loggableDose)
                        .padding(.top, 12)
                }
                .listRowSeparator(.hidden)
            } header: {
                Text("Dose & Duration")
            }
        }
    }

    /// One source line: dose + duration usually share a source (and a deep
    /// link), so collapse to a single row when they match.
    @ViewBuilder
    private func sourceRows(for route: SubstanceRoute) -> some View {
        let doseSlug = routes.showsDoseLadder && route.doses.hasAnyValue ? provenance?.routesBySource[route.route]?.doseSource : nil
        let durSlug = routes.durationVisible && route.duration != nil ? provenance?.routesBySource[route.route]?.durationSource : nil
        if let doseSlug, doseSlug == durSlug {
            SourceAttributionRow(
                slug: doseSlug, label: "Dose & Duration",
                deepLink: SubstanceSourceLinks.deepLink(doseSlug, substance: substance),
                substanceName: substance.name, field: .dose(route.route),
            )
        } else {
            if let doseSlug {
                SourceAttributionRow(
                    slug: doseSlug, label: "Dose data",
                    deepLink: SubstanceSourceLinks.deepLink(doseSlug, substance: substance),
                    substanceName: substance.name, field: .dose(route.route),
                )
            }
            if let durSlug {
                SourceAttributionRow(
                    slug: durSlug, label: "Duration data",
                    deepLink: SubstanceSourceLinks.deepLink(durSlug, substance: substance),
                    substanceName: substance.name, field: .duration(route.route),
                )
            }
        }
        // The sources disagree, often materially — meth's oral "Common" runs
        // 10–20 mg to one source and 15–30 to another. The card has to pick one;
        // this says so and shows the spread rather than letting the chosen
        // number read as the only number.
        let sourceCount = ladderSourceCount(for: route.route)
        if doseSlug != nil, sourceCount > 1 {
            CompareSourcesRow(
                substanceName: substance.name,
                route: route.route,
                sourceCount: sourceCount,
            )
        }
    }

    /// How many sources carry a ladder for this route. The row is pointless at
    /// one — and counting the total rather than the *others* keeps the string
    /// plural in every case it can appear, so it needs no plural rule.
    private func ladderSourceCount(for route: RouteOfAdministration) -> Int {
        SubstanceStore.shared.doseLadders(forSubstanceName: substance.name, route: route).count
    }
}

/// "Compare N other sources ›" — the entry point to ``DoseSourceComparisonView``.
private struct CompareSourcesRow: View {
    let substanceName: String
    let route: RouteOfAdministration
    let sourceCount: Int

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        Button {
            navigator.present(.doseSources(substance: substanceName, route: route))
        } label: {
            HStack(spacing: 4) {
                Text("Compare all \(sourceCount) sources", comment: "Opens the dose-source comparison")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            // Matches SourceAttributionRow's own leading inset — the checkmark
            // glyph's width plus its gap — so this line starts where the source
            // names above it start instead of hanging off to their left.
            .padding(.leading, 22)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack(spacing: 8) {
                ForEach(routes, id: \.route) { r in
                    let isOn = activeRoute == r.route
                    Button {
                        onSelect(r.route)
                    } label: {
                        Text(r.route.localizedName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isOn ? Theme.accent : Color(.tertiarySystemFill)),
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

/// The screen's primary action, rendered as the last row of the dose card: open
/// quick-log with this substance staged at the dose the reader is looking at.
///
/// It has moved twice. In the header it prompted an action before the screen had
/// said anything worth acting on; as a free-floating bar under the card it broke
/// the card rhythm and read as a page-level banner. It belongs to the dose card,
/// because the dose card is what it acts on.
private struct LogThisButton: View {
    let substanceName: String
    /// The dialed tier's dose, when the substance has a ladder.
    let doseText: String?

    @Environment(\.appNavigator) private var navigator

    var body: some View {
        Button {
            navigator.present(.quickLog(routine: nil, prefillSubstance: substanceName))
        } label: {
            Group {
                if let doseText {
                    Text("Log \(doseText)", comment: "Primary action naming the dialed dose")
                } else {
                    Text("Log this", comment: "Primary action when the substance has no dose ladder")
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
    }
}
