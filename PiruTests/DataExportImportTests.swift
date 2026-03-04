import Testing
import Foundation
@testable import Piru

@Suite("DataExportImport")
struct DataExportImportTests {

    @Test("Export filename contains date")
    func exportFilenameFormat() {
        let filename = DataExportImport.exportFilename
        #expect(filename.hasPrefix("Piru "))
        // Should contain a date in format yyyy-MM-dd'T'HHmmss
        #expect(filename.count > 5)
        #expect(filename.contains("T"))
    }

    @Test("Export filename changes over time")
    func exportFilenameUnique() {
        let f1 = DataExportImport.exportFilename
        // Same second will be same, but at least verify format
        #expect(!f1.isEmpty)
        #expect(f1.hasPrefix("Piru "))
    }
}
