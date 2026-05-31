import Testing
@testable import Piru

@Suite("RouteOfAdministration Parsing")
struct RouteParsingTests {
    // MARK: - Oral variants

    @Test(arguments: [
        "oral", "oral_ir", "oral_er", "oral(benzedrex)", "oral(pure)",
    ])
    func `Parses oral variants`(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .oral)
    }

    // MARK: - Insufflation variants

    @Test(arguments: [
        "insufflated", "insufflation", "insufflated(pure)", "intranasal", "nasal"
    ])
    func `Parses insufflation variants`(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .insufflation)
    }

    // MARK: - Inhalation variants

    @Test(arguments: [
        "inhaled", "inhalation", "smoked", "vapourized", "vaporized"
    ])
    func `Parses inhalation variants`(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .inhalation)
    }

    // MARK: - IV variants

    @Test(arguments: ["intravenous", "iv"])
    func `Parses IV variants`(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .intravenous)
    }

    // MARK: - IM variants

    @Test(arguments: ["intramuscular", "im"])
    func `Parses IM variants`(input: String) {
        #expect(RouteOfAdministration.from(string: input) == .intramuscular)
    }

    // MARK: - Other routes

    @Test
    func `Parses sublingual`() {
        #expect(RouteOfAdministration.from(string: "sublingual") == .sublingual)
    }

    @Test
    func `Parses subcutaneous`() {
        #expect(RouteOfAdministration.from(string: "subcutaneous") == .subcutaneous)
    }

    @Test
    func `Parses transdermal and topical`() {
        #expect(RouteOfAdministration.from(string: "transdermal") == .transdermal)
        #expect(RouteOfAdministration.from(string: "topical") == .transdermal)
    }

    @Test
    func `Parses rectal and plugged`() {
        #expect(RouteOfAdministration.from(string: "rectal") == .rectal)
        #expect(RouteOfAdministration.from(string: "plugged") == .rectal)
    }

    // MARK: - Edge cases

    @Test
    func `Unknown string maps to other`() {
        #expect(RouteOfAdministration.from(string: "unknown") == .other)
        #expect(RouteOfAdministration.from(string: "") == .other)
    }

    @Test
    func `Case insensitive parsing`() {
        #expect(RouteOfAdministration.from(string: "ORAL") == .oral)
        #expect(RouteOfAdministration.from(string: "Smoked") == .inhalation)
        #expect(RouteOfAdministration.from(string: "IV") == .intravenous)
    }

    @Test
    func `Trims whitespace`() {
        #expect(RouteOfAdministration.from(string: "  oral  ") == .oral)
        #expect(RouteOfAdministration.from(string: " iv ") == .intravenous)
    }
}
