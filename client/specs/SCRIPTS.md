# private-ai-client Scripts

## scripts/install.sh

- Checks / installs Homebrew, Python, Tailscale
- Opens Tailscale app for login + device approval
- Prompts for server hostname (default: private-ai-server)
- Creates `~/.private-ai-client/env` with exact variables from API_CONTRACT.md
- Appends `source ~/.private-ai-client/env` to `~/.zshrc` (with user consent)
- Installs Aider via pipx (isolated, no global pollution)
- Runs a connectivity test using the contract

## scripts/uninstall.sh

- Removes Aider
- Deletes `~/.private-ai-client`
- Comments out or removes the sourcing line from shell profile
- Leaves Tailscale and Homebrew untouched

## scripts/test.sh

Comprehensive test script that validates all client functionality. Designed to run on the client machine after installation.

### Environment Configuration Tests
- Verify `~/.private-ai-client/env` file exists
- Verify all required environment variables are set:
  - `OLLAMA_API_BASE` (should be `http://<hostname>:11434/v1`)
  - `OPENAI_API_BASE` (should be `http://<hostname>:11434/v1`)
  - `OPENAI_API_KEY` (should be `ollama`)
  - `AIDER_MODEL` (optional, check if set)
- Verify shell profile sources the env file (check `~/.zshrc` or `~/.bashrc` for marker comments)
- Verify environment variables are exported (available to child processes)

### Dependency Tests
- Verify Tailscale is installed and running
- Verify Tailscale is connected (not logged out)
- Verify Homebrew is installed
- Verify Python 3.10+ is available
- Verify pipx is installed
- Verify Aider is installed via pipx (`aider --version`)

### Connectivity Tests
- Test Tailscale connectivity to server hostname
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

### Script Behavior Tests
- Verify install.sh idempotency (safe to re-run)
- Verify uninstall.sh availability (local clone or `~/.private-ai-client/uninstall.sh`)
- Test uninstall.sh on clean system (should not error)

### Output Format
- Clear pass/fail for each test
- Summary count at end (X passed, Y failed, Z skipped)
- Exit code 0 if all tests pass, non-zero otherwise
- Verbose mode option (`--verbose` or `-v`) for detailed output
- Colorized output for readability (green=pass, red=fail, yellow=skip)

### Test Modes
- `--skip-server` - Skip connectivity tests (for offline testing)
- `--skip-aider` - Skip Aider-specific tests
- `--quick` - Run only critical tests (env vars, dependencies, basic connectivity)

## config/env.template

- Template showing the exact variables required by the contract
- Used by install.sh to create `~/.private-ai-client/env`
