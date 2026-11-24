import Foundation
import GRDB
import PortableData

/// A store file of its own for one test, opened as the app opens its journal, and read
/// behind PortableData's back through a second SQLite connection.
struct TestStore {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "piru-portable-\(UUID().uuidString)")
        .appending(path: "journal.store")

    func container(allowsSave: Bool = true) throws -> ModelContainer {
        try ModelContainer(for: Schema(PiruSchema.models), configurations: ModelConfiguration(url: url, allowsSave: allowsSave))
    }

    func execute(_ sql: String, _ arguments: StatementArguments = []) throws {
        try DatabaseQueue(path: url.path).write { try $0.execute(sql: sql, arguments: arguments) }
    }

    /// Each stored row of `entity` that parses, as its JSON object, keyed by primary key.
    func rows(_ entity: String) throws -> [String: [String: Any]] {
        let rows = try DatabaseQueue(path: url.path).read { db in
            try Row.fetchAll(db, sql: "SELECT pk, data FROM portable_models WHERE entity = ?", arguments: [entity])
        }
        var result: [String: [String: Any]] = [:]
        for row in rows {
            let data: Data = row["data"]
            result[row["pk"]] = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return result
    }

    func count(_ entity: String) throws -> Int {
        try DatabaseQueue(path: url.path).read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM portable_models WHERE entity = ?", arguments: [entity]) ?? 0
        }
    }

    /// The store generation each row of `entity` was last written in.
    func generations(_ entity: String) throws -> [String: Int] {
        let rows = try DatabaseQueue(path: url.path).read { db in
            try Row.fetchAll(db, sql: "SELECT pk, gen FROM portable_models WHERE entity = ?", arguments: [entity])
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0["pk"], $0["gen"]) })
    }

    /// Rewrites every stored row of `entity` with SQLite's JSON functions, as an older or
    /// newer build would have written it.
    func rewrite(_ entity: String, _ expression: String, where condition: String = "1") throws {
        try execute("""
        UPDATE portable_models SET data = CAST(\(expression) AS BLOB)
        WHERE entity = '\(entity)' AND \(condition)
        """)
    }
}

let origin = Date(timeIntervalSinceReferenceDate: 812_345_678.123_456)

extension UserDefaults {
    /// The app's twin (Android/Platform/Foundation+Android.swift), which the staged sources'
    /// app-group reads name.
    nonisolated static var androidAppGroup: UserDefaults? {
        .standard
    }
}

/// A journal: one session holding three doses an hour apart, a note in that session, a
/// tolerance cache row and the notification preferences singleton.
@discardableResult
func seedJournal(_ store: TestStore) throws -> (session: UUID, doses: [UUID]) {
    let context = try ModelContext(store.container())
    let session = Session(startDate: origin, title: "Saturday")
    context.insert(session)
    var doses: [UUID] = []
    for index in 0 ..< 3 {
        let dose = DoseEntry(substance: "caffeine\(index)", amount: Double(100 + index), timestamp: origin.addingTimeInterval(Double(index) * 3600))
        dose.session = session
        context.insert(dose)
        doses.append(dose.id)
    }
    let note = SessionNote(text: "calm", session: session)
    context.insert(note)
    context.insert(ToleranceState(target: "serotonin", sAcute: 0.25, lastUpdated: origin))
    context.insert(NotificationPreferences())
    try context.save()
    return (session.id, doses)
}

extension ModelContext {
    func doses() throws -> [DoseEntry] {
        try fetch(FetchDescriptor<DoseEntry>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    func dose(_ id: UUID) throws -> DoseEntry? {
        try fetch(FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.id == id })).first
    }

    func sessions() throws -> [Session] {
        try fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate)]))
    }
}
