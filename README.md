# Keyveil

> Hold Command. Reveal every shortcut.

Keyveil is a lightweight macOS menu bar utility inspired by CheatSheet. Hold the `Command` key and Keyveil reads the active app's menus, then presents its keyboard shortcuts in a clean Liquid Glass overlay. Release `Command` to dismiss it.

![Keyveil design reference](DesignPrototype/design-reference.png)

## Features

- Detects a long press of either `Command` key anywhere in macOS
- Double-tap `Command` to pin the overlay and browse without holding a key
- Reads shortcuts from the frontmost app through the macOS Accessibility API
- Groups shortcuts by their native menu sections
- Ignores normal combinations such as `Command-C`, so they do not open the overlay
- Uses native Liquid Glass on macOS 26 and a system material fallback on macOS 14–15
- Uses a large adaptive 2–3 column shortcut wall with continuous vertical scrolling, adjustable hold delay, multi-display placement, and full-screen Space support
- Caches each app's shortcuts for fast repeat display and safely ignores stale background reads
- Preserves temporarily disabled menu shortcuts and displays them with reduced emphasis
- Runs as a small menu bar app without a Dock icon

## Requirements

- macOS 14 or later
- Xcode 26 or Swift 6.2 or later to build from source; full Xcode is required to run the XCTest suite
- Accessibility permission, used only to read menu titles and shortcut metadata
- Input Monitoring permission, used only to observe Command-key state

Keyveil does not record keystrokes, window content, or typed text. The global event tap only observes modifier changes and cancels itself when another key is pressed.

## Controls

- Hold `Command`: show Keyveil temporarily
- Release `Command`: close the temporary overlay
- Double-tap `Command`: pin or unpin Keyveil
- `Escape`: close a pinned overlay
- Keep holding `Command` and use a trackpad or mouse wheel over the panel to browse more shortcuts

## Build

Build the executable with Swift Package Manager:

```bash
swift build -c release
```

Create an ad-hoc signed universal `.app` bundle and its canonical local zip artifact:

```bash
./scripts/package-app.sh release
open dist
```

The script builds both Apple silicon and Intel slices, then verifies the extracted archive. It intentionally produces only `dist/Keyveil.zip`: synced `Documents` folders can attach Finder metadata to a raw app and invalidate its signature. Unzip it, move `Keyveil.app` to `/Applications`, and only then launch it and grant permissions.

Local packages are ad-hoc signed by default. You can set `CODESIGN_IDENTITY` to a Developer ID Application identity to enable hardened-runtime signing, but a normal public download must also be notarized and stapled with your Apple Developer credentials.

On first launch, Keyveil presents a non-floating setup window for its two required permissions. Choosing **Allow** dismisses Keyveil before macOS presents the authorization interface, so the setup window never covers System Settings.

Enable Keyveil in both locations if macOS asks:

- **System Settings → Privacy & Security → Accessibility**
- **System Settings → Privacy & Security → Input Monitoring**

If a locally rebuilt copy stops responding to Command, remove its old entries from both lists, add the current app again, and relaunch. Ad-hoc development signatures change between builds.

## Development preview

To inspect the UI with deterministic sample data without granting Accessibility access:

```bash
swift run Keyveil --preview
```

Preview the first-launch permission UI without automatically requesting permissions:

```bash
swift run Keyveil --preview-permissions
```

Run the full unit, state, gesture, layout, and rendering suite:

```bash
swift test -Xswiftc -warnings-as-errors
```

Optionally export deterministic light, dark, compact, permission, and 960-shortcut stress snapshots:

```bash
mkdir -p /tmp/keyveil-snapshots
KEYVEIL_SNAPSHOT_DIR=/tmp/keyveil-snapshots swift test --filter ShortcutPanelRenderingTests
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
