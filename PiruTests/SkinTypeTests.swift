import SwiftUI
import Testing
import UIKit
@testable import Piru

@MainActor
@Suite("Skin typography")
struct SkinTypeTests {
    @Test
    func `The bundled display and label faces are registered`() {
        // UIAppFonts in Piru/Info.plist; both families ship in Piru/Fonts.
        #expect(UIFont(name: "Fredoka-Regular", size: 17) != nil)
        #expect(UIFont(name: "Fredoka-Bold", size: 17) != nil)
        #expect(UIFont(name: "DotGothic16-Regular", size: 12) != nil)
        #expect(UIFont.familyNames.contains("Fredoka"))
        #expect(UIFont.familyNames.contains("DotGothic16"))
    }

    @Test
    func `Every skin's typeface names a family the bundle actually has`() {
        for skin in Skin.allCases {
            for family in [skin.typeface.display, skin.typeface.label].compactMap(\.self) {
                #expect(UIFont.familyNames.contains(family), "\(skin.rawValue) names \(family), which is not bundled")
            }
        }
    }

    @Test
    func `The resolver returns registered face names per weight`() {
        // SwiftUI's `Font.custom` + `.weight()` on a family name rendered the
        // system font on device; explicit face names are what reliably resolve.
        #expect(SkinFace.registered("Fredoka", weight: .regular) == "Fredoka-Regular")
        #expect(SkinFace.registered("Fredoka", weight: .semibold) == "Fredoka-SemiBold")
        #expect(SkinFace.registered("Fredoka", weight: .bold) == "Fredoka-Bold")
        #expect(SkinFace.registered("Fredoka", weight: .heavy) == "Fredoka-Bold")
        // DotGothic16 ships one face; every weight lands on it.
        #expect(SkinFace.registered("DotGothic16", weight: .semibold) == "DotGothic16-Regular")
        #expect(SkinFace.registered("NoSuchFamily", weight: .bold) == nil)
    }

    @Test
    func `With ely.pink active, display and label roles resolve to Fredoka and DotGothic16`() {
        let store = SkinStore.shared
        let previous = store.current
        defer { store.setSkin(previous) }
        store.setSkin(.elyPink)
        #expect(SkinFace.display(weight: .bold, size: 20, relativeTo: .title) != nil)
        #expect(SkinFace.label(weight: .semibold, size: 11, relativeTo: .caption2) != nil)
        // The descriptor path resolves the family without a prior name lookup.
        let descriptor = UIFontDescriptor(fontAttributes: [.family: "Fredoka", .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]])
        #expect(UIFont(descriptor: descriptor, size: 20).familyName == "Fredoka")
        #expect(Font.piru(.headline) != Font.system(.headline).weight(.semibold))
        #expect(Font.piru(size: 20, weight: .bold) != Font.system(size: 20, weight: .bold))
    }

    @Test
    func `A skin with a custom face has no root font design`() {
        // A root `.fontDesign` replaces every SwiftUI font in the tree, wrapped
        // custom faces included; only UIKit's navigation bar escapes it.
        for skin in Skin.allCases where skin.typeface.display != nil || skin.typeface.label != nil {
            #expect(skin.fontDesign == nil, "\(skin.rawValue) sets fontDesign, which would erase its custom faces")
        }
    }

    @Test
    func `Only the five display styles are display`() {
        let display: [Font.TextStyle] = [.largeTitle, .title, .title2, .title3, .headline]
        let rest: [Font.TextStyle] = [.subheadline, .body, .callout, .footnote, .caption, .caption2]
        for style in display {
            #expect(style.isDisplay)
        }
        for style in rest {
            #expect(!style.isDisplay)
        }
    }

    @Test
    func `Default point sizes match the system's large-content sizes`() {
        #expect(Font.TextStyle.largeTitle.defaultPointSize == 34)
        #expect(Font.TextStyle.body.defaultPointSize == 17)
        #expect(Font.TextStyle.caption2.defaultPointSize == 11)
    }

    @Test
    func `A skin without custom faces resolves to the plain system styles`() {
        #expect(Skin.piru.typeface == SkinTypeface(display: nil, label: nil))
        // Font is not Equatable by value across custom/system, so check the
        // resolution path: with no family, both helpers hand back the system style.
        if SkinStore.shared.current == .piru {
            #expect(Font.piru(.headline) == Font.system(.headline).weight(.semibold))
            #expect(Font.piru(.title3) == Font.system(.title3).weight(.regular))
            #expect(Font.piruLabel(.caption2) == Font.system(.caption2).weight(.regular))
        }
    }
}
