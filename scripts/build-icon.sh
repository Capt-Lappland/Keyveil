#!/bin/zsh
set -euo pipefail

# Builds IconAssets/Keyveil.icns from the Icon Composer document
# IconAssets/Keyveil.icon using Xcode's `ictool` — the renderer behind the Xcode
# asset pipeline — instead of hand-assembling a 1024pt square with `iconutil`.
#
# Usage:
#   scripts/build-icon.sh [icon-document] [output-icns]
#
# Environment:
#   XCODE_APP           override the Xcode location (default: the `xcode-select -p` parent)
#   RENDITION           Default | Dark | TintedLight | TintedDark | ClearLight | ClearDark
#   DESIGN_GENERATION   26 | 27 (default: whatever generation ictool ships with)
#   GRID                artwork share of the icon canvas, in 1024ths (default 1024, see below)
#
# GRID controls the transparent margin around the artwork:
#
#   1024 (default)  Full bleed. This is what macOS 26 and later want. The system
#                   re-fits the artwork into its own rounded-square enclosure, and
#                   whatever the artwork does not cover is filled with the system's
#                   plate. With the artwork at 80.5% that plate shows up as a light
#                   frame around a dark icon, and the artwork's core shrinks from
#                   12px to 10px at 16px. Full bleed matches the proportions of
#                   Apple's own icons (Calculator's 16px rep is 75% artwork inside
#                   an 88% opaque footprint, the same as ours).
#   824             The classic pre-Tahoe grid, e.g. macOS 14 and 15, which draw the
#                   .icns as-is and need the artwork inset so the icon keeps a shadow
#                   margin. On macOS 26+ this variant renders the icon slightly small
#                   with a visible light frame at 16-32px.

PROJECT_DIR="${0:A:h:h}"
ICON_DOC="${1:-$PROJECT_DIR/IconAssets/Keyveil.icon}"
OUTPUT_ICNS="${2:-$PROJECT_DIR/IconAssets/Keyveil.icns}"
RENDITION="${RENDITION:-Default}"
DESIGN_GENERATION="${DESIGN_GENERATION:-}"
GRID="${GRID:-1024}"

if (( GRID < 512 || GRID > 1024 )); then
    echo "error: GRID must be between 512 and 1024, got $GRID" >&2
    exit 1
fi

python3 -c "import PIL" 2>/dev/null || {
    echo "error: python3 with Pillow is required to assemble the iconset (pip install pillow)" >&2
    exit 1
}

DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
XCODE_APP="${XCODE_APP:-${DEVELOPER_DIR_PATH%%/Contents/Developer}}"
ICTOOL="$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

if [[ ! -x "$ICTOOL" ]]; then
    echo "error: ictool not found at $ICTOOL" >&2
    echo "       It ships inside Xcode 26 or later (Icon Composer). Set XCODE_APP=/path/to/Xcode.app." >&2
    exit 1
fi
[[ -d "$ICON_DOC" ]] || { echo "error: icon document not found: $ICON_DOC" >&2; exit 1; }

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/keyveil-icon.XXXXXX")"
ICONSET_DIR="$STAGING_ROOT/Keyveil.iconset"
cleanup() { rm -rf "$STAGING_ROOT"; }
trap cleanup EXIT
mkdir -p "$ICONSET_DIR"

render() {
    # render <pixel-size> <destination>
    local size="$1" destination="$2"
    local args=(--export-image --output-file "$destination" --platform macOS
                --rendition "$RENDITION" --width "$size" --height "$size" --scale 1)
    [[ -n "$DESIGN_GENERATION" ]] && args+=(--design-generation "$DESIGN_GENERATION")
    "$ICTOOL" "$ICON_DOC" "${args[@]}" >/dev/null
    [[ -s "$destination" ]] || { echo "error: ictool produced no image for ${size}px" >&2; exit 1; }
}

# One artwork render per distinct pixel size, shared by the entries that need it.
# Sizes are rendered natively rather than downscaled: ictool renders each size the
# way the asset pipeline would.
entries=("16 1" "16 2" "32 1" "32 2" "128 1" "128 2" "256 1" "256 2" "512 1" "512 2")
for entry in "${entries[@]}"; do
    base="${entry%% *}"
    scale="${entry##* }"
    canvas=$(( base * scale ))
    inner=$(( (canvas * GRID + 512) / 1024 ))
    suffix=""
    (( scale == 2 )) && suffix="@2x"

    art="$STAGING_ROOT/art-${canvas}.png"
    [[ -f "$art" ]] || render "$inner" "$art"

    OUT="$ICONSET_DIR/icon_${base}x${base}${suffix}.png" python3 - "$art" "$canvas" <<'PY'
import os, sys
from PIL import Image
art = Image.open(sys.argv[1]).convert("RGBA")
canvas = int(sys.argv[2])
page = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
offset = (canvas - art.width) // 2
page.paste(art, (offset, offset))
page.save(os.environ["OUT"])
PY
done

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

# Verify the artifact instead of trusting the toolchain.
OUTPUT_ICNS="$OUTPUT_ICNS" GRID="$GRID" python3 - <<'PY'
import os, subprocess, sys, tempfile
from PIL import Image

path = os.environ["OUTPUT_ICNS"]
grid = int(os.environ["GRID"]) / 1024
expected = {16, 32, 64, 128, 256, 512, 1024}
with tempfile.TemporaryDirectory() as tmp:
    check_dir = os.path.join(tmp, "verify.iconset")
    subprocess.run(["iconutil", "-c", "iconset", path, "-o", check_dir], check=True)
    sizes = set()
    for name in os.listdir(check_dir):
        sizes.add(Image.open(os.path.join(check_dir, name)).width)
    missing = expected - sizes
    if missing:
        print(f"error: icns is missing sizes: {sorted(missing)}", file=sys.stderr)
        sys.exit(1)

    largest = Image.open(os.path.join(check_dir, "icon_512x512@2x.png")).convert("RGBA")
    opaque = largest.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    box = opaque.getbbox()
    share = (box[2] - box[0]) / largest.width
    if abs(share - grid) > 0.02:
        print(f"error: artwork covers {share:.1%} of the canvas, expected about {grid:.1%}", file=sys.stderr)
        sys.exit(1)
    if grid < 1024:
        corners = [(0, 0), (largest.width - 1, 0), (0, largest.height - 1), (largest.width - 1, largest.height - 1)]
        for corner in corners:
            if largest.getpixel(corner)[3] != 0:
                print(f"error: corner {corner} is opaque; the icon has no shadow margin", file=sys.stderr)
                sys.exit(1)

print(f"verified {path}: sizes {sorted(sizes)}, artwork at {share:.1%} of the canvas, grid {os.environ['GRID']}/1024")
PY

echo "Wrote $OUTPUT_ICNS"
