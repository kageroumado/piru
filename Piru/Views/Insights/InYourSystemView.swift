import SwiftData
import SwiftUI

/// "In your system" — a read-only glance at what's still active in the body,
/// with a per-substance elimination curve. Split out from
/// ``HalfLifeCalculatorView`` (`Tool.calculator`) so each screen has a single
/// responsibility; a cross-link row at the bottom jumps to the calculator.
struct InYourSystemView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var cachedActiveSubstances: [ActiveSubstance] = []
    @State private var expandedSubstance: String?

    /// Cap on individual ingestion rows shown per active substance — a daily
    /// medication can accumulate dozens of in-system doses; show the most
    /// recent few and summarize the rest.
    private static let maxDosesShown = 10

    /// Recompute token: the dose-log revision plus the color assignments.
    private var refreshToken: Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        hasher.combine(ColorsFingerprint.make(substanceColors))
        return hasher.finalize()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if cachedActiveSubstances.isEmpty {
                    emptyState
                } else {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        activeList
                    }
                }

                calculatorLink
            }
            .padding()
        }
        .background(Theme.background)
        .task(id: refreshToken) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            cachedActiveSubstances = ActiveSubstanceCalculator.compute(from: allEntries, colorMap: substanceColors.colorMap)
        }
    }

    // MARK: - Active list

    private var activeList: some View {
        VStack(spacing: 12) {
            ForEach(cachedActiveSubstances) { active in
                activeSubstanceCard(active)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            Text("Nothing active right now")
                .font(.headline)
            Text("Substances you log will appear here while they're still estimated to be in your body.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal)
        .themeCard()
    }

    private func activeSubstanceCard(_ active: ActiveSubstance) -> some View {
        let isExpanded = expandedSubstance == active.name

        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.3)) {
                    expandedSubstance = isExpanded ? nil : active.name
                }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(active.color)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(active.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(timeAgoText(active.doses.first?.timestamp))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(active.totalRemaining.doseFormatted)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(active.color)
                            Text(active.unit)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        Text("\(Int(active.eliminatedFraction * 100))% eliminated")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            // Decay progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(active.color.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(active.color)
                        .frame(width: geo.size.width * (1 - active.eliminatedFraction), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.top, 10)

            // Show individual doses if more than one, capped so a substance with
            // dozens of recent ingestions (e.g. a daily medication) doesn't render
            // an unbounded list. The most recent `maxDosesShown` are shown.
            if active.doses.count > 1 {
                VStack(spacing: 4) {
                    ForEach(active.doses.prefix(Self.maxDosesShown)) { d in
                        HStack {
                            Text("\(d.amount.doseFormatted) \(active.unit)")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Spacer()
                            Text(d.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Text("\(d.remaining.doseFormatted) \(active.unit) left")
                                .font(.caption2)
                                .foregroundStyle(active.color.opacity(0.8))
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if active.doses.count > Self.maxDosesShown {
                        HStack {
                            Text("+\(active.doses.count - Self.maxDosesShown) earlier")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 8)
            }

            // Expandable elimination curve
            if isExpanded {
                SubstanceEliminationCurve(active: active)
                    .padding(.top, 14)
            }
        }
        .padding()
        .themeCard()
    }

    // MARK: - Cross-link

    private var calculatorLink: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.leading, 4)

            GlanceCard(icon: "function", title: Text("Half-Life Calculator"), route: .tool(.calculator)) {
                Text("Model a single dose's decay over time")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            GlanceCard(icon: "chart.line.flattrend.xyaxis", title: Text("Steady State"), route: .tool(.steadyState)) {
                Text("Where a med taken on a schedule settles")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    private func timeAgoText(_ date: Date?) -> String {
        guard let date else { return "" }
        let elapsed = Date.now.timeIntervalSince(date)
        if elapsed < 60 { return String(localized: "Just now") }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return String(localized: "\(minutes)m ago") }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "\(hours)h ago") }
        let days = hours / 24
        return String(localized: "\(days)d ago")
    }
}
