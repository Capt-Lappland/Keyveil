import XCTest
@testable import Keyveil

final class CommandGestureStateTests: XCTestCase {
    func testLongHoldEmitsOnceAndReleaseCancels() {
        var state = CommandGestureState()

        XCTAssertEqual(state.commandFlagsChanged(isDown: true, at: 10), [.scheduleHold])
        XCTAssertTrue(state.commandFlagsChanged(isDown: true, at: 10.01).isEmpty)
        XCTAssertEqual(state.holdDelayElapsed(), .holdBegan)
        XCTAssertEqual(
            state.commandFlagsChanged(isDown: false, at: 10.8),
            [.cancelHold, .emit(.released)]
        )
        XCTAssertNil(state.holdDelayElapsed())
    }

    func testQuickDoubleTapTogglesOnlyOnSecondRelease() {
        var state = CommandGestureState(doubleTapInterval: 0.32)

        _ = state.commandFlagsChanged(isDown: true, at: 1)
        _ = state.commandFlagsChanged(isDown: false, at: 1.10)
        XCTAssertEqual(state.commandFlagsChanged(isDown: true, at: 1.30), [.scheduleHold])
        XCTAssertEqual(
            state.commandFlagsChanged(isDown: false, at: 1.40),
            [.cancelHold, .emit(.togglePin)]
        )
        XCTAssertEqual(state.commandFlagsChanged(isDown: true, at: 1.50), [.scheduleHold])
    }

    func testCommandTapThenShortcutDoesNotTogglePin() {
        var state = CommandGestureState()

        _ = state.commandFlagsChanged(isDown: true, at: 2)
        _ = state.commandFlagsChanged(isDown: false, at: 2.08)
        _ = state.commandFlagsChanged(isDown: true, at: 2.20)

        XCTAssertEqual(state.keyPressed(), [.cancelHold, .emit(.released)])
        XCTAssertEqual(
            state.commandFlagsChanged(isDown: false, at: 2.25),
            [.cancelHold, .emit(.released)]
        )
    }

    func testCommandShortcutCancelsHoldAndIgnoresKeyRepeat() {
        var state = CommandGestureState()

        _ = state.commandFlagsChanged(isDown: true, at: 3)
        XCTAssertEqual(state.keyPressed(), [.cancelHold, .emit(.released)])
        XCTAssertTrue(state.keyPressed().isEmpty)
        XCTAssertNil(state.holdDelayElapsed())
    }

    func testEmittedHoldNeverArmsDoubleTapAtTimingBoundary() {
        var state = CommandGestureState(doubleTapInterval: 0.32)

        _ = state.commandFlagsChanged(isDown: true, at: 20)
        XCTAssertEqual(state.holdDelayElapsed(), .holdBegan)
        _ = state.commandFlagsChanged(isDown: false, at: 20.31)
        _ = state.commandFlagsChanged(isDown: true, at: 20.50)

        XCTAssertEqual(
            state.commandFlagsChanged(isDown: false, at: 20.58),
            [.cancelHold, .emit(.released)]
        )
    }

    func testSlowSecondTapStartsNewHold() {
        var state = CommandGestureState(doubleTapInterval: 0.32)

        _ = state.commandFlagsChanged(isDown: true, at: 4)
        _ = state.commandFlagsChanged(isDown: false, at: 4.05)
        XCTAssertEqual(state.commandFlagsChanged(isDown: true, at: 4.38), [.scheduleHold])
    }

    func testHoldingSecondTapBecomesHoldInsteadOfPin() {
        var state = CommandGestureState(doubleTapInterval: 0.32)

        _ = state.commandFlagsChanged(isDown: true, at: 6)
        _ = state.commandFlagsChanged(isDown: false, at: 6.08)
        _ = state.commandFlagsChanged(isDown: true, at: 6.20)

        XCTAssertEqual(state.holdDelayElapsed(), .holdBegan)
        XCTAssertEqual(
            state.commandFlagsChanged(isDown: false, at: 6.60),
            [.cancelHold, .emit(.released)]
        )
    }

    func testResetClearsStuckState() {
        var state = CommandGestureState()
        _ = state.commandFlagsChanged(isDown: true, at: 5)

        state.reset()

        XCTAssertFalse(state.commandIsDown)
        XCTAssertFalse(state.shortcutWasPressed)
        XCTAssertFalse(state.isSecondTapCandidate)
        XCTAssertNil(state.holdDelayElapsed())
    }
}
