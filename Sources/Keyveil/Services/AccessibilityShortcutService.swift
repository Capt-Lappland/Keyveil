import ApplicationServices
import Foundation

struct AccessibilityShortcutService: Sendable {
    func shortcuts(for processID: pid_t) -> [ShortcutGroup] {
        let application = AXUIElementCreateApplication(processID)
        guard let menuBar = elementAttribute(application, kAXMenuBarAttribute) else {
            return []
        }

        let topLevelItems = children(of: menuBar)
        return topLevelItems.compactMap { menuItem in
            let title = stringAttribute(menuItem, kAXTitleAttribute)
            guard !title.isEmpty, title != "Apple" else { return nil }

            let shortcuts = collectShortcuts(from: menuItem, path: title)
            guard !shortcuts.isEmpty else { return nil }
            return ShortcutGroup(title: title, shortcuts: shortcuts)
        }
    }

    private func collectShortcuts(from element: AXUIElement, path: String) -> [ShortcutItem] {
        var result: [ShortcutItem] = []
        for child in children(of: element) {
            let role = stringAttribute(child, kAXRoleAttribute)
            let title = stringAttribute(child, kAXTitleAttribute)
            let childPath = title.isEmpty ? path : "\(path)/\(title)"

            if role == kAXMenuItemRole as String,
               !title.isEmpty,
               boolAttribute(child, kAXEnabledAttribute),
               let keys = shortcutKeys(for: child),
               !keys.isEmpty {
                result.append(ShortcutItem(title: normalizedTitle(title), keys: keys, path: childPath))
            }

            result.append(contentsOf: collectShortcuts(from: child, path: childPath))
        }

        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    private func shortcutKeys(for element: AXUIElement) -> [String]? {
        let commandCharacter = stringAttribute(element, kAXMenuItemCmdCharAttribute)
        let virtualKey = numberAttribute(element, kAXMenuItemCmdVirtualKeyAttribute)?.intValue
        guard !commandCharacter.isEmpty || virtualKey != nil else { return nil }

        let modifiers = numberAttribute(element, kAXMenuItemCmdModifiersAttribute)?.intValue ?? 0
        var keys: [String] = []

        // AXMenuItemModifiers: shift=1, option=2, control=4, no-command=8.
        if modifiers & 4 != 0 { keys.append("⌃") }
        if modifiers & 2 != 0 { keys.append("⌥") }
        if modifiers & 1 != 0 { keys.append("⇧") }
        if modifiers & 8 == 0 { keys.append("⌘") }

        if !commandCharacter.isEmpty {
            keys.append(readableKey(commandCharacter))
        } else if let virtualKey, let key = virtualKeyName(virtualKey) {
            keys.append(key)
        }
        return keys
    }

    private func normalizedTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readableKey(_ value: String) -> String {
        switch value {
        case "\r", "\n": return "↩"
        case "\t": return "⇥"
        case " ": return "Space"
        case "\u{1b}": return "Esc"
        case "\u{7f}": return "⌫"
        default: return value.uppercased()
        }
    }

    private func virtualKeyName(_ keyCode: Int) -> String? {
        let keys: [Int: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
            115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keys[keyCode]
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
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
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return true }
        return (value as? NSNumber)?.boolValue ?? true
    }
}
