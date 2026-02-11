# remote-ollama-proxy ai-server Repository Layout

```
server/
├── specs/                     # This folder — all markdown specifications
│   ├── ARCHITECTURE.md        # Core principles and network topology
│   ├── SECURITY.md            # Three-layer security model
│   ├── FUNCTIONALITIES.md     # Core functionality and components
│   ├── INTERFACES.md          # External interfaces (HAProxy + Ollama)
│   ├── REQUIREMENTS.md        # Hardware and software requirements
│   ├── SCRIPTS.md             # Script specifications
│   ├── FILES.md               # This file
│   ├── ANTHROPIC_COMPATIBILITY.md  # v2+ Anthropic API specification
│   └── HARDENING_OPTIONS.md   # Future capability-mediation options
├── scripts/
│   ├── install.sh             # One-time setup (Tailscale + Ollama + HAProxy)
│   ├── uninstall.sh           # Remove server configuration
│   ├── warm-models.sh         # Optional: pre-load models at boot
│   └── test.sh                # Comprehensive tests (26+ tests)
├── SETUP.md                   # Setup instructions
└── README.md                  # Overview and quick start
```

---

## Runtime Files (Created by install.sh)

### LaunchAgent Plists

**Ollama Service:**
- Location: `~/Library/LaunchAgents/com.ollama.plist`
- Purpose: Configure Ollama as user-level service
- Key settings:
  - `OLLAMA_HOST=127.0.0.1` (loopback-only binding)
  - `RunAtLoad=true` (auto-start on login)
  - `KeepAlive=true` (auto-restart on crash)
  - Logs: `/tmp/ollama.stdout.log`, `/tmp/ollama.stderr.log`

**HAProxy Service:**
- Location: `~/Library/LaunchAgents/com.haproxy.plist`
- Purpose: Configure HAProxy as user-level service
- Key settings:
  - Config file: `~/.haproxy/haproxy.cfg`
  - `RunAtLoad=true` (auto-start on login)
  - `KeepAlive=true` (auto-restart on crash)
  - Logs: `/tmp/haproxy.log` (if enabled)

### HAProxy Configuration

**Config Directory:**
- Location: `~/.haproxy/`
- Created by: `install.sh`
- Contents:
  - `haproxy.cfg` - Main configuration file

**Config File Structure:**
```
~/.haproxy/haproxy.cfg

Contents:
  - Global settings (minimal logging, daemon mode)
  - Frontend: Listen on Tailscale interface (100.x.x.x:11434)
  - Backend: Forward to Ollama (127.0.0.1:11434)
  - Endpoint allowlist (path-based routing)
```

**Allowlisted Endpoints:**

OpenAI API:
- `POST /v1/chat/completions`
- `GET /v1/models`
- `GET /v1/models/{model}`
- `POST /v1/responses`

Anthropic API:
- `POST /v1/messages`

Ollama Native API (metadata only):
- `GET /api/version`
- `GET /api/tags`
- `POST /api/show`

All other paths blocked by default.

### Log Files

**Ollama:**
- Stdout: `/tmp/ollama.stdout.log`
- Stderr: `/tmp/ollama.stderr.log`
- Rotation: Manual (not managed by installer)

**HAProxy:**
- Access log: `/tmp/haproxy.log` (if enabled in config)
- Rotation: Manual (not managed by installer)

---

## Architecture Diagram (File Perspective)

```
┌────────────────────────────────────────────┐
│ Repository (server/)                       │
│ ├── specs/*.md (documentation)             │
│ └── scripts/*.sh (automation)              │
└────────────────────────────────────────────┘
                  │
                  │ install.sh creates ↓
                  ▼
┌────────────────────────────────────────────┐
│ Runtime Configuration                      │
│ ├── ~/Library/LaunchAgents/               │
│ │   ├── com.ollama.plist                  │
│ │   └── com.haproxy.plist                 │
│ ├── ~/.haproxy/                            │
│ │   └── haproxy.cfg                        │
│ └── /tmp/                                  │
│     ├── ollama.stdout.log                  │
│     ├── ollama.stderr.log                  │
│     └── haproxy.log                        │
└────────────────────────────────────────────┘
                  │
                  │ LaunchAgents start ↓
                  ▼
┌────────────────────────────────────────────┐
│ Running Services                           │
│ ├── HAProxy (100.x.x.x:11434)             │
│ │   ↓ forwards allowlisted endpoints      │
│ └── Ollama (127.0.0.1:11434)               │
└────────────────────────────────────────────┘
```

---

## Security Architecture (File and Network Layers)

### Three-Layer Defense

**Layer 1: Tailscale (Network)**
- Managed: Tailscale admin console (external)
- Controls: Device authorization to reach port 11434

**Layer 2: HAProxy (Application)**
- Config: `~/.haproxy/haproxy.cfg`
- Controls: Which endpoints are forwarded

**Layer 3: Ollama (OS Kernel)**
- Config: `OLLAMA_HOST=127.0.0.1` in plist
- Controls: Process network reachability (loopback-only)

---

## Dual API Support (v2+)

The server exposes both OpenAI-compatible and Anthropic-compatible APIs:

**OpenAI API (v1)**:
- For Aider and OpenAI-compatible tools
- Endpoints at `/v1/chat/completions`, `/v1/models`, etc.
- Forwarded by HAProxy to Ollama

**Anthropic API (v2+)**:
- For Claude Code and Anthropic-compatible tools
- Endpoint at `/v1/messages`
- Requires Ollama 0.5.0+
- Forwarded by HAProxy to Ollama
- See `ANTHROPIC_COMPATIBILITY.md` for details

Both APIs served by the same Ollama process on port 11434, accessed through HAProxy.

---

## Configuration Files NOT Required

The following are **not needed** for v1 baseline:

- ❌ TLS certificates (Tailscale provides encryption)
- ❌ Authentication config (network isolation sufficient)
- ❌ Rate limit config (future expansion)
- ❌ Logging config (optional, can be added to haproxy.cfg)

Minimal configuration keeps system simple and maintainable.

---

## Cleanup (uninstall.sh)

### Files Removed

1. `~/Library/LaunchAgents/com.ollama.plist`
2. `~/Library/LaunchAgents/com.haproxy.plist`
3. `~/.haproxy/` directory (including haproxy.cfg)
4. `/tmp/ollama.stdout.log`
5. `/tmp/ollama.stderr.log`
6. `/tmp/haproxy.log` (if exists)

### Files Preserved

- Homebrew binaries (`ollama`, `haproxy`, `tailscale`)
- Ollama models in `~/.ollama/models/` (valuable data)
- Tailscale configuration (may be used for other purposes)

---

## Future Expansion (Out of Scope for v1)

The proxy architecture enables future config files **without re-architecture**:

- `~/.haproxy/auth.conf` - Per-device credentials
- `~/.haproxy/rate-limits.conf` - Request rate limits
- `~/.haproxy/allowed-models.conf` - Model allowlist
- `~/.haproxy/client-certs/` - mTLS certificates

See `HARDENING_OPTIONS.md` for complete design space (not requirements, just options).

---

## Summary

File layout provides:

> **Minimal configuration with maximum security**

- 2 LaunchAgent plists (Ollama + HAProxy)
- 1 HAProxy config file (endpoint allowlist)
- 3 log files (Ollama stdout/stderr + HAProxy)
- All managed by install.sh/uninstall.sh
- Future-expandable without re-architecture
