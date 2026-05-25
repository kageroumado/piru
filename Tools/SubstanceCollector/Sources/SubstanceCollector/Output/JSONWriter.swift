import Foundation

enum JSONWriter {
    static func write(_ substances: [BundledSubstance], to url: URL) throws {
        let encoder = makeEncoder()
        let data = try encoder.encode(substances)
        try writeFile(data, to: url)
    }

    /// Writes the pre-merge sourced dataset. The SQLite builder consumes this
    /// file and attributes every fact-bearing row to `sources.slug =
    /// provenance.rawValue`.
    static func writeSourced(_ records: [SourcedSubstance], to url: URL) throws {
        let encoder = makeEncoder()
        let data = try encoder.encode(records)
        try writeFile(data, to: url)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return encoder
    }

    private static func writeFile(_ data: Data, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
