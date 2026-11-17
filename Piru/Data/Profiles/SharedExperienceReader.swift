import Foundation
import SwiftData

// MARK: - Snapshots

/// One dose from another profile's shared session, copied out of their store so
/// it can cross actors and outlive the context that read it.
nonisolated struct SharedDoseSnapshot: Hashable, Sendable, Codable {
    let id: UUID
    let substance: String
    let amount: Double
    let unit: String
    let routeRaw: String
    let timestamp: Date
    let saltForm: String?
    let isomer: String?
    let releaseForm: String?
    let productName: String?
    let substanceUID: String?
    let displayNameSnapshot: String?
    let mealRaw: String?
    let combinationName: String?
    let volumeML: Double?
    let abv: Double?
    let drinkName: String?
    let isApproximate: Bool
    let isUnknownDose: Bool
    let isBackgroundMed: Bool
    /// The substance's color in their journal.
    let tint: P3Color

    init(_ entry: DoseEntry, tint: P3Color) {
        id = entry.id
        substance = entry.substance
        amount = entry.amount
        unit = entry.unit
        routeRaw = entry.route.rawValue
        timestamp = entry.timestamp
        saltForm = entry.saltForm
        isomer = entry.isomer
        releaseForm = entry.releaseForm
        productName = entry.productName
        substanceUID = entry.substanceUID
        displayNameSnapshot = entry.displayNameSnapshot
        mealRaw = entry.mealRaw
        combinationName = entry.combinationName
        volumeML = entry.volumeML
        abv = entry.abv
        drinkName = entry.drinkName
        isApproximate = entry.isApproximate
        isUnknownDose = entry.isUnknownDose
        isBackgroundMed = entry.isBackgroundMed
        self.tint = tint
    }
}

extension SharedDoseSnapshot {
    /// The dose as a `DoseEntry` that belongs to no context, for the engines
    /// and row builders that read one. Never inserted anywhere: it exists only
    /// to be drawn.
    func detachedEntry() -> DoseEntry {
        let entry = DoseEntry(
            substance: substance,
            amount: amount,
            unit: unit,
            route: RouteOfAdministration(rawValue: routeRaw) ?? .oral,
            saltForm: saltForm,
            isomer: isomer,
            releaseForm: releaseForm,
            productName: productName,
            substanceUID: substanceUID,
            displayNameSnapshot: displayNameSnapshot,
            timestamp: timestamp,
            isBackgroundMed: isBackgroundMed,
            meal: mealRaw.flatMap(MealState.init(rawValue:)),
            isApproximate: isApproximate,
            isUnknownDose: isUnknownDose,
            volumeML: volumeML,
            abv: abv,
            drinkName: drinkName,
            combinationName: combinationName,
        )
        entry.id = id
        return entry
    }
}

/// A timestamped note from another profile's shared session.
nonisolated struct SharedNoteSnapshot: Hashable, Sendable, Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let text: String
}

/// One other profile's side of a shared experience: their session (every one
/// of theirs carrying the id, merged) and what they logged in it.
nonisolated struct SharedSessionSnapshot: Hashable, Sendable {
    let profileID: UUID
    /// Their session's id; the earliest when they have more than one.
    let sessionID: UUID
    let title: String?
    let summary: String?
    let startDate: Date
    let doses: [SharedDoseSnapshot]
    let notes: [SharedNoteSnapshot]
    /// Their own body weight, when their journal records one.
    let weightKg: Double?
}

// MARK: - Reading

/// Reads other profiles' stores for shared experiences, on ``DatabaseActor``
/// with a fresh context per read, so nothing here touches the main actor or
/// keeps a model object alive.
nonisolated enum SharedExperienceReader {
    /// `profileID`'s side of `experienceID` in `container`, or `nil` when they
    /// have no session carrying it.
    @DatabaseActor
    static func session(
        experienceID: UUID,
        profileID: UUID,
        in container: ModelContainer,
    ) -> SharedSessionSnapshot? {
        let context = ModelContext(container)
        let target: UUID? = experienceID
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.sharedExperienceID == target },
            sortBy: [SortDescriptor(\.startDate)],
        )
        guard let sessions = try? context.fetch(descriptor), let first = sessions.first else { return nil }

        let entries = sessions.flatMap { $0.doses ?? [] }.sorted { $0.timestamp < $1.timestamp }
        let names = Set(entries.map { $0.substance.lowercased() })
        let colors = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        var tintMap: [String: P3Color] = [:]
        for color in colors where names.contains(color.substance.lowercased()) {
            tintMap[color.substance.lowercased()] = color.tint
        }
        let doses = entries.map { SharedDoseSnapshot($0, tint: SubstancePalette.tint(for: $0.substance, tintMap: tintMap)) }

        let notes = sessions.flatMap { $0.notes ?? [] }
            .filter { $0.kind != .summary && $0.hasContent }
            .sorted { $0.timestamp < $1.timestamp }
            .map { SharedNoteSnapshot(id: $0.id, timestamp: $0.timestamp, text: $0.text) }
        let summary = sessions.compactMap(\.note).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let weight = (try? context.fetch(FetchDescriptor<UserProfileRecord>()))?.first?.bodyWeightKg

        return SharedSessionSnapshot(
            profileID: profileID,
            sessionID: first.id,
            title: sessions.compactMap(\.title).first,
            summary: summary,
            startDate: entries.first?.timestamp ?? first.startDate,
            doses: doses,
            notes: notes,
            weightKg: weight,
        )
    }

    /// One linked session in a store: its id, its experience, and whether it
    /// holds a dose.
    struct LinkedSession: Hashable, Sendable {
        let sessionID: UUID
        let experienceID: UUID
        let hasDoses: Bool
    }

    /// Every session in `container` that is part of a shared experience.
    @DatabaseActor
    static func linkedSessions(in container: ModelContainer) -> [LinkedSession] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.sharedExperienceID != nil })
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.compactMap { session in
            session.sharedExperienceID.map {
                LinkedSession(sessionID: session.id, experienceID: $0, hasDoses: !(session.doses ?? []).isEmpty)
            }
        }
    }
}
