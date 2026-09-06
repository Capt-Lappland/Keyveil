import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("selectedSettingsPane") private var selectedPane = SettingsPane.general.rawValue

    var body: some View {
        TabView(selection: $selectedPane) {
            GeneralSettingsPane()
                .tabItem {
                    Label(L10n.string("settings.tab.general"), systemImage: "gearshape")
                }
                .tag(SettingsPane.general.rawValue)

            PermissionsSettingsPane()
                .tabItem {
                    Label(L10n.string("settings.tab.permissions"), systemImage: "hand.raised")
                }
                .tag(SettingsPane.permissions.rawValue)
        }
        .scenePadding()
        .frame(
            width: 600,
            height: selectedPane == SettingsPane.permissions.rawValue ? 470 : 650
        )
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionStatus()
            appState.refreshLoginItemStatus()
        }
    }
}

private enum SettingsPane: String {
    case general
    case permissions
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    private var formattedDelay: String {
        appState.holdDelay.formatted(.number.precision(.fractionLength(2)))
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.loginItemStatus.isOn },
            set: { isEnabled in
                appState.setLaunchAtLoginEnabled(isEnabled)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                SettingsIntroduction(
                    symbol: "command",
                    title: L10n.string("settings.command_gesture.title"),
                    description: L10n.string("settings.command_gesture.description")
                )
            }

            Section(L10n.string("settings.activation.section")) {
                LabeledContent {
                    HStack(spacing: 12) {
                        Slider(value: $appState.holdDelay, in: 0.3...1.2, step: 0.05)
                            .frame(width: 250)
                            .accessibilityLabel(L10n.string("settings.activation.accessibility_label"))
                            .accessibilityValue(
                                L10n.format("settings.activation.accessibility_value", formattedDelay)
                            )

                        Text(L10n.format("settings.activation.short_value", formattedDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .frame(width: 58, alignment: .trailing)
                    }
                } label: {
                    Label(L10n.string("settings.activation.hold_duration"), systemImage: "timer")
                }

                Text(L10n.string("settings.activation.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.startup.section")) {
                Toggle(isOn: launchAtLoginBinding) {
                    Label(L10n.string("settings.startup.toggle"), systemImage: "power")
                }
                .disabled(appState.loginItemStatus == .unavailable)

                Text(L10n.string("settings.startup.description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                loginItemStatus
            }

            Section(L10n.string("settings.quick_access.section")) {
                SettingsInfoRow(
                    symbol: "pin",
                    title: L10n.string("settings.quick_access.double_tap.title"),
                    description: L10n.string("settings.quick_access.double_tap.description")
                )

                SettingsInfoRow(
                    symbol: "escape",
                    title: L10n.string("settings.quick_access.escape.title"),
                    description: L10n.string("settings.quick_access.escape.description")
                )
            }

        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshLoginItemStatus()
        }
    }

    @ViewBuilder
    private var loginItemStatus: some View {
        switch appState.loginItemStatus {
        case .disabled:
            if let error = appState.loginItemError {
                Label(
                    L10n.format("settings.startup.error", error),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.red)
            }
        case .enabled:
            Label(L10n.string("settings.startup.enabled"), systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .requiresApproval:
            HStack {
                Label(
                    L10n.string("settings.startup.requires_approval"),
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)

                Spacer()

                Button(L10n.string("settings.startup.review")) {
                    appState.openLoginItemsSettings()
                }
            }
        case .unavailable:
            Label(
                L10n.string("settings.startup.unavailable"),
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionsSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                SettingsIntroduction(
                    symbol: "hand.raised",
                    title: L10n.string("settings.privacy.title"),
                    description: L10n.string("settings.privacy.description")
                )
            }

            Section(L10n.string("settings.permissions.required")) {
                PermissionRow(
                    kind: .accessibility,
                    isGranted: appState.isAccessibilityGranted,
                    openSettings: appState.openAccessibilitySettings
                )

                PermissionRow(
                    kind: .inputMonitoring,
                    isGranted: appState.isInputMonitoringGranted,
                    openSettings: appState.openInputMonitoringSettings
                )
            }

            Label(
                L10n.string("settings.permissions.control_note"),
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshPermissionStatus()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                appState.refreshPermissionStatus()
            }
        }
    }
}

private struct SettingsIntroduction: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsInfoRow: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let isGranted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .fontWeight(.medium)
                Text(kind.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                Label(
                    isGranted
                        ? L10n.string("settings.permissions.allowed")
                        : L10n.string("settings.permissions.required_status"),
                    systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(isGranted ? .green : .orange)

                Button(
                    isGranted
                        ? L10n.string("settings.permissions.manage")
                        : L10n.string("settings.permissions.open_settings"),
                    action: openSettings
                )
                .controlSize(.regular)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
