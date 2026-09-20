import SwiftUI

/// States CYP2D6's role on the detail page of a substance whose metabolism it leads.
///
/// The note distinguishes **prodrug** patterns (CYP2D6 creates an active metabolite — codeine,
/// tramadol) from **clearance** substrates (CYP2D6 eliminates the parent — MDMA, DXM,
/// atomoxetine), because the enzyme does opposite jobs in the two: it switches the first
/// kind on and the second kind off.
struct CYP2D6NoteSection: View {
    let substanceName: String
    let cyp2d6Info: CYP2D6Info

    var body: some View {
        Section {
            InfoBanner(
                icon: "arrow.triangle.branch",
                iconTint: .secondary,
                title: cyp2d6Info.hasProdrugPattern ? "Activated by CYP2D6" : "Cleared by CYP2D6",
            ) {
                Text(noteText)
                    .captionSecondary()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noteText: LocalizedStringResource {
        if cyp2d6Info.hasProdrugPattern {
            "CYP2D6 converts \(substanceName) into an active metabolite."
        } else {
            "CYP2D6 is the main enzyme clearing \(substanceName) from the body."
        }
    }
}
