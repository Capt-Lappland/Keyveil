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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = ShortcutPanelController(appState: appState)
        configureStatusItem()
        startCommandMonitor()

        if isPreviewMode {
            appState.loadPreviewData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.panelController?.show()
            }
        } else {
            observeFrontmostApplication()
            refreshCurrentApplication()

            if !appState.isAccessibilityGranted {
                appState.requestAccessibilityAccess()
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

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Keyveil")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Keyveil", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Shortcuts", action: #selector(refreshShortcuts), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: ""))
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
                self?.refreshCurrentApplication()
            }
        }
    }

    private func startCommandMonitor() {
        let monitor = CommandHoldMonitor(delay: appState.holdDelay) { [weak self] isHeld in
            Task { @MainActor in
                guard let self else { return }
                if isHeld {
                    self.presentForCurrentApplication()
                } else {
                    self.panelController?.hide()
                }
            }
        }
        monitor.start()
        commandMonitor = monitor

        appState.$holdDelay
            .dropFirst()
            .sink { [weak self] delay in
                self?.commandMonitor?.delay = delay
            }
            .store(in: &cancellables)
    }

    private func refreshCurrentApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        appState.updateApplication(application)
    }

    private func presentForCurrentApplication() {
        refreshCurrentApplication()

        guard appState.isAccessibilityGranted else {
            appState.requestAccessibilityAccess()
            panelController?.showPermissionPrompt()
            return
        }

        appState.loadShortcuts()
        panelController?.show()
    }

    @objc private func showPanel() {
        presentForCurrentApplication()
    }

    @objc private func refreshShortcuts() {
        refreshCurrentApplication()
        appState.loadShortcuts()
    }

    @objc private func openAccessibilitySettings() {
        appState.openAccessibilitySettings()
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

    init(appState: AppState) {
        self.appState = appState
        hostingView = NSHostingView(rootView: AnyView(ShortcutPanelView().environmentObject(appState)))
        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
    }

    func show() {
        centerOnActiveScreen()
        appState.isPermissionPromptVisible = false
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func showPermissionPrompt() {
        centerOnActiveScreen()
        appState.isPermissionPromptVisible = true
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            DispatchQueue.main.async {
                panel?.orderOut(nil)
            }
        })
        appState.isPermissionPromptVisible = false
    }

    private func centerOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let width = min(940, visibleFrame.width - 80)
        let height = min(560, visibleFrame.height - 80)
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
