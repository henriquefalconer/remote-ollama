# self-sovereign-ollama ai-server Repository Layout (v2.0.0)

```
server/
├── specs/                     # This folder — all markdown specifications
│   ├── ARCHITECTURE.md        # Core principles, two-layer architecture
│   ├── SECURITY.md            # Two-layer security model (router + server)
│   ├── FUNCTIONALITIES.md     # Core functionality and components
│   ├── INTERFACES.md          # External interfaces (WireGuard + Ollama)
│   ├── REQUIREMENTS.md        # Hardware and software requirements
│   ├── SCRIPTS.md             # Script specifications
│   ├── FILES.md               # This file
│   ├── ANTHROPIC_COMPATIBILITY.md  # Anthropic API specification (Ollama 0.5.0+)
│   └── HARDENING_OPTIONS.md   # Future hardening options
├── scripts/
│   ├── install.sh             # One-time setup (network + Ollama)
│   ├── uninstall.sh           # Remove server configuration
│   ├── warm-models.sh         # Optional: pre-load models at boot
│   └── test.sh                # Comprehensive tests (~25-30 tests)
├── ROUTER_SETUP.md            # Complete OpenWrt router configuration guide
├── SETUP.md                   # Server setup instructions
└── README.md                  # Overview and quick start
```

---

## Runtime Files (Created by install.sh)

### LaunchAgent Plists

**Ollama Service:**
- Location: `~/Library/LaunchAgents/com.ollama.plist`
- Purpose: Configure Ollama as user-level service
- Key settings:
  - `OLLAMA_HOST=192.168.100.10` (DMZ interface) or `0.0.0.0` (all interfaces)
  - `RunAtLoad=true` (auto-start on login)
  - `KeepAlive=true` (auto-restart on crash)
  - Logs: `/tmp/ollama.stdout.log`, `/tmp/ollama.stderr.log`

### Network Configuration

**macOS Static IP:**
- Configured via: `networksetup` command
- Interface: Ethernet (or appropriate network interface)
- IP: `192.168.100.10` (default, configurable)
- Subnet: `255.255.255.0` (/24)
- Router: `192.168.100.1`
- DNS: Router or public DNS (configurable)

**Verification:**
```bash
networksetup -getinfo "Ethernet"
```

### Router Configuration

**External to this repository** - See `ROUTER_SETUP.md`

**Key components:**
- WireGuard VPN configuration on router
- DMZ network configuration
- Firewall rules (VPN → DMZ, DMZ → WAN, etc.)
- Static DHCP lease or router-side static IP assignment

### Log Files

**Ollama:**
- Stdout: `/tmp/ollama.stdout.log`
- Stderr: `/tmp/ollama.stderr.log`
- Rotation: Manual (not managed by installer)

**Router** (external):
- System log: `/var/log/messages` (on router)
- Firewall log: `/var/log/firewall` (if enabled on router)
- WireGuard log: `logread | grep wireguard` (on router)

---

## Architecture Diagram (File Perspective)

```
┌────────────────────────────────────────────┐
│ Repository (server/)                       │
│ ├── specs/*.md (documentation)             │
│ ├── scripts/*.sh (automation)              │
│ └── ROUTER_SETUP.md (router guide)         │
└────────────────────────────────────────────┘
                  │
                  │ install.sh creates ↓
                  ▼
┌────────────────────────────────────────────┐
│ Runtime Configuration                      │
│ ├── ~/Library/LaunchAgents/               │
│ │   └── com.ollama.plist                  │
│ ├── macOS Network Settings                │
│ │   └── Static IP: 192.168.100.10         │
│ └── /tmp/                                  │
│     ├── ollama.stdout.log                  │
│     └── ollama.stderr.log                  │
└────────────────────────────────────────────┘
                  │
                  │ LaunchAgent starts ↓
                  ▼
┌────────────────────────────────────────────┐
│ Running Service                            │
│ └── Ollama (192.168.100.10:11434)         │
│     • Serves all API endpoints directly    │
│     • No application-layer proxy          │
└────────────────────────────────────────────┘
                  ▲
                  │ VPN clients connect via router
                  │
┌────────────────────────────────────────────┐
│ Router (external to repo)                  │
│ ├── WireGuard VPN config                   │
│ ├── DMZ firewall rules                     │
│ └── See ROUTER_SETUP.md                    │
└────────────────────────────────────────────┘
```

---

## Security Architecture (File and Network Layers)

### Two-Layer Defense

**Layer 1: Network Perimeter (Router)**
- Config: OpenWrt UCI or LuCI (external to repository)
- Controls: Who can reach server (VPN auth + firewall)
- See: `ROUTER_SETUP.md`

**Layer 2: Server (Ollama)**
- Config: `OLLAMA_HOST` in plist + macOS network settings
- Controls: Which interface Ollama binds to
- Security: Relies on Layer 1 (network perimeter)

---

## Dual API Support

The server exposes both OpenAI-compatible and Anthropic-compatible APIs:

**OpenAI API:**
- For Aider and OpenAI-compatible tools
- Endpoints at `/v1/chat/completions`, `/v1/models`, etc.
- Served directly by Ollama (no proxy)

**Anthropic API:**
- For Claude Code and Anthropic-compatible tools
- Endpoint at `/v1/messages`
- Requires Ollama 0.5.0+
- Served directly by Ollama (no proxy)
- See `ANTHROPIC_COMPATIBILITY.md` for details

**Ollama Native API:**
- All `/api/*` endpoints accessible to VPN clients
- Includes potentially destructive operations (pull, delete, create)
- See `INTERFACES.md` for complete endpoint list

Both APIs served by the same Ollama process on port 11434. All endpoints accessible to VPN clients (no application-layer filtering).

---

## Configuration Files NOT Required

The following are **not needed** for v2 baseline:

- ❌ TLS certificates (WireGuard provides encryption)
- ❌ Authentication config (VPN provides authentication)
- ❌ Application proxy config (no HAProxy in v2)
- ❌ Endpoint allowlist (firewall controls access, not application)
- ❌ Rate limit config (can be added on router if needed)

Minimal configuration keeps system simple and maintainable.

---

## Cleanup (uninstall.sh)

### Files Removed

1. `~/Library/LaunchAgents/com.ollama.plist`
2. `/tmp/ollama.stdout.log`
3. `/tmp/ollama.stderr.log`
4. Optionally: macOS static IP configuration (reverted to DHCP if user confirms)

### Files Preserved

- Homebrew binary (`ollama`)
- Ollama models in `~/.ollama/models/` (valuable data)
- Router configuration (must be manually reverted if needed)

### Router Cleanup (Manual)

**Not handled by uninstall.sh** - must be done manually:

1. Remove server's IP from DMZ firewall rules
2. Optionally remove DMZ network configuration
3. Remove VPN peer configurations (client public keys)
4. See `ROUTER_SETUP.md` for reversal instructions

---

## Future Expansion (Out of Scope for v2)

The architecture enables future config files **without re-architecture**:

**On router** (network layer):
- Connection rate limiting config
- Per-peer bandwidth limits (QoS)
- IDS/IPS configuration (Snort, Suricata)
- WAF configuration (ModSecurity)

**On server** (if adding application proxy):
- `~/.reverse-proxy/config` - Optional reverse proxy (nginx, caddy)
- Endpoint allowlisting (v1 HAProxy-style)
- API key authentication
- Model allowlists

See `HARDENING_OPTIONS.md` for complete design space (not requirements, just options).

---

## Summary

File layout provides:

> **Minimal server configuration, maximum network control**

**Server-side:**
- 1 LaunchAgent plist (Ollama only)
- 1 network configuration (static IP)
- 2 log files (Ollama stdout/stderr)
- All managed by install.sh/uninstall.sh

**Router-side** (external):
- WireGuard VPN configuration
- DMZ network configuration
- Firewall rules
- See `ROUTER_SETUP.md` for complete guide

**Benefits:**
- Simpler than v1 (no HAProxy)
- Self-sovereign (no third-party VPN service)
- Future-expandable without re-architecture
- Clear separation of concerns (network vs server)
