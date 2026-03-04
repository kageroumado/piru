import SwiftUI

struct ToolsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case interactions = "Interactions"
        case calculator = "Calculator"
        var id: String { rawValue }
    }

    @State private var selectedSection: Section = .interactions

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

            switch selectedSection {
            case .interactions:
                InteractionCheckerView()
            case .calculator:
                HalfLifeCalculatorView()
            }
        }
        .background(Theme.background)
        .navigationTitle("Tools")
    }
}
