# remote-ollama-proxy ai-server Security Model

## Security Philosophy

This architecture implements **defense in depth** through three independent layers, each enforcing a different class of security invariant:

1. **Network-layer isolation** (Tailscale) - Controls who can send packets
2. **Application-layer proxy** (HAProxy) - Controls what packets can do
3. **OS-enforced binding** (Loopback) - Controls what packets can physically arrive

Each layer is independently enforceable and provides security even if others are misconfigured.

---

## Network Topology

```
Authorized client (Tailscale device)
    │
    ▼
Tailscale overlay network (100.x.x.x)
    │
    ▼
┌──────────────────────────────────────────┐
│ Server macOS                              │
│                                           │
│  HAProxy: 100.x.x.x:11434 ←─────┐        │
│      │                           │        │
│      │ (forwards)                │        │
│      ▼                           │        │
│  Ollama: 127.0.0.1:11434         │        │
│                                  │        │
│  Everything else:                │        │
│    • Bound to 127.0.0.1 only     │        │
│    • Or not listening at all     │        │
│                                  │        │
│  ← ONLY this socket exposed ─────┘        │
│     to Tailscale network                  │
└──────────────────────────────────────────┘
```

---

## Layer 1: Network Isolation (Tailscale)

### What it controls

**Who can send packets to the server**

### Implementation

- Tailscale tailnet membership (only invited devices can reach server IP)
- ACL rules enforce tag-based or device-based allowlists for port 11434
- Zero public internet exposure (no port forwarding, no dynamic DNS)

### Security properties

✅ Prevents unauthorized devices from reaching the server
✅ Cryptographically secure WireGuard tunnel
✅ Centralized access revocation (remove device from tailnet)
✅ Near-instant propagation of ACL changes

❌ Does not prevent authorized clients from misusing the API
❌ Does not prevent accidental exposure of other services
❌ Does not protect against Ollama vulnerabilities

---

## Layer 2: Application Proxy (HAProxy)

### What it controls

**What authorized packets are allowed to do**

### Implementation

- HAProxy listens on Tailscale interface only (`100.x.x.x:11434`)
- Forwards only specific endpoints to Ollama
- Ollama remains unreachable from network (loopback-only binding)

### Forwarded endpoints (allowlist)

**OpenAI-compatible API:**
- `POST /v1/chat/completions`
- `GET /v1/models`
- `GET /v1/models/{model}`
- `POST /v1/responses` (experimental, Ollama 0.5.0+)

**Anthropic-compatible API:**
- `POST /v1/messages`

**Ollama native API** (metadata only, safe operations):
- `GET /api/version`
- `GET /api/tags` (list models)
- `POST /api/show` (model info)

All other paths blocked by default.

### Security properties

✅ **Intentional exposure** - Only explicitly-forwarded endpoints are reachable
✅ **Prevents reachability creep** - New Ollama features do not become automatically exposed
✅ **Single choke point** - All network access funnels through one inspectable boundary
✅ **OS-enforced** - Loopback binding means proxy is the only path to Ollama
✅ **Future-expandable** - Can add rate limits, auth, logging without re-architecture

❌ Does not inspect request content (transparent forwarding)
❌ Does not prevent authorized clients from making valid-but-abusive requests
❌ Does not protect against Ollama API vulnerabilities (passes requests through)

### Why this is fundamental

The proxy transforms the security model from:

> "Ollama is exposed; remember not to expose anything else"

To:

> "Nothing is exposed unless explicitly wired through the proxy"

This is **enforced by the kernel** (loopback binding), not by memory or discipline.

---

## Layer 3: Loopback Binding (OS-enforced)

### What it controls

**What packets can physically arrive at a process**

### Implementation

- Ollama configured to bind `127.0.0.1:11434` only (via `OLLAMA_HOST`)
- LaunchAgent plist explicitly sets `OLLAMA_HOST=127.0.0.1`
- No listening sockets bound to `0.0.0.0` or Tailscale interfaces

### Security properties

✅ **Kernel-enforced isolation** - Ollama cannot receive network packets
✅ **Immune to misconfiguration** - Even if proxy fails, Ollama stays unreachable
✅ **Prevents accidental exposure** - Dev tools, debug servers, experiments stay local
✅ **Defense in depth** - Provides security even if proxy is misconfigured

❌ Does not prevent local processes from accessing Ollama
❌ Does not prevent proxy from forwarding malicious requests

---

## What This Architecture Prevents

### ✅ Completely Prevented

**Accidental exposure:**
- Dev servers running on random ports
- Debug dashboards (Prometheus, Grafana, etc.)
- Ad-hoc scripts listening on network interfaces
- Future Ollama features you didn't intend to expose

**Reachability creep:**
- "I forgot this service was running"
- "I didn't know that port was exposed"
- Time-dependent exposure (ports opened during debugging)

**Re-binding risks:**
- Ollama accidentally bound to `0.0.0.0`
- Configuration drift over time
- Experiments that persist

### ⚠️ Mitigated (but not eliminated)

**Resource exhaustion:**
- Proxy can add rate limits (future)
- Proxy can cap concurrent requests (future)
- OS still vulnerable to local resource pressure

### ❌ Explicitly Out of Scope (v1 threat model)

**Abuse by authorized clients:**
- Excessive inference requests
- Prompt injection attacks
- Extraction of model weights
- Quality-of-service violations

**Application-layer vulnerabilities:**
- Ollama API bugs
- Model-level exploits
- Prompt-level attacks

**Host compromise:**
- Kernel vulnerabilities
- Privilege escalation
- Local malware

These are valid concerns but **not addressed by this architecture**.

---

## Access Control & Revocation

### Adding a client

1. Invite device to Tailscale tailnet
2. Add device or tag to ACL allowlist for port 11434
3. Client can now reach HAProxy (and only HAProxy)

### Revoking access

1. Remove device from tailnet, OR
2. Remove device/tag from ACL allowlist

Changes propagate near-instantly (Tailscale WireGuard tunnel update).

### Per-device granularity

Tailscale ACLs support:
- Device-specific rules (allow only laptop-X)
- Tag-based rules (allow all devices tagged `ai-client`)
- Time-based rules (optional, via Tailscale policy)

---

## Operational Security Requirements

### Logging

- Ollama logs remain local (`/tmp/ollama.stdout.log`, `/tmp/ollama.stderr.log`)
- HAProxy logs remain local (if enabled)
- No outbound telemetry or analytics
- Log rotation recommended (via `launchd` or external tool)

### Updates

Regular security updates required for:
- macOS system and security patches
- Tailscale client
- Ollama binary
- HAProxy binary (via Homebrew)

### Process ownership

- Ollama runs as user-level LaunchAgent (not root)
- HAProxy runs as user-level LaunchAgent (not root)
- No elevated privileges required during normal operation

### Monitoring

Optional (not required for security):
- HAProxy statistics socket (local Unix socket)
- Ollama health checks (via proxy)
- System resource monitoring (CPU, memory, GPU)

---

## CORS Considerations

- Default Ollama CORS restrictions apply
- HAProxy does not modify CORS headers (transparent forwarding)
- Optional: Set `OLLAMA_ORIGINS` environment variable if browser-based clients are planned
- Browser clients must go through proxy (cannot reach Ollama directly)

---

## Threat Model Summary

### In scope (addressed by this architecture)

✅ Unauthorized network access
✅ Accidental service exposure
✅ Configuration drift
✅ Reachability creep

### Out of scope (explicitly not addressed)

❌ Authorized client abuse
❌ Application-layer vulnerabilities
❌ Host-level compromise
❌ Physical access attacks
❌ Social engineering

This is intentional. The architecture focuses on **network-layer and exposure-control threats**, not application-layer or abuse-mitigation threats.

Future hardening options (rate limits, auth, quotas) can be layered on top **without changing this base architecture**. See `HARDENING_OPTIONS.md` for design space.

---

## Comparison with Direct Exposure

### Direct Ollama exposure (insecure)

```
Client → Tailscale → Ollama (0.0.0.0:11434)
```

**Problems:**
- Everything Ollama exposes is reachable (including future endpoints)
- Other services accidentally bound to network are exposed
- No choke point for future controls (auth, rate limits, etc.)
- Security depends on remembering to bind everything correctly

### Proxy architecture (this design)

```
Client → Tailscale → HAProxy (100.x.x.x:11434) → Ollama (127.0.0.1:11434)
```

**Benefits:**
- Only explicitly-forwarded endpoints are reachable
- Kernel-enforced isolation (loopback binding)
- Single choke point for future controls
- Security is structural, not procedural

---

## Migration from Direct Exposure

If Ollama was previously bound to `0.0.0.0` or Tailscale interface:

1. Install and configure HAProxy (see `SCRIPTS.md`)
2. Update Ollama LaunchAgent plist: `OLLAMA_HOST=127.0.0.1`
3. Restart Ollama service
4. Verify loopback binding: `lsof -i :11434` (should show `127.0.0.1` only)
5. Test client connectivity through proxy

**No client changes required** - hostname and port remain the same (`remote-ollama-proxy:11434`).

---

## Future Hardening Options

This architecture provides a **foundation** for future security enhancements without re-architecture:

- Endpoint allowlisting (already in place via proxy config)
- Request size limits
- Concurrency limits
- Per-device credentials
- Rate limiting
- Access logging with attribution
- Model allowlists

See `HARDENING_OPTIONS.md` for complete design space (not requirements, just options).

---

## Security Review Recommendations

For production deployments:

1. **Verify loopback binding** - Run `lsof -i :11434` on server
2. **Test isolation** - Attempt direct Ollama access from client (should fail)
3. **Review Tailscale ACLs** - Ensure only intended devices/tags have access
4. **Monitor logs** - Check for unexpected access patterns
5. **Update regularly** - Keep all components patched
6. **Document changes** - Track ACL modifications and access grants

---

## Summary

This architecture provides:

> **Structural security through intentional exposure**

- Network layer controls **who** can reach the server (Tailscale)
- Proxy layer controls **what** they can do (HAProxy)
- Loopback binding ensures **nothing else** is accidentally reachable (OS kernel)

Each layer is independently verifiable and provides defense in depth.
