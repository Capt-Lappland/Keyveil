import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var panelController: ShortcutPanelController?
    private var commandMonitor: CommandHoldMonitor?
    private var statusItem: NSStatusItem?
    private var workspaceObserver: NSObjectProtocol?
    private var permissionPollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let isPreviewMode = CommandLine.arguments.contains("--preview")
    private let isPermissionPreviewMode = CommandLine.arguments.contains("--preview-permissions")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = ShortcutPanelController(appState: appState)
        configureStatusItem()
        if !isPreviewMode, !isPermissionPreviewMode {
            startCommandMonitor()
        }

        if isPermissionPreviewMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.panelController?.showPermissionPrompt()
            }
        } else if isPreviewMode {
            appState.loadPreviewData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.panelController?.show(pinned: true)
            }
        } else {
            observeFrontmostApplication()
            refreshCurrentApplication()

            if !appState.hasRequiredPermissions {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                    self?.panelController?.showPermissionPrompt()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        commandMonitor?.stop()
        permissionPollTimer?.invalidate()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appState.refreshPermissionStatus()
        if appState.hasRequiredPermissions {
            if commandMonitor?.start() == true {
                stopPermissionPolling()
            } else {
                startPermissionPolling()
            }
        } else if !isPreviewMode, !isPermissionPreviewMode, !appState.isPermissionPromptVisible {
            startPermissionPolling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.appState.hasRequiredPermissions else { return }
                self.panelController?.showPermissionPrompt()
            }
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Keyveil")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Keyveil", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Shortcuts", action: #selector(refreshShortcuts), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Input Monitoring Settings…", action: #selector(openInputMonitoringSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Keyveil", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func observeFrontmostApplication() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.appState.refreshPermissionStatus()
                if self.appState.hasRequiredPermissions {
                    if self.commandMonitor?.start() == true {
                        self.stopPermissionPolling()
                    }
                } else {
                    self.startPermissionPolling()
                }
                self.refreshCurrentApplication()
                if self.panelController?.isPinned == true {
                    self.appState.loadShortcuts()
                }
            }
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
                    if !self.appState.isPermissionPromptVisible {
                        self.panelController?.hide()
                    }
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
        guard !isPreviewMode, !isPermissionPreviewMode, permissionPollTimer == nil else { return }

        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.appState.refreshPermissionStatus()
                let monitorStarted = self.commandMonitor?.start() == true
                if self.appState.hasRequiredPermissions, monitorStarted {
                    self.stopPermissionPolling()
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
    }

    private func presentForCurrentApplication(pinned: Bool) {
        refreshCurrentApplication()

        guard appState.hasRequiredPermissions else {
            panelController?.showPermissionPrompt()
            return
        }

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

    @objc private func openAccessibilitySettings() {
        appState.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringSettings() {
        appState.openInputMonitoringSettings()
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
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
    }

    func show(pinned: Bool) {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        centerOnActiveScreen(preferredSize: NSSize(width: 1180, height: 720))
        appState.isPermissionPromptVisible = false
        appState.isPinned = pinned
        appState.beginShortcutPresentation()
        panel.alphaValue = 0

        if pinned {
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            if frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previouslyActiveApplication = frontmostApplication
            }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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

    func showPermissionPrompt() {
        transitionGeneration &+= 1
        panel.level = .normal
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.hidesOnDeactivate = true
        centerOnActiveScreen(preferredSize: NSSize(width: 760, height: 520))
        appState.isPermissionPromptVisible = true
        appState.isPinned = false
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }
}
