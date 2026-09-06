import Foundation
import SwiftData

/// One serum lab result the user enters to calibrate the Injection Levels tool to
/// their own body (Specs/injection-levels-tool.md §3).
///
/// The population depot model gives a wide starting band; each measurement pins the
/// model's amplitude to *this user's* levels, narrowing it. Stored in the analyte's
/// **canonical unit** (pg/mL for estradiol, ng/dL for testosterone); ``inputUnit``
/// records what the user actually typed so the entry can be shown back in their unit.
///
/// All properties are defaulted so the model migrates in additively (no version
/// ladder — see `StoreRecovery`). This is user data the app reads back, so it lives
/// in SwiftData, not the bundled substance DB.
@Model
final class LabMeasurement {
    var id: UUID = UUID()
    /// Blood-draw time.
    var date: Date = Date()
    /// Which analyte this measures: `"estradiol"` or `"testosterone"`.
    var analyteKey: String = "estradiol"
    /// The measured level in the analyte's canonical unit (pg/mL for estradiol,
    /// ng/dL for testosterone).
    var value: Double = 0
    /// The unit the user typed: `"pg/mL"`, `"pmol/L"`, `"ng/dL"`, or `"nmol/L"`.
    var inputUnit: String = "pg/mL"
    /// Which ester this calibrates (`ester_pk.ester_id`), or `nil` for a generic
    /// measurement not tied to one ester.
    var esterID: String?
    /// User- or auto-flagged to drop this point from the calibration fit.
    var excludedFromCalibration: Bool = false
    @Attribute(.externalStorage) var note: String?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        analyteKey: String = "estradiol",
        value: Double = 0,
        inputUnit: String = "pg/mL",
        esterID: String? = nil,
        excludedFromCalibration: Bool = false,
        note: String? = nil,
        createdAt: Date = Date(),
    ) {
        self.id = id
        self.date = date
        self.analyteKey = analyteKey
        self.value = value
        self.inputUnit = inputUnit
        self.esterID = esterID
        self.excludedFromCalibration = excludedFromCalibration
        self.note = note
        self.createdAt = createdAt
    }
}
