import Foundation
import GRDB

/// A marketed product the bundled barcode registry knows — the row a scanned
/// GTIN resolves to, joined to the substance it is sold as. Everything but
/// `canonicalName`/`psid` is the registry's own string, shown as read.
nonisolated struct ProductCodeHit: Hashable {
    /// The 14-digit GTIN the lookup matched.
    let gtin14: String
    /// `"ndc"` | `"upc"` | `"cip13"` — which barcode family the key came from.
    let codeKind: String
    let canonicalName: String
    let psid: String?
    let brand: String?
    /// The registry's strength string — `"36 mg/1"` (openFDA), `"54 mg"` (BDPM).
    let strength: String?
    let form: String?
    let route: String?
    /// ISO country of the registry (`"US"`, `"FR"`).
    let country: String
    /// Registry slug (`"openfda-ndc"`, `"bdpm"`).
    let source: String
    let packCount: Double?
    let packUnit: String?

    /// The strength parsed the way the logging scanner parses a label line.
    @MainActor var parsedStrength: (amount: Double, unit: String)? {
        strength.flatMap(LabelMatcher.parseStrength)
    }
}

/// Barcode → product resolution over `product_codes` ⋈ `coded_products`.
/// Structured lookup, fails closed: one exact key hit or nothing — a barcode
/// never fuzzy-matches.
extension SubstanceReadModel {
    /// The product printed with `gtin14`, or `nil` when the registry has no row
    /// for it. `gtin14` must already be a normalized 14-digit key
    /// (``ProductCodeKey``); the table stores it as an integer.
    func productCode(gtin14: String) -> ProductCodeHit? {
        guard gtin14.count == 14, let code = Int64(gtin14) else { return nil }
        return try? db.read { db in
            try Row.fetchOne(db, sql: """
                SELECT pc.code_kind, pc.pack_count, pc.pack_unit,
                       cp.psid, cp.brand, cp.strength, cp.form, cp.route, cp.country, cp.source,
                       s.canonical_name
                  FROM product_codes pc
                  JOIN coded_products cp ON cp.id = pc.product_id
                  JOIN substances s ON s.id = cp.substance_id
                 WHERE pc.code = ?
                 LIMIT 1
                """, arguments: [code]).map { row in
                ProductCodeHit(
                    gtin14: gtin14,
                    codeKind: row["code_kind"],
                    canonicalName: row["canonical_name"],
                    psid: row["psid"],
                    brand: row["brand"],
                    strength: row["strength"],
                    form: row["form"],
                    route: row["route"],
                    country: row["country"],
                    source: row["source"],
                    packCount: row["pack_count"],
                    packUnit: row["pack_unit"],
                )
            }
        }
    }

    /// How many barcodes the bundled registry carries — zero for a database
    /// from before the table existed, which then resolves no barcodes locally.
    func productCodeCount() -> Int {
        (try? db.read { db in
            guard try db.tableExists("product_codes") else { return 0 }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM product_codes") ?? 0
        }) ?? 0
    }
}

extension SubstanceStore {
    /// Resolve a raw barcode payload (GS1 element string, EAN-13, UPC-A) to a
    /// registry product. Tries every GTIN key the payload could mean, best first.
    func productCode(forBarcode payload: String) -> ProductCodeHit? {
        let reader = reader
        for key in ProductCodeKey.candidates(forBarcode: payload) {
            if let hit = reader.productCode(gtin14: key) { return hit }
        }
        return nil
    }

    /// Resolve a package NDC printed as text (`NDC 50458-586-01`) to its product.
    func productCode(forNDCText text: String) -> ProductCodeHit? {
        guard let key = ProductCodeKey.gtin14(fromText: text) else { return nil }
        return reader.productCode(gtin14: key)
    }
}
