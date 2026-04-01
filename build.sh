#!/bin/bash
# ============================================================
#  Minima OS — Image Build Script
#  Builds a flashable Raspberry Pi image using rpi-image-gen.
#
#  Usage:
#    ./build.sh              # Build using Docker (Mac/Linux)
#    ./build.sh --native     # Build natively on a Raspberry Pi
#    ./build.sh --jar /path  # Use a specific minima.jar
# ============================================================

set -e

GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
JAR_PATH="$SCRIPT_DIR/overlay/opt/minima/minima.jar"
JAR_URL="https://github.com/nicholasHTM/Minima/raw/refs/heads/master/jar/minima.jar"
NATIVE=false

info()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${AMBER}●${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
step()  { echo -e "\n${BOLD}$1${NC}"; }

# ── Parse arguments ──

while [[ $# -gt 0 ]]; do
    case $1 in
        --native)  NATIVE=true; shift ;;
        --jar)     JAR_PATH="$2"; shift 2 ;;
        *)         echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Banner ──

echo ""
echo -e "${AMBER}${BOLD}  ● Minima OS Image Builder${NC}"
echo -e "${DIM}  ─────────────────────────${NC}"
echo ""

# ── Ensure minima.jar exists ──

step "Checking for minima.jar..."

if [[ -f "$JAR_PATH" ]]; then
    JAR_SIZE=$(du -h "$JAR_PATH" | cut -f1)
    info "Found minima.jar ($JAR_SIZE)"
else
    warn "minima.jar not found at $JAR_PATH"

    # Try to find it locally first
    LOCAL_JARS=(
        "$HOME/Projects/minima-installer/minima.jar"
        "$HOME/Projects/Minima/jar/minima.jar"
        "$HOME/minima/minima.jar"
    )

    FOUND=false
    for candidate in "${LOCAL_JARS[@]}"; do
        if [[ -f "$candidate" ]]; then
            info "Found local copy at $candidate"
            mkdir -p "$(dirname "$JAR_PATH")"
            cp "$candidate" "$JAR_PATH"
            FOUND=true
            break
        fi
    done

    if [[ "$FOUND" = false ]]; then
        echo -e "  ${DIM}Downloading from GitHub...${NC}"
        mkdir -p "$(dirname "$JAR_PATH")"
        if curl -sL "$JAR_URL" -o "$JAR_PATH"; then
            info "Downloaded minima.jar"
        else
            fail "Failed to download minima.jar. Use --jar /path/to/minima.jar"
        fi
    fi
fi

# ── Ensure rpi-image-gen is available ──

step "Checking for rpi-image-gen..."

RPI_IMAGE_GEN=""

if command -v rpi-image-gen &>/dev/null; then
    RPI_IMAGE_GEN="rpi-image-gen"
    info "rpi-image-gen found in PATH"
elif [[ -d "$SCRIPT_DIR/rpi-image-gen" ]]; then
    RPI_IMAGE_GEN="$SCRIPT_DIR/rpi-image-gen/rpi-image-gen"
    info "Using local rpi-image-gen"
else
    warn "rpi-image-gen not found. Cloning..."
    git clone --depth 1 https://github.com/raspberrypi/rpi-image-gen.git "$SCRIPT_DIR/rpi-image-gen"
    RPI_IMAGE_GEN="$SCRIPT_DIR/rpi-image-gen/rpi-image-gen"
    info "rpi-image-gen cloned"
fi

# ── Build ──

step "Building Minima OS image..."

mkdir -p "$OUTPUT_DIR"

if [[ "$NATIVE" = true ]]; then
    # Native build (running on a Raspberry Pi or arm64 Linux)
    info "Building natively..."
    sudo "$RPI_IMAGE_GEN" build \
        -S "$SCRIPT_DIR" \
        -c "$SCRIPT_DIR/config/minima-os.yaml" \
        -o "$OUTPUT_DIR"
else
    # Docker build (Mac/Linux x86_64)
    step "Building via Docker (arm64 emulation)..."

    if ! command -v docker &>/dev/null; then
        fail "Docker is required for cross-platform builds. Install Docker Desktop or use --native on a Pi."
    fi

    # Build the Docker image
    docker build -t minima-os-builder -f "$SCRIPT_DIR/Dockerfile.build" "$SCRIPT_DIR"

    # Run the build
    docker run --rm --privileged \
        -v "$SCRIPT_DIR:/src:ro" \
        -v "$OUTPUT_DIR:/output" \
        minima-os-builder \
        /bin/bash -c "
            cd /build/rpi-image-gen && \
            ./rpi-image-gen build \
                -S /src \
                -c /src/config/minima-os.yaml \
                -o /output
        "
fi

# ── Check output ──

step "Checking output..."

IMG_FILE=$(find "$OUTPUT_DIR" -name "*.img" -type f -newer "$JAR_PATH" 2>/dev/null | head -1)

if [[ -n "$IMG_FILE" ]]; then
    IMG_SIZE=$(du -h "$IMG_FILE" | cut -f1)
    info "Image built: $IMG_FILE ($IMG_SIZE)"

    # Compress
    step "Compressing image..."
    if command -v xz &>/dev/null; then
        xz -k -9 -T0 "$IMG_FILE"
        XZ_SIZE=$(du -h "${IMG_FILE}.xz" | cut -f1)
        info "Compressed: ${IMG_FILE}.xz ($XZ_SIZE)"
    else
        warn "xz not found, skipping compression"
    fi

    echo ""
    echo -e "  ${DIM}─────────────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}Build complete!${NC}"
    echo ""
    echo -e "  ${BOLD}Image:${NC}  $IMG_FILE"
    echo -e "  ${BOLD}Size:${NC}   $IMG_SIZE"
    echo ""
    echo -e "  ${DIM}Flash with Raspberry Pi Imager or:${NC}"
    echo -e "  ${DIM}  sudo dd if=$IMG_FILE of=/dev/sdX bs=4M status=progress${NC}"
    echo ""
else
    fail "No .img file found in $OUTPUT_DIR. Check build logs above."
fi
