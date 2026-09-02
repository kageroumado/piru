import SwiftUI

/// A pharmacogenomic note shown on CYP2D6-dependent substance detail pages when the user has
/// set their CYP2D6 metabolizer status in Settings → Metabolism. Self-hides when the status
/// is `.unknown` or when the substance is not a CYP2D6-major substrate.
///
/// The note distinguishes **prodrug** patterns (CYP2D6 creates the active metabolite — codeine,
/// tramadol) from **clearance** substrates (CYP2D6 eliminates the parent — MDMA, DXM,
/// atomoxetine), because the clinical implications are reversed: a slow metabolizer gets less
/// effect from a prodrug but more exposure from a clearance substrate.
struct CYP2D6NoteSection: View {
    let substanceName: String
    let cyp2d6Info: CYP2D6Info
    @State private var profileStore = UserProfileStore.shared

    private var status: CYP2D6Status {
        profileStore.cyp2d6Status
    }

    var body: some View {
        if status != .unknown {
            Section {
                InfoBanner(
                    icon: "person.badge.clock.fill",
                    iconTint: .cautionAccent,
                    title: "CYP2D6: \(status.label)",
                ) {
                    Text(noteText)
                        .captionSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var noteText: LocalizedStringResource {
        if cyp2d6Info.hasProdrugPattern {
            prodrugNote
        } else {
            clearanceNote
        }
    }

    private var prodrugNote: LocalizedStringResource {
        switch status {
        case .slow:
            "Reduced conversion to active metabolite — you may get less effect from \(substanceName)."
        case .rapid:
            "Faster conversion to active metabolite — higher active metabolite exposure. For codeine, this is an FDA contraindication due to the risk of respiratory depression."
        case .unknown:
            "CYP2D6 is a major metabolic pathway for \(substanceName)."
        }
    }

    private var clearanceNote: LocalizedStringResource {
        switch status {
        case .slow:
            "Slower CYP2D6 clearance — \(substanceName) may last longer and accumulate at repeated doses."
        case .rapid:
            "Faster CYP2D6 clearance — shorter duration."
        case .unknown:
            "CYP2D6 is a major metabolic pathway for \(substanceName)."
        }
    }
}
