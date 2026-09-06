import AppKit
import CoreGraphics

enum CommandHoldEvent: Equatable, Sendable {
    case holdBegan
    case released
    case togglePin
}

enum CommandGestureAction: Equatable, Sendable {
    case scheduleHold
    case cancelHold
    case emit(CommandHoldEvent)
}

struct CommandGestureState: Sendable {
    private(set) var commandIsDown = false
    private(set) var shortcutWasPressed = false
    private var pressBeganAt: TimeInterval = 0
    private var lastTapReleasedAt: TimeInterval?
    private(set) var isSecondTapCandidate = false
    private var holdWasEmitted = false

    let doubleTapInterval: TimeInterval

    init(doubleTapInterval: TimeInterval = 0.32) {
        self.doubleTapInterval = doubleTapInterval
    }

    mutating func commandFlagsChanged(isDown: Bool, at eventTime: TimeInterval) -> [CommandGestureAction] {
        if isDown, !commandIsDown {
            commandIsDown = true
            shortcutWasPressed = false
            pressBeganAt = eventTime
            holdWasEmitted = false

            if let lastTapReleasedAt,
               eventTime - lastTapReleasedAt <= doubleTapInterval {
                self.lastTapReleasedAt = nil
                isSecondTapCandidate = true
                return [.scheduleHold]
            }

            isSecondTapCandidate = false
            return [.scheduleHold]
        }

        if !isDown, commandIsDown {
            commandIsDown = false

            if isSecondTapCandidate,
               !shortcutWasPressed,
               eventTime - pressBeganAt <= doubleTapInterval {
                isSecondTapCandidate = false
                lastTapReleasedAt = nil
                return [.cancelHold, .emit(.togglePin)]
            }

            let wasQuickTap = !shortcutWasPressed
                && !isSecondTapCandidate
                && !holdWasEmitted
                && eventTime - pressBeganAt <= doubleTapInterval
            lastTapReleasedAt = wasQuickTap ? eventTime : nil
            isSecondTapCandidate = false
            return [.cancelHold, .emit(.released)]
        }

        return []
    }

    mutating func keyPressed() -> [CommandGestureAction] {
        guard commandIsDown, !shortcutWasPressed else { return [] }
        shortcutWasPressed = true
        lastTapReleasedAt = nil
        isSecondTapCandidate = false
        return [.cancelHold, .emit(.released)]
    }

    mutating func holdDelayElapsed() -> CommandHoldEvent? {
        guard commandIsDown, !shortcutWasPressed else { return nil }
        isSecondTapCandidate = false
        lastTapReleasedAt = nil
        holdWasEmitted = true
        return .holdBegan
    }

    mutating func reset() {
        self = CommandGestureState(doubleTapInterval: doubleTapInterval)
    }
}

final class CommandHoldMonitor: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "app.keyveil.command-monitor")
    private let callback: (CommandHoldEvent) -> Void
    private var delay: TimeInterval
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workItem: DispatchWorkItem?
    private var gestureState = CommandGestureState()

    init(delay: TimeInterval, callback: @escaping (CommandHoldEvent) -> Void) {
        self.delay = delay
        self.callback = callback
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<CommandHoldMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: pointer
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func updateDelay(_ newDelay: TimeInterval) {
        stateQueue.async { [weak self] in
            self?.delay = newDelay
        }
    }

    func stop() {
        stateQueue.sync {
            workItem?.cancel()
            workItem = nil
            gestureState.reset()
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    @discardableResult
    func restart() -> Bool {
        stop()
        return start()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stateQueue.async { [weak self] in
                guard let self else { return }
                self.workItem?.cancel()
                self.workItem = nil
                self.gestureState.reset()
                DispatchQueue.main.async { self.callback(.released) }
            }

            if let eventTap, CFMachPortIsValid(eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    self?.start()
                }
            }
            return
        }

        let commandFlagIsSet = event.flags.contains(.maskCommand)
        if type == .keyDown, !commandFlagIsSet {
            return
        }
        let eventTime = event.timestamp == 0
            ? ProcessInfo.processInfo.systemUptime
            : TimeInterval(event.timestamp) / 1_000_000_000

        stateQueue.async { [weak self] in
            guard let self else { return }

            if type == .keyDown {
                self.apply(self.gestureState.keyPressed())
                return
            }

            guard type == .flagsChanged else { return }
            self.apply(self.gestureState.commandFlagsChanged(isDown: commandFlagIsSet, at: eventTime))
        }
    }

    private func apply(_ actions: [CommandGestureAction]) {
        for action in actions {
            switch action {
            case .scheduleHold:
                scheduleShow()
            case .cancelHold:
                self.workItem?.cancel()
                self.workItem = nil
            case let .emit(event):
                DispatchQueue.main.async { self.callback(event) }
            }
        }
    }

    private func scheduleShow() {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let event = self.gestureState.holdDelayElapsed() else { return }
            DispatchQueue.main.async { self.callback(event) }
        }
        workItem = item
        // Give the second tap a small release window before treating it as a hold.
        // Dispatch timers may fire a little early under load, so scheduling exactly
        // on the double-tap boundary can otherwise make pinning feel unreliable.
        let scheduledDelay = gestureState.isSecondTapCandidate
            ? max(delay, gestureState.doubleTapInterval + 0.04)
            : delay
        stateQueue.asyncAfter(deadline: .now() + scheduledDelay, execute: item)
    }
}
