import SwiftUI

@main
struct KeyveilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Keyveil") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
    }
}
