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
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 8, trailing: 20))
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

                DoseDurationCard(
                    route: route.route,
                    unit: salt?.unit ?? route.unit,
                    doses: salt?.doses ?? route.doses,
                    duration: routes.durationVisible ? (salt?.duration ?? route.duration) : nil,
                    releaseWindow: route.durationOfAction?.formattedWindow,
                    elementalFraction: salt?.elementalFraction,
                    showsDoseLadder: routes.showsDoseLadder,
                    showsDuration: routes.durationVisible,
                    accent: substance.category.color,
                )
                .listRowSeparator(.hidden)

                sourceRows(for: route)
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
        }
    }
}
