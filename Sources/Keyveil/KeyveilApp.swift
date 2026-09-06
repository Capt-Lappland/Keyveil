import SwiftUI

@main
struct KeyveilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n.string("menu.about")) {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
    }
}
