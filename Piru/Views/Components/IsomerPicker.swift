import SwiftUI

/// The stereoisomer picker — the sibling of ``SaltPicker`` for the second form
/// axis. Lets a person choose which resolved enantiomer (or the racemate) of a
/// substance a dose refers to: Ketamine → Ketamine / Esketamine / Arketamine,
/// Methylphenidate → Methylphenidate / Dexmethylphenidate (Focalin), Modafinil →
/// Modafinil / Armodafinil (Nuvigil).
///
/// Unlike salt, the options are **named** — each carries a recognized display
/// name (a `code` of `nil` is the racemic parent, titled with the substance's own
/// name), because an enantiomer is often its own INN-named drug with distinct
/// kinetics. Selecting one swaps the visible dose ladder. Same two shared rules as
/// the salt picker: render nothing unless the route offers more than one option
/// (see ``body``), and reconcile the selection on a route change (see
/// ``revalidate(_:against:)``).
///
/// Isomer names are chemical proper nouns and are **not** localized; only the
/// "Isomer" picker title is.
struct IsomerPicker: View {
    /// A selectable form on the isomer axis. `code == nil` is the racemic /
    /// unspecified parent; `displayName` is what titles the option ("Esketamine").
    struct Option: Identifiable, Hashable {
        let code: String?
        let displayName: String
        var id: String {
            code ?? ""
        }
    }

    /// The options offered by the current route, racemic first. The picker renders
    /// nothing when this has ≤1 entry.
    let options: [Option]
    /// The selected isomer *code* (`nil` = racemic), matching `DoseEntry.isomer`.
    @Binding var selection: String?
    let style: Style

    /// Presentation surface — mirrors ``SaltPicker/Style``.
    enum Style {
        case menuPill(namespace: Namespace.ID, id: String, height: CGFloat)
        case formRow
    }

    private var current: Option? {
        options.first { $0.code == selection } ?? options.first
    }

    var body: some View {
        if options.count > 1 {
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
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.code
                } label: {
                    if option.code == selection {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "circle.lefthalf.filled")
                    .imageScale(.small)
                Text(current?.displayName ?? "")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: id, in: namespace)
        .accessibilityLabel(Text("Isomer"))
        .accessibilityValue(current?.displayName ?? "")
    }

    // MARK: Form row (entry forms + library detail)

    @ViewBuilder
    private var formRow: some View {
        let picker = Picker(String(localized: "Isomer"), selection: $selection) {
            ForEach(options) { option in
                Text(option.displayName).tag(option.code)
            }
        }
        // Segmented reads best for a couple of options; past three the labels
        // truncate, so fall back to a menu that keeps them full.
        if options.count >= 4 {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: Revalidation

    /// Reconcile an isomer selection against the options a (possibly newly chosen)
    /// route offers: keep the current selection when the route still offers that
    /// code, otherwise fall to the racemic form (or the first option). Call this
    /// from every route-change handler, mirroring ``SaltPicker/revalidate(_:against:)``.
    static func revalidate(_ selection: inout String?, against options: [Option]) {
        if options.contains(where: { $0.code == selection }) { return }
        selection = options.first?.code
    }
}
