#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
CONFIGURATION="${1:-release}"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$PROJECT_DIR/dist/Keyveil.app"
ARCHIVE_PATH="$DIST_DIR/Keyveil.zip"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/keyveil-package.XXXXXX")"
STAGED_APP="$STAGING_ROOT/Keyveil.app"
CONTENTS_DIR="$STAGED_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
KEYVEIL_DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
SWIFT_BIN="$(DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" /usr/bin/xcrun --find swift)"
LIPO_BIN="$(DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" /usr/bin/xcrun --find lipo)"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
mkdir -p "$DIST_DIR"

if [[ "$CONFIGURATION" == "release" ]]; then
    DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c release --arch arm64
    DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c release --arch x86_64
    ARM64_BIN_DIR="$(DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c release --arch arm64 --show-bin-path)"
    X86_64_BIN_DIR="$(DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c release --arch x86_64 --show-bin-path)"
else
    DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c "$CONFIGURATION"
    BUILD_BIN_DIR="$(DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c "$CONFIGURATION" --show-bin-path)"
fi

mkdir -p "$MACOS_DIR"
if [[ "$CONFIGURATION" == "release" ]]; then
    "$LIPO_BIN" -create \
        "$ARM64_BIN_DIR/Keyveil" \
        "$X86_64_BIN_DIR/Keyveil" \
        -output "$MACOS_DIR/Keyveil"
else
    cp "$BUILD_BIN_DIR/Keyveil" "$MACOS_DIR/Keyveil"
fi
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
xattr -cr "$STAGED_APP"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$STAGED_APP"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$STAGED_APP"
fi
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

# The zip is the canonical local distribution artifact. FileProvider may attach
# Finder metadata to a raw .app placed inside Documents after packaging, but
# it cannot alter the already archived bundle contents.
rm -rf "$APP_DIR"
rm -f "$ARCHIVE_PATH"
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc --noextattr "$STAGED_APP" "$ARCHIVE_PATH"

ZIP_VERIFY_DIR="$STAGING_ROOT/zip-verification"
mkdir -p "$ZIP_VERIFY_DIR"
ditto -x -k "$ARCHIVE_PATH" "$ZIP_VERIFY_DIR"
codesign --verify --deep --strict --verbose=2 "$ZIP_VERIFY_DIR/Keyveil.app"

echo "Created $ARCHIVE_PATH"
