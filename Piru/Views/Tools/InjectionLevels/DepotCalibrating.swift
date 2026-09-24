import Observation

/// The calibration surface the shared depot-calibration controls bind to
/// (`CalibrationControl`, `ReferenceLinesEditor`). Both the prediction Tool's
/// ``InjectionLevelsModel`` and the retrospective ``HormoneLevelsModel`` conform, so
/// one implementation of the personal-multiplier knob, the lab-driven state, and the
/// user's reference lines serves both (Specs/injection-levels-v3.md §2).
@MainActor
protocol DepotCalibrating: AnyObject, Observable {
    var hasLabs: Bool { get }
    var isLabDriven: Bool { get }
    var autoCalibrateFromLabs: Bool { get set }
    var fitRates: Bool { get set }
    var personalMultiplier: Double { get set }
    /// The amplitude multiplier in effect — the lab-fit scale when lab-driven, else
    /// the hand-set personal multiplier.
    var effectiveMultiplier: Double { get }
    var calibration: DepotCalibration.Result? { get }
    /// How many lab points feed the fit — gates the "fit shape too" toggle.
    var calibrationMeasurementCount: Int { get }
    var referenceLow: Double? { get set }
    var referenceHigh: Double? { get set }
}
