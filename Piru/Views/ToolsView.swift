import SwiftUI

struct ToolsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case interactions = "Interactions"
        case calculator = "Calculator"
        case volumetric = "Volumetric"
        case recovery = "Recovery"
        var id: String { rawValue }

        var displayName: LocalizedStringResource {
            switch self {
            case .interactions: "Interactions"
            case .calculator: "Calculator"
            case .volumetric: "Volumetric"
            case .recovery: "Recovery"
            }
        }
    }

    @State private var selectedSection: Section = .interactions

    private var title: LocalizedStringResource {
        switch selectedSection {
        case .interactions: "Interactions"
        case .calculator: "Calculator"
        case .volumetric: "Volumetric Dosing"
        case .recovery: "Recovery Guide"
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
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("Section", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
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
    }
}
