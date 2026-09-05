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
    private var cancellables = Set<AnyCancellable>()
    private let isPreviewMode = CommandLine.arguments.contains("--preview")
    private let isPermissionPreviewMode = CommandLine.arguments.contains("--preview-permissions")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = ShortcutPanelController(appState: appState)
        configureStatusItem()
        startCommandMonitor()

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
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appState.refreshPermissionStatus()
        if appState.hasRequiredPermissions {
            commandMonitor?.start()
        } else if !isPreviewMode, !isPermissionPreviewMode, !appState.isPermissionPromptVisible {
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
                    self.commandMonitor?.start()
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
        monitor.start()
        commandMonitor = monitor

        appState.$holdDelay
            .dropFirst()
            .sink { [weak self] delay in
                self?.commandMonitor?.updateDelay(delay)
            }
            .store(in: &cancellables)
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
    }

    func show(pinned: Bool) {
        transitionGeneration &+= 1
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        centerOnActiveScreen(preferredSize: NSSize(width: 1180, height: 720))
        appState.isPermissionPromptVisible = false
        appState.isPinned = pinned
        panel.alphaValue = 0

        if pinned {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
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
        appState.isPinned = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.transitionGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        })
        appState.isPermissionPromptVisible = false
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
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
