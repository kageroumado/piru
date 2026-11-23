import Foundation

/// Molecular formulas as they are typeset: atom counts in subscript digits
/// ("C₁₁H₁₅NO₂"). A digit that leads the formula or a dot-separated part is a
/// multiplier ("·2H₂O") and stays full size.
nonisolated enum ChemicalFormula {
    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    ]

    static func typeset(_ formula: String) -> String {
        var out = ""
        var countFollows = false
        for character in formula {
            if countFollows, let sub = subscripts[character] {
                out.append(sub)
                continue
            }
            out.append(character)
            countFollows = character.isLetter || character == ")" || character == "]"
        }
        return out
    }
}
