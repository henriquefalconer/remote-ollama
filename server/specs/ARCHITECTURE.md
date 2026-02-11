# remote-ollama ai-server Architecture

## Core Principles

- **Intentional exposure** - Only explicitly-forwarded endpoints are reachable via network
- **Kernel-enforced isolation** - Ollama bound to loopback only; unreachable from network
- **Single choke point** - All remote access funnels through application proxy (HAProxy)
- Run Ollama exclusively on a dedicated, always-on machine (separate from clients)
- Zero public internet exposure
- Zero third-party cloud dependencies
- Minimal external dependencies (Ollama + Tailscale + HAProxy)
- Native macOS service management via launchd
- Access restricted to explicitly authorized client devices only

---

## Intended Deployment Context

- Apple Silicon Mac (M-series) with high unified memory capacity (≥96 GB strongly recommended)
- 24/7 operation with uninterruptible power supply
- High upload bandwidth network connection (≥100 Mb/s recommended for low-latency streaming worldwide)
- The server machine is **not** the development or usage workstation — clients connect remotely

---

## Architecture Overview

### Network Topology

```
┌─────────────────────────────────────────────────────────┐
│                  Authorized Clients                      │
│             (Tailscale-connected devices)                │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Tailscale Overlay Network                   │
│                   (100.x.x.x/24)                         │
│         Encrypted WireGuard tunnel + ACLs                │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│                Server macOS (M-series)                   │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  HAProxy (Layer 2: Application Proxy)              │ │
│  │  • Listen: 100.x.x.x:11434 (Tailscale interface)   │ │
│  │  • Forward: Only allowlisted endpoints             │ │
│  │  • Block: Everything else by default               │ │
│  └──────────────────┬─────────────────────────────────┘ │
│                     │                                    │
│                     ▼                                    │
│  ┌────────────────────────────────────────────────────┐ │
│  │  Ollama (Layer 3: Loopback-bound)                  │ │
│  │  • Bind: 127.0.0.1:11434 ONLY                      │ │
│  │  • Unreachable from network                        │ │
│  │  • Model loading, inference, streaming             │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  All Other Services                                 │ │
│  │  • Bound to 127.0.0.1 only                         │ │
│  │  • Or not listening at all                         │ │
│  │  • NOT exposed to Tailscale network                │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Security Layers (Defense in Depth)

1. **Tailscale (Network Layer)** - Controls **who** can send packets
   - WireGuard tunnel encryption
   - ACL-based device/tag allowlisting
   - Zero trust network model

2. **HAProxy (Application Layer)** - Controls **what** packets can do
   - Endpoint allowlisting (only specific paths forwarded)
   - Single inspectable boundary
   - Future expansion point (auth, rate limits, logging)

3. **Loopback Binding (OS Layer)** - Controls **what** packets can physically arrive
   - Kernel-enforced isolation
   - Ollama unreachable from network
   - Prevents accidental exposure

See `SECURITY.md` for complete security model documentation.

---

## Server Responsibilities

### Ollama Configuration

- Bind Ollama to **loopback only** (`127.0.0.1:11434`)
- Configured via `OLLAMA_HOST=127.0.0.1` environment variable in LaunchAgent plist
- Let Ollama handle model loading, inference, and unloading automatically
- Leverage Ollama's native support for streaming responses, JSON mode, tool calling

### HAProxy Configuration

- Listen on Tailscale interface only (`100.x.x.x:11434`)
- Forward only allowlisted endpoints to Ollama
- Transparent forwarding (no request mutation, minimal latency)
- Block all non-allowlisted paths by default

### Dual API Surface (via HAProxy)

Ollama exposes both OpenAI-compatible and Anthropic-compatible APIs. HAProxy forwards both:

**OpenAI-compatible API:**
- `POST /v1/chat/completions`
- `GET /v1/models`
- `GET /v1/models/{model}`
- `POST /v1/responses` (experimental, Ollama 0.5.0+)

**Anthropic-compatible API:**
- `POST /v1/messages`

**Ollama Native API** (metadata only):
- `GET /api/version`
- `GET /api/tags`
- `POST /api/show`

All other endpoints blocked by default.

---

## Component Management

### Service Architecture

All services run as user-level LaunchAgents (not root):

**Ollama LaunchAgent** (`~/Library/LaunchAgents/com.ollama.plist`)
- Binds `127.0.0.1:11434`
- Sets `OLLAMA_HOST=127.0.0.1`
- Auto-start on login (`RunAtLoad=true`)
- Auto-restart on crash (`KeepAlive=true`)
- Logs to `/tmp/ollama.stdout.log`, `/tmp/ollama.stderr.log`

**HAProxy LaunchAgent** (`~/Library/LaunchAgents/com.haproxy.plist`)
- Binds Tailscale interface port 11434
- Auto-start on login
- Auto-restart on crash
- Logs to `/tmp/haproxy.log` (if enabled)

### Service Management Commands

**Ollama:**
```bash
# Status
launchctl list | grep com.ollama

# Start/Stop/Restart
launchctl kickstart gui/$(id -u)/com.ollama
launchctl stop gui/$(id -u)/com.ollama
launchctl kickstart -k gui/$(id -u)/com.ollama

# View logs
tail -f /tmp/ollama.stdout.log
tail -f /tmp/ollama.stderr.log
```

**HAProxy:**
```bash
# Status
launchctl list | grep com.haproxy

# Start/Stop/Restart
launchctl kickstart gui/$(id -u)/com.haproxy
launchctl stop gui/$(id -u)/com.haproxy
launchctl kickstart -k gui/$(id -u)/com.haproxy

# View logs (if enabled)
tail -f /tmp/haproxy.log
```

---

## Network & Access Model

### Tailscale Configuration

- All remote access goes through Tailscale overlay network
- No port forwarding, no dynamic DNS, no public IP binding
- ACLs enforce per-device or per-tag authorization for port 11434
- Clients connect to `remote-ollama:11434` (resolved via Tailscale DNS)

### HAProxy Configuration

- Listens on Tailscale interface address (`100.x.x.x:11434`)
- Forwards allowlisted endpoints to `127.0.0.1:11434` (Ollama)
- Configuration file: `~/.haproxy/haproxy.cfg` (see `FILES.md`)
- Minimal config: transparent forwarding, no TLS, no auth (v1)

### Loopback Isolation

- Ollama bound to `127.0.0.1` only
- Cannot receive packets from network interfaces
- Only local processes (including HAProxy) can connect
- Kernel-enforced (not dependent on firewall rules)

---

## Design Rationale

### Why Proxy Instead of Direct Exposure?

**Previous approach (insecure):**
```
Client → Tailscale → Ollama (0.0.0.0:11434)
```
- Ollama directly reachable from network
- All Ollama endpoints automatically exposed (including future ones)
- Other services accidentally bound to network also exposed
- Security depends on remembering to configure everything correctly

**Current approach (secure):**
```
Client → Tailscale → HAProxy (100.x.x.x:11434) → Ollama (127.0.0.1:11434)
```
- Ollama unreachable from network (kernel-enforced)
- Only explicitly-forwarded endpoints exposed
- Single choke point for all access
- Security is structural, not procedural

### Why HAProxy?

- **Independent** - Community-driven, no company control
- **Mature** - Proven in production for 20+ years
- **Minimal** - Small footprint, transparent forwarding
- **Fast** - Negligible latency overhead (<1ms)
- **Expandable** - Can add rate limits, auth, logging later without re-architecture
- **Simple** - Configuration is straightforward and readable

Alternative proxies considered but rejected:
- nginx/caddy - Company-backed, more features than needed
- socat - Too simple, hard to expand
- Envoy/Traefik - Too heavy, too complex
- Custom script - Maintenance burden

---

## Performance Characteristics

### Latency Impact

HAProxy adds **<1ms** per request:
- Minimal parsing (just path matching)
- No content inspection
- No request mutation
- No TLS termination (Tailscale already encrypted)

For typical inference workload:
- Model loading: 1-10 seconds (Ollama)
- Token generation: 50-200ms per token (Ollama)
- Proxy overhead: <1ms

Proxy latency is **negligible** compared to inference time.

### Throughput Impact

HAProxy can handle:
- 10,000+ requests/second on modest hardware
- Concurrent connections limited only by Ollama (typically 5-10)

For this use case (single-user or small team):
- Ollama is bottleneck (model loading, GPU memory)
- HAProxy is never the limiting factor

---

## Deployment Variants

### Single Server (Standard)

```
Client 1 ─┐
Client 2 ─┼→ Tailscale → HAProxy → Ollama (127.0.0.1)
Client 3 ─┘
```

All clients share single Ollama instance. This is the standard deployment.

### Future: Multiple Backends (Optional)

```
Client ─→ Tailscale ─→ HAProxy ─┬→ Ollama 1 (127.0.0.1:11434)
                                 ├→ Ollama 2 (127.0.0.1:11435)
                                 └→ Ollama 3 (127.0.0.1:11436)
```

HAProxy can load-balance across multiple Ollama instances (if running multiple on same host).

**Out of scope for v1**, but architecture supports it.

---

## Migration Path

If previously deployed with direct Ollama exposure:

1. Install HAProxy via `install.sh` (user consent required)
2. Update Ollama plist: `OLLAMA_HOST=127.0.0.1`
3. Restart Ollama service
4. Verify isolation: `lsof -i :11434` (should show loopback only)
5. Test client connectivity

**No client changes required** - hostname stays `remote-ollama:11434`.

---

## Out of Scope

### v1 Baseline

The following are **intentionally excluded** from baseline architecture:

- Built-in authentication / API keys (network isolation sufficient)
- TLS termination (Tailscale already provides encryption)
- Request content inspection / mutation
- Rate limiting / quotas (can add later via HAProxy)
- Access logging (can add later via HAProxy)
- Monitoring / metrics endpoints (can add later)
- Web-based UI
- Model quantization / conversion
- Multi-server load balancing

These can be added **without changing the base architecture**. See `HARDENING_OPTIONS.md` for future expansion options.

---

## Failure Modes & Recovery

### HAProxy Crash

- Ollama remains running but unreachable from network
- Loopback binding prevents direct access
- LaunchAgent auto-restarts HAProxy (KeepAlive=true)
- Typical recovery time: <1 second

### Ollama Crash

- HAProxy remains running
- Returns 503 Service Unavailable to clients
- LaunchAgent auto-restarts Ollama (KeepAlive=true)
- Typical recovery time: 5-10 seconds (model reloading)

### Tailscale Disconnect

- Both services remain running
- All clients lose connectivity
- No exposed attack surface (loopback binding)
- Reconnects automatically when Tailscale recovers

### Configuration Error

- If HAProxy config invalid: refuses to start
- If Ollama binding wrong: HAProxy returns 503
- If both misconfigured: loopback binding prevents exposure

**Defense in depth**: Even with component failure, system stays secure.

---

## Monitoring & Observability

### Health Checks

**Ollama health:**
```bash
curl http://127.0.0.1:11434/api/version
```

**HAProxy health:**
```bash
curl http://127.0.0.1:9090/stats  # If stats socket enabled
```

**End-to-end health (from client):**
```bash
curl http://remote-ollama:11434/v1/models
```

### Log Locations

- Ollama: `/tmp/ollama.stdout.log`, `/tmp/ollama.stderr.log`
- HAProxy: `/tmp/haproxy.log` (if enabled)
- LaunchAgent: `~/Library/Logs/` (system logs)

### Optional Metrics

HAProxy can export (future):
- Request rates
- Response times
- Error rates
- Backend health

Not required for v1, but supported by HAProxy.

---

## Summary

This architecture provides:

> **Secure remote access via structural isolation**

Three independent layers:
1. **Tailscale** controls who can reach the server
2. **HAProxy** controls what they can access
3. **Loopback binding** ensures nothing else is accidentally exposed

Benefits:
- ✅ Minimal attack surface (only allowlisted endpoints)
- ✅ Kernel-enforced isolation (not dependent on configuration)
- ✅ Future-expandable (auth, rate limits, etc. can be added)
- ✅ Negligible performance impact (<1ms proxy latency)
- ✅ Defense in depth (each layer independently secure)

All while maintaining:
- Zero public internet exposure
- Zero third-party cloud dependencies
- Simple operational model (LaunchAgent services)
- Transparent to clients (same hostname, same endpoints)
