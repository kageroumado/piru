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
    /// The miniatures' width. Settings shows the picker in a short panel over
    /// the app itself, so its cards are small; onboarding has the whole screen.
    var cardWidth: CGFloat = 176

    @State private var shop = SkinShop.shared
    /// Seeded from the skin being worn, so the carousel comes back to the same
    /// card when `SkinnedRoot` re-creates the tree after a skin is chosen.
    @State private var focused: Skin = SkinStore.shared.current

    var body: some View {
        VStack(spacing: Spacing.lg) {
            SkinCarousel(focused: $focused, cardWidth: cardWidth)
            SkinCaption(skin: focused, owned: shop.owns(focused), price: shop.product(for: focused)?.displayPrice)
            SkinPrimaryAction(skin: focused, offersUse: offersUse)
                .padding(.horizontal, Spacing.xxxl)
        }
        .skinShopNotices()
    }
}

// MARK: - Carousel

/// Live miniatures of every skin on offer, paged so one sits in front.
private struct SkinCarousel: View {
    @Binding var focused: Skin
    let cardWidth: CGFloat
    @State private var position: Skin?
    @State private var containerWidth: CGFloat = 0

    private enum Metrics {
        static let spacing: CGFloat = 16
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Metrics.spacing) {
                ForEach(Skin.available) { skin in
                    Button {
                        withAnimation(.snappy) { position = skin }
                    } label: {
                        SkinPreviewCard(skin: skin, animates: skin == focused, width: cardWidth)
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
        .contentMargins(.horizontal, max(0, (containerWidth - cardWidth) / 2), for: .scrollContent)
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

/// Two lines: the name with what it costs beside it, and the tagline.
///
/// Each line sits in a slot of fixed height. The app is wearing the skin in
/// front, so these faces change as the carousel moves; with hugging heights
/// the whole picker would shift under the finger.
private struct SkinCaption: View {
    let skin: Skin
    let owned: Bool
    let price: String?

    private enum Slots {
        static let name: CGFloat = 28
        static let tagline: CGFloat = 18
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                Text(skin.displayName)
                    .font(.piru(.title3))
                status
                    .font(.piruLabel(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(height: Slots.name)
            Text(skin.tagline)
                .captionSecondary()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: Slots.tagline)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xxxl)
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

/// The one thing to do with the skin in front. Always a button, in a slot of
/// fixed height: the skin being worn gets a switched-off one rather than a gap.
private struct SkinPrimaryAction: View {
    let skin: Skin
    let offersUse: Bool

    @State private var skins = SkinStore.shared
    @State private var shop = SkinShop.shared

    private static let height: CGFloat = 52

    var body: some View {
        ZStack { button }
            .frame(height: Self.height)
    }

    @ViewBuilder private var button: some View {
        if shop.owns(skin) {
            if !offersUse {
                EmptyView()
            } else if skin == skins.chosen {
                GlassPillButton(title: "Wearing This Skin", prominence: .neutral) {}
                    .disabled(true)
            } else {
                GlassPillButton(title: "Use This Skin") { skins.setSkin(skin) }
            }
        } else if let product = shop.product(for: skin) {
            GlassPillButton(title: "Unlock \(skin.displayName) · \(product.displayPrice)") {
                shop.buy(product, thenWear: offersUse ? skin : nil)
            }
            .disabled(shop.activity != .idle)
        } else {
            GlassPillButton(title: "Paid", prominence: .neutral) {}
                .disabled(true)
        }
    }
}

/// Every skin at once, and Restore Purchases: the two things that are about the
/// shop rather than about the skin in front. Rows for a `List` in Settings,
/// stacked under the picker in onboarding.
struct SkinShopOffers: View {
    @State private var shop = SkinShop.shared

    var body: some View {
        if !shop.ownsEverything, let product = shop.everythingProduct {
            Button {
                shop.buy(product, thenWear: nil)
            } label: {
                HStack(spacing: Spacing.xl) {
                    CaptionedRowLabel(
                        title: "Everything, Forever",
                        systemImage: "sparkles",
                        caption: Text("Every skin there is and every skin still to come."),
                    )
                    Spacer(minLength: 0)
                    Text(product.displayPrice)
                        .font(.piruLabel(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .disabled(shop.activity != .idle)
        }
        Button {
            Task(name: "Restore skins") { await shop.restore() }
        } label: {
            Label("Restore Purchases", systemImage: "arrow.clockwise")
        }
        .disabled(shop.activity != .idle)
    }
}

// MARK: - Notices

extension View {
    /// The alert for a purchase that is pending, failed, or found nothing to
    /// restore. One per screen that can start a purchase.
    func skinShopNotices() -> some View {
        modifier(SkinShopNotices())
    }
}

private struct SkinShopNotices: ViewModifier {
    @State private var shop = SkinShop.shared

    func body(content: Content) -> some View {
        content.alert(title, isPresented: presented) {
            Button("OK") { shop.notice = nil }
        } message: {
            Text(message)
        }
    }

    private var presented: Binding<Bool> {
        Binding(get: { shop.notice != nil }, set: { if !$0 { shop.notice = nil } })
    }

    private var title: LocalizedStringResource {
        switch shop.notice {
        case .pending: "Waiting for Approval"
        case .nothingToRestore: "Nothing to Restore"
        case .failed, nil: "Purchase Not Completed"
        }
    }

    private var message: LocalizedStringResource {
        switch shop.notice {
        case .pending: "The skin unlocks as soon as the purchase is approved."
        case .nothingToRestore: "This Apple Account has no Piru purchases."
        case .failed, nil: "Nothing was charged. You can try again."
        }
    }
}
