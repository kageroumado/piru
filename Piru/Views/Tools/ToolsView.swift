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
    case ceiling
    case benzoEquivalence
    case opioidEquivalence
    case toleranceInfo
    case inventory
    case effectSandbox
    case steadyState
    case drugClasses

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
        case .ceiling: "Ceiling Effect"
        case .benzoEquivalence: "Benzo Equivalence"
        case .opioidEquivalence: "Opioid Equivalence"
        case .toleranceInfo: "How Tolerance Works"
        case .inventory: "Inventory"
        case .effectSandbox: "Effect Estimator"
        case .steadyState: "Steady State"
        case .drugClasses: "Drug Classes"
        }
    }

    /// One-line description shown under the name in the hub list.
    var subtitle: LocalizedStringResource {
        switch self {
        case .interactions: "Check how substances interact"
        case .calculator: "Estimate active levels over time"
        case .volumetric: "Dilute and measure precise doses"
        case .recovery: "Comedown and aftercare tips"
        case .pharma: "Browse pharmacokinetics for every substance"
        case .ceiling: "When dose and exposure aren't proportional"
        case .benzoEquivalence: "Compare benzodiazepine doses to diazepam"
        case .opioidEquivalence: "Convert opioid doses to morphine (MME)"
        case .toleranceInfo: "Why effects fade and how receptors recover"
        case .inventory: "Track how much you have on hand"
        case .effectSandbox: "Compare substances and preview how they may feel"
        case .steadyState: "Where a repeated dose settles, and when"
        case .drugClasses: "What the members of a family share"
        }
    }

    var icon: String {
        switch self {
        case .interactions: "exclamationmark.triangle"
        case .calculator: "hourglass"
        case .volumetric: "drop"
        case .recovery: "heart.text.square"
        case .pharma: "pills"
        case .ceiling: "chart.line.uptrend.xyaxis"
        case .benzoEquivalence: "moon.fill"
        case .opioidEquivalence: "cross.case"
        case .toleranceInfo: "chart.line.downtrend.xyaxis"
        case .inventory: "shippingbox"
        case .effectSandbox: "slider.horizontal.2.square"
        case .steadyState: "chart.line.flattrend.xyaxis"
        case .drugClasses: "square.stack.3d.up"
        }
    }
}

/// The Tools tab root: a hub of tools, each pushing a full-screen view.
///
/// Two safety-relevant tools lead as richer summary cards that glance their
/// current state — Interactions surfaces the most important active interactions
/// (``InteractionsSummaryCard``), Inventory shows what's low
/// (``InventorySummaryCard``). The learn-oriented screens (ceiling effect,
/// tolerance, recovery) are grouped under an expandable ``EducationCard``.
struct ToolsView: View {
    /// Plain tools rendered as rows, in order.
    private let rowTools: [Tool] = [.effectSandbox, .calculator, .steadyState, .volumetric, .benzoEquivalence, .opioidEquivalence, .pharma]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                EducationCard()

                InteractionsSummaryCard()
                InventorySummaryCard()

                ForEach(rowTools) { tool in
                    GlanceCard(icon: tool.icon, title: Text(tool.name), route: .tool(tool)) {
                        Text(tool.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        .appNavigationBar("Tools")
    }
}
