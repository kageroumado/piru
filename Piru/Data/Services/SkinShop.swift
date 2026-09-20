import Foundation
import Observation
import os
import StoreKit
import WidgetKit

/// What this person owns from the App Store, and the way to buy more.
///
/// Every feature of Piru is free. Skins are the one thing sold, as a way to
/// support the project, so this store gates nothing but which skins
/// ``SkinStore`` will wear. Ownership is read from StoreKit's on-device verified
/// entitlements — there is no server and no receipt leaves the device — and
/// mirrored into the app group so the widget and Live Activity, which have no
/// StoreKit, resolve the same skin through ``SkinDefaults/usable(_:in:)``.
@Observable
@MainActor
final class SkinShop {
    static let shared = SkinShop(
        defaults: UserDefaults(suiteName: SkinDefaults.suite) ?? .standard,
        skins: .shared,
    )

    enum Activity: Equatable {
        case idle
        case purchasing(productID: String)
        case restoring
    }

    /// The outcome of the last purchase or restore that the UI has to say
    /// something about. A cancelled sheet is not one of them.
    enum Notice: Equatable {
        /// Ask to Buy, or a bank's confirmation: the purchase will arrive
        /// through `Transaction.updates` if it is approved.
        case pending
        case failed
        case nothingToRestore
    }

    /// Loaded products by identifier; empty until the App Store answers.
    private(set) var products: [String: Product] = [:]
    private(set) var owned: Set<String>
    private(set) var activity: Activity = .idle
    var notice: Notice?

    private let defaults: UserDefaults
    private let skins: SkinStore
    private var updates: Task<Void, Never>?
    private static let log = Logger(subsystem: "dev.yumeji.piru", category: "SkinShop")

    init(defaults: UserDefaults, skins: SkinStore) {
        self.defaults = defaults
        self.skins = skins
        owned = SkinDefaults.ownedProducts(in: defaults)
    }

    // MARK: - Ownership

    func owns(_ skin: Skin) -> Bool {
        SkinDefaults.usable(skin, owned: owned)
    }

    var ownsEverything: Bool {
        owned.contains(SkinProducts.everything)
    }

    /// The product that unlocks `skin` alone, once loaded.
    func product(for skin: Skin) -> Product? {
        skin.productID.flatMap { products[$0] }
    }

    var everythingProduct: Product? {
        products[SkinProducts.everything]
    }

    /// Replaces the owned set, mirrors it for the extensions, and lets
    /// ``SkinStore`` re-resolve the skin it is wearing.
    func setOwned(_ productIDs: Set<String>) {
        guard productIDs != owned else { return }
        owned = productIDs
        defaults.set(productIDs.sorted(), forKey: SkinDefaults.ownedProductsKey)
        skins.ownershipChanged()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Lifecycle

    /// Call once at launch. Listens for transactions that arrive outside a
    /// purchase call (Ask to Buy approvals, refunds, another device), then
    /// reads the current entitlements and the catalog.
    func start() {
        guard updates == nil else { return }
        updates = Task(name: "Skin transactions") { [weak self] in
            for await update in Transaction.updates {
                if case let .verified(transaction) = update { await transaction.finish() }
                await self?.refreshOwned()
            }
        }
        Task(name: "Skin catalog") {
            await refreshOwned()
            await loadProducts()
        }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: SkinProducts.all)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            Self.log.error("Product request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshOwned() async {
        var current: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            guard case let .verified(transaction) = entitlement, transaction.revocationDate == nil else { continue }
            current.insert(transaction.productID)
        }
        #if DEBUG
            // `-piruOwnEverything` wears any skin without a purchase, for
            // screenshots and for looking at a paid skin on a device.
            if ProcessInfo.processInfo.arguments.contains("-piruOwnEverything") {
                current.insert(SkinProducts.everything)
            }
        #endif
        setOwned(current)
    }

    // MARK: - Buying

    func purchase(_ product: Product) async {
        guard activity == .idle else { return }
        activity = .purchasing(productID: product.id)
        defer { activity = .idle }
        do {
            switch try await product.purchase() {
            case let .success(.verified(transaction)):
                await transaction.finish()
                await refreshOwned()
            case .success(.unverified):
                notice = .failed
            case .pending:
                notice = .pending
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            Self.log.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            notice = .failed
        }
    }

    /// Restore Purchases. `AppStore.sync()` asks for the Apple Account password,
    /// so it runs only from the button and never at launch.
    func restore() async {
        guard activity == .idle else { return }
        activity = .restoring
        defer { activity = .idle }
        do {
            try await AppStore.sync()
            await refreshOwned()
            if owned.isEmpty { notice = .nothingToRestore }
        } catch {
            // Dismissing the sign-in sheet throws; that is a cancel, not a failure.
            if case StoreKitError.userCancelled = error { return }
            Self.log.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            notice = .failed
        }
    }
}
