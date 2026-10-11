import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var panelController: ShortcutPanelController?
    private var commandMonitor: CommandHoldMonitor?
    private var settingsPresenter: SettingsPresenter!
    private var permissionSetup: PermissionSetupWindowController!
    private var statusItem: NSStatusItem?
    private var permissionSetupMenuItem: NSMenuItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var observers: [NSObjectProtocol] = []
    private var permissionPollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastPermissionState: PermissionState?
    private let accessibilityMenuObserver = AccessibilityMenuObserver()
    private let menuRefreshDebouncer = DebouncedAction(delay: .milliseconds(350))
    private let runtimeRecoveryDebouncer = DebouncedAction(delay: .milliseconds(180))
    private let isPreviewMode = CommandLine.arguments.contains("--preview")
    private let isPermissionPreviewMode = CommandLine.arguments.contains("--preview-permissions")
    private let isSettingsPreviewMode = CommandLine.arguments.contains("--preview-settings")

    private struct PermissionState: Equatable {
        let accessibility: Bool
        let inputMonitoring: Bool
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.lifecycle.notice("Keyveil finished launching")
        NSApp.setActivationPolicy(.accessory)

        closePlaceholderScenes()

        panelController = ShortcutPanelController(appState: appState)
        settingsPresenter = SettingsPresenter(appState: appState)
        permissionSetup = PermissionSetupWindowController(appState: appState)
        configureStatusItem()
        if !isPreviewMode, !isPermissionPreviewMode, !isSettingsPreviewMode {
            startCommandMonitor()
        }

        if isSettingsPreviewMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                self.openSettings()
            }
        } else if isPermissionPreviewMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showPermissionSetup()
            }
        } else if isPreviewMode {
            appState.loadPreviewData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.panelController?.show(pinned: true)
            }
        } else {
            observeWorkspaceEvents()
            refreshCurrentApplication()

            if !appState.hasRequiredPermissions, !appState.isPermissionSetupDeferred {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                    guard let self,
                          !self.appState.hasRequiredPermissions,
                          !self.appState.isPermissionSetupDeferred else { return }
                    self.showPermissionSetup()
                }
            }
        }
    }

    /// A menu bar app lives in the status item, so losing every window is normal and
    /// must not end the process. Without this the app quit as soon as the placeholder
    /// scene was dismissed, and would also have quit whenever the user closed the
    /// preferences window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        commandMonitor?.stop()
        permissionPollTimer?.invalidate()
        accessibilityMenuObserver.stop()
        menuRefreshDebouncer.cancel()
        runtimeRecoveryDebouncer.cancel()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers = []
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appState.refreshPermissionStatus()
        appState.refreshLoginItemStatus()
        guard !isPreviewMode, !isPermissionPreviewMode, !isSettingsPreviewMode else { return }

        if appState.hasRequiredPermissions {
            if commandMonitor?.start() == true {
                stopPermissionPolling()
                observeCurrentApplicationMenu()
            } else {
                startPermissionPolling()
            }
        } else if !isPreviewMode,
                  !isPermissionPreviewMode,
                  !appState.isPermissionPromptVisible,
                  !appState.isPermissionSetupDeferred {
            startPermissionPolling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self,
                      !self.appState.hasRequiredPermissions,
                      !self.appState.isPermissionSetupDeferred else { return }
                self.showPermissionSetup()
            }
        }
    }

    /// Dismisses the empty scene SwiftUI requires the app to declare.
    ///
    /// SwiftUI will not build an `App` with no scenes, but Keyveil's interface is the
    /// status item, so that placeholder must never be seen — and SwiftUI re-shows it
    /// well after launch, so a launch-time sweep is not enough and a timed one only
    /// moves the problem. It is dismissed whenever it appears instead, and also when
    /// the app is activated or reopened, which is when AppKit would surface it.
    private func closePlaceholderScenes() {
        for name in [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didUpdateNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification
        ] {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.closeWindowsThatAreNotOurs()
                    }
                }
            )
        }
    }

    /// Anything that is not a window this app owns is not ours to show.
    private func closeWindowsThatAreNotOurs() {
        var owned: Set<ObjectIdentifier> = []
        if let panel = panelController?.window { owned.insert(ObjectIdentifier(panel)) }
        if let preferences = settingsPresenter?.window { owned.insert(ObjectIdentifier(preferences)) }
        if let setup = permissionSetup?.window { owned.insert(ObjectIdentifier(setup)) }

        for window in NSApp.windows where !owned.contains(ObjectIdentifier(window)) {
            window.orderOut(nil)
            window.close()
        }
    }

    /// AppKit surfaces a window when the app is reopened; the status item is enough.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        closeWindowsThatAreNotOurs()
        return false
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Keyveil")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.string("menu.show"), action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.string("menu.refresh"), action: #selector(refreshShortcuts), keyEquivalent: "r"))
        let setupItem = NSMenuItem(
            title: L10n.string("menu.complete_setup"),
            action: #selector(showPermissionSetup),
            keyEquivalent: ""
        )
        permissionSetupMenuItem = setupItem
        menu.addItem(setupItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.string("menu.open_accessibility"), action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.string("menu.open_input_monitoring"), action: #selector(openInputMonitoringSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.string("menu.settings"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.string("menu.quit"), action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        updatePermissionAppearance()

        appState.$permissionRevision
            .sink { [weak self] _ in
                self?.updatePermissionAppearance()
            }
            .store(in: &cancellables)
    }

    private func updatePermissionAppearance() {
        let permissionState = PermissionState(
            accessibility: appState.isAccessibilityGranted,
            inputMonitoring: appState.isInputMonitoringGranted
        )
        let hasRequiredPermissions = permissionState.accessibility && permissionState.inputMonitoring

        statusItem?.button?.contentTintColor = hasRequiredPermissions ? nil : .systemOrange
        statusItem?.button?.toolTip = hasRequiredPermissions
            ? L10n.string("menu.status.ready")
            : L10n.string("menu.status.permission_required")
        permissionSetupMenuItem?.isHidden = hasRequiredPermissions

        if permissionState != lastPermissionState {
            Diagnostics.permissions.notice(
                "Permission state changed; accessibility=\(permissionState.accessibility, privacy: .public), input-monitoring=\(permissionState.inputMonitoring, privacy: .public)"
            )
            lastPermissionState = permissionState
        }
    }

    private func observeWorkspaceEvents() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleFrontmostApplicationChange()
            }
        })

        for name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ] {
            workspaceObservers.append(notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.suspendRuntimeForSystemInterruption()
                }
            })
        }

        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            workspaceObservers.append(notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRuntimeRecovery()
                }
            })
        }
    }

    private func handleFrontmostApplicationChange() {
        appState.refreshPermissionStatus()
        if appState.hasRequiredPermissions {
            if commandMonitor?.start() == true {
                stopPermissionPolling()
            }
        } else {
            startPermissionPolling()
        }
        refreshCurrentApplication()
        if panelController?.isPinned == true {
            appState.loadShortcuts()
        }
    }

    private func suspendRuntimeForSystemInterruption() {
        Diagnostics.lifecycle.notice("Suspending runtime monitors for a system interruption")
        runtimeRecoveryDebouncer.cancel()
        menuRefreshDebouncer.cancel()
        accessibilityMenuObserver.stop()
        commandMonitor?.stop()
        stopPermissionPolling()
        panelController?.hide(force: true)
    }

    private func scheduleRuntimeRecovery() {
        runtimeRecoveryDebouncer.schedule { [weak self] in
            self?.recoverRuntimeAfterSystemInterruption()
        }
    }

    private func recoverRuntimeAfterSystemInterruption() {
        appState.refreshPermissionStatus()
        refreshCurrentApplication()

        let monitorStarted = appState.hasRequiredPermissions
            && commandMonitor?.restart() == true
        if monitorStarted {
            stopPermissionPolling()
            observeCurrentApplicationMenu()
            Diagnostics.lifecycle.notice("Runtime monitors recovered after a system interruption")
        } else {
            accessibilityMenuObserver.stop()
            startPermissionPolling()
            Diagnostics.lifecycle.warning("Runtime recovery is waiting for permission")
        }
    }

    private func startCommandMonitor() {
        let monitor = CommandHoldMonitor(delay: appState.holdDelay) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event {
                case .holdBegan:
                    if self.panelController?.isPinned != true {
                        self.presentForCurrentApplication(pinned: false)
                    }
                case .released:
                    self.panelController?.hide()
                case .togglePin:
                    if self.panelController?.isPinned == true {
                        self.panelController?.hide(force: true)
                    } else {
                        self.presentForCurrentApplication(pinned: true)
                    }
                }
            }
        }
        commandMonitor = monitor
        if !monitor.start() || !appState.hasRequiredPermissions {
            Diagnostics.permissions.warning("Global Command monitor is waiting for permission")
            startPermissionPolling()
        }

        appState.$holdDelay
            .dropFirst()
            .sink { [weak self] delay in
                self?.commandMonitor?.updateDelay(delay)
            }
            .store(in: &cancellables)
    }

    private func startPermissionPolling() {
        guard !isPreviewMode,
              !isPermissionPreviewMode,
              !isSettingsPreviewMode,
              permissionPollTimer == nil else { return }

        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.appState.refreshPermissionStatus()
                let monitorStarted = self.commandMonitor?.start() == true
                if self.appState.hasRequiredPermissions, monitorStarted {
                    self.stopPermissionPolling()
                    self.observeCurrentApplicationMenu()
                }
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func refreshCurrentApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        appState.updateApplication(application)
        observeCurrentApplicationMenu()
    }

    private func observeCurrentApplicationMenu() {
        guard appState.isAccessibilityGranted, appState.applicationPID > 0 else {
            accessibilityMenuObserver.stop()
            return
        }

        accessibilityMenuObserver.observe(processID: appState.applicationPID) { [weak self] processID in
            self?.scheduleShortcutRefresh(afterMenuChangeFor: processID)
        }
    }

    private func scheduleShortcutRefresh(afterMenuChangeFor processID: pid_t) {
        guard processID == appState.applicationPID else { return }
        menuRefreshDebouncer.schedule { [weak self] in
            guard let self, processID == self.appState.applicationPID else { return }
            if self.panelController?.isPinned == true {
                self.appState.loadShortcuts(forceRefresh: true)
            } else {
                self.appState.invalidateShortcutCache(for: processID)
            }
        }
    }

    private func presentForCurrentApplication(pinned: Bool) {
        refreshCurrentApplication()

        guard appState.hasRequiredPermissions else {
            Diagnostics.presentation.notice("Presenting permission setup instead of shortcuts")
            showPermissionSetup()
            return
        }

        Diagnostics.presentation.debug("Presenting shortcut panel; pinned=\(pinned, privacy: .public)")
        appState.loadShortcuts()
        panelController?.show(pinned: pinned)
    }

    @objc private func showPanel() {
        presentForCurrentApplication(pinned: true)
    }

    @objc private func refreshShortcuts() {
        refreshCurrentApplication()
        appState.loadShortcuts(forceRefresh: true)
    }

    @objc private func showPermissionSetup() {
        appState.resumePermissionSetup()
        permissionSetup.show()
    }

    @objc private func openAccessibilitySettings() {
        appState.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringSettings() {
        appState.openInputMonitoringSettings()
    }

    @objc private func openSettings() {
        settingsPresenter.present()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class SettingsPresenter {
    private let appState: AppState

    /// The preferences window, once it has been built.
    private(set) var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Brings the window up, and verifies it actually came up.
    ///
    /// The old version deferred to the `showSettingsWindow:` selector and trusted
    /// its return value. That value says only that *some* responder accepted the
    /// action, not that a window appeared — and with a SwiftUI `Settings` scene the
    /// window was created but never ordered on screen, so the menu item silently did
    /// nothing while reporting success. The window is owned here now, and
    /// presentation is confirmed rather than assumed.
    func present() {
        let window = makeWindow()
        if !window.isVisible {
            window.center()
        }

        // Activate first, then order the window front. Ordering first let the window
        // open behind whatever app was active, which looks exactly like the menu item
        // doing nothing.
        activateApp()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        if !window.isVisible {
            Diagnostics.lifecycle.warning("The preferences window did not come to the front")
        }
    }

    @discardableResult
    func makeWindow() -> NSWindow {
        if let window { return window }

        let settingsWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.preferredSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = L10n.string("settings.window_title")
        settingsWindow.isReleasedWhenClosed = false
        // Same reasoning as the setup window: a plain hosting view in a fixed frame,
        // so AppKit owns the window size and SwiftUI has nothing to negotiate.
        let host = NSHostingView(rootView: SettingsView().environmentObject(appState))
        host.frame = NSRect(origin: .zero, size: SettingsView.preferredSize)
        host.autoresizingMask = [.width, .height]
        settingsWindow.contentView = host
        settingsWindow.setContentSize(SettingsView.preferredSize)
        settingsWindow.center()
        window = settingsWindow
        return settingsWindow
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
final class ShortcutPanelController {
    private let panel: OverlayPanel
    private let appState: AppState
    private let hostingView: NSHostingView<AnyView>
    private var transitionGeneration = 0
    private var previouslyActiveApplication: NSRunningApplication?

    var isPinned: Bool { appState.isPinned }

    /// The overlay panel, so callers can tell it apart from other windows.
    var window: NSWindow { panel }

    init(appState: AppState) {
        self.appState = appState
        hostingView = NSHostingView(rootView: AnyView(ShortcutPanelView().environmentObject(appState)))
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // A borderless transparent panel receives a rectangular AppKit shadow.
        // It clashes with the rounded glass surface and can look like a black rim.
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        appState.dismissOverlay = { [weak self] in
            self?.hide(force: true)
        }
        panel.onEscape = { [weak self] in
            self?.hide(force: true)
        }
        panel.onScrollCommand = { [weak appState] command in
            guard let appState, appState.isPinned else { return false }
            appState.requestShortcutScroll(command)
            return true
        }
    }

    func show(pinned: Bool) {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        centerOnActiveScreen(preferredSize: NSSize(width: 1180, height: 720))
        appState.isPinned = pinned
        appState.beginShortcutPresentation()
        panel.alphaValue = 0

        if pinned {
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            if frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previouslyActiveApplication = frontmostApplication
            }
            // `makeKeyAndOrderFront` is enough for keyboard browsing: the panel is
            // a nonactivating panel, so it takes key focus without Keyveil becoming
            // the active application. Activating here would drag the user out of
            // the app they were working in, which is the opposite of what a peek
            // at shortcuts should cost them.
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        let animationDuration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.transitionGeneration == generation else { return }
                self.panel.alphaValue = 1
            }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self, self.transitionGeneration == generation, self.panel.isVisible else { return }
            self.panel.alphaValue = 1
        }
    }

    func hide(force: Bool = false) {
        guard panel.isVisible else { return }
        guard force || !appState.isPinned else { return }

        transitionGeneration &+= 1
        let generation = transitionGeneration
        let applicationToRestore = appState.isPinned ? previouslyActiveApplication : nil
        previouslyActiveApplication = nil
        appState.isPinned = false

        let animationDuration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.completeHide(generation: generation, restoring: applicationToRestore)
            }
        })
        // AppKit has occasionally failed to invoke animation completions for a
        // nonactivating panel. Keep dismissal deterministic in that case.
        DispatchQueue.main.asyncAfter(deadline: .now() + max(animationDuration + 0.06, 0.06)) { [weak self] in
            self?.completeHide(generation: generation, restoring: applicationToRestore)
        }
        appState.isPermissionPromptVisible = false
    }

    private func completeHide(generation: Int, restoring application: NSRunningApplication?) {
        guard transitionGeneration == generation, panel.isVisible else { return }
        panel.orderOut(nil)

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let keyveilIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == currentPID
        if let application,
           !application.isTerminated,
           NSApp.isActive || keyveilIsFrontmost {
            let currentApplication = NSRunningApplication.current
            NSApp.yieldActivation(to: application)
            application.activate(from: currentApplication, options: [])
        }
    }

    private func centerOnActiveScreen(preferredSize: NSSize) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let width = min(preferredSize.width, visibleFrame.width - 48)
        let height = min(preferredSize.height, visibleFrame.height - 48)
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2 + 18
        )
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }
}

final class OverlayPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onScrollCommand: ((ShortcutScrollCommand) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        if !Self.isEditingText(in: self),
           let command = Self.shortcutScrollCommand(for: event),
           onScrollCommand?(command) == true {
            return
        }
        super.sendEvent(event)
    }

    /// While the search field owns the field editor, arrow keys have to move the
    /// insertion point and Page Up/Down has to move through the query. Taking
    /// those keys for the wall would make the field impossible to edit.
    ///
    /// AppKit's field editor is itself an `NSTextView`, and the overlay contains
    /// no other text input, so the responder check is exact here.
    static func isEditingText(in window: NSWindow) -> Bool {
        window.firstResponder is NSTextView
    }

    static func shortcutScrollCommand(for event: NSEvent) -> ShortcutScrollCommand? {
        guard event.type == .keyDown else { return nil }
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return nil }

        return switch event.keyCode {
        case 126: .lineUp
        case 125: .lineDown
        case 116: .pageUp
        case 121: .pageDown
        case 115: .home
        case 119: .end
        default: nil
        }
    }
}
