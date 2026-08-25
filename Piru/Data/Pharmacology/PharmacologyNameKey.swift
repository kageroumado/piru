import Foundation

/// The one substance-name folding + lookup mechanism for the hardcoded
/// pharmacology tables (`HalfLifeDatabase`, `SubstanceModelDatabase`,
/// `MechanismOfActionDatabase`, `MetabolicModulation`).
///
/// Each table keeps its **own** alias map — only the mechanism is shared.
/// Never merge the alias tables: they encode different relations. To
/// `HalfLifeDatabase`, `lisdexamfetamine` is its own compound (its own
/// half-life); to `SubstanceModelDatabase`, it aliases to `amphetamine`
/// (it must inherit amphetamine's PD scalars). One shared table would force
/// one table's relation onto the other.
nonisolated enum PharmacologyNameKey {
    /// The one fold: lowercased, whitespace/newline-trimmed.
    static func fold(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Direct hit first, then one alias hop. Direct-first means adding an
    /// alias row can only turn a miss into a hit: a spelling that is itself a
    /// data key always resolves to its own value, even when an alias row also
    /// claims it.
    static func resolve<Value>(
        _ name: String,
        in data: [String: Value],
        aliases: [String: String],
    ) -> Value? {
        let key = fold(name)
        if let direct = data[key] { return direct }
        if let canonical = aliases[key] { return data[canonical] }
        return nil
    }

    /// The canonical key alone (alias target when one exists, else the fold),
    /// for callers that match against a set or group rather than look up a
    /// value.
    static func canonical(_ name: String, aliases: [String: String]) -> String {
        let key = fold(name)
        return aliases[key] ?? key
    }
}
