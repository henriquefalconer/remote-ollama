# remote-ollama ai-server External Interfaces

## Architecture Overview

The server exposes APIs through a **three-layer architecture**:

```
Client → Tailscale → HAProxy (100.x.x.x:11434) → Ollama (127.0.0.1:11434)
```

- **Clients** connect to `remote-ollama:11434` (Tailscale DNS resolution)
- **HAProxy** listens on Tailscale interface, forwards allowlisted endpoints only
- **Ollama** bound to loopback only, unreachable from network

This provides **intentional exposure** - only explicitly-forwarded endpoints are reachable.

---

## Dual API Surface

Ollama exposes two distinct API compatibility layers. HAProxy forwards both on the same port (11434):

1. **OpenAI-Compatible API** - For Aider, Continue, and OpenAI-compatible tools
2. **Anthropic-Compatible API** - For Claude Code and Anthropic-compatible tools

Both served by the same Ollama process with no additional Ollama configuration required.

---

## OpenAI-Compatible API (v1)

### Client Perspective

- HTTP API at `http://remote-ollama:11434/v1`
- Fully OpenAI-compatible schema (chat completions endpoint)
- No custom routes or extensions in v1

### Forwarded Endpoints (via HAProxy)

**Primary endpoints:**
- `GET /v1/models` - List available models
- `GET /v1/models/{model}` - Get model details
- `POST /v1/chat/completions` - Chat completion requests (streaming & non-streaming)
- `POST /v1/responses` - Experimental non-stateful responses endpoint (Ollama 0.5.0+)

**Ollama Native API** (metadata only, safe operations):
- `GET /api/version` - Ollama version info
- `GET /api/tags` - List models
- `POST /api/show` - Model details

All other endpoints blocked by HAProxy.

### Security Note

Ollama also serves additional native endpoints at `/api/*` (e.g., `/api/pull`, `/api/delete`, `/api/create`), but these are **not forwarded** by HAProxy and are therefore unreachable from clients. This prevents:
- Accidental model deletion
- Unauthorized model pulls (consuming disk space)
- Model creation/modification

The guaranteed contract for clients is the forwarded endpoints only (see `../client/specs/API_CONTRACT.md`).

---

## Anthropic-Compatible API (v2+)

### Client Perspective

- HTTP API at `http://remote-ollama:11434/v1/messages`
- Anthropic Messages API compatibility layer
- Experimental feature (Ollama 0.5.0+)

### Forwarded Endpoints (via HAProxy)

**Primary endpoint:**
- `POST /v1/messages` - Anthropic-style message creation

### Supported features

- ✅ Messages with text and image content (base64 only)
- ✅ Streaming via Server-Sent Events (SSE)
- ✅ System prompts
- ✅ Multi-turn conversations
- ✅ Tool use (function calling)
- ✅ Thinking blocks
- ❌ `tool_choice` parameter (not supported by Ollama)
- ❌ Prompt caching (not supported by Ollama)
- ❌ PDF/document support (not supported by Ollama)

**See `ANTHROPIC_COMPATIBILITY.md` for complete specification.**

---

## HAProxy Configuration Interface

### Configuration File

- Location: `~/.haproxy/haproxy.cfg`
- Format: HAProxy configuration syntax
- Managed by: `install.sh` and `uninstall.sh`

### Minimal Configuration (v1)

The proxy is configured for **transparent forwarding**:
- No authentication
- No TLS termination (Tailscale already provides encryption)
- No request mutation
- No content inspection
- Endpoint allowlisting only

Future hardening can be added without client changes (see `HARDENING_OPTIONS.md`).

### Service Management

HAProxy runs as a user-level LaunchAgent:

- **LaunchAgent plist**: `~/Library/LaunchAgents/com.haproxy.plist`
- **Check status**: `launchctl list | grep com.haproxy`
- **Start**: `launchctl kickstart gui/$(id -u)/com.haproxy`
- **Stop**: `launchctl stop gui/$(id -u)/com.haproxy`
- **Restart**: `launchctl kickstart -k gui/$(id -u)/com.haproxy`
- **View logs**: `tail -f /tmp/haproxy.log` (if enabled)

---

## Ollama Configuration Interface

### Environment Variables

- **OLLAMA_HOST**: Must be set to `127.0.0.1` for loopback binding
- **OLLAMA_ORIGINS**: Optional CORS configuration (if browser clients needed)

### LaunchAgent Configuration

- **LaunchAgent plist**: `~/Library/LaunchAgents/com.ollama.plist`
- **Binding**: Enforced via `OLLAMA_HOST=127.0.0.1` in plist
- **Check status**: `launchctl list | grep com.ollama`
- **Start**: `launchctl kickstart gui/$(id -u)/com.ollama`
- **Stop**: `launchctl stop gui/$(id -u)/com.ollama`
- **Restart**: `launchctl kickstart -k gui/$(id -u)/com.ollama`
- **View logs**: `tail -f /tmp/ollama.stdout.log` or `/tmp/ollama.stderr.log`

---

## Management Interface (minimal)

### Tailscale ACLs

- Managed via Tailscale admin console (external to this monorepo)
- Controls which devices can reach port 11434 on the server
- Tag-based or device-based allowlisting

### Optional Components

- Model pre-warming script (`warm-models.sh`)
- Test validation script (`test.sh`)

---

## Client Consumption Patterns (informative only)

### Supported Client Types

**CLI tools:**
- Aider (OpenAI-compatible)
- Claude Code (Anthropic-compatible)
- Continue (OpenAI-compatible)
- Any tool supporting custom base URLs

**SDKs:**
- OpenAI SDK (Python, Node.js, etc.) with `base_url` override
- Anthropic SDK (Python, TypeScript) with `base_url` override

**Custom scripts:**
- Direct HTTP requests to forwarded endpoints
- Must go through HAProxy (direct Ollama access blocked by loopback binding)

### Connection Requirements

1. Device must be connected to Tailscale tailnet
2. Device must be authorized via ACLs for port 11434
3. Connect to `remote-ollama:11434` (Tailscale DNS handles resolution)

---

## Network Security Boundaries

### Layer 1: Tailscale (Who can connect)

- Controls: Device authorization
- Enforcement: WireGuard tunnel, ACL rules
- Management: Tailscale admin console

### Layer 2: HAProxy (What they can access)

- Controls: Endpoint allowlisting
- Enforcement: Path-based forwarding rules
- Management: `~/.haproxy/haproxy.cfg`

### Layer 3: Loopback (What can physically arrive)

- Controls: Process network reachability
- Enforcement: OS kernel socket binding
- Management: `OLLAMA_HOST` environment variable

See `SECURITY.md` for complete security model.

---

## Migration from Direct Exposure

If previously deployed without proxy layer:

### For Server Operator

1. Install HAProxy via `install.sh`
2. Update Ollama plist: `OLLAMA_HOST=127.0.0.1`
3. Restart Ollama service
4. Verify isolation: `lsof -i :11434` (should show loopback only)

### For Clients

**No changes required** - hostname and port remain the same (`remote-ollama:11434`).

HAProxy transparently replaces direct Ollama access at the same network endpoint.

---

## Performance Characteristics

### Latency

HAProxy adds **<1ms** per request:
- Path matching only (no content inspection)
- Transparent forwarding
- No TLS termination (Tailscale handles encryption)

For typical inference:
- Model loading: 1-10 seconds
- Token generation: 50-200ms per token
- Proxy overhead: <1ms (negligible)

### Throughput

HAProxy can handle:
- 10,000+ requests/second (proxy capacity)
- Limited by Ollama concurrency (typically 5-10 concurrent)

Proxy is never the bottleneck for this use case.

---

## Future Expansion Options

The proxy architecture enables future enhancements **without re-architecture**:

- Request size limits
- Concurrency limits
- Per-device credentials
- Rate limiting
- Access logging with attribution
- Model allowlists
- mTLS client certificates

See `HARDENING_OPTIONS.md` for complete design space (not requirements, just options).

---

## Summary

This interface design provides:

> **Secure, transparent access through intentional exposure**

- Clients connect to same hostname and port (`remote-ollama:11434`)
- HAProxy ensures only allowlisted endpoints are reachable
- Ollama stays isolated on loopback (kernel-enforced)
- Future hardening can be added without client changes

Three security layers, zero client complexity.
