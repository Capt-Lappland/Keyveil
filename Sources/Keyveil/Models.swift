import AppKit
import ApplicationServices
import Combine
import CoreGraphics

struct ShortcutItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let keys: [String]
    let isEnabled: Bool

    init(title: String, keys: [String], path: String, isEnabled: Bool = true) {
        self.id = "\(path)/\(title)/\(keys.joined())"
        self.title = title
        self.keys = keys
        self.isEnabled = isEnabled
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

enum ShortcutColumnLayout {
    static func columnCount(forWidth width: CGFloat, groupCount: Int) -> Int {
        guard groupCount > 0 else { return 0 }
        let preferredCount = width >= 1_000 ? 3 : 2
        return min(preferredCount, groupCount)
    }

    static func balanced(_ groups: [ShortcutGroup], columnCount: Int) -> [[ShortcutGroup]] {
        let count = min(max(1, columnCount), max(1, groups.count))
        guard !groups.isEmpty else { return [] }

        let groupWeights = groups.map { max(3, $0.shortcuts.count) + 2 }
        var remainingWeight = groupWeights.reduce(0, +)
        var remainingColumns = count
        var columns: [[ShortcutGroup]] = []
        var currentColumn: [ShortcutGroup] = []
        var currentWeight = 0

        for (index, group) in groups.enumerated() {
            let weight = groupWeights[index]
            if !currentColumn.isEmpty, remainingColumns > 1 {
                let targetWeight = Double(remainingWeight) / Double(remainingColumns)
                let groupsStillUnplaced = groups.count - index
                let mustStartNextColumn = groupsStillUnplaced == remainingColumns - 1
                let currentDistance = abs(Double(currentWeight) - targetWeight)
                let addedDistance = abs(Double(currentWeight + weight) - targetWeight)

                if mustStartNextColumn || currentDistance <= addedDistance {
                    columns.append(currentColumn)
                    remainingWeight -= currentWeight
                    remainingColumns -= 1
                    currentColumn = []
                    currentWeight = 0
                }
            }

            currentColumn.append(group)
            currentWeight += weight
        }

        columns.append(currentColumn)

        return columns
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var applicationName = "Current App"
    @Published var applicationIcon: NSImage?
    @Published var applicationPID: pid_t = 0
    @Published var groups: [ShortcutGroup] = []
    @Published var isLoading = false
    @Published var isPermissionPromptVisible = false
    @Published private(set) var permissionRevision = 0
    @Published var isPinned = false
    @Published private(set) var overlayPresentationRevision = 0
    @Published var holdDelay: TimeInterval {
        didSet {
            UserDefaults.standard.set(holdDelay, forKey: Self.holdDelayKey)
        }
    }

    var dismissOverlay: (() -> Void)?

    private let shortcutProvider: any ShortcutProviding
    private let accessibilityCheck: () -> Bool
    private let inputMonitoringCheck: () -> Bool
    private var loadTask: Task<[ShortcutGroup]?, Never>?
    private var applicationBundleIdentifier = ""
    private var shortcutCache: [String: CacheEntry] = [:]

    private static let holdDelayKey = "commandHoldDelay"
    private static let cacheLifetime: TimeInterval = 120
    private static let maximumCachedApplications = 24

    private struct CacheEntry {
        let groups: [ShortcutGroup]
        let loadedAt: Date
    }

    init(
        shortcutProvider: any ShortcutProviding = AccessibilityShortcutService(),
        accessibilityCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
        inputMonitoringCheck: @escaping () -> Bool = { CGPreflightListenEventAccess() }
    ) {
        self.shortcutProvider = shortcutProvider
        self.accessibilityCheck = accessibilityCheck
        self.inputMonitoringCheck = inputMonitoringCheck
        let savedDelay = UserDefaults.standard.double(forKey: Self.holdDelayKey)
        holdDelay = savedDelay == 0 ? 0.55 : min(max(savedDelay, 0.3), 1.2)
    }

    var isAccessibilityGranted: Bool {
        accessibilityCheck()
    }

    var isInputMonitoringGranted: Bool {
        inputMonitoringCheck()
    }

    var hasRequiredPermissions: Bool {
        isAccessibilityGranted && isInputMonitoringGranted
    }

    var shortcutCount: Int {
        groups.reduce(0) { $0 + $1.shortcuts.count }
    }

    func updateApplication(_ application: NSRunningApplication) {
        updateApplication(
            name: application.localizedName ?? "Current App",
            icon: application.icon,
            processID: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier ?? "pid:\(application.processIdentifier)"
        )
    }

    func updateApplication(name: String, icon: NSImage?, processID: pid_t, bundleIdentifier: String) {
        applicationName = name
        applicationIcon = icon
        applicationPID = processID
        applicationBundleIdentifier = bundleIdentifier
    }

    func loadShortcuts(forceRefresh: Bool = false) {
        guard applicationPID > 0, isAccessibilityGranted else { return }

        let pid = applicationPID
        let cacheKey = applicationBundleIdentifier
        let now = Date()
        loadTask?.cancel()
        loadTask = nil

        if let cached = shortcutCache[cacheKey] {
            groups = cached.groups
            isLoading = false
            if !forceRefresh, now.timeIntervalSince(cached.loadedAt) < Self.cacheLifetime {
                return
            }
        } else {
            // Never render the previous app's shortcuts beneath a new header.
            groups = []
            isLoading = true
        }

        let provider = shortcutProvider
        let scanTask = Task.detached(priority: .userInitiated) {
            provider.shortcuts(for: pid)
        }
        loadTask = scanTask

        Task { [weak self] in
            let loadedGroups = await scanTask.value

            guard !scanTask.isCancelled,
                  let self,
                  self.applicationPID == pid,
                  self.applicationBundleIdentifier == cacheKey else { return }

            self.loadTask = nil
            guard let loadedGroups else {
                // A transient AX failure should be retried on the next reveal,
                // rather than cached as an empty result for two minutes.
                self.isLoading = false
                return
            }

            self.storeInCache(loadedGroups, for: cacheKey, at: Date())
            self.groups = loadedGroups
            self.isLoading = false
        }
    }

    private func storeInCache(_ groups: [ShortcutGroup], for key: String, at date: Date) {
        shortcutCache = shortcutCache.filter {
            date.timeIntervalSince($0.value.loadedAt) < Self.cacheLifetime
        }

        if shortcutCache[key] == nil,
           shortcutCache.count >= Self.maximumCachedApplications,
           let oldestKey = shortcutCache.min(by: { $0.value.loadedAt < $1.value.loadedAt })?.key {
            shortcutCache.removeValue(forKey: oldestKey)
        }

        shortcutCache[key] = CacheEntry(groups: groups, loadedAt: date)
    }

    func closeOverlay() {
        dismissOverlay?()
    }

    func beginShortcutPresentation() {
        overlayPresentationRevision &+= 1
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
                ShortcutItem(title: "Previous Tab", keys: ["⌃", "⇧", "⇥"], path: "Tabs"),
                ShortcutItem(title: "Move Tab to New Window", keys: ["⌥", "⌘", "N"], path: "Tabs"),
                ShortcutItem(title: "Pin Tab", keys: ["⌥", "⌘", "P"], path: "Tabs", isEnabled: false),
                ShortcutItem(title: "Mute Tab", keys: ["⌥", "⌘", "M"], path: "Tabs"),
                ShortcutItem(title: "Select First Tab", keys: ["⌘", "1"], path: "Tabs"),
                ShortcutItem(title: "Select Last Tab", keys: ["⌘", "9"], path: "Tabs")
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
            ]),
            ShortcutGroup(title: "History", shortcuts: [
                ShortcutItem(title: "Show All History", keys: ["⌘", "Y"], path: "History"),
                ShortcutItem(title: "Back", keys: ["⌘", "["], path: "History"),
                ShortcutItem(title: "Forward", keys: ["⌘", "]"], path: "History")
            ]),
            ShortcutGroup(title: "Bookmarks", shortcuts: [
                ShortcutItem(title: "Add Bookmark", keys: ["⌘", "D"], path: "Bookmarks"),
                ShortcutItem(title: "Show Start Page", keys: ["⇧", "⌘", "\\"], path: "Bookmarks"),
                ShortcutItem(title: "Show Bookmarks", keys: ["⌃", "⌘", "1"], path: "Bookmarks")
            ])
        ]
    }

    func requestAccessibilityAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func requestAccessibilityFromOnboarding() {
        closeOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.requestAccessibilityAccess()
        }
    }

    func requestInputMonitoringFromOnboarding() {
        closeOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            CGRequestListenEventAccess()
        }
    }

    func refreshPermissionStatus() {
        permissionRevision &+= 1
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}
