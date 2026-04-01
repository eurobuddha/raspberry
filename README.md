# Minima OS

A flashable Raspberry Pi image that boots straight into the Minima MDS Hub. Plug in, power on, you're running a Minima node.

## Builds

| Build | Target | Experience |
|-------|--------|------------|
| **Kiosk** (Pi 4/5) | Pi 4, Pi 5 (4GB+) | Full-screen MDS Hub on HDMI, boot splash, dedicated appliance |
| **Headless** (Pi Zero 2 W) | Pi Zero 2 W | No display — access MDS Hub from phone/laptop browser |

## Quick Start — Headless (Pi Zero 2 W)

1. Flash **Raspberry Pi OS Lite (64-bit)** with [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
   - Enable SSH and configure WiFi in the imager settings
2. SSH in: `ssh pi@minima.local`
3. Run:
   ```bash
   curl -sL https://raw.githubusercontent.com/eurobuddha/raspberry/main/headless/setup-minima-headless.sh | bash
   ```
4. Open `https://minima.local:15003` from any device on your network

See [headless/README.md](headless/README.md) for details.

## Quick Start — Kiosk (Pi 4/5)

### Option A: Pre-built Image

1. Download `minima-os.img.xz` from [Releases](https://github.com/eurobuddha/raspberry/releases)
2. Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (select "Use custom")
3. Insert SD card, connect HDMI + power
4. Wait ~60 seconds — the MDS Hub appears fullscreen

### Option B: Build Your Own Image

Requirements: Docker, or a Raspberry Pi running 64-bit Pi OS.

```bash
git clone https://github.com/eurobuddha/raspberry.git
cd raspberry
./build.sh              # Docker build (Mac/Linux)
./build.sh --native     # Native build (on a Pi)
```

The image lands in `output/minima-os.img`.

## Architecture

```
┌─────────────────────────────────────────┐
│              Raspberry Pi               │
├─────────────────────────────────────────┤
│  Plymouth boot splash (Minima branding) │
├─────────────────────────────────────────┤
│  systemd                                │
│  ├── minima-node.service (Java JAR)     │
│  └── minima-kiosk.service               │
│      └── Cage (Wayland) → Chromium      │
│          └── https://127.0.0.1:15003   │
├─────────────────────────────────────────┤
│  Raspberry Pi OS (Bookworm arm64)       │
└─────────────────────────────────────────┘
```

- **Minima** runs as a systemd service, auto-starts on boot, auto-restarts on crash
- **Cage** is a Wayland kiosk compositor — runs one app fullscreen, no desktop, no escape
- **Chromium** in kiosk mode points at the MDS Hub on localhost
- **Plymouth** shows a Minima boot splash instead of Linux text
- **avahi** makes the device reachable as `minima.local`

## Default Credentials

| Setting | Default |
|---------|---------|
| MDS Password | `minima` |
| Node Port | `15001` |
| MDS Hub | `https://<ip>:15003` |

Change the MDS password via the Security MiniDapp or:
```bash
sudo nano /etc/minima/minima.env   # edit MDS_PASSWORD
sudo systemctl restart minima-node
```

## Project Structure

```
raspberry/
├── config/
│   └── minima-os.yaml              # rpi-image-gen main config
├── layer/
│   └── minima-kiosk.yaml           # Custom layer (Java + Cage + Chromium)
├── overlay/
│   ├── etc/
│   │   ├── systemd/system/
│   │   │   ├── minima-node.service
│   │   │   └── minima-kiosk.service
│   │   ├── minima/minima.env
│   │   └── chromium-browser/policies/managed/minima.json
│   ├── opt/minima/
│   │   ├── kiosk-start.sh          # Waits for node, launches browser
│   │   └── loading.html            # Shown while node starts
│   └── usr/share/plymouth/themes/minima/
├── headless/
│   ├── setup-minima-headless.sh    # One-script Pi Zero 2 W setup
│   └── README.md
├── scripts/
│   └── generate-logo.sh
├── build.sh                        # Top-level build script
├── Dockerfile.build                # Docker cross-compile env
└── README.md
```

## Ports

| Port  | Service          |
|-------|------------------|
| 15001 | Minima P2P       |
| 15002 | Minima RPC       |
| 15003 | MDS Hub (HTTPS)  |

## Hardware Notes

- **Pi 5 (4/8GB)**: Best performance. Primary target.
- **Pi 4 (4/8GB)**: Excellent. Fully supported.
- **Pi 4 (2GB)**: Works but tight. Chromium + Java use ~500MB.
- **Pi Zero 2 W (512MB)**: Headless only. Not enough RAM for kiosk browser + Java.

## License

MIT
