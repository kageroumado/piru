import Testing
import UIKit
@testable import Piru

@MainActor
@Suite("Keyboard dismiss tap")
struct KeyboardDismissTapTests {
    private typealias Coordinator = KeyboardDismissTap.Coordinator

    @Test
    func `A tap on plain chrome is received`() {
        let root = UIView()
        let button = UIButton()
        root.addSubview(button)
        #expect(Coordinator.landsInTextInput(button) == false)
        #expect(Coordinator.landsInTextInput(root) == false)
        #expect(Coordinator.landsInTextInput(nil) == false)
    }

    @Test
    func `A tap on a text field or text view is declined`() {
        #expect(Coordinator.landsInTextInput(UITextField()))
        #expect(Coordinator.landsInTextInput(UITextView()))
        #expect(Coordinator.landsInTextInput(UISearchTextField()))
    }

    @Test
    func `A tap on a subview of a text input is declined`() {
        // SwiftUI hands the touch to a subview of the backing field (its clear
        // button, the caret layer's host), so the ancestor walk is what keeps a
        // re-tap on a focused field from blurring it.
        let field = UITextField()
        let inner = UIView()
        let deeper = UIView()
        field.addSubview(inner)
        inner.addSubview(deeper)
        #expect(Coordinator.landsInTextInput(deeper))
    }

    @Test
    func `A text input elsewhere in the tree does not shield its siblings`() {
        let root = UIView()
        let field = UITextField()
        let sibling = UIView()
        root.addSubview(field)
        root.addSubview(sibling)
        #expect(Coordinator.landsInTextInput(sibling) == false)
    }
}
