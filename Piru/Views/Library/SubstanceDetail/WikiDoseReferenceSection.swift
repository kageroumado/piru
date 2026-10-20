import SwiftUI

/// Published dose references never enter the app's dose ladder or logging flow.
struct WikiDoseReferenceSection: View {
    let records: [WikiDoseReferenceRecord]
    @State private var isExpanded = false

    var body: some View {
        if !records.isEmpty {
            CollapsibleSection("substance.wiki dose references", isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("These references do not set dose prefills, dose classifications or calculations. They are not dosing recommendations.")
                        .captionSecondary()
                    ForEach(records) { record in
                        if records.count > 1 {
                            Text(verbatim: record.sourceName).font(.subheadline.bold())
                        }
                        WikiDoseReferenceContent(record: record)
                        if record.id != records.last?.id { Divider() }
                    }
                }
                .padding(.vertical, Spacing.xs)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The expanded reference body is shared with native rendering checks.
struct WikiDoseReferenceContent: View {
    let record: WikiDoseReferenceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if record.model.status == "withdrawn" {
                Text("These dose references have been withdrawn. No bands are shown.")
                    .font(.subheadline.bold())
            } else if record.model.status == "unavailable" {
                Text("No dose references are available in this release.")
                    .font(.subheadline.bold())
            }
            WikiDoseReferenceNotes(notes: record.model.notes, warnings: record.model.warnings)
            if record.model.status != "withdrawn" {
                ForEach(record.model.groups) { group in
                    WikiDoseReferenceGroupView(group: group)
                }
            }
            if let url = record.sourceURL {
                Link("Read source context", destination: url).font(.caption)
            }
        }
    }
}

private struct WikiDoseReferenceGroupView: View {
    let group: WikiDoseReferenceGroup
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            WikiDoseReferenceGroupContent(group: group)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !group.route.isEmpty {
                    Text(verbatim: group.route).font(.headline)
                } else {
                    Text("Route unknown").font(.headline)
                }
                if let formulation = group.formulation {
                    Text(verbatim: formulation).captionSecondary()
                }
                if group.kind == "provisional_human" {
                    Text("Provisional human reference · editorial hypotheses")
                        .font(.caption.bold())
                } else if group.bands.isEmpty {
                    Text("Source context").captionSecondary()
                } else {
                    Text("Published dose reference").captionSecondary()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Expanded source context and bands, independent of disclosure state.
struct WikiDoseReferenceGroupContent: View {
    let group: WikiDoseReferenceGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if group.kind == "provisional_human" {
                Text("These proposed bands are editorial hypotheses. Human observations do not establish population-wide intensity bands or a safe upper limit.")
                    .captionSecondary()
            }
            WikiDoseReferenceField("Published units", value: group.units)
            WikiDoseReferenceField("Material basis", value: group.materialBasis)
            WikiDoseReferenceField("Population and limits", value: group.populationLimits)
            if group.calculationEligible == false {
                Text("Excluded from calculations by the source.").captionSecondary()
            }
            WikiDoseReferenceNotes(notes: group.notes, warnings: group.warnings)
            ForEach(group.bands) { band in
                WikiDoseReferenceBandView(band: band, group: group)
                if band.id != group.bands.last?.id { Divider() }
            }
            if !group.sources.isEmpty || !group.observations.isEmpty {
                DisclosureGroup("All evidence and source context") {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(group.sources) { source in
                            WikiDoseReferenceSourceView(source: source)
                        }
                        ForEach(Array(group.observations.enumerated()), id: \.offset) { _, observation in
                            WikiDoseReferenceObservationView(observation: observation, sources: group.sources)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

private struct WikiDoseReferenceBandView: View {
    let band: WikiDoseReferenceBand
    let group: WikiDoseReferenceGroup

    private var observations: [WikiDoseReferenceJSON] {
        group.observations.filter { observation in
            guard let id = observation["id"]?.stringValue else { return false }
            return band.sourceObservationIds.contains(id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: band.label).font(.subheadline.bold())
            // Source text retains inequalities, units and prose without inventing
            // a scale or a missing endpoint for an open-ended amount.
            Text(verbatim: band.text).font(.body.monospacedDigit())
            Text(WikiDoseReferenceLabels.status(band.status)).font(.caption.bold())
            Text("Confidence: \(WikiDoseReferenceLabels.confidence(band.confidence))")
                .font(.caption)
            if band.calculationEligible == false {
                Text("Excluded from calculations by the source.").captionSecondary()
            }
            WikiDoseReferenceNotes(notes: band.notes, warnings: [])
            DisclosureGroup("Evidence and qualifications") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    WikiDoseReferenceField("Material basis", value: band.provenance?["analyte_basis"]?.stringValue)
                    WikiDoseReferenceField("Source explanation", value: band.provenance?["basis"]?.stringValue)
                    WikiDoseReferenceAdditionalContext(value: band.provenance, excluding: [
                        "id", "band", "label", "lower", "upper", "status", "confidence", "calculation_eligible",
                        "source_observation_ids", "source", "lineage_reviewed", "note", "basis", "analyte_basis",
                    ])
                    ForEach(group.sources.filter { band.sourceIds.contains($0.id) }) { source in
                        WikiDoseReferenceSourceView(source: source)
                    }
                    ForEach(Array(observations.enumerated()), id: \.offset) { _, observation in
                        WikiDoseReferenceObservationView(observation: observation, sources: group.sources)
                    }
                    if band.sourceIds.isEmpty, observations.isEmpty {
                        Text("No supporting sources or observations are linked to this band.")
                            .captionSecondary()
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .font(.caption)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WikiDoseReferenceObservationView: View {
    let observation: WikiDoseReferenceJSON
    let sources: [WikiDoseReferenceSource]

    private var sourceIDs: [String] {
        observation["source_ids"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Human observation").font(.caption.bold())
            WikiDoseReferenceField("Reported amount", value: observation["dose"]?["text"]?.stringValue)
            if let tier = WikiDoseReferenceLabels.evidence(observation["evidence_tier"]?.stringValue) {
                Text(tier).font(.caption)
            }
            WikiDoseReferenceField("Route", value: WikiDoseReferenceLabels.route(observation["route"]?.stringValue))
            WikiDoseReferenceField("Population and context", value: observation["population"]?.stringValue)
            WikiDoseReferenceField("Chemical form", value: observation["chemical_form"]?.stringValue)
            WikiDoseReferenceField("Material basis", value: observation["mass_basis"]?.stringValue)
            WikiDoseReferenceProse("Observed effects", value: observation["observed_effects"])
            WikiDoseReferenceProse("Adverse effects", value: observation["adverse_effects"])
            WikiDoseReferenceProse("Limitations", value: observation["limitations"])
            WikiDoseReferenceAdditionalContext(value: observation, excluding: [
                "id", "dose", "route", "population", "chemical_form", "mass_basis", "evidence_tier",
                "observed_effects", "adverse_effects", "limitations", "source_ids",
            ])
            ForEach(sources.filter { sourceIDs.contains($0.id) }) { source in
                WikiDoseReferenceSourceLink(source: source)
            }
        }
    }
}

private struct WikiDoseReferenceSourceView: View {
    let source: WikiDoseReferenceSource

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            WikiDoseReferenceSourceLink(source: source)
            WikiDoseReferenceField("Source date", value: source.details["date"]?.stringValue)
            WikiDoseReferenceField("Source revision", value: source.details["revision"]?.stringValue)
            WikiDoseReferenceProse("Source context", value: source.details["lineage"])
            WikiDoseReferenceField("Citation", value: source.details["citation"]?.stringValue)
            WikiDoseReferenceField("Source location", value: source.details["locator"]?.stringValue)
            if let access = WikiDoseReferenceLabels.access(source.details["evidence_access"]?.stringValue) {
                Text(access).captionSecondary()
            }
            WikiDoseReferenceAdditionalContext(value: source.details, excluding: [
                "id", "title", "name", "url", "date", "revision", "lineage", "citation", "locator",
                "evidence_access", "lineage_reviewed",
            ])
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WikiDoseReferenceSourceLink: View {
    let source: WikiDoseReferenceSource

    var body: some View {
        if let url = source.safeURL {
            Link(destination: url) {
                if let title = source.title, !title.isEmpty {
                    Text(verbatim: title)
                } else {
                    Text("Read source context")
                }
            }
            .font(.caption)
        } else if let title = source.title, !title.isEmpty {
            Text(verbatim: title).font(.caption.bold())
        } else {
            Text("Source link unavailable").captionSecondary()
        }
    }
}

private struct WikiDoseReferenceField: View {
    let title: LocalizedStringKey
    let value: String?

    init(_ title: LocalizedStringKey, value: String?) {
        self.title = title
        self.value = value
    }

    var body: some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.caption.bold())
                Text(verbatim: value).captionSecondary()
            }
        }
    }
}

private struct WikiDoseReferenceProse: View {
    let title: LocalizedStringKey
    let value: WikiDoseReferenceJSON?

    init(_ title: LocalizedStringKey, value: WikiDoseReferenceJSON?) {
        self.title = title
        self.value = value
    }

    private var paragraphs: [String] {
        if let text = value?.stringValue { return text.isEmpty ? [] : [text] }
        return value?.arrayValue?.compactMap(\.stringValue).filter { !$0.isEmpty } ?? []
    }

    var body: some View {
        if !paragraphs.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.caption.bold())
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph).captionSecondary()
                }
            }
        }
    }
}

private struct WikiDoseReferenceNotes: View {
    let notes: [String]
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                Text(verbatim: note).captionSecondary()
            }
            if !warnings.isEmpty {
                Text("Warnings").font(.caption.bold())
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    Text(verbatim: warning).captionSecondary()
                }
            }
        }
    }
}

private struct WikiDoseReferenceAdditionalContext: View {
    let value: WikiDoseReferenceJSON?
    let excluding: Set<String>

    private var paragraphs: [String] {
        WikiDoseReferenceSourceText.additionalProse(value, excluding: excluding)
    }

    var body: some View {
        if !paragraphs.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Additional source context").font(.caption.bold())
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph).captionSecondary()
                }
            }
        }
    }
}

/// New prose qualifications remain readable without exposing a JSON document or
/// treating an unfamiliar numeric field as a new dose boundary.
enum WikiDoseReferenceSourceText {
    static func additionalProse(_ value: WikiDoseReferenceJSON?, excluding: Set<String>) -> [String] {
        guard let fields = value?.objectValue else { return [] }
        return fields.keys.sorted().filter { !excluding.contains($0) }
            .flatMap { prose(fields[$0]) }
    }

    private static func prose(_ value: WikiDoseReferenceJSON?) -> [String] {
        guard let value else { return [] }
        return switch value {
        case let .string(text): text.isEmpty ? [] : [text]
        case let .array(values): values.flatMap { prose($0) }
        case let .object(fields): fields.keys.sorted().flatMap { prose(fields[$0]) }
        default: []
        }
    }
}

enum WikiDoseReferenceLabels {
    static func status(_ token: String?) -> String {
        switch token {
        case "supported": String(localized: "Source-supported")
        case "low_confidence": String(localized: "Low-confidence reference")
        case "editorial_hypothesis": String(localized: "Editorial hypothesis")
        case "legacy_unverified": String(localized: "Unverified legacy reference")
        default: provided(token) ?? String(localized: "Status not specified")
        }
    }

    static func confidence(_ value: WikiDoseReferenceJSON?) -> String {
        if let number = value?.numberValue { return String(number) }
        switch value?.stringValue {
        case "very_low": return String(localized: "Very low")
        case "low": return String(localized: "Low")
        case "low_moderate": return String(localized: "Low to moderate")
        case "moderate": return String(localized: "Moderate")
        case "high": return String(localized: "High")
        default: return provided(value?.stringValue) ?? String(localized: "Not specified")
        }
    }

    static func route(_ value: String?) -> String? {
        value == "not_reported" ? String(localized: "Not reported") : value
    }

    static func evidence(_ token: String?) -> String? {
        switch token {
        case "historical_self_experiment": String(localized: "Historical self-experiment")
        case "historical_summary": String(localized: "Historical summary")
        case "clinical_trial": String(localized: "Clinical trial")
        case "unverified_anecdote": String(localized: "Unverified personal report")
        default: provided(token)
        }
    }

    static func access(_ token: String?) -> String? {
        switch token {
        case "primary_full_text": String(localized: "Primary source · full text reviewed")
        case "primary_abstract": String(localized: "Primary source · abstract reviewed")
        case "primary_metadata": String(localized: "Primary source · metadata only")
        case "authoritative_reproduction": String(localized: "Authoritative reproduction")
        case "first_person_report": String(localized: "First-person report")
        default: provided(token)
        }
    }

    private static func provided(_ token: String?) -> String? {
        guard let token, !token.isEmpty else { return nil }
        return token
    }
}
