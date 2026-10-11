import AppKit
import SwiftUI

/// The permission a row is asking for, and what the row can honestly offer.
enum OnboardingPermissionState: Equatable {
    /// Never requested. The row can raise the system prompt itself.
    case notRequested
    /// Requested and still unanswered. macOS shows its prompt once, so asking
    /// again does nothing and the only useful route left is System Settings.
    case awaitingApproval
    /// Approved. Nothing left to do.
    case granted

    static func resolve(isGranted: Bool, hasRequested: Bool) -> OnboardingPermissionState {
        if isGranted { return .granted }
        return hasRequested ? .awaitingApproval : .notRequested
    }
}

/// First-run permission setup.
///
/// A standard titled window rather than the overlay panel it used to share.
/// Onboarding needs the user's full attention plus a trip out to System Settings
/// and back, so it has to be a real window: it stays put while the user is in
/// another app and can be moved aside. The overlay panel does the opposite by
/// design — it floats, never activates, and disappears on release — which is right
/// for a shortcut wall and wrong for setup.
///
/// The structure follows the shape every Mac permission screen uses: identity,
/// one plain-language reason, one row per permission with its own state and its
/// own action, and a single sentence about what happens next.
struct PermissionSetupView: View {
    @EnvironmentObject private var appState: AppState
    var onDismiss: () -> Void

    private var accessibilityState: OnboardingPermissionState {
        OnboardingPermissionState.resolve(
            isGranted: appState.isAccessibilityGranted,
            hasRequested: appState.hasRequestedAccessibility
        )
    }

    private var inputMonitoringState: OnboardingPermissionState {
        OnboardingPermissionState.resolve(
            isGranted: appState.isInputMonitoringGranted,
            hasRequested: appState.hasRequestedInputMonitoring
        )
    }

    private var isComplete: Bool {
        accessibilityState == .granted && inputMonitoringState == .granted
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            VStack(spacing: 0) {
                PermissionSetupRow(
                    kind: .accessibility,
                    state: accessibilityState,
                    action: primaryAction(for: accessibilityState, kind: .accessibility),
                    buttonTitle: buttonTitle(for: accessibilityState)
                )

                Divider()

                PermissionSetupRow(
                    kind: .inputMonitoring,
                    state: inputMonitoringState,
                    action: primaryAction(for: inputMonitoringState, kind: .inputMonitoring),
                    buttonTitle: buttonTitle(for: inputMonitoringState)
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
            .frame(maxWidth: 420)

            footer
        }
        .padding(24)
        .frame(width: PermissionSetupView.contentSize.width, height: PermissionSetupView.contentSize.height)
    }

    /// Fixed size for the setup screen. Declared on the view as well as the window
    /// because SwiftUI sizes a hosting view's window from the view, and an ambiguous
    /// view size puts SwiftUI and AppKit into a resize loop.
    static let contentSize = NSSize(width: 560, height: 520)

    private var header: some View {
        VStack(spacing: 6) {
            // The app icon is how a Mac window says which app is asking. The symbol
            // is only a fallback for contexts with no bundle image, such as
            // offscreen rendering.
            appIcon
                .frame(width: 58, height: 58)
                .accessibilityHidden(true)

            Text(L10n.string("onboarding.title"))
                .font(.title2.weight(.semibold))

            Text(L10n.string("onboarding.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
        }
    }

    /// What happens next, stated once. This is the sentence that stops the window
    /// feeling like a dead end while the user is over in System Settings.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(isComplete ? "onboarding.footer.done" : "onboarding.footer.pending"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(L10n.string("onboarding.not_now")) {
                appState.deferPermissionSetupForSession()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApplication.shared.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "command.square.fill")
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
        }
    }

    private func buttonTitle(for state: OnboardingPermissionState) -> String {
        switch state {
        case .notRequested: L10n.string("onboarding.allow")
        case .awaitingApproval: L10n.string("onboarding.open_settings")
        case .granted: ""
        }
    }

    /// Each permission needs its own trip through System Settings, so each row
    /// carries its own action rather than one button that has to guess.
    private func primaryAction(
        for state: OnboardingPermissionState,
        kind: PermissionKind
    ) -> () -> Void {
        switch state {
        case .notRequested:
            switch kind {
            case .accessibility: appState.requestAccessibilityFromOnboarding
            case .inputMonitoring: appState.requestInputMonitoringFromOnboarding
            }
        case .awaitingApproval:
            switch kind {
            case .accessibility: appState.openAccessibilitySettings
            case .inputMonitoring: appState.openInputMonitoringSettings
            }
        case .granted:
            {}
        }
    }
}

private struct PermissionSetupRow: View {
    let kind: PermissionKind
    let state: OnboardingPermissionState
    let action: () -> Void
    let buttonTitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                    .fontWeight(.medium)
                Text(kind.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // An explanation that only exists while it is true, rather than a
                // permanent subtitle the user has to read past every time.
                if state == .awaitingApproval {
                    Text(L10n.string("onboarding.status.waiting"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            switch state {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.string("onboarding.granted"))
            case .notRequested, .awaitingApproval:
                // The system accent colour, not a hardcoded tint, so the window
                // matches whatever accent the user has chosen.
                Button(buttonTitle, action: action)
                    .controlSize(.regular)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Owns the setup window's lifetime.
@MainActor
final class PermissionSetupWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState

    /// The setup window, once it has been built.
    private(set) var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        let window = existingOrNewWindow()
        window.center()
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func close() {
        window?.orderOut(nil)
        appState.isPermissionPromptVisible = false
    }

    /// Keeps the flag honest when the user closes the window with its own control
    /// rather than through the buttons in the view.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.appState.isPermissionPromptVisible = false
        }
    }

    @discardableResult
    func existingOrNewWindow() -> NSWindow {
        if let window { return window }

        let setupWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: PermissionSetupView.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        setupWindow.title = L10n.string("onboarding.window_title")
        setupWindow.isReleasedWhenClosed = false
        setupWindow.delegate = self
        appState.isPermissionPromptVisible = true
        // A plain hosting view in a fixed frame rather than a
        // `contentViewController`: a hosting *controller* claims ownership of the
        // window's size and SwiftUI then re-derives it on every constraint pass,
        // which looped against AppKit and aborted the app. Here the frame is
        // authoritative and SwiftUI has nothing to negotiate.
        let size = PermissionSetupView.contentSize
        let host = NSHostingView(
            rootView: PermissionSetupView(onDismiss: { [weak self] in
                self?.close()
            })
            .environmentObject(appState)
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        setupWindow.contentView = host
        setupWindow.setContentSize(size)
        window = setupWindow
        return setupWindow
    }
}
