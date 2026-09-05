import AppKit
import SwiftUI

struct ShortcutPanelView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var searchIsFocused: Bool
    @State private var pageIndex = 0

    private let groupsPerPage = 3

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
        .padding(18)
        .onChange(of: appState.searchFocusRequest) { _, _ in
            searchIsFocused = true
        }
        .onChange(of: appState.filteredGroups.map(\.id)) { _, _ in
            pageIndex = 0
        }
        .onExitCommand {
            appState.closeOverlay()
        }
    }

    private var shortcutContent: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35).padding(.vertical, 18)

            if appState.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Reading shortcuts…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Spacer()
            } else if appState.filteredGroups.isEmpty {
                emptyState
            } else {
                groups
            }

            footer
        }
        .padding(24)
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
                        .font(.system(size: 24))
                }
            }
            .frame(width: 46, height: 46)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text("CURRENT APP")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.15)
                    .foregroundStyle(.secondary)
                Text(appState.applicationName)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }

            Spacer(minLength: 28)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search shortcuts", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchIsFocused)
                KeycapView(label: "⌘K", compact: true)
                    .opacity(0.62)
            }
            .padding(.horizontal, 12)
            .frame(width: 290, height: 38)
            .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(.white.opacity(0.09), lineWidth: 0.8)
            }

            Spacer(minLength: 28)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.mint)
                    .frame(width: 6, height: 6)
                    .shadow(color: .mint.opacity(0.7), radius: 5)
                KeycapView(label: "⌘", compact: true)
                Text(appState.isPinned ? "Pinned" : "Hold")
                    .foregroundStyle(.secondary)

                if appState.isPinned {
                    Button {
                        appState.closeOverlay()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Keyveil")
                }
            }
            .font(.system(size: 11))
        }
    }

    private var groups: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(visibleGroups.enumerated()), id: \.element.id) { index, group in
                    ShortcutGroupView(group: group)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 14)

                    if index < visibleGroups.count - 1 {
                        Divider().opacity(0.32)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if pageCount > 1 {
                pageControls
            }
        }
    }

    private var visibleGroups: [ShortcutGroup] {
        let groups = appState.filteredGroups
        guard !groups.isEmpty else { return [] }
        let safePage = min(pageIndex, pageCount - 1)
        let start = safePage * groupsPerPage
        let end = min(start + groupsPerPage, groups.count)
        return Array(groups[start..<end])
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(appState.filteredGroups.count) / Double(groupsPerPage))))
    }

    private var pageControls: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    pageIndex = max(0, pageIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(pageIndex == 0)

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { page in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            pageIndex = page
                        }
                    } label: {
                        Capsule()
                            .fill(.primary.opacity(page == pageIndex ? 0.62 : 0.16))
                            .frame(width: page == pageIndex ? 14 : 5, height: 5)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    pageIndex = min(pageCount - 1, pageIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(pageIndex == pageCount - 1)
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(height: 18)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(.secondary)
            Text(appState.searchText.isEmpty ? "No shortcuts found" : "No matching shortcuts")
                .font(.system(size: 13, weight: .medium))
            Text(appState.searchText.isEmpty ? "Try refreshing after granting Accessibility access." : "Try a different search term.")
                .font(.system(size: 11))
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
                if appState.isPinned {
                    Text("Press Esc or double-tap")
                    KeycapView(label: "⌘", compact: true)
                    Text("to close")
                } else {
                    Text("Release")
                    KeycapView(label: "⌘", compact: true)
                    Text("to close")
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.top, 15)
    }
}

private struct ShortcutGroupView: View {
    let group: ShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(group.title, systemImage: group.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.cyan.opacity(0.86))
                .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(group.shortcuts) { shortcut in
                        HStack(spacing: 10) {
                            Text(shortcut.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 6)
                            HStack(spacing: 3) {
                                ForEach(Array(shortcut.keys.enumerated()), id: \.offset) { _, key in
                                    KeycapView(label: key)
                                }
                            }
                        }
                        .frame(height: 42)
                        .opacity(shortcut.isEnabled ? 1 : 0.42)

                        if shortcut.id != group.shortcuts.last?.id {
                            Divider().opacity(0.24)
                        }
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
            .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
            .frame(minWidth: compact ? 17 : 20, minHeight: compact ? 17 : 20)
            .padding(.horizontal, compact ? 3 : 2)
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.13), .white.opacity(0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: compact ? 5 : 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 5 : 6, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 0.7)
            }
    }
}

private struct PermissionPromptView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 17) {
            Image(systemName: "command.square.fill")
                .font(.system(size: 48, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan)

            Text("Allow Keyveil to read shortcuts")
                .font(.system(size: 21, weight: .semibold, design: .rounded))

            Text("Keyveil reads menu titles and keyboard shortcuts from the active app.\nIt never records what you type.")
                .multilineTextAlignment(.center)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            Button("Open Accessibility Settings") {
                appState.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Not Now") {
                appState.closeOverlay()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(54)
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
