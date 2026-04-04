# Minima OS

A flashable Raspberry Pi image that boots straight into the Minima MDS Hub. Plug in, power on, you're running a Minima node.

## Quick Start — Headless (Pi 4 / Pi 5)

1. Flash **Raspberry Pi OS Lite (64-bit)** with [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
   - Enable SSH and configure WiFi in the imager settings
2. SSH in: `ssh pi@minima.local`
3. Run:
   ```bash
   curl -sL https://raw.githubusercontent.com/eurobuddha/raspberry/main/headless/setup-minima-headless.sh | bash
   ```
4. Open `https://minima.local:9003` from any device on your network

See [headless/README.md](headless/README.md) for details.

## Quick Start — Kiosk (Pi 4/5)

### Option A: Pre-built Image

1. Download `minima-os.img.xz` from [Releases](https://github.com/eurobuddha/raspberry/releases)
2. Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (select "Use custom")
3. Insert SD card, connect HDMI + power
4. Wait ~60 seconds — the MDS Hub appears fullscreen

### Option B: Build Your Own Image

Requirements: A Raspberry Pi running 64-bit Pi OS, or Docker on Mac/Linux.

```bash
git clone https://github.com/eurobuddha/raspberry.git
cd raspberry
./build.sh --native     # Build on a Pi (recommended)
./build.sh              # Cross-compile via Docker (Mac/Linux)
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
│          └── https://127.0.0.1:9003    │
├─────────────────────────────────────────┤
│  Raspberry Pi OS (Bookworm arm64)       │
└─────────────────────────────────────────┘
```

- **Minima** runs as a systemd service, auto-starts on boot, auto-restarts on crash
- **MDS Hub** serves at `https://localhost:9003` — the MiniDapp System where you manage MiniDapps, check balance, send transactions
- **Cage** is a Wayland kiosk compositor — runs one app fullscreen, no desktop, no escape
- **Chromium** in kiosk mode points at the MDS Hub on localhost
- **Plymouth** shows a Minima boot splash instead of Linux text
- **avahi** makes the device reachable as `minima.local`

## Configuration

All config lives in `/etc/minima/minima.env` using the `MINIMA_` prefix:

```bash
sudo nano /etc/minima/minima.env
sudo systemctl daemon-reload && sudo systemctl restart minima-node
```

Minima reads `MINIMA_` environment variables natively. Example:

```
MINIMA_PORT=9001
MINIMA_MDSPASSWORD=minima
MINIMA_MDSENABLE=true
MINIMA_RPCENABLE=true
MINIMA_MEGAMMR=true
```

## Ports

| Port | Service                    |
|------|----------------------------|
| 9001 | Minima P2P                 |
| 9003 | MDS Hub (HTTPS)            |
| 9005 | Minima RPC                 |

## Hardware

- **Pi 5 (4/8GB)**: Best performance. Primary target.
- **Pi 4 (4/8GB)**: Excellent. Fully supported.
- **Pi 4 (2GB)**: Works but tight with kiosk mode.

Pi Zero 2 W (512MB) is not recommended — insufficient RAM for stable operation.

## License

MIT
