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

    /// Leading inset that aligns the secondary line under the name (past the
    /// colour dot + its spacing).
    private static let textInset: CGFloat = 18

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
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(display.color)
                        .frame(width: 10, height: 10)
                    Text(display.core.displayName)
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    // One coherent line — route · amount · level — differentiated
                    // by weight and colour rather than mixing plain text with a
                    // pill. The dose level qualifies the amount, so it sits next
                    // to it; the route leads as context, the amount and level are
                    // the emphasised data.
                    HStack(spacing: 5) {
                        // Lowercased so the line reads as a phrase — "rectal · 20
                        // mg" — not a title. A no-op for the case-less CJK
                        // localizations.
                        Text(String(localized: display.core.route.localizedName).lowercased())
                            .foregroundStyle(Theme.secondaryLabel)
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                        Text("\(display.core.amount.doseFormatted) \(display.core.unit)")
                            .foregroundStyle(.primary)
                            .fontWeight(.semibold)
                        if let doseLevel = display.core.doseLevel {
                            Text(verbatim: "·").foregroundStyle(.tertiary)
                            // Same weight as the route (regular) — only the
                            // amount carries emphasis; the level reads via colour.
                            Text(String(localized: doseLevel.displayName).lowercased())
                                .foregroundStyle(doseLevel.labelColor)
                        }
                    }
                    .font(.subheadline)
                    if let hr = display.hr {
                        hrChip(hr)
                    }
                    if !display.core.tags.isEmpty {
                        TagChipsView(tags: display.core.tags, compact: true)
                    }
                }
                .padding(.leading, Self.textInset)
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 60)) { _ in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(display.core.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                    if showRelativeTime {
                        Text(relativeTime)
                            .font(.caption)
                    }
                }
                .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, 2)
    }

    /// This dose's heart-rate response: HR at dose → peak within the response
    /// window, the delta, and a mini sparkline of the window. Data-only — the
    /// analysis happens upstream in `SessionDetailView.loadVitals`.
    private func hrChip(_ hr: DoseHRResponse) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 9))
            Text(verbatim: "\(hr.atDose)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Image(systemName: "arrow.right")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: "\(hr.peak)")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(verbatim: "bpm")
            Text(verbatim: "(\(hr.delta >= 0 ? "+" : "")\(hr.delta))")
                .foregroundStyle(.secondary)
            if hr.sparkline.count >= 2 {
                HRSparkline(values: hr.sparkline)
                    .frame(width: 30, height: 11)
                    .padding(.leading, 2)
            }
        }
        .font(.caption)
        .foregroundStyle(VitalsPalette.heart)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(VitalsPalette.heart.opacity(0.14), in: Capsule())
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
