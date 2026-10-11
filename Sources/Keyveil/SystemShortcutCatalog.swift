/// Recognises the shortcuts that every app inherits from AppKit rather than
/// defining itself.
///
/// Measured on macOS: Safari, Finder, Preview, TextEdit and Calendar each expose
/// between 62 and 112 shortcuts, and exactly 22 of them are identical in all
/// five. Those 22 are the window arrangement block plus a handful of global
/// commands. On a 62-shortcut app that is a third of the panel spent telling the
/// user something they already know, so they are collected into one collapsed
/// group instead of being mixed in with the app's own features.
///
/// The match is deliberately conservative. Anything that could plausibly be an
/// app's own command is left alone: `Cut`, `Copy` and `Paste` are *not* captured
/// even though they are universal, because a false capture moves a command the
/// user was looking for out of the menu they would look in.
enum SystemShortcutCatalog {
    /// Window arrangement commands. These names are dangerous on their own —
    /// `TextEdit → Format → Centre` is text alignment, not window tiling — so they
    /// only count as system items inside the Window menu, where AppKit puts its
    /// inherited block.
    private static let windowArrangementTitles: Set<String> = [
        "Minimise", "Minimise All", "Minimize", "Minimize All",
        "Enter Full Screen", "Exit Full Screen",
        "Fill", "Centre", "Center",
        "Left", "Right", "Top", "Bottom",
        "Left & Right", "Right & Left",
        "Left & Quarters", "Right & Quarters",
        "Top & Bottom", "Bottom & Top",
        "Top & Quarters", "Bottom & Quarters",
        "Return to Previous Size",
        "Move Window to Left Side of Screen", "Move Window to Right Side of Screen",
        "Tile Window to Left of Screen", "Tile Window to Right of Screen"
    ]

    /// Commands the system injects into whatever menu it likes. These are
    /// unambiguous because they act on the application itself, not on its content.
    private static let globalCommandTitles: Set<String> = [
        "Settings…", "Settings", "Preferences…", "Preferences",
        "Hide Others", "Show All",
        "Start Dictation", "Emoji & Symbols",
        "Enter Full Screen", "Exit Full Screen"
    ]

    /// Localised menu titles for the Window menu. Only used when no title matches
    /// the English spelling, so an English system is unaffected by these.
    private static let windowMenuTitles: Set<String> = ["Window", "窗口"]

    static func isSystemShortcut(groupTitle: String, itemTitle: String) -> Bool {
        if isWindowMenu(groupTitle), windowArrangementTitles.contains(itemTitle) {
            return true
        }
        return globalCommandTitles.contains(itemTitle)
    }

    private static func isWindowMenu(_ title: String) -> Bool {
        windowMenuTitles.contains(title)
    }

    /// Splits a scan into what the app itself offers and the inherited set.
    static func partition(_ groups: [ShortcutGroup]) -> (app: [ShortcutGroup], system: [ShortcutGroup]) {
        var appGroups: [ShortcutGroup] = []
        var systemGroups: [ShortcutGroup] = []

        for group in groups {
            var appItems: [ShortcutItem] = []
            var systemItems: [ShortcutItem] = []

            for item in group.shortcuts {
                if isSystemShortcut(groupTitle: group.title, itemTitle: item.title) {
                    systemItems.append(item)
                } else {
                    appItems.append(item)
                }
            }

            if !appItems.isEmpty {
                appGroups.append(ShortcutGroup(title: group.title, shortcuts: appItems))
            }
            if !systemItems.isEmpty {
                systemGroups.append(ShortcutGroup(title: group.title, shortcuts: systemItems))
            }
        }

        return (appGroups, systemGroups)
    }
}
