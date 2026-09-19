import Foundation
import SwiftData

/// One timestamped observation inside a ``Session`` — a session is a timeline of
/// these, each anchored to the moment it was made, optionally structured.
///
/// Free text is the only field that is always meaningful; everything else is
/// captured when the person chose to (a rating, mood, energy, descriptors from the
/// SubFxOnEx vocabulary, a heart-rate snapshot). A note records; it never grades —
/// nothing here is interpreted by the app.
///
/// SwiftData `@Model` shared across the main Piru app, the Home Screen widget and
/// the Lock Screen Live Activity extension, like every other model in `Shared/`.
/// Opened with `cloudKitDatabase: .none`, so the `.unique` `id` is fine.
@Model
final class SessionNote {
    /// What prompted the note. Persisted by raw value.
    nonisolated enum Kind: String, Codable, CaseIterable, Sendable {
        /// Written unprompted.
        case observation
        /// Written from a scheduled check-in notification.
        case checkIn
        /// The session's one summary — mirrors ``Session/note`` (see
        /// ``SessionNoteService``).
        case summary
    }

    #Index<SessionNote>([\.timestamp])

    /// Stable identifier for routing (a sheet editing one note) and export.
    @Attribute(.unique) var id: UUID

    /// When the observation was made — editable, so a note typed later can be
    /// placed at the moment it describes.
    var timestamp: Date

    /// Free text; may be empty when only structure was captured.
    var text: String

    /// Shulgin rating: `0…4` → ±, +, ++, +++, ++++ (PiHKAL, 1991). `nil` = not rated.
    var shulgin: Int?

    /// Mood, `-3…+3`. `nil` = not captured.
    var mood: Int?

    /// Energy, `-3…+3` (sedated … stimulated). `nil` = not captured.
    var energy: Int?

    /// Desire to be around people, `-3…+3` (alone … social). `nil` = not
    /// captured. Separate from ``mood``: wanting company and feeling good are
    /// different axes, and on an empathogen they are the axis people report.
    var social: Int?

    /// Whether the dose did its job, `-1…+1` (less than usual, about right,
    /// more than usual). `nil` = not captured. A separate question from
    /// ``shulgin``: that scale measures how strong an experience is, this one
    /// whether a medication performed the way it usually does.
    var worked: Int?

    /// SubFxOnEx concept ids (`subjective_effect_concepts.id`) — the vocabulary
    /// lives in the bundled DB, so a note stores identity, never the display name.
    var descriptors: [String]

    /// Heart rate (bpm) nearest the note's timestamp, captured when the health
    /// overlay is on. Shown beside the note as a number and nothing more.
    var heartRate: Double?

    var kindRaw: String

    var session: Session?

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .observation }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        text: String = "",
        shulgin: Int? = nil,
        mood: Int? = nil,
        energy: Int? = nil,
        social: Int? = nil,
        worked: Int? = nil,
        descriptors: [String] = [],
        heartRate: Double? = nil,
        kind: Kind = .observation,
        session: Session? = nil,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.shulgin = shulgin
        self.mood = mood
        self.energy = energy
        self.social = social
        self.worked = worked
        self.descriptors = descriptors
        self.heartRate = heartRate
        kindRaw = kind.rawValue
        self.session = session
    }

    /// `true` when the note carries something beyond its timestamp — the
    /// sheet's Save gate and the export's "skip empty" test.
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || shulgin != nil || mood != nil || energy != nil
            || social != nil || worked != nil
            || !descriptors.isEmpty || heartRate != nil
    }
}

/// The three answers to "did it work?" — the scale a medication is read on,
/// where the reference point is this person's own usual result rather than any
/// population figure. Shared by the note sheet, the note rows, the report and
/// the Insights pass that groups days by it.
nonisolated enum WorkedScale {
    static let levels = [-1, 0, 1]

    /// The on-screen word for a level, localized.
    static func label(_ level: Int) -> LocalizedStringResource? {
        switch level {
        case -1: "Less than usual"
        case 0: "About right"
        case 1: "More than usual"
        default: nil
        }
    }

    /// The short form the segmented control shows, localized.
    static func shortLabel(_ level: Int) -> LocalizedStringResource? {
        switch level {
        case -1: "Less"
        case 0: "About right"
        case 1: "More"
        default: nil
        }
    }

    /// The English word the portable exports write, so a report reads the same
    /// whatever locale produced it.
    static func exportWord(_ level: Int) -> String? {
        switch level {
        case -1: "less than usual"
        case 0: "about right"
        case 1: "more than usual"
        default: nil
        }
    }
}

/// The Shulgin scale's glyphs and definitions as PiHKAL (1991) states them.
/// Shared by the note sheet, the note rows, and the trip report.
nonisolated enum ShulginScale {
    static let levels = 0 ... 4

    /// `0…4` → ±, +, ++, +++, ++++. Anything out of range returns nil.
    static func glyph(_ level: Int) -> String? {
        switch level {
        case 0: "±"
        case 1: "+"
        case 2: "++"
        case 3: "+++"
        case 4: "++++"
        default: nil
        }
    }
}
