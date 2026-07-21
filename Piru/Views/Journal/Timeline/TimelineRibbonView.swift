import SwiftUI

/// The continuous multi-day dose-effect ribbon: a horizontally scrolling
/// `LazyHStack` of fixed-width time tiles, right edge anchored just past *now*,
/// scrolling back through history. Time is continuous here — sessions are an
/// analysis artifact, so curves flow straight across day and session seams.
///
/// Tiles are **wall-clock-aligned 6 h slots** (00 / 06 / 12 / 18) so day
/// boundaries land exactly on tile edges and every tile's window is stable as
/// the clock ticks — which is what keeps the per-tile memo in
/// ``TimelineRibbonModel`` valid across re-renders. Only the trailing tile is
/// partial: it ends at now + ~2 h (rounded up to the hour, so its key changes
/// at most hourly). On a DST transition a slot's real duration is 5 or 7 hours
/// while its width stays fixed — a two-day-a-year distortion we accept for
/// stable, labeled wall-clock edges.
///
/// Used at two sizes: the Journal's compact card (~72 pt, `compact: true`) and
/// the full-screen scrubbable variant (``TimelineRibbonScreen``).
struct TimelineRibbonView: View {
    let model: TimelineRibbonModel
    /// Width of one full 6 h tile; partial tiles scale proportionally.
    var tileWidth: CGFloat = 150
    var height: CGFloat = 72
    /// Compact drops label weight and disables the scrub affordance.
    var compact = true
    /// How far back the ribbon reaches. `nil` = back to the earliest dose.
    var historyLimit: TimeInterval?
    /// Enables the touch-and-hold inspection rule (full-screen variant only).
    var scrubEnabled = false

    /// The instant under the user's held finger, or `nil` at rest.
    @State private var scrubDate: Date?

    private static let contentSpace = "timelineRibbonContent"
    private static let projectionSeconds: TimeInterval = 2 * 3600

    /// One tile's window. Identified by its start — stable across re-renders.
    struct TileWindow: Hashable, Identifiable {
        let start: Date
        let end: Date

        var id: Date {
            start
        }
    }

    var body: some View {
        // Re-evaluate each minute so the now marker tracks the clock (and the
        // trailing tile rolls forward on the hour) without a per-frame tick.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ribbon(now: context.date)
        }
        .frame(height: height)
    }

    private func ribbon(now: Date) -> some View {
        let tiles = tileWindows(now: now)
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(tiles) { tile in
                    TimelineRibbonTile(
                        model: model,
                        start: tile.start,
                        end: tile.end,
                        width: width(of: tile),
                        height: height,
                        compact: compact,
                    )
                }
            }
            .coordinateSpace(name: Self.contentSpace)
            .overlay(alignment: .topLeading) {
                nowMarker(now: now, tiles: tiles)
            }
            .overlay(alignment: .topLeading) {
                if let scrubDate {
                    scrubOverlay(at: scrubDate, tiles: tiles)
                }
            }
            .gesture(scrubGesture(tiles: tiles))
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.trailing)
        .defaultScrollAnchor(.trailing, for: .sizeChanges)
    }

    // MARK: - Tile layout

    /// Wall-clock 6 h slot boundaries from the history start through now + ~2 h.
    private func tileWindows(now: Date) -> [TileWindow] {
        let calendar = Calendar.current
        let projectionEnd = projectionEnd(after: now, calendar: calendar)

        // Reach back to the earliest dose, but always show at least a day.
        var historyStart = min(model.earliestDose ?? now, now.addingTimeInterval(-24 * 3600))
        if let historyLimit {
            historyStart = max(historyStart, now.addingTimeInterval(-historyLimit))
        }

        var boundaries: [Date] = []
        var day = calendar.startOfDay(for: historyStart)
        let lastDay = calendar.startOfDay(for: projectionEnd)
        while day <= lastDay {
            for hour in [0, 6, 12, 18] {
                if let boundary = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                   boundary < projectionEnd {
                    boundaries.append(boundary)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        guard !boundaries.isEmpty else {
            return [TileWindow(start: projectionEnd.addingTimeInterval(-6 * 3600), end: projectionEnd)]
        }

        // Trim to the slot containing the history start.
        let firstIndex = boundaries.lastIndex { $0 <= historyStart } ?? 0
        let kept = Array(boundaries[firstIndex...])
        return kept.enumerated().map { index, start in
            TileWindow(start: start, end: index + 1 < kept.count ? kept[index + 1] : projectionEnd)
        }
    }

    /// now + 2 h, rounded up to the next full hour so the trailing tile's
    /// window (and memo key) changes at most once an hour.
    private func projectionEnd(after now: Date, calendar: Calendar) -> Date {
        let target = now.addingTimeInterval(Self.projectionSeconds)
        return calendar.nextDate(
            after: target,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime,
        ) ?? target
    }

    private func width(of tile: TileWindow) -> CGFloat {
        tileWidth * CGFloat(tile.end.timeIntervalSince(tile.start) / (6 * 3600))
    }

    /// X position of an instant in ribbon-content coordinates, or `nil` when
    /// it falls outside the laid-out tiles.
    private func xOffset(of date: Date, tiles: [TileWindow]) -> CGFloat? {
        var x: CGFloat = 0
        for tile in tiles {
            let tileWidth = width(of: tile)
            if date >= tile.start, date <= tile.end {
                let fraction = date.timeIntervalSince(tile.start) / tile.end.timeIntervalSince(tile.start)
                return x + tileWidth * CGFloat(fraction)
            }
            x += tileWidth
        }
        return nil
    }

    private func date(atContentX x: CGFloat, tiles: [TileWindow]) -> Date? {
        var cursor: CGFloat = 0
        for tile in tiles {
            let tileWidth = width(of: tile)
            if x <= cursor + tileWidth {
                let fraction = Double(max(0, x - cursor) / max(tileWidth, 1))
                return tile.start.addingTimeInterval(tile.end.timeIntervalSince(tile.start) * fraction)
            }
            cursor += tileWidth
        }
        return tiles.last?.end
    }

    // MARK: - Now marker

    @ViewBuilder
    private func nowMarker(now: Date, tiles: [TileWindow]) -> some View {
        if let x = xOffset(of: now, tiles: tiles) {
            let lineHeight = height - RibbonMetrics.labelBand(compact: compact) - 2
            VStack(spacing: 0) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 5)
                Rectangle()
                    .fill(Theme.accent.opacity(0.85))
                    .frame(width: 2)
            }
            .frame(width: 5, height: lineHeight)
            .offset(x: x - 2.5, y: 2)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Scrub

    private func scrubGesture(tiles: [TileWindow]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.contentSpace)))
            .onChanged { value in
                guard scrubEnabled, case .second(true, let drag?) = value else { return }
                scrubDate = date(atContentX: drag.location.x, tiles: tiles)
            }
            .onEnded { _ in
                scrubDate = nil
            }
    }

    @ViewBuilder
    private func scrubOverlay(at date: Date, tiles: [TileWindow]) -> some View {
        if let x = xOffset(of: date, tiles: tiles) {
            let readings = scrubReadings(at: date, tiles: tiles)
            let contentWidth = tiles.reduce(CGFloat(0)) { $0 + width(of: $1) }
            let calloutOnLeft = x > contentWidth - 170

            Rectangle()
                .fill(Theme.secondaryLabel.opacity(0.7))
                .frame(width: 1.5, height: height - RibbonMetrics.labelBand(compact: compact) - 2)
                .offset(x: x - 0.75, y: 2)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3) {
                Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption.weight(.semibold))
                ForEach(readings.prefix(3), id: \.name) { reading in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: reading.colorHex))
                            .frame(width: 6, height: 6)
                        Text(verbatim: reading.name)
                            .lineLimit(1)
                        Text(reading.fraction, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .font(.caption2)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: 180, alignment: .leading)
            .fixedSize()
            .offset(x: calloutOnLeft ? max(0, x - 168) : x + 10, y: 6)
            .allowsHitTesting(false)
        }
    }

    /// Per-substance normalized intensity at the scrubbed instant, strongest
    /// first, read from the already-evaluated tile samples.
    private func scrubReadings(at date: Date, tiles: [TileWindow]) -> [(name: String, colorHex: String, fraction: Double)] {
        guard let tile = tiles.first(where: { date >= $0.start && date < $0.end }) ?? tiles.last,
              let plot = model.plot(for: model.key(start: tile.start, end: tile.end))
        else { return [] }
        let span = plot.end.timeIntervalSince(plot.start)
        guard span > 0, plot.sampleCount > 1 else { return [] }
        let fraction = date.timeIntervalSince(plot.start) / span
        let index = max(0, min(plot.sampleCount - 1, Int((fraction * Double(plot.sampleCount - 1)).rounded())))
        let yNorm = model.yNormalization
        return plot.series.compactMap { series in
            let value = series.values[index]
            guard value > 0.02 else { return nil }
            return (series.name, series.colorHex, min(1, value * yNorm))
        }
        .sorted { $0.fraction > $1.fraction }
    }
}

/// Shared layout constants for the ribbon and its tiles.
enum RibbonMetrics {
    static func labelBand(compact: Bool) -> CGFloat {
        compact ? 13 : 18
    }
}
