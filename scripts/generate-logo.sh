#!/bin/bash
# ============================================================
#  Generate a placeholder Minima logo PNG for Plymouth.
#  Replace overlay/usr/share/plymouth/themes/minima/logo.png
#  with the real Minima logo (recommended: 200x200, transparent PNG).
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$SCRIPT_DIR/../overlay/usr/share/plymouth/themes/minima/logo.png"

if command -v convert &>/dev/null; then
    # ImageMagick available — generate a simple placeholder
    convert -size 200x200 xc:transparent \
        -fill none -stroke '#00d4aa' -strokewidth 2 \
        -draw "circle 100,100 100,10" \
        -draw "circle 100,100 100,30" \
        -draw "circle 100,100 100,55" \
        -fill '#00d4aa' -stroke none \
        -draw "circle 100,100 100,96" \
        "$OUTPUT"
    echo "Generated placeholder logo at $OUTPUT"
else
    echo "ImageMagick not found. Please place your Minima logo at:"
    echo "  $OUTPUT"
    echo "Recommended: 200x200 PNG with transparent background."
fi
