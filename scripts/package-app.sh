#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
APP_DIR="$PROJECT_DIR/dist/Keyveil.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$PROJECT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$PROJECT_DIR/.build/$CONFIGURATION/Keyveil" "$MACOS_DIR/Keyveil"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

echo "Created $APP_DIR"
