import Testing
import SwiftUI
@testable import Piru

@Suite("Color from Hex")
struct ColorHexTests {

    // Helper to extract RGB components from a Color
    private func rgb(from color: Color) -> (r: Double, g: Double, b: Double) {
        let resolved = color.resolve(in: .init())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }

    // MARK: - Valid hex parsing

    @Test("Parses red hex correctly")
    func parsesRed() {
        let color = Color(hex: "#FF0000")
        let (r, g, b) = rgb(from: color)
        #expect(r > 0.99)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test("Parses green hex correctly")
    func parsesGreen() {
        let color = Color(hex: "#00FF00")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g > 0.99)
        #expect(b < 0.01)
    }

    @Test("Parses blue hex correctly")
    func parsesBlue() {
        let color = Color(hex: "#0000FF")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b > 0.99)
    }

    @Test("Parses white hex correctly")
    func parsesWhite() {
        let color = Color(hex: "#FFFFFF")
        let (r, g, b) = rgb(from: color)
        #expect(r > 0.99)
        #expect(g > 0.99)
        #expect(b > 0.99)
    }

    @Test("Parses black hex correctly")
    func parsesBlack() {
        let color = Color(hex: "#000000")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    // MARK: - Prefix handling

    @Test("Parses hex without # prefix")
    func parsesWithoutHash() {
        let color = Color(hex: "FF0000")
        let (r, _, _) = rgb(from: color)
        #expect(r > 0.99)
    }

    @Test("Parses hex with # prefix")
    func parsesWithHash() {
        let color = Color(hex: "#FF0000")
        let (r, _, _) = rgb(from: color)
        #expect(r > 0.99)
    }

    // MARK: - Case sensitivity

    @Test("Case insensitive parsing")
    func caseInsensitive() {
        let lower = Color(hex: "ff0000")
        let upper = Color(hex: "FF0000")
        let lowerRGB = rgb(from: lower)
        let upperRGB = rgb(from: upper)
        #expect(abs(lowerRGB.r - upperRGB.r) < 0.01)
        #expect(abs(lowerRGB.g - upperRGB.g) < 0.01)
        #expect(abs(lowerRGB.b - upperRGB.b) < 0.01)
    }

    // MARK: - Invalid input

    @Test("3-char shorthand expands correctly")
    func threeCharShorthand() {
        let white = Color(hex: "FFF")
        let (wr, wg, wb) = rgb(from: white)
        #expect(wr > 0.99)
        #expect(wg > 0.99)
        #expect(wb > 0.99)

        let red = Color(hex: "F00")
        let (rr, rg, rb) = rgb(from: red)
        #expect(rr > 0.99)
        #expect(rg < 0.01)
        #expect(rb < 0.01)
    }

    @Test("Invalid length defaults to black")
    func invalidLength() {
        let color = Color(hex: "GG")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }

    @Test("Empty string defaults to black")
    func emptyString() {
        let color = Color(hex: "")
        let (r, g, b) = rgb(from: color)
        #expect(r < 0.01)
        #expect(g < 0.01)
        #expect(b < 0.01)
    }
}
