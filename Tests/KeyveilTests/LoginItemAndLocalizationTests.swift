import Foundation
import XCTest
@testable import Keyveil

@MainActor
final class LoginItemAndLocalizationTests: XCTestCase {
    func testSettingsPresenterFallsBackToAReusableWindow() {
        let presenter = SettingsPresenter(appState: makeState(loginItemClient: .live))

        let window = presenter.makeWindow()

        // The window hosts SwiftUI through a plain hosting view in a fixed frame.
        // A hosting *controller* would claim the window's size and SwiftUI would
        // re-derive it on every constraint pass, which looped and aborted the app.
        let contentDescription = window.contentView.map { String(describing: type(of: $0)) } ?? "nil"
        XCTAssertTrue(
            contentDescription.contains("NSHostingView"),
            "Expected a SwiftUI hosting view, got \(contentDescription)"
        )
        XCTAssertNotNil(window.contentView)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertFalse(window.title.isEmpty)
        XCTAssertFalse(window.title.hasSuffix("…"), "Window titles should not keep the menu ellipsis")

        // Asking again reuses the same window instead of stacking copies.
        XCTAssertTrue(presenter.makeWindow() === window)
        window.orderOut(nil)
    }

    func testLaunchAtLoginUsesInjectedSystemClient() {
        var storedStatus = LoginItemStatus.disabled
        var changes: [Bool] = []
        var settingsOpenCount = 0
        let client = LoginItemClient(
            status: { storedStatus },
            setEnabled: { isEnabled in
                changes.append(isEnabled)
                storedStatus = isEnabled ? .enabled : .disabled
            },
            openSystemSettings: {
                settingsOpenCount += 1
            }
        )
        let state = makeState(loginItemClient: client)

        XCTAssertEqual(state.loginItemStatus, .disabled)

        state.setLaunchAtLoginEnabled(true)
        XCTAssertEqual(state.loginItemStatus, .enabled)
        XCTAssertTrue(state.loginItemStatus.isOn)

        state.setLaunchAtLoginEnabled(false)
        XCTAssertEqual(state.loginItemStatus, .disabled)
        XCTAssertEqual(changes, [true, false])

        state.openLoginItemsSettings()
        XCTAssertEqual(settingsOpenCount, 1)
    }

    func testApprovalRequiredIsPresentedAsEnabledWithoutAnError() {
        var storedStatus = LoginItemStatus.disabled
        let client = LoginItemClient(
            status: { storedStatus },
            setEnabled: { _ in
                storedStatus = .requiresApproval
                throw LoginItemTestError.denied
            },
            openSystemSettings: {}
        )
        let state = makeState(loginItemClient: client)

        state.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(state.loginItemStatus, .requiresApproval)
        XCTAssertTrue(state.loginItemStatus.isOn)
        XCTAssertNil(state.loginItemError)
    }

    func testUnexpectedLoginItemFailureIsExposedToTheSettingsUI() {
        let client = LoginItemClient(
            status: { .disabled },
            setEnabled: { _ in throw LoginItemTestError.denied },
            openSystemSettings: {}
        )
        let state = makeState(loginItemClient: client)

        state.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(state.loginItemStatus, .disabled)
        XCTAssertNotNil(state.loginItemError)
    }

    func testPermissionRefreshPublishesTheLatestSystemChecks() {
        var accessibilityGranted = false
        var inputMonitoringGranted = false
        let state = AppState(
            shortcutProvider: EmptyLoginItemTestShortcutProvider(),
            accessibilityCheck: { accessibilityGranted },
            inputMonitoringCheck: { inputMonitoringGranted },
            loginItemClient: LoginItemClient(
                status: { .disabled },
                setEnabled: { _ in },
                openSystemSettings: {}
            )
        )
        let initialRevision = state.permissionRevision

        accessibilityGranted = true
        inputMonitoringGranted = true
        state.refreshPermissionStatus()

        XCTAssertEqual(state.permissionRevision, initialRevision + 1)
        XCTAssertTrue(state.hasRequiredPermissions)
    }

    func testDeferringPermissionSetupLastsUntilExplicitlyResumed() {
        let state = makeState(
            loginItemClient: LoginItemClient(
                status: { .disabled },
                setEnabled: { _ in },
                openSystemSettings: {}
            )
        )
        var dismissCount = 0
        state.dismissOverlay = { dismissCount += 1 }

        state.deferPermissionSetupForSession()

        XCTAssertTrue(state.isPermissionSetupDeferred)
        XCTAssertEqual(dismissCount, 1)

        state.resumePermissionSetup()
        XCTAssertFalse(state.isPermissionSetupDeferred)
    }

    func testEnglishAndSimplifiedChineseContainTheSameKeys() throws {
        let english = try localizationDictionary("en")
        let simplifiedChinese = try localizationDictionary("zh-Hans")

        XCTAssertEqual(Set(english.keys), Set(simplifiedChinese.keys))
        XCTAssertGreaterThan(english.count, 40)
        XCTAssertEqual(english["settings.tab.general"], "General")
        XCTAssertEqual(simplifiedChinese["settings.tab.general"], "通用")
        XCTAssertEqual(simplifiedChinese["permission.accessibility.title"], "辅助功能")
    }

    func testEveryKeyTheInterfaceAsksForIsDefined() {
        // A key referenced in code but missing from the tables renders as the raw
        // key on screen. The check runs against the compiled bundle, so it covers
        // both the .strings and .stringsdict tables.
        let keys = [
            "onboarding.title", "onboarding.description", "onboarding.not_now",
            "onboarding.granted", "onboarding.allow", "onboarding.window_title",
            "onboarding.open_settings", "onboarding.status.waiting",
            "onboarding.footer.pending", "onboarding.footer.done",
            "panel.group.common", "panel.group.collapse",
            "settings.tab.general", "settings.tab.permissions",
            "settings.activation.section", "settings.activation.hold_duration",
            "settings.startup.section", "settings.startup.toggle",
            "settings.quick_access.section",
            "settings.permissions.required", "settings.permissions.control_note",
            "menu.settings", "menu.complete_setup"
        ]

        for localization in ["en", "zh-Hans"] {
            for key in keys {
                let value = L10n.string(key, localization: localization)
                XCTAssertNotNil(value, "\(localization) has no entry for \(key)")
                XCTAssertNotEqual(
                    value,
                    key,
                    "\(localization).\(key) resolved to the key itself, so it is missing"
                )
            }
        }
    }

    func testPluralRulesCoverEveryLocalisedCount() throws {
        // Counts are formatted through the stringsdict table, and every key used
        // there needs a rule in both localisations or the panel would show a raw
        // key in one language only.
        let pluralKeys: Set<String> = [
            "panel.shortcut_count",
            "panel.group.show_more",
            "panel.group.folded_count"
        ]

        for localization in ["en", "zh-Hans"] {
            let table = try stringsdictTable(localization)
            for key in pluralKeys {
                let entry = try XCTUnwrap(
                    table[key] as? [String: Any],
                    "\(localization) is missing \(key)"
                )
                let format = try XCTUnwrap(entry["NSStringLocalizedFormatKey"] as? String)
                XCTAssertTrue(
                    format.contains("%#@"),
                    "\(localization).\(key) is not a plural format: \(format)"
                )

                // The variable the format refers to must exist and declare a rule.
                let variable = format
                    .replacingOccurrences(of: "%#@", with: "")
                    .replacingOccurrences(of: "@", with: "")
                let rules = try XCTUnwrap(entry[variable] as? [String: String])
                XCTAssertEqual(
                    rules["NSStringFormatSpecTypeKey"],
                    "NSStringPluralRuleType",
                    "\(localization).\(key) does not declare a plural rule"
                )
                XCTAssertNotNil(rules["other"], "\(localization).\(key) has no 'other' rule")
            }
        }

        // English distinguishes one from many; Chinese has a single category.
        func pluralRules(_ localization: String) throws -> [String: String] {
            let entry = try XCTUnwrap(
                try stringsdictTable(localization)["panel.group.show_more"] as? [String: Any]
            )
            return try XCTUnwrap(entry["more"] as? [String: String])
        }
        XCTAssertNotNil(try pluralRules("en")["one"])
        XCTAssertNil(try pluralRules("zh-Hans")["one"])
    }

    private func stringsdictTable(_ localization: String) throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "Localizable",
                withExtension: "stringsdict",
                subdirectory: nil,
                localization: localization
            )
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    func testLocalizedBundleLookupDoesNotFallBackToKeys() throws {
        let english = try XCTUnwrap(
            L10n.string("settings.startup.toggle", localization: "en")
        )
        let simplifiedChinese = try XCTUnwrap(
            L10n.string("settings.startup.toggle", localization: "zh-Hans")
        )

        XCTAssertEqual(english, "Launch Keyveil at login")
        XCTAssertEqual(simplifiedChinese, "登录时启动 Keyveil")
    }

    func testShortcutCountUsesLocalizedPluralRules() throws {
        XCTAssertEqual(
            try XCTUnwrap(L10n.format("panel.shortcut_count", localization: "en", Int64(1))),
            "1 shortcut"
        )
        XCTAssertEqual(
            try XCTUnwrap(L10n.format("panel.shortcut_count", localization: "en", Int64(2))),
            "2 shortcuts"
        )
        XCTAssertEqual(
            try XCTUnwrap(L10n.format("panel.shortcut_count", localization: "zh-Hans", Int64(2))),
            "2 个快捷键"
        )
    }

    private func makeState(loginItemClient: LoginItemClient) -> AppState {
        AppState(
            shortcutProvider: EmptyLoginItemTestShortcutProvider(),
            accessibilityCheck: { true },
            inputMonitoringCheck: { true },
            loginItemClient: loginItemClient
        )
    }

    private func localizationDictionary(_ localization: String) throws -> [String: String] {
        // `Bundle.module.bundleURL` is the bundle root; its resources live in `Contents/Resources`
        // on macOS, so ask the bundle to resolve the localization directory instead of assuming
        // a layout. This keeps the test valid for both flat and versioned bundle layouts.
        let stringsURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            ),
            "Missing \(localization).lproj/Localizable.strings in \(Bundle.module.bundleURL.path)"
        )
        let data = try Data(contentsOf: stringsURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }
}

private struct EmptyLoginItemTestShortcutProvider: ShortcutProviding {
    func shortcuts(for processID: pid_t) -> ShortcutScanResult { .success([]) }
}

private enum LoginItemTestError: Error {
    case denied
}
