import AppKit
import ApplicationServices
import Combine
import CoreGraphics

struct ShortcutItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let keys: [String]
    let isEnabled: Bool

    /// `ordinal` is the item's position in the scan.
    ///
    /// It is part of the identity because a menu can legitimately repeat a title:
    /// Finder's File menu offers "Eject" three times, for ⌘E, ⌃⌘E and ⌥⌘E. Without
    /// a positional component those collapse onto a single identity, and the wall
    /// then drops all but one of them.
    init(title: String, keys: [String], path: String, isEnabled: Bool = true, ordinal: Int = 0) {
        self.id = "\(path)/\(title)/\(keys.joined())/\(ordinal)"
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

    init(title: String, shortcuts: [ShortcutItem], symbol: String? = nil) {
        self.id = title
        self.title = title
        self.symbol = symbol ?? ShortcutGroup.symbol(for: title)
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

/// Narrows the shortcut wall down to what the user typed. Kept free of view
/// state so the matching rules can be tested on their own.
enum ShortcutQuery {
    static func filter(_ groups: [ShortcutGroup], matching query: String) -> [ShortcutGroup] {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        guard !terms.isEmpty else { return groups }

        return groups.compactMap { group in
            let shortcuts = group.shortcuts.filter { shortcut in
                let haystack = [shortcut.title, shortcut.keys.joined()]
                    .joined(separator: " ")
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                return terms.allSatisfy(haystack.contains)
            }
            guard !shortcuts.isEmpty else { return nil }
            return ShortcutGroup(title: group.title, shortcuts: shortcuts)
        }
    }

    static func count(in groups: [ShortcutGroup]) -> Int {
        groups.reduce(0) { $0 + $1.shortcuts.count }
    }
}

enum ShortcutColumnLayout {
    /// Height of one shortcut row, including its divider. Measured from a rendered
    /// panel: rows came out at 43–45 pt.
    static let rowHeight: CGFloat = 45

    /// Height of a group's header row, which carries the fold control. Measured
    /// from a rendered panel.
    static let groupHeaderHeight: CGFloat = 35

    /// How many shortcut rows fit in a column of the given height.
    ///
    /// A folded group has to keep its "show more" control on screen, otherwise the
    /// shortcuts are simply hidden rather than folded. One slot is therefore
    /// reserved for the control, and the result is clamped so a very short panel
    /// still shows something.
    static func visibleRowBudget(forColumnHeight height: CGFloat) -> Int {
        guard height > 0 else { return ShortcutWallPlan.revealLimit }
        let slots = Int(height / rowHeight)
        let budget = max(1, slots - 1)
        return min(budget, 400)
    }

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

/// What a long menu group does the first time the wall is shown.
enum FoldBehaviour: String, CaseIterable, Identifiable, Sendable {
    /// Fold anything taller than one screen, so the first screen is readable.
    case automatic
    /// Show every menu in full and let the user scroll.
    case alwaysExpanded
    /// Fold every menu down to a handful of rows.
    case compact

    var id: String { rawValue }

    /// Rows a folded group shows, or nil when nothing folds.
    /// - Parameter rowBudget: rows that fit in a column at the current panel size.
    func revealLimit(rowBudget: Int) -> Int? {
        switch self {
        case .automatic: min(rowBudget, ShortcutWallPlan.maximumReveal)
        case .alwaysExpanded: nil
        case .compact: min(rowBudget, ShortcutWallPlan.compactReveal)
        }
    }
}

/// Which colour the overlay's accents use.
enum PanelTheme: String, CaseIterable, Identifiable, Sendable {
    /// Follows the macOS accent colour in System Settings.
    case system
    /// A neutral grey, for a quieter wall.
    case monochrome
    /// A fixed blue, whatever the system accent is set to.
    case blue
    /// A fixed purple.
    case purple
    /// A fixed pink.
    case pink

    var id: String { rawValue }

    /// nil means "inherit the system accent colour". Kept as plain data so this
    /// model stays free of SwiftUI, which the view layer supplies.
    var accentName: String? {
        switch self {
        case .system: nil
        case .monochrome: "monochrome"
        case .blue: "blue"
        case .purple: "purple"
        case .pink: "pink"
        }
    }
}

enum ShortcutLoadIssue: Equatable {
    case timedOut
    case unavailable
}

enum ShortcutScrollCommand: Equatable, Sendable {
    case lineUp
    case lineDown
    case pageUp
    case pageDown
    case home
    case end
}

struct ShortcutScrollRequest: Equatable, Sendable {
    let command: ShortcutScrollCommand
    let revision: Int
}

@MainActor
final class AppState: ObservableObject {
    @Published var applicationName = L10n.string("app.current")
    @Published var applicationIcon: NSImage?
    @Published var applicationPID: pid_t = 0
    @Published var groups: [ShortcutGroup] = []
    @Published var isLoading = false
    @Published private(set) var shortcutLoadIssue: ShortcutLoadIssue?
    @Published var isPermissionPromptVisible = false
    /// Whether the system prompt has already been raised this session. macOS shows
    /// its permission dialog once, so a second request would silently do nothing;
    /// the setup screen uses this to offer System Settings instead of a dead button.
    @Published private(set) var hasRequestedAccessibility = false
    @Published private(set) var hasRequestedInputMonitoring = false
    @Published private(set) var isPermissionSetupDeferred = false
    @Published private(set) var permissionRevision = 0
    @Published private(set) var loginItemStatus: LoginItemStatus
    @Published private(set) var loginItemError: String?
    @Published var isPinned = false
    /// Group identifiers the user opened by hand. Kept per session rather than per
    /// app so that opening a long group in one app keeps it open in the next.
    @Published private(set) var expandedGroupIDs: Set<String> = []
    @Published private(set) var overlayPresentationRevision = 0
    @Published private(set) var shortcutScrollRequest: ShortcutScrollRequest?
    @Published var holdDelay: TimeInterval {
        didSet {
            UserDefaults.standard.set(holdDelay, forKey: Self.holdDelayKey)
        }
    }
    @Published var foldBehaviour: FoldBehaviour {
        didSet {
            UserDefaults.standard.set(foldBehaviour.rawValue, forKey: Self.foldBehaviourKey)
        }
    }
    @Published var panelTheme: PanelTheme {
        didSet {
            UserDefaults.standard.set(panelTheme.rawValue, forKey: Self.panelThemeKey)
        }
    }

    var dismissOverlay: (() -> Void)?

    private let shortcutProvider: any ShortcutProviding
    private let accessibilityCheck: () -> Bool
    private let inputMonitoringCheck: () -> Bool
    private let loginItemClient: LoginItemClient
    private var loadTask: Task<ShortcutScanResult, Never>?
    private var applicationBundleIdentifier = ""
    private var shortcutCache: [String: CacheEntry] = [:]

    private static let holdDelayKey = "commandHoldDelay"
    private static let foldBehaviourKey = "foldBehaviour"
    private static let panelThemeKey = "panelTheme"
    private static let cacheLifetime: TimeInterval = 120
    private static let maximumCachedApplications = 24

    private struct CacheEntry {
        let groups: [ShortcutGroup]
        let loadedAt: Date
    }

    init(
        shortcutProvider: any ShortcutProviding = AccessibilityShortcutService(),
        accessibilityCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
        inputMonitoringCheck: @escaping () -> Bool = { CGPreflightListenEventAccess() },
        loginItemClient: LoginItemClient = .live
    ) {
        self.shortcutProvider = shortcutProvider
        self.accessibilityCheck = accessibilityCheck
        self.inputMonitoringCheck = inputMonitoringCheck
        self.loginItemClient = loginItemClient
        loginItemStatus = loginItemClient.status()
        let savedDelay = UserDefaults.standard.double(forKey: Self.holdDelayKey)
        holdDelay = savedDelay == 0 ? 0.55 : min(max(savedDelay, 0.3), 1.2)
        foldBehaviour = UserDefaults.standard.string(forKey: Self.foldBehaviourKey)
            .flatMap(FoldBehaviour.init(rawValue:)) ?? .automatic
        panelTheme = UserDefaults.standard.string(forKey: Self.panelThemeKey)
            .flatMap(PanelTheme.init(rawValue:)) ?? .system
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
            name: application.localizedName ?? L10n.string("app.current"),
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
        shortcutLoadIssue = nil

        if let cached = shortcutCache[cacheKey] {
            groups = cached.groups
            isLoading = false
            if !forceRefresh, now.timeIntervalSince(cached.loadedAt) < Self.cacheLifetime {
                Diagnostics.shortcutScan.debug("Using a fresh shortcut cache entry")
                return
            }
        } else {
            // Never render the previous app's shortcuts beneath a new header.
            groups = []
            isLoading = true
        }

        let provider = shortcutProvider
        let scanStartedAt = ProcessInfo.processInfo.systemUptime
        Diagnostics.shortcutScan.debug("Starting shortcut scan")
        let scanTask = Task.detached(priority: .userInitiated) {
            provider.shortcuts(for: pid)
        }
        loadTask = scanTask

        Task { [weak self] in
            let result = await scanTask.value

            guard !scanTask.isCancelled,
                  let self,
                  self.applicationPID == pid,
                  self.applicationBundleIdentifier == cacheKey else { return }

            self.loadTask = nil
            let elapsedMilliseconds = Int(
                (ProcessInfo.processInfo.systemUptime - scanStartedAt) * 1_000
            )

            switch result {
            case let .success(loadedGroups):
                self.storeInCache(loadedGroups, for: cacheKey, at: Date())
                self.groups = loadedGroups
                self.shortcutLoadIssue = nil
                Diagnostics.shortcutScan.info(
                    "Shortcut scan completed in \(elapsedMilliseconds, privacy: .public) ms with \(self.shortcutCount, privacy: .public) items"
                )
            case let .timedOut(partialGroups):
                if !partialGroups.isEmpty {
                    self.groups = partialGroups
                }
                self.shortcutLoadIssue = .timedOut
                Diagnostics.shortcutScan.warning(
                    "Shortcut scan timed out after \(elapsedMilliseconds, privacy: .public) ms"
                )
            case .unavailable:
                // Deliberately leave `groups` untouched: a scan that fails must
                // never wipe content the user is already reading. The panel
                // reports the failure next to that surviving content, and falls
                // back to its retryable empty state when there was nothing yet.
                self.shortcutLoadIssue = .unavailable
                Diagnostics.shortcutScan.error(
                    "Shortcut scan failed after \(elapsedMilliseconds, privacy: .public) ms"
                )
            }

            self.isLoading = false
        }
    }

    func retryShortcutLoad() {
        loadShortcuts(forceRefresh: true)
    }

    @discardableResult
    func invalidateShortcutCache(for processID: pid_t) -> Bool {
        guard processID == applicationPID else { return false }
        shortcutCache.removeValue(forKey: applicationBundleIdentifier)
        Diagnostics.shortcutScan.debug("Invalidated shortcut cache after a menu change")
        return true
    }

    /// Marks both system prompts as already raised. Used by tests and previews to
    /// reach the "asked, still unanswered" state without touching real TCC.
    func markPermissionRequestsMadeForTesting() {
        hasRequestedAccessibility = true
        hasRequestedInputMonitoring = true
    }

    func deferPermissionSetupForSession() {
        isPermissionSetupDeferred = true
        Diagnostics.permissions.notice("Permission setup deferred for this session")
        closeOverlay()
    }

    func resumePermissionSetup() {
        isPermissionSetupDeferred = false
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
        shortcutScrollRequest = nil
    }

    /// Folds or unfolds one group. The choice is remembered for the session, so a
    /// user who opened a long group in one app does not have to open it again in
    /// the next.
    func toggleGroupExpansion(_ groupID: String) {
        expandedGroupIDs.formSymmetricDifference([groupID])
    }

    func requestShortcutScroll(_ command: ShortcutScrollCommand) {
        guard isPinned else { return }
        let revision = (shortcutScrollRequest?.revision ?? 0) &+ 1
        shortcutScrollRequest = ShortcutScrollRequest(command: command, revision: revision)
    }

    func loadPreviewData() {
        applicationName = "Safari"
        applicationIcon = NSImage(systemSymbolName: "safari", accessibilityDescription: "Safari")
        isPermissionPromptVisible = false
        isLoading = false
        shortcutLoadIssue = nil
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
        hasRequestedAccessibility = true
        closeOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.requestAccessibilityAccess()
        }
    }

    func requestInputMonitoringFromOnboarding() {
        hasRequestedInputMonitoring = true
        closeOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            CGRequestListenEventAccess()
        }
    }

    func refreshPermissionStatus() {
        permissionRevision &+= 1
    }

    func refreshLoginItemStatus() {
        let refreshedStatus = loginItemClient.status()
        if refreshedStatus != loginItemStatus {
            loginItemError = nil
        }
        loginItemStatus = refreshedStatus
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        loginItemError = nil

        do {
            try loginItemClient.setEnabled(isEnabled)
        } catch {
            loginItemStatus = loginItemClient.status()
            if loginItemStatus != .requiresApproval {
                loginItemError = error.localizedDescription
            }
            return
        }

        loginItemStatus = loginItemClient.status()
    }

    func openLoginItemsSettings() {
        loginItemClient.openSystemSettings()
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
