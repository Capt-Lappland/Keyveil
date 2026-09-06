import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedSettingsPane") private var selectedPane = SettingsPane.general.rawValue

    var body: some View {
        TabView(selection: $selectedPane) {
            GeneralSettingsPane()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsPane.general.rawValue)

            PermissionsSettingsPane()
                .tabItem {
                    Label("Permissions", systemImage: "hand.raised")
                }
                .tag(SettingsPane.permissions.rawValue)
        }
        .scenePadding()
        .frame(
            width: 600,
            height: selectedPane == SettingsPane.permissions.rawValue ? 450 : 480
        )
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

    var body: some View {
        Form {
            Section {
                SettingsIntroduction(
                    symbol: "command",
                    title: "Command gesture",
                    description: "Choose how long to hold Command before Keyveil reveals the active app’s shortcuts."
                )
            }

            Section("Activation") {
                LabeledContent {
                    HStack(spacing: 12) {
                        Slider(value: $appState.holdDelay, in: 0.3...1.2, step: 0.05)
                            .frame(width: 250)
                            .accessibilityLabel("Command hold duration")
                            .accessibilityValue("\(formattedDelay) seconds")

                        Text("\(formattedDelay) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .frame(width: 54, alignment: .trailing)
                    }
                } label: {
                    Label("Hold duration:", systemImage: "timer")
                }

                Text("A shorter duration feels faster; a longer duration reduces accidental activation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Quick access") {
                SettingsInfoRow(
                    symbol: "pin",
                    title: "Double-tap Command",
                    description: "Pin or unpin the shortcut panel without keeping Command held down."
                )

                SettingsInfoRow(
                    symbol: "escape",
                    title: "Press Escape",
                    description: "Close the panel whenever it is pinned."
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Changes apply immediately")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                SettingsIntroduction(
                    symbol: "hand.raised",
                    title: "Privacy & Security",
                    description: "Keyveil needs two macOS permissions to read menu shortcuts and detect the Command key."
                )
            }

            Section("Required permissions") {
                PermissionRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    description: "Reads shortcut titles and key equivalents from the active app’s menu.",
                    isGranted: appState.isAccessibilityGranted,
                    openSettings: appState.openAccessibilitySettings
                )

                PermissionRow(
                    symbol: "keyboard",
                    title: "Input Monitoring",
                    description: "Observes Command-key state without recording the keys you type.",
                    isGranted: appState.isInputMonitoringGranted,
                    openSettings: appState.openInputMonitoringSettings
                )
            }

            Label(
                "Permission changes remain under your control in System Settings.",
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            appState.refreshPermissionStatus()
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
    let symbol: String
    let title: String
    let description: String
    let isGranted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                Label(
                    isGranted ? "Allowed" : "Required",
                    systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(isGranted ? .green : .orange)

                Button(isGranted ? "Manage…" : "Open Settings…", action: openSettings)
                    .controlSize(.regular)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
