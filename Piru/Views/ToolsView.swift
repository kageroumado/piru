import SwiftUI

struct ToolsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case interactions = "Interactions"
        case calculator = "Calculator"
        case volumetric = "Volumetric"
        case recovery = "Recovery"
        case pharma = "Pharma"
        var id: String { rawValue }

        var displayName: LocalizedStringResource {
            switch self {
            case .interactions: "Interactions"
            case .calculator: "Calculator"
            case .volumetric: "Volumetric"
            case .recovery: "Recovery"
            case .pharma: "Pharma"
            }
        }

        /// Sections always visible regardless of disclosure tier.
        static let coreSections: [Section] = [.interactions, .calculator, .volumetric, .recovery]
    }

    @State private var selectedSection: Section = .interactions

    /// Pharma search is only exposed on the pharma-nerd tier — keeps the
    /// segmented picker uncluttered for casual + harm-reduction users.
    private var availableSections: [Section] {
        if SubstanceStore.shared.userProfile == .pharmaNerd {
            return Section.coreSections + [.pharma]
        }
        return Section.coreSections
    }

    private var title: LocalizedStringResource {
        switch selectedSection {
        case .interactions: "Interactions"
        case .calculator: "Calculator"
        case .volumetric: "Volumetric Dosing"
        case .recovery: "Recovery Guide"
        case .pharma: "Pharma Search"
        }
    }

    var body: some View {
        Group {
            switch selectedSection {
            case .interactions:
                InteractionCheckerView(toolsSection: $selectedSection)
            case .calculator:
                HalfLifeCalculatorView(toolsSection: $selectedSection)
            case .volumetric:
                VolumetricDosingView(toolsSection: $selectedSection)
            case .recovery:
                ComedownGuideView(toolsSection: $selectedSection)
            case .pharma:
                AdvancedSearchView()
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("Section", selection: $selectedSection) {
                ForEach(availableSections) { section in
                    Text(section.displayName).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Theme.background)
        }
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: SubstanceStore.shared.userProfile) { _, _ in
            // Fall back to interactions if the selected section is no longer
            // available after a profile downgrade.
            if !availableSections.contains(selectedSection) {
                selectedSection = .interactions
            }
        }
    }
}
