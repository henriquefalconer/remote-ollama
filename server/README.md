# self-sovereign-ollama ai-server

Ollama server configuration for secure remote access from Apple Silicon Macs with high unified memory.

## Overview

The self-sovereign-ollama ai-server configures Ollama to provide secure, remote LLM inference with:
- **Two-layer security**: Network Perimeter (OpenWrt router + WireGuard VPN + DMZ isolation + Firewall) + AI Server (Ollama on DMZ)
- **Dual API support**: OpenAI-compatible `/v1/*` and Anthropic-compatible `/v1/messages` endpoints
- Supports both Aider (OpenAI API) and Claude Code (Anthropic API)
- OpenWrt router provides VPN authentication, DMZ network segmentation, and port-level firewall rules
- Runs exclusively on a dedicated, always-on Mac in DMZ network
- Zero public internet exposure
- Self-sovereign infrastructure (no third-party VPN services)

## Quick Reference

| Operation | Command | Description |
|-----------|---------|-------------|
| **Check status** | `launchctl list \| grep com.ollama` | Check if Ollama service is loaded |
| | `curl -sf http://192.168.100.10:11434/v1/models` | Test API endpoint availability from VPN |
| **Start service** | `launchctl kickstart gui/$(id -u)/com.ollama` | Start Ollama if stopped |
| **Stop service** | `launchctl stop gui/$(id -u)/com.ollama` | Stop Ollama temporarily |
| **Restart service** | `launchctl kickstart -k gui/$(id -u)/com.ollama` | Kill and restart Ollama immediately |
| **View logs** | `tail -f /tmp/ollama.stdout.log` | Monitor Ollama standard output logs |
| | `tail -f /tmp/ollama.stderr.log` | Monitor Ollama error logs |
| **Check models** | `ollama list` | List all pulled models |
| **Warm models** | `./scripts/warm-models.sh <model-name>` | Pre-load models into memory for faster response |
| **Run tests** | `./scripts/test.sh` | Run comprehensive test suite (36 tests) |
| | `./scripts/test.sh --skip-anthropic-tests` | Skip Anthropic API tests (for Ollama < 0.5.0) |
| | `./scripts/test.sh --skip-model-tests` | Run tests without model inference |
| **Router config** | See [ROUTER_SETUP.md](ROUTER_SETUP.md) | OpenWrt + WireGuard VPN configuration guide |
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
Client → WireGuard VPN (Router) → Firewall (port 11434) → Ollama (DMZ: 192.168.100.10:11434)
```

**Network segmentation:**
- **VPN subnet**: 10.10.10.0/24 (WireGuard clients)
- **DMZ subnet**: 192.168.100.0/24 (Ollama server isolated from LAN)
- **LAN subnet**: 192.168.1.0/24 (Admin access only, no VPN/DMZ access)

**Key principles:**
- **Two-layer security**: Network Perimeter (Router + VPN + DMZ + Firewall) → AI Server (Ollama)
- Built on Ollama's native dual API capabilities (OpenAI + Anthropic)
- Self-sovereign infrastructure (OpenWrt router + WireGuard VPN)
- Native macOS service management via launchd
- Router firewall provides port-level access control (VPN → DMZ port 11434 only)
- DMZ isolation (server separated from LAN)
- Access restricted to authorized VPN peers (WireGuard public key authentication)

## API

The server exposes dual API surfaces directly via Ollama at:
```
http://192.168.100.10:11434
```

All Ollama endpoints are accessible to authorized VPN clients. Access control provided by router firewall (VPN authentication + port 11434 only).

### OpenAI-Compatible API

For Aider and OpenAI-compatible tools:

**Available endpoints:**
- `/v1/chat/completions` - Streaming, JSON mode, tool calling
- `/v1/models` - List available models
- `/v1/models/{model}` - Get model details
- `/v1/responses` - Experimental non-stateful endpoint (Ollama 0.5.0+)

### Anthropic-Compatible API

For Claude Code and Anthropic-compatible tools:

**Available endpoint:**
- `/v1/messages` - Anthropic Messages API compatibility (Ollama 0.5.0+)

**Supported**:
- Messages, streaming, system prompts, multi-turn conversations
- Vision (base64 images), tool use, thinking blocks

**Limitations**:
- No `tool_choice` parameter
- No prompt caching (major performance impact)
- No PDF support, no URL-based images

See [specs/ANTHROPIC_COMPATIBILITY.md](specs/ANTHROPIC_COMPATIBILITY.md) for complete specification.

### Ollama Native API

All native Ollama endpoints accessible to VPN clients:
- `GET /api/version` - Ollama version info
- `GET /api/tags` - List models
- `POST /api/show` - Model details
- `POST /api/pull`, `/api/delete`, `/api/create`, `/api/push`, `/api/copy` - Model management

**Note**: v2 architecture trusts authorized VPN clients. If model management restriction needed, add reverse proxy (see [specs/HARDENING_OPTIONS.md](specs/HARDENING_OPTIONS.md)).

### API Contract

Full API contract documented in [../client/specs/API_CONTRACT.md](../client/specs/API_CONTRACT.md).

## Setup

See [SETUP.md](SETUP.md) for server installation instructions and [ROUTER_SETUP.md](ROUTER_SETUP.md) for router configuration.

Quick summary:
1. Configure OpenWrt router with WireGuard VPN server and DMZ network segmentation (see [ROUTER_SETUP.md](ROUTER_SETUP.md))
2. Install Ollama on Mac server
3. Configure Ollama to bind to DMZ interface (192.168.100.10) via launchd
4. Configure server with static IP on DMZ network
5. Add VPN client public keys to router WireGuard configuration
6. Pull desired models via Ollama CLI
7. Verify connectivity from VPN client (test firewall rules and DMZ isolation)

## Operations

Once installed, Ollama service runs as a LaunchAgent and starts automatically at login.

### Check Status
```bash
# Check if Ollama service is running
launchctl list | grep com.ollama

# Test API endpoint (from server locally on DMZ interface)
curl -sf http://192.168.100.10:11434/v1/models

# Test from VPN client (requires VPN connection)
curl -sf http://192.168.100.10:11434/v1/models
```

### Start Service
```bash
# Start Ollama (if stopped)
launchctl kickstart gui/$(id -u)/com.ollama
```

### Stop Service
```bash
# Stop Ollama temporarily
launchctl stop gui/$(id -u)/com.ollama
```

### Restart Service
```bash
# Restart Ollama (kill and restart immediately)
launchctl kickstart -k gui/$(id -u)/com.ollama
```

### Disable Service (Prevent Auto-Start)
```bash
# Unload Ollama completely
launchctl bootout gui/$(id -u)/com.ollama
```

### Re-enable Service
```bash
# Load Ollama again
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ollama.plist
```

### View Logs
```bash
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
# Run all tests (36 tests: service status, OpenAI API, Anthropic API, security, network configuration)
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
- **Service Status** (3 tests): Ollama LaunchAgent loaded, process running, port listening, HTTP response
- **OpenAI API** (7 tests): All OpenAI-compatible endpoints (`/v1/models`, `/v1/models/{model}`, `/v1/chat/completions`, `/v1/responses`), streaming, error handling
- **Anthropic API** (5 tests): `/v1/messages` endpoint (non-streaming, streaming, system prompts, error handling)
- **Security** (4 tests): Process owners, log files, plist configuration, OLLAMA_HOST verification
- **Network Configuration** (6 tests): DMZ interface binding (192.168.100.10), localhost unreachable (DMZ-only), static IP configuration
- **Router Integration** (Manual checklist): VPN connectivity, firewall rules, DMZ isolation (requires SSH access to router)

**Total**: 36 tests (automated) + manual router integration checklist

### Sample Output

```
self-sovereign-ollama ai-server Test Suite
Running 36 tests

=== Service Status Tests ===
✓ PASS Ollama LaunchAgent is loaded: com.ollama
✓ PASS Ollama process is running (PID: 19272, user: vm)
✓ PASS Ollama is listening on port 11434

=== Network Configuration Tests ===
✓ PASS Ollama is bound to DMZ interface (192.168.100.10)
✓ PASS Ollama is unreachable from localhost (DMZ-only)
✓ PASS Static IP configured on DMZ network

=== OpenAI API Endpoint Tests ===
✓ PASS GET /v1/models returns valid JSON (1 models)
✓ PASS GET /v1/models/{model} returns valid model details
✓ PASS POST /v1/chat/completions (non-streaming) succeeded
✓ PASS POST /v1/chat/completions (streaming) returns SSE chunks

=== Anthropic API Tests ===
✓ PASS POST /v1/messages (non-streaming) succeeded
✓ PASS POST /v1/messages (streaming) returns SSE chunks
✓ PASS POST /v1/messages with system prompt succeeded
✓ PASS POST /v1/messages error handling works (400/404/500)
✓ PASS POST /v1/messages multi-turn conversation succeeded
✓ PASS POST /v1/messages streaming includes usage metrics

...

Test Summary
───────────────────────────────
Passed:  36
Failed:  0
Skipped: 0
Total:   36
═══════════════════════════════

✓ All tests passed!

=== Manual Router Integration Checklist ===
(Requires SSH access to router - see ROUTER_SETUP.md)
```

All 36 automated tests pass (service status, APIs, security, network configuration).

## Security

See [specs/SECURITY.md](specs/SECURITY.md) for the complete security model.

**Two-layer defense in depth:**
1. **Network Perimeter** (Router + VPN + DMZ + Firewall) - Controls WHO can reach the server and WHAT ports are accessible
2. **AI Server** (Ollama on DMZ) - Provides inference services

**Properties:**
- No public internet exposure (VPN-only access)
- Self-sovereign infrastructure (no third-party VPN services)
- DMZ isolation (server separated from LAN)
- Per-peer VPN authentication (WireGuard public key cryptography)
- Port-level firewall (only port 11434 accessible from VPN)
- Direct Ollama API exposure (all endpoints accessible to authorized VPN clients)

## Documentation

- [SETUP.md](SETUP.md) – Server setup instructions
- [ROUTER_SETUP.md](ROUTER_SETUP.md) – OpenWrt router + WireGuard VPN configuration guide
- [specs/ARCHITECTURE.md](specs/ARCHITECTURE.md) – Architecture and principles
- [specs/FUNCTIONALITIES.md](specs/FUNCTIONALITIES.md) – Detailed functionality specifications
- [specs/SECURITY.md](specs/SECURITY.md) – Security model and two-layer architecture
- [specs/INTERFACES.md](specs/INTERFACES.md) – External interfaces
- [specs/FILES.md](specs/FILES.md) – Repository layout
- [specs/HARDENING_OPTIONS.md](specs/HARDENING_OPTIONS.md) – Router-based security expansion options

## Out of Scope

- Built-in authentication proxy / API keys
- Web-based chat UI
- Automatic model quantization
- Load balancing across multiple nodes
- Monitoring / metrics endpoint
