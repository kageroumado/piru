import SwiftUI

/// The salt / ester picker, shared across every surface that lets a person
/// choose which form of a multi-salt substance (Magnesium → Citrate /
/// Glycinate / L-Threonate…, Lithium → Carbonate / Orotate…) a dose refers to.
///
/// One source of truth for the two things every call site repeated: the
/// **visibility rule** (render nothing unless the route offers more than one
/// form) and the **revalidation rule** (when the route changes, keep the
/// selected salt if the new route still offers it, else fall to the route's
/// first form). See ``revalidate(_:against:)``.
///
/// Salt labels are chemical proper nouns (Citrate, Glycinate, Carbonate…) and
/// are **not** localized; the "Form" picker title *is* (`String(localized:
/// "Form")`).
struct SaltPicker: View {
    /// The forms offered by the current route, in display order. The first is
    /// the route's default. The picker renders nothing when this has ≤1 entry.
    let forms: [String]
    @Binding var selection: String?
    let style: Style

    /// Presentation surface.
    enum Style {
        /// A capsule menu pill matching the tray's route pill — used inside the
        /// quick-log staged-dose editor, where it morphs in place via a
        /// `matchedGeometryEffect`.
        case menuPill(namespace: Namespace.ID, id: String, height: CGFloat)

        /// A `Form`-row `Picker` titled "Form", segmented for a few forms and a
        /// menu past three (segmented labels truncate) — used in the entry
        /// add/edit forms and the library detail dose card.
        case formRow
    }

    var body: some View {
        if forms.count > 1 {
            switch style {
            case let .menuPill(namespace, id, height):
                menuPill(namespace: namespace, id: id, height: height)
            case .formRow:
                formRow
            }
        }
    }

    // MARK: Menu pill (tray)

    private func menuPill(namespace: Namespace.ID, id: String, height: CGFloat) -> some View {
        MenuPillLabel(
            systemImage: "atom",
            text: selection ?? forms.first ?? "",
            namespace: namespace,
            geometryID: id,
            height: height,
            accessibilityLabel: Text("Salt form"),
            accessibilityValue: selection ?? forms.first ?? "",
        ) {
            ForEach(forms, id: \.self) { form in
                Button {
                    selection = form
                } label: {
                    if form == selection {
                        Label(form, systemImage: "checkmark")
                    } else {
                        Text(form)
                    }
                }
            }
        }
    }

    // MARK: Form row (entry forms + library detail)

    @ViewBuilder
    private var formRow: some View {
        let picker = Picker(String(localized: "Form"), selection: $selection) {
            ForEach(forms, id: \.self) { form in
                Text(form).tag(String?.some(form))
            }
        }
        // Segmented reads best for a couple of forms; past three the labels
        // truncate, so fall back to a menu that keeps them full.
        if forms.count >= 4 {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: Revalidation

    /// Reconcile a salt selection against the forms a (possibly newly chosen)
    /// route offers: keep the current selection when the route still offers it,
    /// otherwise fall to that route's first form (or `nil` when the route has no
    /// salt dimension). Call this from every route-change handler.
    static func revalidate(_ selection: inout String?, against forms: [String]) {
        if let current = selection, forms.contains(current) { return }
        selection = forms.first
    }
}
