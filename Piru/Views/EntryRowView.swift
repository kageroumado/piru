import SwiftUI

/// The substance-resolved, render-ready facts about one logged dose, computed
/// **once** when the day's entries change (memoized in `SessionDetailView`'s
/// `resolvedDay`) — never in a row `body`. Resolving the substance + dose level
/// is the expensive part the day detail used to repeat per row on every
/// unrelated screen toggle. Value type + `Equatable` so the row diffs cheaply.
struct DayEntryCore: Equatable {
    let entryID: UUID
    let timestamp: Date
    let displayName: String
    let amount: Double
    let unit: String
    let route: RouteOfAdministration
    let doseLevel: DoseLevel?
    let tags: [String]
    /// The dose's full modeled duration in minutes (onset → afterglow end), used
    /// to draw the row's elimination-progress rail. `nil` when the substance has
    /// no duration data (the rail is then omitted). Static — the live fraction is
    /// computed in the row body from this + the timestamp.
    var totalMinutes: Double?
}

/// A `DayEntryCore` plus the row's resolved colour. Colour is applied at the
/// row-build site (a cheap `colorMap` lookup) rather than memoized with the
/// substance resolve, so a recolour doesn't force the heavy resolve to re-run.
struct DayEntryDisplay: Equatable {
    let core: DayEntryCore
    let color: Color
    /// This dose's Apple Health heart-rate response (HR at dose → peak), when the
    /// session has vitals and the overlay is enabled. Applied at the row-build site
    /// like `color`, so it updates when HealthKit data arrives without re-running
    /// the heavy substance resolve. Nil — the default — renders no chip.
    var hr: DoseHRResponse?

    /// Build render-ready displays for a set of doses — the same resolution
    /// `SessionDetailView` does inline (substance lookup, dose-level classification,
    /// `CustomSubstanceStore` name override, colour map), hoisted so off-screen
    /// consumers (e.g. the share-image renderer) reproduce the on-screen rows
    /// exactly. Caches the per-substance lookup so repeated substances resolve once.
    @MainActor
    static func make(from entries: [DoseEntry], colors: [SubstanceColor]) -> [DayEntryDisplay] {
        let colorMap = colors.colorMap
        var cache: [String: Substance?] = [:]
        func substance(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let cached = cache[key] { return cached }
            let resolved = SubstanceLibrary.lookupByNameOrAlias(name)
            cache[key] = resolved
            return resolved
        }
        return entries.map { entry in
            let doseLevel = substance(entry.substance)?.doseRange(for: entry.route)?.level(for: entry.amount)
            let core = DayEntryCore(
                entryID: entry.id,
                timestamp: entry.timestamp,
                displayName: CustomSubstanceStore.shared.displayName(for: entry.substance),
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route,
                doseLevel: doseLevel,
                tags: entry.tags,
                // Acute effect window (same source as the timeline curve), so the
                // rail matches the graph — not the long elimination tail.
                totalMinutes: ActiveSubstanceState.from(entry: entry, colorHex: "000000")?.totalMinutes,
            )
            return DayEntryDisplay(core: core, color: colorMap[entry.substance.lowercased()] ?? Theme.accent)
        }
    }
}

/// One dose row's content: colour dot + name, the route · amount · level phrase,
/// tags, and the clock/relative time. Renders purely from a `DayEntryDisplay` —
/// it does **no** substance lookup of its own (that happens once, upstream).
struct EntryRowView: View {
    let display: DayEntryDisplay
    /// Whether to show the "13h ago" relative line under the clock time. Set by
    /// the day detail for today/yesterday so every row in a recent day matches;
    /// older days show the clock time alone, keeping the column symmetric.
    var showRelativeTime: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Elapsed time since the dose, e.g. "45m ago", "13h 25m ago", or "1d ago".
    private var relativeTime: String {
        let elapsed = max(0, Date.now.timeIntervalSince(display.core.timestamp))
        let totalMinutes = Int(elapsed / 60)
        guard totalMinutes >= 1 else { return String(localized: "just now") }
        let hours = totalMinutes / 60
        if hours >= 24 {
            let days = hours / 24
            return String(localized: "\(days)d ago")
        }
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return String(localized: "\(hours)h \(minutes)m ago")
        } else if hours > 0 {
            return String(localized: "\(hours)h ago")
        } else {
            return String(localized: "\(minutes)m ago")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes the one-line layout would truncate both
                // the name and the dose to "…", so stack them: name cluster on
                // top, the dose (still the hero) on its own line below.
                VStack(alignment: .leading, spacing: 4) {
                    nameCluster(nameLineLimit: 2)
                    HStack(alignment: .center, spacing: 8) {
                        doseText
                        Spacer(minLength: 8)
                        chevron
                    }
                }
            } else {
                // Dot · name · ROA pill on the left; the dose — the hero, in the
                // same rounded face as the detail card — and the disclosure chevron
                // on the right. Centre-aligned so the name, pill, dose, and chevron
                // all sit on one line at the dose's height.
                HStack(alignment: .center, spacing: 8) {
                    nameCluster(nameLineLimit: 1)
                    Spacer(minLength: 8)
                    doseText
                    chevron
                }
            }

            if let hr = display.hr {
                hrChip(hr)
            }

            eliminationFooter
        }
        .padding(.vertical, 1)
    }

    private func nameCluster(nameLineLimit: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(display.color)
                .accessibilityHidden(true)
            Text(display.core.displayName)
                .font(.body.weight(.semibold))
                .lineLimit(nameLineLimit)
            roaPill
        }
    }

    /// Coloured by its dose level (common/strong/heavy…) so the level reads
    /// without a text label.
    private var doseText: some View {
        Text("\(display.core.amount.doseFormatted) \(display.core.unit)")
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(display.core.doseLevel?.labelColor ?? .primary)
            .lineLimit(1)
            .accessibilityLabel(doseAccessibilityLabel)
    }

    private var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// The route badge — a tinted capsule in the route's *own* fixed colour (every
    /// "oral" pill matches), not the substance's colour.
    private var roaPill: some View {
        let tint = display.core.route.tintColor
        return Text(String(localized: display.core.route.localizedName).lowercased())
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    /// The dose's elimination-progress rail (when the substance has a modeled
    /// duration) above the clock time + relative "ago / left" — refreshed each
    /// minute so an active dose's fill and countdown stay live. The (unimportant)
    /// tags ride quietly at the trailing edge when the dose is no longer active.
    private var eliminationFooter: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let elapsed = max(0, now.timeIntervalSince(display.core.timestamp) / 60)
            let total = display.core.totalMinutes
            let active = total.map { elapsed < $0 } ?? false

            VStack(alignment: .leading, spacing: 5) {
                // The rail is only meaningful while the dose is still eliminating —
                // a fully-worn-off dose shows just its time, no spent bar.
                if let total, active {
                    GeometryReader { geo in
                        let fraction = min(1, max(0, elapsed / total))
                        ZStack(alignment: .leading) {
                            Capsule().fill(display.color.opacity(0.14))
                            Capsule()
                                .fill(display.color.opacity(0.6))
                                .frame(width: max(0, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 3)
                }

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        // The side-by-side columns compress at accessibility sizes
                        // until the clock time wraps mid-token ("3:33 A / M") —
                        // stack them instead, each line free to use the full width.
                        VStack(alignment: .leading, spacing: 2) {
                            timeLine
                            trailingLine(active: active, total: total, now: now)
                        }
                    } else {
                        HStack(spacing: 0) {
                            timeLine
                            Spacer(minLength: 8)
                            trailingLine(active: active, total: total, now: now)
                                .lineLimit(1)
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()
            }
        }
    }

    /// Clock time plus the optional "8h ago" relative phrase.
    private var timeLine: some View {
        HStack(spacing: 0) {
            Text(display.core.timestamp.formatted(date: .omitted, time: .shortened))
            if showRelativeTime {
                Text(verbatim: "  ·  ").foregroundStyle(.tertiary)
                Text(relativeTime)
            }
        }
    }

    /// Tags then the dose-strength label ("Common"/"Strong"/…), in the same gray
    /// as the time — the colour ladder alone reads as ambiguous, so the level is
    /// spelled out. The live countdown takes this slot while a dose is active.
    @ViewBuilder
    private func trailingLine(active: Bool, total: Double?, now: Date) -> some View {
        if active, let total {
            Text(remainingText(total: total, now: now))
        } else if let meta = trailingMeta {
            Text(meta)
        }
    }

    /// The row's trailing metadata: the (unimportant) tags followed by the dose's
    /// strength label — all one gray. Nil when there's neither.
    private var trailingMeta: String? {
        var parts = display.core.tags
        if let level = display.core.doseLevel {
            parts.append(String(localized: level.displayName).lowercased())
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "1h 4m left" — the modeled time until this dose's effects fully fade.
    private func remainingText(total: Double, now: Date) -> String {
        let remaining = total * 60 - now.timeIntervalSince(display.core.timestamp)
        return String(localized: "\(remaining.durationHM) left")
    }

    /// VoiceOver spells out the dose *and* its level, since the level is conveyed
    /// only by colour on screen.
    private var doseAccessibilityLabel: Text {
        let dose = "\(display.core.amount.doseFormatted) \(display.core.unit)"
        guard let level = display.core.doseLevel else { return Text(dose) }
        return Text("\(dose), \(String(localized: level.displayName))")
    }

    /// This dose's heart-rate response: HR at dose → peak within the response
    /// window, the delta, and a mini sparkline of the window. Data-only — the
    /// analysis happens upstream in `SessionDetailView.loadVitals`.
    private func hrChip(_ hr: DoseHRResponse) -> some View {
        // Quiet inline metric (Option A): a heart glyph in the vitals hue with the
        // numbers in the label colour — reads as data, not a coloured pill.
        HStack(spacing: 5) {
            Image(systemName: "heart.fill")
                .font(.system(size: 9))
                .foregroundStyle(VitalsPalette.heart)
            Text(verbatim: "\(hr.atDose)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Image(systemName: "arrow.right")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(verbatim: "\(hr.peak)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text("bpm")
                .foregroundStyle(.secondary)
            Text(verbatim: "\(hr.delta >= 0 ? "+" : "")\(hr.delta)")
                .foregroundStyle(VitalsPalette.heart)
            if hr.sparkline.count >= 2 {
                HRSparkline(values: hr.sparkline)
                    .frame(width: 34, height: 12)
                    .padding(.leading, 2)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart rate \(hr.atDose) rising to \(hr.peak) beats per minute"))
    }
}

/// A tiny line sparkline of heart-rate values, min–max normalised to its frame.
private struct HRSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return }
                let span = max(1, hi - lo)
                for (index, value) in values.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = geo.size.height * (1 - CGFloat((value - lo) / span))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(VitalsPalette.heart, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
    }
}
