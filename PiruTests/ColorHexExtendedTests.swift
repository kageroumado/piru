import SwiftUI
import Testing
@testable import Piru

@Suite("Color from Hex Extended")
struct ColorHexExtendedTests {
    private func rgb(from color: Color) -> (r: Double, g: Double, b: Double) {
        let resolved = color.resolve(in: .init())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }

    // MARK: - 8-char RRGGBBAA format

    @Test
    func `Parses 8-char hex with alpha (ignores alpha)`() {
        let color = Color(hex: "FF000080") // red with 50% alpha
        let (r, g, b) = rgb(from: color)
        #expect(r > 0.99)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test
    func `8-char white with alpha`() {
        let color = Color(hex: "FFFFFFFF")
        let (r, g, b) = rgb(from: color)
        #expect(r > 0.99)
        #expect(g > 0.99)
        #expect(b > 0.99)
    }

    // MARK: - Specific color values

    @Test
    func `Parses mid-gray correctly`() {
        let color = Color(hex: "#808080")
        let (r, g, b) = rgb(from: color)
        // 0x80 / 255 ≈ 0.502
        #expect(abs(r - 0.502) < 0.01)
        #expect(abs(g - 0.502) < 0.01)
        #expect(abs(b - 0.502) < 0.01)
    }

    @Test
    func `Parses preset color hex values correctly`() {
        // Just verify that preset hex values produce non-black colors
        for preset in PresetColor.all.prefix(5) {
            let color = Color(hex: preset.hex)
            let (r, g, b) = rgb(from: color)
            let isNotBlack = r > 0.01 || g > 0.01 || b > 0.01
            #expect(isNotBlack, "\(preset.name) (\(preset.hex)) should not be black")
        }
    }

    // MARK: - Invalid inputs

    @Test
    func `4-char hex defaults to black`() {
        let color = Color(hex: "FFFF")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test
    func `Non-hex characters default to black`() {
        let color = Color(hex: "ZZZZZZ")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test
    func `Hash-only string defaults to black`() {
        let color = Color(hex: "#")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }
}
