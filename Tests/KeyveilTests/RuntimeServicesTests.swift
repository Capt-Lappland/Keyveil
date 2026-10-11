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

    func testStatusLightReflectsWhatIsActuallyOnScreen() {
        // Nothing on screen: the light must not imply the shortcuts are fine,
        // whatever the scan reported.
        XCTAssertEqual(
            ShortcutPanelStatus.resolve(isLoading: false, hasShortcuts: false, issue: nil),
            .failed
        )
        XCTAssertEqual(
            ShortcutPanelStatus.resolve(isLoading: false, hasShortcuts: false, issue: .unavailable),
            .failed
        )
        XCTAssertEqual(
            ShortcutPanelStatus.resolve(isLoading: false, hasShortcuts: false, issue: .timedOut),
            .failed
        )

        // Content on screen: green only when it came from a clean scan.
        XCTAssertEqual(
            ShortcutPanelStatus.resolve(isLoading: false, hasShortcuts: true, issue: nil),
            .ready
        )
        XCTAssertEqual(
            ShortcutPanelStatus.resolve(isLoading: false, hasShortcuts: true, issue: .unavailable),
            .stale
        )
        XCTAssertEqual(
            ShortcutPanelStatus.resolve(isLoading: false, hasShortcuts: true, issue: .timedOut),
            .stale
        )

        // A scan in flight is never reported as ready.
        XCTAssertEqual(
            ShortcutPanelStatus.resolve(isLoading: true, hasShortcuts: true, issue: nil),
            .loading
        )
        XCTAssertEqual(
            ShortcutPanelStatus.resolve(isLoading: true, hasShortcuts: false, issue: nil),
            .loading
        )
    }

    func testOnboardingPermissionStateModel() {
        // Never asked: the row can raise the system prompt itself.
        XCTAssertEqual(
            OnboardingPermissionState.resolve(isGranted: false, hasRequested: false),
            .notRequested
        )
        // Asked and unanswered: macOS will not show its prompt again, so the row has
        // to offer System Settings instead of a button that does nothing.
        XCTAssertEqual(
            OnboardingPermissionState.resolve(isGranted: false, hasRequested: true),
            .awaitingApproval
        )
        // Granted wins regardless of whether it was ever requested this session,
        // which is the case when permission was given in an earlier launch.
        XCTAssertEqual(
            OnboardingPermissionState.resolve(isGranted: true, hasRequested: false),
            .granted
        )
        XCTAssertEqual(
            OnboardingPermissionState.resolve(isGranted: true, hasRequested: true),
            .granted
        )
    }

    func testOverlayKeepsArrowKeysForTextEditing() {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        panel.contentView = textView

        // Nothing focused: the wall may use the navigation keys.
        XCTAssertFalse(OverlayPanel.isEditingText(in: panel))

        // With the search field focused, AppKit makes its field editor the first
        // responder. That editor is an NSTextView, so the panel must leave the
        // arrow keys alone and let it move the insertion point.
        XCTAssertTrue(panel.makeFirstResponder(textView))
        XCTAssertTrue(OverlayPanel.isEditingText(in: panel))

        panel.orderOut(nil)
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
