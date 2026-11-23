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
    /// The skin in front. The host owns it, so a grid beside the carousel can
    /// move the carousel too.
    @Binding var focused: Skin
    /// What "Use This Skin" does — the Skins sheet wears the skin and closes.
    /// `nil` leaves the button out: onboarding's Continue keeps whichever skin
    /// is showing.
    var use: ((Skin) -> Void)?
    /// The miniatures' width. Settings shows the picker in a short panel over
    /// the app itself, so its cards are small; onboarding has the whole screen.
    var cardWidth: CGFloat = 176

    var body: some View {
        VStack(spacing: Spacing.lg) {
            SkinCarousel(focused: $focused, cardWidth: cardWidth)
            SkinCaption(skin: focused)
            SkinDots(focused: $focused)
            SkinPrimaryAction(skin: focused, use: use)
                .padding(.horizontal, Spacing.xxxl)
        }
        .skinShopNotices()
    }
}

// MARK: - Carousel

/// Live miniatures of every skin on offer, paged so one sits in front and its
/// neighbors stand back.
private struct SkinCarousel: View {
    @Binding var focused: Skin
    let cardWidth: CGFloat
    @State private var position: Skin?
    @State private var containerWidth: CGFloat = 0

    private enum Metrics {
        static let spacing: CGFloat = 16
        /// How far a card that is not in front stands back.
        static let restingScale: CGFloat = 0.88
        static let restingOpacity: CGFloat = 0.7
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
                    .scrollTransition(.interactive, axis: .horizontal) { card, phase in
                        card
                            .scaleEffect(phase.isIdentity ? 1 : Metrics.restingScale)
                            .opacity(phase.isIdentity ? 1 : Metrics.restingOpacity)
                    }
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
        // The dots and the grid move `focused`; the carousel follows them.
        .onChange(of: focused) { _, skin in
            guard position != skin else { return }
            withAnimation(.snappy) { position = skin }
        }
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

/// The name, centered, and under it what the skin costs this person.
///
/// Each line sits in a slot of fixed height. The app is wearing the skin in
/// front, so these faces change as the carousel moves; with hugging heights
/// the whole picker would shift under the finger.
struct SkinCaption: View {
    let skin: Skin

    private enum Slots {
        static let name: CGFloat = 28
        static let status: CGFloat = 18
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(skin.displayName)
                .font(.piru(.title3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: Slots.name)
            SkinStatus(skin: skin)
                .frame(height: Slots.status)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xxxl)
        .accessibilityElement(children: .combine)
    }
}

/// What a skin costs this person: free, already theirs, or its price.
struct SkinStatus: View {
    let skin: Skin
    @State private var shop = SkinShop.shared

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.piruLabel(.footnote, weight: .semibold))
        }
        .foregroundStyle(Theme.accent)
        .lineLimit(1)
    }

    private var owned: Bool {
        skin.tier != .free && shop.owns(skin)
    }

    private var systemImage: String? {
        if skin.tier == .free { nil } else if owned { "checkmark.seal.fill" } else { "lock.fill" }
    }

    private var title: String {
        if skin.tier == .free {
            String(localized: "Free")
        } else if owned {
            String(localized: "Yours")
        } else {
            shop.product(for: skin)?.displayPrice ?? String(localized: "Paid")
        }
    }
}

// MARK: - Dots

/// One dot per skin, in that skin's own accent: where the carousel stands
/// among all of them, and a track to drag along to reach a far one.
private struct SkinDots: View {
    @Binding var focused: Skin
    @State private var width: CGFloat = 0

    private let skins = Skin.available

    private enum Metrics {
        static let dot: CGFloat = 8
        static let focusedScale: CGFloat = 1.75
        static let height: CGFloat = 28
        static let maxWidth: CGFloat = 320
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(skins) { skin in
                Circle()
                    .fill(skin.accentMark)
                    .overlay { Circle().strokeBorder(.primary.opacity(skin == focused ? 0.5 : 0.12), lineWidth: 1) }
                    .frame(width: Metrics.dot, height: Metrics.dot)
                    .scaleEffect(skin == focused ? Metrics.focusedScale : 1)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: Metrics.maxWidth)
        .frame(height: Metrics.height)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
                guard width > 0 else { return }
                let index = Int(drag.location.x / width * CGFloat(skins.count))
                let skin = skins[min(max(index, 0), skins.count - 1)]
                if skin != focused { focused = skin }
            },
        )
        .animation(.snappy, value: focused)
        .sensoryFeedback(.selection, trigger: focused)
        .accessibilityElement()
        .accessibilityLabel(Text("Skin"))
        .accessibilityValue(Text(focused.displayName))
        .accessibilityAdjustableAction { direction in
            guard let index = skins.firstIndex(of: focused) else { return }
            switch direction {
            case .increment: focused = skins[min(index + 1, skins.count - 1)]
            case .decrement: focused = skins[max(index - 1, 0)]
            @unknown default: break
            }
        }
    }
}

// MARK: - Actions

/// The one thing to do with the skin in front, in a slot of fixed height. The
/// skin being worn has nothing to do, and says so in place of a button.
struct SkinPrimaryAction: View {
    let skin: Skin
    let use: ((Skin) -> Void)?

    @State private var skins = SkinStore.shared
    @State private var shop = SkinShop.shared

    private static let height: CGFloat = 52

    var body: some View {
        ZStack { button }
            .frame(height: Self.height)
    }

    @ViewBuilder private var button: some View {
        if shop.owns(skin) {
            if let use {
                if skin == skins.chosen {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .accessibilityHidden(true)
                        Text("Wearing this skin")
                            .font(.piruLabel(.subheadline, weight: .semibold))
                    }
                    .foregroundStyle(Theme.secondaryLabel)
                } else {
                    GlassPillButton(title: "Use This Skin") { use(skin) }
                }
            }
        } else if let product = shop.product(for: skin) {
            GlassPillButton(title: "Unlock \(skin.displayName) · \(product.displayPrice)") {
                let skin = skin
                shop.buy(product) {
                    // Wear what was just bought, if it is still the one in front.
                    if shop.owns(skin), skins.tryingOn == skin { use?(skin) }
                }
            }
            .disabled(shop.activity != .idle)
        } else {
            GlassPillButton(title: "Paid", prominence: .neutral) {}
                .disabled(true)
        }
    }
}

/// Every skin at once, and Restore Purchases: the two things that are about the
/// shop rather than about the skin in front, stacked under onboarding's picker.
struct SkinShopOffers: View {
    var body: some View {
        SkinEverythingOffer()
        SkinRestoreButton()
    }
}

/// "Everything, Forever": the one purchase that covers every skin. To whoever
/// has bought it, the same row says it is theirs.
struct SkinEverythingOffer: View {
    @State private var shop = SkinShop.shared

    var body: some View {
        if shop.ownsEverything {
            row { Label("Yours", systemImage: "checkmark.seal.fill") }
        } else if let product = shop.everythingProduct {
            Button {
                shop.buy(product)
            } label: {
                row { Text(product.displayPrice) }
            }
            .disabled(shop.activity != .idle)
        }
    }

    private func row(@ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: Spacing.xl) {
            CaptionedRowLabel(
                title: "Everything, Forever",
                systemImage: "sparkles",
                caption: Text("Every skin there is and every skin still to come."),
            )
            Spacer(minLength: 0)
            trailing()
                .font(.piruLabel(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
    }
}

struct SkinRestoreButton: View {
    @State private var shop = SkinShop.shared

    var body: some View {
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
