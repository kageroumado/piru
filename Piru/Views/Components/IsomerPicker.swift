import SwiftUI

/// The stereoisomer picker — the sibling of ``SaltPicker`` for the second form
/// axis. Lets a person choose which resolved enantiomer (or the racemate) of a
/// substance a dose refers to: Ketamine → Ketamine / Esketamine / Arketamine,
/// Methylphenidate → Methylphenidate / Dexmethylphenidate (Focalin), Modafinil →
/// Modafinil / Armodafinil (Nuvigil).
///
/// Unlike salt, the options are **named** — each resolved enantiomer carries a
/// recognized display name, because an enantiomer is often its own INN-named drug
/// with distinct kinetics. The racemic/unspecified parent (`code == nil`) renders
/// as a generic "Regular" ("Racemic" at the Pharma Nerd tier) rather than
/// repeating the substance's own name, which is already on screen. Selecting one
/// swaps the visible dose ladder. Same two shared rules as the salt picker: render
/// nothing unless the route offers more than one option (see ``body``), and
/// reconcile the selection on a route change (see ``revalidate(_:against:)``).
///
/// Enantiomer names are chemical proper nouns and are **not** localized; the
/// "Isomer" title and the racemic "Regular"/"Racemic" label are.
struct IsomerPicker: View {
    /// A selectable form on the isomer axis. `code == nil` is the racemic /
    /// unspecified parent — the picker renders a generic label for it, not
    /// `displayName`; a non-nil code titles the option with `displayName`
    /// ("Esketamine").
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

    @State private var profileStore = UserProfileStore.shared

    /// Presentation surface — mirrors ``SaltPicker/Style``.
    enum Style {
        case menuPill(namespace: Namespace.ID, id: String, height: CGFloat)
        case formRow
    }

    private var current: Option? {
        options.first { $0.code == selection } ?? options.first
    }

    /// What to render for an option. The racemic parent's `displayName` is the
    /// substance's own name; showing it would repeat a name already on screen, so
    /// it renders a generic term instead — "Racemic" at the Pharma Nerd tier,
    /// "Regular" otherwise. Every other option keeps its enantiomer name.
    private func label(for option: Option) -> String {
        guard option.code == nil else { return option.displayName }
        return profileStore.disclosureTier == .pharmaNerd
            ? String(localized: "Racemic", comment: "Isomer picker: the racemic parent form (Pharma Nerd wording)")
            : String(localized: "Regular", comment: "Isomer picker: the racemic/unspecified parent form")
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
        // Decoupled + fixed-size like the tray's route pill: a `Menu` label is
        // sized by the UIKit menu button outside the SwiftUI transaction, so the
        // tray's expand/collapse `matchedGeometryEffect` interpolated a stale
        // frame and clipped the label. The Menu is an invisible overlay instead.
        HStack(spacing: 5) {
            Image(systemName: "circle.lefthalf.filled")
                .imageScale(.small)
            Text(current.map { label(for: $0) } ?? "")
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .font(.footnote.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 11)
        .frame(height: height)
        .background(Color(.secondarySystemFill), in: Capsule())
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
        .overlay {
            Menu {
                ForEach(options) { option in
                    Button {
                        selection = option.code
                    } label: {
                        if option.code == selection {
                            Label(label(for: option), systemImage: "checkmark")
                        } else {
                            Text(label(for: option))
                        }
                    }
                }
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .accessibilityLabel(Text("Isomer"))
            .accessibilityValue(current.map { label(for: $0) } ?? "")
        }
        .matchedGeometryEffect(id: id, in: namespace)
    }

    // MARK: Form row (entry forms + library detail)

    @ViewBuilder
    private var formRow: some View {
        let picker = Picker(String(localized: "Isomer"), selection: $selection) {
            ForEach(options) { option in
                Text(label(for: option)).tag(option.code)
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
    ///
    /// When the new route has **no** isomer axis at all, the selection is
    /// preserved rather than cleared: switching Focalin from oral (which offers a
    /// D ladder) to a route with none should keep the user's Dexmethylphenidate
    /// intent — no picker is shown there anyway — instead of silently reverting
    /// the dose to racemic and misclassifying it on the way back.
    static func revalidate(_ selection: inout String?, against options: [Option]) {
        guard !options.isEmpty else { return }
        if options.contains(where: { $0.code == selection }) { return }
        selection = options.first?.code
    }
}
