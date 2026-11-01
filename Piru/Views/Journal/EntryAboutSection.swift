import SwiftUI

/// "About <substance>" — the substance screen's dose & duration card
/// (``RouteDosingCard``), filtered to this dose's route, salt form and isomer,
/// with the emphasis on this dose's own tier rather than the typical one. No
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
            let doses = showsLadder ? info.doseRange(for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer) : nil
            let duration = durationVisible ? info.resolveDuration(for: entry.route) : nil
            let releaseWindow = info.routes.first { $0.route == entry.route }?.durationOfAction?.formattedWindow
            if doses?.hasAnyValue == true || duration != nil || releaseWindow != nil {
                Section {
                    RouteDosingCard(
                        route: entry.route,
                        unit: info.unit(for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer),
                        doses: doses,
                        duration: duration,
                        releaseWindow: releaseWindow,
                        elementalFraction: info.elementalFraction(for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer),
                        showsDoseLadder: showsLadder,
                        showsDuration: duration != nil,
                        showsTitle: false,
                        // The classifier behind the hero's strength chip, so the
                        // washed row and the chip always name the same tier.
                        emphasizedLevel: showsLadder ? entry.doseLevel(on: info) : nil,
                    )
                } header: {
                    HStack {
                        // Route-specific card (dose ladder + duration for this
                        // dose's ROA), so the header names the route.
                        Text("About \(CustomSubstanceStore.shared.displayName(for: entry.substance)) (\(entry.route.localizedName))")
                        Spacer()
                        RouteLink(PushRoute.substance(name: info.name)) {
                            Text("Show All")
                        }
                    }
                }
            } else {
                // No dose/duration data for this route — keep the substance page
                // reachable through the familiar plain link.
                Section {
                    RouteLink(PushRoute.substance(name: info.name)) {
                        Label("Substance Info", systemImage: "info.circle")
                    }
                }
            }
        }
    }
}
