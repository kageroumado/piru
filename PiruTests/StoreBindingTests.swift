import Foundation
import Testing
@testable import Piru

/// A type that keeps a `ModelContainer?` and is not in
/// `StoreBinding.boundTypes` would keep reading the previous profile's store
/// after a switch. The app's sources are scanned for every such declaration.
@Suite("Profiles — every held store is rebound")
@MainActor
struct StoreBindingTests {
    private static func appSources(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Piru")
    }

    /// Every type in the app that declares a stored `ModelContainer?`.
    static func typesHoldingContainers() throws -> [String: String] {
        // `var name: ModelContainer?` (or `!`) at any access level, static or not.
        let heldContainer = try Regex(
            #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:private|fileprivate|internal|public|nonisolated)(?:\(set\))?\s+)*(?:static\s+)?var\s+\w+\s*:\s*ModelContainer[?!]"#,
        )
        let typeDeclaration = try Regex(
            #"^(\s*)(?:@\w+\s+)*(?:(?:private|fileprivate|internal|public|final|nonisolated)\s+)*(?:class|struct|enum|actor|extension)\s+(\w+)"#,
        )
        var found: [String: String] = [:]
        let root = appSources()
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.firstMatch(of: heldContainer) != nil {
                let indent = line.prefix { $0 == " " }.count
                let owner = lines[..<index].reversed().lazy.compactMap { candidate -> String? in
                    guard let match = candidate.firstMatch(of: typeDeclaration),
                          let leading = match.output[1].substring,
                          let name = match.output[2].substring,
                          leading.count < indent else { return nil }
                    return String(name)
                }.first
                found[owner ?? "?"] = "\(file.lastPathComponent):\(index + 1)"
            }
        }
        return found
    }

    @Test
    func `Every type holding a ModelContainer is rebound on a profile switch`() throws {
        let holders = try Self.typesHoldingContainers()
        #expect(holders.count >= 10, "the scan found too little: \(holders)")
        let bound = Set(StoreBinding.boundTypes.map { String(describing: $0) })
        // The directory opens the stores and hands them out; it is what rebinds.
        let exempt: Set = ["ProfileDirectory"]
        for (type, location) in holders.sorted(by: { $0.key < $1.key }) where !exempt.contains(type) {
            #expect(bound.contains(type), "\(type) holds a ModelContainer (\(location)) but is not in StoreBinding.boundTypes")
        }
    }
}
