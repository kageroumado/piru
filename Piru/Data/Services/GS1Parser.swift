import Foundation

/// The four Application Identifiers a GS1 medication barcode carries, decoded
/// from a DataMatrix/GS1-128 payload.
struct GS1Data: Equatable {
    /// AI `01` — Global Trade Item Number, 14 digits. The drug-identifying field.
    var gtin: String?
    /// AI `17` — expiry, stored as the raw `YYMMDD` the barcode encodes.
    var expiryDate: String?
    /// AI `10` — lot/batch number, variable length.
    var lotNumber: String?
    /// AI `21` — serial number, variable length.
    var serialNumber: String?

    var isEmpty: Bool {
        gtin == nil && expiryDate == nil && lotNumber == nil && serialNumber == nil
    }
}

/// Decodes a GS1 element string into its Application Identifiers.
///
/// GS1 payloads concatenate `AI + value` segments. Fixed-length AIs (`01`, `17`)
/// consume their defined width; variable-length AIs (`10`, `21`) run until the
/// next FNC1 group separator (`\u{1D}`) or the end of the string. This covers the
/// four AIs mandated by both US DSCSA and EU FMD; any other AI encountered is
/// consumed (by its known fixed width, else as variable) so parsing stays aligned
/// and later AIs are still recovered.
enum GS1Parser {
    /// The FNC1 group separator that terminates a variable-length value.
    private static let groupSeparator: Character = "\u{1D}"

    /// AIs with a defined fixed value width (digits after the 2-char AI).
    private static let fixedWidths: [String: Int] = [
        "00": 18, // SSCC
        "01": 14, // GTIN
        "11": 6, // production date  YYMMDD
        "13": 6, // packaging date
        "15": 6, // best-before
        "16": 6, // sell-by
        "17": 6, // expiry          YYMMDD
    ]

    static func parse(_ payload: String) -> GS1Data {
        var result = GS1Data()
        let chars = Array(payload)
        var i = 0
        let n = chars.count

        // A leading FNC1 (some scanners prefix the whole payload) is not data.
        if i < n, chars[i] == groupSeparator { i += 1 }

        while i + 2 <= n {
            let ai = String(chars[i ..< i + 2])
            i += 2

            if let width = fixedWidths[ai] {
                let end = min(i + width, n)
                let value = String(chars[i ..< end])
                i = end
                assign(ai: ai, value: value, into: &result)
            } else {
                // Variable length: consume to the next separator or end.
                var end = i
                while end < n, chars[end] != groupSeparator {
                    end += 1
                }
                let value = String(chars[i ..< end])
                i = end
                assign(ai: ai, value: value, into: &result)
            }

            // Step over a separator between segments, if present.
            if i < n, chars[i] == groupSeparator { i += 1 }
        }

        return result
    }

    private static func assign(ai: String, value: String, into result: inout GS1Data) {
        guard !value.isEmpty else { return }
        switch ai {
        case "01": result.gtin = value
        case "17": result.expiryDate = value
        case "10": result.lotNumber = value
        case "21": result.serialNumber = value
        default: break
        }
    }
}
