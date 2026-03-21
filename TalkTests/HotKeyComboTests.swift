//
//  HotKeyComboTests.swift
//  TalkTests
//
//  HotKeyCombo unit tests using Swift Testing framework
//

import Testing
import Foundation
@testable import Talk

struct HotKeyComboTests {

    // MARK: - Default combo

    @Test func defaultComboIsControlKey() {
        let combo = HotKeyCombo.defaultCombo
        #expect(combo.carbonKeyCode == 59)
        #expect(combo.carbonModifiers == 0)
        #expect(combo.isModifierOnly == true)
    }

    // MARK: - displayString

    @Test func displayStringControlAlone() {
        let combo = HotKeyCombo(carbonModifiers: 0, carbonKeyCode: 59, isModifierOnly: true)
        #expect(combo.displayString == "\u{2303} Control")
    }

    @Test func displayStringOptionControl() {
        // Option (0x0800) as additional modifier, Control (keyCode 59) as primary modifier-only key
        let combo = HotKeyCombo(carbonModifiers: 0x0800, carbonKeyCode: 59, isModifierOnly: true)
        #expect(combo.displayString.contains("\u{2303}"))
        #expect(combo.displayString.contains("\u{2325}"))
        #expect(combo.displayString.contains("Control"))
    }

    @Test func displayStringCommandSpace() {
        let combo = HotKeyCombo(carbonModifiers: 0x0100, carbonKeyCode: 49, isModifierOnly: false)
        #expect(combo.displayString == "\u{2318} Space")
    }

    @Test func displayStringRegularKeyWithModifiers() {
        // Command + T (keyCode 17)
        let combo = HotKeyCombo(carbonModifiers: 0x0100, carbonKeyCode: 17, isModifierOnly: false)
        #expect(combo.displayString == "\u{2318} T")
    }

    // MARK: - Codable

    @Test func codableRoundTrip() throws {
        let original = HotKeyCombo(carbonModifiers: 0x0100, carbonKeyCode: 49, isModifierOnly: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyCombo.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Equatable

    @Test func equalWhenSameValues() {
        let a = HotKeyCombo(carbonModifiers: 0x0100, carbonKeyCode: 49, isModifierOnly: false)
        let b = HotKeyCombo(carbonModifiers: 0x0100, carbonKeyCode: 49, isModifierOnly: false)
        #expect(a == b)
    }

    @Test func notEqualWhenDifferentValues() {
        let a = HotKeyCombo(carbonModifiers: 0x0100, carbonKeyCode: 49, isModifierOnly: false)
        let b = HotKeyCombo(carbonModifiers: 0x0800, carbonKeyCode: 59, isModifierOnly: true)
        #expect(a != b)
    }

    // MARK: - fromLegacyString

    @Test func legacyStringControl() {
        let combo = HotKeyCombo.fromLegacyString("Control")
        #expect(combo.carbonKeyCode == 59)
        #expect(combo.carbonModifiers == 0)
        #expect(combo.isModifierOnly == true)
    }

    @Test func legacyStringOptionControl() {
        let combo = HotKeyCombo.fromLegacyString("Option + Control")
        #expect(combo.carbonKeyCode == 59)
        #expect(combo.carbonModifiers == 0x0800)
        #expect(combo.isModifierOnly == true)
    }

    @Test func legacyStringCommandSpace() {
        let combo = HotKeyCombo.fromLegacyString("Command + Space")
        #expect(combo.carbonKeyCode == 49)
        #expect(combo.carbonModifiers == 0x0100)
        #expect(combo.isModifierOnly == false)
    }
}
