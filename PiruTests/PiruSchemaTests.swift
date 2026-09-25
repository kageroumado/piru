import Foundation
import SwiftData
import Testing
@testable import Piru

/// Guards the one schema every target opens the store with. SwiftData reads a
/// schema that omits an entity the store holds as an instruction to migrate
/// that entity away: read-only opens then fail (the widget showed "No active
/// session" for every user) and writable opens drop the omitted tables from the
/// canonical store. The two source scans keep that from recurring silently;
/// the reopen test pins the widget's exact read path.
@Suite("PiruSchema")
@MainActor
struct PiruSchemaTests {
    /// `<repo>/PiruTests/PiruSchemaTests.swift` → `<repo>`.
    private static func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Every target that ships code, plus the shared folders they compile.
    private static let shippingFolders = [
        "Piru", "Shared", "PiruWidget", "PiruLiveActivityExtension",
        "PiruWatch Watch App", "PiruComplication",
    ]

    private static func swiftSources(in folders: [String]) throws -> [(path: String, text: String)] {
        let root = repoRoot()
        var out: [(String, String)] = []
        for folder in folders {
            let dir = root.appendingPathComponent(folder)
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                try out.append((url.path.replacingOccurrences(of: root.path + "/", with: ""), String(contentsOf: url, encoding: .utf8)))
            }
        }
        return out
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0 ..< match.numberOfRanges).map { i in
                guard let r = Range(match.range(at: i), in: text) else { return "" }
                return String(text[r])
            }
        }
    }

    @Test
    func `deleting the journal empties every model and remains empty after reopening`() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-reset-\(UUID()).store")
        try autoreleasepool {
            let container = try ModelContainer(for: Schema(PiruSchema.models), configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = container.mainContext
            let session = Session(startDate: .now)
            context.insert(session)
            let entry = DoseEntry(substance: "Caffeine", amount: 100)
            context.insert(entry)
            entry.session = session
            context.insert(SubstanceColor(substance: "Caffeine", tint: P3Color(red: 1, green: 0.2, blue: 0.4), usesDefault: false))
            context.insert(DailyDoseItem(substance: "Caffeine", amount: 100))
            context.insert(FavoriteSubstance(substance: "Caffeine"))
            context.insert(QuickLogDose(substance: "Caffeine", route: .oral, amount: 100, unit: "mg", sortOrder: 0))
            context.insert(DoseRoutine(name: "Morning"))
            context.insert(InventoryItem(substance: "Caffeine"))
            context.insert(UserProfileRecord())
            context.insert(ToleranceState(target: "adenosine"))
            context.insert(CustomSubstanceRecord(name: "Custom"))
            context.insert(CustomDrinkPreset(name: "Custom drink", strengthABV: 5))
            context.insert(CustomUnitPreset(substanceName: "Caffeine", label: "tablet", amountPerUnit: 100))
            context.insert(NotificationPreferences())
            context.insert(RoutineOccurrence(substance: "Caffeine", route: .oral, dueDay: .now))
            context.insert(SessionNote(text: "Private note", session: session))
            context.insert(LabMeasurement(value: 100, note: "Private result"))
            try context.save()
            for model in PiruSchema.models { #expect(try Self.count(model, in: context) > 0) }
            try DataExportImport.deleteAll(context: context)
            for model in PiruSchema.models { #expect(try Self.count(model, in: context) == 0) }
            try DataExportImport.deleteAll(context: context)
        }
        let reopened = try ModelContainer(for: Schema(PiruSchema.models), configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        for model in PiruSchema.models { #expect(try Self.count(model, in: reopened.mainContext) == 0) }
    }

    private static func count<M: PersistentModel>(_: M.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<M>())
    }

    @Test
    func `every @Model class in the repo is in PiruSchema.models`() throws {
        let declared = try Set(Self.swiftSources(in: Self.shippingFolders).flatMap { file in
            // `@Model`, any further attributes, then the class keyword and name.
            Self.matches(#"@Model\s+(?:@\w+(?:\([^)]*\))?\s+)*(?:public\s+|final\s+)*class\s+(\w+)"#, in: file.text).map { $0[1] }
        })
        let listed = Set(PiruSchema.models.map { String(describing: $0) })
        #expect(!declared.isEmpty)
        #expect(declared.subtracting(listed).isEmpty, "@Model types missing from PiruSchema.models: \(declared.subtracting(listed).sorted())")
        #expect(listed.subtracting(declared).isEmpty, "PiruSchema.models names types no target declares: \(listed.subtracting(declared).sorted())")
    }

    @Test
    func `no target opens a store with anything but PiruSchema.models`() throws {
        var offenders: [String] = []
        for file in try Self.swiftSources(in: Self.shippingFolders) where file.path != "Shared/Models/PiruSchema.swift" {
            // A container built from an explicit type list, or a Schema built from
            // a literal array, is a second copy of the model list waiting to drift.
            let typeList = Self.matches(#"ModelContainer\(\s*for:\s*[A-Z]\w*\.self"#, in: file.text)
            let literalSchema = Self.matches(#"Schema\(\s*\["#, in: file.text)
            let containers = Self.matches(#"ModelContainer\(\s*for:"#, in: file.text).count
            let viaShared = Self.matches(#"ModelContainer\(\s*for:\s*Schema\(PiruSchema\.models\)"#, in: file.text).count
            if !typeList.isEmpty || !literalSchema.isEmpty || containers != viaShared {
                offenders.append(file.path)
            }
        }
        #expect(offenders.isEmpty, "Containers not built from Schema(PiruSchema.models): \(offenders)")
    }

    @Test
    func `a full-schema store reopens read-only through PiruSchema and the widget's session query reads it`() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("piru-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("default.store")

        try autoreleasepool {
            let container = try ModelContainer(
                for: Schema(PiruSchema.models),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
            )
            let ctx = ModelContext(container)
            let entry = DoseEntry(substance: "Clonidine", amount: 0.1)
            ctx.insert(entry)
            let session = Session(startDate: entry.timestamp)
            ctx.insert(session)
            entry.session = session
            ctx.insert(NotificationPreferences())
            ctx.insert(CustomUnitPreset(substanceName: "Clonidine", label: "tab", amountPerUnit: 0.1))
            try ctx.save()
        }

        // The widget's open: read-only, no CloudKit, the shared schema.
        let readOnly = ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none)
        try autoreleasepool {
            let container = try ModelContainer(for: Schema(PiruSchema.models), configurations: readOnly)
            let ctx = ModelContext(container)
            var descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
            descriptor.fetchLimit = 1
            let doses = try ctx.fetch(descriptor).first?.orderedDoses ?? []
            #expect(doses.map(\.substance) == ["Clonidine"])
        }

        // The Take-Med intent's open, then the app's: every table survives.
        try autoreleasepool {
            let writable = ModelConfiguration(url: url, allowsSave: true, cloudKitDatabase: .none)
            _ = try ModelContainer(for: Schema(PiruSchema.models), configurations: writable)
        }
        let container = try ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none),
        )
        let ctx = ModelContext(container)
        #expect(try ctx.fetchCount(FetchDescriptor<NotificationPreferences>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<CustomUnitPreset>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<Session>()) == 1)
    }
}
