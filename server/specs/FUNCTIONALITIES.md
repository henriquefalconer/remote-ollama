# self-sovereign-ollama ai-server Functionalities (v2.0.0)

This specification documents functionality across both architectural layers.

------------------------------------------------------------
LAYER 1 — NETWORK PERIMETER FUNCTIONALITY
------------------------------------------------------------

See `ROUTER_SETUP.md` for complete router configuration.

## Router Responsibilities

**WireGuard VPN:**
- Host WireGuard VPN server on OpenWrt
- Listen on UDP port (default: 51820) on WAN interface
- Per-peer public key authentication
- Assign VPN clients to 10.10.10.0/24 subnet
- No client-to-client routing
- No VPN client internet access

**Firewall:**
- Deny all inbound WAN traffic except WireGuard UDP
- Allow VPN → DMZ port 11434 only
- Deny VPN → LAN completely
- Deny DMZ → LAN completely
- Allow DMZ → WAN (outbound internet)
- Optionally allow LAN → DMZ (admin access)

**DMZ Network:**
- Dedicated subnet for AI server (default: 192.168.100.0/24)
- Router provides DHCP or static IP assignment
- Router provides DNS resolution (optional)
- Router provides internet gateway for DMZ

## Security Behavior

**Access control:**
- Only WireGuard-authenticated peers can reach DMZ
- Per-peer revocation via public key removal
- No shared secrets (no password authentication)

**Network isolation:**
- DMZ server cannot reach LAN resources
- VPN clients cannot reach LAN resources
- LAN devices cannot initiate connections to DMZ (unless explicitly allowed)

**Blast radius containment:**
- If DMZ server compromised, attacker cannot pivot to LAN
- Attacker has outbound internet (trade-off for functionality)

------------------------------------------------------------
LAYER 2 — AI SERVER CAPABILITIES
------------------------------------------------------------

## Core Functionality

- One-time installer that configures Ollama as LaunchAgent service
- Static IP configuration on DMZ network
- Ollama bound to DMZ interface (or all interfaces if configured)
- Uninstaller that removes server-side configuration (Ollama LaunchAgent, optionally revert to DHCP)
- Optional model pre-warming script for boot-time loading
- Comprehensive test script for automated validation (network, service, API, security)
- Service management via standard launchctl commands (start/stop/restart/status)

---

## Component Architecture

### Ollama (Inference Engine)

**Purpose**: Model loading, inference, and API serving

**Functionality**:
- Bind to DMZ interface (`192.168.100.10:11434`) or all interfaces (`0.0.0.0:11434`)
- Serve OpenAI-compatible API at `/v1/*`
- Serve Anthropic-compatible API at `/v1/messages` (Ollama 0.5.0+)
- Serve Ollama native API at `/api/*`
- Automatic model loading and unloading
- Concurrent request handling (queuing)
- GPU memory management (Apple Silicon unified memory)

**Managed by**:
- Installed via `install.sh` (Homebrew)
- Configured via LaunchAgent plist (`~/Library/LaunchAgents/com.ollama.plist`)
- Runs as user-level LaunchAgent (not root)
- Auto-start on login (`RunAtLoad=true`)
- Auto-restart on crash (`KeepAlive=true`)
- Logs to `/tmp/ollama.stdout.log` and `/tmp/ollama.stderr.log`

**Security properties**:
- No built-in authentication (relies on network perimeter)
- Logs stored locally only (no outbound telemetry)
- All endpoints accessible to VPN clients (no application-layer filtering)
- Network perimeter (router firewall) provides security

---

## Exposed API Endpoints

### OpenAI-Compatible API

**Base URL**: `http://192.168.100.10:11434/v1`

**Primary endpoints**:
- `POST /v1/chat/completions` - Chat completions (streaming & non-streaming)
- `GET /v1/models` - List available models
- `GET /v1/models/{model}` - Get model details
- `POST /v1/responses` - Experimental non-stateful responses (Ollama 0.5.0+)

**Supported features**:
- Streaming responses (`stream: true`)
- JSON structured output (`response_format: {"type": "json_object"}`)
- Tool calling / function calling (model-dependent)
- Vision (image_url for base64 images)
- Temperature, top_p, max_tokens, seed, stop, n parameters
- System, user, assistant roles
- Stream options (include_usage)

**Limitations**:
- No stateful conversations
- No previous_response_id support
- No server-side session tracking

### Anthropic-Compatible API

**Base URL**: `http://192.168.100.10:11434/v1/messages`

**Endpoint**:
- `POST /v1/messages` - Anthropic Messages API (Ollama 0.5.0+)

**Supported features**:
- Messages with text and image content (base64 only)
- Streaming via Server-Sent Events (SSE)
- System prompts
- Multi-turn conversations
- Tool use (function calling)
- Thinking blocks
- Temperature, top_p, max_tokens parameters

**Limitations**:
- No `tool_choice` parameter (cannot force specific tool)
- No prompt caching
- No PDF/document support
- No URL-based images (base64 only)

See `ANTHROPIC_COMPATIBILITY.md` for complete specification.

### Ollama Native API

**Base URL**: `http://192.168.100.10:11434/api`

**Endpoints**:
- `GET /api/version` - Ollama version info
- `GET /api/tags` - List models
- `POST /api/show` - Model details
- `POST /api/generate` - Native generate endpoint
- `POST /api/pull` - Model download
- `POST /api/push` - Model upload (if model registry configured)
- `POST /api/create` - Create model from Modelfile
- `DELETE /api/delete` - Delete model

**Note**: All native endpoints accessible to VPN clients. Use with caution (e.g., clients can delete models).

---

## Service Management

### LaunchAgent Configuration

**Plist location**: `~/Library/LaunchAgents/com.ollama.plist`

**Key settings**:
- `ProgramArguments`: Path to Ollama binary
- `EnvironmentVariables`:
  - `OLLAMA_HOST`: DMZ interface IP or 0.0.0.0
  - `OLLAMA_ORIGINS`: CORS configuration (optional)
- `RunAtLoad`: true (start on login)
- `KeepAlive`: true (auto-restart on crash)
- `StandardOutPath`: `/tmp/ollama.stdout.log`
- `StandardErrorPath`: `/tmp/ollama.stderr.log`

### Management Commands

```bash
# Check service status
launchctl list | grep com.ollama

# Start service
launchctl kickstart gui/$(id -u)/com.ollama

# Stop service
launchctl stop gui/$(id -u)/com.ollama

# Restart service
launchctl kickstart -k gui/$(id -u)/com.ollama

# View logs
tail -f /tmp/ollama.stdout.log
tail -f /tmp/ollama.stderr.log

# Verify network binding
lsof -i :11434
```

---

## Resource Management

### Model Loading

**Automatic behavior**:
- First request to a model triggers loading into memory
- Subsequent requests use loaded model (fast)
- Idle models unloaded when memory pressure
- Most recently used models kept resident

**Manual pre-warming** (optional):
```bash
# Use warm-models.sh script
./server/scripts/warm-models.sh qwen2.5-coder:32b deepseek-r1:70b

# Or manually pull and load
ollama pull qwen2.5-coder:32b
curl -X POST http://192.168.100.10:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen2.5-coder:32b", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 1}'
```

### Concurrency

**Ollama behavior**:
- Queues concurrent requests (typically 5-10 concurrent)
- GPU memory shared across requests (Apple Silicon unified memory)
- Streaming responses returned incrementally
- No artificial rate limiting (clients can overwhelm server)

**Firewall rate limiting** (optional):
- Can be configured on router to limit connection rate
- Requires OpenWrt iptables rules
- See `ROUTER_SETUP.md` for instructions

### Memory Management

**Unified memory (Apple Silicon)**:
- Models loaded into shared CPU/GPU memory
- Large models (70B+) require ≥96GB RAM
- Memory pressure triggers model unloading
- OS swap not recommended for inference (too slow)

**Disk usage**:
- Models stored in `~/.ollama/models/`
- Can consume 100+ GB depending on models
- Recommend ≥500GB free disk space

---

## Network Configuration

### Static IP Setup

**Configured during installation**:
- Prompts for DMZ subnet (default: 192.168.100.0/24)
- Prompts for server IP (default: 192.168.100.10)
- Configures macOS network interface via `networksetup`
- Sets router as gateway (192.168.100.1)
- Optionally configures DNS

**Verification**:
```bash
# Check interface configuration
networksetup -getinfo "Ethernet"

# Should show:
# IP address: 192.168.100.10
# Subnet mask: 255.255.255.0
# Router: 192.168.100.1
```

### Router Connectivity

**Requirements**:
- Router must be reachable at DMZ gateway IP (192.168.100.1)
- Router must provide internet access for model downloads
- Router must have DMZ firewall rules configured

**Test connectivity**:
```bash
# Test router
ping -c 3 192.168.100.1

# Test internet
ping -c 3 8.8.8.8

# Test DNS (if configured)
nslookup google.com
```

---

## Operational Requirements

### 24/7 Operation

**Recommended setup**:
- Uninterruptible power supply (UPS)
- Ethernet connection (no Wi-Fi)
- Disable sleep mode on macOS
- LaunchAgent ensures auto-start after reboot
- Monitor server health periodically

**Prevent sleep**:
```bash
# Disable sleep when plugged in
sudo pmset -c sleep 0
sudo pmset -c disksleep 0

# Verify settings
pmset -g
```

### Updates and Maintenance

**Regular updates required**:
- macOS security patches (monthly)
- Ollama binary updates (check releases)
- Model updates (if models receive patches)

**During updates**:
- Server will be unavailable briefly
- LaunchAgent auto-restarts Ollama after update
- No client configuration changes needed

### Monitoring

**Health checks**:
```bash
# From server
curl http://192.168.100.10:11434/v1/models

# From VPN client
curl http://192.168.100.10:11434/v1/models
```

**Logs**:
- Check `/tmp/ollama.*.log` for errors
- Monitor disk space for model storage
- Monitor memory usage for large models

---

## Out of Scope (v2)

The following are **intentionally excluded** from this functionality specification:

- Built-in authentication / API keys (network perimeter provides security)
- Application-layer TLS termination (WireGuard provides encryption)
- Application-layer rate limiting (can be added via firewall)
- Endpoint allowlisting (all endpoints accessible to VPN clients)
- Request content inspection (transparent forwarding)
- Web-based UI for server management
- Multi-server load balancing
- Model quantization / conversion
- Wi-Fi infrastructure (wired only)

These can be added later without changing the base architecture. See `HARDENING_OPTIONS.md` for future expansion options.

---

## Component Architecture

### HAProxy (Security Layer)

**Purpose**: Application-layer proxy that controls what endpoints clients can access

**Functionality**:
- Listen on Tailscale interface only (`100.x.x.x:11434`)
- Forward only allowlisted endpoints to Ollama
- Block all non-allowlisted paths by default
- Transparent forwarding (no request mutation, minimal latency)

**Managed by**:
- Installed via `install.sh` (with user consent)
- Configured via `~/.haproxy/haproxy.cfg`
- Runs as user-level LaunchAgent (`~/Library/LaunchAgents/com.haproxy.plist`)
- Auto-start on login, auto-restart on crash

**Security properties**:
- Only explicitly-forwarded endpoints are reachable
- Prevents accidental exposure of future Ollama features
- Single choke point for all remote access
- Future expansion point (auth, rate limits, logging)

### Ollama (Inference Engine)

**Purpose**: Model loading, inference, and API serving

**Functionality**:
- Bind to loopback only (`127.0.0.1:11434`)
- Serve OpenAI-compatible API at `/v1/*`
- Serve Anthropic-compatible API at `/v1/messages`
- Automatic model loading and unloading
- Concurrent request handling (queuing)

**Managed by**:
- Configured via `install.sh`
- Environment: `OLLAMA_HOST=127.0.0.1` (loopback-only binding)
- Runs as user-level LaunchAgent (`~/Library/LaunchAgents/com.ollama.plist`)
- Auto-start on login, auto-restart on crash

**Security properties**:
- Unreachable from network (kernel-enforced loopback binding)
- Only local processes (including HAProxy) can connect
- Prevents direct network access bypassing proxy

---

## Exposed APIs (via HAProxy)

### OpenAI-Compatible API (v1)

- HTTP endpoint at `/v1`
- Primary route: `/v1/chat/completions`
- Supports:
  - Streaming (stream: true)
  - Non-streaming responses
  - JSON structured output (format: "json")
  - Tool / function calling (when underlying model implements it)
  - System, user, assistant message roles
- Model selection via `model` parameter (any model available on the server)
- **Primary clients**: Aider, Continue, OpenAI SDKs with custom base_url

**Forwarded endpoints:**
- `POST /v1/chat/completions`
- `GET /v1/models`
- `GET /v1/models/{model}`
- `POST /v1/responses` (experimental, Ollama 0.5.0+)

### Anthropic-Compatible API (v2+)

- HTTP endpoint at `/v1/messages`
- Anthropic Messages API compatibility layer
- Supports:
  - Messages with text and image content (base64)
  - Streaming via Server-Sent Events (SSE)
  - System prompts
  - Multi-turn conversations
  - Tool use (function calling)
  - Thinking blocks
- Limitations:
  - No `tool_choice` parameter
  - No prompt caching
  - No PDF/document support
  - Image URLs not supported (base64 only)
- Model selection via `model` parameter (same models as OpenAI API)
- **Primary clients**: Claude Code, Anthropic SDKs with custom base_url

**Forwarded endpoints:**
- `POST /v1/messages`

### Ollama Native API (Metadata Only)

**Safe metadata operations** (forwarded by HAProxy):
- `GET /api/version` - Ollama version info
- `GET /api/tags` - List models
- `POST /api/show` - Model details

**Dangerous operations** (blocked by HAProxy):
- `/api/pull` - Model download (consumes disk space)
- `/api/delete` - Model deletion (destructive)
- `/api/create` - Model creation (resource intensive)
- `/api/push` - Model upload (not applicable)
- `/api/copy` - Model copying (disk usage)

This prevents accidental or unauthorized model management operations.

---

## Service Behavior Requirements

### HAProxy

- **Startup**: Auto-start on user login
- **Availability**: Listen on Tailscale interface immediately after start
- **Failure handling**: Auto-restart on crash (KeepAlive=true)
- **Logging**: Optional (can be enabled in config)
- **Performance**: <1ms latency per request (transparent forwarding)

### Ollama

- **Startup**: Auto-start on user login (may take 5-10 seconds)
- **Model loading**: Automatic on first request (or pre-warmed via script)
- **Concurrency**: Graceful handling of concurrent requests (queuing)
- **Keep-alive**: Frequently used models kept in memory
- **Shutdown**: Clean restart without losing in-flight generations (best-effort)
- **Failure handling**: Auto-restart on crash (KeepAlive=true)

---

## Installation Workflow

### First-Time Setup (install.sh)

1. **System validation** - Check macOS 14+, Apple Silicon
2. **Dependencies** - Install Homebrew (if needed)
3. **Tailscale** - Install and configure for network access
4. **Ollama** - Install via Homebrew
5. **HAProxy** - Install via Homebrew (with user consent, "highly recommended")
6. **Configuration** - Create LaunchAgent plists for both services
7. **Loopback binding** - Set `OLLAMA_HOST=127.0.0.1` in Ollama plist
8. **Proxy config** - Generate `~/.haproxy/haproxy.cfg` with endpoint allowlist
9. **Service start** - Load both LaunchAgents
10. **Verification** - Test loopback binding and proxy forwarding
11. **Instructions** - Display Tailscale ACL configuration steps

### User Consent for HAProxy

Installation script prompts:
```
───────────────────────────────────────
Security Layer: HAProxy Proxy (Highly Recommended)
───────────────────────────────────────

This adds a security proxy between clients and Ollama.

Benefits:
  • Only allowlisted endpoints exposed (prevents accidental exposure)
  • Kernel-enforced isolation (Ollama unreachable from network)
  • Future-expandable (auth, rate limits can be added later)

Without proxy:
  • Ollama directly exposed to Tailscale network
  • All Ollama endpoints reachable (including future ones)
  • Higher risk of accidental exposure

Install HAProxy proxy? (Y/n)
```

Default: Yes (recommended)

---

## Uninstallation (uninstall.sh)

### Components Removed

1. **HAProxy service** - Stop and remove LaunchAgent
2. **HAProxy config** - Delete `~/.haproxy/` directory
3. **Ollama service** - Stop and remove LaunchAgent
4. **Ollama plist** - Delete `~/Library/LaunchAgents/com.ollama.plist`
5. **Logs** - Clean up `/tmp/ollama.*.log`, `/tmp/haproxy.log`

### Components Preserved

- Homebrew (may be needed for other tools)
- Tailscale (may be used for other purposes)
- Ollama binary (user may want to keep)
- Downloaded models in `~/.ollama/models/` (valuable data)
- HAProxy binary (from Homebrew, harmless)

---

## Testing (test.sh)

Comprehensive test script validates:

### Service Status Tests

- HAProxy LaunchAgent loaded and running
- HAProxy listening on Tailscale interface
- Ollama LaunchAgent loaded and running
- Ollama process running as user (not root)
- Ollama bound to loopback only (verified via `lsof -i :11434`)

### Security Isolation Tests

- Verify Ollama is unreachable from Tailscale IP directly
- Verify HAProxy forwards allowlisted endpoints only
- Verify non-allowlisted endpoints are blocked (403/404)

### API Endpoint Tests (OpenAI-Compatible)

- `GET /v1/models` - Returns JSON model list
- `GET /v1/models/{model}` - Returns single model details
- `POST /v1/chat/completions` - Non-streaming request succeeds
- `POST /v1/chat/completions` - Streaming (`stream: true`) returns SSE chunks
- `POST /v1/chat/completions` - JSON mode works
- `POST /v1/responses` - Experimental endpoint (Ollama 0.5.0+)

### API Endpoint Tests (Anthropic-Compatible)

- `POST /v1/messages` - Non-streaming request succeeds
- `POST /v1/messages` - Streaming returns correct SSE event sequence
- `POST /v1/messages` - System prompt processing
- `POST /v1/messages` - Error handling (nonexistent model)

### Performance Tests

- Measure HAProxy latency overhead (should be <1ms)
- Verify streaming latency (no buffering delays)

**Total tests**: 26+ (20 OpenAI, 6 Anthropic, security validation)

---

## Optional Model Pre-Warming (warm-models.sh)

**Purpose**: Load models into memory at boot time (reduces first-request latency)

**Functionality**:
- Accepts model names as command-line arguments
- Pulls models if not present (via `/api/pull`)
- Sends minimal inference request to force memory loading
- Continues on individual model failures (resilient)

**Usage**:
```bash
./warm-models.sh qwen2.5-coder:32b deepseek-r1:70b
```

**Integration** (optional):
- Can be wired into LaunchAgent as post-boot script
- Not required for normal operation

---

## Service Management Commands

### HAProxy

```bash
# Status
launchctl list | grep com.haproxy

# Start/Stop/Restart
launchctl kickstart gui/$(id -u)/com.haproxy
launchctl stop gui/$(id -u)/com.haproxy
launchctl kickstart -k gui/$(id -u)/com.haproxy

# Logs (if enabled)
tail -f /tmp/haproxy.log
```

### Ollama

```bash
# Status
launchctl list | grep com.ollama

# Start/Stop/Restart
launchctl kickstart gui/$(id -u)/com.ollama
launchctl stop gui/$(id -u)/com.ollama
launchctl kickstart -k gui/$(id -u)/com.ollama

# Logs
tail -f /tmp/ollama.stdout.log
tail -f /tmp/ollama.stderr.log
```

---

## Intended Testing Scope (non-normative)

### Model Classes

- Large instruction-tuned models (30B–70B+ class)
- Code-specialized models (qwen3-coder, deepseek-coder)
- Quantized variants suitable for Apple Silicon unified memory

### Performance Expectations

- Low added latency for worldwide clients (dependent on upload bandwidth)
- HAProxy overhead: <1ms per request (negligible)
- Reasonable throughput on large models when kept resident

---

## Future Expansion (Out of Scope for v1)

The proxy architecture enables future enhancements **without re-architecture**:

### Network-Level Hardening

- Request size limits
- Method allowlisting (GET/POST only)
- Endpoint-specific rate limits

### Execution-Level Hardening

- Concurrency limits (global and per-client)
- Timeout enforcement
- Model allowlists

### Identity-Aware Hardening

- Per-device credentials (static tokens)
- mTLS client certificates
- Tailscale identity integration

### Observability

- Structured access logs
- Request/response metrics
- Alerting on anomalies

See `HARDENING_OPTIONS.md` for complete design space (not requirements, just options).

---

## Summary

This functionality design provides:

> **Secure, transparent inference service through intentional exposure**

Three-layer architecture:
1. **Tailscale** - Controls who can reach the server
2. **HAProxy** - Controls what they can access
3. **Ollama** - Isolated on loopback, unreachable from network

All while maintaining:
- Dual API support (OpenAI + Anthropic)
- Automatic model loading and management
- Simple service management (LaunchAgent)
- Future-expandable security (proxy is expansion point)
- Zero client complexity (transparent proxy)
