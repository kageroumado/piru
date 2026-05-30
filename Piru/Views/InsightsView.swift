import SwiftUI

struct InsightsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case adherence = "Adherence"
        case usage = "Usage"
        var id: String { rawValue }

        var displayName: LocalizedStringResource {
            switch self {
            case .adherence: "Adherence"
            case .usage: "Usage"
            }
        }
    }

    @State private var selectedSection: Section = .adherence

    var body: some View {
        Group {
            switch selectedSection {
            case .adherence:
                AdherenceView()
            case .usage:
                UsageStatsView()
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("Section", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.displayName).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Theme.background)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
