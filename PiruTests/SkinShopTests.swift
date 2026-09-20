import Foundation
import Testing
@testable import Piru

@MainActor
@Suite("Skin shop")
struct SkinShopTests {
    /// A throwaway suite per test so runs never see each other's state.
    private func freshDefaults() -> UserDefaults {
        let name = "test.skinshop.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeShop(_ defaults: UserDefaults) -> (shop: SkinShop, skins: SkinStore) {
        let skins = SkinStore(defaults: defaults)
        return (SkinShop(defaults: defaults, skins: skins), skins)
    }

    private var paidSkins: [Skin] {
        Skin.allCases.filter { $0.tier != .free }
    }

    // MARK: - Tiers

    @Test
    func `The plain skins and the two promo skins are free`() {
        for skin in [Skin.piru, .graphite, .linen, .slate, .elyPink, .doseWiki] {
            #expect(skin.tier == .free)
            #expect(skin.productID == nil)
        }
    }

    @Test
    func `A paid skin's product is named after it`() {
        #expect(Skin.jellyfish.productID == "dev.yumeji.piru.skin.jellyfish")
        #expect(!paidSkins.isEmpty)
    }

    // MARK: - Ownership

    @Test
    func `With nothing owned, free skins can be worn and paid ones cannot`() {
        let (shop, skins) = makeShop(freshDefaults())
        for skin in Skin.allCases {
            #expect(shop.owns(skin) == (skin.tier == .free))
        }
        skins.setSkin(.jellyfish)
        #expect(skins.current == SkinDefaults.skinDefault)
        skins.setSkin(.linen)
        #expect(skins.current == .linen)
    }

    @Test
    func `Owning one skin unlocks that skin alone`() throws {
        let (shop, skins) = makeShop(freshDefaults())
        try shop.setOwned([#require(Skin.jellyfish.productID)])
        #expect(shop.owns(.jellyfish))
        #expect(!shop.owns(.tsuki))
        skins.setSkin(.jellyfish)
        #expect(skins.current == .jellyfish)
    }

    /// Written over `allCases` so a skin added later is covered the day it lands:
    /// "everything, forever" has to keep meaning it.
    @Test
    func `Owning everything unlocks every skin there is`() {
        let (shop, _) = makeShop(freshDefaults())
        shop.setOwned([SkinProducts.everything])
        #expect(shop.ownsEverything)
        for skin in Skin.allCases {
            #expect(shop.owns(skin))
        }
    }

    @Test
    func `The owned set reaches the app group for the extensions`() throws {
        let defaults = freshDefaults()
        let (shop, _) = makeShop(defaults)
        let productID = try #require(Skin.kumo.productID)
        shop.setOwned([productID])
        #expect(SkinDefaults.ownedProducts(in: defaults) == [productID])
        #expect(SkinDefaults.usable(.kumo, in: defaults))
        #expect(makeShop(defaults).shop.owns(.kumo))
    }

    // MARK: - Refund and restore

    @Test
    func `A refunded skin falls back to the default and returns when restored`() throws {
        let defaults = freshDefaults()
        let (shop, skins) = makeShop(defaults)
        let productID = try #require(Skin.tsuki.productID)
        shop.setOwned([productID])
        skins.setSkin(.tsuki)

        shop.setOwned([])
        #expect(skins.current == SkinDefaults.skinDefault)
        #expect(SkinDefaults.storedSkin(in: defaults) == SkinDefaults.skinDefault)
        // The choice itself is kept, so restoring the purchase restores the skin.
        #expect(defaults.string(forKey: SkinDefaults.skinKey) == Skin.tsuki.rawValue)

        shop.setOwned([productID])
        #expect(skins.current == .tsuki)
    }

    // MARK: - Try-on

    @Test
    func `Trying a skin on dresses the app and never reaches the app group`() {
        let defaults = freshDefaults()
        let (_, skins) = makeShop(defaults)
        skins.tryOn(.jellyfish)
        #expect(skins.current == .jellyfish)
        #expect(skins.chosen == SkinDefaults.skinDefault)
        #expect(defaults.string(forKey: SkinDefaults.skinKey) == nil)
        #expect(SkinDefaults.storedSkin(in: defaults) == SkinDefaults.skinDefault)

        skins.tryOn(nil)
        #expect(skins.current == SkinDefaults.skinDefault)
    }

    @Test
    func `Settling keeps a skin that can be worn and drops one that cannot`() throws {
        let (shop, skins) = makeShop(freshDefaults())
        skins.tryOn(.jellyfish)
        skins.settleTryOn()
        #expect(skins.current == SkinDefaults.skinDefault)

        skins.tryOn(.linen)
        skins.settleTryOn()
        #expect(skins.chosen == .linen)

        try shop.setOwned([#require(Skin.jellyfish.productID)])
        skins.tryOn(.jellyfish)
        skins.settleTryOn()
        #expect(skins.chosen == .jellyfish)
        #expect(skins.tryingOn == nil)
    }

    @Test
    func `Onboarding offers skins last, just before it ends`() {
        #expect(OnboardingStep.skins.next == .done)
        #expect(OnboardingStep.progressSteps.last == .skins)
    }

    // MARK: - The StoreKit test catalog

    private struct Catalog: Decodable {
        struct Product: Decodable {
            let productID: String
            let type: String
        }

        let products: [Product]
    }

    /// Catches a mistyped identifier here, before App Store Connect does.
    @Test
    func `The StoreKit catalog sells exactly what the app asks for`() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "StoreKit/Skins.storekit")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        #expect(Set(catalog.products.map(\.productID)) == Set(SkinProducts.all))
        #expect(catalog.products.allSatisfy { $0.type == "NonConsumable" })
    }
}
