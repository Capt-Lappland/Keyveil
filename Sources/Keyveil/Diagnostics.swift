import OSLog

enum Diagnostics {
    static let lifecycle = Logger(subsystem: "app.keyveil.mac", category: "lifecycle")
    static let permissions = Logger(subsystem: "app.keyveil.mac", category: "permissions")
    static let presentation = Logger(subsystem: "app.keyveil.mac", category: "presentation")
    static let shortcutScan = Logger(subsystem: "app.keyveil.mac", category: "shortcut-scan")
}
