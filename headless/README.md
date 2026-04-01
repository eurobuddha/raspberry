# Minima Headless Node — Raspberry Pi Zero 2 W

Run a Minima node on a Pi Zero 2 W. No monitor needed — access the MDS Hub from any device on your network.

## What You Need

- Raspberry Pi Zero 2 W
- microSD card (16GB+)
- Power supply (5V/2.5A micro-USB)
- WiFi network

## Setup

### 1. Flash Raspberry Pi OS Lite (64-bit)

Open [Raspberry Pi Imager](https://www.raspberrypi.com/software/) and:

1. Choose **Raspberry Pi Zero 2 W** as the device
2. Choose **Raspberry Pi OS Lite (64-bit)** — under "Raspberry Pi OS (other)"
3. Click the **gear icon** (or Edit Settings) before flashing:
   - Set hostname to `minima`
   - Enable SSH (use password authentication)
   - Set username/password (e.g. `pi` / your password)
   - Configure your WiFi network name and password
4. Flash to your microSD card

### 2. Boot and Connect

1. Insert the microSD into the Pi Zero 2 W and power it on
2. Wait ~90 seconds for first boot
3. SSH in:
   ```
   ssh pi@minima.local
   ```

### 3. Run the Setup Script

```bash
curl -sL https://raw.githubusercontent.com/eurobuddha/raspberry/main/headless/setup-minima-headless.sh | bash
```

Or if you have the script locally:
```bash
bash setup-minima-headless.sh
```

### 4. Access the MDS Hub

From any device on your network, open:

```
https://minima.local:9005
```

- **Password:** `minima` (change this via the Security MiniDapp)
- You'll see a certificate warning — click "Advanced" then "Proceed" (self-signed cert, this is normal)

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

# Change MDS password
sudo nano /etc/minima/minima.env    # edit MDS_PASSWORD=yourpassword
sudo systemctl restart minima-node
```

## Memory Optimizations

The setup script applies these automatically for the Pi Zero 2 W's 512MB RAM:

- **GPU memory → 16MB** (no display needed, frees ~100MB)
- **zram swap** (compressed RAM swap, avoids SD card wear)
- **tmpfs on /tmp** (reduces SD card writes)
- **Java heap capped at 256MB** (`-Xmx256m`)

## Ports

| Port | Service                    |
|------|----------------------------|
| 9001 | Minima P2P                 |
| 9002 | Minima RPC                 |
| 9005 | MDS Hub (HTTPS)            |

## Installing MiniDapps

Once the MDS Hub is running, you can install MiniDapps (`.mds.zip` files) via the Hub interface at `https://minima.local:9005`, or via RPC:

```bash
curl -k https://localhost:9002/mds%20action:install%20file:/path/to/mydapp.mds.zip
```
