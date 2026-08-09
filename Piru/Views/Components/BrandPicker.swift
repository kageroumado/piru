import SwiftUI

/// The QuickLog brand picker — a progressive pill for the branded-medication
/// audience. A person on the Methylphenidate row picks their real product
/// (Concerta, Ritalin LA) instead of a bare release code, and that sets
/// `productName` — the key every brand surface already reads: the product-duration
/// curve draws, the tablet-strength chips appear, and the title becomes the brand
/// with the molecule as its subtitle.
///
/// The menu is progressive, mirroring how a person narrows down: **Regular** (the
/// base immediate-release form, which draws the substance's own curve) or
/// **Extended-release ▸**, whose submenu lists the flagship/curve brands with the
/// niche ones tucked under **More…**. Selecting a brand sets `productName` +
/// `releaseForm` and clears the isomer (every brand here is the racemic parent —
/// the enantiomer axis, Focalin, is its own picker and its own search).
///
/// It shows only when the substance has an extended-release brand — that is the
/// choice worth surfacing; an immediate-release-only substance stays a plain log
/// and reaches any brand label by search. Brand names are proper nouns and are not
/// localized; "Regular", "Extended-release", and "More…" are.
struct BrandPicker: View {
    /// The substance's branded products, flagships first (see ``SubstanceStore/brandProducts(forUID:)``).
    let brands: [SubstanceStore.BrandProduct]
    /// The user's chosen product ("Concerta"), matching `DoseEntry.productName`.
    @Binding var productName: String?
    /// The release facet the chosen brand names, matching `DoseEntry.releaseForm`.
    @Binding var releaseForm: String?
    /// Cleared to the racemic parent (`nil`) whenever a brand is chosen — brands
    /// never name an enantiomer.
    @Binding var isomer: String?
    let style: Style

    /// Presentation surface — mirrors ``IsomerPicker/Style``. Only the tray pill is
    /// used.
    enum Style {
        case menuPill(namespace: Namespace.ID, id: String, height: CGFloat)
    }

    private var extendedReleaseBrands: [SubstanceStore.BrandProduct] {
        brands.filter(\.isExtendedRelease)
    }

    /// The brand the current `productName` names, if it is one of this substance's
    /// listed products; `nil` for the base form or a product not in the list (a
    /// niche brand reached by search still shows its own name via ``label``).
    private var currentBrand: SubstanceStore.BrandProduct? {
        guard let productName else { return nil }
        return brands.first { $0.name.caseInsensitiveCompare(productName) == .orderedSame }
    }

    /// The pill's collapsed label: the chosen brand if any (even one not in the
    /// menu, so a searched niche brand still reads correctly), else the base form.
    private var label: String {
        if let productName, !productName.isEmpty { return productName }
        return String(localized: "Regular", comment: "Brand picker: the base immediate-release form")
    }

    private func isSelected(_ brand: SubstanceStore.BrandProduct) -> Bool {
        currentBrand?.name.caseInsensitiveCompare(brand.name) == .orderedSame
    }

    private func select(_ brand: SubstanceStore.BrandProduct) {
        productName = brand.name
        releaseForm = brand.releaseForm
        isomer = nil
    }

    private func selectRegular() {
        productName = nil
        releaseForm = nil
        isomer = nil
    }

    var body: some View {
        if !extendedReleaseBrands.isEmpty {
            switch style {
            case let .menuPill(namespace, id, height):
                menuPill(namespace: namespace, id: id, height: height)
            }
        }
    }

    // MARK: Menu pill (tray)

    private func menuPill(namespace: Namespace.ID, id: String, height: CGFloat) -> some View {
        // Decoupled + fixed-size like the tray's other pills: a `Menu` label is
        // sized by the UIKit menu button outside the SwiftUI transaction, so the
        // tray's expand/collapse `matchedGeometryEffect` interpolated a stale frame
        // and clipped the label. The Menu is an invisible overlay instead.
        HStack(spacing: 5) {
            Image(systemName: "pills")
                .imageScale(.small)
            Text(label)
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
                menuContent
            } label: {
                Color.clear.contentShape(Capsule())
            }
            .accessibilityLabel(Text("Formulation"))
            .accessibilityValue(label)
        }
        .matchedGeometryEffect(id: id, in: namespace)
    }

    @ViewBuilder
    private var menuContent: some View {
        Button {
            selectRegular()
        } label: {
            if currentBrand == nil {
                Label(String(localized: "Regular", comment: "Brand picker: the base immediate-release form"), systemImage: "checkmark")
            } else {
                Text(String(localized: "Regular", comment: "Brand picker: the base immediate-release form"))
            }
        }

        let flagship = extendedReleaseBrands.filter(\.isFlagship)
        let niche = extendedReleaseBrands.filter { !$0.isFlagship }
        Menu(String(localized: "Extended-release", comment: "Brand picker: the extended-release brand group")) {
            ForEach(flagship, id: \.name) { brand in
                brandButton(brand)
            }
            if !niche.isEmpty {
                Menu(String(localized: "More…", comment: "Brand picker: submenu of niche extended-release brands")) {
                    ForEach(niche, id: \.name) { brand in
                        brandButton(brand)
                    }
                }
            }
        }
    }

    private func brandButton(_ brand: SubstanceStore.BrandProduct) -> some View {
        Button {
            select(brand)
        } label: {
            if isSelected(brand) {
                Label(brand.name, systemImage: "checkmark")
            } else {
                Text(brand.name)
            }
        }
    }
}
