# remote-ollama ai-server

Ollama server configuration for secure remote access from Apple Silicon Macs with high unified memory.

## Overview

The remote-ollama ai-server configures Ollama to provide secure, remote LLM inference with:
- **Three-layer security**: Tailscale → HAProxy → Ollama (loopback-bound)
- **Dual API support**: OpenAI-compatible `/v1/*` and Anthropic-compatible `/v1/messages` endpoints
- Supports both Aider (OpenAI API) and Claude Code (Anthropic API)
- HAProxy provides endpoint allowlisting and kernel-enforced isolation
- Runs exclusively on a dedicated, always-on Mac
- Zero public internet exposure
- No third-party cloud dependencies beyond Ollama, HAProxy, and Tailscale

## Quick Reference

| Operation | Command | Description |
|-----------|---------|-------------|
| **Check status** | `launchctl list \| grep com.haproxy` | Check if HAProxy service is loaded |
| | `launchctl list \| grep com.ollama` | Check if Ollama service is loaded |
| | `curl -sf http://localhost:11434/v1/models` | Test API endpoint availability (via HAProxy) |
| **Start service** | `launchctl kickstart gui/$(id -u)/com.haproxy` | Start HAProxy proxy if stopped |
| | `launchctl kickstart gui/$(id -u)/com.ollama` | Start Ollama if stopped |
| **Stop service** | `launchctl stop gui/$(id -u)/com.haproxy` | Stop HAProxy temporarily |
| | `launchctl stop gui/$(id -u)/com.ollama` | Stop Ollama temporarily |
| **Restart service** | `launchctl kickstart -k gui/$(id -u)/com.haproxy` | Kill and restart HAProxy immediately |
| | `launchctl kickstart -k gui/$(id -u)/com.ollama` | Kill and restart Ollama immediately |
| **View logs** | `tail -f /tmp/haproxy.log` | Monitor HAProxy access logs (if enabled) |
| | `tail -f /tmp/ollama.stdout.log` | Monitor Ollama standard output logs |
| | `tail -f /tmp/ollama.stderr.log` | Monitor Ollama error logs |
| **Check models** | `ollama list` | List all pulled models |
| **Warm models** | `./scripts/warm-models.sh <model-name>` | Pre-load models into memory for faster response |
| **Run tests** | `./scripts/test.sh` | Run comprehensive test suite (26 tests) |
| | `./scripts/test.sh --skip-anthropic-tests` | Skip Anthropic API tests (for Ollama < 0.5.0) |
| | `./scripts/test.sh --skip-model-tests` | Run tests without model inference |
| **Uninstall** | `./scripts/uninstall.sh` | Remove server configuration and services |

## Intended Deployment

- **Hardware**: Apple Silicon Mac (M-series) with ≥96 GB unified memory recommended
- **Network**: High upload bandwidth (≥100 Mb/s recommended for worldwide low-latency streaming)
- **Uptime**: 24/7 operation with UPS recommended
- **OS**: macOS 14 Sonoma or later

## Architecture

See [specs/ARCHITECTURE.md](specs/ARCHITECTURE.md) for full architectural details.

**Network topology:**
```
Client → Tailscale → HAProxy (100.x.x.x:11434) → Ollama (127.0.0.1:11434)
```

**Key principles:**
- **Three-layer security**: Tailscale (WHO can connect) → HAProxy (WHAT they can access) → Loopback binding (WHAT can physically arrive)
- Built on Ollama's native dual API capabilities (OpenAI + Anthropic)
- Minimal external dependencies (Ollama + HAProxy + Tailscale)
- Native macOS service management via launchd
- HAProxy provides endpoint allowlisting (only safe endpoints forwarded)
- Ollama kernel-isolated on loopback (127.0.0.1), unreachable from network
- Access restricted to authorized Tailscale devices

## API

The server exposes dual API surfaces via HAProxy at:
```
http://<tailscale-assigned-ip>:11434
```

HAProxy forwards allowlisted endpoints to Ollama (loopback-bound). All API access goes through the proxy layer.

### OpenAI-Compatible API (v1)

For Aider and OpenAI-compatible tools:

**Forwarded endpoints:**
- `/v1/chat/completions` - Streaming, JSON mode, tool calling
- `/v1/models` - List available models
- `/v1/models/{model}` - Get model details
- `/v1/responses` - Experimental non-stateful endpoint (Ollama 0.5.0+)

### Anthropic-Compatible API (v2+)

For Claude Code and Anthropic-compatible tools:

**Forwarded endpoint:**
- `/v1/messages` - Anthropic Messages API compatibility (Ollama 0.5.0+)

**Supported**:
- Messages, streaming, system prompts, multi-turn conversations
- Vision (base64 images), tool use, thinking blocks

**Limitations**:
- No `tool_choice` parameter
- No prompt caching (major performance impact)
- No PDF support, no URL-based images

See [specs/ANTHROPIC_COMPATIBILITY.md](specs/ANTHROPIC_COMPATIBILITY.md) for complete specification.

### Ollama Native API (Metadata Only)

HAProxy forwards safe metadata operations only:
- `GET /api/version` - Ollama version info
- `GET /api/tags` - List models
- `POST /api/show` - Model details

**Dangerous operations blocked** (not forwarded by HAProxy):
- `/api/pull`, `/api/delete`, `/api/create`, `/api/push`, `/api/copy`

This prevents unauthorized model management operations.

### API Contract

Full API contract documented in [../client/specs/API_CONTRACT.md](../client/specs/API_CONTRACT.md).

## Setup

See [SETUP.md](SETUP.md) for complete installation instructions.

Quick summary:
1. Install Tailscale, Ollama, and HAProxy
2. Configure Ollama with loopback binding (127.0.0.1) via launchd
3. Configure HAProxy to listen on Tailscale interface and forward allowlisted endpoints
4. Configure Tailscale ACLs for client access
5. Pull desired models via Ollama CLI
6. Verify connectivity from client (test HAProxy forwarding and loopback isolation)

## Operations

Once installed, both HAProxy and Ollama services run as LaunchAgents and start automatically at login.

### Check Status
```bash
# Check if HAProxy proxy is running
launchctl list | grep com.haproxy

# Check if Ollama service is running
launchctl list | grep com.ollama

# Test API endpoint (direct Ollama access from localhost, bypasses HAProxy)
curl -sf http://localhost:11434/v1/models

# Test HAProxy forwarding (from server via Tailscale IP)
curl -sf http://$(tailscale ip -4):11434/v1/models
```

### Start Service
```bash
# Start HAProxy (if stopped)
launchctl kickstart gui/$(id -u)/com.haproxy

# Start Ollama (if stopped)
launchctl kickstart gui/$(id -u)/com.ollama
```

### Stop Service
```bash
# Stop HAProxy temporarily
launchctl stop gui/$(id -u)/com.haproxy

# Stop Ollama temporarily
launchctl stop gui/$(id -u)/com.ollama
```

### Restart Service
```bash
# Restart HAProxy (kill and restart immediately)
launchctl kickstart -k gui/$(id -u)/com.haproxy

# Restart Ollama (kill and restart immediately)
launchctl kickstart -k gui/$(id -u)/com.ollama
```

### Disable Service (Prevent Auto-Start)
```bash
# Unload HAProxy completely
launchctl bootout gui/$(id -u)/com.haproxy

# Unload Ollama completely
launchctl bootout gui/$(id -u)/com.ollama
```

### Re-enable Service
```bash
# Load HAProxy again
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.haproxy.plist

# Load Ollama again
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ollama.plist
```

### View Logs
```bash
# HAProxy access logs (if enabled)
tail -f /tmp/haproxy.log

# Ollama standard output
tail -f /tmp/ollama.stdout.log

# Ollama error output
tail -f /tmp/ollama.stderr.log
```

### Warm Models (Optional Performance Optimization)

The `warm-models.sh` script pre-loads models into memory for faster first-request latency. This is useful for ensuring models are immediately ready after server boot or restart.

```bash
# Warm a single model
./scripts/warm-models.sh qwen2.5-coder:32b

# Warm multiple models
./scripts/warm-models.sh qwen2.5-coder:32b deepseek-r1:70b llama3.2-vision:90b
```

What it does:
- Pulls each model (downloads if not already present)
- Sends a minimal inference request to force-load the model into memory
- Continues processing remaining models if one fails
- Provides detailed progress reporting and summary

When to use it:
- After server restarts or reboots to eliminate cold-start latency
- Before critical workloads that require immediate response
- Can be integrated into launchd for automatic warmup at boot (see script comments)

## Testing & Verification

### Running the Test Suite

The server includes a comprehensive automated test suite that verifies all functionality:

```bash
# Run all tests (26 tests: service status, OpenAI API, Anthropic API, security, network)
./scripts/test.sh

# Skip Anthropic API tests (useful for Ollama versions < 0.5.0)
./scripts/test.sh --skip-anthropic-tests

# Run tests without model inference (faster, skips model-dependent tests)
./scripts/test.sh --skip-model-tests

# Run with verbose output (shows full API request/response details and timing)
./scripts/test.sh --verbose
```

### Test Coverage

The test suite validates:
- **Service Status** (6 tests): HAProxy and Ollama LaunchAgents loaded, processes running, HAProxy listening on Tailscale interface, Ollama listening on loopback
- **OpenAI API** (9 tests): All OpenAI-compatible endpoints (`/v1/models`, `/v1/models/{model}`, `/v1/chat/completions`, `/v1/responses`), streaming, error handling
- **Anthropic API** (6 tests, v2+): `/v1/messages` endpoint (non-streaming, streaming, system prompts, error handling, multi-turn, usage metrics)
- **Security Isolation** (3 tests): Ollama bound to loopback only (verified via `lsof`), Ollama unreachable from Tailscale IP directly, HAProxy forwards allowlisted endpoints only
- **Endpoint Allowlisting** (2 tests): Allowlisted endpoints forwarded correctly, non-allowlisted endpoints blocked

**Total**: 26 tests (20 v1 tests + 6 v2+ Anthropic API tests)

### Sample Output

```
remote-ollama ai-server Test Suite
Running 26 tests

=== Service Status Tests ===
✓ PASS HAProxy LaunchAgent is loaded: com.haproxy
✓ PASS HAProxy is listening on Tailscale interface
✓ PASS Ollama LaunchAgent is loaded: com.ollama
✓ PASS Ollama process is running (PID: 19272, user: vm)
✓ PASS Ollama is listening on port 11434
✓ PASS Ollama responds to HTTP requests

=== Security Isolation Tests ===
✓ PASS Ollama is bound to loopback only (127.0.0.1)
✓ PASS Ollama is unreachable from Tailscale IP directly
✓ PASS HAProxy forwards allowlisted endpoints only

=== OpenAI API Endpoint Tests ===
✓ PASS GET /v1/models returns valid JSON (1 models)
✓ PASS GET /v1/models/{model} returns valid model details
✓ PASS POST /v1/chat/completions (non-streaming) succeeded
✓ PASS POST /v1/chat/completions (streaming) returns SSE chunks

=== Anthropic API Tests (v2+) ===
✓ PASS POST /v1/messages (non-streaming) succeeded
✓ PASS POST /v1/messages (streaming) returns SSE chunks
✓ PASS POST /v1/messages with system prompt succeeded
✓ PASS POST /v1/messages error handling works (400/404/500)
✓ PASS POST /v1/messages multi-turn conversation succeeded
✓ PASS POST /v1/messages streaming includes usage metrics

...

Test Summary
───────────────────────────────
Passed:  26
Failed:  0
Skipped: 0
Total:   26
═══════════════════════════════

✓ All tests passed!
```

All 26 tests passed on hardware testing (2026-02-10 on vm@remote-ollama with qwen2.5-coder:7b).

## Security

See [specs/SECURITY.md](specs/SECURITY.md) for the complete security model.

**Three-layer defense in depth:**
1. **Tailscale** (Network Layer) - Controls WHO can reach the server
2. **HAProxy** (Application Layer) - Controls WHAT they can access (endpoint allowlist)
3. **Loopback Binding** (OS Kernel) - Controls WHAT can physically arrive (kernel-enforced)

**Properties:**
- No public internet exposure
- Intentional exposure (only allowlisted endpoints reachable)
- Kernel-enforced isolation (Ollama unreachable from network)
- Device-level authorization (Tailscale ACLs)
- Future-expandable security (HAProxy is expansion point)

## Documentation

- [SETUP.md](SETUP.md) – Complete setup instructions
- [specs/ARCHITECTURE.md](specs/ARCHITECTURE.md) – Architecture and principles
- [specs/FUNCTIONALITIES.md](specs/FUNCTIONALITIES.md) – Detailed functionality specifications
- [specs/SECURITY.md](specs/SECURITY.md) – Security model and three-layer architecture
- [specs/INTERFACES.md](specs/INTERFACES.md) – External interfaces
- [specs/FILES.md](specs/FILES.md) – Repository layout
- [specs/HARDENING_OPTIONS.md](specs/HARDENING_OPTIONS.md) – Future security expansion options

## Out of Scope (v1)

- Built-in authentication proxy / API keys
- Web-based chat UI
- Automatic model quantization
- Load balancing across multiple nodes
- Monitoring / metrics endpoint
