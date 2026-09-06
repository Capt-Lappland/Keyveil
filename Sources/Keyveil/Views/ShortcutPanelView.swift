import AppKit
import Combine
import SwiftUI

struct ShortcutPanelView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var scrollController = ShortcutScrollController()

    var body: some View {
        ZStack {
            // Keep the expensive optical material on a static layer. Applying
            // glassEffect to the scrolling subtree forces it to re-composite
            // continuously while the trackpad is moving.
            LiquidGlassSurface(cornerRadius: 30)
                .allowsHitTesting(false)

            Group {
                if appState.isPermissionPromptVisible {
                    PermissionPromptView()
                } else {
                    shortcutContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
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

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.mint)
                    .frame(width: 8, height: 8)
                    .shadow(color: .mint.opacity(0.7), radius: 5)
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

    private var groups: some View {
        GeometryReader { proxy in
            let columnCount = ShortcutColumnLayout.columnCount(
                forWidth: proxy.size.width,
                groupCount: appState.groups.count
            )
            let columns = ShortcutColumnLayout.balanced(appState.groups, columnCount: columnCount)

            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(columns.indices, id: \.self) { index in
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(columns[index]) { group in
                                ShortcutGroupView(group: group)
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
                    L10n.format("panel.shortcut_count", Int64(appState.shortcutCount)),
                    systemImage: "sparkles"
                )

                if appState.shortcutLoadIssue != nil, !appState.groups.isEmpty {
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

private struct ShortcutGroupView: View {
    let group: ShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(group.title, systemImage: group.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.86))
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)

            LazyVStack(spacing: 0) {
                ForEach(group.shortcuts) { shortcut in
                    HStack(spacing: 12) {
                        Text(shortcut.title)
                            .font(.system(size: 15))
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                            .truncationMode(.middle)
                            .foregroundStyle(shortcut.isEnabled ? Color.primary : Color.secondary)
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
                    .help(
                        shortcut.title
                            + (shortcut.isEnabled
                                ? ""
                                : L10n.string("panel.shortcut.unavailable_suffix"))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(shortcut.title)
                    .accessibilityValue(
                        shortcut.keys.joined(separator: " ")
                            + (shortcut.isEnabled
                                ? ""
                                : L10n.string("panel.shortcut.unavailable_accessibility_suffix"))
                    )

                    if shortcut.id != group.shortcuts.last?.id {
                        Divider().opacity(0.24)
                    }
                }
            }
        }
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

private struct PermissionPromptView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 42, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan)

            Text(L10n.string("onboarding.title"))
                .font(.system(size: 21, weight: .semibold, design: .rounded))

            Text(L10n.string("onboarding.description"))
                .multilineTextAlignment(.center)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: 460)

            VStack(spacing: 8) {
                PermissionStatusRow(
                    kind: .accessibility,
                    isGranted: appState.isAccessibilityGranted
                ) {
                    appState.requestAccessibilityFromOnboarding()
                }

                PermissionStatusRow(
                    kind: .inputMonitoring,
                    isGranted: appState.isInputMonitoringGranted
                ) {
                    appState.requestInputMonitoringFromOnboarding()
                }
            }
            .frame(maxWidth: 500)

            Button(L10n.string("onboarding.not_now")) {
                appState.deferPermissionSetupForSession()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(0.65))
        }
        .padding(54)
    }
}

private struct PermissionStatusRow: View {
    let kind: PermissionKind
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(isGranted ? .green : .cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(kind.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Label(L10n.string("onboarding.granted"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button(action: action) {
                    Text(L10n.string("onboarding.allow"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(.cyan.gradient, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.primary.opacity(0.10), lineWidth: 0.7)
        }
    }
}

private struct LiquidGlassSurface: View {
    let cornerRadius: CGFloat
    @State private var displayOptionsRevision = 0

    private var reduceTransparency: Bool {
        _ = displayOptionsRevision
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var increaseContrast: Bool {
        _ = displayOptionsRevision
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    var body: some View {
        Group {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.primary.opacity(0.42), lineWidth: increaseContrast ? 1.5 : 0.8)
                    }
                    .onAppear {
                        Diagnostics.presentation.notice("Using an opaque overlay for Reduce Transparency")
                    }
            } else if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.32), .cyan.opacity(0.10), .purple.opacity(0.08), .white.opacity(0.16)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: increaseContrast ? 1.5 : 0.8
                            )
                    }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                .white.opacity(increaseContrast ? 0.38 : 0.17),
                                lineWidth: increaseContrast ? 1.5 : 0.8
                            )
                    }
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            )
        ) { _ in
            displayOptionsRevision &+= 1
        }
    }
}
