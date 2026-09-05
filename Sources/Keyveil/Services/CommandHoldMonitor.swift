import AppKit
import CoreGraphics

enum CommandHoldEvent: Sendable {
    case holdBegan
    case released
    case togglePin
}

final class CommandHoldMonitor: @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "app.keyveil.command-monitor")
    private let callback: (CommandHoldEvent) -> Void
    private var delay: TimeInterval
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workItem: DispatchWorkItem?
    private var commandIsDown = false
    private var shortcutWasPressed = false
    private var pressBeganAt: TimeInterval = 0
    private var lastTapReleasedAt: TimeInterval?
    private var toggledPinOnCurrentPress = false

    private let doubleTapInterval: TimeInterval = 0.32

    init(delay: TimeInterval, callback: @escaping (CommandHoldEvent) -> Void) {
        self.delay = delay
        self.callback = callback
    }

    func start() {
        guard eventTap == nil else { return }

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
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        let commandFlagIsSet = event.flags.contains(.maskCommand)
        let eventTime = ProcessInfo.processInfo.systemUptime

        stateQueue.async { [weak self] in
            guard let self else { return }

            if type == .keyDown, self.commandIsDown {
                self.shortcutWasPressed = true
                self.lastTapReleasedAt = nil
                self.workItem?.cancel()
                self.workItem = nil
                DispatchQueue.main.async { self.callback(.released) }
                return
            }

            guard type == .flagsChanged else { return }
            let isDown = commandFlagIsSet

            if isDown, !self.commandIsDown {
                self.commandIsDown = true
                self.shortcutWasPressed = false
                self.pressBeganAt = eventTime

                if let lastTap = self.lastTapReleasedAt,
                   eventTime - lastTap <= self.doubleTapInterval {
                    self.lastTapReleasedAt = nil
                    self.toggledPinOnCurrentPress = true
                    self.workItem?.cancel()
                    self.workItem = nil
                    DispatchQueue.main.async { self.callback(.togglePin) }
                } else {
                    self.toggledPinOnCurrentPress = false
                    self.scheduleShow()
                }
            } else if !isDown, self.commandIsDown {
                self.commandIsDown = false
                self.workItem?.cancel()
                self.workItem = nil

                let wasQuickTap = !self.shortcutWasPressed
                    && !self.toggledPinOnCurrentPress
                    && eventTime - self.pressBeganAt <= self.doubleTapInterval
                self.lastTapReleasedAt = wasQuickTap ? eventTime : nil
                self.toggledPinOnCurrentPress = false
                DispatchQueue.main.async { self.callback(.released) }
            }
        }
    }

    private func scheduleShow() {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.commandIsDown, !self.shortcutWasPressed else { return }
            DispatchQueue.main.async { self.callback(.holdBegan) }
        }
        workItem = item
        stateQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
