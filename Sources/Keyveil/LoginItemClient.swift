import ServiceManagement

enum LoginItemStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isOn: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
struct LoginItemClient {
    let status: () -> LoginItemStatus
    let setEnabled: (Bool) throws -> Void
    let openSystemSettings: () -> Void

    static var live: LoginItemClient {
        LoginItemClient(
            status: {
                switch SMAppService.mainApp.status {
                case .notRegistered:
                    .disabled
                case .enabled:
                    .enabled
                case .requiresApproval:
                    .requiresApproval
                case .notFound:
                    .unavailable
                @unknown default:
                    .unavailable
                }
            },
            setEnabled: { isEnabled in
                if isEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            },
            openSystemSettings: {
                SMAppService.openSystemSettingsLoginItems()
            }
        )
    }
}
