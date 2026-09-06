import XCTest
@testable import Keyveil

final class ShortcutKeyFormatterTests: XCTestCase {
    func testModifierOrderAndDefaultCommandModifier() {
        XCTAssertEqual(
            ShortcutKeyFormatter.keys(commandCharacter: "p", virtualKey: nil, modifiers: 7),
            ["⌃", "⌥", "⇧", "⌘", "P"]
        )
    }

    func testNoCommandModifierBit() {
        XCTAssertEqual(
            ShortcutKeyFormatter.keys(commandCharacter: "p", virtualKey: nil, modifiers: 8),
            ["P"]
        )
    }

    func testReadableControlNavigationAndUnicodeFunctionKeys() {
        XCTAssertEqual(ShortcutKeyFormatter.readableKey("\r"), "↩")
        XCTAssertEqual(ShortcutKeyFormatter.readableKey("\t"), "⇥")
        XCTAssertEqual(ShortcutKeyFormatter.readableKey(" "), "Space")
        XCTAssertEqual(ShortcutKeyFormatter.readableKey("\u{7f}"), "⌫")
        XCTAssertEqual(ShortcutKeyFormatter.readableKey("\u{F700}"), "↑")
        XCTAssertEqual(ShortcutKeyFormatter.readableKey("\u{F704}"), "F1")
        XCTAssertEqual(ShortcutKeyFormatter.readableKey("\u{F70F}"), "F12")
        XCTAssertEqual(ShortcutKeyFormatter.readableKey("\u{F726}"), "F35")
    }

    func testVirtualFunctionKeys() {
        let expected: [Int: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
        ]

        for (keyCode, label) in expected {
            XCTAssertEqual(ShortcutKeyFormatter.virtualKeyName(keyCode), label)
        }
    }

    func testMenuGlyphs() {
        XCTAssertEqual(ShortcutKeyFormatter.glyphName(0x0B), "↩")
        XCTAssertEqual(ShortcutKeyFormatter.glyphName(0x64), "←")
        XCTAssertEqual(ShortcutKeyFormatter.glyphName(0x78), "F10")
        XCTAssertEqual(ShortcutKeyFormatter.glyphName(0x90), "F17")
        XCTAssertEqual(
            ShortcutKeyFormatter.keys(commandCharacter: "", virtualKey: 999, glyph: 0x6A, modifiers: 0),
            ["⌘", "↓"]
        )
    }

    func testUnknownVirtualKeyDoesNotCreateModifierOnlyShortcut() {
        XCTAssertNil(ShortcutKeyFormatter.keys(commandCharacter: "", virtualKey: 999, modifiers: 0))
        XCTAssertNil(ShortcutKeyFormatter.keys(commandCharacter: "", virtualKey: nil, modifiers: 0))
    }
}
