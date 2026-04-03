#!/bin/bash
# ============================================================
#  Minima Node — Headless Setup for Raspberry Pi Zero 2 W
#  Flash Pi OS Lite (64-bit), SSH in, run this script.
#
#  512MB RAM — aggressive memory tuning applied:
#    Java heap 256MB, GPU 16MB, zram swap, SD swap, tmpfs
# ============================================================

set -e

GREEN='\033[0;32m'
AMBER='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "${AMBER}${BOLD}  ● Minima Node Setup (Pi Zero 2 W)${NC}"
echo -e "${DIM}  ───────────────────────────────────${NC}"
echo ""

info()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${AMBER}●${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
step()  { echo -e "\n  ${BOLD}$1${NC}"; }

# ---- Check architecture ----

if [[ "$(uname -m)" != "aarch64" ]]; then
  fail "This script requires Pi OS Lite 64-bit (aarch64). Got: $(uname -m)"
fi

TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
info "Detected ${TOTAL_RAM_MB}MB RAM"

# ---- Apply memory optimizations FIRST (before installing anything) ----

step "Applying memory optimizations..."

# Reduce GPU memory to minimum (headless, no display needed)
BOOT_CONFIG="/boot/firmware/config.txt"
[[ ! -f "$BOOT_CONFIG" ]] && BOOT_CONFIG="/boot/config.txt"
if ! grep -q "^gpu_mem=" "$BOOT_CONFIG" 2>/dev/null; then
  echo "gpu_mem=16" | sudo tee -a "$BOOT_CONFIG" > /dev/null
  info "GPU memory reduced to 16MB (frees ~100MB for Java)."
else
  info "GPU memory already configured."
fi

# Create a 512MB swap file on SD card (supplements zram)
if [[ ! -f /swapfile ]]; then
  sudo dd if=/dev/zero of=/swapfile bs=1M count=512 status=none
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile > /dev/null
  sudo swapon /swapfile
  if ! grep -q "/swapfile" /etc/fstab; then
    echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
  fi
  info "512MB swap file created (SD card backed)."
else
  info "Swap file already exists."
fi

# zram compressed swap (in addition to SD swap)
if ! dpkg -s systemd-zram-generator &>/dev/null 2>&1; then
  sudo apt-get update -qq
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
  info "zram swap enabled (256MB compressed in RAM)."
else
  info "zram swap already configured."
fi

# Mount /tmp as tmpfs to reduce SD card writes
if ! grep -q "tmpfs /tmp" /etc/fstab; then
  echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,size=32m 0 0" | sudo tee -a /etc/fstab > /dev/null
  sudo mount -o remount /tmp 2>/dev/null || true
  info "/tmp mounted as tmpfs (32MB)."
else
  info "/tmp already mounted as tmpfs."
fi

# Tune swappiness — prefer swap earlier to keep RAM free for Java
if ! grep -q "^vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
  echo "vm.swappiness=60" | sudo tee -a /etc/sysctl.conf > /dev/null
  sudo sysctl -w vm.swappiness=60 > /dev/null
  info "Swappiness set to 60."
fi

# Disable unnecessary services to free RAM
for svc in bluetooth hciuart triggerhappy ModemManager; do
  if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
    sudo systemctl disable --now "$svc" 2>/dev/null || true
  fi
done
info "Disabled unnecessary services."

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

echo -e "  ${DIM}Downloading minima.jar (~73MB — this will take a while on Pi Zero)...${NC}"
sudo curl -sfL "$JAR_URL" -o /opt/minima/minima.jar || fail "Failed to download minima.jar"
if ! file /opt/minima/minima.jar | grep -qi "java archive\|zip"; then
  sudo rm -f /opt/minima/minima.jar
  fail "Downloaded file is not a valid JAR. Check the URL."
fi
info "minima.jar installed to /opt/minima/"

# ---- Set default config ----

if [[ ! -f /etc/minima/minima.env ]]; then
  sudo tee /etc/minima/minima.env > /dev/null << 'ENVFILE'
# Minima Node Configuration (Pi Zero 2 W — 512MB)
# All vars use MINIMA_ prefix. Minima reads them automatically.
# Edit, then: sudo systemctl daemon-reload && sudo systemctl restart minima-node
# Port layout: 9001 P2P | 9003 MDS Hub | 9004 MDS Cmd | 9005 RPC
MINIMA_PORT=9001
MINIMA_DATA=/home/minima/.minima
MINIMA_MDSENABLE=true
MINIMA_MDSPASSWORD=minima
MINIMA_RPCENABLE=true
ENVFILE
  sudo chmod 600 /etc/minima/minima.env
  info "Default config written to /etc/minima/minima.env"
else
  info "Config already exists."
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
EnvironmentFile=/etc/minima/minima.env
ExecStart=/usr/bin/java -Xmx256m -jar /opt/minima/minima.jar -daemon
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

# ---- Wait for Minima to start (longer timeout for Zero 2 W) ----

step "Waiting for Minima to start (slower on Pi Zero, be patient)..."

for i in $(seq 1 45); do
  if curl -sk https://localhost:9003 -o /dev/null 2>&1; then
    info "Minima MDS Hub is running!"
    break
  fi
  if [[ $i -eq 45 ]]; then
    warn "Minima is still starting up. Check: sudo systemctl status minima-node"
  fi
  sleep 3
done

# ---- Get IP address ----

IP_ADDR=$(hostname -I | awk '{print $1}')

# ---- Done ----

echo ""
echo -e "  ${DIM}───────────────────────────────────${NC}"
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
echo -e "  ${BOLD}Memory:${NC}      Java 256MB heap, 512MB SD swap, ~256MB zram swap"
echo ""
echo -e "  ${DIM}Open the MDS Hub URL from any device on your network.${NC}"
echo -e "  ${DIM}You'll see a certificate warning — that's normal (self-signed).${NC}"
echo ""
echo -e "  ${AMBER}Reboot recommended to apply all memory optimizations.${NC}"
echo ""
