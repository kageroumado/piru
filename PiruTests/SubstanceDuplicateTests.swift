import Foundation
import GRDB
import Testing
@testable import Piru

@Suite("Substance Duplicates")
struct SubstanceDuplicateTests {
    /// Genuinely distinct substances that share an alias — a brand/generic pair,
    /// a combo product, or an ester/base relationship. NOT duplicates.
    static let knownDistinct: Set<String> = [
        "Dextroamphetamine-Amphetamine",
        "Epidiolex",
        "Fluocinolone",
    ]

    @Test
    @MainActor
    func `No substance name duplicates an alias of a different substance`() async throws {
        await SubstanceStore.shared.ensureAllLoaded()
        let collisions = try await SubstanceStore.shared.substancesDB.read { db -> [(String, String)] in
            try Row.fetchAll(db, sql: """
            SELECT s.canonical_name AS substance, s2.canonical_name AS alias_of
            FROM substances s
            JOIN aliases a ON lower(a.alias) = lower(s.canonical_name)
            JOIN substances s2 ON s2.id = a.substance_id
            WHERE s.id != s2.id
            ORDER BY s.canonical_name
            """)
            .map { ($0["substance"] as String, $0["alias_of"] as String) }
        }
        let unwaived = collisions.filter { !Self.knownDistinct.contains($0.0) }
        #expect(
            unwaived.isEmpty,
            "Substances that are aliases of another: \(unwaived.map { "\($0.0) → \($0.1)" }.joined(separator: ", "))",
        )
    }

    @Test
    @MainActor
    func `No two substances normalize to the same name`() async {
        await SubstanceStore.shared.ensureAllLoaded()
        let all = SubstanceLibrary.all
        var seen: [String: String] = [:]
        var collisions: [(String, String)] = []
        for substance in all {
            let key = Self.normalize(substance.name)
            if let existing = seen[key], existing != substance.name {
                collisions.append((existing, substance.name))
            } else {
                seen[key] = substance.name
            }
        }
        #expect(
            collisions.isEmpty,
            "Substances with colliding normalized names: \(collisions.map { "\($0.0) ↔ \($0.1)" }.joined(separator: ", "))",
        )
    }

    private static func normalize(_ name: String) -> String {
        var s = name.lowercased()
        for prefix in ["(+)-", "(-)-", "(±)-", "l-", "d-", "dl-"] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        }
        return s.filter { $0.isLetter || $0.isNumber }
    }
}
