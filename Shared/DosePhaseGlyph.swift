import Foundation

/// The glyph for each moment of a dose's arc, and the plain word for the phase
/// a dose is in right now.
///
/// One table, read by the Live Activity's next-phase countdown, the journal
/// timeline's milestone marks and word-state glance, and the substance card's
/// phase rows — so a come-up cannot wear one symbol on the Lock Screen and
/// another in the app.
nonisolated enum DosePhaseGlyph {
    static let comeup = "arrow.up.right"
    static let peak = "sparkles"
    static let offset = "arrow.down.right"
    static let afterglow = "moon.stars"
    static let ended = "checkmark.circle"

    /// Effects ending for a substance whose whole point is wakefulness
    /// (``SubstanceCategory/wakePromoting``). The moon says what the checkmark
    /// cannot: this is the hour the dose is out of the way of sleep.
    static let sleep = "moon.zzz"

    /// The mark for a dose's effects ending — the moon only where the app is
    /// already allowed to talk about bedtime.
    static func end(affectsSleep: Bool) -> String {
        affectsSleep ? sleep : ended
    }
}

/// The phase a dose is in, said in the words someone asks the question in:
/// "is it working yet", not "which limb of the curve is this".
///
/// The nouns (Onset, Come-up, Offset) live on ``DosePhaseProgressBar/Phase``
/// and name the *phase*; these name the *state the person is in*, which is what
/// a glance at the timeline gutter is for.
nonisolated enum DosePhaseWord {
    static let onset: LocalizedStringResource = "Onset"
    static let comingUp: LocalizedStringResource = "Coming up"
    static let peak: LocalizedStringResource = "Peak"
    static let wearingOff: LocalizedStringResource = "Wearing off"
    static let afterglow: LocalizedStringResource = "Afterglow"
}
