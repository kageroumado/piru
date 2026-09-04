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
    @State private var hidden: Set<Int> = []
    @State private var selectedDate: Date?
    @State private var selectedCategory: SubstanceCategory?
    @State private var seriesCategories: [Int: SubstanceCategory] = [:]

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
                activeSection
                steadyStateSection
                relatedSection
            }
            .padding(.horizontal)
            .padding(.top, Spacing.xs)
            .padding(.bottom, 80)
        }
        .background(Theme.background)
        .toolbar {
            if !allEntries.isEmpty {
                ToolbarItem(placement: .platformTopBarTrailing) { rangeMenu }
            }
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
                seriesCategories = Dictionary(uniqueKeysWithValues: trail.series.map {
                    ($0.id, SubstanceLibrary.lookup($0.displayName)?.category ?? .other)
                })
            }
        }
    }

    // MARK: - Toolbar

    private var rangeMenu: some View {
        Menu {
            Picker("Time Range", selection: $range) {
                ForEach(UsageTimeRange.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            Text(range.displayName)
                .sectionLabel()
        }
        .onChange(of: range) { selectedDate = nil }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartSection: some View {
        if allEntries.isEmpty {
            ContentUnavailableView(
                "No Logged Entries",
                systemImage: "waveform.path.ecg",
                description: Text("Log some doses to see what's been in your body over time."),
            )
            .padding(.top, 40)
        } else if let trail = manager.trail, !trail.isEmpty {
            chartCard(trail)
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

    private func chartCard(_ trail: BodyLoadTrail) -> some View {
        UsageSectionCard(title: "In your body over time", subtitle: "Each line as a share of its own peak") {
            let filtered = filteredSeries(from: trail)
            let visible = filtered.filter { !hidden.contains($0.id) }
            let series = visible.isEmpty ? filtered : visible
            BodyLoadChart(series: series, dates: trail.dates, selectedDate: $selectedDate)
            if let selectedDate {
                BodyLoadReadout(series: series, date: selectedDate)
            }
            if categories(for: trail).count > 1 {
                categoryFilter(trail)
            }
            legend(trail)
        }
    }

    // MARK: - Category filter

    private func categories(for trail: BodyLoadTrail) -> [(category: SubstanceCategory, count: Int)] {
        var counts: [SubstanceCategory: Int] = [:]
        for item in trail.series {
            counts[seriesCategories[item.id] ?? .other, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private func filteredSeries(from trail: BodyLoadTrail) -> [BodyLoadTrail.Series] {
        guard let cat = selectedCategory else { return trail.series }
        return trail.series.filter { (seriesCategories[$0.id] ?? .other) == cat }
    }

    private func categoryFilter(_ trail: BodyLoadTrail) -> some View {
        FlowLayout(spacing: Spacing.sm) {
            let cats = categories(for: trail)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCategory = nil
                    hidden.removeAll()
                }
            } label: {
                Text("All")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 5)
                    .background(selectedCategory == nil ? Theme.accent.opacity(0.15) : Color.platformTertiarySystemFill)
                    .foregroundStyle(selectedCategory == nil ? Theme.accent : .primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            ForEach(cats, id: \.category) { entry in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = selectedCategory == entry.category ? nil : entry.category
                        hidden.removeAll()
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        LegendDot(color: entry.category.color, size: .compact)
                        Text(entry.category.displayName)
                            .font(.caption2.weight(.medium))
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 5)
                    .background(selectedCategory == entry.category ? entry.category.color.opacity(0.15) : Color.platformTertiarySystemFill)
                    .foregroundStyle(selectedCategory == entry.category ? entry.category.color : .primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Legend

    private func legend(_ trail: BodyLoadTrail) -> some View {
        let filtered = filteredSeries(from: trail)
        return FlowLayout(spacing: Spacing.md) {
            ForEach(filtered) { item in
                legendChip(item)
            }
        }
    }

    private func legendChip(_ item: BodyLoadTrail.Series) -> some View {
        let isHidden = hidden.contains(item.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isHidden { hidden.remove(item.id) } else { hidden.insert(item.id) }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                LegendDot(color: item.color)
                    .opacity(isHidden ? 0.3 : 1)
                Text(item.displayName)
                    .font(.caption2)
                    .foregroundStyle(isHidden ? Theme.secondaryLabel : .primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.displayName))
        .accessibilityValue(isHidden ? Text("Hidden") : Text("Shown"))
        .accessibilityHint(Text("Toggles this substance's line"))
        .accessibilityAddTraits(isHidden ? [] : [.isSelected])
    }

    // MARK: - Active substances

    @ViewBuilder
    private var activeSection: some View {
        if !activeSubstances.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("In your system")
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
                    .font(.title3)
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
