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

        let standardSize = NSSize(width: 1_180, height: 720)
        let compactSize = NSSize(width: 760, height: 520)
        let standard = try render(state: state, size: standardSize, colorScheme: .light)
        let compact = try render(state: state, size: compactSize, colorScheme: .light)
        let dark = try render(state: state, size: standardSize, colorScheme: .dark)

        try assertRenderedSnapshot(standard, expectedSize: standardSize)
        try assertRenderedSnapshot(compact, expectedSize: compactSize)
        try assertRenderedSnapshot(dark, expectedSize: standardSize)
        try writeSnapshotIfRequested(standard, name: "keyveil-shortcuts-standard.png")
        try writeSnapshotIfRequested(compact, name: "keyveil-shortcuts-compact.png")
        try writeSnapshotIfRequested(dark, name: "keyveil-shortcuts-dark.png")
    }

    func testPermissionPanelRendersWithoutRequestingSystemAccess() throws {
        let state = makeState(accessibilityGranted: false, inputMonitoringGranted: false)
        state.isPermissionPromptVisible = true

        let size = NSSize(width: 760, height: 520)
        let snapshot = try render(state: state, size: size, colorScheme: .light)

        try assertRenderedSnapshot(snapshot, expectedSize: size)
        try writeSnapshotIfRequested(snapshot, name: "keyveil-permissions.png")
    }

    func testPinnedPanelRendersKeyboardNavigationGuidanceAtCompactSize() throws {
        let state = makeState()
        state.loadPreviewData()
        state.isPinned = true
        state.beginShortcutPresentation()

        let size = NSSize(width: 760, height: 520)
        let snapshot = try render(state: state, size: size, colorScheme: .light)

        try assertRenderedSnapshot(snapshot, expectedSize: size)
        try writeSnapshotIfRequested(snapshot, name: "keyveil-shortcuts-pinned-compact.png")
    }

    func testRetryableShortcutFailuresRender() async throws {
        let size = NSSize(width: 760, height: 520)
        let timeoutState = makeState(shortcutResult: .timedOut([]))
        timeoutState.updateApplication(
            name: "Unresponsive App",
            icon: nil,
            processID: 301,
            bundleIdentifier: "test.timeout.render"
        )
        timeoutState.loadShortcuts()
        await waitUntil { !timeoutState.isLoading }

        let unavailableState = makeState(shortcutResult: .unavailable)
        unavailableState.updateApplication(
            name: "Unavailable App",
            icon: nil,
            processID: 302,
            bundleIdentifier: "test.unavailable.render"
        )
        unavailableState.loadShortcuts()
        await waitUntil { !unavailableState.isLoading }

        let timeout = try render(state: timeoutState, size: size, colorScheme: .light)
        let unavailable = try render(state: unavailableState, size: size, colorScheme: .dark)

        try assertRenderedSnapshot(timeout, expectedSize: size)
        try assertRenderedSnapshot(unavailable, expectedSize: size)
        XCTAssertNotEqual(timeout, unavailable)
        try writeSnapshotIfRequested(timeout, name: "keyveil-shortcuts-timeout.png")
        try writeSnapshotIfRequested(unavailable, name: "keyveil-shortcuts-unavailable.png")
    }

    func testSettingsPanesRenderInLightAndDarkAppearances() throws {
        let state = makeState(
            accessibilityGranted: false,
            inputMonitoringGranted: true,
            loginItemStatus: .requiresApproval
        )
        let generalSize = NSSize(width: 640, height: 720)
        let permissionsSize = NSSize(width: 640, height: 540)
        let generalLight = try renderSettings(
            state: state,
            selectedPane: "general",
            size: generalSize,
            colorScheme: .light
        )
        let generalDark = try renderSettings(
            state: state,
            selectedPane: "general",
            size: generalSize,
            colorScheme: .dark
        )
        let permissionsLight = try renderSettings(
            state: state,
            selectedPane: "permissions",
            size: permissionsSize,
            colorScheme: .light
        )
        let permissionsDark = try renderSettings(
            state: state,
            selectedPane: "permissions",
            size: permissionsSize,
            colorScheme: .dark
        )

        try assertRenderedSnapshot(generalLight, expectedSize: generalSize)
        try assertRenderedSnapshot(generalDark, expectedSize: generalSize)
        try assertRenderedSnapshot(permissionsLight, expectedSize: permissionsSize)
        try assertRenderedSnapshot(permissionsDark, expectedSize: permissionsSize)
        XCTAssertNotEqual(generalLight, generalDark)
        XCTAssertNotEqual(permissionsLight, permissionsDark)
        try writeSnapshotIfRequested(generalLight, name: "keyveil-settings-general-light.png")
        try writeSnapshotIfRequested(generalDark, name: "keyveil-settings-general-dark.png")
        try writeSnapshotIfRequested(permissionsLight, name: "keyveil-settings-permissions-light.png")
        try writeSnapshotIfRequested(permissionsDark, name: "keyveil-settings-permissions-dark.png")
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

        try assertRenderedSnapshot(snapshot, expectedSize: NSSize(width: 1_180, height: 720))
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
        size: NSSize,
        colorScheme: ColorScheme
    ) throws -> Data {
        let defaults = UserDefaults.standard
        let previousPane = defaults.object(forKey: "selectedSettingsPane")
        defaults.set(selectedPane, forKey: "selectedSettingsPane")
        defer {
            if let previousPane {
                defaults.set(previousPane, forKey: "selectedSettingsPane")
            } else {
                defaults.removeObject(forKey: "selectedSettingsPane")
            }
        }

        return try renderView(
            SettingsView()
                .environmentObject(state),
            size: size,
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
        inputMonitoringGranted: Bool = true,
        loginItemStatus: LoginItemStatus = .disabled,
        shortcutResult: ShortcutScanResult = .success([])
    ) -> AppState {
        AppState(
            shortcutProvider: FixedShortcutProvider(result: shortcutResult),
            accessibilityCheck: { accessibilityGranted },
            inputMonitoringCheck: { inputMonitoringGranted },
            loginItemClient: LoginItemClient(
                status: { loginItemStatus },
                setEnabled: { _ in },
                openSystemSettings: {}
            )
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous state", file: file, line: line)
    }

    private func assertRenderedSnapshot(
        _ data: Data,
        expectedSize: NSSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertGreaterThan(data.count, 10_000, file: file, line: line)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data), file: file, line: line)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(expectedSize.width), file: file, line: line)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, Int(expectedSize.height), file: file, line: line)

        let expectedAspectRatio = expectedSize.width / expectedSize.height
        let actualAspectRatio = CGFloat(bitmap.pixelsWide) / CGFloat(bitmap.pixelsHigh)
        XCTAssertEqual(actualAspectRatio, expectedAspectRatio, accuracy: 0.01, file: file, line: line)

        var sampledColors = Set<UInt32>()
        let xStep = max(bitmap.pixelsWide / 24, 1)
        let yStep = max(bitmap.pixelsHigh / 24, 1)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let red = UInt32((color.redComponent * 255).rounded())
                let green = UInt32((color.greenComponent * 255).rounded())
                let blue = UInt32((color.blueComponent * 255).rounded())
                let alpha = UInt32((color.alphaComponent * 255).rounded())
                sampledColors.insert((red << 24) | (green << 16) | (blue << 8) | alpha)
            }
        }
        XCTAssertGreaterThan(sampledColors.count, 8, "Snapshot appears blank", file: file, line: line)
    }
}

private struct FixedShortcutProvider: ShortcutProviding {
    let result: ShortcutScanResult

    func shortcuts(for processID: pid_t) -> ShortcutScanResult { result }
}

private enum SnapshotError: Error {
    case bitmapCreationFailed
    case pngEncodingFailed
}
