import SwiftUI

/// One day slice of the continuous strip, all in points. Within the slice —
/// as across the whole strip — larger y = earlier. `mapHeight` is the slice's
/// share of the global time map; `totalHeight` can exceed it when displaced
/// cards spill past the mapped span.
nonisolated struct TimelineDayLayout: Identifiable, Equatable, Codable {
    let date: Date
    let isToday: Bool
    let style: Style
    /// The strip's newest slice: carries the axis arrowhead, the top fade,
    /// and (usually) the "Now" line.
    let showsLiveEdge: Bool
    /// Height of the empty run at the slice's top standing in for skipped
    /// whole days (``TimelineTimeMap/breakHeight``), or 0 when the strip
    /// continues straight from the newer slice.
    let breakAbove: CGFloat
    /// The next older slice starts after a break: the axis fades out toward
    /// this slice's bottom edge.
    let fadesAxisBelow: Bool
    let cardGroups: [CardGroup]
    let envelopes: [SessionEnvelope]
    let series: [CurveSeries]
    let doseDots: [DoseDot]
    let connectors: [Connector]
    let noteMarks: [NoteMark]
    /// Phase boundaries of the one dose that has the slice to itself, in the
    /// lane beside its curve. Empty whenever more than one dose is running:
    /// two curves make a lone glyph ambiguous about which drug it belongs to.
    let milestones: [Milestone]
    /// The plain word for what the one running dose is doing at `now`, for
    /// the gutter under the "Now" tag. `nil` on every slice but the live edge,
    /// and whenever the milestones are empty for the same reason.
    let wordState: WordState?
    /// Heart rate across the slice as (y, 0…1) points, y ascending. Empty
    /// unless the health overlay is on and the slice holds enough samples to
    /// read as a line.
    let heartRate: [CurvePoint]
    let hourTicks: [HourTick]
    let nowY: CGFloat?
    let mapHeight: CGFloat
    let totalHeight: CGFloat

    var id: Date {
        date
    }

    /// The display options the slice was laid out for.
    struct Style: Equatable, Codable {
        /// Off: no strip, ruler or curves — the bubbles stack as a list.
        let showsAxis: Bool
        let bubbleStyle: TimelineBubbleStyle
        /// Body-load mode: half-life PK decay instead of effect curves, and
        /// elimination percentages on the bubbles.
        let pkMode: Bool
    }

    static let cardSpacing: CGFloat = 4
    static let groupGap: CGFloat = 14
    static let envelopePad: CGFloat = 6
    static let envelopeFooterHeight: CGFloat = 22
    /// Base vertical resolution at zoom 1 — uniform across the whole strip.
    static let basePointsPerMinute: CGFloat = 1.4

    struct CardGroup: Identifiable, Equatable, Codable {
        /// ``DoseEntry/id`` of the group's first dose. Never a `PersistentIdentifier`:
        /// one decoded from the launch cache and a live one for the same row
        /// compare equal but hash differently, and SwiftUI's `ForEach` trapped on
        /// exactly that the first time a cached strip was rebuilt after a log.
        let id: UUID
        /// Newest first — matching the axis direction.
        let items: [CardItem]
        let representativeTime: Date
        /// Where ``representativeTime`` falls on the axis — the time capsule
        /// sits here, beside the dose dot, however far the card stack below is
        /// pushed down by the groups above it.
        var timeY: CGFloat = 0
        let sessionID: UUID?
        /// Each bubble's height, per the bubble style.
        let cardHeight: CGFloat
        /// Resolved top of the card stack (after collision push-down).
        var topY: CGFloat = 0
        var inSession = false
        /// Trailing (oldest) items the strip does not draw: their session
        /// envelope ran past the slice's mapped span, and they stand behind
        /// its "+n more" footer instead. Always 0 outside an envelope.
        var hiddenItemCount = 0
        /// `false` when the group's time capsule would overprint the "Now"
        /// tag in the gutter — Now wins (``TimelineGutterLabels``).
        var showsTimeLabel = true

        var height: CGFloat {
            CGFloat(items.count) * cardHeight
                + CGFloat(items.count - 1) * TimelineDayLayout.cardSpacing
        }

        /// The items the strip draws as bubbles.
        var visibleItems: ArraySlice<CardItem> {
            items.dropLast(hiddenItemCount)
        }

        /// The session this group's bubbles open, when the bubble is the
        /// only door to it: a session with a single dose in this slice draws
        /// no envelope, and the session's notes, check-ins and splitting
        /// would otherwise be unreachable from the strip. Inside an
        /// envelope the bubble opens its dose and the envelope the session.
        var sessionOpenedByBubble: UUID? {
            inSession ? nil : sessionID
        }

        var bottomY: CGFloat {
            topY + height
        }
    }

    /// One dose as the strip draws it — plain values, no `@Model` reference,
    /// so a whole layout can be encoded to the launch cache and decoded off
    /// the main actor.
    struct CardItem: Identifiable, Equatable, Codable {
        /// ``DoseEntry/id`` — the row identity and what a tap pushes. Never
        /// a `PersistentIdentifier` (see ``CardGroup/id``).
        let id: UUID
        let timestamp: Date
        let amount: Double
        let unit: String
        /// Whether the dose has no amount — the bubble prints `?` for it.
        let isUnknownDose: Bool
        let route: RouteOfAdministration
        /// The dose's title, resolved once here (a derive layer) through the shared
        /// ``DoseTitle/resolve(for:)`` — so the bubble shows the brand ("Medikinet")
        /// the entry was logged under, matching the session/journal rows, not the
        /// bare canonical substance.
        let displayName: String
        /// The logged substance name — what Substance Info opens.
        let substance: String
        let color: Color
        let remainingFraction: Double?
        /// The dose's acute-effect state while its effects are still running
        /// at build time — the bubble's phase progress reads from it. `nil`
        /// for ended doses and doses without duration data.
        let state: ActiveSubstanceState?

        init(entry: DoseEntry, displayName: String, color: Color, remainingFraction: Double?, state: ActiveSubstanceState?) {
            id = entry.id
            timestamp = entry.timestamp
            amount = entry.amount
            unit = entry.unit
            isUnknownDose = entry.isUnknownDose
            route = entry.route
            self.displayName = displayName
            substance = entry.substance
            self.color = color
            self.remainingFraction = remainingFraction
            self.state = state
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case timestamp
            case amount
            case unit
            case isUnknownDose
            case route
            case displayName
            case substance
            case color
            case remainingFraction
            case state
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            timestamp = try c.decode(Date.self, forKey: .timestamp)
            amount = try c.decode(Double.self, forKey: .amount)
            unit = try c.decode(String.self, forKey: .unit)
            isUnknownDose = try c.decodeIfPresent(Bool.self, forKey: .isUnknownDose) ?? false
            route = try c.decode(RouteOfAdministration.self, forKey: .route)
            displayName = try c.decode(String.self, forKey: .displayName)
            substance = try c.decode(String.self, forKey: .substance)
            color = try c.decode(P3Color.self, forKey: .color).color
            remainingFraction = try c.decodeIfPresent(Double.self, forKey: .remainingFraction)
            state = try c.decodeIfPresent(ActiveSubstanceState.self, forKey: .state)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(timestamp, forKey: .timestamp)
            try c.encode(amount, forKey: .amount)
            try c.encode(unit, forKey: .unit)
            try c.encode(isUnknownDose, forKey: .isUnknownDose)
            try c.encode(route, forKey: .route)
            try c.encode(displayName, forKey: .displayName)
            try c.encode(substance, forKey: .substance)
            try c.encode(color.cacheTint(), forKey: .color)
            try c.encodeIfPresent(remainingFraction, forKey: .remainingFraction)
            try c.encodeIfPresent(state, forKey: .state)
        }
    }

    struct SessionEnvelope: Identifiable, Equatable, Codable {
        let id: UUID
        let yStart: CGFloat
        let yEnd: CGFloat
        /// Doses of the run drawn as a "+n more" footer instead of bubbles,
        /// because the bubbles would have run past the slice.
        let hiddenDoseCount: Int
    }

    /// One substance's effect curve as (y, 0…1) points, y ascending (newest
    /// first): the doses' strength on their substance's ladder in effect mode,
    /// the substance's all-time peak concentration in body-load mode. Each point carries the phase of the newest dose
    /// covering it, which the stroke draws as a color shift along the line;
    /// body-load curves model no phases and carry `nil`.
    struct CurveSeries: Equatable, Codable {
        let color: Color
        let points: [CurvePoint]
        /// The substance has no dose ladder, so the curve sits at a fixed
        /// neutral height rather than a read strength, and strokes dotted.
        let isUnscaled: Bool
        /// The substance's display name, written at the curve's peak under
        /// Differentiate Without Color so the curve is named by more than its hue.
        let label: String

        init(color: Color, points: [CurvePoint], isUnscaled: Bool = false, label: String = "") {
            self.color = color
            self.points = points
            self.isUnscaled = isUnscaled
            self.label = label
        }

        private enum CodingKeys: String, CodingKey { case color, points, isUnscaled, label }

        /// Points travel as one flat number array — `y` to a tenth of a point,
        /// `v` to four places, the phase as its case index (−1 for none) — a
        /// fifth of the keyed form's bytes: the curves are most of the strip's
        /// launch cache, and the layout does not resolve finer than that.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            color = try c.decode(P3Color.self, forKey: .color).color
            let flat = try c.decode([Double].self, forKey: .points)
            var decoded: [CurvePoint] = []
            decoded.reserveCapacity(flat.count / 3)
            var i = 0
            while i + 2 < flat.count {
                let phaseIndex = Int(flat[i + 2])
                let phase = TimelineCurvePhase.allCases.indices.contains(phaseIndex) ? TimelineCurvePhase.allCases[phaseIndex] : nil
                decoded.append(CurvePoint(y: flat[i], v: flat[i + 1], phase: phase))
                i += 3
            }
            points = decoded
            isUnscaled = try c.decodeIfPresent(Bool.self, forKey: .isUnscaled) ?? false
            label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(color.cacheTint(), forKey: .color)
            var flat: [Double] = []
            flat.reserveCapacity(points.count * 3)
            for point in points {
                flat.append((Double(point.y) * 10).rounded() / 10)
                flat.append((point.v * 10_000).rounded() / 10_000)
                flat.append(Double(point.phase.flatMap { TimelineCurvePhase.allCases.firstIndex(of: $0) } ?? -1))
            }
            try c.encode(flat, forKey: .points)
            if isUnscaled { try c.encode(true, forKey: .isUnscaled) }
            if !label.isEmpty { try c.encode(label, forKey: .label) }
        }
    }

    struct CurvePoint: Equatable, Codable {
        let y: CGFloat
        let v: Double
        var phase: TimelineCurvePhase?
    }

    struct DoseDot: Identifiable, Equatable, Codable {
        /// ``DoseEntry/id`` of the dose the dot marks.
        let id: UUID
        let y: CGFloat
        let color: Color

        init(id: UUID, y: CGFloat, color: Color) {
            self.id = id
            self.y = y
            self.color = color
        }

        private enum CodingKeys: String, CodingKey { case id, y, color }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            y = try c.decode(CGFloat.self, forKey: .y)
            color = try c.decode(P3Color.self, forKey: .color).color
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(y, forKey: .y)
            try c.encode(color.cacheTint(), forKey: .color)
        }
    }

    /// A thin line from a dose's true position on the time axis to the
    /// vertical center of its card — the card can sit away from its moment
    /// when several land in one stretch, and with many entries in one hour
    /// the connectors are what say which dot belongs to which card.
    struct Connector: Equatable, Codable {
        let fromY: CGFloat
        let toY: CGFloat
        let color: Color

        init(fromY: CGFloat, toY: CGFloat, color: Color) {
            self.fromY = fromY
            self.toY = toY
            self.color = color
        }

        private enum CodingKeys: String, CodingKey { case fromY, toY, color }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fromY = try c.decode(CGFloat.self, forKey: .fromY)
            toY = try c.decode(CGFloat.self, forKey: .toY)
            color = try c.decode(P3Color.self, forKey: .color).color
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(fromY, forKey: .fromY)
            try c.encode(toY, forKey: .toY)
            try c.encode(color.cacheTint(), forKey: .color)
        }
    }

    /// One session note at its own moment on the axis. It lives in the lane
    /// between the curves and the bubble column, never in the gutter, so it
    /// can't collide with a dose capsule.
    struct NoteMark: Identifiable, Equatable, Codable {
        let id: UUID
        let sessionID: UUID
        let kind: SessionNote.Kind
        let timestamp: Date
        /// First line of the note's text, empty when the note carries only
        /// structure (a rating, a mood).
        let text: String
        let y: CGFloat
        /// How much of the curve lane is taken by the widest curve at this y,
        /// `0…1`. The view turns it into the room left for the note's text.
        let curveFraction: Double
        /// A dose time capsule or the "Now" tag shares this note's height, so
        /// it starts further into the lane than an hour pill would need.
        let besideCapsule: Bool
    }

    struct HourTick: Identifiable, Equatable, Codable {
        /// The hour the tick marks; one tick per hour, so it is the identity.
        let id: Date
        let y: CGFloat
        /// The hour as the locale writes it on its own (``TimelineHourMark``),
        /// or `nil` when the gridline stands alone — its label would collide
        /// with the day tag, a dose capsule, the "Now" tag, or a neighboring
        /// hour label.
        let label: String?
    }
}
