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
RESOURCES_DIR="$CONTENTS_DIR/Resources"
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
    # `--arch` alone no longer separates the products: current SwiftPM writes both
    # slices to the same bin path, so the second build silently replaced the first
    # and lipo was handed the same x86_64 binary twice. Each slice therefore gets
    # its own scratch directory, which also keeps the build output out of a synced
    # Documents folder where a file provider could invalidate the signature.
    ARM64_SCRATCH="$STAGING_ROOT/build-arm64"
    X86_64_SCRATCH="$STAGING_ROOT/build-x86_64"

    DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c release \
        --triple arm64-apple-macosx14.0 --scratch-path "$ARM64_SCRATCH"
    DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c release \
        --triple x86_64-apple-macosx14.0 --scratch-path "$X86_64_SCRATCH"

    ARM64_BIN_DIR="$(DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c release \
        --triple arm64-apple-macosx14.0 --scratch-path "$ARM64_SCRATCH" --show-bin-path)"
    X86_64_BIN_DIR="$(DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c release \
        --triple x86_64-apple-macosx14.0 --scratch-path "$X86_64_SCRATCH" --show-bin-path)"

    if [[ "$ARM64_BIN_DIR" == "$X86_64_BIN_DIR" ]]; then
        echo "error: both architectures resolved to $ARM64_BIN_DIR; refusing to lipo one slice twice" >&2
        exit 1
    fi

    RESOURCE_BUNDLE_DIR="$ARM64_BIN_DIR/Keyveil_Keyveil.bundle"
else
    DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c "$CONFIGURATION"
    BUILD_BIN_DIR="$(DEVELOPER_DIR="$KEYVEIL_DEVELOPER_DIR" "$SWIFT_BIN" build -c "$CONFIGURATION" --show-bin-path)"
    RESOURCE_BUNDLE_DIR="$BUILD_BIN_DIR/Keyveil_Keyveil.bundle"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
if [[ "$CONFIGURATION" == "release" ]]; then
    "$LIPO_BIN" -create \
        "$ARM64_BIN_DIR/Keyveil" \
        "$X86_64_BIN_DIR/Keyveil" \
        -output "$MACOS_DIR/Keyveil"

    # Assert the artifact really is universal instead of trusting the build step.
    ARCHITECTURES="$("$LIPO_BIN" -archs "$MACOS_DIR/Keyveil")"
    if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
        echo "error: expected a universal binary, got '$ARCHITECTURES'" >&2
        exit 1
    fi
else
    cp "$BUILD_BIN_DIR/Keyveil" "$MACOS_DIR/Keyveil"
fi
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/IconAssets/Keyveil.icns" "$RESOURCES_DIR/Keyveil.icns"
ditto "$RESOURCE_BUNDLE_DIR" "$RESOURCES_DIR/Keyveil_Keyveil.bundle"
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
