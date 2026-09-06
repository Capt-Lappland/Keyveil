import AppKit
import SwiftUI

struct ShortcutPanelView: View {
    @EnvironmentObject private var appState: AppState

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
                Text("Reading shortcuts…")
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
                Text("CURRENT APP")
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
                Text(appState.isPinned ? "Pinned" : "Hold")
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
                    .help("Close Keyveil")
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
            }
            .id(appState.overlayPresentationRevision)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(.secondary)
            Text("No shortcuts found")
                .font(.system(size: 16, weight: .medium))
            Text("Try refreshing after granting Accessibility access.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Label("\(appState.shortcutCount) shortcuts", systemImage: "sparkles")
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .accessibilityHidden(true)
                if appState.isPinned {
                    Text("Scroll if needed · Press Esc or double-tap")
                    KeycapView(label: "⌘", compact: true)
                    Text("to close")
                } else {
                    Text("Scroll if needed · Release")
                    KeycapView(label: "⌘", compact: true)
                    Text("to close")
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.top, 12)
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
                    .help(shortcut.title + (shortcut.isEnabled ? "" : " (Unavailable)"))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(shortcut.title)
                    .accessibilityValue(
                        shortcut.keys.joined(separator: " ")
                            + (shortcut.isEnabled ? "" : ", unavailable")
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

            Text("Finish setting up Keyveil")
                .font(.system(size: 21, weight: .semibold, design: .rounded))

            Text("Two macOS permissions are required. Choose one below; Keyveil will close before the system authorization appears.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: 460)

            VStack(spacing: 8) {
                PermissionStatusRow(
                    title: "Accessibility",
                    detail: "Reads menu names and shortcut metadata",
                    systemImage: "accessibility",
                    isGranted: appState.isAccessibilityGranted
                ) {
                    appState.requestAccessibilityFromOnboarding()
                }

                PermissionStatusRow(
                    title: "Input Monitoring",
                    detail: "Detects when Command is held",
                    systemImage: "keyboard",
                    isGranted: appState.isInputMonitoringGranted
                ) {
                    appState.requestInputMonitoringFromOnboarding()
                }
            }
            .frame(maxWidth: 500)

            Button("Not Now") {
                appState.closeOverlay()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(0.65))
        }
        .padding(54)
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(isGranted ? .green : .cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button(action: action) {
                    Text("Allow")
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

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
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
                            lineWidth: 0.8
                        )
                }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.17), lineWidth: 0.8)
                }
        }
    }
}
