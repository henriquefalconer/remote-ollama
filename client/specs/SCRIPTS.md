# self-sovereign-ollama ai-client Scripts (v2.0.0)

## scripts/install.sh

### Functionality
- Validates macOS 14+ (Sonoma or later)
- Checks / installs Homebrew, Python 3.10+, WireGuard
- Installs WireGuard via Homebrew (`brew install wireguard-tools`)
- Generates WireGuard keypair for this client
  - Private key stored securely in `~/.ai-client/wireguard/privatekey`
  - Public key stored in `~/.ai-client/wireguard/publickey`
  - Displays public key for user to send to router admin
- Prompts for server IP (default: 192.168.100.10)
- Prompts for VPN server public key (provided by router admin)
- Prompts for VPN server endpoint (public IP:port, e.g., `1.2.3.4:51820`)
- Generates WireGuard configuration file
- Provides instructions for importing config into WireGuard app or `wg-quick`
- Creates `~/.ai-client/` directory
- Generates `~/.ai-client/env` with exact variables from API_CONTRACT.md
- Prompts for user consent before modifying shell profile
- Appends `source ~/.ai-client/env` to `~/.zshrc` or `~/.bashrc` with marker comments
- Installs pipx if needed, runs `pipx ensurepath`
- Installs Aider via pipx (isolated, no global pollution)
- Copies uninstall.sh to `~/.ai-client/` for curl-pipe users
- Runs connectivity test **after user confirms VPN is connected** (warns but does not abort if server unreachable)

### UX Requirements
- **Homebrew noise suppression** - Set HOMEBREW_NO_ENV_HINTS and HOMEBREW_NO_INSTALL_CLEANUP
- **Color-coded output** - Use echo -e with GREEN/YELLOW/RED/BLUE for messages
- **Clear sections** - Use boxed or visually separated sections for major steps
- **Progress tracking** - Show what's being installed/configured at each step
- **Interactive consent** - Always ask before modifying shell profile
- **Dual-mode support** - Work both as local clone and curl-pipe installation:
  - Embed env.template content as heredoc fallback
  - Copy uninstall.sh to `~/.ai-client/` for later access
- **WireGuard setup guidance**:
  - Display generated public key prominently with instructions to send to router admin
  - Wait for user to confirm they've been added as VPN peer before proceeding
  - Provide clear instructions for importing WireGuard config
  - Note that VPN must be connected to use Aider/Claude Code with local backend
- **Connectivity test** - Test server connection **after user confirms VPN connected**, but only warn (don't fail) if unreachable
- **Final summary** - Show what was installed and next steps:
  - Display WireGuard public key again
  - Remind user to send public key to router admin if not done yet
  - Remind to connect VPN before using Aider
  - Remind to open new terminal or run `exec $SHELL`
  - Show example Aider command (after connecting VPN)
  - Display troubleshooting resources
- **Idempotent** - Safe to re-run without breaking existing setup

## scripts/uninstall.sh

### Functionality
- Removes Aider via `pipx uninstall aider-chat`
- Removes marker-delimited block from shell profile (`~/.zshrc` and `~/.bashrc`)
- Deletes `~/.ai-client/` directory (includes env file, WireGuard keys, copied uninstall script)
- **WireGuard cleanup**:
  - Removes WireGuard configuration files
  - Optionally removes WireGuard app/tools (prompts user)
  - Displays reminder to have router admin remove client's public key from VPN peers
- Leaves Homebrew and pipx untouched (user may need them for other tools)
- Handles edge cases gracefully (Aider not installed, directory missing, profile not modified)

### UX Requirements
- **Clear banner** - Display script name and purpose at start
- **Color-coded output** - Use echo -e with GREEN/YELLOW/RED for messages
- **Progress tracking** - Show what's being removed at each step
- **Final summary** - Display boxed or clearly separated summary showing:
  - What was successfully removed
  - What was left intact (WireGuard app, Homebrew, pipx)
  - **Important reminder**: "Ask router admin to remove your VPN peer (public key: ...)"
  - Reminder to close/reopen terminal for changes to take effect
- **Graceful degradation** - Continue with remaining cleanup even if some steps fail
- **Idempotent** - Safe to re-run on already-cleaned system (no errors on missing components)

## scripts/test.sh

Comprehensive test script that validates all client functionality. Designed to run on the client machine after installation.

### Environment Configuration Tests
- Verify `~/.ai-client/env` file exists
- Verify all required environment variables are set:
  - `OLLAMA_API_BASE` (should be `http://<hostname>:11434` — no `/v1` suffix)
  - `OPENAI_API_BASE` (should be `http://<hostname>:11434/v1` — with `/v1` suffix)
  - `OPENAI_API_KEY` (should be `ollama`)
  - `AIDER_MODEL` (optional, check if set)
- Verify shell profile sources the env file (check `~/.zshrc` or `~/.bashrc` for marker comments)
- Verify environment variables are exported (available to child processes)

### Dependency Tests
- Verify WireGuard is installed (`which wg` or `brew list wireguard-tools`)
- Verify Homebrew is installed
- Verify Python 3.10+ is available
- Verify pipx is installed
- Verify Aider is installed via pipx (`aider --version`)

### Connectivity Tests
- **VPN Connection Check** - Verify WireGuard VPN is active before testing server connectivity
  - Check for active WireGuard interface (e.g., `utun` device on macOS)
  - Verify VPN tunnel shows connected status
  - Warn if VPN not connected (skip server tests, show connection instructions)
- Test network connectivity to server IP (192.168.100.10)
- `GET /v1/models` returns JSON model list from server
- `GET /v1/models/{model}` returns model details (if models available)
- `POST /v1/chat/completions` non-streaming request succeeds
- `POST /v1/chat/completions` streaming request returns SSE chunks
- Test error handling when server unreachable (graceful failure messages)

### API Contract Validation Tests
- Verify base URL format matches contract
- Verify all endpoints return expected HTTP status codes
- Verify response structure matches OpenAI API schema
- Test JSON mode response format
- Test streaming with `stream_options.include_usage`

### Aider Integration Tests
- Verify Aider can be invoked (`which aider`)
- Verify Aider binary is in PATH
- Test Aider reads environment variables correctly (dry-run mode if available)
- Note: Full Aider conversation test requires user interaction

### Claude Code Integration Tests (v2+, Optional)

These tests validate the optional Claude Code + Ollama integration. All tests in this category should be skippable if Claude Code is not installed or if the user has not opted into the integration.

- Verify Claude Code binary is installed (`which claude`)
- Verify Claude Code binary is in PATH
- Verify `claude-ollama` alias exists in shell profile (check between `# >>> claude-ollama >>>` and `# <<< claude-ollama <<<` markers)
- Verify alias has correct environment variables (`ANTHROPIC_AUTH_TOKEN=ollama`, `ANTHROPIC_API_KEY=""`, `ANTHROPIC_BASE_URL=http://<hostname>:11434`)
- Test `POST /v1/messages` endpoint connectivity (non-streaming)
  - Verify response has required Anthropic API fields: `id`, `type: "message"`, `role: "assistant"`, `content` array, `stop_reason`, `usage`
- Test `POST /v1/messages` streaming connectivity
  - Verify SSE event types are correct: `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`
- Note: Full Claude Code integration test requires actual claude invocation (deferred to user acceptance)

**Flag Support**: `--skip-claude` flag to skip all Claude Code tests

### Version Management Tests (v2+, Optional)

These tests validate the version management scripts. Tests should be skippable if scripts are not present (v2+ not yet installed).

- Verify `check-compatibility.sh` exists in `client/scripts/`
- Verify `check-compatibility.sh` has valid bash syntax (`bash -n check-compatibility.sh`)
- Verify `check-compatibility.sh` is executable
- Verify `pin-versions.sh` exists in `client/scripts/`
- Verify `pin-versions.sh` has valid bash syntax
- Verify `pin-versions.sh` is executable
- Verify `downgrade-claude.sh` exists in `client/scripts/`
- Verify `downgrade-claude.sh` has valid bash syntax
- Verify `downgrade-claude.sh` is executable
- If `~/.ai-client/.version-lock` exists, verify format:
  - File is readable
  - Contains `CLAUDE_CODE_VERSION=X.Y.Z`
  - Contains `OLLAMA_VERSION=X.Y.Z`
  - Contains `TESTED_DATE=YYYY-MM-DD`
  - Contains `STATUS=working` (or other valid status)

**Flag Support**: Version management tests auto-skip if scripts don't exist

**Note**: Full specification of check-compatibility.sh, pin-versions.sh, and downgrade-claude.sh can be found in `client/specs/VERSION_MANAGEMENT.md`.

### Script Behavior Tests
- Verify install.sh idempotency (safe to re-run)
- Verify uninstall.sh availability (local clone or `~/.ai-client/uninstall.sh`)
- Test uninstall.sh on clean system (should not error)

### Output Format
- **Per-test results** - Clear pass/fail/skip for each test with brief description
- **Summary statistics** - Final count (X passed, Y failed, Z skipped)
- **Exit codes** - 0 if all tests pass, non-zero otherwise
- **Verbose mode** - `--verbose` or `-v` flag for detailed output (request/response bodies)
- **Colorized output** - Use echo -e with color codes:
  - GREEN for passed tests
  - RED for failed tests
  - YELLOW for skipped tests
- **Progress indication** - Show test number / total (e.g., "Running test 12/27...")
- **Grouped results** - Organize output by test category (Environment, Dependencies, Connectivity, etc.)

### UX Requirements
- **Clear banner** - Display script name, purpose, and test count at start
- **Real-time feedback** - Show results as tests run (don't wait until end)
- **Minimal noise** - Suppress verbose curl output unless --verbose flag used
- **Helpful failures** - When test fails, show:
  - What was expected
  - What was received
  - Suggested troubleshooting steps (e.g., "Run install.sh to configure", "Check VPN connection", "Verify router firewall rules")
- **Skip guidance** - If tests are skipped, explain why and how to enable them
- **Final summary box** - Visually separated summary section with:
  - Overall pass/fail status
  - Statistics
  - Next steps if failures occurred (e.g., "Run install.sh", "Connect VPN", "Check server status", "Verify router firewall rules")

### Test Modes
- `--skip-server` - Skip connectivity tests (for offline testing)
- `--skip-aider` - Skip Aider-specific tests (v1)
- `--skip-claude` - Skip Claude Code integration tests (v2+)
- `--quick` - Run only critical tests (env vars, dependencies, basic connectivity)
- `--v1-only` - Run only v1/Aider tests (equivalent to `--skip-claude`)
- `--v2-only` - Run only v2+/Claude Code tests (equivalent to `--skip-aider`)

## config/env.template

- Template showing the exact variables required by the contract
- Used by install.sh to create `~/.ai-client/env`

## Root-Level Analytics Scripts (v2+)

These scripts are located in the root directory and provide performance analytics for Claude Code + Ollama integration.

### loop.sh

**Purpose**: Execute Claude Code continuously until completion or user intervention

**Functionality**:
- Runs `claude code continue` in a loop until `.agent_complete` marker file appears
- Allows manual breaking with Ctrl+C
- Useful for unattended execution of complex workflows

**Usage**:
```bash
./loop.sh
```

**Exit conditions**:
- File `.agent_complete` exists in project root (agent signals completion)
- User presses Ctrl+C

### loop-with-analytics.sh

**Purpose**: Execute Claude Code with comprehensive performance measurement

**Functionality**:
- Wraps `claude code continue` with analytics collection
- Captures Claude Code JSON logs from `~/.claude/`
- Extracts performance metrics: tool usage, token usage, cache efficiency, subagent spawns
- Generates structured JSON report: `analytics-YYYYMMDD-HHMMSS.json`
- Runs until `.agent_complete` marker file appears or user interrupts
- Compatible with custom instructions (reads from CLAUDE.md if present)

**Usage**:
```bash
./loop-with-analytics.sh
```

**Output**:
- Real-time progress display during execution
- JSON file: `analytics-YYYYMMDD-HHMMSS.json` with metrics:
  - `tool_usage`: Count of each tool invocation (Read, Bash, Edit, Write, Grep, Glob, Task)
  - `token_usage`: Input tokens, cache creation/reads, output tokens
  - `cache_efficiency`: Cache hit rate percentage
  - `subagent_spawns`: Count of Task tool invocations
  - `timestamp`, `duration_seconds`, `backend` (ollama/anthropic)

**Exit conditions**:
- File `.agent_complete` exists in project root
- User presses Ctrl+C

### compare-analytics.sh

**Purpose**: Compare performance between Anthropic cloud and Ollama backends

**Functionality**:
- Loads two analytics JSON files (typically one from each backend)
- Calculates comparative metrics:
  - Tool usage differences (absolute and percentage)
  - Token usage differences (input, cache, output)
  - Cache efficiency comparison
  - Subagent spawn comparison
  - Total cost estimation (Anthropic cloud pricing)
- Displays side-by-side comparison table
- Highlights significant differences (>10% variance)

**Usage**:
```bash
./compare-analytics.sh analytics-file1.json analytics-file2.json
```

**Example**:
```bash
# Compare Anthropic cloud run vs Ollama run
./compare-analytics.sh analytics-20260211-142030.json analytics-20260211-151545.json
```

**Output**:
- Human-readable comparison table
- Color-coded differences (green=better, red=worse, yellow=neutral)
- Recommendations based on variance

**Requirements**:
- Two analytics JSON files generated by `loop-with-analytics.sh`
- `jq` installed for JSON parsing (automatically checked)

**Documentation**: See `ANALYTICS_README.md` for complete analytics workflow and interpretation guide
