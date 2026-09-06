import Foundation

enum L10n {
    private static let previewLocalization = CommandLine.arguments
        .first(where: { $0.hasPrefix("--preview-language=") })?
        .dropFirst("--preview-language=".count)
        .description

    private static var resourceBundle: Bundle {
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }

        if let resourceURL = Bundle.main.resourceURL,
           let embeddedBundle = Bundle(
               url: resourceURL.appendingPathComponent("Keyveil_Keyveil.bundle")
           ) {
            return embeddedBundle
        }

        return .module
    }

    private static var bundle: Bundle {
        if let previewLocalization,
           let previewBundle = localizedBundle(
               for: previewLocalization,
               in: resourceBundle
           ) {
            return previewBundle
        }
        return resourceBundle
    }

    private static func localizedBundle(
        for localization: String,
        in resourceBundle: Bundle
    ) -> Bundle? {
        let localizationURL = (resourceBundle.resourceURL ?? resourceBundle.bundleURL)
            .appendingPathComponent("\(localization.lowercased()).lproj", isDirectory: true)
        return Bundle(url: localizationURL)
    }

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: Locale.current,
            arguments: arguments
        )
    }

    static func string(_ key: String, localization: String) -> String? {
        guard let localizedBundle = localizedBundle(for: localization, in: .module) else { return nil }
        return localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(
        _ key: String,
        localization: String,
        _ arguments: CVarArg...
    ) -> String? {
        guard let format = string(key, localization: localization) else { return nil }
        return String(
            format: format,
            locale: Locale(identifier: localization),
            arguments: arguments
        )
    }
}

enum PermissionKind: CaseIterable {
    case accessibility
    case inputMonitoring

    var title: String {
        switch self {
        case .accessibility:
            L10n.string("permission.accessibility.title")
        case .inputMonitoring:
            L10n.string("permission.input_monitoring.title")
        }
    }

    var description: String {
        switch self {
        case .accessibility:
            L10n.string("permission.accessibility.description")
        case .inputMonitoring:
            L10n.string("permission.input_monitoring.description")
        }
    }

    var systemImage: String {
        switch self {
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard"
        }
    }
}
