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
    /// no duration data, or when the dose names a form we decline to model (a
    /// Concerta, a depot injection) — the rail is then omitted, matching the
    /// graph, which marks the dose rather than drawing it.
    var totalMinutes: Double?
    /// The color-map key — the canonical substance string, not the title. A
    /// Concerta row titles "Concerta" but must take Methylphenidate's color, or
    /// the same substance would render in two colors depending on what it was
    /// called.
    let substanceKey: String
    /// Whether the logged amount is the user's estimate — draws a leading `~`.
    let isApproximate: Bool

    /// Resolve each dose row's substance facts once: title, dose level, and the
    /// rail's window.
    ///
    /// The single builder for both `EntryRowView.make` (journal, share images) and
    /// `SessionDetailView` (session rows), which carried byte-identical copies of
    /// this and drifted — the session's markers still named substances differently
    /// from the journal's. Caches the per-substance lookup so repeated substances
    /// in a day resolve once.
    @MainActor
    static func make(from entries: [DoseEntry]) -> [DayEntryCore] {
        var cache: [String: Substance?] = [:]
        func substance(_ name: String) -> Substance? {
            let key = name.lowercased()
            if let cached = cache[key] { return cached }
            let resolved = SubstanceLibrary.lookup(name)
            cache[key] = resolved
            return resolved
        }
        return entries.map { entry in
            // Classify against the ladder the dose was actually logged on. Omitting
            // the facets read a 10 mg Dexmethylphenidate dose — "common" on the D
            // ladder and shown as such in the staged editor — as "light" against
            // racemic methylphenidate's, and disagreed with `EntryDetailView`'s
            // edit mode, so tapping Edit visibly flipped the badge.
            let doseLevel = substance(entry.substance)?
                .doseRange(for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer)?
                .level(for: entry.amount)
            return DayEntryCore(
                entryID: entry.id,
                timestamp: entry.timestamp,
                displayName: DoseTitle.resolve(for: entry),
                amount: entry.amount,
                unit: entry.unit,
                route: entry.route,
                doseLevel: doseLevel,
                tags: entry.tags,
                // Acute effect window (same source as the timeline curve), so the
                // rail matches the graph — not the long elimination tail.
                totalMinutes: ActiveSubstanceState.from(entry: entry, colorHex: "000000")?.totalMinutes,
                substanceKey: entry.substance.lowercased(),
                isApproximate: entry.isApproximate,
            )
        }
    }
}

/// A `DayEntryCore` plus the row's resolved color. Color is applied at the
/// row-build site (a cheap `colorMap` lookup) rather than memoized with the
/// substance resolve, so a recolor doesn't force the heavy resolve to re-run.
struct DayEntryDisplay: Equatable {
    let core: DayEntryCore
    let color: Color
    /// This dose's Apple Health heart-rate response (HR at dose → peak), when the
    /// session has vitals and the overlay is enabled. Applied at the row-build site
    /// like `color`, so it updates when HealthKit data arrives without re-running
    /// the heavy substance resolve. Nil — the default — renders no chip.
    var hr: DoseHRResponse?

    /// Build render-ready displays for a set of doses. Hoisted so off-screen
    /// consumers (e.g. the share-image renderer) reproduce the on-screen rows
    /// exactly.
    @MainActor
    static func make(from entries: [DoseEntry], colors: [SubstanceColor]) -> [DayEntryDisplay] {
        let colorMap = colors.colorMap
        return DayEntryCore.make(from: entries).map { core in
            DayEntryDisplay(core: core, color: colorMap[core.substanceKey] ?? Theme.accent)
        }
    }
}

/// One dose row's content: color dot + name, the route · amount · level phrase,
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
                // on the right. Center-aligned so the name, pill, dose, and chevron
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

            if !display.core.tags.isEmpty {
                tagRow
            }
        }
        .padding(.vertical, 1)
    }

    /// Tags on their own line as unfilled, bordered pills — pulled off the meta
    /// line (where they used to fight the clock time hard enough to wrap "PM"
    /// mid-token) and given a distinct outlined grammar so a rarely-used tag reads
    /// as a quiet annotation rather than another filled badge.
    private var tagRow: some View {
        HStack(spacing: 6) {
            ForEach(display.core.tags, id: \.self) { tag in
                Text(tag).capsuleOutlineChip()
            }
        }
        .accessibilityElement(children: .combine)
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

    /// The primary label color (black in light, white in dark) — the dose is the
    /// row's hero, and the strength tier is carried separately by the ``strengthChip``
    /// below, so the dose itself needn't double as a tier color.
    private var doseText: some View {
        MeasurementLabel(amount: display.core.amount, unit: display.core.unit, isApproximate: display.core.isApproximate)
            .accessibilityLabel(doseAccessibilityLabel)
    }

    private var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// The route badge — a tinted capsule in the route's *own* fixed color (every
    /// "oral" pill matches), not the substance's color.
    private var roaPill: some View {
        ROAPill(route: display.core.route, size: .compact)
    }

    /// The strength badge ("light"/"common"/"heavy"…) — same capsule grammar as
    /// the route pill, tinted by the level's color so the tier reads as color
    /// *and* text at all times. It used to be a gray word that the live countdown
    /// displaced, hiding the tier exactly while the dose was active.
    @ViewBuilder
    private var strengthChip: some View {
        if let level = display.core.doseLevel {
            Text(String(localized: level.displayName).lowercased())
                .capsuleChip(text: level.labelColor, fill: level.swiftUIColor)
                // VoiceOver already gets the level through the dose's label.
                .accessibilityHidden(true)
        }
    }

    /// The clock time + relative "ago" with the persistent strength chip, and —
    /// while the dose is active — the elimination-progress rail with its live
    /// countdown alongside, refreshed each minute. The rail line reads
    /// left-to-right as "how far along → how much left"; a fully-worn-off dose
    /// shows no rail.
    private var eliminationFooter: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let elapsed = max(0, now.timeIntervalSince(display.core.timestamp) / 60)
            let total = display.core.totalMinutes
            let active = total.map { elapsed < $0 } ?? false

            VStack(alignment: .leading, spacing: 7) {
                if dynamicTypeSize.isAccessibilitySize {
                    // The side-by-side columns compress at accessibility sizes
                    // until the clock time wraps mid-token ("3:33 A / M") —
                    // stack them instead, each line free to use the full width.
                    VStack(alignment: .leading, spacing: 4) {
                        metaTextLine
                        strengthChip
                    }
                } else {
                    HStack(spacing: 8) {
                        metaTextLine
                        Spacer(minLength: 8)
                        strengthChip
                    }
                }

                if let total, active {
                    railRow(elapsed: elapsed, total: total, now: now)
                }
            }
        }
    }

    /// Clock time and the relative "ago" — one gray line. Tags moved to their own
    /// ``tagRow`` so they can't crowd the clock time.
    private var metaTextLine: some View {
        timeLine
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryLabel)
            .monospacedDigit()
    }

    /// The elimination-progress rail with the live countdown at its trailing
    /// edge — the number sits beside the bar it measures.
    private func railRow(elapsed: Double, total: Double, now: Date) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                let fraction = min(1, max(0, elapsed / total))
                ZStack(alignment: .leading) {
                    Capsule().fill(display.color.opacity(0.10))
                    Capsule()
                        .fill(display.color.opacity(0.6))
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 3)
            Text(remainingText(total: total, now: now))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
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

    /// "1h 4m left" — the modeled time until this dose's effects fully fade.
    private func remainingText(total: Double, now: Date) -> String {
        let remaining = total * 60 - now.timeIntervalSince(display.core.timestamp)
        return String(localized: "\(remaining.durationHM) left")
    }

    /// VoiceOver spells out the dose *and* its level, since the level is conveyed
    /// only by color on screen.
    private var doseAccessibilityLabel: Text {
        let formatted = display.core.amount.doseFormatted
        let dose = display.core.isApproximate
            ? String(localized: "approximately \(formatted) \(display.core.unit)")
            : "\(formatted) \(display.core.unit)"
        guard let level = display.core.doseLevel else { return Text(dose) }
        return Text("\(dose), \(String(localized: level.displayName))")
    }

    /// This dose's heart-rate response: HR at dose → peak within the response
    /// window, the delta, and a mini sparkline of the window. Data-only — the
    /// analysis happens upstream in `SessionDetailView.loadVitals`.
    private func hrChip(_ hr: DoseHRResponse) -> some View {
        // Quiet inline metric (Option A): a heart glyph in the vitals hue with the
        // numbers in the label color — reads as data, not a colored pill.
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

/// A tiny line sparkline of heart-rate values, min–max normalized to its frame.
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
