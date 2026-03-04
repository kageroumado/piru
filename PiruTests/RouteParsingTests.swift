import Testing
@testable import Piru

@Suite("RouteOfAdministration Parsing")
struct RouteParsingTests {

    // MARK: - Oral variants

    @Test("Parses oral variants", arguments: [
        "oral", "oral_ir", "oral_er", "oral(benzedrex)", "oral(pure)"
    ])
    func oralVariants(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .oral)
    }

    // MARK: - Insufflation variants

    @Test("Parses insufflation variants", arguments: [
        "insufflated", "insufflation", "insufflated(pure)", "intranasal", "nasal"
    ])
    func insufflationVariants(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .insufflation)
    }

    // MARK: - Inhalation variants

    @Test("Parses inhalation variants", arguments: [
        "inhaled", "inhalation", "smoked", "vapourized", "vaporized"
    ])
    func inhalationVariants(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .inhalation)
    }

    // MARK: - IV variants

    @Test("Parses IV variants", arguments: ["intravenous", "iv"])
    func ivVariants(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .intravenous)
    }

    // MARK: - IM variants

    @Test("Parses IM variants", arguments: ["intramuscular", "im"])
    func imVariants(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .intramuscular)
    }

    // MARK: - Other routes

    @Test("Parses sublingual")
    func sublingual() {
        #expect(RouteOfAdministration.from(string: "sublingual") == .sublingual)
    }

    @Test("Parses subcutaneous")
    func subcutaneous() {
        #expect(RouteOfAdministration.from(string: "subcutaneous") == .subcutaneous)
    }

    @Test("Parses transdermal and topical")
    func transdermal() {
        #expect(RouteOfAdministration.from(string: "transdermal") == .transdermal)
        #expect(RouteOfAdministration.from(string: "topical") == .transdermal)
    }

    @Test("Parses rectal and plugged")
    func rectal() {
        #expect(RouteOfAdministration.from(string: "rectal") == .rectal)
        #expect(RouteOfAdministration.from(string: "plugged") == .rectal)
    }

    // MARK: - Edge cases

    @Test("Unknown string maps to other")
    func unknownMapsToOther() {
        #expect(RouteOfAdministration.from(string: "unknown") == .other)
        #expect(RouteOfAdministration.from(string: "") == .other)
    }

    @Test("Case insensitive parsing")
    func caseInsensitive() {
        #expect(RouteOfAdministration.from(string: "ORAL") == .oral)
        #expect(RouteOfAdministration.from(string: "Smoked") == .inhalation)
        #expect(RouteOfAdministration.from(string: "IV") == .intravenous)
    }

    @Test("Trims whitespace")
    func trimsWhitespace() {
        #expect(RouteOfAdministration.from(string: "  oral  ") == .oral)
        #expect(RouteOfAdministration.from(string: " iv ") == .intravenous)
    }
}
