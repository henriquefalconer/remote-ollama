# self-sovereign-ollama ai-server – Setup Instructions

Target: Apple Silicon Mac (high memory recommended) running recent macOS

## Prerequisites

- Administrative access
- Homebrew package manager
- OpenWrt router configured with WireGuard VPN (see [ROUTER_SETUP.md](ROUTER_SETUP.md))
- Static IP configured on DMZ network (default: 192.168.100.10)

## Step-by-Step Setup

### 1. Configure OpenWrt Router

**IMPORTANT**: Complete router configuration first before proceeding with server setup.

See [ROUTER_SETUP.md](ROUTER_SETUP.md) for comprehensive OpenWrt + WireGuard VPN configuration instructions.

Required router configuration:
- OpenWrt 23.05 LTS or later installed
- WireGuard VPN server configured on router
- DMZ network created (192.168.100.0/24)
- Firewall rules: VPN → DMZ port 11434 only
- Static DHCP reservation for server (192.168.100.10)

### 2. Configure Server Network

Connect server to router via Ethernet on DMZ network.

**Verify static IP assignment:**
```bash
# Check current IP address
ifconfig | grep 192.168.100

# Should show: inet 192.168.100.10
```

**If static IP not assigned by router DHCP:**
Configure manually in System Settings → Network → Select interface → Details → TCP/IP → Configure IPv4: Manually
- IP Address: 192.168.100.10
- Subnet Mask: 255.255.255.0
- Router: 192.168.100.1
- DNS: 192.168.100.1 (or 1.1.1.1)

### 3. Install Ollama

```bash
brew install ollama
```

### 4. Configure Ollama with DMZ Binding

Create user-level launch agent with **DMZ interface binding** (192.168.100.10):

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
        <string>192.168.100.10</string>
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

**Important:** `OLLAMA_HOST=192.168.100.10` binds Ollama to the DMZ interface. Router firewall controls access (VPN clients → port 11434 only).

**Alternative binding:** Use `OLLAMA_HOST=0.0.0.0` to listen on all interfaces (DMZ + localhost). Router firewall still controls external access.

### 5. Start Ollama Service

```bash
# Start Ollama
launchctl kickstart gui/$(id -u)/com.ollama

# Verify service is running
launchctl list | grep com.ollama

# Test local access on DMZ interface
curl -sf http://192.168.100.10:11434/v1/models
```

### 6. (Optional) Pre-pull Large Models

```bash
ollama pull <model-name>   # repeat for desired models
```

### 7. Add VPN Client Public Keys to Router

On the router (via SSH or LuCI web interface), add each VPN client's public key:

```bash
# SSH to router
ssh root@192.168.100.1

# Add VPN peer (client)
uci add wireguard wg0 peer
uci set wireguard.@peer[-1].PublicKey='CLIENT_PUBLIC_KEY_HERE'
uci set wireguard.@peer[-1].AllowedIPs='10.10.10.X/32'  # Assign VPN IP to this client
uci set wireguard.@peer[-1].PersistentKeepalive='25'
uci commit wireguard
/etc/init.d/wireguard restart
```

See [ROUTER_SETUP.md](ROUTER_SETUP.md) for complete VPN peer management instructions.

### 8. Verify Server Reachability

#### Test 1: Verify Ollama DMZ binding (from server)

```bash
# Test local access on DMZ interface
curl -sf http://192.168.100.10:11434/v1/models
echo "✓ Ollama accessible on DMZ interface"

# Verify Ollama is bound to DMZ IP or all interfaces
lsof -i :11434 | grep LISTEN
# Expected output: ollama should show 192.168.100.10:11434 (or 0.0.0.0:11434)
```

#### Test 2: OpenAI-Compatible API (for Aider)

From a VPN-connected client machine:

```bash
curl http://192.168.100.10:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "any-available-model",
    "messages": [{"role": "user", "content": "Say hello"}]
  }'
```

#### Test 3: Anthropic-Compatible API (for Claude Code, requires Ollama 0.5.0+)

From a VPN-connected client machine:

```bash
curl http://192.168.100.10:11434/v1/messages \
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
curl http://192.168.100.10:11434/v1/messages \
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

VPN clients with authorized public keys configured on the router can connect. See [ROUTER_SETUP.md](ROUTER_SETUP.md) for managing VPN peers.

## Managing the Services

Ollama runs as a user-level LaunchAgent and starts automatically at login.

### Check Status
```bash
# Check if Ollama service is loaded
launchctl list | grep com.ollama

# Test API availability on DMZ interface
curl -sf http://192.168.100.10:11434/v1/models

# Test Anthropic API availability (Ollama 0.5.0+)
curl -sf http://192.168.100.10:11434/v1/messages \
  -X POST \
  -H "Content-Type: application/json" \
  -H "x-api-key: test" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"test","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'
```

### Start Service
```bash
# Start Ollama
launchctl kickstart gui/$(id -u)/com.ollama
```

### Stop Service
```bash
# Temporarily stop Ollama (will restart on next login)
launchctl stop gui/$(id -u)/com.ollama
```

### Restart Service
```bash
# Kill and immediately restart Ollama
launchctl kickstart -k gui/$(id -u)/com.ollama
```

### Disable Service (Prevent Auto-Start)
```bash
# Completely unload Ollama
launchctl bootout gui/$(id -u)/com.ollama
```

### Re-enable Service
```bash
# Load Ollama again
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ollama.plist
```

### View Logs
```bash
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
cd /path/to/self-sovereign-ollama/server

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

**Symptom**: `curl http://192.168.100.10:11434/v1/models` times out or refuses connection.

**Solutions**:
- Verify Ollama is running: `launchctl list | grep com.ollama` (should show PID in first column)
- Check if Ollama process is actually running:
  - `ps aux | grep "[o]llama serve"`
- Verify port binding:
  - `lsof -i :11434` should show Ollama bound to 192.168.100.10 (or 0.0.0.0)
- Check environment variable in Ollama plist: `plutil -p ~/Library/LaunchAgents/com.ollama.plist | grep OLLAMA_HOST` (should be `192.168.100.10` or `0.0.0.0`)
- Review logs:
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

**Symptom**: VPN client cannot reach server on 192.168.100.10:11434.

**Solutions**:
- Verify VPN connection:
  - Client should have active WireGuard tunnel
  - Check client can ping DMZ server: `ping 192.168.100.10`
- Verify Ollama is running and listening on DMZ interface:
  - `launchctl list | grep com.ollama`
  - `lsof -i :11434` should show Ollama bound to 192.168.100.10 (or 0.0.0.0)
- Verify Ollama DMZ binding:
  - `lsof -i :11434 | grep ollama` should show `192.168.100.10:11434` (or `*:11434`)
  - Check plist: `plutil -p ~/Library/LaunchAgents/com.ollama.plist | grep OLLAMA_HOST` (should be `192.168.100.10` or `0.0.0.0`)
- Test from server itself:
  - DMZ interface: `curl http://192.168.100.10:11434/v1/models`
- If server test works but client test doesn't:
  - Router firewall may be blocking: Check [ROUTER_SETUP.md](ROUTER_SETUP.md) firewall rules
  - Verify VPN → DMZ rule allows port 11434: `ssh root@192.168.100.1 "iptables -L FORWARD -v -n | grep 11434"`
  - Check client's VPN peer is configured on router: `ssh root@192.168.100.1 "wg show wg0"`
- Verify no macOS firewall blocking port 11434 (System Settings → Network → Firewall)

### Running the Test Suite

If unsure about the state of your installation, run the comprehensive test suite:

```bash
# Run all 36 tests (service status, security, network configuration, OpenAI API, Anthropic API)
./scripts/test.sh

# Skip Anthropic API tests (for Ollama < 0.5.0)
./scripts/test.sh --skip-anthropic-tests

# Skip model inference tests (faster)
./scripts/test.sh --skip-model-tests

# Show detailed request/response data
./scripts/test.sh --verbose
```

The test suite will identify specific issues with:
- Ollama service status
- DMZ interface binding and network configuration
- Static IP configuration
- OpenAI API endpoints
- Anthropic API endpoints (if Ollama 0.5.0+)
- Network isolation (DMZ vs LAN)

**Note**: Router integration tests (firewall rules, VPN connectivity) are manual - see [ROUTER_SETUP.md](ROUTER_SETUP.md) verification section.
