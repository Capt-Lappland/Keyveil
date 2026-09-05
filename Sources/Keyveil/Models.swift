import AppKit
import ApplicationServices
import Combine

struct ShortcutItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let keys: [String]

    init(title: String, keys: [String], path: String) {
        self.id = "\(path)/\(title)/\(keys.joined())"
        self.title = title
        self.keys = keys
    }
}

struct ShortcutGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let shortcuts: [ShortcutItem]

    init(title: String, shortcuts: [ShortcutItem]) {
        self.id = title
        self.title = title
        self.symbol = ShortcutGroup.symbol(for: title)
        self.shortcuts = shortcuts
    }

    private static func symbol(for title: String) -> String {
        let lowered = title.lowercased()
        if lowered.contains("file") || lowered.contains("文件") { return "doc" }
        if lowered.contains("edit") || lowered.contains("编辑") { return "slider.horizontal.3" }
        if lowered.contains("view") || lowered.contains("显示") { return "eye" }
        if lowered.contains("window") || lowered.contains("窗口") { return "macwindow" }
        if lowered.contains("help") || lowered.contains("帮助") { return "questionmark.circle" }
        if lowered.contains("history") || lowered.contains("历史") { return "clock.arrow.circlepath" }
        if lowered.contains("bookmark") || lowered.contains("书签") { return "bookmark" }
        return "command"
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var applicationName = "Current App"
    @Published var applicationIcon: NSImage?
    @Published var applicationPID: pid_t = 0
    @Published var groups: [ShortcutGroup] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var isPermissionPromptVisible = false
    @Published var holdDelay: TimeInterval = 0.55

    private let accessibilityService = AccessibilityShortcutService()

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    var filteredGroups: [ShortcutGroup] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return groups
        }
        let query = searchText.localizedLowercase
        return groups.compactMap { group in
            let items = group.shortcuts.filter {
                $0.title.localizedLowercase.contains(query) || $0.keys.joined().localizedLowercase.contains(query)
            }
            return items.isEmpty ? nil : ShortcutGroup(title: group.title, shortcuts: items)
        }
    }

    var shortcutCount: Int {
        filteredGroups.reduce(0) { $0 + $1.shortcuts.count }
    }

    func updateApplication(_ application: NSRunningApplication) {
        applicationName = application.localizedName ?? "Current App"
        applicationIcon = application.icon
        applicationPID = application.processIdentifier
    }

    func loadShortcuts() {
        guard applicationPID > 0, isAccessibilityGranted else { return }
        isLoading = true
        let pid = applicationPID

        Task.detached(priority: .userInitiated) { [accessibilityService] in
            let groups = accessibilityService.shortcuts(for: pid)
            await MainActor.run {
                self.groups = groups
                self.isLoading = false
            }
        }
    }

    func loadPreviewData() {
        applicationName = "Safari"
        applicationIcon = NSImage(systemSymbolName: "safari", accessibilityDescription: "Safari")
        isPermissionPromptVisible = false
        isLoading = false
        groups = [
            ShortcutGroup(title: "Tabs", shortcuts: [
                ShortcutItem(title: "New Tab", keys: ["⌘", "T"], path: "Tabs"),
                ShortcutItem(title: "Close Tab", keys: ["⌘", "W"], path: "Tabs"),
                ShortcutItem(title: "Reopen Last Closed Tab", keys: ["⇧", "⌘", "T"], path: "Tabs"),
                ShortcutItem(title: "Next Tab", keys: ["⌃", "⇥"], path: "Tabs"),
                ShortcutItem(title: "Previous Tab", keys: ["⌃", "⇧", "⇥"], path: "Tabs")
            ]),
            ShortcutGroup(title: "View", shortcuts: [
                ShortcutItem(title: "Focus Address Bar", keys: ["⌘", "L"], path: "View"),
                ShortcutItem(title: "Find on Page", keys: ["⌘", "F"], path: "View"),
                ShortcutItem(title: "Reload Page", keys: ["⌘", "R"], path: "View"),
                ShortcutItem(title: "Go Back", keys: ["⌘", "["], path: "View"),
                ShortcutItem(title: "Show Downloads", keys: ["⌥", "⌘", "L"], path: "View")
            ]),
            ShortcutGroup(title: "Window", shortcuts: [
                ShortcutItem(title: "New Window", keys: ["⌘", "N"], path: "Window"),
                ShortcutItem(title: "Close Window", keys: ["⇧", "⌘", "W"], path: "Window"),
                ShortcutItem(title: "Minimize", keys: ["⌘", "M"], path: "Window"),
                ShortcutItem(title: "Enter Full Screen", keys: ["⌃", "⌘", "F"], path: "Window"),
                ShortcutItem(title: "Show Reading List", keys: ["⌃", "⌘", "2"], path: "Window")
            ])
        ]
    }

    func requestAccessibilityAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
