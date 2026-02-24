import SwiftUI

struct InsightsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case adherence = "Adherence"
        case usage = "Usage"
        case halfLife = "Half-Life"
        case chat = "AI Chat"
        var id: String { rawValue }
    }

    @State private var selectedSection: Section = .adherence

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
            case .adherence:
                AdherenceView()
            case .usage:
                UsageStatsView()
            case .halfLife:
                HalfLifeCalculatorView()
            case .chat:
                ChatView()
            }
        }
        .navigationTitle("Insights")
    }
}
