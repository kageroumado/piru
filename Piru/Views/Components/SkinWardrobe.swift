import StoreKit
import SwiftUI

/// The skin picker: a carousel of live miniatures, and under it what can be
/// done with the skin in front.
///
/// Stopping on a skin **tries it on** — the whole app wears it, this screen
/// included — so a paid skin is seen on the person's own screens before it is
/// bought. A try-on is never persisted (``SkinStore/tryOn(_:)``); what ends it
/// is the host's business, because Settings drops it on the way out while
/// onboarding carries it to the last step.
struct SkinWardrobe: View {
    /// Settings offers "Use This Skin". Onboarding leaves it out: Continue
    /// keeps whichever skin is showing.
    var offersUse = true

    @State private var skins = SkinStore.shared
    @State private var shop = SkinShop.shared
    /// Seeded from the skin being worn, so the carousel comes back to the same
    /// card when `SkinnedRoot` re-creates the tree after a skin is chosen.
    @State private var focused: Skin = SkinStore.shared.current

    var body: some View {
        VStack(spacing: Spacing.xl) {
            SkinCarousel(focused: $focused)
            SkinCaption(skin: focused, owned: shop.owns(focused), price: shop.product(for: focused)?.displayPrice)
            SkinActions(skin: focused, offersUse: offersUse)
        }
        .alert(noticeTitle, isPresented: noticePresented) {
            Button("OK") { shop.notice = nil }
        } message: {
            Text(noticeMessage)
        }
    }

    private var noticePresented: Binding<Bool> {
        Binding(get: { shop.notice != nil }, set: { if !$0 { shop.notice = nil } })
    }

    private var noticeTitle: LocalizedStringResource {
        switch shop.notice {
        case .pending: "Waiting for Approval"
        case .nothingToRestore: "Nothing to Restore"
        case .failed, nil: "Purchase Not Completed"
        }
    }

    private var noticeMessage: LocalizedStringResource {
        switch shop.notice {
        case .pending: "The skin unlocks as soon as the purchase is approved."
        case .nothingToRestore: "This Apple Account has no Piru purchases."
        case .failed, nil: "Nothing was charged. You can try again."
        }
    }
}

// MARK: - Carousel

/// Live miniatures of every skin on offer, paged so one sits in front.
private struct SkinCarousel: View {
    @Binding var focused: Skin
    @State private var position: Skin?
    @State private var containerWidth: CGFloat = 0

    private enum Metrics {
        static let cardWidth: CGFloat = 176
        static let spacing: CGFloat = 16
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Metrics.spacing) {
                ForEach(Skin.available) { skin in
                    Button {
                        withAnimation(.snappy) { position = skin }
                    } label: {
                        SkinPreviewCard(skin: skin, animates: skin == focused, width: Metrics.cardWidth)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(skin == focused ? .isSelected : [])
                    .id(skin)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .contentMargins(.horizontal, max(0, (containerWidth - Metrics.cardWidth) / 2), for: .scrollContent)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { containerWidth = $0 }
        .onAppear { position = focused }
        // The app re-skins once the scroll comes to rest, never while cards
        // are sliding past: a try-on re-renders every skinned view on screen.
        .onScrollPhaseChange { _, phase in
            guard phase == .idle, let position else { return }
            focused = position
            SkinStore.shared.tryOn(position)
        }
    }
}

// MARK: - Caption

/// Name, tagline, and what the skin costs or that it is already owned.
private struct SkinCaption: View {
    let skin: Skin
    let owned: Bool
    let price: String?

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(skin.displayName)
                .font(.piru(.title3))
            Text(skin.tagline)
                .captionSecondary()
                .multilineTextAlignment(.center)
            status
                .font(.piruLabel(.footnote, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
    }

    @ViewBuilder private var status: some View {
        if skin.tier == .free {
            Text("Free")
        } else if owned {
            Label("Yours", systemImage: "checkmark.seal.fill")
        } else if let price {
            Label(price, systemImage: "lock.fill")
        } else {
            Label("Paid", systemImage: "lock.fill")
        }
    }
}

// MARK: - Actions

/// What can be done with the skin in front, the everything unlock, and Restore.
private struct SkinActions: View {
    let skin: Skin
    let offersUse: Bool

    @State private var skins = SkinStore.shared
    @State private var shop = SkinShop.shared

    var body: some View {
        VStack(spacing: Spacing.md) {
            primary
            if !shop.ownsEverything {
                everything
            }
            Button("Restore Purchases") {
                Task(name: "Restore skins") { await shop.restore() }
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryLabel)
            .disabled(shop.activity != .idle)
        }
        .padding(.horizontal, Spacing.lg)
    }

    @ViewBuilder private var primary: some View {
        if shop.owns(skin) {
            if offersUse {
                if skin == skins.chosen {
                    Label("Wearing This Skin", systemImage: "checkmark")
                        .font(.piru(.headline))
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(minHeight: 44)
                } else {
                    GlassPillButton(title: "Use This Skin") { skins.setSkin(skin) }
                }
            }
        } else if let product = shop.product(for: skin) {
            GlassPillButton(title: "Unlock \(skin.displayName) · \(product.displayPrice)") {
                buy(product)
            }
            .disabled(shop.activity != .idle)
        }
    }

    @ViewBuilder private var everything: some View {
        if let product = shop.everythingProduct {
            VStack(spacing: Spacing.xs) {
                GlassPillButton(title: "Everything, Forever · \(product.displayPrice)", prominence: .neutral) {
                    buy(product)
                }
                .disabled(shop.activity != .idle)
                Text("Every skin there is and every skin still to come.")
                    .captionSecondary()
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// Buys, then wears the skin in front if the purchase made it wearable —
    /// which covers both its own product and the everything unlock.
    private func buy(_ product: Product) {
        let skin = skin
        Task(name: "Buy skin") {
            await shop.purchase(product)
            if offersUse, shop.owns(skin), skins.tryingOn == skin { skins.setSkin(skin) }
        }
    }
}
