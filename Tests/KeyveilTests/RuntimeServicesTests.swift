import AppKit
import XCTest
@testable import Keyveil

@MainActor
final class RuntimeServicesTests: XCTestCase {
    func testDebouncedActionCoalescesBurstsAndCanBeCancelled() async {
        let debouncer = DebouncedAction(delay: .milliseconds(30))
        var values: [Int] = []

        debouncer.schedule { values.append(1) }
        debouncer.schedule { values.append(2) }
        debouncer.schedule { values.append(3) }
        try? await Task.sleep(for: .milliseconds(70))

        XCTAssertEqual(values, [3])

        debouncer.schedule { values.append(4) }
        debouncer.cancel()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(values, [3])
    }

    func testOverlayMapsPinnedNavigationKeys() throws {
        let expectations: [(UInt16, ShortcutScrollCommand)] = [
            (126, .lineUp),
            (125, .lineDown),
            (116, .pageUp),
            (121, .pageDown),
            (115, .home),
            (119, .end)
        ]

        for (keyCode, expectedCommand) in expectations {
            let event = try XCTUnwrap(keyEvent(keyCode: keyCode))
            XCTAssertEqual(OverlayPanel.shortcutScrollCommand(for: event), expectedCommand)
        }
    }

    func testOverlayLeavesModifiedAndUnrelatedKeysAlone() throws {
        let commandDown = try XCTUnwrap(keyEvent(keyCode: 125, modifiers: .command))
        let optionPageDown = try XCTUnwrap(keyEvent(keyCode: 121, modifiers: .option))
        let letter = try XCTUnwrap(keyEvent(keyCode: 0))

        XCTAssertNil(OverlayPanel.shortcutScrollCommand(for: commandDown))
        XCTAssertNil(OverlayPanel.shortcutScrollCommand(for: optionPageDown))
        XCTAssertNil(OverlayPanel.shortcutScrollCommand(for: letter))
    }

    func testScrollControllerMovesByLinePageAndDocumentBounds() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        scrollView.documentView = FlippedDocumentView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 1_200)
        )
        scrollView.layoutSubtreeIfNeeded()
        let controller = ShortcutScrollController()
        controller.attach(scrollView)

        controller.perform(.lineDown)
        XCTAssertEqual(scrollView.contentView.bounds.minY, 52, accuracy: 0.5)

        let lineOffset = scrollView.contentView.bounds.minY
        controller.perform(.pageDown)
        XCTAssertGreaterThan(scrollView.contentView.bounds.minY, lineOffset + 100)

        controller.perform(.end)
        let expectedEnd = 1_200 - scrollView.contentView.bounds.height
        XCTAssertEqual(scrollView.contentView.bounds.minY, expectedEnd, accuracy: 0.5)

        controller.perform(.pageDown)
        XCTAssertEqual(scrollView.contentView.bounds.minY, expectedEnd, accuracy: 0.5)

        controller.perform(.home)
        XCTAssertEqual(scrollView.contentView.bounds.minY, 0, accuracy: 0.5)

        controller.perform(.lineUp)
        XCTAssertEqual(scrollView.contentView.bounds.minY, 0, accuracy: 0.5)
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
