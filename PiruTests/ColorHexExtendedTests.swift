import Testing
import SwiftUI
@testable import Piru

@Suite("Color from Hex Extended")
struct ColorHexExtendedTests {

    private func rgb(from color: Color) -> (r: Double, g: Double, b: Double) {
        let resolved = color.resolve(in: .init())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }

    // MARK: - 8-char RRGGBBAA format

    @Test("Parses 8-char hex with alpha (ignores alpha)")
    func eightCharHex() {
        let color = Color(hex: "FF000080") // red with 50% alpha
        let (r, g, b) = rgb(from: color)
        #expect(r > 0.99)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test("8-char white with alpha")
    func eightCharWhite() {
        let color = Color(hex: "FFFFFFFF")
        let (r, g, b) = rgb(from: color)
        #expect(r > 0.99)
        #expect(g > 0.99)
        #expect(b > 0.99)
    }

    // MARK: - Specific color values

    @Test("Parses mid-gray correctly")
    func midGray() {
        let color = Color(hex: "#808080")
        let (r, g, b) = rgb(from: color)
        // 0x80 / 255 ≈ 0.502
        #expect(abs(r - 0.502) < 0.01)
        #expect(abs(g - 0.502) < 0.01)
        #expect(abs(b - 0.502) < 0.01)
    }

    @Test("Parses preset color hex values correctly")
    func presetColors() {
        // Just verify that preset hex values produce non-black colors
        for preset in PresetColor.all.prefix(5) {
            let color = Color(hex: preset.hex)
            let (r, g, b) = rgb(from: color)
            let isNotBlack = r > 0.01 || g > 0.01 || b > 0.01
            #expect(isNotBlack, "\(preset.name) (\(preset.hex)) should not be black")
        }
    }

    // MARK: - Invalid inputs

    @Test("4-char hex defaults to black")
    func fourCharHex() {
        let color = Color(hex: "FFFF")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test("Non-hex characters default to black")
    func nonHexChars() {
        let color = Color(hex: "ZZZZZZ")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test("Hash-only string defaults to black")
    func hashOnly() {
        let color = Color(hex: "#")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }
}
