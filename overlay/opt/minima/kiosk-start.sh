#!/bin/bash
# ============================================================
#  Minima Kiosk Launcher
#  Shows a loading page while waiting for Minima to start,
#  then switches to the MDS Hub.
# ============================================================

MDS_URL="https://127.0.0.1:9005"
LOADING_PAGE="file:///opt/minima/loading.html"

# Chromium flags for kiosk mode
CHROMIUM_FLAGS=(
    --kiosk
    --noerrdialogs
    --disable-infobars
    --disable-translate
    --disable-features=TranslateUI
    --ignore-certificate-errors
    --disable-pinch
    --overscroll-history-navigation=0
    --ozone-platform=wayland
    --enable-features=OverlayScrollbar
    --disk-cache-dir=/dev/null
    --password-store=basic
    --no-first-run
    --disable-session-crashed-bubble
    --disable-component-update
    --autoplay-policy=no-user-gesture-required
    --check-for-update-interval=31536000
)

# Wait for Minima MDS Hub to be ready
READY=false
for i in $(seq 1 60); do
    if curl -sk "$MDS_URL" -o /dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 2
done

if [ "$READY" = true ]; then
    exec /usr/bin/chromium "${CHROMIUM_FLAGS[@]}" "$MDS_URL"
else
    # Start with loading page — it will auto-redirect when MDS is ready
    exec /usr/bin/chromium "${CHROMIUM_FLAGS[@]}" "$LOADING_PAGE"
fi
