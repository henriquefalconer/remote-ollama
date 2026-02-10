# private-ai-server Scripts

## scripts/install.sh

- Validates macOS + Apple Silicon hardware requirements
- Checks / installs Homebrew
- Checks / installs Tailscale (opens GUI app for login + device approval)
- Checks / installs Ollama via Homebrew
- Stops any existing Ollama service (brew services or launchd) to avoid conflicts
- Creates `~/Library/LaunchAgents/com.ollama.plist` to run Ollama as user-level service
  - Sets `OLLAMA_HOST=0.0.0.0` to bind all network interfaces
  - Configures `KeepAlive=true` and `RunAtLoad=true` for automatic startup
  - Logs to `/tmp/ollama.stdout.log` and `/tmp/ollama.stderr.log`
- Loads the plist via `launchctl bootstrap` (modern API)
- Verifies Ollama is listening on port 11434 (retry loop with timeout)
- Prompts user to set Tailscale machine name (default: `private-ai-server`)
- Prints Tailscale ACL JSON snippet for user to apply in admin console
- Runs self-test: `curl -sf http://localhost:11434/v1/models`
- Idempotent: safe to re-run without breaking existing setup

## scripts/uninstall.sh

- Stops the Ollama LaunchAgent service via `launchctl bootout`
- Removes `~/Library/LaunchAgents/com.ollama.plist`
- Optionally cleans up Ollama logs from `/tmp/` (`ollama.stdout.log`, `ollama.stderr.log`)
- Leaves Homebrew, Tailscale, and Ollama binary untouched (user may want to keep them)
- Leaves downloaded models in `~/.ollama/models/` untouched (valuable data)
- Provides clear summary of what was removed and what remains
- Handles edge cases gracefully (service not running, plist missing, partial installation)

## scripts/warm-models.sh

- Accepts model names as command-line arguments (e.g., `qwen2.5-coder:32b deepseek-r1:70b`)
- Verifies Ollama is running before proceeding
- For each model:
  - Pulls the model via `ollama pull <model>` (downloads if not present)
  - Sends lightweight `/v1/chat/completions` request to force-load into memory
    - Uses minimal prompt ("hi") with `max_tokens: 1`
- Reports progress per model (pulling, loading, ready, failed)
- Continues on individual model failures; prints summary at end
- Includes comments documenting how to wire into launchd as post-boot warmup (optional)

## scripts/test.sh

Comprehensive test script that validates all server functionality. Designed to run on the server machine after installation.

### Service Status Tests
- Verify LaunchAgent is loaded (`launchctl list | grep com.ollama`)
- Verify Ollama process is running as user (not root)
- Verify Ollama is listening on port 11434
- Verify service responds to basic HTTP requests

### API Endpoint Tests
- `GET /v1/models` - returns JSON model list
- `GET /v1/models/{model}` - returns single model details (requires at least one pulled model)
- `POST /v1/chat/completions` - non-streaming request succeeds
- `POST /v1/chat/completions` - streaming (`stream: true`) returns SSE chunks
- `POST /v1/chat/completions` - with `stream_options.include_usage` returns usage data
- `POST /v1/chat/completions` - JSON mode (`response_format: {"type": "json_object"}`)
- `POST /v1/responses` - experimental endpoint (note if requires Ollama 0.5.0+)

### Error Behavior Tests
- 500 error on inference with nonexistent model
- Appropriate error responses for malformed requests

### Security Tests
- Verify Ollama process owner is current user (not root)
- Verify log files exist and are readable (`/tmp/ollama.stdout.log`, `/tmp/ollama.stderr.log`)
- Verify plist file exists at `~/Library/LaunchAgents/com.ollama.plist`
- Verify `OLLAMA_HOST=0.0.0.0` is set in plist environment variables

### Network Tests
- Verify service binds to all interfaces (0.0.0.0)
- Test local access via localhost
- Test local access via Tailscale IP (if Tailscale connected)
- Note: Testing from unauthorized client requires separate client-side test

### Output Format
- Clear pass/fail for each test
- Summary count at end (X passed, Y failed, Z skipped)
- Exit code 0 if all tests pass, non-zero otherwise
- Verbose mode option (`--verbose` or `-v`) for detailed output
- Colorized output for readability (green=pass, red=fail, yellow=skip)

### Test Requirements
- Requires at least one model pulled for model-specific tests
- Can run with `--skip-model-tests` flag if no models available
- Non-destructive: does not modify server state (read-only API calls)

## No config files

Server requires no configuration files. All settings are managed via:
- Environment variables in the launchd plist (`OLLAMA_HOST=0.0.0.0`)
- Ollama's built-in configuration system
- Tailscale ACLs (managed via Tailscale admin console)
