import SwiftUI

/// One logged substance's tolerance readout: **every** mechanism class it drives (MDMA touches DAT/NET,
/// SERT and 5-HT2A, each with its own level), highest-severity first, plus its dose history. Only
/// substances the model actually scored appear — the "can't predict yet" set stays in its own section.
struct ToleranceSubstanceGroup: Identifiable {
    let name: String
    let displayName: String
    let doses: [DoseEntry]
    /// The mechanism classes this substance contributes to, sorted by severity (worst first).
    let classes: [ClassTolerance]

    var id: String {
        name
    }

    /// The substance's worst mechanism — drives the leading dot's color and the list ordering.
    var topSeverity: Double {
        classes.first?.severity ?? 0
    }
}

/// The **By substance** detail: one card per scored substance, each with its per-mechanism levels and
/// (expandable) dose history. Shows a spinner while the heavier per-substance replay is still running.
struct TolerancePerSubstanceSection: View {
    let groups: [ToleranceSubstanceGroup]
    let tier: UserProfile
    /// The per-substance replay is still running (first entry into this view) — show a spinner rather
    /// than the "log a few doses" empty copy.
    let isReplayRunning: Bool
    @Binding var expandedSubstances: Set<String>

    var body: some View {
        if groups.isEmpty {
            Section {
                if isReplayRunning {
                    HStack(spacing: Spacing.md) {
                        ProgressView()
                        Text("Calculating each substance's contribution…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .padding(.vertical, Spacing.xs)
                } else {
                    Text("Log a few doses and each substance's tolerance shows up here.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.vertical, Spacing.xs)
                }
            }
        } else {
            Section {
                Label("Each card is that substance's own contribution. Mechanisms are shared, so your overall level (the chart above, or By mechanism) can be higher.", systemImage: "person.fill.viewfinder")
                    .captionSecondary()
                    .padding(.vertical, Spacing.xs)
            }
            ForEach(groups) { group in
                Section {
                    ToleranceSubstanceCard(group: group, tier: tier, expandedSubstances: $expandedSubstances)
                }
            }
        }
    }
}

struct ToleranceSubstanceCard: View {
    let group: ToleranceSubstanceGroup
    let tier: UserProfile
    @Binding var expandedSubstances: Set<String>

    /// Most doses shown when a card is expanded — enough to see the recent pattern without a
    /// hundreds-row wall (a heavy caffeine log runs to hundreds of rows, which would bury the rest).
    private static let expandedDoseLimit = 20

    var body: some View {
        let topColor = group.classes.first?.receptorClass.familyColor ?? .secondary
        let expanded = expandedSubstances.contains(group.name)
        let total = group.doses.count
        let cap = min(total, Self.expandedDoseLimit)
        let shown = expanded ? Array(group.doses.prefix(cap)) : Array(group.doses.prefix(3))
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(spacing: Spacing.md) {
                LegendDot(color: topColor, size: .large)
                Text(group.displayName)
                    .cardTitle()
                Spacer(minLength: 8)
            }

            // Every mechanism this substance drives, each with its own level and family-colored bar.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ForEach(group.classes) { snapshot in
                    ToleranceMechanismRow(
                        color: snapshot.receptorClass.familyColor,
                        name: toleranceClassName(snapshot.receptorClass, tier: tier),
                        word: ToleranceBucket(responseFraction: snapshot.responseFraction).word,
                        severity: snapshot.severity,
                    )
                }
            }

            Divider()

            VStack(spacing: Spacing.md) {
                ForEach(shown) { entry in
                    ToleranceDoseRow(entry: entry)
                    if entry.id != shown.last?.id { Divider() }
                }
            }

            if total > 3 {
                Button {
                    toggleExpanded(group.name)
                } label: {
                    Text(collapsedLabel(total: total, expanded: expanded))
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    /// The expand/collapse button's label: "Show less" when open, otherwise "Show all N doses" (when
    /// they all fit) or "Show 20 latest doses" (when the log is capped).
    private func collapsedLabel(total: Int, expanded: Bool) -> LocalizedStringResource {
        if expanded { return "Show less" }
        return total > Self.expandedDoseLimit
            ? "Show \(Self.expandedDoseLimit) latest doses"
            : "Show all \(total) doses"
    }

    private func toggleExpanded(_ name: String) {
        if expandedSubstances.contains(name) {
            expandedSubstances.remove(name)
        } else {
            expandedSubstances.insert(name)
        }
    }
}

/// One mechanism line inside a per-substance card: the class name + its tolerance word, over a slim
/// family-colored level bar.
struct ToleranceMechanismRow: View {
    let color: Color
    let name: LocalizedStringResource
    let word: LocalizedStringResource
    let severity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Spacing.md) {
                LegendDot(color: color, size: .compact)
                Text(name)
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(word)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(Theme.Opacity.tintActive))
                    Capsule().fill(color)
                        .frame(width: max(0, geo.size.width * min(1, max(0, severity))))
                }
            }
            .frame(height: 7)
        }
    }
}

/// One dose in a per-substance card — the Your-History row layout (amount + route on the left, the
/// timestamp on the right) so the two screens read identically.
struct ToleranceDoseRow: View {
    let entry: DoseEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(entry.amount.doseFormatted) \(entry.unit)")
                    .font(.subheadline)
                Text(entry.route.localizedName)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Spacer()
            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                .captionSecondary()
        }
    }
}
