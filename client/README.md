# self-sovereign-ollama ai-client

macOS client setup for connecting to remote Ollama, supporting Aider (v1) and Claude Code (v2+).

## Current Status

**✅ v1**: Aider integration with OpenAI-compatible API
**✅ v2+**: Claude Code integration, analytics, version management

All features are fully implemented and tested (40 tests passing).

## Overview

The self-sovereign-ollama ai-client is a one-time installer that configures your macOS environment to use remote Ollama via OpenAI and Anthropic-compatible APIs.

**Available features**:
- **Aider** (and other OpenAI-compatible tools) connect to remote Ollama automatically (v1)
- **Claude Code** integration with optional remote Ollama backend (v2+)
- **Performance analytics** tools for measuring tool usage (v2+)
- **Version compatibility management** for Claude Code + Ollama (v2+)
- Zero manual configuration per session
- All API calls go through secure WireGuard VPN

## What the Client Does

1. Installs and configures WireGuard VPN client
2. Generates WireGuard keypair (sends public key to router admin)
3. Creates environment variables pointing to remote Ollama server
4. Installs Aider with automatic Ollama connection (v1)
5. Optionally configures Claude Code with remote Ollama backend (v2+)
6. Provides analytics and version management tools (v2+)
7. Provides clean uninstallation

## Quick Reference

### Aider Commands

| Operation | Command | Description |
|-----------|---------|-------------|
| **Start Aider** | `aider` | Launch Aider in interactive mode |
| | `aider --yes` | Launch Aider in YOLO mode (auto-accept changes) |

### Configuration

| Operation | Command | Description |
|-----------|---------|-------------|
| **Check config** | `echo $OPENAI_API_BASE` | Display OpenAI API base URL (for Aider) |
| | `cat ~/.ai-client/env` | View all environment variables |
| **Test connectivity** | `curl $OPENAI_API_BASE/models` | Test OpenAI API connection |
| | Check WireGuard status | Verify VPN tunnel is active (method depends on WireGuard client) |

### Testing

| Operation | Command | Description |
|-----------|---------|-------------|
| **Run tests** | `./client/scripts/test.sh` | Run comprehensive test suite (40 tests) |
| | `./client/scripts/test.sh --skip-server` | Run tests without server connectivity checks |
| | `./client/scripts/test.sh --quick` | Run quick tests (skip model inference) |

### Shell Management

| Operation | Command | Description |
|-----------|---------|-------------|
| **Reload environment** | `source ~/.ai-client/env` | Reload environment variables in current shell |
| | `exec $SHELL` | Restart shell to apply environment changes |

### Uninstall

| Operation | Command | Description |
|-----------|---------|-------------|
| **Uninstall** | `./client/scripts/uninstall.sh` | Remove client configuration and Aider |
| | `~/.ai-client/uninstall.sh` | Uninstall if installed via curl-pipe |

---

## v2+ Features (Fully Implemented)

### Claude Code Integration

**Purpose**: Optional integration allowing Claude Code to use remote Ollama backend as an alternative to Anthropic cloud API.

**Capabilities**:
- Shell alias (`claude-ollama`) for easy backend switching
- Opt-in during installation (user consent required)
- Support for both Anthropic cloud (default) and remote Ollama backend
- Backend selection based on use case (cloud for complex tasks, Ollama for privacy-critical work)

**Why this matters**: Some users may prefer running inference on their private VPN network for sensitive code. However, Anthropic cloud API remains the default and recommended option due to superior quality and performance (prompt caching support).

### Performance Analytics

**Purpose**: Measure actual Claude Code tool usage and performance to make data-driven decisions about backend suitability.

**Tools**:
- `loop-with-analytics.sh` - Enhanced execution with performance measurement
- `compare-analytics.sh` - Compare performance between different backends

**Metrics measured**:
- Tool usage counts (Read, Bash, Edit, Write, Grep, Glob, Task spawns)
- Token usage (input, cache creation/reads, output)
- Cache efficiency (hit rate percentage)
- Workload classification (shallow vs deep operations)

**Why this matters**: Empirical data to validate whether remote Ollama is suitable for specific workflows, or if Anthropic cloud API's prompt caching provides essential performance benefits.

See [ANALYTICS_README.md](../ANALYTICS_README.md) for detailed analytics documentation.

### Version Management

**Purpose**: Prevent breaking changes from Claude Code or Ollama updates.

**Tools**:
- `check-compatibility.sh` - Verify Claude Code and Ollama versions are tested together
- `pin-versions.sh` - Lock tools to known-working versions
- `downgrade-claude.sh` - Rollback Claude Code if update breaks

**Why this matters**: Ollama's Anthropic API compatibility is experimental. Claude Code updates may require features Ollama doesn't support yet. Version management prevents downtime from breaking changes.

---

## Requirements

- macOS 14 Sonoma or later
- Homebrew
- Python 3.10+
- WireGuard client (installed via Homebrew)
- Access to a self-sovereign-ollama ai-server (public key must be added to router's VPN configuration)

## Installation

See [SETUP.md](SETUP.md) for complete setup instructions.

Quick start:
```bash
./scripts/install.sh
```

## API Contract

The client relies on the exact API contract documented in [specs/API_CONTRACT.md](specs/API_CONTRACT.md).

The remote Ollama server provides:
- OpenAI-compatible `/v1` endpoints (native Ollama feature)
- Anthropic-compatible `/v1/messages` endpoint (Ollama 0.5.0+)
- Static IP access via VPN (192.168.100.10:11434)
- Support for streaming, JSON mode, tool calling
- No authentication required (VPN authentication provides security)

## Usage

The client has **no persistent daemon or background service**. It only configures environment variables that tools use to connect to remote Ollama.

### Running Aider

After installation, simply run:
```bash
aider                     # interactive mode
aider --yes               # YOLO mode
```

Aider automatically reads the environment variables and connects to remote Ollama.

### Using Other Tools

Any tool that supports custom OpenAI base URLs will work automatically:
```bash
# Environment variables are already set
echo $OPENAI_API_BASE    # http://192.168.100.10:11434/v1
echo $OPENAI_API_KEY     # ollama
```

### No Service Management Required

Unlike the Ollama server, the client requires no start/stop/restart commands. Simply invoke tools when needed.

## Testing & Verification

### Running the Test Suite

The client includes a comprehensive automated test suite that verifies installation and connectivity:

```bash
# Run all tests (40 tests covering environment, dependencies, connectivity, API contract, Aider, Claude Code, analytics, and version management)
./scripts/test.sh

# Run tests without server connectivity checks (useful during initial setup)
./scripts/test.sh --skip-server

# Run only critical tests (skip API contract validation and Aider integration)
./scripts/test.sh --quick

# Run with verbose output (shows full API request/response details and timing)
./scripts/test.sh --verbose
```

### Test Coverage

The test suite validates:
- **Environment Configuration** (7 tests): env file exists, all 4 variables set correctly, shell profile sourcing, variables exported
- **Dependencies** (6 tests): WireGuard installed, Homebrew installed, Python 3.10+, pipx installed, Aider installed
- **Connectivity** (6 tests): VPN connection active, server reachable, all API endpoints responding, error handling
- **API Contract** (5 tests): Base URL formats, HTTP status codes, response schemas, streaming with usage data
- **Aider Integration** (3 tests): Binary in PATH, environment variables configured
- **Script Behavior** (3 tests): Uninstall script available, valid syntax, install idempotency

### Sample Output

```
self-sovereign-ollama ai-client Test Suite
Running 40 tests

=== Environment Configuration Tests ===
✓ PASS Environment file exists (~/.ai-client/env)
✓ PASS OLLAMA_API_BASE is set: http://192.168.100.10:11434
✓ PASS OPENAI_API_BASE is set: http://192.168.100.10:11434/v1
✓ PASS OPENAI_API_KEY is set correctly: ollama
• SKIP AIDER_MODEL is not set (optional)
✓ PASS Shell profile sources env file (/Users/vm/.zshrc)
✓ PASS Environment variables are exported in env file

=== Dependency Tests ===
✓ PASS WireGuard is installed
✓ PASS Homebrew is installed
✓ PASS Python 3.14 found (>= 3.10)
✓ PASS pipx is installed
✓ PASS Aider is installed: aider 0.86.1

=== Connectivity Tests ===
✓ PASS VPN connection is active
✓ PASS Server is reachable (192.168.100.10)
✓ PASS GET /v1/models returns valid JSON (1 models)

...

Test Summary
───────────────────────────────
Passed:  40
Failed:  0
Skipped: 0
Total:   40
═══════════════════════════════

✓ All tests passed!
```

All 40 tests pass (environment, dependencies, connectivity, API contract, Aider, Claude Code, analytics, version management).

## Uninstallation

```bash
./scripts/uninstall.sh
```

This removes:
- Aider installation
- Environment variable configuration
- Shell profile modifications
- WireGuard configuration files
- Client keypair (public/private keys)

**Important**: Ask router admin to remove your VPN peer (public key) from the router configuration.

WireGuard client (Homebrew package) and Homebrew are left untouched.

## Documentation

- [SETUP.md](SETUP.md) – Complete setup instructions
- [specs/API_CONTRACT.md](specs/API_CONTRACT.md) – Exact server API interface
- [specs/ARCHITECTURE.md](specs/ARCHITECTURE.md) – Client architecture
- [specs/FUNCTIONALITIES.md](specs/FUNCTIONALITIES.md) – Client functionalities
- [specs/REQUIREMENTS.md](specs/REQUIREMENTS.md) – System requirements
- [specs/SCRIPTS.md](specs/SCRIPTS.md) – Script documentation
- [specs/FILES.md](specs/FILES.md) – Repository layout

## Out of Scope

- Direct HTTP API calls (use Aider or other tools)
- Linux/Windows support
- IDE plugins
- Custom authentication
