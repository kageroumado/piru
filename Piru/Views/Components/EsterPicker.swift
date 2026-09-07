import SwiftUI

/// The injectable-ester picker — Estradiol → Cypionate / Valerate / Enanthate
/// (and future hormone esters) — for a dose logged intramuscularly or
/// subcutaneously. A visual sibling of ``SaltPicker`` and ``BrandPicker`` (the
/// same tray menu pill), but sourced from the `ester_pk` table rather than the
/// salt-family dosing rows.
///
/// The chosen ester is stored on the dose's salt/ester axis (``StagedDose/saltForm``);
/// its label matches ``EsterPKRecord/label`` so the Injection Levels tool maps a
/// logged dose to its depot parameters. Two deliberate differences from
/// ``SaltPicker``: it shows even for a single ester (there is no route "default
/// ester" to fall back on), and it **never auto-picks** — an ester the user
/// didn't state stays unset, so the tool won't attribute a curve to a guess.
///
/// Ester names are chemical proper nouns and are not localized; the placeholder
/// and accessibility label are.
struct EsterPicker: View {
    /// The esters offered, in a stable order. Renders nothing when empty.
    let forms: [String]
    @Binding var selection: String?
    let style: Style

    /// Presentation surface, mirroring ``SaltPicker/Style``.
    enum Style {
        /// A capsule menu pill matching the tray's route pill — used inside the
        /// quick-log staged-dose editor.
        case menuPill(namespace: Namespace.ID, id: String, height: CGFloat)
        /// A `Form`-row menu `Picker` — used in the entry add/edit form.
        case formRow
    }

    private var placeholder: String {
        String(localized: "Ester")
    }

    var body: some View {
        if !forms.isEmpty {
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
            systemImage: "syringe",
            text: selection ?? placeholder,
            namespace: namespace,
            geometryID: id,
            height: height,
            accessibilityLabel: Text("Ester"),
            accessibilityValue: selection ?? placeholder,
        ) {
            menuItems
        }
    }

    @ViewBuilder
    private var menuItems: some View {
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
        if selection != nil {
            Divider()
            Button {
                selection = nil
            } label: {
                Label(String(localized: "No specific ester"), systemImage: "xmark")
            }
        }
    }

    // MARK: Form row (entry forms)

    private var formRow: some View {
        Picker(String(localized: "Ester"), selection: $selection) {
            Text(placeholder).tag(String?.none)
            ForEach(forms, id: \.self) { form in
                Text(form).tag(String?.some(form))
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: Revalidation

    /// Keep the selection if the new route still offers it, else clear it. Unlike
    /// ``SaltPicker/revalidate(_:against:)`` this never falls to the first form —
    /// an ester is never assumed, so an unstated one stays `nil`.
    static func revalidate(_ selection: inout String?, against forms: [String]) {
        if let current = selection, !forms.contains(current) { selection = nil }
    }
}
