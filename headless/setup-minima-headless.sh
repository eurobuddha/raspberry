#!/bin/bash
# ============================================================
#  Minima OS — Headless Setup for Raspberry Pi Zero 2 W
#  Flash Pi OS Lite (64-bit), SSH in, run this script.
# ============================================================

set -e

GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${AMBER}${BOLD}  ● Minima Headless Node Setup${NC}"
echo -e "${DIM}  ─────────────────────────────${NC}"
echo ""

info()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${AMBER}●${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
step()  { echo -e "\n  ${BOLD}$1${NC}"; }

# ---- Check we're on a Pi ----

if [[ "$(uname -m)" != "aarch64" ]]; then
  fail "This script is for 64-bit ARM (aarch64) only."
fi

# ---- Install Java (headless) ----

step "Installing Java runtime..."

if command -v java &>/dev/null; then
  info "Java already installed: $(java -version 2>&1 | head -n1)"
else
  sudo apt-get update -qq
  sudo apt-get install -y default-jre-headless
  info "Java installed: $(java -version 2>&1 | head -n1)"
fi

# ---- Install avahi for .local discovery ----

step "Installing mDNS (avahi)..."

if dpkg -s avahi-daemon &>/dev/null 2>&1; then
  info "avahi-daemon already installed."
else
  sudo apt-get install -y avahi-daemon
  info "avahi-daemon installed."
fi

# ---- Create minima user ----

step "Creating minima user..."

if id minima &>/dev/null; then
  info "User 'minima' already exists."
else
  sudo useradd -r -m -s /bin/bash minima
  info "User 'minima' created."
fi

# ---- Set up Minima ----

step "Installing Minima node..."

sudo mkdir -p /opt/minima
sudo mkdir -p /etc/minima
sudo mkdir -p /home/minima/.minima
sudo chown minima:minima /home/minima/.minima

# Download minima.jar
JAR_URL="https://github.com/minima-global/Minima/raw/master/jar/minima.jar"

echo -e "  ${DIM}Downloading minima.jar...${NC}"
sudo curl -sfL "$JAR_URL" -o /opt/minima/minima.jar || fail "Failed to download minima.jar"
# Verify it's actually a JAR
if ! file /opt/minima/minima.jar | grep -qi "java archive\|zip"; then
  sudo rm -f /opt/minima/minima.jar
  fail "Downloaded file is not a valid JAR. Check the URL."
fi
info "minima.jar installed to /opt/minima/"

# ---- Set default MDS password ----

if [[ ! -f /etc/minima/minima.env ]]; then
  echo 'MDS_PASSWORD=minima' | sudo tee /etc/minima/minima.env > /dev/null
  sudo chmod 600 /etc/minima/minima.env
  info "Default MDS password set to 'minima'"
else
  info "MDS password already configured."
fi

# ---- Install systemd service ----

step "Installing systemd service..."

sudo tee /etc/systemd/system/minima-node.service > /dev/null << 'EOF'
[Unit]
Description=Minima Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=minima
Group=minima
WorkingDirectory=/opt/minima
ExecStart=/usr/bin/java -Xmx256m -jar /opt/minima/minima.jar \
    -port 9001 \
    -data /home/minima/.minima \
    -mdsenable \
    -mdspassword "${MDS_PASSWORD}" \
    -rpcenable
Restart=always
RestartSec=10
EnvironmentFile=/etc/minima/minima.env
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/home/minima/.minima
ProtectHome=false

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable minima-node.service
sudo systemctl start minima-node.service
info "minima-node.service enabled and started."

# ---- Set hostname ----

step "Setting hostname to 'minima'..."

CURRENT_HOST=$(hostname)
if [[ "$CURRENT_HOST" != "minima" ]]; then
  sudo hostnamectl set-hostname minima
  info "Hostname set to 'minima' (reachable as minima.local)"
else
  info "Hostname already set to 'minima'."
fi

# ---- Optimize for 512MB RAM ----

step "Applying memory optimizations..."

# Reduce GPU memory to minimum (headless, no display needed)
if ! grep -q "^gpu_mem=" /boot/firmware/config.txt 2>/dev/null; then
  echo "gpu_mem=16" | sudo tee -a /boot/firmware/config.txt > /dev/null
  info "GPU memory reduced to 16MB (frees ~100MB for Java)."
else
  info "GPU memory already configured."
fi

# Enable zram swap (better than SD card swap)
if ! command -v zramctl &>/dev/null; then
  sudo apt-get install -y zram-tools
fi
if [[ ! -f /etc/default/zramswap ]]; then
  sudo tee /etc/default/zramswap > /dev/null << 'ZRAM'
ALGO=zstd
PERCENT=50
ZRAM
  sudo systemctl enable zramswap
  sudo systemctl start zramswap
  info "zram swap enabled (256MB compressed)."
else
  info "zram swap already configured."
fi

# Mount /tmp as tmpfs to reduce SD card writes
if ! grep -q "tmpfs /tmp" /etc/fstab; then
  echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,size=64m 0 0" | sudo tee -a /etc/fstab > /dev/null
  info "/tmp mounted as tmpfs (reduces SD card wear)."
else
  info "/tmp already mounted as tmpfs."
fi

# ---- Wait for Minima to start ----

step "Waiting for Minima to start..."

for i in $(seq 1 30); do
  if curl -sk https://localhost:9003 -o /dev/null 2>&1; then
    info "Minima MDS Hub is running!"
    break
  fi
  if [[ $i -eq 30 ]]; then
    warn "Minima is still starting up. Check: sudo systemctl status minima-node"
  fi
  sleep 2
done

# ---- Get IP address ----

IP_ADDR=$(hostname -I | awk '{print $1}')

# ---- Done ----

echo ""
echo -e "  ${DIM}─────────────────────────────${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}Setup complete!${NC}"
echo ""
echo -e "  ${BOLD}MDS Hub:${NC}     https://${IP_ADDR}:9003"
echo -e "  ${BOLD}            ${NC} https://minima.local:9003"
echo -e "  ${BOLD}Password:${NC}    minima"
echo -e "  ${BOLD}Node port:${NC}   9001"
echo -e "  ${BOLD}RPC port:${NC}    9005"
echo -e "  ${BOLD}Service:${NC}     sudo systemctl {status|restart|stop} minima-node"
echo ""
echo -e "  ${DIM}Open the MDS Hub URL from any device on your network.${NC}"
echo -e "  ${DIM}You'll see a certificate warning — that's normal (self-signed).${NC}"
echo -e "  ${DIM}Change your MDS password via the Security MiniDapp.${NC}"
echo ""
echo -e "  ${AMBER}Reboot recommended to apply memory optimizations.${NC}"
echo ""
