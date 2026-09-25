import Charts
import SwiftData
import SwiftUI

/// Unified "In Your Body" screen — merges the former two-screen split ("In your
/// system" + "In your body over time") into one scrollable view:
///
/// 1. Body-load chart (historic PK curves per substance)
/// 2. Currently active substance cards (remaining amount + decay bar)
/// 3. Projected steady state for regularly dosed substances
/// 4. Related calculators (half-width compact cards)
struct InYourBodyView: View {
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var allEntries: [DoseEntry]
    @Query private var substanceColors: [SubstanceColor]

    @State private var manager = BodyLevelsManager.shared
    @State private var range: UsageTimeRange = .thirtyDays
    /// The chart's substance/category/legend narrowing. Held for the session
    /// only, like the Usage screen's substance filter it mirrors.
    @State private var filter = ModeledLevelsFilter()
    @State private var showingSubstanceSheet = false

    @State private var activeSubstances: [ActiveSubstance] = []
    @State private var projections: [SteadyStateProjection] = []
    @State private var expandedSubstance: String?
    @State private var substanceProjections: [String: SteadyStateProjection] = [:]

    private let compactColumns = [
        GridItem(.flexible(), spacing: Spacing.xl),
        GridItem(.flexible(), spacing: Spacing.xl),
    ]

    private var refreshToken: Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        hasher.combine(ColorsFingerprint.make(substanceColors))
        hasher.combine(range)
        return hasher.finalize()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                chartSection
                // Cross-link for the person who thinks of their serum hormone as
                // "what's in me": the same card the Insights landing shows, pushing to
                // the same Hormone Levels detail (Specs/injection-levels-v3.md §1.2).
                // Gated on an injectable ester being logged.
                if HormoneLevelsLog.hasInjectableHormone(in: allEntries) {
                    HormoneLevelsInsightCard()
                }
                activeSection
                steadyStateSection
                relatedSection
            }
            .padding(.horizontal)
            .padding(.top, Spacing.xs)
            .padding(.bottom, 80)
        }
        .skinBackdrop()
        .toolbar {
            if !allEntries.isEmpty {
                ToolbarItem(placement: .platformTopBarTrailing) { filterMenu }
            }
        }
        .sheet(isPresented: $showingSubstanceSheet) {
            SubstanceFilterSheet(
                substances: filter.substanceRefs(manager.trail?.series ?? []),
                selection: $filter.selectedSubstances,
            )
        }
        .task(id: refreshToken) {
            await SubstanceStore.shared.ensureAllLoaded()
            await manager.refresh(entries: allEntries, colors: substanceColors, range: range)
            let colorMap = substanceColors.colorMap
            activeSubstances = ActiveSubstanceCalculator.compute(from: allEntries, colorMap: colorMap)
            let allProjections = SteadyStateProjectionBuilder.compute(entries: allEntries, colorMap: colorMap)
            projections = allProjections
            substanceProjections = Dictionary(uniqueKeysWithValues: allProjections.map { ($0.id, $0) })
            if let trail = manager.trail {
                filter.setCategories(Dictionary(
                    trail.series.map { ($0.displayName, SubstanceLibrary.lookup($0.displayName)?.category ?? .other) },
                    uniquingKeysWith: { first, _ in first },
                ))
            }
        }
    }

    // MARK: - Toolbar

    /// The Usage screen's filter menu: time range, plus the substance sheet
    /// once more than one substance is modeled.
    private var filterMenu: some View {
        InsightsFilterMenu(
            range: $range,
            selectedCount: filter.selectedSubstances.count,
            offersSubstances: filter.substanceRefs(manager.trail?.series ?? []).count > 1,
            showSubstances: { showingSubstanceSheet = true },
        )
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartSection: some View {
        if allEntries.isEmpty {
            ContentUnavailableView(
                "No Logged Entries",
                systemImage: "waveform.path.ecg",
                description: Text("Add entries to see modeled levels over time."),
            )
            .padding(.top, 40)
        } else if let trail = manager.trail, !trail.isEmpty {
            ModeledLevelsChartCard(trail: trail, range: range, filter: filter)
        } else if manager.trail != nil {
            ContentUnavailableView(
                "Nothing to Model",
                systemImage: "waveform.path.ecg",
                description: Text("None of your logged substances in this range have a modeled elimination curve."),
            )
            .padding(.top, 40)
        } else {
            ProgressView()
                .padding(.top, 60)
        }
    }

    // MARK: - Active substances

    @ViewBuilder
    private var activeSection: some View {
        if !activeSubstances.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Modeled as active")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.leading, Spacing.xs)

                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    VStack(spacing: Spacing.xl) {
                        ForEach(activeSubstances) { active in
                            activeSubstanceCard(active)
                        }
                    }
                }
            }
        }
    }

    private static let maxDosesShown = 10

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
                    projection: substanceProjections[active.name.lowercased()],
                )
                .padding(.top, 14)
            }
        }
        .padding()
        .themeCard()
    }

    // MARK: - Steady state

    @ViewBuilder
    private var steadyStateSection: some View {
        if !projections.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.up.forward.circle")
                        .foregroundStyle(.mint)
                        .font(.subheadline)
                    Text("Projected Steady State")
                        .sectionLabel()
                }

                Text("Where each regularly dosed substance settles, based on your log's cadence")
                    .captionSecondary()

                ForEach(projections) { projection in
                    SteadyStateProjectionCard(projection: projection)
                }
            }
        }
    }

    // MARK: - Related tools

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Related")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.leading, Spacing.xs)

            LazyVGrid(columns: compactColumns, spacing: Spacing.xl) {
                relatedCard(
                    icon: "function",
                    title: "Half-Life Calculator",
                    subtitle: "Model a single dose's decay over time",
                    route: .tool(.calculator),
                )
                relatedCard(
                    icon: "chart.line.flattrend.xyaxis",
                    title: "Steady State",
                    subtitle: "Model a fixed dose schedule's plateau",
                    route: .tool(.steadyState),
                )
            }

            Text("A model estimate, not a measurement. What's in your body and what you feel don't always line up.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.horizontal, Spacing.xs)
        }
    }

    private func relatedCard(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, route: PushRoute) -> some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.piru(.title3))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

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
