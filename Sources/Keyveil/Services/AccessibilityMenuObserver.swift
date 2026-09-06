import ApplicationServices
import Foundation

@MainActor
final class AccessibilityMenuObserver: @unchecked Sendable {
    private var observer: AXObserver?
    private var observedElements: [AXUIElement] = []
    private var observedProcessID: pid_t?
    private var onChange: (@MainActor @Sendable (pid_t) -> Void)?
    private var menuBarDiscoveryTask: Task<Void, Never>?
    private var registrationCount = 0

    func observe(
        processID: pid_t,
        onChange: @escaping @MainActor @Sendable (pid_t) -> Void
    ) {
        if observedProcessID == processID, observer != nil {
            self.onChange = onChange
            return
        }

        stop()

        var newObserver: AXObserver?
        let result = AXObserverCreate(
            processID,
            { _, _, _, context in
                guard let context else { return }
                let menuObserver = Unmanaged<AccessibilityMenuObserver>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                Task { @MainActor in
                    menuObserver.emitChange()
                }
            },
            &newObserver
        )
        guard result == .success, let newObserver else {
            Diagnostics.shortcutScan.debug("Menu observation is unavailable for the active app")
            return
        }

        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 1)
        observer = newObserver
        observedProcessID = processID
        self.onChange = onChange
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
        register(
            element: application,
            notifications: [
                kAXMenuOpenedNotification as CFString,
                kAXMenuClosedNotification as CFString
            ]
        )
        discoverAndRegisterMenuBar(for: processID)
    }

    func stop() {
        menuBarDiscoveryTask?.cancel()
        menuBarDiscoveryTask = nil
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        observedElements = []
        observedProcessID = nil
        onChange = nil
        registrationCount = 0
    }

    private func emitChange() {
        guard let observedProcessID else { return }
        onChange?(observedProcessID)
    }

    private func discoverAndRegisterMenuBar(for processID: pid_t) {
        menuBarDiscoveryTask = Task { @MainActor [weak self] in
            let menuBar = await Task.detached(priority: .utility) { () -> SendableAXElement? in
                let application = AXUIElementCreateApplication(processID)
                AXUIElementSetMessagingTimeout(application, 1)
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    application,
                    kAXMenuBarAttribute as CFString,
                    &value
                ) == .success,
                      let value,
                      CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
                return SendableAXElement(value: value as! AXUIElement)
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.observedProcessID == processID else { return }

            if let menuBar {
                self.register(
                    element: menuBar.value,
                    notifications: [
                        kAXLayoutChangedNotification as CFString,
                        kAXCreatedNotification as CFString,
                        kAXValueChangedNotification as CFString,
                        kAXUIElementDestroyedNotification as CFString
                    ]
                )
            }

            if self.registrationCount > 0 {
                Diagnostics.shortcutScan.debug("Observing active-app menu changes")
            } else {
                Diagnostics.shortcutScan.debug(
                    "The active app does not expose menu change notifications"
                )
            }
            self.menuBarDiscoveryTask = nil
        }
    }

    private func register(element: AXUIElement, notifications: [CFString]) {
        guard let observer else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        var didRegisterElement = false

        for notification in notifications {
            let result = AXObserverAddNotification(
                observer,
                element,
                notification,
                context
            )
            if result == .success || result == .notificationAlreadyRegistered {
                registrationCount += 1
                didRegisterElement = true
            }
        }

        if didRegisterElement {
            observedElements.append(element)
        }
    }
}

private struct SendableAXElement: @unchecked Sendable {
    let value: AXUIElement
}
