# self-sovereign-ollama ai-server External Interfaces (v2.0.0)

## Architecture Overview

The server exposes APIs through a **two-layer architecture**:

```
VPN Client → WireGuard (Router) → Firewall → Ollama (192.168.100.10:11434)
```

- **VPN Clients** connect via WireGuard tunnel to router
- **Router Firewall** allows VPN → DMZ port 11434 only
- **Ollama** bound to DMZ interface, serves all API endpoints directly

This provides **network perimeter security** - only VPN-authenticated clients can reach the server.

---

## Network Access Path

### Layer 1: VPN Connection

**Client establishes WireGuard VPN:**
- Client connects to router's public IP (WireGuard UDP port, default 51820)
- Per-peer public key authentication
- Client assigned VPN IP (10.10.10.x)

### Layer 2: Firewall Forwarding

**Router firewall allows:**
- VPN → DMZ port 11434 (TCP)
- All other VPN → DMZ traffic denied
- VPN → LAN traffic denied
- VPN → WAN traffic denied

### Layer 3: Ollama Binding

**Ollama listens on:**
- DMZ interface: `192.168.100.10:11434` (recommended)
- Or all interfaces: `0.0.0.0:11434` (simpler configuration)

---

## Dual API Surface

Ollama exposes two distinct API compatibility layers on the same port (11434):

1. **OpenAI-Compatible API** - For Aider, Continue, and OpenAI-compatible tools
2. **Anthropic-Compatible API** - For Claude Code and Anthropic-compatible tools

Both served by the same Ollama process with no additional Ollama configuration required.

**Note**: All endpoints accessible to VPN clients (no application-layer filtering). Security provided by network perimeter (router firewall + VPN authentication).

---

## OpenAI-Compatible API

### Client Perspective

- HTTP API at `http://192.168.100.10:11434/v1`
- Fully OpenAI-compatible schema (chat completions endpoint)
- Accessible only from VPN clients

### Available Endpoints

**Primary endpoints:**
- `GET /v1/models` - List available models
- `GET /v1/models/{model}` - Get model details
- `POST /v1/chat/completions` - Chat completion requests (streaming & non-streaming)
- `POST /v1/responses` - Experimental non-stateful responses endpoint (Ollama 0.5.0+)

**Ollama Native API:**
- `GET /api/version` - Ollama version info
- `GET /api/tags` - List models
- `POST /api/show` - Model details
- `POST /api/generate` - Native generate endpoint
- `POST /api/pull` - Download models
- `POST /api/push` - Upload models (if registry configured)
- `POST /api/create` - Create model from Modelfile
- `DELETE /api/delete` - Delete models

### Security Note

**All Ollama endpoints are accessible to VPN clients**, including potentially destructive operations like:
- Model deletion (`DELETE /api/delete`)
- Model downloads (`POST /api/pull`) - can consume disk space
- Model creation (`POST /api/create`)

**Security model**: Trust VPN clients completely. Network perimeter (firewall + VPN auth) provides access control.

**Clients should use responsibly**. See `../client/specs/API_CONTRACT.md` for recommended usage patterns.

---

## Anthropic-Compatible API

### Client Perspective

- HTTP API at `http://192.168.100.10:11434/v1/messages`
- Anthropic Messages API compatibility layer
- Experimental feature (Ollama 0.5.0+)
- Accessible only from VPN clients

### Available Endpoints

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

## Network Configuration Interface

### DMZ Network

**Server static IP:**
- IP: `192.168.100.10` (default, configurable during install)
- Subnet: `192.168.100.0/24` (default, configurable)
- Gateway: `192.168.100.1` (router)
- DNS: Router or public DNS (configurable)

**Configured via:**
- `networksetup` command (macOS)
- Set during `install.sh` execution
- Can be manually changed in System Settings → Network

### Verify Configuration

**Check static IP:**
```bash
networksetup -getinfo "Ethernet"
```

**Test connectivity:**
```bash
# Router
ping -c 3 192.168.100.1

# Internet
ping -c 3 8.8.8.8
```

---

## Ollama Configuration Interface

### Environment Variables

- **OLLAMA_HOST**: Set to DMZ IP (`192.168.100.10`) or all interfaces (`0.0.0.0`)
- **OLLAMA_ORIGINS**: Optional CORS configuration (if browser clients needed)

### LaunchAgent Configuration

- **LaunchAgent plist**: `~/Library/LaunchAgents/com.ollama.plist`
- **Binding**: Enforced via `OLLAMA_HOST` in plist environment variables
- **Check status**: `launchctl list | grep com.ollama`
- **Start**: `launchctl kickstart gui/$(id -u)/com.ollama`
- **Stop**: `launchctl stop gui/$(id -u)/com.ollama`
- **Restart**: `launchctl kickstart -k gui/$(id -u)/com.ollama`
- **View logs**: `tail -f /tmp/ollama.stdout.log` or `/tmp/ollama.stderr.log`

### Verify Binding

```bash
# Check which interface Ollama is listening on
lsof -i :11434

# Should show:
# - 192.168.100.10:11434 (DMZ interface), or
# - *:11434 (all interfaces if 0.0.0.0)
```

---

## Router Management Interface

**Configuration**: See `ROUTER_SETUP.md` for complete guide

### WireGuard VPN

**Managed via router SSH or LuCI:**
- Add/remove VPN peers
- View tunnel status: `wg show wg0`
- Check handshakes and traffic

### Firewall Rules

**Managed via router SSH or LuCI:**
- View rules: `iptables -L -n -v`
- Modify rules: UCI commands or LuCI web interface
- Test connectivity from VPN client

### Router Access

**SSH** (recommended):
```bash
ssh root@192.168.100.1  # From DMZ server
ssh root@192.168.1.1     # From LAN
```

**LuCI Web Interface**:
```
http://192.168.100.1  # From DMZ server
http://192.168.1.1    # From LAN
```

---

## Management Interface (Server)

### Optional Scripts

- **Model pre-warming**: `server/scripts/warm-models.sh`
- **Test validation**: `server/scripts/test.sh`
- **Uninstall**: `server/scripts/uninstall.sh`

### Configuration Files

- **Ollama plist**: `~/Library/LaunchAgents/com.ollama.plist`
- **Ollama models**: `~/.ollama/models/`
- **Ollama logs**: `/tmp/ollama.stdout.log`, `/tmp/ollama.stderr.log`

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
- Direct HTTP requests to any Ollama endpoint
- Must connect via VPN (direct access from internet blocked by firewall)

### Connection Requirements

1. **Install WireGuard client** on device
2. **Import VPN configuration** (provided by router admin)
3. **Connect to VPN** - establishes encrypted tunnel
4. **Connect to server** - `http://192.168.100.10:11434`

See `../client/specs/` for complete client setup instructions.

---

## Network Security Boundaries

### Layer 1: Router Firewall (Who can reach server)

- Controls: Network access to DMZ
- Enforcement: Firewall rules (iptables)
- Management: Router configuration (see `ROUTER_SETUP.md`)

### Layer 2: WireGuard VPN (Who can authenticate)

- Controls: Per-peer authentication
- Enforcement: Public key cryptography
- Management: Router WireGuard configuration

### Layer 3: DMZ Isolation (What server can access)

- Controls: Server's network reachability
- Enforcement: Firewall rules (DMZ → LAN denied)
- Management: Router firewall zones

See `SECURITY.md` for complete security model.

---

## Migration from v1 (Tailscale + HAProxy)

If migrating from v1.1.1:

### For Server Operator

1. **Configure router** - Follow `ROUTER_SETUP.md`
2. **Configure static IP** - Run `install.sh` (v2) or configure manually
3. **Update Ollama binding** - Change `OLLAMA_HOST=127.0.0.1` to `OLLAMA_HOST=192.168.100.10`
4. **Restart Ollama** - `launchctl kickstart -k gui/$(id -u)/com.ollama`
5. **Verify binding** - `lsof -i :11434` (should show DMZ IP)
6. **Remove old stack** - Uninstall Tailscale and HAProxy (optional)

### For Clients

**Changes required**:
- Install WireGuard client
- Import VPN configuration
- Update environment variables:
  - Old: `OPENAI_API_BASE=http://self-sovereign-ollama:11434/v1`
  - New: `OPENAI_API_BASE=http://192.168.100.10:11434/v1`

See `../client/specs/` for complete migration guide.

---

## Performance Characteristics

### Latency

Network path adds minimal overhead:
- WireGuard encryption/decryption: ~0.1-0.5ms
- Router forwarding: <1ms
- No application-layer proxy (direct to Ollama)

For typical inference:
- Model loading: 1-10 seconds
- Token generation: 50-200ms per token
- Network overhead: ~1-2ms (negligible)

### Throughput

Router forwarding can handle:
- 10,000+ packets/second (routing capacity)
- Limited by Ollama concurrency (typically 5-10 concurrent)
- Upload bandwidth recommended: ≥100 Mb/s for low-latency streaming

Router is never the bottleneck for this use case.

### Bandwidth

**Upload bandwidth critical** for streaming responses:
- Typical streaming response: 50-200 tokens/second
- Token size: ~4 bytes
- Streaming bandwidth: ~1-2 KB/s per active stream
- Recommended: ≥100 Mb/s upload for worldwide low-latency

---

## Future Expansion Options

The architecture enables future enhancements **without re-architecture**:

**Network layer** (router):
- Connection rate limiting (iptables)
- Per-peer bandwidth limits (QoS)
- Intrusion detection system (Snort, Suricata)
- Web application firewall (ModSecurity)

**Application layer** (add reverse proxy in DMZ if needed):
- Request size limits
- Endpoint allowlisting (v1 HAProxy-style)
- API key authentication
- Access logging with attribution
- Model allowlists

See `HARDENING_OPTIONS.md` for complete design space (not requirements, just options).

---

## Summary

This interface design provides:

> **Self-sovereign network access with defense-in-depth**

**Network perimeter:**
- Router controls all ingress (single point of administration)
- WireGuard VPN provides per-peer authentication
- DMZ isolation prevents lateral movement

**Server simplicity:**
- Ollama serves all endpoints directly (no proxy)
- Static IP configuration (no dynamic DNS)
- Standard macOS service management (launchd)

**Security properties:**
- No public exposure of inference port
- Cryptographic authentication (WireGuard keys)
- Network segmentation (DMZ isolation)
- Minimal attack surface

Two architectural layers, complete network control.
