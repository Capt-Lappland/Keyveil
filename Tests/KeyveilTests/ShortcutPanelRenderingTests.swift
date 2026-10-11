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

    func testPermissionSetupRendersEveryPermissionState() throws {
        // Onboarding is a standard window, so it renders on its own rather than as
        // part of the overlay panel. The three states are compared under one
        // appearance: what matters here is that the window tells the user where they
        // are, and the middle state — asked, still unanswered — is the one the window
        // spends most of its life in.
        let size = NSSize(width: 540, height: 500)

        func render(
            accessibility: Bool,
            inputMonitoring: Bool,
            hasRequested: Bool
        ) throws -> Data {
            let state = makeState(
                accessibilityGranted: accessibility,
                inputMonitoringGranted: inputMonitoring
            )
            if hasRequested { state.markPermissionRequestsMadeForTesting() }
            return try renderView(
                PermissionSetupView(onDismiss: {}).environmentObject(state),
                size: size,
                colorScheme: .light
            )
        }

        let fresh = try render(accessibility: false, inputMonitoring: false, hasRequested: false)
        let awaiting = try render(accessibility: false, inputMonitoring: false, hasRequested: true)
        let complete = try render(accessibility: true, inputMonitoring: true, hasRequested: false)

        // A snapshot that renders nothing would satisfy "all three differ", so
        // require actual contrast in each one before comparing them.
        for (name, data) in [("fresh", fresh), ("awaiting", awaiting), ("complete", complete)] {
            let range = try luminanceRange(of: data)
            XCTAssertGreaterThan(
                range,
                0.5,
                "\(name) rendered without enough contrast; the window may be blank"
            )
        }

        XCTAssertNotEqual(fresh, awaiting, "Requesting a permission changed nothing on screen")
        XCTAssertNotEqual(awaiting, complete)
        XCTAssertNotEqual(fresh, complete)

        try writeSnapshotIfRequested(fresh, name: "keyveil-onboarding-fresh.png")
        try writeSnapshotIfRequested(awaiting, name: "keyveil-onboarding-awaiting.png")
        try writeSnapshotIfRequested(complete, name: "keyveil-onboarding-complete.png")
    }

    /// Spread between the darkest and lightest pixel, used to catch a blank render.
    private func luminanceRange(of data: Data) throws -> Double {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        var minimum = 1.0
        var maximum = 0.0
        let xStep = max(bitmap.pixelsWide / 80, 1)
        let yStep = max(bitmap.pixelsHigh / 80, 1)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: yStep) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: xStep) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
            }
        }
        return maximum - minimum
    }

    func testWindowControllersProduceWindowsOfTheDeclaredSize() {
        // The real regression: the setup window came out 166 x 4258 on screen. Size
        // the actual windows rather than trusting the declaration.
        let state = makeState(accessibilityGranted: false, inputMonitoringGranted: false)

        let setup = PermissionSetupWindowController(appState: state).existingOrNewWindow()
        XCTAssertEqual(setup.contentLayoutRect.width, PermissionSetupView.contentSize.width, accuracy: 1)
        XCTAssertEqual(setup.contentLayoutRect.height, PermissionSetupView.contentSize.height, accuracy: 1)
        setup.orderOut(nil)

        let presenter = SettingsPresenter(appState: state)
        let settings = presenter.makeWindow()
        XCTAssertEqual(settings.contentLayoutRect.width, SettingsView.preferredSize.width, accuracy: 1)
        XCTAssertEqual(settings.contentLayoutRect.height, SettingsView.preferredSize.height, accuracy: 1)
        settings.orderOut(nil)
    }

    func testSetupWindowSurvivesADisplayCycle() throws {
        // The crash this guards: pinning contentMinSize and contentMaxSize on a
        // window that has a contentViewController makes the constraints
        // unsatisfiable, and AppKit throws from the display cycle during layout —
        // which aborted the app on launch.
        let state = makeState(accessibilityGranted: false, inputMonitoringGranted: false)
        let setup = PermissionSetupWindowController(appState: state).existingOrNewWindow()
        setup.makeKeyAndOrderFront(nil)
        settleRunLoop()
        XCTAssertTrue(setup.isVisible)
        setup.orderOut(nil)
    }

    func testSettingsWindowSurvivesADisplayCycle() throws {
        let state = makeState(accessibilityGranted: false, inputMonitoringGranted: false)
        let settings = SettingsPresenter(appState: state).makeWindow()
        settings.makeKeyAndOrderFront(nil)
        settleRunLoop()
        XCTAssertTrue(settings.isVisible)
        settings.orderOut(nil)
    }

    /// Runs the run loop briefly so AppKit's display cycle actually executes.
    private func settleRunLoop() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    func testWindowsAreSizedFromTheirDeclaredContentSize() {
        // A window driven by a `contentViewController` sizes itself from
        // `preferredContentSize`. Leaving it unset let AppKit choose a runaway
        // height, which rendered the setup window as a 166 x 4258 strip. Both
        // windows now declare their size, and this pins it.
        XCTAssertEqual(PermissionSetupView.contentSize.width, 560)
        XCTAssertEqual(PermissionSetupView.contentSize.height, 520)
        XCTAssertEqual(SettingsView.preferredSize.width, 660)
        XCTAssertEqual(SettingsView.preferredSize.height, 520)

        for size in [PermissionSetupView.contentSize, SettingsView.preferredSize] {
            XCTAssertGreaterThan(size.width, 400, "A settings or setup window must not be a strip")
            XCTAssertLessThan(size.height, 800, "Window height must stay a window, not a column")
        }
    }

    func testEveryPreferencesPaneRenders() throws {
        let state = makeState(
            accessibilityGranted: false,
            inputMonitoringGranted: true,
            loginItemStatus: .requiresApproval
        )
        let size = SettingsView.preferredSize

        // Every pane, so adding one cannot leave a blank screen behind.
        for pane in SettingsPane.allCases {
            let light = try renderSettings(state: state, pane: pane, size: size, colorScheme: .light)
            let dark = try renderSettings(state: state, pane: pane, size: size, colorScheme: .dark)
            try assertRenderedSnapshot(light, expectedSize: size)
            try assertRenderedSnapshot(dark, expectedSize: size)
            XCTAssertNotEqual(light, dark, "\(pane.rawValue) does not follow the appearance")
            try writeSnapshotIfRequested(light, name: "keyveil-preferences-\(pane.rawValue).png")
        }
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
        pane: SettingsPane,
        size: NSSize,
        colorScheme: ColorScheme
    ) throws -> Data {
        try renderView(
            SettingsView(initialPane: pane)
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

    /// The overlay sits on top of whatever the user was doing, so the surface has
    /// to define its own background instead of letting a white document or a
    /// bright wallpaper show through and wreck the contrast of 15 pt text.
    func testSurfaceDefinesItsOwnBackgroundOverAnyBackdrop() throws {
        let size = NSSize(width: 400, height: 300)

        // Pure white is the case that used to fail: the surface tinted itself with
        // a colour that also resolves to white, so the panel vanished into a white
        // page and the text had nothing to sit against.
        let overWhite = try renderSurface(
            over: .white,
            reduceTransparency: false,
            increaseContrast: false,
            colorScheme: .light,
            size: size
        )
        let overBlack = try renderSurface(
            over: .black,
            reduceTransparency: false,
            increaseContrast: false,
            colorScheme: .light,
            size: size
        )

        let whiteCenter = try color(ofPixelAt: CGPoint(x: 200, y: 150), in: overWhite)
        let blackCenter = try color(ofPixelAt: CGPoint(x: 200, y: 150), in: overBlack)

        // The real question is not "how grey is it" but "can the label colour be
        // read on it". The worst case in each appearance is the backdrop that
        // pushes the panel towards the value of its own labels: a white page behind
        // a light panel, and a white page behind a dark one. Sweep every
        // appearance/backdrop pair and hold all of them to the WCAG AA ratio.
        for scheme in [ColorScheme.light, .dark] {
            let label = try labelColor(for: scheme)
            for backdrop in [Color.white, Color.black] {
                let name = backdrop == .white ? "white" : "black"
                let center = try color(
                    ofPixelAt: CGPoint(x: 200, y: 150),
                    in: try renderSurface(
                        over: backdrop,
                        reduceTransparency: false,
                        increaseContrast: false,
                        colorScheme: scheme,
                        size: size
                    )
                )
                let ratio = contrastRatio(of: center, against: label)
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    "\(scheme) surface over a \(name) backdrop only reaches \(ratio):1"
                )
            }
        }

        let lightRatio = contrastRatio(of: whiteCenter, against: try labelColor(for: .light))
        XCTAssertGreaterThanOrEqual(lightRatio, 4.5)

        // A light panel over a white page cannot win on value alone, so it must
        // keep the translucency that makes it read as a surface...
        XCTAssertLessThan(
            whiteCenter.brightnessComponent,
            0.999,
            "Surface no longer lets the backdrop through; it is just an opaque sheet"
        )
        // ...and it must not darken into a slab either, which is what washes out
        // the cyan menu headings. Light appearance stays light.
        XCTAssertGreaterThan(
            whiteCenter.brightnessComponent,
            0.75,
            "Light appearance darkened into a slab; coloured headings lose their contrast"
        )

        // The backdrop still has to reach the result, or the panel has stopped
        // being translucent.
        XCTAssertGreaterThan(
            abs(whiteCenter.brightnessComponent - blackCenter.brightnessComponent),
            0.02,
            "Two opposite backdrops produce the same surface"
        )

        // Dark appearance inverts the polarity: a dark panel with light labels.
        let darkOverBlack = try color(
            ofPixelAt: CGPoint(x: 200, y: 150),
            in: try renderSurface(
                over: .black,
                reduceTransparency: false,
                increaseContrast: false,
                colorScheme: .dark,
                size: size
            )
        )
        let darkRatio = contrastRatio(of: darkOverBlack, against: try labelColor(for: .dark))
        XCTAssertGreaterThanOrEqual(
            darkRatio,
            4.5,
            "Dark surface over a dark backdrop only reaches \(darkRatio):1 against the label colour"
        )
        XCTAssertLessThan(
            darkOverBlack.brightnessComponent,
            0.35,
            "Dark appearance lightened into a slab; light labels lose their contrast"
        )

        // Reduce Transparency is the escape hatch and must be genuinely opaque:
        // the backdrop may not influence the result at all.
        let opaqueOverWhite = try renderSurface(
            over: .white,
            reduceTransparency: true,
            increaseContrast: false,
            colorScheme: .light,
            size: size
        )
        let opaqueOverBlack = try renderSurface(
            over: .black,
            reduceTransparency: true,
            increaseContrast: false,
            colorScheme: .light,
            size: size
        )
        XCTAssertEqual(
            try luminance(ofCenterIn: opaqueOverWhite),
            try luminance(ofCenterIn: opaqueOverBlack),
            accuracy: 0.02,
            "Reduce Transparency must remove the backdrop from the result"
        )

        // Corners stay rounded, so the surface never paints a hard rectangle over
        // the app behind it. With a 30 pt radius the arc only begins around 9 pt
        // in, so a pixel on the rounded part must differ from one on the straight
        // top edge.
        let onTheArc = try color(ofPixelAt: CGPoint(x: 6, y: 6), in: overWhite)
        let onTheEdge = try color(ofPixelAt: CGPoint(x: 200, y: 2), in: overWhite)
        XCTAssertNotEqual(
            onTheArc.brightnessComponent,
            onTheEdge.brightnessComponent,
            accuracy: 0.02,
            "Surface is painting square corners"
        )
    }

    /// A shadow painted into a transparent borderless window has nowhere to fade
    /// once it passes the window edge: it gets cut off flat and reads as a
    /// translucent grey box around the panel instead of as a shadow.
    ///
    /// This is asserted as geometry rather than as pixels because SwiftUI does not
    /// draw shadows into an offscreen `cacheDisplay`, so a rendered check would
    /// pass no matter how far the shadow reached. Verified by hand: a deliberately
    /// enormous shadow still produced an all-zero scan.
    func testShadowFitsInsideTheWindowMargin() {
        let reach = PanelSurfaceStyle.shadowReach
        let inset = PanelSurfaceStyle.surfaceInset

        XCTAssertLessThanOrEqual(
            reach,
            inset,
            "The shadow reaches \(reach) pt but the window only leaves \(inset) pt, "
                + "so it would be cut off flat and read as a grey box"
        )
        XCTAssertTrue(PanelSurfaceStyle.shadowFitsInsideWindow)

        // The model that matters: a blur of radius r paints out to about 2·r, so the
        // downward reach is nearer 22 pt than the 13 pt that `radius + offset` suggests.
        // The 14 pt inset this test used to accept was 11% opaque where the window
        // ended, which is exactly the flat edge the assertion above describes.
        XCTAssertGreaterThanOrEqual(
            inset,
            PanelSurfaceStyle.shadowRadius * 2 + PanelSurfaceStyle.shadowOffsetY,
            "A blur of radius \(PanelSurfaceStyle.shadowRadius) pt still paints about "
                + "\(PanelSurfaceStyle.shadowRadius * 2) pt out; the inset has to cover that "
                + "plus the \(PanelSurfaceStyle.shadowOffsetY) pt offset"
        )
        // And there must still be a shadow worth drawing.
        XCTAssertGreaterThan(PanelSurfaceStyle.shadowRadius, 0)
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertGreaterThan(PanelSurfaceStyle.shadowOpacity(for: scheme), 0)
        }
    }

    func testSurfaceStyleHoldsItsValueAndKeepsItsEdge() {
        // The base fill has to hold the panel's own value on its own, so it can
        // never be a thin wash — but it also must not become the whole surface, or
        // the panel stops being glass.
        for scheme in [ColorScheme.light, .dark] {
            let opacity = PanelSurfaceStyle.baseOpacity(for: scheme)
            XCTAssertGreaterThan(opacity, 0.6, "Base fill is too thin in \(scheme)")
            XCTAssertLessThan(opacity, 1, "Base fill is opaque in \(scheme)")
        }

        // The two appearances are tuned independently rather than by a shared
        // formula, so assert they are actually distinct.
        XCTAssertNotEqual(
            PanelSurfaceStyle.baseOpacity(for: .light),
            PanelSurfaceStyle.baseOpacity(for: .dark)
        )

        // Reduce Transparency is the escape hatch and must be genuinely flat.
        XCTAssertEqual(PanelSurfaceStyle.opaqueBaseOpacity, 1)

        // Polarity: light appearance paints a light surface, dark appearance a dark
        // one. Reversing this is what flattened the panel into a grey slab and cost
        // the coloured heading text its contrast.
        XCTAssertGreaterThan(PanelSurfaceStyle.baseWhite(for: .light), 0.75)
        XCTAssertLessThan(PanelSurfaceStyle.baseWhite(for: .dark), 0.25)

        // The edge runs the opposite way to the fill, so a light panel keeps a
        // visible outline against a white page and a dark one against a dark app.
        XCTAssertLessThan(
            PanelSurfaceStyle.borderWhite(for: .light),
            PanelSurfaceStyle.baseWhite(for: .light)
        )
        XCTAssertGreaterThan(
            PanelSurfaceStyle.borderWhite(for: .dark),
            PanelSurfaceStyle.baseWhite(for: .dark)
        )

        for scheme in [ColorScheme.light, .dark] {
            XCTAssertGreaterThan(PanelSurfaceStyle.borderOpacity(for: scheme), 0.15)
            XCTAssertGreaterThan(PanelSurfaceStyle.shadowOpacity(for: scheme), 0.1)
        }
    }

    private func renderSurface(
        over backdrop: Color,
        reduceTransparency: Bool,
        increaseContrast: Bool,
        colorScheme: ColorScheme,
        size: NSSize
    ) throws -> Data {
        try renderView(
            ZStack {
                backdrop
                PanelSurface(
                    cornerRadius: 30,
                    reduceTransparency: reduceTransparency,
                    increaseContrast: increaseContrast,
                    colorScheme: colorScheme
                )
            },
            size: size,
            colorScheme: colorScheme
        )
    }

    private func color(ofPixelAt point: CGPoint, in data: Data) throws -> NSColor {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let scale = CGFloat(bitmap.pixelsWide) / 400
        let x = Int(point.x * scale)
        let y = Int(point.y * scale)
        return try XCTUnwrap(bitmap.colorAt(x: x, y: y)).usingColorSpace(.deviceRGB)
            ?? NSColor.black
    }

    private func luminance(ofCenterIn data: Data) throws -> Double {
        let color = try color(ofPixelAt: CGPoint(x: 200, y: 150), in: data)
        return 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
    }

    /// The colour AppKit uses for primary label text in the given appearance,
    /// resolved to concrete RGB so it can be measured against a rendered pixel.
    private func labelColor(for colorScheme: ColorScheme) throws -> NSColor {
        let appearance = try XCTUnwrap(
            NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        )
        var resolved = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .black
        }
        return resolved
    }

    /// WCAG 2.x contrast ratio between two opaque colours.
    private func contrastRatio(of first: NSColor, against second: NSColor) -> Double {
        let a = relativeLuminance(of: first)
        let b = relativeLuminance(of: second)
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(of color: NSColor) -> Double {
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent)
            + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
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
