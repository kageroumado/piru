import SwiftUI

/// What the options menu shows **below** the always-on combined recovery chart: per-mechanism **cards**
/// or per-substance **rows**. The combined chart shows in both; this only switches the detail.
enum ToleranceDetailMode: CaseIterable, Identifiable {
    case perReceptor
    case perSubstance

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .perReceptor: "By mechanism"
        case .perSubstance: "By substance"
        }
    }
}
