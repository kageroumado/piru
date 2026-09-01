import Foundation
import SwiftData
import Testing
@testable import Piru

private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Schema(StoreRecovery.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
    )
    return ModelContext(container)
}

// MARK: - Migration shim

@MainActor
@Suite("SessionNote — summary shim")
struct SessionNoteShimTests {
    @Test
    func `A pre-notes summary becomes one summary note at the session start`() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(startDate: start, note: "Quiet evening.")
        context.insert(session)
        try context.save()

        SessionNoteService.migrateLegacySummaries(in: context)

        let notes = session.orderedNotes
        #expect(notes.count == 1)
        #expect(notes.first?.kind == .summary)
        #expect(notes.first?.text == "Quiet evening.")
        #expect(notes.first?.timestamp == start)

        // Idempotent: a second pass adds nothing.
        SessionNoteService.migrateLegacySummaries(in: context)
        #expect(session.orderedNotes.count == 1)
    }

    @Test
    func `Setting the summary writes both the field and the summary note`() throws {
        let context = try makeContext()
        let session = Session(startDate: .now)
        context.insert(session)

        SessionService.setNote("  First take  ", for: session)
        #expect(session.note == "First take")
        #expect(SessionNoteService.summaryNote(of: session)?.text == "First take")

        SessionService.setNote("Second take", for: session)
        #expect(session.orderedNotes.filter { $0.kind == .summary }.count == 1)
        #expect(SessionNoteService.summaryNote(of: session)?.text == "Second take")

        SessionService.setNote("", for: session)
        #expect(session.note == nil)
        #expect(SessionNoteService.summaryNote(of: session) == nil)
    }

    @Test
    func `An empty draft is not inserted`() throws {
        let context = try makeContext()
        let session = Session(startDate: .now)
        context.insert(session)
        #expect(SessionNoteService.add(to: session, timestamp: .now, text: "   ") == nil)
        #expect(SessionNoteService.add(to: session, timestamp: .now, text: "", shulgin: 2) != nil)
        #expect(session.orderedNotes.count == 1)
    }

    @Test
    func `Deleting a session cascades to its notes`() throws {
        let context = try makeContext()
        let session = Session(startDate: .now)
        context.insert(session)
        SessionNoteService.add(to: session, timestamp: .now, text: "gone with it")
        try context.save()
        context.delete(session)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SessionNote>()) == 0)
    }
}

// MARK: - T+ and structure formatting

@Suite("TripReport — formatting")
struct TripReportFormattingTests {
    @Test
    func `T+ offsets are hours and zero-padded minutes`() {
        #expect(TripReport.tPlus(0) == "T+0:00")
        #expect(TripReport.tPlus(45 * 60) == "T+0:45")
        #expect(TripReport.tPlus(130 * 60) == "T+2:10")
        #expect(TripReport.tPlus(26 * 3_600 + 5 * 60) == "T+26:05")
        #expect(TripReport.tPlus(29.6) == "T+0:00")
        #expect(TripReport.tPlus(-15 * 60) == "T−+0:15")
    }

    @Test
    func `Structure line omits what was not captured`() {
        #expect(TripReport.structureLine(shulgin: nil, mood: nil, energy: nil, heartRate: nil) == "")
        #expect(TripReport.structureLine(shulgin: 2, mood: nil, energy: nil, heartRate: nil) == "++")
        #expect(TripReport.structureLine(shulgin: 0, mood: 2, energy: -1, heartRate: 84) == "± · mood +2 · energy −1 · ♥ 84")
        #expect(TripReport.structureLine(shulgin: 9, mood: 0, energy: nil, heartRate: nil) == "mood 0")
    }
}

// MARK: - Trip report shape

@MainActor
@Suite("TripReport — build")
struct TripReportBuildTests {
    @Test
    func `Notes render at their offsets and descriptors group by domain with first-noted T+`() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(startDate: start, note: "Good night.")
        context.insert(session)
        let dose = DoseEntry(substance: "LSD", amount: 100, unit: "µg", route: .sublingual, timestamp: start)
        dose.session = session
        context.insert(dose)
        let ontology = SubjectiveEffectOntology.shared
        let geometry = try #require(ontology.search("geometric imagery").first?.concept)
        let nausea = try #require(ontology.search("nausea").first?.concept)
        SessionNoteService.add(to: session, timestamp: start.addingTimeInterval(40 * 60), text: "queasy", shulgin: 0, descriptors: [nausea.id])
        SessionNoteService.add(to: session, timestamp: start.addingTimeInterval(125 * 60), text: "patterns", shulgin: 3, mood: 2, descriptors: [geometry.id, nausea.id], kind: .checkIn)
        SessionNoteService.ensureSummaryNote(for: session)

        let report = TripReport.build(session: session)
        #expect(report.notes.count == 2)
        #expect(report.summary == "Good night.")

        let grouped = report.descriptorsByDomain
        #expect(grouped.map(\.domain) == [nausea.domain, geometry.domain])
        let nauseaFirst = try #require(grouped.first?.first.first)
        #expect(nauseaFirst.at == start.addingTimeInterval(40 * 60))

        let md = report.markdown(locale: Locale(identifier: "en_US"))
        #expect(md.contains("**T+0:40**"))
        #expect(md.contains("**T+2:05**"))
        #expect(md.contains("check-in"))
        #expect(md.contains("+++ · mood +2"))
        #expect(md.contains("## Descriptors by domain"))
        #expect(md.contains("- \(geometry.name) — T+2:05"))
        #expect(md.contains("## Summary"))
        #expect(!md.lowercased().contains("harm reduction"))
    }
}

// MARK: - Export shape

@MainActor
@Suite("SessionNote — export")
struct SessionNoteExportTests {
    @Test
    func `Native export carries notes and a re-import keeps them once`() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(startDate: start, note: "Summary text")
        context.insert(session)
        let dose = DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", route: .oral, timestamp: start)
        dose.session = session
        context.insert(dose)
        SessionNoteService.add(to: session, timestamp: start.addingTimeInterval(600), text: "warm", shulgin: 1, mood: 2, energy: -1, descriptors: ["abc"], heartRate: 84)
        SessionNoteService.ensureSummaryNote(for: session)
        try context.save()

        let data = try DataExportImport.exportJSON(format: .piru, context: context)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sessions = try #require(json["sessions"] as? [[String: Any]])
        let notes = try #require(sessions.first?["notes"] as? [[String: Any]])
        #expect(notes.count == 2)
        let observation = try #require(notes.first { ($0["kind"] as? String) == "observation" })
        #expect(observation["shulgin"] as? Int == 1)
        #expect(observation["mood"] as? Int == 2)
        #expect(observation["energy"] as? Int == -1)
        #expect(observation["heartRate"] as? Double == 84)
        #expect(observation["descriptors"] as? [String] == ["abc"])

        try DataExportImport.importJSON(data: data, context: context)
        #expect(try context.fetchCount(FetchDescriptor<SessionNote>()) == 2)

        try DataExportImport.deleteAll(context: context)
        try context.save()
        try DataExportImport.importJSON(data: data, context: context)
        let restored = try context.fetch(FetchDescriptor<Session>())
        #expect(restored.count == 1)
        #expect(restored.first?.orderedNotes.count == 2)
        #expect(restored.first?.orderedNotes.first?.kind == .summary)
        #expect(restored.first?.note == "Summary text")
    }

    @Test
    func `PsyLog export writes timed notes in PsychonautWiki's shape and reads them back`() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = Session(startDate: start)
        context.insert(session)
        let dose = DoseEntry(substance: "Caffeine", amount: 100, unit: "mg", route: .oral, timestamp: start)
        dose.session = session
        context.insert(dose)
        SessionNoteService.add(to: session, timestamp: start.addingTimeInterval(1_200), text: "warm", shulgin: 2)
        try context.save()

        let data = try DataExportImport.exportJSON(format: .psyLog, context: context)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let experiences = try #require(json["experiences"] as? [[String: Any]])
        let timed = try #require(experiences.first?["timedNotes"] as? [[String: Any]])
        #expect(timed.count == 1)
        #expect(timed.first?["time"] as? Int64 == start.addingTimeInterval(1_200).msSince1970)
        #expect(timed.first?["note"] as? String == "[++] warm")
        #expect(timed.first?["color"] as? String == "blue")
        #expect(timed.first?["isPartOfTimeline"] as? Bool == true)

        try DataExportImport.deleteAll(context: context)
        try context.save()
        try DataExportImport.importJSON(data: data, context: context)
        let restored = try #require(try context.fetch(FetchDescriptor<Session>()).first)
        #expect(restored.orderedNotes.map(\.text) == ["[++] warm"])
    }
}

// MARK: - Ontology reader

@MainActor
@Suite("SubjectiveEffectOntology")
struct SubjectiveEffectOntologyTests {
    @Test
    func `Twenty-one rollups, each atomic under exactly one`() {
        let ontology = SubjectiveEffectOntology.shared
        let rollups = ontology.rollups
        #expect(rollups.count == 21)
        #expect(Set(rollups.map(\.domain)).count == 21)
        let atomicCount = rollups.reduce(0) { $0 + ontology.atomics(under: $1).count }
        #expect(atomicCount == 485)
        for rollup in rollups {
            for atomic in ontology.atomics(under: rollup) {
                #expect(!atomic.isRollup)
                #expect(ontology.rollup(of: atomic)?.id == rollup.id)
            }
        }
    }

    @Test
    func `Search matches names, then aliases, and reports the alias`() throws {
        let ontology = SubjectiveEffectOntology.shared
        let byName = ontology.search("nausea")
        #expect(byName.first?.concept.name == "nausea")
        #expect(byName.first?.matchedAlias == nil)

        let byAlias = ontology.search("absorbed in the present")
        let hit = try #require(byAlias.first)
        #expect(hit.concept.name == "attentional absorption")
        #expect(hit.matchedAlias == "absorbed in the present")

        #expect(ontology.search("   ").isEmpty)
        #expect(ontology.search("zzzz-no-such-effect").isEmpty)
    }

    @Test
    func `Query normalization follows the release`() {
        #expect(SubjectiveEffectOntology.normalize("  Closed–Eye   Visuals ") == "closed-eye visuals")
        #expect(SubjectiveEffectOntology.normalize("déjà_vu") == "deja vu")
        #expect(SubjectiveEffectOntology.normalize("Δ-wave") == "delta-wave")
    }

    @Test
    func `Unknown ids fall back to the id, never blank`() {
        #expect(SubjectiveEffectOntology.shared.name(for: "not-a-concept") == "not-a-concept")
    }
}

// MARK: - Check-ins

@Suite("CheckInScheduler")
struct CheckInSchedulerTests {
    @Test
    func `Fire dates follow the cadence from the anchor and skip the past`() {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let ladder = CheckInScheduler.fireDates(cadence: .ladder, anchor: anchor, now: anchor)
        #expect(ladder.map { $0.timeIntervalSince(anchor) / 60 } == [30, 60, 120, 240, 360])

        let late = CheckInScheduler.fireDates(cadence: .everyHour, anchor: anchor, now: anchor.addingTimeInterval(150 * 60))
        #expect(late.first.map { Int($0.timeIntervalSince(anchor).rounded()) } == 180 * 60)
        #expect(late.count == 6)

        #expect(CheckInScheduler.Cadence(storedMinutes: nil) == nil)
        #expect(CheckInScheduler.Cadence(storedMinutes: 0) == .ladder)
        #expect(CheckInScheduler.Cadence(storedMinutes: 60) == .everyHour)
    }

    @Test
    func `Nearest heart-rate sample within two minutes, workouts excluded`() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            HeartRateSample(date: at.addingTimeInterval(-100), bpm: 80),
            HeartRateSample(date: at.addingTimeInterval(30), bpm: 84),
            HeartRateSample(date: at.addingTimeInterval(10), bpm: 140, isWorkout: true),
            HeartRateSample(date: at.addingTimeInterval(500), bpm: 70),
        ]
        #expect(SessionNoteDraft.nearestHeartRate(to: at, in: samples) == 84)
        #expect(SessionNoteDraft.nearestHeartRate(to: at.addingTimeInterval(1_000), in: samples) == nil)
    }
}
