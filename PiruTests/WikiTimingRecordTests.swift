import Foundation
import Testing
@testable import Piru

@Suite("Published wiki timing semantics")
@MainActor
struct WikiTimingRecordTests {
    private func record(_ json: String, kind: String = "duration_curve", id: String = "fixture") throws -> WikiTimingRecord {
        try WikiTimingRecord(
            id: id, sourceName: "Fictional compound", route: "ophthalmic",
            kind: kind, entryIndex: 0,
            entryJSON: json, timingTextJSON: "{}",
        )
    }

    @Test
    func `unknown onset and neutral tail survive`() throws {
        let result = try record(#"""
        {"partial_duration_curve":{"units":"days","onset":{"start":null,"end":null},
         "peak":{"start":1,"end":2},"after_effects":{"start":6,"end":9},
         "total_duration":{"min":2,"max":4,"note":"Fictional fixture"}}}
        """#, kind: "partial_duration_curve")
        let curve = try #require(result.curve)
        #expect(curve.onset?.start == nil)
        #expect(curve.onset?.end == nil)
        #expect(curve.peak?.start == 1)
        #expect(curve.afterEffects?.start == 6)
        #expect(curve.afterEffects?.end == 9)
        #expect(curve.total?.min == 2)
        #expect(curve.units == "days")
        #expect(result.study == nil)
    }

    @Test
    func `one unknown boundary does not erase the other`() throws {
        let result = try record(#"""
        {"partial_duration_curve":{"units":"minutes","onset":{"start":null,"end":5}}}
        """#, kind: "partial_duration_curve")
        #expect(result.curve?.onset?.start == nil)
        #expect(result.curve?.onset?.end == 5)
    }

    @Test
    func `offset overlap is retained without repair`() throws {
        let result = try record(#"""
        {"duration_curve":{"units":"hours","peak":{"start":1,"end":3},
         "offset":{"start":2,"end":3},"after_effects":{"start":8,"end":9}}}
        """#)
        #expect(result.curve?.offset?.start == 2)
        #expect(result.curve?.offset?.end == 3)
        #expect(result.curve?.afterEffects?.start == 8)
    }

    @Test
    func `duplicate routes keep identity and formulation`() throws {
        let json = #"{"formulation":"Fictional ointment","partial_duration_curve":{"units":"days","onset":{"start":0,"end":null}}}"#
        let first = try record(json, kind: "partial_duration_curve", id: "first")
        let second = try record(json, kind: "partial_duration_curve", id: "second")
        #expect(first.id != second.id)
        #expect(first.route == second.route)
        #expect(first.formulation == "Fictional ointment")
        #expect(first.curve?.onset?.start == 0)
        #expect(first.curve?.onset?.end == nil)
    }

    @Test(arguments: [
        ("3-Methyl-4-fluoro-α-pyrrolidinovalerophenone", "3-methyl-4-fluoro-alpha-pyrrolidinovalerophenone"),
        ("Butylone (βk-MBDB)", "butylone-betak-mbdb"),
        ("Δ Fictional é ①", "delta-fictional-e-1"),
    ])
    func `source links retain Greek letters and normalized characters`(name: String, slug: String) throws {
        let result = try WikiTimingRecord(
            id: "fictional", sourceName: name, route: nil, kind: "duration_curve",
            entryIndex: 0, entryJSON: "{}", timingTextJSON: "{}",
        )
        #expect(result.sourceURL?.absoluteString == "https://substance.wiki/drug/\(slug)")
    }

    @Test
    func `study statistics remain statistics`() throws {
        let result = try record(#"""
        {"schemaVersion":"drug-community-study-timeline/1","id":"fictional-study",
         "units":"hours","nominalStudyDoseMicrogramsBase":100,
         "context":{"route":"oral","formulation":"Fictional solution","population":"Fictional participants",
           "participantCount":16,"endpoint":"Fictional response","clockOrigin":"administration",
           "condition":"Fictional condition","studyDesign":"Fictional design",
           "onsetOffsetThresholdFraction":0.1,"thresholdBasis":"individual_maximum_modeled_response"},
         "points":[{"key":"maximum","label":"Fictional maximum","mean":2.6,"standardDeviation":1.1,
           "participantRange":{"min":1.3,"max":6.5},"quantity":"time_since_administration","sourceCell":"D5"}],
         "activeDuration":{"mean":8.3,"standardDeviation":2.9,"participantRange":{"min":5,"max":18},
           "quantity":"interval_between_modeled_onset_and_offset","sourceCell":"D6"},
         "rangeMeaning":"reported_minimum_and_maximum_of_participant_modeled_estimates",
         "source":{"articleUrl":"https://example.org/study","tableUrl":"https://example.org/table",
           "doi":"fictional","locator":"Fictional table"}}
        """#, kind: "duration_study")
        let study = try #require(result.study)
        #expect(result.curve == nil)
        #expect(study.points[0].mean == 2.6)
        #expect(study.points[0].standardDeviation == 1.1)
        #expect(study.points[0].participantRange.max == 6.5)
        #expect(study.activeDuration.quantity == "interval_between_modeled_onset_and_offset")
        #expect(study.context.participantCount == 16)
    }

    @Test
    func `duration charts keep their evidence class and hypothesis`() throws {
        let result = try record(#"""
        {"schemaVersion":"drug-community-duration-chart/1","id":"fictional-oral-hypothesis-v1",
         "label":"Fictional schematic","route":"oral","formulation":null,
         "time_origin":"single_administration","kind":"subjective_effect","evidence":"extrapolated_timing",
         "sources":[{"title":"Fictional source","url":"https://example.org/a"}],
         "limitations":["Fictional limitation"],
         "curve":{"reference":"Fictional","units":"hours","total_duration":{"min":12,"max":30},
           "onset":{"start":0.5,"end":2},"peak":{"start":2,"end":6},"offset":{"start":8,"end":30}},
         "hypothesis":{"model_status":"extrapolated_not_validated","context":"recreational",
           "confidence":"low","attribution":"Fictional proposal","residual_may_exceed_end":true}}
        """#, kind: "duration_chart")
        let chart = try #require(result.chart)
        #expect(result.study == nil)
        #expect(chart.evidence == "extrapolated_timing")
        #expect(chart.hypothesis?.modelStatus == "extrapolated_not_validated")
        #expect(chart.hypothesis?.confidence == "low")
        #expect(chart.limitations == ["Fictional limitation"])
        #expect(chart.sources?.first?.url == "https://example.org/a")
        #expect(result.curve?.offset?.end == 30)
        #expect(result.formulation == nil)
    }

    @Test
    func `a plasma model stays a plasma model`() throws {
        let result = try record(#"""
        {"schemaVersion":"drug-community-duration-chart/1","id":"fictional-oral-parent-plasma-v1",
         "label":"Fictional plasma model","route":"oral","formulation":"Fictional tablet",
         "time_origin":"single_administration","kind":"plasma_concentration","evidence":"parameterized_model",
         "sources":[{"title":"Fictional label","url":"https://example.org/b"}],
         "limitations":["Plasma concentration is not felt effect"],
         "compartment":"plasma","normalization":"peak_percent",
         "analyte":{"name":"fictional","kind":"parent_drug"},
         "representation":"one_compartment_first_order_absorption","phase_definition":"rise_peak_decline",
         "absorption_lag_hours":0,
         "parameters":{"half_life_hours":75,"tmax_hours":3,"reported_tmax_hours":[3,5]},
         "time_horizon_hours":300,"scenarios":[],"assumptions":["Fictional assumption"]}
        """#, kind: "duration_chart")
        let chart = try #require(result.chart)
        #expect(chart.kind == "plasma_concentration")
        #expect(chart.analyte?.name == "fictional")
        #expect(chart.parameters?.halfLifeHours == 75)
        #expect(chart.parameters?.tmaxHours == 3)
        #expect(result.curve == nil)
        #expect(result.formulation == "Fictional tablet")
    }

    @Test
    func `Only a web address from the source data becomes a link`() {
        #expect(WikiSourceLink.url("https://doi.org/10.1038/s41386-020-00883-6") != nil)
        #expect(WikiSourceLink.url("http://example.org/a") != nil)
        #expect(WikiSourceLink.url("piru://quicklog?substance=x") == nil)
        #expect(WikiSourceLink.url("tel:123") == nil)
        #expect(WikiSourceLink.url("javascript:alert(1)") == nil)
        #expect(WikiSourceLink.url("https:///nohost") == nil)
    }
}
