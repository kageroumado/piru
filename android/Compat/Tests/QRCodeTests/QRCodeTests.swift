import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Testing

/// Android draws the pairing code with `QRCodeMatrix`; an iPhone's camera reads it. Each code is
/// read back with Core Image's QR reader and compared with Core Image's own generator.
@Suite("QRCodeMatrix")
nonisolated struct QRCodeTests {
    /// A pairing link as PairingCode writes one, with a name that needs percent-encoding.
    static let pairingLink = "piru://pair?v=1&id=5c3f6a9e-1d2b-4c8a-9f0e-7b6d5a4c3b2a&k=Qm9iJ3MgcHVibGljIGtleSwgMzIgYnl0ZXMgbG9uZyE&n=Ma%C3%ADra%20%E7%A9%BA&m=MS"

    /// Black modules on white, with the four-module quiet zone, `scale` pixels a module.
    static func image(_ matrix: QRCodeMatrix, scale: Int = 6) -> CGImage {
        let side = (matrix.size + 8) * scale
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue,
        )!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(gray: 0, alpha: 1)
        for y in 0 ..< matrix.size {
            for x in 0 ..< matrix.size where matrix[x, y] {
                // Core Graphics counts rows from the bottom.
                context.fill(CGRect(x: (x + 4) * scale, y: side - (y + 5) * scale, width: scale, height: scale))
            }
        }
        return context.makeImage()!
    }

    static func read(_ image: CGImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector?.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }

    /// Core Image's code for `text` at level M, as PairingView makes it on iOS: one pixel a module.
    static func coreImageModules(_ text: String) -> (size: Int, dark: (Int, Int) -> Bool) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        let output = filter.outputImage!
        let image = CIContext().createCGImage(output, from: output.extent)!
        let width = image.width
        let context = CGContext(
            data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue,
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: width))
        let pixels = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: width * width))
        // Core Image leaves a one-module margin.
        return (width - 2, { x, y in pixels[(y + 1) * width + x + 1] < 128 })
    }

    @Test
    func `A pairing link reads back`() throws {
        let matrix = try #require(QRCodeMatrix(Self.pairingLink))
        #expect(Self.read(Self.image(matrix)) == Self.pairingLink)
    }

    @Test(arguments: [1, 17, 40, 120, 300, 700, 1_200, 2_000, 2_331])
    func `Every version size reads back`(length: Int) throws {
        let text = String((0 ..< length).map { index in Character(UnicodeScalar(UInt8(48 + (index * 7 + index / 13) % 75))) })
        let matrix = try #require(QRCodeMatrix(text))
        #expect(matrix.size == matrix.version * 4 + 17)
        #expect(Self.read(Self.image(matrix, scale: 4)) == text)
    }

    @Test
    func `Text past version 40 makes no code`() {
        #expect(QRCodeMatrix(String(repeating: "a", count: 2_332)) == nil)
    }

    /// The data, error correction and layout match Core Image exactly. Core Image picks its mask
    /// by rules of its own, so the comparison takes the mask it chose. A full pairing link
    /// differs in its data modules, as Core Image segments some texts its own way; it reads back
    /// all the same, which `A pairing link reads back` checks.
    @Test(arguments: ["piru://pair?v=1", String(repeating: "Ab3", count: 90)])
    func `Matches Core Image module for module under the same mask`(text: String) {
        let reference = Self.coreImageModules(text)
        let matching = (0 ..< 8).compactMap { QRCodeMatrix(text, mask: $0) }.filter { matrix in
            matrix.size == reference.size && (0 ..< matrix.size).allSatisfy { y in
                (0 ..< matrix.size).allSatisfy { x in matrix[x, y] == reference.dark(x, y) }
            }
        }
        #expect(matching.count == 1)
    }
}
