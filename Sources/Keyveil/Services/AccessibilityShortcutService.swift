import ApplicationServices
import Foundation

protocol ShortcutProviding: Sendable {
    func shortcuts(for processID: pid_t) -> ShortcutScanResult
}

enum ShortcutScanResult: Equatable, Sendable {
    case success([ShortcutGroup])
    case timedOut([ShortcutGroup])
    case unavailable
}

enum ShortcutKeyFormatter {
    static func keys(commandCharacter: String, virtualKey: Int?, glyph: Int? = nil, modifiers: Int) -> [String]? {
        let primaryKey: String?
        if !commandCharacter.isEmpty {
            primaryKey = readableKey(commandCharacter)
        } else {
            primaryKey = virtualKey.flatMap(virtualKeyName) ?? glyph.flatMap(glyphName)
        }
        guard let primaryKey else { return nil }

        var keys: [String] = []

        // AXMenuItemModifiers: shift=1, option=2, control=4, no-command=8.
        if modifiers & 4 != 0 { keys.append("⌃") }
        if modifiers & 2 != 0 { keys.append("⌥") }
        if modifiers & 1 != 0 { keys.append("⇧") }
        if modifiers & 8 == 0 { keys.append("⌘") }

        keys.append(primaryKey)

        return keys
    }

    static func readableKey(_ value: String) -> String {
        switch value {
        case "\r", "\n": return "↩"
        case "\t": return "⇥"
        case " ": return "Space"
        case "\u{1b}": return "Esc"
        case "\u{7f}": return "⌫"
        default: break
        }

        if value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first {
            switch scalar.value {
            case 0xF700: return "↑"
            case 0xF701: return "↓"
            case 0xF702: return "←"
            case 0xF703: return "→"
            case 0xF704...0xF726: return "F\(scalar.value - 0xF704 + 1)"
            case 0xF727: return "Insert"
            case 0xF728: return "⌦"
            case 0xF729: return "↖"
            case 0xF72B: return "↘"
            case 0xF72C: return "⇞"
            case 0xF72D: return "⇟"
            case 0xF735: return "Menu"
            case 0xF746: return "Help"
            default: break
            }
        }

        return value.uppercased()
    }

    /// Key codes as they arrive from the menu metadata. Built once: this runs for
    /// every shortcut of every scan.
    private static let virtualKeyNames: [Int: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
        64: "F17", 79: "F18", 80: "F19", 90: "F20",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 105: "F13", 106: "F16",
        107: "F14", 109: "F10", 110: "Menu", 111: "F12",
        113: "F15", 114: "Help", 115: "↖", 116: "⇞", 117: "⌦",
        118: "F4", 119: "↘", 120: "F2", 121: "⇟", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func virtualKeyName(_ keyCode: Int) -> String? {
        virtualKeyNames[keyCode]
    }

    /// Carbon menu glyphs, for shortcuts that carry no key code.
    private static let glyphNames: [Int: String] = [
        0x02: "⇥", 0x03: "⇤", 0x04: "⌤", 0x09: "Space",
        0x0A: "⌦", 0x0B: "↩", 0x0C: "↩", 0x0D: "↩",
        0x17: "⌫", 0x1B: "Esc", 0x1C: "Clear",
        0x62: "⇞", 0x64: "←", 0x65: "→", 0x66: "↖",
        0x67: "Help", 0x68: "↑", 0x69: "↘", 0x6A: "↓",
        0x6B: "⇟", 0x6D: "Menu", 0x6E: "Power", 0x8C: "Eject"
    ]

    static func glyphName(_ glyph: Int) -> String? {
        if (0x6F...0x7A).contains(glyph) {
            return "F\(glyph - 0x6F + 1)"
        }
        if (0x87...0x89).contains(glyph) {
            return "F\(glyph - 0x87 + 13)"
        }
        if (0x8F...0x92).contains(glyph) {
            return "F\(glyph - 0x8F + 16)"
        }

        return glyphNames[glyph]
    }
}

struct AccessibilityShortcutService: ShortcutProviding {
    private let scanTimeout: TimeInterval

    init(scanTimeout: TimeInterval = 4) {
        self.scanTimeout = scanTimeout
    }

    func shortcuts(for processID: pid_t) -> ShortcutScanResult {
        guard !Task.isCancelled else { return .unavailable }

        let deadline = ProcessInfo.processInfo.systemUptime + scanTimeout

        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 1.5)
        guard let menuBar = elementAttribute(application, kAXMenuBarAttribute) else {
            return .unavailable
        }

        guard let topLevelItems = children(of: menuBar) else { return .unavailable }
        var groups: [ShortcutGroup] = []
        // A scan-wide ordinal. Real apps do repeat a menu title — Finder carries
        // three items called "Eject", for ⌘E, ⌃⌘E and ⌥⌘E — and those are distinct
        // commands. Identity has to come from position, not from the title.
        var ordinal = 0

        for menuItem in topLevelItems {
            guard !Task.isCancelled else { return .unavailable }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                return .timedOut(groups)
            }
            let title = stringAttribute(menuItem, kAXTitleAttribute)
            guard !title.isEmpty, title != "Apple" else { continue }

            var shortcuts: [ShortcutItem] = []
            var seen = Set<String>()
            let didTimeOut = collectShortcuts(
                from: menuItem,
                path: title,
                depth: 0,
                deadline: deadline,
                result: &shortcuts,
                seen: &seen,
                ordinal: &ordinal
            )
            if !shortcuts.isEmpty {
                groups.append(ShortcutGroup(title: title, shortcuts: shortcuts))
            }
            if didTimeOut {
                return .timedOut(groups)
            }
        }

        return .success(groups)
    }

    @discardableResult
    private func collectShortcuts(
        from element: AXUIElement,
        path: String,
        depth: Int,
        deadline: TimeInterval,
        result: inout [ShortcutItem],
        seen: inout Set<String>,
        ordinal: inout Int
    ) -> Bool {
        guard depth < 16, !Task.isCancelled else { return false }
        guard ProcessInfo.processInfo.systemUptime < deadline else { return true }

        guard let children = children(of: element) else { return false }
        for child in children {
            guard !Task.isCancelled else { return false }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return true }
            let role = stringAttribute(child, kAXRoleAttribute)
            let title = stringAttribute(child, kAXTitleAttribute)
            let childPath = title.isEmpty ? path : "\(path)/\(title)"

            if role == kAXMenuItemRole as String,
               !title.isEmpty,
               let keys = shortcutKeys(for: child),
               !keys.isEmpty {
                let shortcut = ShortcutItem(
                    title: normalizedTitle(title),
                    keys: keys,
                    path: childPath,
                    isEnabled: boolAttribute(child, kAXEnabledAttribute),
                    ordinal: ordinal
                )
                ordinal += 1
                if seen.insert(shortcut.id).inserted {
                    result.append(shortcut)
                }
            }

            if collectShortcuts(
                from: child,
                path: childPath,
                depth: depth + 1,
                deadline: deadline,
                result: &result,
                seen: &seen,
                ordinal: &ordinal
            ) {
                return true
            }
        }

        return false
    }

    private func shortcutKeys(for element: AXUIElement) -> [String]? {
        let commandCharacter = stringAttribute(element, kAXMenuItemCmdCharAttribute)
        let virtualKey = numberAttribute(element, kAXMenuItemCmdVirtualKeyAttribute)?.intValue
        let glyph = numberAttribute(element, kAXMenuItemCmdGlyphAttribute)?.intValue
        let modifiers = numberAttribute(element, kAXMenuItemCmdModifiersAttribute)?.intValue ?? 0
        return ShortcutKeyFormatter.keys(
            commandCharacter: commandCharacter,
            virtualKey: virtualKey,
            glyph: glyph,
            modifiers: modifiers
        )
    }

    private func normalizedTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return nil }
        return children
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    private func numberAttribute(_ element: AXUIElement, _ attribute: String) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? NSNumber
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        numberAttribute(element, attribute)?.boolValue ?? true
    }
}
