import Foundation
import SwiftData

// MARK: - DrugsPRO Codable Types

/// A DrugsPRO journal export (protestkit.eu/drugspro): `v` format version,
/// `t` export time, `e` experiences, `u` the flat usage ledger, `x` app state.
///
/// The two lists describe the same doses from two sides and neither is
/// complete alone. An experience substance carries the clock time and the
/// offset from the session's first dose, but its route is `roaIdx`, an index
/// into DrugsPRO's per-substance route list that this file does not include,
/// and it has no unit. A usage row carries the route name and the unit in
/// `dose` ("3.6 g"), but only a calendar date. ``DataExportImport/importDrugsPro``
/// joins them on (calendar day, name, amount).
nonisolated struct DrugsProFile: Decodable {
    var experiences: [DrugsProExperience]
    var usage: [DrugsProUsage]

    private enum CodingKeys: String, CodingKey {
        case experiences = "e"
        case usage = "u"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        experiences = try c.decode([DrugsProExperience].self, forKey: .experiences)
        usage = try c.decodeIfPresent([DrugsProUsage].self, forKey: .usage) ?? []
    }
}

nonisolated struct DrugsProExperience: Decodable {
    /// `yyyy-MM-dd`, the local day of the moment `minutesAhead` counts from.
    var date: String
    var title: String
    var description: String
    /// The substance names joined with " + ", which DrugsPRO also uses as the
    /// default title.
    var substanceSummary: String
    var substances: [DrugsProSubstance]

    private enum CodingKeys: String, CodingKey {
        case date
        case title
        case description
        case substanceSummary = "substance"
        case substances
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        substanceSummary = try c.decodeIfPresent(String.self, forKey: .substanceSummary) ?? ""
        substances = try c.decodeIfPresent([DrugsProSubstance].self, forKey: .substances) ?? []
    }
}

nonisolated struct DrugsProSubstance: Decodable {
    var name: String
    /// The amount, in the unit the matching usage row names.
    var doseMult: Double
    /// Minutes after the experience's zero point. It runs past midnight
    /// (`timeHHMM` "02:23" at 719 minutes after "14:24"), so it is what says
    /// which day a dose fell on.
    var minutesAhead: Int
    /// Local wall-clock time, `HH:mm`.
    var timeHHMM: String?
    /// The route's display name, written only on doses entered in DrugsPRO itself.
    var roaName: String?
    var tag: String
    var goal: String

    private enum CodingKeys: String, CodingKey {
        case name
        case doseMult
        case minutesAhead
        case timeHHMM
        case roaName
        case tag
        case goal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        doseMult = try c.decodeIfPresent(Double.self, forKey: .doseMult) ?? 0
        minutesAhead = try c.decodeIfPresent(Int.self, forKey: .minutesAhead) ?? 0
        timeHHMM = try c.decodeIfPresent(String.self, forKey: .timeHHMM)
        roaName = try c.decodeIfPresent(String.self, forKey: .roaName)
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? ""
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
    }
}

nonisolated struct DrugsProUsage: Decodable {
    /// `yyyy-MM-dd`, the local day the dose was taken.
    var dateISO: String
    var name: String
    /// Amount and unit separated by a space: "25 mg", "3.6 g", "1 units".
    var dose: String
    var roa: String

    var amount: Double? {
        dose.split(separator: " ", maxSplits: 1).first.flatMap { Double($0) }
    }

    var unit: String? {
        let parts = dose.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let unit = parts[1].trimmingCharacters(in: .whitespaces)
        return unit.isEmpty ? nil : unit
    }
}

// MARK: - DrugsPRO Import

extension DataExportImport {
    /// Whether a top-level JSON object is a DrugsPRO journal export.
    nonisolated static func isDrugsPro(_ object: [String: Any]) -> Bool {
        object["v"] != nil && object["e"] is [Any] && object["u"] is [Any]
    }

    /// Imports a DrugsPRO journal export: each experience becomes a session
    /// carrying its title and description, each substance a dose.
    ///
    /// Times are local wall-clock times with no zone in the file, so they are
    /// read in the device's current time zone. Experiences recur through a
    /// `schedule` in DrugsPRO; schedules, effect selections, prices, and
    /// achievement state are left behind.
    @MainActor
    static func importDrugsPro(data: Data, context: ModelContext) throws {
        let file = try JSONDecoder().decode(DrugsProFile.self, from: data)
        var ledger = DrugsProLedger(file.usage)
        let calendar = Calendar.current

        let existingDoses = (try? context.fetch(FetchDescriptor<DoseEntry>())) ?? []
        var seenDoseKeys = Set(existingDoses.map {
            doseDedupKey(substance: $0.substance, timestamp: $0.timestamp, amount: $0.amount, unit: $0.unit, route: $0.route)
        })

        for experience in file.experiences {
            guard let day = DrugsProLedger.day(experience.date, calendar: calendar),
                  let first = experience.substances.min(by: { $0.minutesAhead < $1.minutesAhead })
            else { continue }
            let firstClock = first.timeHHMM.flatMap(DrugsProLedger.minutes) ?? 0
            // `date` is the day of the experience's zero point, which a deleted
            // first dose can leave hours before the earliest remaining one, so
            // the zero point's clock is wrapped into that day.
            let start = ((firstClock - first.minutesAhead) % 1440 + 1440) % 1440

            var sessionDoses: [DoseEntry] = []
            for substance in experience.substances where substance.doseMult > 0 {
                let elapsed = start + substance.minutesAhead
                let clock = substance.timeHHMM.flatMap(DrugsProLedger.minutes) ?? ((elapsed % 1440) + 1440) % 1440
                // The day comes from the offset and the minute from the clock:
                // `minutesAhead` is rounded from seconds and can disagree with
                // `timeHHMM` by a minute.
                let dayOffset = Int((Double(elapsed - clock) / 1440).rounded())
                guard let doseDay = calendar.date(byAdding: .day, value: dayOffset, to: day),
                      let timestamp = calendar.date(bySettingHour: clock / 60, minute: clock % 60, second: 0, of: doseDay)
                else { continue }

                let row = ledger.take(day: doseDay, name: substance.name, amount: substance.doseMult)
                let routeName = row?.roa ?? substance.roaName
                let route = routeName.map(RouteOfAdministration.from(string:)) ?? .other
                let unit = row?.unit ?? ledger.unit(for: substance.name) ?? "mg"

                let key = doseDedupKey(substance: substance.name, timestamp: timestamp, amount: substance.doseMult, unit: unit, route: route)
                guard seenDoseKeys.insert(key).inserted else { continue }

                let tag = substance.tag.trimmingCharacters(in: .whitespaces)
                let goal = substance.goal.trimmingCharacters(in: .whitespacesAndNewlines)
                let entry = DoseEntry(
                    substance: substance.name,
                    amount: substance.doseMult,
                    unit: unit,
                    route: route,
                    timestamp: timestamp,
                    notes: goal.isEmpty ? nil : goal,
                    tags: tag.isEmpty ? [] : [tag],
                )
                context.insert(entry)
                sessionDoses.append(entry)
            }

            guard let sessionStart = sessionDoses.map(\.timestamp).min() else { continue }
            let title = experience.title.trimmingCharacters(in: .whitespaces)
            let description = experience.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let session = Session(
                startDate: sessionStart,
                // DrugsPRO titles an untitled experience with its substance list,
                // which Piru already draws from the doses.
                title: title.isEmpty || title == experience.substanceSummary ? nil : title,
                note: description.isEmpty ? nil : description,
            )
            context.insert(session)
            for dose in sessionDoses {
                dose.session = session
            }
            session.refreshDoseBounds()
            SessionNoteService.ensureSummaryNote(for: session)
        }

        var colorRows = (try? context.fetch(FetchDescriptor<SubstanceColor>())) ?? []
        for name in Set(file.experiences.flatMap { $0.substances.map(\.name) }) {
            if let row = SubstanceColorStore.ensureRow(for: name, existing: colorRows, in: context) {
                colorRows.append(row)
            }
        }
    }
}

/// The usage ledger indexed for the join, each row handed out once so two
/// identical doses on one day pair with two rows.
private struct DrugsProLedger {
    private var rows: [String: [DrugsProUsage]] = [:]
    private var unitByName: [String: String] = [:]

    init(_ usage: [DrugsProUsage]) {
        for row in usage {
            guard let amount = row.amount else { continue }
            rows[Self.key(row.dateISO, row.name, amount), default: []].append(row)
            if let unit = row.unit {
                unitByName[row.name.lowercased()] = unitByName[row.name.lowercased()] ?? unit
            }
        }
    }

    mutating func take(day: Date, name: String, amount: Double) -> DrugsProUsage? {
        let key = Self.key(Self.isoDay(day), name, amount)
        guard var matches = rows[key], !matches.isEmpty else { return nil }
        let row = matches.removeFirst()
        rows[key] = matches
        return row
    }

    /// The unit DrugsPRO used for this substance anywhere in the file, for a
    /// dose with no ledger row of its own.
    func unit(for name: String) -> String? {
        unitByName[name.lowercased()]
    }

    private static func key(_ day: String, _ name: String, _ amount: Double) -> String {
        "\(day)|\(name.lowercased())|\(amount)"
    }

    static func day(_ iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func isoDay(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Minutes after midnight for `HH:mm`.
    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0 ..< 24).contains(parts[0]), (0 ..< 60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}
