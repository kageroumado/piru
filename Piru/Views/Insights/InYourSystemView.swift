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
    @State private var projections: [String: SteadyStateProjection] = [:]

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
            VStack(spacing: Spacing.xxl) {
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
            await SubstanceStore.shared.ensureAllLoaded()
            cachedActiveSubstances = ActiveSubstanceCalculator.compute(from: allEntries, colorMap: substanceColors.colorMap)
            let allProjections = SteadyStateProjectionBuilder.compute(entries: allEntries, colorMap: substanceColors.colorMap)
            projections = Dictionary(uniqueKeysWithValues: allProjections.map { ($0.id, $0) })
        }
    }

    // MARK: - Active list

    private var activeList: some View {
        VStack(spacing: Spacing.xl) {
            ForEach(cachedActiveSubstances) { active in
                activeSubstanceCard(active)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            Text("Nothing active right now")
                .cardTitle()
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
                HStack(spacing: Spacing.xl) {
                    Circle()
                        .fill(active.color)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(active.name)
                            .sectionLabel()
                            .foregroundStyle(.primary)
                        Text(timeAgoText(active.doses.first?.timestamp))
                            .captionSecondary()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
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
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
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
            .padding(.top, Spacing.lg)

            // Show individual doses if more than one, capped so a substance with
            // dozens of recent ingestions (e.g. a daily medication) doesn't render
            // an unbounded list. The most recent `maxDosesShown` are shown.
            if active.doses.count > 1 {
                VStack(spacing: Spacing.xs) {
                    ForEach(active.doses.prefix(Self.maxDosesShown)) { d in
                        HStack {
                            Text("\(d.amount.doseFormatted) \(active.unit)")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Spacer()
                            Text(Self.doseTimestampText(d.timestamp))
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                            Text("\(d.remaining.doseFormatted) \(active.unit) left")
                                .font(.caption2)
                                .foregroundStyle(active.color.opacity(Theme.Opacity.strong))
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
                .padding(.top, Spacing.md)
            }

            if isExpanded {
                SubstanceEliminationCurve(
                    active: active,
                    projection: projections[active.name.lowercased()],
                )
                .padding(.top, 14)
            }
        }
        .padding()
        .themeCard()
    }

    // MARK: - Cross-link

    private var calculatorLink: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Related")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.leading, Spacing.xs)

            GlanceCard(icon: "function", title: Text("Half-Life Calculator"), route: .tool(.calculator)) {
                Text("Model a single dose's decay over time")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            GlanceCard(icon: "waveform.path.ecg", title: Text("In Your Body"), route: .insight(.bodyLoad)) {
                Text("Body levels over time, with steady-state projections")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            GlanceCard(icon: "chart.line.flattrend.xyaxis", title: Text("Steady State Calculator"), route: .tool(.steadyState)) {
                Text("Model a fixed dose schedule's plateau")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    private static func doseTimestampText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
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
