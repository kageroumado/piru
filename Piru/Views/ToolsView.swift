import SwiftUI

/// A tool surfaced in the Tools tab hub. Each value is pushed as a full-screen
/// destination via `PushRoute.tool`. Kept `nonisolated`/`Codable` so it can ride
/// inside `PushRoute` (state restoration + potential deep links).
nonisolated enum Tool: String, Hashable, Codable, Sendable, CaseIterable, Identifiable {
    case interactions
    case calculator
    case volumetric
    case recovery
    case pharma

    var id: String { rawValue }

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

    /// Tools always available regardless of disclosure tier.
    static let coreTools: [Tool] = [.interactions, .calculator, .volumetric, .recovery]
}

/// The Tools tab root: a hub list of tools, each pushing a full-screen view.
/// Pharma search is only exposed on the pharma-nerd tier.
struct ToolsView: View {
    @Environment(\.appNavigator) private var navigator

    private var availableTools: [Tool] {
        SubstanceStore.shared.userProfile == .pharmaNerd
            ? Tool.coreTools + [.pharma]
            : Tool.coreTools
    }

    var body: some View {
        List {
            ForEach(availableTools) { tool in
                NavigationLink(value: PushRoute.tool(tool)) {
                    HStack(spacing: 14) {
                        Image(systemName: tool.icon)
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                            Text(tool.subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Tools")
    }
}
