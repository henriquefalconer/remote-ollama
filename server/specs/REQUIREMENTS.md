# self-sovereign-ollama ai-server Requirements (v2.0.0)

## macOS Server

- macOS 14 Sonoma or later
- Apple Silicon (M-series processor) — **required**
- zsh (default) or bash

## Hardware

- High unified memory capacity (≥96 GB strongly recommended for large models)
- 24/7 operation capability with uninterruptible power supply
- High upload bandwidth network connection (≥100 Mb/s recommended for low-latency streaming worldwide)
- Sufficient disk space for model storage (varies by model; 100+ GB recommended)
- **Wired Ethernet connection** (no Wi-Fi)

## Prerequisites (installer enforces)

- Homebrew
- Ollama (installed via Homebrew if missing)
- **OpenWrt router with WireGuard VPN** (configured separately - see ROUTER_SETUP.md)

## Router Requirements (Layer 1)

**Separate from server** - See `ROUTER_SETUP.md` for complete requirements:

- OpenWrt-compatible hardware
- OpenWrt 23.05 LTS or later
- WireGuard support (kernel module + packages)
- Minimum 2 network interfaces (WAN + DMZ)
- Sufficient RAM for firewall rules (typically 128MB+)
- Public IP address or dynamic DNS

## No sudo required for server operation

Ollama runs as a user-level LaunchAgent (not root) for security. Sudo may be required only for:
- Initial Homebrew installation (if not already present)
- Network configuration (`networksetup` command requires sudo)

## Network Requirements

### Server (Layer 2)
- Static IP on DMZ network (default: 192.168.100.10)
- Ethernet connection to router DMZ interface
- No Wi-Fi infrastructure

### Router (Layer 1)
- Public IP address (for WireGuard VPN server)
- DMZ network configured (default: 192.168.100.0/24)
- WireGuard VPN configured with per-peer keys
- Firewall rules configured (see ROUTER_SETUP.md)
- No public exposure of port 11434 (only WireGuard UDP)

### Internet Connectivity
- Outbound internet from DMZ (for model downloads, OS updates)
  - Trade-off: Allows automatic updates but increases attack surface
  - Alternative: Fully air-gapped DMZ with manual model loading
- No inbound internet access except WireGuard VPN
