# Keyveil

> Hold Command. Reveal every shortcut.

Keyveil is a lightweight macOS menu bar utility inspired by CheatSheet. Hold the `Command` key and Keyveil reads the active app's menus, then presents its keyboard shortcuts in a clean Liquid Glass overlay. Release `Command` to dismiss it.

![Keyveil design reference](DesignPrototype/design-reference.png)

## Features

- Detects a long press of either `Command` key anywhere in macOS
- Reads shortcuts from the frontmost app through the macOS Accessibility API
- Groups shortcuts by their native menu sections
- Ignores normal combinations such as `Command-C`, so they do not open the overlay
- Uses native Liquid Glass on macOS 26 and a system material fallback on macOS 14–15
- Includes search, adjustable hold delay, multi-display placement, and full-screen Space support
- Runs as a small menu bar app without a Dock icon

## Requirements

- macOS 14 or later
- Swift 6.2 or later to build from source
- Accessibility permission, used only to read menu titles and shortcut metadata

Keyveil does not record keystrokes, window content, or typed text. The global event tap only observes modifier changes and cancels itself when another key is pressed.

## Build

Build the executable with Swift Package Manager:

```bash
swift build -c release
```

Create a signed local `.app` bundle:

```bash
./scripts/package-app.sh release
open dist/Keyveil.app
```

The first launch opens the macOS Accessibility permission prompt. Enable Keyveil under **System Settings → Privacy & Security → Accessibility**, then relaunch it.

## Development preview

To inspect the UI with deterministic sample data without granting Accessibility access:

```bash
swift run Keyveil --preview
```

The original browser-based interaction study is preserved in [`DesignPrototype`](DesignPrototype/).

## Architecture

```text
CommandHoldMonitor
        │ long hold / release
        ▼
    AppDelegate ─── frontmost app ─── NSWorkspace
        │
        ├── menu shortcuts ────────── AccessibilityShortcutService
        │
        └── presentation ──────────── NSPanel + SwiftUI Liquid Glass
```

## Privacy

All processing stays on the Mac. Keyveil has no analytics, network client, account system, or cloud service.

## License

MIT
