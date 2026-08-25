import SwiftData
import SwiftUI

// MARK: - Display metadata

extension InsightGroup {
    var title: LocalizedStringKey {
        switch self {
        case .inYourBody: "In Your Body"
        case .toleranceReceptors: "Tolerance & Receptors"
        }
    }
}

extension Insight {
    /// Row title for the group screen and card headers.
    var cardTitle: LocalizedStringKey {
        switch self {
        case .adherence: "Adherence"
        case .usage: "Usage"
        case .tolerance: "Tolerance"
        case .inSystem: "In your system"
        case .bodyLoad: "In your body over time"
        case .receptorLoad: "Receptor load over time"
        case .steadyStateProjection: "Steady state"
        case .patterns: "Patterns"
        }
    }

    var icon: String {
        switch self {
        case .adherence: "flame.fill"
        case .usage: "chart.bar.fill"
        case .tolerance: "chart.line.downtrend.xyaxis"
        case .inSystem: "hourglass"
        case .bodyLoad: "waveform.path.ecg"
        case .receptorLoad: "chart.xyaxis.line"
        case .steadyStateProjection: "arrow.up.forward.circle"
        case .patterns: "list.clipboard"
        }
    }

    var tint: Color {
        switch self {
        case .adherence: .orange
        case .usage: .blue
        case .tolerance: .purple
        case .inSystem: .teal
        case .bodyLoad: .indigo
        case .receptorLoad: .pink
        case .steadyStateProjection: .mint
        case .patterns: .brown
        }
    }

    /// One-line description shown under the title in a group list.
    var blurb: LocalizedStringKey {
        switch self {
        case .adherence: "Your streak and this month's rate"
        case .usage: "When and how much you log"
        case .tolerance: "Predicted per-mechanism tolerance"
        case .inSystem: "What's still active in your body right now"
        case .bodyLoad: "How body-load has moved over time"
        case .receptorLoad: "How hard each mechanism has been driven over time"
        case .steadyStateProjection: "Where a regular dose settles, from your own cadence"
        case .patterns: "Days used, exposure, dose trend, and overlap"
        }
    }
}

// MARK: - Group screen

/// The middle tier of the Insights two-level push: a group's graphs listed as
/// tappable cards. Only reached for groups with more than one graph; a lone
/// graph is pushed straight from the landing.
struct InsightGroupView: View {
    let group: InsightGroup

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(group.insights) { insight in
                    GlanceCard(
                        icon: insight.icon,
                        tint: insight.tint,
                        titleColor: insight.tint,
                        title: Text(insight.cardTitle),
                        route: .insight(insight),
                    ) {
                        Text(insight.blurb)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .background(Theme.background)
    }
}
