# Future Hardening Options (Design Space)

## Purpose of This Document

This document catalogs **optional capability-mediation controls** that can be layered onto the base architecture **without re-architecture**.

**This is NOT a roadmap or requirement list.**

It's a design space—a menu of orthogonal controls you can draw from later as needs evolve.

---

## Base Architecture (v1 Baseline)

The current three-layer architecture provides:

```
Layer 1: Tailscale → Controls WHO can reach the server
Layer 2: HAProxy → Controls WHAT they can access (endpoint allowlist)
Layer 3: Loopback → Controls WHAT can physically arrive (kernel-enforced)
```

This baseline provides:
- ✅ Intentional exposure (only allowlisted endpoints)
- ✅ Kernel-enforced isolation (loopback binding)
- ✅ Network-layer authorization (Tailscale ACLs)
- ✅ Single choke point for future controls (HAProxy)

**The following options build on top of this foundation.**

---

## A. Network-Level Capability Mediation

These controls act **before** a request reaches Ollama.

### A1. Endpoint Allowlisting

**Status**: ✅ Already implemented (HAProxy config)

Current allowlist:
- `POST /v1/chat/completions`
- `GET /v1/models`
- `GET /v1/models/{model}`
- `POST /v1/responses`
- `POST /v1/messages`
- `GET /api/version`
- `GET /api/tags`
- `POST /api/show`

All other paths blocked by default.

### A2. Method Allowlisting

**Capability**: Restrict HTTP methods to known-safe subset

**Implementation**: HAProxy ACL rules
```haproxy
acl is_safe_method method GET POST
http-request deny unless is_safe_method
```

**Mitigates**:
- Weird HTTP verb attacks (PUT, DELETE, PATCH, etc.)
- HTTP verb tampering
- Edge case vulnerabilities

**Cost**: None (negligible performance impact)

**Complexity**: Low (2-line config change)

### A3. Request Size Caps

**Capability**: Limit maximum request size to prevent resource exhaustion

**Implementation**: HAProxy config
```haproxy
# Max headers
tune.http.maxhdr 100

# Max request body (e.g., 100MB for images/contexts)
http-request deny if { req.body_size gt 104857600 }
```

**Mitigates**:
- Memory pressure from giant contexts
- Disk filling from massive image uploads
- Pathological payloads

**Trade-offs**:
- May need adjustment for legitimate large contexts
- Vision models with many images may hit limits

**Cost**: None (actually prevents resource waste)

**Complexity**: Low (config tuning)

### A4. Path Sanitization

**Capability**: Block requests with suspicious path patterns

**Implementation**: HAProxy ACL rules
```haproxy
acl has_path_traversal path_reg \\.\\./
acl has_null_bytes path_reg \\x00
http-request deny if has_path_traversal || has_null_bytes
```

**Mitigates**:
- Path traversal attempts
- Null byte injection
- URL encoding attacks

**Cost**: None

**Complexity**: Low

---

## B. Execution-Level Mediation

These controls regulate **how much** inference can happen.

### B1. Concurrency Limits

**Capability**: Cap maximum simultaneous requests

**Implementation**: HAProxy config
```haproxy
backend ollama
    maxconn 10  # Global limit
```

For per-client limits:
```haproxy
stick-table type ip size 100k expire 30s store conn_cur
acl too_many_conns src_conn_cur gt 3
http-request deny if too_many_conns
```

**Mitigates**:
- Silent compute abuse (one client monopolizing server)
- Self-DoS (buggy client spawning unbounded requests)
- Resource exhaustion

**Trade-offs**:
- May need tuning based on actual usage patterns
- Single client limited even if server idle

**Cost**: Minimal (just queue management)

**Complexity**: Low to Medium (depending on per-client vs global)

### B2. Time Limits (Request Timeout)

**Capability**: Kill hung requests after timeout

**Implementation**: HAProxy config
```haproxy
timeout client 300s  # 5 minutes max
timeout server 300s
```

**Mitigates**:
- Zombie generations (model stuck, never completes)
- Resource leaks from abandoned connections
- Streaming requests that never close

**Trade-offs**:
- Large models may legitimately take minutes
- May need longer timeouts for batch generations

**Cost**: None (prevents resource waste)

**Complexity**: Low

### B3. Model Allowlists

**Capability**: Restrict which models clients can load

**Implementation**: HAProxy Lua script or custom validation
```lua
-- Check if requested model is in allowlist
allowedModels = {
  ["qwen3-coder"] = true,
  ["glm-4.7:cloud"] = true,
  ["llama3.2"] = true
}

-- Extract model from request body, check allowlist
```

**Mitigates**:
- Accidental loading of huge models (OOM risk)
- Loading experimental/untrusted weights
- Resource exhaustion from model thrashing

**Trade-offs**:
- Requires maintaining allowlist
- Reduces flexibility (can't quickly try new models)

**Cost**: Low (validation overhead minimal)

**Complexity**: Medium (requires Lua scripting or external validation)

### B4. Rate Limiting (Requests per Time Window)

**Capability**: Cap requests per client per time period

**Implementation**: HAProxy stick tables
```haproxy
stick-table type ip size 100k expire 60s store http_req_rate(60s)
acl is_rate_limited src_http_req_rate gt 100
http-request deny if is_rate_limited
```

**Mitigates**:
- Abuse (excessive requests)
- Accidental loops (buggy client)
- Resource exhaustion

**Trade-offs**:
- Legitimate heavy users may hit limits
- Needs tuning based on workload

**Cost**: Minimal (table lookups)

**Complexity**: Medium

---

## C. Identity-Aware Mediation

These controls tie actions to device identity.

### C1. Per-Device Static Tokens

**Capability**: Require static API key per client device

**Implementation**: HAProxy header validation + stick table
```haproxy
# Define valid tokens (or load from file)
acl valid_token hdr(X-API-Key) -m str -f /etc/haproxy/tokens.txt
http-request deny unless valid_token

# Map token to device for attribution
stick-table type string len 64 size 10k expire 24h store ...
```

**Provides**:
- Per-device attribution (know who did what)
- Revocation capability (remove token)
- Differentiated access (different tokens, different limits)

**Trade-offs**:
- Requires token management (distribution, rotation)
- Adds operational complexity
- Tokens can leak (not cryptographically strong)

**Cost**: Low (header validation)

**Complexity**: Medium (token management overhead)

### C2. mTLS Client Certificates

**Capability**: Cryptographically strong client authentication

**Implementation**: HAProxy TLS frontend + client cert validation
```haproxy
frontend https
    bind *:11434 ssl crt /etc/haproxy/server.pem ca-file /etc/haproxy/ca.pem verify required
```

**Provides**:
- Strong authentication (private key required)
- Tamper-proof identity (certificate validation)
- Integration with Tailscale device identity

**Trade-offs**:
- High operational complexity (PKI management)
- Certificate distribution and renewal overhead
- Adds TLS termination (latency, though minimal)

**Cost**: Low latency (~1-2ms TLS handshake once per connection)

**Complexity**: High (certificate authority, renewal automation)

### C3. Tailscale Identity Integration

**Capability**: Extract Tailscale device identity from connection

**Implementation**: Custom HAProxy Lua script + Tailscale API
```lua
-- Query Tailscale API to map source IP to device
-- Use device tags for authorization decisions
```

**Provides**:
- Seamless integration with existing Tailscale ACLs
- No additional secrets to manage
- Centralized identity source

**Trade-offs**:
- Requires Tailscale API calls (latency)
- Depends on external service (Tailscale)
- Complex implementation

**Cost**: Medium (API call latency per new connection)

**Complexity**: High (API integration, caching)

---

## D. Observability & Audit

These controls provide visibility without restricting access.

### D1. Structured Access Logs

**Capability**: Log all requests with attribution

**Implementation**: HAProxy log format
```haproxy
log-format "%ci:%cp [%tr] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r"
```

**Captures**:
- Client IP (Tailscale device)
- Timestamp
- Endpoint accessed
- Response status
- Latency breakdown
- Request/response sizes

**Provides**:
- Usage patterns (who uses what, when)
- Performance insights (latency, throughput)
- Security auditing (detect anomalies)

**Trade-offs**:
- Log storage (grows over time)
- Privacy implications (tracks all usage)
- Log rotation required

**Cost**: Low (write-only, no blocking)

**Complexity**: Low (HAProxy built-in)

### D2. Metrics Export

**Capability**: Expose metrics for monitoring systems

**Implementation**: HAProxy stats socket
```haproxy
stats socket /run/haproxy/admin.sock mode 660 level admin
stats timeout 30s
```

Query via:
```bash
echo "show stat" | socat stdio /run/haproxy/admin.sock
```

**Metrics available**:
- Request rates
- Response times (percentiles)
- Error rates
- Concurrent connections
- Backend health

**Provides**:
- Real-time visibility
- Alerting basis (integrate with Prometheus/Grafana)
- Capacity planning data

**Trade-offs**:
- Requires monitoring infrastructure
- Unix socket security (access control)

**Cost**: Minimal (stats are always collected)

**Complexity**: Low (enable socket) to Medium (full monitoring stack)

### D3. Alerting Hooks

**Capability**: Trigger actions on anomalies

**Implementation**: HAProxy Lua + external webhook
```lua
-- On repeated failures, call webhook
if failCount > threshold then
    http.post("http://localhost:8080/alert", ...)
end
```

**Alerts on**:
- Repeated authentication failures
- Unusual request patterns
- High error rates
- Concurrent connection spikes

**Provides**:
- Proactive incident response
- Abuse detection
- Operational awareness

**Trade-offs**:
- Requires external alerting system
- False positives possible
- Alert fatigue risk

**Cost**: Low (webhook calls async)

**Complexity**: Medium to High (depends on alerting sophistication)

---

## E. Hard Isolation (If Priorities Shift)

These are architectural changes, not config additions.

### E1. VM/Container Boundary

**Capability**: Run Ollama in isolated environment

**Options**:
- VM: Ollama inside macOS VM (UTM, Parallels)
- Container: Ollama inside Docker container
- Sandbox: macOS App Sandbox restrictions

**Provides**:
- Kernel-level isolation (Ollama can't affect host)
- Resource limits (CPU, memory quotas)
- Snapshot/restore capability

**Trade-offs**:
- Performance overhead (especially for GPU passthrough)
- Complexity (VM/container management)
- Reduced hardware access (GPU may be virtualized)

**Cost**: High (10-30% performance penalty for virtualization)

**Complexity**: Very High (requires re-architecture)

**Recommendation**: Only if hosting untrusted models or tools.

### E2. Separate User Account

**Capability**: Run services as dedicated low-privilege user

**Implementation**:
```bash
sudo dscl . -create /Users/ollama
sudo dscl . -create /Users/ollama UserShell /usr/bin/false
# Run services as ollama user
```

**Provides**:
- Privilege separation (process can't access user files)
- Audit trail (filesystem actions attributed to ollama user)
- Defense in depth (compromised service contained)

**Trade-offs**:
- More complex setup (sudo required)
- File permission management overhead
- Breaks LaunchAgent user-level pattern

**Cost**: None (security benefit)

**Complexity**: Medium (user management, permissions)

---

## Decision Framework

When evaluating future hardening options:

### Questions to Ask

1. **What threat does this mitigate?**
   - Be specific (not just "security")
   - Is the threat realistic for your deployment?

2. **What's the operational cost?**
   - Complexity added (config, maintenance)
   - Performance impact (latency, throughput)
   - Ongoing overhead (token rotation, cert renewal)

3. **Can it be added incrementally?**
   - Does it require re-architecture?
   - Can it be tested in staging first?
   - Can it be rolled back easily?

4. **What's the baseline alternative?**
   - Network isolation (Tailscale) already in place
   - Endpoint allowlisting already in place
   - Loopback binding already in place

5. **Is there a simpler solution?**
   - Tighter Tailscale ACLs
   - Better monitoring (detect vs prevent)
   - Operational procedure (not technical control)

### Prioritization Matrix

| Option | Threat Mitigated | Complexity | Cost | Incremental? |
|--------|------------------|------------|------|--------------|
| Request size caps | Resource exhaustion | Low | None | ✅ Yes |
| Concurrency limits | Abuse, self-DoS | Low | None | ✅ Yes |
| Access logging | (Visibility only) | Low | Storage | ✅ Yes |
| Rate limiting | Abuse | Medium | Low | ✅ Yes |
| Static tokens | Attribution, abuse | Medium | Low | ✅ Yes |
| Model allowlist | Resource control | Medium | Low | ✅ Yes |
| mTLS | Strong auth | High | Low | ⚠️ Partial |
| VM isolation | Kernel compromise | Very High | High | ❌ No |

---

## Recommended Adoption Order

If you decide to add hardening:

**Phase 1: Zero-Cost Visibility**
1. Enable structured access logs (D1)
2. Analyze actual usage patterns
3. Identify real threats (not theoretical)

**Phase 2: Low-Complexity Controls**
4. Add request size caps (A3) - prevents obvious abuse
5. Add concurrency limits (B1) - prevents resource exhaustion
6. Add method allowlisting (A2) - closes edge cases

**Phase 3: Identity-Aware (If Needed)**
7. Implement per-device tokens (C1) - attribution and revocation
8. Enable metrics export (D2) - operational visibility
9. Set up alerting (D3) - proactive response

**Phase 4: Advanced (Only If Required)**
10. Rate limiting (B4) - if abuse detected in logs
11. Model allowlists (B3) - if resource thrashing occurs
12. mTLS (C2) - if cryptographic auth required

**NOT Recommended Unless...**
- VM isolation (E1) - Only for untrusted models/workloads
- Separate user (E2) - Only for paranoid deployments

---

## Implementation Patterns

### Incremental Addition

All options can be added via HAProxy config changes:

1. Edit `~/.haproxy/haproxy.cfg`
2. Test config: `haproxy -c -f ~/.haproxy/haproxy.cfg`
3. Reload (zero downtime): `launchctl kickstart -k gui/$(id -u)/com.haproxy`
4. Monitor logs for impact
5. Rollback if needed (restore previous config, reload)

### Testing Strategy

Before production:
1. Add control in staging environment
2. Measure impact (latency, false positives)
3. Tune thresholds based on real traffic
4. Document rollback procedure
5. Deploy to production with monitoring

### Rollback Safety

All options are **config-only** - no code changes required.

Rollback process:
1. Keep previous config: `cp haproxy.cfg haproxy.cfg.bak`
2. If issue: `mv haproxy.cfg.bak haproxy.cfg`
3. Reload: `launchctl kickstart -k gui/$(id -u)/com.haproxy`

---

## Summary

This document provides:

> **A catalog of optional controls, not requirements**

Key principles:
- ✅ Base architecture is secure (three-layer defense)
- ✅ All options are additive (no re-architecture needed)
- ✅ Prioritize based on actual threats (not theory)
- ✅ Measure before optimizing (logs first, controls second)
- ✅ Keep it simple (operational complexity is a cost)

**Start with visibility (logs), add controls only when data justifies them.**

The current baseline (Tailscale + HAProxy + Loopback) is strong. Don't add hardening prematurely—add it when you have evidence it's needed.
