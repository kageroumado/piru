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

    private var title: String {
        switch selectedSection {
        case .interactions: "Interactions"
        case .calculator: "Calculator"
        case .volumetric: "Volumetric Dosing"
        case .recovery: "Recovery Guide"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

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
        }
        .background(Theme.background)
        .navigationTitle(title)
    }
}
