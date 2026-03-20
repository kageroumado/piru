import SwiftUI

struct ToolsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case interactions = "Interactions"
        case calculator = "Calculator"
        case volumetric = "Volumetric"
        case recovery = "Recovery"
        var id: String { rawValue }
    }

    @State private var selectedSection: Section = .interactions

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
            }
        }
        .background(Theme.background)
    }
}
