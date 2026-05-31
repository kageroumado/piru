import Testing
@testable import Piru

@Suite("SubstanceCategory")
struct SubstanceCategoryTests {
    // MARK: - TripSit category mapping

    @Test
    func `Maps stimulant`() {
        #expect(SubstanceCategory.from(tripSitCategory: "stimulant") == .stimulant)
    }

    @Test
    func `Maps psychedelic and hallucinogen`() {
        #expect(SubstanceCategory.from(tripSitCategory: "psychedelic") == .psychedelic)
        #expect(SubstanceCategory.from(tripSitCategory: "hallucinogen") == .psychedelic)
    }

    @Test
    func `Maps dissociative`() {
        #expect(SubstanceCategory.from(tripSitCategory: "dissociative") == .dissociative)
    }

    @Test
    func `Maps opioid and opiate`() {
        #expect(SubstanceCategory.from(tripSitCategory: "opioid") == .opioid)
        #expect(SubstanceCategory.from(tripSitCategory: "opiate") == .opioid)
    }

    @Test
    func `Maps benzodiazepine`() {
        #expect(SubstanceCategory.from(tripSitCategory: "benzodiazepine") == .benzodiazepine)
    }

    @Test
    func `Maps depressant variants`() {
        #expect(SubstanceCategory.from(tripSitCategory: "depressant") == .depressant)
        #expect(SubstanceCategory.from(tripSitCategory: "barbiturate") == .depressant)
        #expect(SubstanceCategory.from(tripSitCategory: "sedative") == .depressant)
    }

    @Test
    func `Maps empathogen and entactogen`() {
        #expect(SubstanceCategory.from(tripSitCategory: "empathogen") == .empathogen)
        #expect(SubstanceCategory.from(tripSitCategory: "entactogen") == .empathogen)
    }

    @Test
    func `Maps cannabinoid`() {
        #expect(SubstanceCategory.from(tripSitCategory: "cannabinoid") == .cannabinoid)
    }

    @Test
    func `Maps nootropic`() {
        #expect(SubstanceCategory.from(tripSitCategory: "nootropic") == .nootropic)
    }

    @Test
    func `Maps antidepressant subtypes`() {
        #expect(SubstanceCategory.from(tripSitCategory: "ssri") == .antidepressant)
        #expect(SubstanceCategory.from(tripSitCategory: "snri") == .antidepressant)
        #expect(SubstanceCategory.from(tripSitCategory: "maoi") == .antidepressant)
        #expect(SubstanceCategory.from(tripSitCategory: "antidepressant") == .antidepressant)
    }

    @Test
    func `Maps antipsychotic`() {
        #expect(SubstanceCategory.from(tripSitCategory: "antipsychotic") == .antipsychotic)
    }

    @Test
    func `Maps antihistamine`() {
        #expect(SubstanceCategory.from(tripSitCategory: "antihistamine") == .antihistamine)
    }

    @Test
    func `Maps deliriant and anticholinergic variants`() {
        #expect(SubstanceCategory.from(tripSitCategory: "deliriant") == .deliriant)
        #expect(SubstanceCategory.from(tripSitCategory: "anticholinergic") == .deliriant)
        #expect(SubstanceCategory.from(tripSitCategory: "muscarinic-antagonist") == .deliriant)
    }

    @Test
    func `Maps supplement variants`() {
        #expect(SubstanceCategory.from(tripSitCategory: "supplement") == .supplement)
        #expect(SubstanceCategory.from(tripSitCategory: "vitamin") == .supplement)
        #expect(SubstanceCategory.from(tripSitCategory: "steroid") == .supplement)
    }

    @Test
    func `Maps gabapentinoid variants`() {
        #expect(SubstanceCategory.from(tripSitCategory: "gabapentinoid") == .gabapentinoid)
        #expect(SubstanceCategory.from(tripSitCategory: "gabaergic") == .gabapentinoid)
    }

    @Test
    func `Maps analgesic`() {
        #expect(SubstanceCategory.from(tripSitCategory: "analgesic") == .analgesic)
    }

    @Test
    func `Unknown category maps to other`() {
        #expect(SubstanceCategory.from(tripSitCategory: "notacategory") == .other)
        #expect(SubstanceCategory.from(tripSitCategory: "") == .other)
    }

    @Test
    func `Mapping is case-insensitive`() {
        #expect(SubstanceCategory.from(tripSitCategory: "STIMULANT") == .stimulant)
        #expect(SubstanceCategory.from(tripSitCategory: "Psychedelic") == .psychedelic)
    }

    // MARK: - Modifier categories

    @Test
    func `Modifier categories contains expected values`() {
        #expect(SubstanceCategory.modifierCategories.contains("common"))
        #expect(SubstanceCategory.modifierCategories.contains("habit-forming"))
        #expect(SubstanceCategory.modifierCategories.contains("research-chemical"))
        #expect(SubstanceCategory.modifierCategories.contains("tentative"))
        #expect(SubstanceCategory.modifierCategories.contains("inactive"))
    }

    @Test
    func `Modifier categories does not contain substantive categories`() {
        #expect(!SubstanceCategory.modifierCategories.contains("stimulant"))
        #expect(!SubstanceCategory.modifierCategories.contains("opioid"))
    }

    // MARK: - Enum properties

    @Test
    func `Has 28 cases`() {
        #expect(SubstanceCategory.allCases.count == 28)
    }

    @Test
    func `ID matches raw value`() {
        for category in SubstanceCategory.allCases {
            #expect(category.id == category.rawValue)
        }
    }

    @Test
    func `All raw values are capitalized display strings`() {
        for category in SubstanceCategory.allCases {
            #expect(!category.rawValue.isEmpty)
            // First character should be uppercase
            #expect(category.rawValue.first?.isUppercase == true)
        }
    }
}
