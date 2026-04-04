# Minima Headless Node — Raspberry Pi 4 / Pi 5

Run a Minima node on a Raspberry Pi. No monitor needed — access the MDS Hub from any device on your network.

## What You Need

- Raspberry Pi 4 or Pi 5 (4GB+ recommended)
- microSD card (16GB+)
- Power supply
- WiFi or Ethernet

## Setup

### 1. Flash Raspberry Pi OS Lite (64-bit)

Open [Raspberry Pi Imager](https://www.raspberrypi.com/software/) and:

1. Choose your Pi model as the device
2. Choose **Raspberry Pi OS Lite (64-bit)** — under "Raspberry Pi OS (other)"
3. Click **Edit Settings** before flashing:
   - Set hostname to `minima`
   - Enable SSH (use password authentication)
   - Set username/password (e.g. `pi` / your password)
   - Configure your WiFi network name and password
4. Flash to your microSD card

### 2. Boot and Connect

1. Insert the microSD into the Pi and power it on
2. Wait ~60 seconds for first boot
3. SSH in:
   ```
   ssh pi@minima.local
   ```

### 3. Run the Setup Script

```bash
curl -sL https://raw.githubusercontent.com/eurobuddha/raspberry/main/headless/setup-minima-headless.sh | bash
```

### 4. Access the MDS Hub

From any device on your network, open:

```
https://minima.local:9003
```

- **Password:** `minima` (change via the Security MiniDapp)
- You'll see a certificate warning — click "Advanced" then "Proceed" (self-signed cert, normal)

## Configuration

All config is in `/etc/minima/minima.env` using the `MINIMA_` prefix. Minima reads these natively.

```bash
sudo nano /etc/minima/minima.env
sudo systemctl daemon-reload && sudo systemctl restart minima-node
```

Example:
```
MINIMA_PORT=9001
MINIMA_MDSPASSWORD=minima
MINIMA_MDSENABLE=true
MINIMA_RPCENABLE=true
MINIMA_MEGAMMR=true
```

## Managing the Node

```bash
# Check status
sudo systemctl status minima-node

# View logs
sudo journalctl -u minima-node -f

# Restart
sudo systemctl restart minima-node

# Stop
sudo systemctl stop minima-node
```

## Ports

| Port | Service                    |
|------|----------------------------|
| 9001 | Minima P2P                 |
| 9003 | MDS Hub (HTTPS)            |
| 9005 | Minima RPC                 |

## Installing MiniDapps

Install MiniDapps (`.mds.zip` files) via the Hub interface at `https://minima.local:9003`.
