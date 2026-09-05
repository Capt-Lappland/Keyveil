import AppKit
import SwiftUI

struct ShortcutPanelView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isPermissionPromptVisible {
                PermissionPromptView()
            } else {
                shortcutContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassPanel(cornerRadius: 30)
        .padding(18)
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
                Text("Hold")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
        }
    }

    private var groups: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(Array(appState.filteredGroups.enumerated()), id: \.element.id) { index, group in
                    ShortcutGroupView(group: group)
                        .frame(width: 238)
                        .padding(.horizontal, 14)

                    if index < appState.filteredGroups.count - 1 {
                        Divider().opacity(0.32)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
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
                Text("Release")
                KeycapView(label: "⌘", compact: true)
                Text("to close")
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

            ForEach(group.shortcuts.prefix(8)) { shortcut in
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

                if shortcut.id != group.shortcuts.prefix(8).last?.id {
                    Divider().opacity(0.24)
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
            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
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
                NSApp.windows.first(where: { $0 is OverlayPanel })?.orderOut(nil)
                appState.isPermissionPromptVisible = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(54)
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassPanel(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self
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
                .shadow(color: .black.opacity(0.42), radius: 34, y: 20)
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.17), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.42), radius: 34, y: 20)
        }
    }
}
