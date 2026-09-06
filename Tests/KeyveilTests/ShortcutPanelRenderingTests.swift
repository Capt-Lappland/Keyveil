import AppKit
import SwiftUI
import XCTest
@testable import Keyveil

@MainActor
final class ShortcutPanelRenderingTests: XCTestCase {
    func testShortcutPanelRendersAtStandardAndCompactSizes() throws {
        let state = makeState()
        state.loadPreviewData()
        state.beginShortcutPresentation()

        let standard = try render(state: state, size: NSSize(width: 1_180, height: 720), colorScheme: .light)
        let compact = try render(state: state, size: NSSize(width: 760, height: 520), colorScheme: .light)
        let dark = try render(state: state, size: NSSize(width: 1_180, height: 720), colorScheme: .dark)

        XCTAssertGreaterThan(standard.count, 10_000)
        XCTAssertGreaterThan(compact.count, 10_000)
        XCTAssertGreaterThan(dark.count, 10_000)
        try writeSnapshotIfRequested(standard, name: "keyveil-shortcuts-standard.png")
        try writeSnapshotIfRequested(compact, name: "keyveil-shortcuts-compact.png")
        try writeSnapshotIfRequested(dark, name: "keyveil-shortcuts-dark.png")
    }

    func testPermissionPanelRendersWithoutRequestingSystemAccess() throws {
        let state = makeState(accessibilityGranted: false, inputMonitoringGranted: false)
        state.isPermissionPromptVisible = true

        let snapshot = try render(state: state, size: NSSize(width: 760, height: 520), colorScheme: .light)

        XCTAssertGreaterThan(snapshot.count, 10_000)
        try writeSnapshotIfRequested(snapshot, name: "keyveil-permissions.png")
    }

    func testSettingsPanesRenderInLightAndDarkAppearances() throws {
        let state = makeState(accessibilityGranted: false, inputMonitoringGranted: true)
        let general = try renderSettings(state: state, selectedPane: "general", colorScheme: .light)
        let permissions = try renderSettings(state: state, selectedPane: "permissions", colorScheme: .dark)

        XCTAssertGreaterThan(general.count, 10_000)
        XCTAssertGreaterThan(permissions.count, 10_000)
        try writeSnapshotIfRequested(general, name: "keyveil-settings-general.png")
        try writeSnapshotIfRequested(permissions, name: "keyveil-settings-permissions.png")
    }

    func testLargeShortcutDatasetRenders() throws {
        let state = makeState()
        state.applicationName = "Stress Test"
        state.groups = (0..<24).map { groupIndex in
            ShortcutGroup(
                title: "Menu Group \(groupIndex)",
                shortcuts: (0..<40).map { itemIndex in
                    ShortcutItem(
                        title: "A deliberately long localized command title \(itemIndex)",
                        keys: ["⌃", "⌥", "⇧", "⌘", "Space"],
                        path: "Stress/\(groupIndex)"
                    )
                }
            )
        }
        state.beginShortcutPresentation()

        let snapshot = try render(
            state: state,
            size: NSSize(width: 1_180, height: 720),
            colorScheme: .dark
        )

        XCTAssertGreaterThan(snapshot.count, 10_000)
        try writeSnapshotIfRequested(snapshot, name: "keyveil-shortcuts-stress.png")
    }

    func testOverlayPanelHandlesEscapeBeforeSwiftUIFocusRouting() {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var didHandleEscape = false
        panel.onEscape = { didHandleEscape = true }
        let escapeEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )

        XCTAssertNotNil(escapeEvent)
        if let escapeEvent {
            panel.sendEvent(escapeEvent)
        }
        XCTAssertTrue(didHandleEscape)
    }

    private func render(state: AppState, size: NSSize, colorScheme: ColorScheme) throws -> Data {
        try renderView(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                ShortcutPanelView()
                    .environmentObject(state)
            },
            size: size,
            colorScheme: colorScheme
        )
    }

    private func renderSettings(
        state: AppState,
        selectedPane: String,
        colorScheme: ColorScheme
    ) throws -> Data {
        UserDefaults.standard.set(selectedPane, forKey: "selectedSettingsPane")
        return try renderView(
            SettingsView()
                .environmentObject(state),
            size: NSSize(width: 640, height: selectedPane == "permissions" ? 510 : 540),
            colorScheme: colorScheme
        )
    }

    private func renderView<Content: View>(
        _ content: Content,
        size: NSSize,
        colorScheme: ColorScheme
    ) throws -> Data {
        let hostingView = NSHostingView(
            rootView: content.environment(\.colorScheme, colorScheme)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SnapshotError.bitmapCreationFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }
        return data
    }

    private func writeSnapshotIfRequested(_ data: Data, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["KEYVEIL_SNAPSHOT_DIR"] else { return }
        let outputURL = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name)
        try data.write(to: outputURL, options: .atomic)
    }

    private func makeState(
        accessibilityGranted: Bool = true,
        inputMonitoringGranted: Bool = true
    ) -> AppState {
        AppState(
            shortcutProvider: EmptyShortcutProvider(),
            accessibilityCheck: { accessibilityGranted },
            inputMonitoringCheck: { inputMonitoringGranted }
        )
    }
}

private struct EmptyShortcutProvider: ShortcutProviding {
    func shortcuts(for processID: pid_t) -> [ShortcutGroup]? { [] }
}

private enum SnapshotError: Error {
    case bitmapCreationFailed
    case pngEncodingFailed
}
