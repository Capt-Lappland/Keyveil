import AppKit
import SwiftUI

@main
struct KeyveilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // There is deliberately no SwiftUI `Settings` scene.
        //
        // A `Settings` scene claims the `showSettingsWindow:` selector, so
        // `NSApp.sendAction` reported success, but on macOS 26 its window was never
        // ordered on screen — which left the menu item doing nothing at all. The
        // preferences window is built by `SettingsPresenter` instead, where its
        // presentation can actually be checked.
        //
        // SwiftUI refuses to build an `App` with no scenes, so this placeholder is
        // required. It is never meant to be seen: Keyveil's whole interface is the
        // status item `AppDelegate` installs. `AppDelegate` dismisses it whenever it
        // appears, including the re-show that happens well after launch.
        Window("Keyveil Background", id: "keyveil-background") {
            EmptyView()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}
