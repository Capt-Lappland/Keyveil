import AppKit
import Combine
import SwiftUI

/// What the header status light reports. It is derived entirely from what the
/// user is looking at, so the light can never claim availability while the wall
/// is empty, still loading, or reduced to earlier results.
enum ShortcutPanelStatus: Equatable {
    case ready
    case loading
    case stale
    case failed

    static func resolve(
        isLoading: Bool,
        hasShortcuts: Bool,
        issue: ShortcutLoadIssue?
    ) -> ShortcutPanelStatus {
        if isLoading { return .loading }
        guard hasShortcuts else { return .failed }
        return issue == nil ? .ready : .stale
    }
}

struct ShortcutPanelView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var scrollController = ShortcutScrollController()
    @State private var searchQuery = ""

    var body: some View {
        ZStack {
            // Keep the expensive optical material on a static layer. Applying
            // glassEffect to the scrolling subtree forces it to re-composite
            // continuously while the trackpad is moving.
            LiquidGlassSurface(cornerRadius: 30)
                .allowsHitTesting(false)

            shortcutContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Shared with the surface: the window shadow is disabled, so this inset is
        // the entire margin the drawn shadow has to fade out inside.
        .padding(PanelSurfaceStyle.surfaceInset)
        .onExitCommand {
            appState.closeOverlay()
        }
    }

    private var shortcutContent: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35).padding(.vertical, 16)

            if appState.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text(L10n.string("panel.loading"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer()
            } else if isSearchEmpty {
                searchEmptyState
            } else if appState.groups.isEmpty {
                emptyState
            } else {
                groups
            }

            footer
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Group {
                if let icon = appState.applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 30))
                }
            }
            .frame(width: 60, height: 60)
            .shadow(color: .black.opacity(0.20), radius: 7, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("panel.current_app"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                Text(appState.applicationName)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }

            Spacer(minLength: 40)

            HStack(spacing: 10) {
                searchField
                HStack(spacing: 8) {
                    ShortcutStatusIndicator(status: shortcutStatus)
                    KeycapView(label: "⌘", compact: true)
                    Text(
                        appState.isPinned
                            ? L10n.string("panel.pinned")
                            : L10n.string("panel.hold")
                    )
                        .foregroundStyle(.secondary)

                    if appState.isPinned {
                        Button {
                            appState.closeOverlay()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.string("panel.close"))
                    }
                }
                .font(.system(size: 13, weight: .medium))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(L10n.string("panel.search.placeholder"), text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 150)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L10n.string("panel.search.clear"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.primary.opacity(0.07))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.primary.opacity(0.12), lineWidth: 0.7)
        }
    }

    private var groups: some View {
        GeometryReader { proxy in
            // The row budget comes from the height actually available, and drives
            // both which groups fold and how many rows each shows.
            let rowBudget = ShortcutColumnLayout.visibleRowBudget(
                forColumnHeight: proxy.size.height
            )
            let sections = displayedSections(rowBudget: rowBudget)
            let columnCount = ShortcutColumnLayout.columnCount(
                forWidth: proxy.size.width,
                groupCount: sections.count
            )
            let columns = ShortcutColumnLayout.balanced(
                sections.map(\.group),
                columnCount: columnCount
            )
            let sectionsByID = Dictionary(
                uniqueKeysWithValues: sections.map { ($0.id, $0) }
            )

            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(columns.indices, id: \.self) { index in
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(columns[index]) { group in
                                if let section = sectionsByID[group.id] {
                                    ShortcutGroupView(
                                        section: section,
                                        accent: accent,
                                        onToggleExpansion: {
                                            appState.toggleGroupExpansion(section.id)
                                        }
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, 18)

                        if index < columns.count - 1 {
                            Divider().opacity(0.28)
                        }
                    }
                }
                .padding(.vertical, 2)
                .background {
                    ScrollViewResolver { scrollView in
                        scrollController.attach(scrollView)
                    }
                }
            }
            .id(appState.overlayPresentationRevision)
            // A new query means a new wall, so start reading it from the top
            // rather than leaving the scroll position where the old one ended.
            .onChange(of: searchQuery) { _, _ in
                scrollController.perform(.home)
            }
            .onChange(of: appState.shortcutScrollRequest) { _, request in
                guard let request else { return }
                scrollController.perform(request.command)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: emptyStateSymbol)
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.system(size: 16, weight: .medium))
            Text(emptyStateDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if appState.shortcutLoadIssue != nil {
                Button {
                    appState.retryShortcutLoad()
                } label: {
                    Label(L10n.string("panel.error.retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(.secondary)
            Text(L10n.string("panel.search.no_results.title"))
                .font(.system(size: 16, weight: .medium))
            Text(L10n.string("panel.search.no_results.description"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateSymbol: String {
        switch appState.shortcutLoadIssue {
        case .timedOut: "clock.badge.exclamationmark"
        case .unavailable: "exclamationmark.triangle"
        case nil: "keyboard.badge.ellipsis"
        }
    }

    private var emptyStateTitle: String {
        switch appState.shortcutLoadIssue {
        case .timedOut: L10n.string("panel.error.timeout.title")
        case .unavailable: L10n.string("panel.error.unavailable.title")
        case nil: L10n.string("panel.empty.title")
        }
    }

    private var emptyStateDescription: String {
        switch appState.shortcutLoadIssue {
        case .timedOut: L10n.string("panel.error.timeout.description")
        case .unavailable: L10n.string("panel.error.unavailable.description")
        case nil: L10n.string("panel.empty.description")
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 12) {
                Label(
                    L10n.format("panel.shortcut_count", Int64(displayedShortcutCount)),
                    systemImage: "sparkles"
                )

                // Only explain a failure on top of content that is actually on
                // screen. With nothing to show, the empty state already names
                // the failure, and a "showing last results" badge would point
                // at results that do not exist.
                if appState.shortcutLoadIssue != nil, displayedShortcutCount > 0 {
                    Label(
                        footerIssueLabel,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .accessibilityHidden(true)
                if appState.isPinned {
                    Text(L10n.string("panel.footer.pinned_navigation"))
                } else {
                    Text(L10n.string("panel.footer.held_before_key"))
                    KeycapView(label: "⌘", compact: true)
                    Text(L10n.string("panel.footer.close_after_key"))
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.top, 12)
    }

    private func makePlan(rowBudget: Int) -> WallPlan {
        ShortcutWallPlan.makePlan(
            groups: appState.groups,
            expandedIDs: appState.expandedGroupIDs,
            commonGroupTitle: L10n.string("panel.group.common"),
            revealLimit: appState.foldBehaviour.revealLimit(rowBudget: rowBudget)
        )
    }

    /// The user's theme choice, or the system accent when they left it alone.
    private var accent: Color {
        switch appState.panelTheme.accentName {
        case nil: .accentColor
        case "monochrome": Color(white: 0.55)
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        default: .accentColor
        }
    }

    /// What the wall actually shows.
    ///
    /// With no query this is the plan as folded. While searching, folding is
    /// suspended and every section is narrowed to its matches instead — otherwise a
    /// shortcut sitting inside a folded group or inside the folded Common group
    /// would be unfindable, which is exactly the case search exists to serve.
    private func displayedSections(rowBudget: Int) -> [WallSection] {
        let base = makePlan(rowBudget: rowBudget)
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base.sections
        }

        return base.sections.compactMap { section -> WallSection? in
            let matches = ShortcutQuery.filter([section.group], matching: searchQuery)
            guard let narrowed = matches.first else { return nil }
            return WallSection(
                id: section.id,
                group: narrowed,
                isCollapsed: false,
                canCollapse: section.canCollapse,
                revealLimit: section.revealLimit,
                originHints: section.originHints
            )
        }
    }

    private var displayedShortcutCount: Int {
        displayedSections(rowBudget: ShortcutWallPlan.revealLimit)
            .reduce(0) { $0 + $1.group.shortcuts.count }
    }

    private var isSearchEmpty: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && displayedShortcutCount == 0
    }

    private var shortcutStatus: ShortcutPanelStatus {
        ShortcutPanelStatus.resolve(
            isLoading: appState.isLoading,
            hasShortcuts: appState.shortcutCount > 0,
            issue: appState.shortcutLoadIssue
        )
    }

    private var footerIssueLabel: String {
        switch appState.shortcutLoadIssue {
        case .timedOut:
            L10n.string("panel.error.partial_results")
        case .unavailable:
            L10n.string("panel.error.cached_results")
        case nil:
            ""
        }
    }
}

@MainActor
final class ShortcutScrollController: ObservableObject {
    private weak var scrollView: NSScrollView?
    private var pendingCommand: ShortcutScrollCommand?

    func attach(_ scrollView: NSScrollView) {
        self.scrollView = scrollView
        if let pendingCommand {
            self.pendingCommand = nil
            perform(pendingCommand)
        }
    }

    func perform(_ command: ShortcutScrollCommand) {
        guard let scrollView, let documentView = scrollView.documentView else {
            pendingCommand = command
            return
        }

        scrollView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let minimumY = documentView.bounds.minY
        let maximumY = max(minimumY, documentView.bounds.maxY - clipView.bounds.height)
        let currentY = clipView.bounds.minY
        let lineDistance: CGFloat = 52
        let pageDistance = max(80, clipView.bounds.height * 0.82)
        let targetY: CGFloat

        switch command {
        case .lineUp:
            targetY = currentY - lineDistance
        case .lineDown:
            targetY = currentY + lineDistance
        case .pageUp:
            targetY = currentY - pageDistance
        case .pageDown:
            targetY = currentY + pageDistance
        case .home:
            targetY = minimumY
        case .end:
            targetY = maximumY
        }

        let clampedY = min(max(targetY, minimumY), maximumY)
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: clampedY))
        scrollView.reflectScrolledClipView(clipView)
    }
}

private struct ScrollViewResolver: NSViewRepresentable {
    let onResolve: @MainActor (NSScrollView) -> Void

    func makeNSView(context: Context) -> ScrollViewProbe {
        let view = ScrollViewProbe()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: ScrollViewProbe, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveEnclosingScrollView()
    }
}

private final class ScrollViewProbe: NSView {
    var onResolve: (@MainActor (NSScrollView) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveEnclosingScrollView()
    }

    func resolveEnclosingScrollView() {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                onResolve?(scrollView)
                return
            }
            ancestor = view.superview
        }
    }
}

/// Applies `help` only when there is something to say, so rows without a
/// tooltip do not pay for an empty one.
private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

private struct ShortcutStatusIndicator: View {
    let status: ShortcutPanelStatus

    private var tint: Color {
        switch status {
        case .ready: .mint
        case .loading: .secondary
        case .stale: .orange
        case .failed: .red
        }
    }

    private var label: String {
        switch status {
        case .ready: L10n.string("panel.status.ready")
        case .loading: L10n.string("panel.status.loading")
        case .stale: L10n.string("panel.status.stale")
        case .failed: L10n.string("panel.status.failed")
        }
    }

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .shadow(color: status == .loading ? .clear : tint.opacity(0.7), radius: 5)
            .help(label)
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}

private struct ShortcutGroupView: View {
    let section: WallSection
    /// Resolved accent for headers and the fold control.
    let accent: Color
    let onToggleExpansion: () -> Void

    private var group: ShortcutGroup { section.group }

    private var visibleShortcuts: [ShortcutItem] { section.visibleShortcuts }

    private var hiddenCount: Int { section.hiddenCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 0) {
                ForEach(visibleShortcuts) { shortcut in
                    shortcutRow(shortcut)

                    if shortcut.id != visibleShortcuts.last?.id {
                        Divider().opacity(0.24)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label(group.title, systemImage: group.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .accessibilityAddTraits(.isHeader)

            if section.canCollapse {
                // The disclosure lives in the header on purpose. Placed at the end of
                // the list it falls below the visible area — a group long enough to
                // fold is by definition taller than one screen — which makes the fold
                // invisible and therefore useless.
                Button(action: onToggleExpansion) {
                    HStack(spacing: 3) {
                        Text(
                            section.isCollapsed
                                ? L10n.format("panel.group.folded_count", Int64(group.shortcuts.count))
                                : L10n.string("panel.group.collapse")
                        )
                        Image(systemName: section.isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.14)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(disclosureHelp)
                .accessibilityLabel(disclosureHelp)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
    }

    private var disclosureHelp: String {
        section.isCollapsed
            ? L10n.format("panel.group.show_more", Int64(hiddenCount))
            : L10n.string("panel.group.collapse")
    }

    private func shortcutRow(_ shortcut: ShortcutItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(shortcut.title)
                    .font(.system(size: 15))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .truncationMode(.middle)
                    .foregroundStyle(shortcut.isEnabled ? Color.primary : Color.secondary)

                // Inside the aggregated Common group it matters which menu the
                // shortcut came from, so the inherited block stays traceable.
                if let origin = section.originHints[
                    WallSection.originKey(groupTitle: group.title, itemTitle: shortcut.title)
                ] {
                    Text(origin)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(Array(shortcut.keys.enumerated()), id: \.offset) { _, key in
                    KeycapView(label: key)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .opacity(shortcut.isEnabled ? 1 : 0.68)
        }
        .frame(minHeight: 43)
        // A tooltip per row means a tracking area per row, which gets expensive on
        // the 900-shortcut stress case. The title is already on screen, so only the
        // disabled state needs one.
        .modifier(OptionalHelp(text: shortcut.isEnabled
            ? nil
            : shortcut.title + L10n.string("panel.shortcut.unavailable_suffix")))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.title)
        .accessibilityValue(
            shortcut.keys.joined(separator: " ")
                + (shortcut.isEnabled
                    ? ""
                    : L10n.string("panel.shortcut.unavailable_accessibility_suffix"))
        )
    }

}

struct KeycapView: View {
    let label: String
    var compact = false

    var body: some View {
        Text(label)
            .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .frame(minWidth: compact ? 22 : 26, minHeight: compact ? 22 : 26)
            .padding(.horizontal, compact ? 4 : 3)
            .background(
                LinearGradient(
                    colors: [.primary.opacity(0.12), .primary.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
                    .stroke(.primary.opacity(0.15), lineWidth: 0.7)
            }
    }
}
