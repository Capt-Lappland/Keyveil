import AppKit
import CoreGraphics

final class CommandHoldMonitor: @unchecked Sendable {
    var delay: TimeInterval

    private let stateQueue = DispatchQueue(label: "app.keyveil.command-monitor")
    private var callback: (Bool) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workItem: DispatchWorkItem?
    private var commandIsDown = false
    private var shortcutWasPressed = false

    init(delay: TimeInterval, callback: @escaping (Bool) -> Void) {
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
        let commandFlagIsSet = event.flags.contains(.maskCommand)

        stateQueue.async { [weak self] in
            guard let self else { return }

            if type == .keyDown, self.commandIsDown {
                self.shortcutWasPressed = true
                self.workItem?.cancel()
                self.workItem = nil
                DispatchQueue.main.async { self.callback(false) }
                return
            }

            guard type == .flagsChanged else { return }
            let isDown = commandFlagIsSet

            if isDown, !self.commandIsDown {
                self.commandIsDown = true
                self.shortcutWasPressed = false
                self.scheduleShow()
            } else if !isDown, self.commandIsDown {
                self.commandIsDown = false
                self.workItem?.cancel()
                self.workItem = nil
                DispatchQueue.main.async { self.callback(false) }
            }
        }
    }

    private func scheduleShow() {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.commandIsDown, !self.shortcutWasPressed else { return }
            DispatchQueue.main.async { self.callback(true) }
        }
        workItem = item
        stateQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
