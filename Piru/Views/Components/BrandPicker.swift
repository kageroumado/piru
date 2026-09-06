import SwiftUI

/// The QuickLog brand picker — a progressive pill for the branded-medication
/// audience. A person on the Methylphenidate row picks their real product
/// (Concerta, Ritalin LA) instead of a bare release code, and that sets
/// `productName` — the key every brand surface already reads: the product-duration
/// curve draws, the tablet-strength chips appear, and the title becomes the brand
/// with the molecule as its subtitle.
///
/// The menu is progressive, mirroring how a person narrows down: **Unbranded** (no
/// specific brand — draws the substance's own curve), then an **Immediate-release ▸**
/// group (Medikinet, Ritalin) and an **Extended-release ▸** group (Concerta,
/// Ritalin LA), each listing its flagship/curve brands with the niche ones tucked
/// under **More…**. Selecting a brand sets `productName` + `releaseForm` and clears
/// the isomer (every brand here is the racemic parent — the enantiomer axis,
/// Focalin, is its own picker and its own search).
///
/// It shows only when the substance has an extended-release brand — that is the
/// multi-formulation case worth surfacing; an immediate-release-only substance
/// stays a plain log and reaches any brand label by search. Brand names are proper
/// nouns and are not localized; "Unbranded", "Immediate-release",
/// "Extended-release", and "More…" are.
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

    /// Immediate-release / base brands (Medikinet, Ritalin, Equasym) — the ones a
    /// person on the plain form actually holds, grouped apart from the XR products.
    private var immediateReleaseBrands: [SubstanceStore.BrandProduct] {
        brands.filter { !$0.isExtendedRelease }
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
        return String(localized: "Unbranded", comment: "Brand picker: no specific brand — the plain substance")
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
        MenuPillLabel(
            systemImage: "pills",
            text: label,
            namespace: namespace,
            geometryID: id,
            height: height,
            accessibilityLabel: Text("Formulation"),
            accessibilityValue: label,
        ) {
            menuContent
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        Button {
            selectRegular()
        } label: {
            if currentBrand == nil {
                Label(String(localized: "Unbranded", comment: "Brand picker: no specific brand — the plain substance"), systemImage: "checkmark")
            } else {
                Text(String(localized: "Unbranded", comment: "Brand picker: no specific brand — the plain substance"))
            }
        }

        if !immediateReleaseBrands.isEmpty {
            brandGroup(
                String(localized: "Immediate-release", comment: "Brand picker: the immediate-release brand group"),
                immediateReleaseBrands,
            )
        }
        if !extendedReleaseBrands.isEmpty {
            brandGroup(
                String(localized: "Extended-release", comment: "Brand picker: the extended-release brand group"),
                extendedReleaseBrands,
            )
        }
    }

    /// One release-form submenu: the flagship brands, with the niche ones tucked
    /// under a nested "More…" so the common products lead.
    @ViewBuilder
    private func brandGroup(_ title: String, _ list: [SubstanceStore.BrandProduct]) -> some View {
        let flagship = list.filter(\.isFlagship)
        let niche = list.filter { !$0.isFlagship }
        Menu(title) {
            ForEach(flagship, id: \.name) { brand in
                brandButton(brand)
            }
            if !niche.isEmpty {
                Menu(String(localized: "More…", comment: "Brand picker: submenu of niche brands")) {
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
