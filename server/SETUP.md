# remote-ollama ai-server – Setup Instructions

Target: Apple Silicon Mac (high memory recommended) running recent macOS

## Prerequisites

- Administrative access
- Homebrew package manager
- Tailscale account (free personal tier sufficient)

## Step-by-Step Setup

### 1. Install Tailscale

```bash
brew install tailscale
open -a Tailscale          # complete login and device approval
```

### 2. Install Ollama (if not already present)

```bash
brew install ollama
```

### 3. Install HAProxy (Highly Recommended)

HAProxy provides a security proxy layer for endpoint allowlisting and kernel-enforced isolation.

```bash
brew install haproxy
```

**Benefits:**
- Only allowlisted endpoints exposed (prevents accidental exposure)
- Kernel-enforced isolation (Ollama unreachable from network)
- Future-expandable (auth, rate limits can be added later)

**Without proxy:**
- Ollama directly exposed to Tailscale network
- All Ollama endpoints reachable (including future ones)
- Higher risk of accidental exposure

### 4. Configure Ollama with loopback binding

Create user-level launch agent with **loopback binding** (127.0.0.1):

```bash
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.ollama.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/ollama</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>127.0.0.1</string>
    </dict>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ollama.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ollama.stderr.log</string>
</dict>
</plist>
EOF

launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ollama.plist
```

**Important:** `OLLAMA_HOST=127.0.0.1` binds Ollama to loopback only, making it unreachable from the network. HAProxy will provide remote access on the Tailscale interface.

### 5. Configure HAProxy proxy

Create HAProxy configuration directory and config file:

```bash
mkdir -p ~/.haproxy

# Get your Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)

# Create HAProxy configuration
cat > ~/.haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    maxconn 2000
    daemon

defaults
    log global
    mode http
    option httplog
    timeout connect 5s
    timeout client 300s
    timeout server 300s

frontend ollama
    bind ${TAILSCALE_IP}:11434

    # Allowlisted endpoints
    acl is_openai_chat path_beg /v1/chat/completions
    acl is_openai_models path_beg /v1/models
    acl is_openai_responses path_beg /v1/responses
    acl is_anthropic_messages path_beg /v1/messages
    acl is_ollama_version path /api/version
    acl is_ollama_tags path /api/tags
    acl is_ollama_show path /api/show

    # Forward allowlisted endpoints
    use_backend ollama if is_openai_chat
    use_backend ollama if is_openai_models
    use_backend ollama if is_openai_responses
    use_backend ollama if is_anthropic_messages
    use_backend ollama if is_ollama_version
    use_backend ollama if is_ollama_tags
    use_backend ollama if is_ollama_show

    # Block everything else
    default_backend blocked

backend ollama
    server ollama 127.0.0.1:11434 check

backend blocked
    http-request deny
EOF

echo "✓ HAProxy config created at ~/.haproxy/haproxy.cfg"
echo "  Listening on: ${TAILSCALE_IP}:11434"
echo "  Forwarding to: 127.0.0.1:11434"
```

### 6. Create HAProxy LaunchAgent

```bash
cat > ~/Library/LaunchAgents/com.haproxy.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.haproxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/haproxy</string>
        <string>-f</string>
        <string>/Users/YOUR_USERNAME/.haproxy/haproxy.cfg</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/haproxy.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/haproxy.log</string>
</dict>
</plist>
EOF

# Replace YOUR_USERNAME with actual username
sed -i '' "s/YOUR_USERNAME/$(whoami)/g" ~/Library/LaunchAgents/com.haproxy.plist

# Load HAProxy service
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.haproxy.plist

echo "✓ HAProxy LaunchAgent created and loaded"
```

### 7. Start services

```bash
# Start Ollama
launchctl kickstart gui/$(id -u)/com.ollama

# Start HAProxy
launchctl kickstart gui/$(id -u)/com.haproxy

# Verify both services are running
launchctl list | grep com.ollama
launchctl list | grep com.haproxy
```

### 8. (Optional) Pre-pull large models for testing

```bash
ollama pull <model-name>   # repeat for desired models
```

### 9. Configure Tailscale ACLs

In Tailscale admin console at tailscale.com:

1. Assign a machine name e.g. "remote-ollama"
2. Create tags e.g. tag:ai-client
3. Add ACL rule example:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:ai-client"],
      "dst": ["tag:ai-server:11434"]
    }
  ]
}
```

### 10. Verify server reachability and security isolation

#### Test 1: Verify Ollama loopback binding (from server)

```bash
# This should work (localhost = 127.0.0.1, bypasses HAProxy)
curl -sf http://localhost:11434/v1/models
echo "✓ Ollama accessible on loopback"

# This should work (through HAProxy)
curl -sf http://$(tailscale ip -4):11434/v1/models
echo "✓ HAProxy forwarding works"

# Verify Ollama is bound to loopback only
lsof -i :11434 | grep LISTEN
# Expected output: ollama should show 127.0.0.1:11434 (not 0.0.0.0)
```

#### Test 2: OpenAI-Compatible API (for Aider)

From an authorized client machine:

```bash
curl http://remote-ollama:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "any-available-model",
    "messages": [{"role": "user", "content": "Say hello"}]
  }'
```

#### Test 3: Anthropic-Compatible API (for Claude Code, requires Ollama 0.5.0+)

From an authorized client machine:

```bash
curl http://remote-ollama:11434/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: ollama" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "any-available-model",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Say hello"}]
  }'
```

**Expected response format:**
```json
{
  "id": "msg_abc123",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "Hello! How can I help you today?"
    }
  ],
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 10,
    "output_tokens": 15
  }
}
```

**Test streaming (optional):**

```bash
curl http://remote-ollama:11434/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: ollama" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "any-available-model",
    "max_tokens": 1024,
    "stream": true,
    "messages": [{"role": "user", "content": "Say hello"}]
  }'
```

This returns Server-Sent Events (SSE) with event types: `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`.

**Note**: The Anthropic-compatible API is experimental in Ollama and requires version 0.5.0 or later. See `server/specs/ANTHROPIC_COMPATIBILITY.md` for complete details on supported features and limitations.

## Server is now operational

Clients must join the same tailnet and receive the appropriate tag to connect.

## Managing the Services

Both HAProxy and Ollama run as user-level LaunchAgents and start automatically at login.

### Check Status
```bash
# Check if both services are loaded
launchctl list | grep com.haproxy
launchctl list | grep com.ollama

# Test API availability (through HAProxy)
curl -sf http://localhost:11434/v1/models

# Test from Tailscale IP (through HAProxy)
curl -sf http://$(tailscale ip -4):11434/v1/models

# Test Anthropic API availability (Ollama 0.5.0+)
curl -sf http://localhost:11434/v1/messages \
  -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: test" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"test","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'
```

### Start Service
```bash
# Start HAProxy
launchctl kickstart gui/$(id -u)/com.haproxy

# Start Ollama
launchctl kickstart gui/$(id -u)/com.ollama
```

### Stop Service
```bash
# Temporarily stop HAProxy (will restart on next login)
launchctl stop gui/$(id -u)/com.haproxy

# Temporarily stop Ollama (will restart on next login)
launchctl stop gui/$(id -u)/com.ollama
```

### Restart Service
```bash
# Kill and immediately restart HAProxy
launchctl kickstart -k gui/$(id -u)/com.haproxy

# Kill and immediately restart Ollama
launchctl kickstart -k gui/$(id -u)/com.ollama
```

### Disable Service (Prevent Auto-Start)
```bash
# Completely unload HAProxy
launchctl bootout gui/$(id -u)/com.haproxy

# Completely unload Ollama
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
# Monitor HAProxy logs
tail -f /tmp/haproxy.log

# Monitor Ollama standard output
tail -f /tmp/ollama.stdout.log

# Monitor Ollama errors
tail -f /tmp/ollama.stderr.log
```

### Check Current Models
```bash
# List all pulled models
ollama list

# Pull a new model
ollama pull <model-name>
```

### (Optional) Warm Models for Faster First Response

The `warm-models.sh` script eliminates cold-start latency by pre-loading models into memory. This is particularly useful for large models that take significant time to load on first request.

```bash
# Navigate to server directory if not already there
cd /path/to/remote-ollama/server

# Warm specific models
./scripts/warm-models.sh qwen2.5-coder:32b deepseek-r1:70b
```

The script will:
1. Verify Ollama is running
2. Pull each model (if not already downloaded)
3. Send a minimal inference request to load the model into memory
4. Report success/failure for each model

This step is optional but recommended if you want immediate response times after server boot or restart. You can also integrate this into launchd for automatic warmup at boot - see the script's inline comments for details.

## Troubleshooting

### HAProxy Service Not Starting

**Symptom**: `launchctl list | grep com.haproxy` shows nothing, or service won't load.

**Solutions**:
- Verify plist exists: `ls -l ~/Library/LaunchAgents/com.haproxy.plist`
- Check plist syntax: `plutil -lint ~/Library/LaunchAgents/com.haproxy.plist`
- Verify HAProxy config: `haproxy -c -f ~/.haproxy/haproxy.cfg`
- Check if port 11434 is already in use: `lsof -i :11434`
- Try manually loading: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.haproxy.plist`
- Check logs for errors: `tail -20 /tmp/haproxy.log`

### Ollama Service Not Starting

**Symptom**: `launchctl list | grep com.ollama` shows nothing, or service won't load.

**Solutions**:
- Check if another Ollama instance is running: `ps aux | grep ollama`
- If Homebrew services is running Ollama, stop it: `brew services stop ollama`
- Verify plist exists: `ls -l ~/Library/LaunchAgents/com.ollama.plist`
- Check plist syntax: `plutil -lint ~/Library/LaunchAgents/com.ollama.plist`
- Try manually loading: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ollama.plist`
- Check logs for errors: `tail -20 /tmp/ollama.stderr.log`

### Port 11434 Already in Use

**Symptom**: Service fails to start, logs show "address already in use".

**Solutions**:
- Find what's using the port: `lsof -i :11434`
- Stop conflicting service (usually Homebrew's Ollama): `brew services stop ollama`
- Kill the conflicting process: `kill <PID>` (from lsof output)
- Restart the LaunchAgent: `launchctl kickstart -k gui/$(id -u)/com.ollama`

### API Not Responding

**Symptom**: `curl http://localhost:11434/v1/models` times out or refuses connection.

**Solutions**:
- Verify HAProxy is running: `launchctl list | grep com.haproxy` (should show PID in first column)
- Verify Ollama is running: `launchctl list | grep com.ollama` (should show PID in first column)
- Check if processes are actually running:
  - `ps aux | grep "[h]aproxy"`
  - `ps aux | grep "[o]llama serve"`
- Verify port bindings:
  - `lsof -i :11434` should show both HAProxy (Tailscale IP) and Ollama (127.0.0.1)
- Check environment variable in Ollama plist: `plutil -p ~/Library/LaunchAgents/com.ollama.plist | grep OLLAMA_HOST` (should be `127.0.0.1`)
- Verify HAProxy config: `haproxy -c -f ~/.haproxy/haproxy.cfg`
- Review logs:
  - `tail -50 /tmp/haproxy.log`
  - `tail -50 /tmp/ollama.stdout.log`
  - `tail -50 /tmp/ollama.stderr.log`

### Models Not Loading

**Symptom**: API responds but model inference requests fail.

**Solutions**:
- Verify models are pulled: `ollama list`
- Pull the model manually: `ollama pull <model-name>`
- Check available memory: Large models require significant RAM
- Review stderr log for out-of-memory errors: `tail -50 /tmp/ollama.stderr.log`

### Client Cannot Connect

**Symptom**: Client can reach Tailscale IP but gets connection refused on port 11434.

**Solutions**:
- Verify HAProxy is running and listening on Tailscale interface:
  - `launchctl list | grep com.haproxy`
  - `lsof -i :11434` should show HAProxy bound to your Tailscale IP
- Verify Ollama is bound to loopback only:
  - `lsof -i :11434 | grep ollama` should show `127.0.0.1:11434` (not `0.0.0.0`)
  - Check plist: `plutil -p ~/Library/LaunchAgents/com.ollama.plist | grep OLLAMA_HOST` (should be `127.0.0.1`)
- Test from server itself:
  - Localhost (bypasses HAProxy): `curl http://localhost:11434/v1/models`
  - Tailscale IP (through HAProxy): `curl http://$(tailscale ip -4):11434/v1/models`
- If localhost works but Tailscale IP doesn't:
  - HAProxy may not be running or configured correctly
  - Check HAProxy config: `cat ~/.haproxy/haproxy.cfg`
  - Verify bind address matches your Tailscale IP
  - Check HAProxy logs: `tail -50 /tmp/haproxy.log`
- Check Tailscale ACLs: client must have appropriate tag or device access
- Verify no firewall blocking port 11434 (macOS firewall typically allows local binaries)

### Running the Test Suite

If unsure about the state of your installation, run the comprehensive test suite:

```bash
# Run all 26 tests (service status, security isolation, OpenAI API, Anthropic API)
./scripts/test.sh

# Skip Anthropic API tests (for Ollama < 0.5.0)
./scripts/test.sh --skip-anthropic-tests

# Skip model inference tests (faster)
./scripts/test.sh --skip-model-tests

# Show detailed request/response data
./scripts/test.sh --verbose
```

The test suite will identify specific issues with:
- HAProxy and Ollama service status
- Loopback binding and security isolation
- HAProxy endpoint allowlisting
- OpenAI API endpoints
- Anthropic API endpoints (if Ollama 0.5.0+)
- Network binding configuration
