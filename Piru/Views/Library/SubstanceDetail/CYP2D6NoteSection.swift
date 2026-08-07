import SwiftUI

/// A pharmacogenomic note shown on CYP2D6-dependent substance detail pages when the user has
/// set their CYP2D6 metabolizer status in Settings → Metabolism. Self-hides when the status
/// is `.unknown` or when the substance is not a CYP2D6-major substrate.
///
/// The note distinguishes **prodrug** patterns (CYP2D6 creates the active metabolite — codeine,
/// tramadol) from **clearance** substrates (CYP2D6 eliminates the parent — MDMA, DXM,
/// atomoxetine), because the clinical implications are reversed: a poor metabolizer gets less
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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.badge.clock.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CYP2D6: \(status.label)")
                            .font(.subheadline.weight(.semibold))
                        Text(noteText)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
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
        case .poor:
            "Reduced conversion to active metabolite — you may get less effect from \(substanceName)."
        case .intermediate:
            "Mildly reduced conversion to active metabolite — effect may be modestly lower."
        case .ultraRapid:
            "Faster conversion to active metabolite — higher active metabolite exposure. For codeine, this is an FDA contraindication due to the risk of respiratory depression."
        case .extensive, .unknown:
            "CYP2D6 is a major metabolic pathway for \(substanceName)."
        }
    }

    private var clearanceNote: LocalizedStringResource {
        switch status {
        case .poor:
            "Slower CYP2D6 clearance — \(substanceName) may last longer and accumulate at repeated doses."
        case .intermediate:
            "Mildly slower CYP2D6 clearance — duration may be modestly longer."
        case .ultraRapid:
            "Faster CYP2D6 clearance — shorter duration. Be aware of re-dose timing."
        case .extensive, .unknown:
            "CYP2D6 is a major metabolic pathway for \(substanceName)."
        }
    }
}
