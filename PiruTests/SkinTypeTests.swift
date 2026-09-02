import SwiftUI
import Testing
import UIKit
@testable import Piru

@MainActor
@Suite("Skin typography")
struct SkinTypeTests {
    @Test("The bundled display and label faces are registered")
    func fontsRegistered() {
        // UIAppFonts in Piru/Info.plist; both families ship in Piru/Fonts.
        #expect(UIFont(name: "Fredoka-Regular", size: 17) != nil)
        #expect(UIFont(name: "Fredoka-Bold", size: 17) != nil)
        #expect(UIFont(name: "DotGothic16-Regular", size: 12) != nil)
        #expect(UIFont.familyNames.contains("Fredoka"))
        #expect(UIFont.familyNames.contains("DotGothic16"))
    }

    @Test("Every skin's typeface names a family the bundle actually has")
    func typefacesResolve() {
        for skin in Skin.allCases {
            for family in [skin.typeface.display, skin.typeface.label].compactMap(\.self) {
                #expect(UIFont.familyNames.contains(family), "\(skin.rawValue) names \(family), which is not bundled")
            }
        }
    }

    @Test("Only the five display styles are display")
    func displayStyles() {
        let display: [Font.TextStyle] = [.largeTitle, .title, .title2, .title3, .headline]
        let rest: [Font.TextStyle] = [.subheadline, .body, .callout, .footnote, .caption, .caption2]
        for style in display { #expect(style.isDisplay) }
        for style in rest { #expect(!style.isDisplay) }
    }

    @Test("Default point sizes match the system's large-content sizes")
    func defaultSizes() {
        #expect(Font.TextStyle.largeTitle.defaultPointSize == 34)
        #expect(Font.TextStyle.body.defaultPointSize == 17)
        #expect(Font.TextStyle.caption2.defaultPointSize == 11)
    }

    @Test("A skin without custom faces resolves to the plain system styles")
    func defaultSkinIsSystem() {
        #expect(Skin.piru.typeface == SkinTypeface(display: nil, label: nil))
        // Font is not Equatable by value across custom/system, so check the
        // resolution path: with no family, both helpers hand back the system style.
        if SkinStore.shared.current == .piru {
            #expect(Font.piru(.headline) == .system(.headline))
            #expect(Font.piruLabel(.caption2) == .system(.caption2))
        }
    }
}
