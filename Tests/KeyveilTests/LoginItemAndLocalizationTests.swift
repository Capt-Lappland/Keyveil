import Foundation
import XCTest
@testable import Keyveil

@MainActor
final class LoginItemAndLocalizationTests: XCTestCase {
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

    func testEnglishAndSimplifiedChineseContainTheSameKeys() throws {
        let english = try localizationDictionary("en")
        let simplifiedChinese = try localizationDictionary("zh-Hans")

        XCTAssertEqual(Set(english.keys), Set(simplifiedChinese.keys))
        XCTAssertGreaterThan(english.count, 40)
        XCTAssertEqual(english["settings.tab.general"], "General")
        XCTAssertEqual(simplifiedChinese["settings.tab.general"], "通用")
        XCTAssertEqual(simplifiedChinese["permission.accessibility.title"], "辅助功能")
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
        let stringsURL = Bundle.module.bundleURL
            .appendingPathComponent("\(localization.lowercased()).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: stringsURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }
}

private struct EmptyLoginItemTestShortcutProvider: ShortcutProviding {
    func shortcuts(for processID: pid_t) -> [ShortcutGroup]? { [] }
}

private enum LoginItemTestError: Error {
    case denied
}
