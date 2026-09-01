#if DEBUG
    import Foundation

    /// Canned box readings for exercising the identify flow without a camera,
    /// selected with the `-piruScanFixture <name>` launch argument:
    ///
    ///     xcrun simctl launch booted dev.yumeji.piru -piruScanFixture concerta
    ///
    /// On launch the app opens Tools ▸ Identify a Box with the fixture already
    /// resolved, so the result screen can be driven and screenshotted on a
    /// simulator. Barcodes are real registry codes (openFDA / BDPM).
    enum ScanFixtures {
        static let launchArgumentKey = "piruScanFixture"

        static let all: [String: BoxReading] = [
            // A US box, resolved by its NDC barcode (UPC-A 3 + NDC-10 + check).
            "concerta": BoxReading(
                texts: ["CONCERTA®", "(methylphenidate HCl)", "Extended-Release Tablets", "36 mg", "100 Tablets", "NDC 50458-586-01", "CII"],
                barcodes: ["350458586015"],
            ),
            // A French box, resolved by its CIP13 (EAN-13) barcode.
            "ritaline": BoxReading(
                texts: ["RITALINE 10 mg", "Chlorhydrate de méthylphénidate", "comprimé sécable", "30 comprimés", "CIP 3400933929404"],
                barcodes: ["3400933929404"],
            ),
            // No barcode: name and pack size read from the print alone.
            "ibuprofen": BoxReading(
                texts: ["Ibuprofen 400 mg", "Film-coated tablets", "2 × 12 tablets", "For oral use"],
                barcodes: [],
            ),
            // Nothing the library knows: the external-links state.
            "unknown": BoxReading(
                texts: ["Zaltrapex", "Comprimés pelliculés", "20 comprimés"],
                barcodes: ["3400912345676"],
            ),
        ]

        /// The reading the launch argument names, or `nil`.
        static func launchReading() -> BoxReading? {
            guard let name = UserDefaults.standard.string(forKey: launchArgumentKey) else { return nil }
            guard let reading = all[name] else {
                print("ScanFixtures: unknown fixture '\(name)' — known: \(all.keys.sorted().joined(separator: ", "))")
                return nil
            }
            return reading
        }

        static var isRequested: Bool {
            UserDefaults.standard.string(forKey: launchArgumentKey) != nil
        }
    }
#endif
