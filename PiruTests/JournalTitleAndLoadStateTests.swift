import Foundation
import Testing
@testable import Piru

struct SessionDateTitleTests {
    @Test
    func `An untitled session reads weekday, then day`() {
        let date = Date.now
        let expected = "\(date.formatted(.dateTime.weekday(.wide))), \(SessionDateTitle.day(date))"
        #expect(SessionDateTitle.full(date) == expected)
    }

    @Test
    func `The year shows only for another year`() throws {
        let now = Date.now
        let lastYear = try #require(Calendar.current.date(byAdding: .year, value: -1, to: now))
        let year = String(Calendar.current.component(.year, from: lastYear))
        #expect(SessionDateTitle.day(lastYear).contains(year))
        let thisYear = String(Calendar.current.component(.year, from: now))
        #expect(!SessionDateTitle.day(now).contains(thisYear))
    }

    @Test
    func `A journal day header three days back carries the shared day title`() throws {
        let day = try #require(Calendar.current.date(byAdding: .day, value: -3, to: .now))
        let start = Calendar.current.startOfDay(for: day).addingTimeInterval(12 * 3_600)
        let header = SessionDay(date: start, sessions: [])
        #expect(header.dateTitle == SessionDateTitle.day(start))
    }
}

@MainActor
struct JournalModelLoadStateTests {
    @Test
    func `The derived data is current only for the revision it was built from`() {
        let model = JournalModel()
        #expect(!model.hasDerivedOnce)
        #expect(!model.isDerived(atLogRevision: 0))
        model.markDerived(logRevision: 3)
        #expect(model.hasDerivedOnce)
        #expect(model.isDerived(atLogRevision: 3))
        #expect(!model.isDerived(atLogRevision: 4))
    }
}
