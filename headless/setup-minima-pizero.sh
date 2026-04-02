#!/bin/bash
# ============================================================
#  Minima Node — Setup for Raspberry Pi Zero W v1.1
#  Flash Pi OS Lite (32-bit), SSH in, run this script.
#
#  Pi Zero W has WiFi + Bluetooth built in.
#  512MB RAM is very tight — this is experimental.
# ============================================================

set -e

GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${AMBER}${BOLD}  ● Minima Node Setup (Pi Zero W v1.1)${NC}"
echo -e "${DIM}  ──────────────────────────────────────${NC}"
echo ""

info()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${AMBER}●${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
step()  { echo -e "\n  ${BOLD}$1${NC}"; }

# ---- Check architecture ----

ARCH=$(uname -m)
if [[ "$ARCH" != "armv6l" && "$ARCH" != "armv7l" && "$ARCH" != "aarch64" ]]; then
  fail "This script is for ARM devices only (got: $ARCH)."
fi

if [[ "$ARCH" == "armv6l" ]]; then
  info "Detected Pi Zero W v1.1 (armv6l, 32-bit)"
fi

# ---- Check available RAM ----

TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
info "Total RAM: ${TOTAL_RAM_MB}MB"

if [[ $TOTAL_RAM_MB -lt 400 ]]; then
  warn "Very low RAM (${TOTAL_RAM_MB}MB). Minima may struggle. Proceeding anyway..."
fi

# ---- Install Java (headless) ----

step "Installing Java runtime..."

if command -v java &>/dev/null; then
  info "Java already installed: $(java -version 2>&1 | head -n1)"
else
  sudo apt-get update -qq
  sudo apt-get install -y default-jre-headless
  if command -v java &>/dev/null; then
    info "Java installed: $(java -version 2>&1 | head -n1)"
  else
    fail "Java installation failed."
  fi
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

echo -e "  ${DIM}Downloading minima.jar (~73MB, this will take a while on Pi Zero)...${NC}"
sudo curl -sfL "$JAR_URL" -o /opt/minima/minima.jar || fail "Failed to download minima.jar"
if ! file /opt/minima/minima.jar | grep -qi "java archive\|zip"; then
  sudo rm -f /opt/minima/minima.jar
  fail "Downloaded file is not a valid JAR."
fi
info "minima.jar installed to /opt/minima/"

# ---- Set default MDS password ----

if [[ ! -f /etc/minima/minima.env ]]; then
  sudo tee /etc/minima/minima.env > /dev/null << 'ENVFILE'
# Minima Node Configuration (Pi Zero v1.1)
# Port layout: 9001 P2P | 9003 MDS Hub | 9004 MDS Cmd | 9005 RPC
MDS_PASSWORD=minima
ENVFILE
  sudo chmod 600 /etc/minima/minima.env
  info "Default MDS password set to 'minima'"
else
  info "MDS password already configured."
fi

# ---- Install systemd service ----
# Java heap capped at 128MB for 512MB Pi Zero

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
EnvironmentFile=/etc/minima/minima.env
ExecStart=/usr/bin/java -Xmx128m -jar /opt/minima/minima.jar \
    -port 9001 \
    -data /home/minima/.minima \
    -mdsenable \
    -mdspassword ${MDS_PASSWORD} \
    -rpcenable \
    -daemon
Restart=always
RestartSec=15
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

# ---- Aggressive memory optimizations for 512MB ----

step "Applying memory optimizations (512MB mode)..."

# Reduce GPU memory to absolute minimum
if ! grep -q "^gpu_mem=" /boot/firmware/config.txt 2>/dev/null && \
   ! grep -q "^gpu_mem=" /boot/config.txt 2>/dev/null; then
  # Pi Zero uses /boot/config.txt (not /boot/firmware/)
  BOOT_CONFIG="/boot/config.txt"
  [[ -f /boot/firmware/config.txt ]] && BOOT_CONFIG="/boot/firmware/config.txt"
  echo "gpu_mem=16" | sudo tee -a "$BOOT_CONFIG" > /dev/null
  info "GPU memory reduced to 16MB."
else
  info "GPU memory already configured."
fi

# zram swap
if ! dpkg -s systemd-zram-generator &>/dev/null 2>&1; then
  sudo apt-get install -y systemd-zram-generator
fi
if [[ ! -f /etc/systemd/zram-generator.conf ]]; then
  sudo tee /etc/systemd/zram-generator.conf > /dev/null << 'ZRAM'
[zram0]
compression-algorithm = zstd
zram-size = ram / 2
ZRAM
  sudo systemctl daemon-reload
  sudo systemctl start systemd-zram-setup@zram0.service
  info "zram swap enabled (256MB compressed)."
else
  info "zram swap already configured."
fi

# tmpfs for /tmp
if ! grep -q "tmpfs /tmp" /etc/fstab; then
  echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,size=32m 0 0" | sudo tee -a /etc/fstab > /dev/null
  info "/tmp mounted as tmpfs (32MB)."
else
  info "/tmp already mounted as tmpfs."
fi

# Disable unnecessary services to free RAM
for svc in bluetooth hciuart triggerhappy; do
  if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
    sudo systemctl disable --now "$svc" 2>/dev/null
  fi
done
info "Disabled unnecessary services."

# ---- Wait for Minima to start ----

step "Waiting for Minima to start (may take a while on Pi Zero)..."

for i in $(seq 1 60); do
  if curl -sk https://localhost:9003 -o /dev/null 2>&1; then
    info "Minima MDS Hub is running!"
    break
  fi
  if [[ $i -eq 60 ]]; then
    warn "Minima is still starting up. Check: sudo systemctl status minima-node"
  fi
  sleep 3
done

# ---- Get IP address ----

IP_ADDR=$(hostname -I | awk '{print $1}')

# ---- Done ----

echo ""
echo -e "  ${DIM}────────────────────────────────────${NC}"
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
echo ""
echo -e "  ${AMBER}${BOLD}WARNING:${NC}${AMBER} 512MB RAM is very tight. If the node crashes,${NC}"
echo -e "  ${AMBER}try reducing -Xmx128m to -Xmx96m in the service file.${NC}"
echo ""
echo -e "  ${AMBER}Reboot recommended to apply memory optimizations.${NC}"
echo ""
