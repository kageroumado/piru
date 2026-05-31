import SwiftUI

/// A tool surfaced in the Tools tab hub. Each value is pushed as a full-screen
/// destination via `PushRoute.tool`. Kept `nonisolated`/`Codable` so it can ride
/// inside `PushRoute` (state restoration + potential deep links).
nonisolated enum Tool: String, Hashable, Codable, CaseIterable, Identifiable {
    case interactions
    case calculator
    case volumetric
    case recovery
    case pharma

    var id: String {
        rawValue
    }

    /// Row label and pushed-screen title.
    var name: LocalizedStringResource {
        switch self {
        case .interactions: "Interactions"
        case .calculator: "Half-Life Calculator"
        case .volumetric: "Volumetric Dosing"
        case .recovery: "Recovery Guide"
        case .pharma: "Pharma Search"
        }
    }

    /// One-line description shown under the name in the hub list.
    var subtitle: LocalizedStringResource {
        switch self {
        case .interactions: "Check how substances interact"
        case .calculator: "Estimate active levels over time"
        case .volumetric: "Dilute and measure precise doses"
        case .recovery: "Comedown and aftercare tips"
        case .pharma: "Search by receptor and affinity"
        }
    }

    var icon: String {
        switch self {
        case .interactions: "exclamationmark.triangle"
        case .calculator: "hourglass"
        case .volumetric: "drop"
        case .recovery: "heart.text.square"
        case .pharma: "pills"
        }
    }
}

/// The Tools tab root: a hub list of tools, each pushing a full-screen view.
struct ToolsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(Tool.allCases) { tool in
                    NavigationLink(value: PushRoute.tool(tool)) {
                        NavCardLabel(icon: tool.icon, title: Text(tool.name)) {
                            Text(tool.subtitle)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        .appHeader("Tools")
    }
}
