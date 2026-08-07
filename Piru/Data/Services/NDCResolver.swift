import Foundation
import OSLog

/// A drug product as returned by openFDA — the raw label facts, before they are
/// resolved to a Piru `Substance`. `LabelMatcher` turns the name into a substance.
struct NDCProduct: Equatable {
    var genericName: String?
    var brandName: String?
    /// The first active ingredient's strength as printed, e.g. `"36 mg/1"`.
    var strengthText: String?
    var dosageForm: String?
    /// openFDA route names, e.g. `["ORAL"]`.
    var routes: [String]

    var displayName: String? {
        genericName ?? brandName
    }
}

/// GTIN → NDC arithmetic. US drug barcodes embed the National Drug Code inside a
/// GTIN-14 (or a UPC-A that widens to one): the layout is
/// `[indicator][0][3][NDC-10][check]`, so stripping the indicator, the `03` drug
/// prefix, and the trailing check digit leaves the 10-digit NDC.
enum NDC {
    /// Extract the 10-digit NDC from a GTIN-14 or a 12-digit UPC-A. Returns `nil`
    /// for a payload that is not a US drug code (wrong length, or not `03`-prefixed).
    static func ndc10(from code: String) -> String? {
        let digits = code.filter(\.isNumber)
        switch digits.count {
        case 14:
            // 00 3 <NDC-10> <check>  →  the "3" (drug system) sits at index 2.
            let arr = Array(digits)
            guard arr[1] == "0", arr[2] == "3" else { return nil }
            return String(arr[3 ..< 13])
        case 12:
            // UPC-A: [3]<NDC-10><check>. Number-system digit "3" flags a drug.
            let arr = Array(digits)
            guard arr[0] == "3" else { return nil }
            return String(arr[1 ..< 11])
        default:
            return nil
        }
    }

    /// The `labeler-product` NDC forms openFDA's `product_ndc` field can take,
    /// derived from a 10-digit packaged NDC. The package code (last 1–2 digits)
    /// isn't self-delimiting, so all three standard configurations are offered as
    /// candidates for an OR query: 5-4-1, 5-3-2, and 4-4-2.
    static func productNDCCandidates(fromNDC10 ndc10: String) -> [String] {
        let d = Array(ndc10)
        guard d.count == 10 else { return [] }
        func slice(_ r: Range<Int>) -> String {
            String(d[r])
        }
        return [
            "\(slice(0 ..< 5))-\(slice(5 ..< 9))", // 5-4-1
            "\(slice(0 ..< 5))-\(slice(5 ..< 8))", // 5-3-2
            "\(slice(0 ..< 4))-\(slice(4 ..< 8))", // 4-4-2
        ]
    }
}

/// Minimal, single-purpose openFDA client. One endpoint per barcode shape, no API
/// key (unauthenticated is rate-limited to 240/min/IP — ample for single scans).
struct NDCResolver {
    private static let logger = Logger(subsystem: "dev.yumeji.piru", category: "NDCResolver")

    /// Resolve a GTIN (from a GS1 DataMatrix `01` AI) to a product via the NDC
    /// directory endpoint. Returns `nil` on any failure — the caller falls through
    /// to OCR.
    func lookup(gtin: String) async -> NDCProduct? {
        guard let ndc10 = NDC.ndc10(from: gtin) else { return nil }
        let candidates = NDC.productNDCCandidates(fromNDC10: ndc10)
        guard !candidates.isEmpty else { return nil }

        let search = candidates.map { "product_ndc:\"\($0)\"" }.joined(separator: " OR ")
        var components = URLComponents(string: "https://api.fda.gov/drug/ndc.json")
        components?.queryItems = [
            URLQueryItem(name: "search", value: search),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else { return nil }

        guard let result = await fetch(OpenFDANDCResponse.self, from: url)?.results?.first else { return nil }
        return NDCProduct(
            genericName: result.generic_name?.trimmed,
            brandName: result.brand_name?.trimmed,
            strengthText: result.active_ingredients?.first?.strength?.trimmed,
            dosageForm: result.dosage_form?.trimmed,
            routes: result.route ?? [],
        )
    }

    /// Resolve a raw 12-digit UPC-A via the label endpoint's `openfda.upc` field —
    /// no NDC surgery needed. Strength isn't reliably structured here, so it is
    /// left to the OCR strength parse.
    func lookup(upc: String) async -> NDCProduct? {
        let digits = upc.filter(\.isNumber)
        guard digits.count == 12 else { return nil }
        var components = URLComponents(string: "https://api.fda.gov/drug/label.json")
        components?.queryItems = [
            URLQueryItem(name: "search", value: "openfda.upc:\"\(digits)\""),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else { return nil }

        guard let openfda = await fetch(OpenFDALabelResponse.self, from: url)?.results?.first?.openfda else { return nil }
        return NDCProduct(
            genericName: openfda.generic_name?.first?.trimmed,
            brandName: openfda.brand_name?.first?.trimmed,
            strengthText: nil,
            dosageForm: openfda.dosage_form?.first?.trimmed,
            routes: openfda.route ?? [],
        )
    }

    private func fetch<T: Decodable>(_: T.Type, from url: URL) async -> T? {
        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // 404 is openFDA's "no match" — expected, not worth logging loudly.
                if http.statusCode != 404 {
                    Self.logger.warning("openFDA HTTP \(http.statusCode) for \(url.absoluteString, privacy: .public)")
                }
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Self.logger.debug("openFDA request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - openFDA response shapes

private struct OpenFDANDCResponse: Decodable {
    let results: [Result]?
    struct Result: Decodable {
        let generic_name: String?
        let brand_name: String?
        let dosage_form: String?
        let route: [String]?
        let active_ingredients: [Ingredient]?
        struct Ingredient: Decodable {
            let name: String?
            let strength: String?
        }
    }
}

private struct OpenFDALabelResponse: Decodable {
    let results: [Result]?
    struct Result: Decodable {
        let openfda: OpenFDA?
        struct OpenFDA: Decodable {
            let generic_name: [String]?
            let brand_name: [String]?
            let dosage_form: [String]?
            let route: [String]?
        }
    }
}

private extension String {
    /// Trimmed, or `nil` when nothing but whitespace remains.
    var trimmed: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
