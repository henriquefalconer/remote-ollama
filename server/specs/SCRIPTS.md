# self-sovereign-ollama ai-server Scripts (v2.0.0)

## scripts/install.sh

### System Validation
- Validates macOS 14+ (Sonoma) and Apple Silicon hardware requirements
- Checks / installs Homebrew

### Homebrew Configuration
- Suppresses Homebrew noise: `HOMEBREW_NO_ENV_HINTS=1`, `HOMEBREW_NO_INSTALL_CLEANUP=1`
- Redirects verbose installation output to `/tmp/*.log` files for cleaner UX

### Network Configuration Check
- Prompts user to configure router first if not already done
- Displays message:
  ```
  ═══════════════════════════════════════════════════════
  Router Configuration Required
  ═══════════════════════════════════════════════════════

  Before installing the AI server, you must configure your
  OpenWrt router with WireGuard VPN and DMZ network.

  Follow the complete guide:
    server/ROUTER_SETUP.md

  Have you completed router setup? (y/N)
  ```
- If user answers No, exits with instructions
- If user answers Yes, continues

### DMZ Network Configuration
- Prompts for DMZ subnet (default: `192.168.100.0/24`)
- Prompts for server static IP (default: `192.168.100.10`)
- Validates IP format and subnet membership
- Displays network configuration summary for user confirmation

### Static IP Configuration
- Configures macOS to use static IP on appropriate network interface
- Determines network interface connected to DMZ network:
  - Lists available interfaces: `networksetup -listallhardwareports`
  - User selects interface or script detects automatically
- Sets static IP configuration:
  ```bash
  sudo networksetup -setmanual "Ethernet" \
    192.168.100.10 \
    255.255.255.0 \
    192.168.100.1
  ```
- Configures DNS servers (router as primary, public DNS as backup)
- Verifies connectivity to router: `ping -c 3 192.168.100.1`

### Ollama Installation & Configuration
- Checks / installs Ollama via Homebrew (output redirected to log)
- Stops any existing Ollama service (brew services or launchd) to avoid conflicts
- Creates `~/Library/LaunchAgents/com.ollama.plist` to run Ollama as user-level service
  - Sets `OLLAMA_HOST=192.168.100.10` to bind DMZ interface only (configurable)
    - Alternative: `OLLAMA_HOST=0.0.0.0` if user prefers to bind all interfaces
  - Configures `KeepAlive=true` and `RunAtLoad=true` for automatic startup
  - Logs to `/tmp/ollama.stdout.log` and `/tmp/ollama.stderr.log`
- Loads the plist via `launchctl bootstrap` (modern API)
- Verifies Ollama is listening on port 11434 (retry loop with timeout)
- Verifies binding to correct interface: `lsof -i :11434` (should show DMZ IP)
- Verifies process is running as user (not root)
- Runs self-test: `curl -sf http://192.168.100.10:11434/v1/models`

### Router Connectivity Verification
- Tests connectivity to router:
  ```bash
  ping -c 3 192.168.100.1  # Router gateway
  ```
- Tests DNS resolution (if configured)
- Displays warning if router unreachable
- Continues installation but alerts user to verify router setup

### Model Pre-pull (Optional)
- Prompts user: "Pre-pull models now? (y/N)"
- If yes:
  - Shows popular model examples (qwen2.5-coder:32b, deepseek-r1:70b, llama3.2)
  - Prompts for model list (space-separated)
  - Runs `ollama pull <model>` for each
  - Displays progress and final status

### Final Summary
- Visual hierarchy with boxed "Installation Complete" message
- Shows service status:
  - Ollama running on DMZ interface (192.168.100.10:11434)
  - Static IP configured
  - Auto-start enabled
  - Router connectivity: OK/WARNING
- **What's Next** section with numbered steps:
  1. Verify router WireGuard VPN is configured (see ROUTER_SETUP.md)
  2. Add VPN client peers to router (client installation will generate keys)
  3. Install client on laptop/desktop (provides curl-pipe command)
  4. Test connection from VPN client
- **Security Notes**:
  - Port 11434 is NOT publicly exposed (firewall protects it)
  - Only WireGuard VPN clients can reach server
  - DMZ isolation prevents server from accessing LAN
- Troubleshooting commands section:
  - Restart Ollama
  - View logs
  - Check network binding
  - Verify router connectivity

### Design Principles
- Idempotent: safe to re-run without breaking existing setup
- User-friendly: minimal noise, clear visual hierarchy, actionable instructions
- Interactive: user controls pacing (prompts for configuration)
- Informative: context-specific error messages and troubleshooting tips
- Complete: guides user through entire workflow including router setup reference
- References external documentation: points to ROUTER_SETUP.md for router configuration

## scripts/uninstall.sh

### Functionality
- Stops the Ollama LaunchAgent service via `launchctl bootout`
- Removes `~/Library/LaunchAgents/com.ollama.plist`
- Cleans up Ollama logs from `/tmp/` (`ollama.stdout.log`, `ollama.stderr.log`)
- **Network cleanup**:
  - Optionally revert static IP to DHCP
  - Prompts user: "Revert to DHCP? (y/N)"
  - If yes: `sudo networksetup -setdhcp "Ethernet"`
- Leaves Homebrew and Ollama binary untouched (user may want to keep them)
- Leaves downloaded models in `~/.ollama/models/` untouched (valuable data)
- **Does NOT touch router configuration** - router setup must be manually reverted if needed
- Handles edge cases gracefully (service not running, plist missing, partial installation)

### UX Requirements
- **Clear banner** - Display script name and purpose at start
- **Color-coded output** - Use echo -e with GREEN/YELLOW/RED for info/warn/error messages
- **Progress tracking** - Show what's being removed at each step
- **Final summary** - Display boxed or clearly separated summary section showing:
  - What was successfully removed (Ollama service, LaunchAgent)
  - What was left intact (Homebrew, Ollama binary, models, router config)
  - Any errors or warnings encountered
- **Router note** - Display reminder:
  ```
  Note: Router WireGuard configuration NOT removed.
  To fully uninstall:
  1. Remove this server's peer from router WireGuard config
  2. Remove DMZ firewall rules (optional)
  3. See ROUTER_SETUP.md for instructions
  ```
- **Graceful degradation** - Continue with remaining cleanup even if some steps fail
- **Idempotent** - Safe to re-run on already-cleaned system (no errors on missing files)

## scripts/warm-models.sh

### Functionality
- Accepts model names as command-line arguments (e.g., `qwen2.5-coder:32b deepseek-r1:70b`)
- Shows usage message if no models specified
- Verifies Ollama is running before proceeding (fail fast with clear error if not)
- For each model:
  - Pulls the model via `ollama pull <model>` (downloads if not present)
  - Sends lightweight `/v1/chat/completions` request to force-load into memory
    - Uses minimal prompt ("hi") with `max_tokens: 1`
- Continues on individual model failures (resilient)
- Includes comments documenting how to wire into launchd as post-boot warmup (optional)

### UX Requirements
- **Clear usage** - Show usage message with examples if invoked without arguments
- **Color-coded output** - Use echo -e with GREEN/YELLOW/RED for status messages
- **Progress per model** - Show clear status for each model:
  - "Pulling model..." (if download needed)
  - "Loading into memory..." (warm-up request)
  - "✓ Ready" (success) or "✗ Failed: <reason>" (error)
- **Progress indicators** - Show what's happening during long operations (pulling large models)
- **Final summary** - Display results at end:
  - Count of models successfully warmed
  - Count of models that failed (if any)
  - List of failed models with brief reason
- **Continue on failure** - Don't abort entire script if one model fails
- **Time estimates** - Optionally show estimated time remaining for large downloads

## scripts/test.sh

Comprehensive test script that validates all server functionality. Designed to run on the server machine after installation.

### Network Configuration Tests
- Verify static IP is configured correctly
- Check interface binding: `networksetup -getinfo "Ethernet"`
- Verify IP matches configured DMZ IP (e.g., 192.168.100.10)
- Test router connectivity: `ping -c 3 192.168.100.1`
- Test DNS resolution (if configured)
- Test outbound internet: `ping -c 3 8.8.8.8`
- Verify LAN isolation: `ping -c 1 192.168.1.x` (should fail or timeout)

### Service Status Tests
- Verify LaunchAgent is loaded (`launchctl list | grep com.ollama`)
- Verify Ollama process is running as user (not root)
- Verify Ollama is listening on port 11434
- Verify binding to correct interface: `lsof -i :11434` (should show DMZ IP or 0.0.0.0)
- Verify service responds to basic HTTP requests

### API Endpoint Tests (OpenAI-Compatible)
- `GET /v1/models` - returns JSON model list
- `GET /v1/models/{model}` - returns single model details (requires at least one pulled model)
- `POST /v1/chat/completions` - non-streaming request succeeds
- `POST /v1/chat/completions` - streaming (`stream: true`) returns SSE chunks
- `POST /v1/chat/completions` - with `stream_options.include_usage` returns usage data
- `POST /v1/chat/completions` - JSON mode (`response_format: {"type": "json_object"}`)
- `POST /v1/responses` - experimental endpoint (note if requires Ollama 0.5.0+)

### API Endpoint Tests (Anthropic-Compatible, v2+)

These tests validate the Anthropic Messages API endpoint (`/v1/messages`) introduced in Ollama 0.5.0+. If Ollama version is < 0.5.0, these tests should be skipped with appropriate messaging.

- `POST /v1/messages` - non-streaming request succeeds with text content
  - Verify response has required fields: `id`, `type: "message"`, `role: "assistant"`, `content` (array), `stop_reason`, `usage`
  - Verify `content[0].type: "text"` and `content[0].text` is a non-empty string
  - Verify `usage` has `input_tokens` and `output_tokens`
- `POST /v1/messages` - streaming request returns correct SSE event sequence
  - Verify event sequence: `message_start` → `content_block_start` → `content_block_delta` (multiple) → `content_block_stop` → `message_delta` → `message_stop`
  - Verify `message_start` event has `message` with `id`, `type`, `role`, `content` (empty array initially), `usage`
  - Verify `content_block_delta` events have `delta.text` with incremental text
  - Verify final `message_stop` event completes the stream
- `POST /v1/messages` - with system prompt
  - Verify system prompt is processed (request includes `system: "You are a helpful assistant"` or system array)
  - Verify response acknowledges or respects system instructions (implementation-dependent, may just verify 200 OK)
- `POST /v1/messages` - error case with nonexistent model
  - Verify appropriate error status (400, 404, or 500)
  - Verify error response has meaningful error message
- `POST /v1/messages` - tool use (optional/skippable, model-dependent)
  - If model supports tools, verify `tools` parameter is accepted
  - Verify `tool_use` content blocks are returned when appropriate
  - Mark as SKIP if model doesn't support tools
- `POST /v1/messages` - thinking blocks (optional/skippable, model-dependent)
  - If model supports thinking, verify `thinking` content blocks are returned
  - Mark as SKIP if model doesn't support thinking

**Flag Support**:
- Add `--skip-anthropic-tests` flag to skip all Anthropic API tests (for environments with Ollama < 0.5.0)
- If `--skip-anthropic-tests` is not provided but Ollama version < 0.5.0 is detected, auto-skip with message: "Anthropic API tests skipped (requires Ollama 0.5.0+, detected X.Y.Z)"

**Total Test Count**: Update `TOTAL_TESTS` variable to include these new tests (current: 20, add ~5-6 non-optional Anthropic tests = ~25-26 total)

### Error Behavior Tests
- 500 error on inference with nonexistent model
- Appropriate error responses for malformed requests

### Security Tests
- Verify Ollama process owner is current user (not root)
- Verify log files exist and are readable (`/tmp/ollama.stdout.log`, `/tmp/ollama.stderr.log`)
- Verify plist file exists at `~/Library/LaunchAgents/com.ollama.plist`
- Verify `OLLAMA_HOST` is set correctly in plist (DMZ IP or 0.0.0.0)
- Verify no unexpected network services running: `lsof -i` (should only show Ollama on 11434)

### Network Isolation Tests
- Verify Ollama service binds to correct interface
  - Use `lsof -i :11434` to check binding
  - Should show DMZ IP (192.168.100.10) or 0.0.0.0
- Test local access via DMZ IP (should succeed)
- Test router connectivity (should succeed)
- Test LAN isolation: attempt to reach LAN device (should fail)
  - Note: This validates DMZ → LAN firewall rule on router
  - If succeeds, indicates router misconfiguration
- **Note**: Testing from VPN client requires client-side test (cannot be automated from server)

### Router Integration Tests (Manual Checklist - Not Automated)

**These tests require VPN client or router SSH access and cannot be automated from server:**

**From VPN client (after VPN connected):**
- [ ] Can reach DMZ server: `ping 192.168.100.10` (should succeed)
- [ ] Can reach port 11434: `nc -zv 192.168.100.10 11434` (should succeed)
- [ ] Cannot reach LAN: `ping 192.168.1.1` (should timeout/fail)
- [ ] Cannot reach internet: `ping 8.8.8.8` (should timeout/fail)
- [ ] Inference works: `curl http://192.168.100.10:11434/v1/models` (should return JSON)

**From router (via SSH):**
- [ ] WireGuard running: `wg show wg0` (should show peers)
- [ ] Firewall rules present: `iptables -L -v -n` (should show VPN → DMZ rules)
- [ ] Can reach DMZ server: `ping 192.168.100.10` (should succeed)
- [ ] DMZ server isolated from LAN: check firewall rules

**From internet (before VPN):**
- [ ] Port 11434 not exposed: `nmap -p 11434 <public-ip>` (should be closed/filtered)
- [ ] Only WireGuard port open: `nmap -p 51820 <public-ip>` (should be open/udp)

**Expected test count**: ~25-30 automated tests + manual router integration checklist

### Output Format
- **Per-test results** - Clear pass/fail/skip for each test with brief description
- **Summary statistics** - Final count (X passed, Y failed, Z skipped)
- **Exit codes** - 0 if all tests pass, non-zero otherwise
- **Verbose mode** - `--verbose` or `-v` flag for detailed output (request/response bodies, timing)
- **Colorized output** - Use echo -e with color codes:
  - GREEN for passed tests
  - RED for failed tests
  - YELLOW for skipped tests (manual tests)
- **Progress indication** - Show test number / total (e.g., "Running test 5/25...")
- **Grouped results** - Organize output by test category:
  - Network Configuration
  - Service Status
  - API Endpoints (OpenAI + Anthropic)
  - Security
  - Network Isolation
  - Manual Router Tests (checklist only)

### UX Requirements
- **Clear banner** - Display script name, purpose, and test count at start
- **Real-time feedback** - Show results as tests run (don't wait until end)
- **Minimal noise** - Suppress verbose curl output unless --verbose flag used
- **Helpful failures** - When test fails, show:
  - What was expected
  - What was received
  - Suggested troubleshooting steps (check router, check network, etc.)
- **Manual test checklist** - Display checklist for tests that require VPN client or router access
- **Skip guidance** - If tests are skipped, explain why and how to enable them
- **Final summary box** - Visually separated summary section with:
  - Overall pass/fail status
  - Statistics (automated tests only)
  - Manual checklist reminder
  - Next steps if failures occurred (check ROUTER_SETUP.md, etc.)

### Test Requirements
- Requires at least one model pulled for model-specific tests
- Can run with `--skip-model-tests` flag if no models available
- Non-destructive: does not modify server state (read-only API calls)
- Manual tests require VPN client or router SSH access (not automated)

## Configuration files

Server configuration is minimal and managed via:
- Environment variables in the Ollama launchd plist (`OLLAMA_HOST=192.168.100.10` or `0.0.0.0`)
- macOS network settings (static IP for DMZ interface)
- Ollama's built-in configuration system
- Router configuration (managed separately, see ROUTER_SETUP.md)
- No additional configuration files needed on server
