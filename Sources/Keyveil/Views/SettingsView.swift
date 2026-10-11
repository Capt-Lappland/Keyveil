import AppKit
import Combine
import SwiftUI

/// The settings window.
///
/// Structured the way macOS expects a preferences window to be: a sidebar listing
/// panes beside a grouped form, rather than a segmented `TabView`. The sidebar is
/// what every system app uses and it is what macOS 26 frames in glass, so the
/// window keeps its native appearance instead of imitating one.
struct SettingsView: View {
    /// Fixed window size. A settings window keeps one size across panes; letting it
    /// track its content makes it jump and lets AppKit pick a runaway height.
    static let preferredSize = NSSize(width: 660, height: 520)

    @EnvironmentObject private var appState: AppState
    /// Injectable so the pane can be rendered deterministically, by tests and by
    /// the preview flags, without going through persisted state.
    var initialPane: SettingsPane = .general
    @State private var selectedPane: SettingsPane?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()

            Group {
                switch selectedPane ?? initialPane {
                case .general:
                    GeneralSettingsPane()
                case .appearance:
                    AppearanceSettingsPane()
                case .permissions:
                    PermissionsSettingsPane()
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .onAppear { selectedPane = initialPane }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.refreshPermissionStatus()
            appState.refreshLoginItemStatus()
        }
    }

    /// The pane list down the left edge, shaped like a source list.
    ///
    /// The selection is drawn from `Color.accentColor` explicitly rather than left
    /// to `List`'s own highlight. The system highlight only resolves correctly for a
    /// window that the window server considers active, which makes the selected row
    /// render as an unreadable black bar in any context that renders the view
    /// outside a live key window.
    private var sidebar: some View {
        VStack(spacing: 0) {
            ForEach(SettingsPane.allCases) { pane in
                let isSelected = (selectedPane ?? initialPane) == pane
                Button {
                    selectedPane = pane
                } label: {
                    Label(pane.title, systemImage: pane.symbol)
                        .font(.body)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(width: 184)
    }

}

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L10n.string("settings.tab.general")
        case .appearance: L10n.string("settings.tab.appearance")
        case .permissions: L10n.string("settings.tab.permissions")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .permissions: "hand.raised"
        }
    }
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
                Toggle(isOn: launchAtLoginBinding) {
                    Text(L10n.string("settings.startup.toggle"))
                }
                .disabled(appState.loginItemStatus == .unavailable)

                loginItemStatusRow
            } header: {
                Text(L10n.string("settings.startup.section"))
            } footer: {
                Text(L10n.string("settings.startup.description"))
            }

            Section {
                LabeledContent {
                    HStack(spacing: 12) {
                        Slider(value: $appState.holdDelay, in: 0.3...1.2, step: 0.05)
                            .frame(minWidth: 180)
                            .accessibilityLabel(L10n.string("settings.activation.accessibility_label"))
                            .accessibilityValue(
                                L10n.format("settings.activation.accessibility_value", formattedDelay)
                            )

                        Text(L10n.format("settings.activation.short_value", formattedDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .frame(width: 52, alignment: .trailing)
                    }
                } label: {
                    Text(L10n.string("settings.activation.hold_duration"))
                }
            } header: {
                Text(L10n.string("settings.activation.section"))
            } footer: {
                Text(L10n.string("settings.activation.description"))
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
    private var loginItemStatusRow: some View {
        switch appState.loginItemStatus {
        case .disabled:
            if let error = appState.loginItemError {
                // A status the user cannot act on inside this pane, so it is stated
                // rather than tinted as an alarm.
                Text(L10n.format("settings.startup.error", error))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .enabled:
            Label(L10n.string("settings.startup.enabled"), systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .requiresApproval:
            HStack {
                Label(
                    L10n.string("settings.startup.requires_approval"),
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.callout)

                Spacer()

                Button(L10n.string("settings.startup.review")) {
                    appState.openLoginItemsSettings()
                }
            }
        case .unavailable:
            Text(L10n.string("settings.startup.unavailable"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppearanceSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker(L10n.string("settings.folding.behaviour"), selection: $appState.foldBehaviour) {
                    Text(L10n.string("settings.folding.automatic")).tag(FoldBehaviour.automatic)
                    Text(L10n.string("settings.folding.compact")).tag(FoldBehaviour.compact)
                    Text(L10n.string("settings.folding.alwaysExpanded")).tag(FoldBehaviour.alwaysExpanded)
                }
            } header: {
                Text(L10n.string("settings.folding.section"))
            } footer: {
                Text(L10n.string("settings.folding.description"))
            }

            Section {
                Picker(L10n.string("settings.appearance.theme"), selection: $appState.panelTheme) {
                    Text(L10n.string("settings.appearance.theme.system")).tag(PanelTheme.system)
                    Text(L10n.string("settings.appearance.theme.monochrome")).tag(PanelTheme.monochrome)
                    Text(L10n.string("settings.appearance.theme.blue")).tag(PanelTheme.blue)
                    Text(L10n.string("settings.appearance.theme.purple")).tag(PanelTheme.purple)
                    Text(L10n.string("settings.appearance.theme.pink")).tag(PanelTheme.pink)
                }
            } header: {
                Text(L10n.string("settings.appearance.section"))
            } footer: {
                Text(L10n.string("settings.appearance.theme.description"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
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
            } header: {
                Text(L10n.string("settings.permissions.required"))
            } footer: {
                Text(L10n.string("settings.permissions.control_note"))
            }
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

private struct SettingsInfoRow: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: kind.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                Text(kind.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 6) {
                Label(
                    isGranted
                        ? L10n.string("settings.permissions.allowed")
                        : L10n.string("settings.permissions.required_status"),
                    systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                Button(
                    isGranted
                        ? L10n.string("settings.permissions.manage")
                        : L10n.string("settings.permissions.open_settings"),
                    action: openSettings
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
