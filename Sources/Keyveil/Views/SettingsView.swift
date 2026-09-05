import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Activation") {
                HStack {
                    Text("Command hold delay")
                    Slider(value: $appState.holdDelay, in: 0.3...1.2, step: 0.05)
                    Text("\(appState.holdDelay, specifier: "%.2f") s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }

            Section("Permissions") {
                HStack {
                    Label(
                        appState.isAccessibilityGranted ? "Accessibility access granted" : "Accessibility access required",
                        systemImage: appState.isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(appState.isAccessibilityGranted ? .green : .orange)
                    Spacer()
                    Button("Open Settings") {
                        appState.openAccessibilitySettings()
                    }
                }

                HStack {
                    Label(
                        appState.isInputMonitoringGranted ? "Input Monitoring access granted" : "Input Monitoring access required",
                        systemImage: appState.isInputMonitoringGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(appState.isInputMonitoringGranted ? .green : .orange)
                    Spacer()
                    Button("Open Settings") {
                        appState.openInputMonitoringSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 500, height: 260)
    }
}
