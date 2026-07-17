import SwiftUI

/// "About <substance>" — the substance screen's dose & duration card, verbatim
/// (``RouteDosingCard``), filtered to this dose's route and salt form. No
/// folding: the header's "Show All" hops to the full substance page for every
/// other route, sources, and the rest.
struct EntryAboutSection: View {
    let entry: DoseEntry
    let substance: Substance?

    var body: some View {
        if let info = substance {
            let showsLadder = info.displayClass.showsDoseLadder
            let durationVisible = info.displayClass.showsDuration
                && !(info.displayClass == .otc && info.durationImplausible)
            let doses = showsLadder ? info.doseRange(for: entry.route, saltForm: entry.saltForm) : nil
            let duration = durationVisible ? info.resolveDuration(for: entry.route) : nil
            if doses?.hasAnyValue == true || duration != nil {
                Section {
                    RouteDosingCard(
                        route: entry.route,
                        unit: info.unit(for: entry.route, saltForm: entry.saltForm),
                        doses: doses,
                        duration: duration,
                        releaseWindow: info.routes.first { $0.route == entry.route }?.durationOfAction?.formattedWindow,
                        elementalFraction: info.elementalFraction(for: entry.route, saltForm: entry.saltForm),
                        showsDoseLadder: showsLadder,
                        showsDuration: duration != nil,
                        showsTitle: false,
                    )
                } header: {
                    HStack {
                        // Route-specific card (dose ladder + duration for this
                        // dose's ROA), so the header names the route.
                        Text("About \(CustomSubstanceStore.shared.displayName(for: entry.substance)) (\(entry.route.localizedName))")
                        Spacer()
                        NavigationLink(value: PushRoute.substance(name: info.name)) {
                            Text("Show All")
                        }
                    }
                }
            } else {
                // No dose/duration data for this route — keep the substance page
                // reachable through the familiar plain link.
                Section {
                    NavigationLink(value: PushRoute.substance(name: info.name)) {
                        Label("Substance Info", systemImage: "info.circle")
                    }
                }
            }
        }
    }
}
