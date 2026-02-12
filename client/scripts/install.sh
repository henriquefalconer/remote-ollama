#!/bin/bash
set -euo pipefail

# self-sovereign-ollama ai-client install script (v2)
# Configures environment to connect to self-sovereign-ollama ai-server via WireGuard VPN
# Works both from local clone and via curl-pipe installation
# Source: client/specs/* and client/SETUP.md

# Suppress Homebrew noise
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

fatal() {
    error "$1"
    exit 1
}

prompt() {
    echo -e "${BLUE}[PROMPT]${NC} $1"
}

section_break() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ -n "${1:-}" ]]; then
        echo "  $1"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
    echo ""
}

# Banner
echo "================================================"
echo "  self-sovereign-ollama ai-client Installation"
echo "================================================"
echo ""

section_break "System Requirements Check"

# Step 1: Detect macOS 14+ (Sonoma)
info "Checking system requirements..."
if [[ "$(uname)" != "Darwin" ]]; then
    fatal "This script requires macOS. Detected: $(uname)"
fi

MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [[ "$MACOS_MAJOR" -lt 14 ]]; then
    fatal "This script requires macOS 14 (Sonoma) or later. Detected: $MACOS_VERSION"
fi
info "✓ macOS $MACOS_VERSION detected"

# Step 2: Detect user's shell
info "Detecting shell..."
USER_SHELL=$(basename "$SHELL")
if [[ "$USER_SHELL" != "zsh" && "$USER_SHELL" != "bash" ]]; then
    warn "Detected shell: $USER_SHELL (expected zsh or bash)"
    USER_SHELL="zsh"  # Default to zsh on modern macOS
fi

if [[ "$USER_SHELL" == "zsh" ]]; then
    SHELL_PROFILE="$HOME/.zshrc"
elif [[ "$USER_SHELL" == "bash" ]]; then
    SHELL_PROFILE="$HOME/.bashrc"
fi
info "✓ Shell detected: $USER_SHELL (profile: $SHELL_PROFILE)"

section_break "Dependency Installation"

# Step 3: Check for Homebrew
info "Checking for Homebrew..."
if ! command -v brew &> /dev/null; then
    warn "Homebrew not found"
    echo "Please install Homebrew from https://brew.sh and re-run this script"
    fatal "Homebrew is required"
fi
info "✓ Homebrew found: $(brew --version | head -n1)"

# Step 4: Check/install Python 3.12 (required for Aider compatibility)
info "Checking for Python 3.12 (required for Aider)..."

# Python 3.12 is required because Aider depends on numpy==1.24.3
# numpy 1.24.3 has NO pre-built wheels for Python 3.13+ (verified via PyPI)
# Python 3.10-3.12 all have numpy 1.24.3 wheels available
PYTHON_PATH=""
PYTHON_VERSION=""

# Check for Python 3.12 specifically (via Homebrew)
PYTHON312_PATH="/opt/homebrew/opt/python@3.12/libexec/bin/python"
if [[ -x "$PYTHON312_PATH" ]]; then
    PYTHON_PATH="$PYTHON312_PATH"
    PYTHON_VERSION=$($PYTHON_PATH --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    info "✓ Python $PYTHON_VERSION found (via python@3.12)"
else
    # Check if system python3 is in the acceptable range (3.10-3.12)
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
        PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
        PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

        if [[ "$PYTHON_MAJOR" -eq 3 && "$PYTHON_MINOR" -ge 10 && "$PYTHON_MINOR" -le 12 ]]; then
            # Python 3.10-3.12 are all compatible with numpy 1.24.3
            PYTHON_PATH=$(command -v python3)
            info "✓ Python $PYTHON_VERSION found (compatible)"
        elif [[ "$PYTHON_MAJOR" -ge 3 && "$PYTHON_MINOR" -ge 13 ]]; then
            warn "Python $PYTHON_VERSION detected - incompatible with Aider dependencies"
            warn "Aider requires numpy 1.24.3 which has no wheels for Python 3.13+"
            warn "Installing Python 3.12 for compatibility..."
            brew install python@3.12 > /tmp/python312-install.log 2>&1 || fatal "Failed to install Python 3.12"
            PYTHON_PATH="$PYTHON312_PATH"
            PYTHON_VERSION=$($PYTHON_PATH --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
            info "✓ Python $PYTHON_VERSION installed"
        else
            warn "Python $PYTHON_VERSION is too old (need 3.10+)"
            info "Installing Python 3.12 via Homebrew (this may take a minute)..."
            brew install python@3.12 > /tmp/python312-install.log 2>&1 || fatal "Failed to install Python 3.12"
            PYTHON_PATH="$PYTHON312_PATH"
            PYTHON_VERSION=$($PYTHON_PATH --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
            info "✓ Python $PYTHON_VERSION installed"
        fi
    else
        # No Python found, install 3.12
        info "Installing Python 3.12 via Homebrew (this may take a minute)..."
        brew install python@3.12 > /tmp/python312-install.log 2>&1 || fatal "Failed to install Python 3.12"
        PYTHON_PATH="$PYTHON312_PATH"
        PYTHON_VERSION=$($PYTHON_PATH --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
        info "✓ Python $PYTHON_VERSION installed"
    fi
fi

info "Using Python: $PYTHON_PATH"

echo ""
echo "=== Step 5: WireGuard VPN Setup ==="
echo ""

# Check if WireGuard is installed
if ! command -v wg &> /dev/null && ! brew list wireguard-tools &> /dev/null 2>&1; then
    info "Installing WireGuard tools..."
    if brew install wireguard-tools > /tmp/wireguard-install.log 2>&1; then
        info "✓ WireGuard tools installed"
    else
        error "Failed to install WireGuard tools"
        cat /tmp/wireguard-install.log
        exit 1
    fi
else
    info "✓ WireGuard tools already installed"
fi

# Create WireGuard config directory
WG_DIR="$HOME/.ai-client/wireguard"
mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"

# Generate keypair if not exists
WG_PRIVATE_KEY="$WG_DIR/privatekey"
WG_PUBLIC_KEY="$WG_DIR/publickey"

if [[ ! -f "$WG_PRIVATE_KEY" ]]; then
    info "Generating WireGuard keypair..."
    wg genkey | tee "$WG_PRIVATE_KEY" | wg pubkey > "$WG_PUBLIC_KEY"
    chmod 600 "$WG_PRIVATE_KEY"
    chmod 644 "$WG_PUBLIC_KEY"
    info "✓ Keypair generated"
else
    info "✓ Keypair already exists"
fi

# Display public key
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Your WireGuard Public Key:${NC}"
echo ""
cat "$WG_PUBLIC_KEY"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
warn "IMPORTANT: Send this public key to your router administrator"
echo "  They will need to add it as a VPN peer on the OpenWrt router."
echo ""

# Prompt for server IP
echo "=== Server Configuration ==="
echo ""
info "Enter the AI server IP address (default: 192.168.100.10)"
read -r -p "Server IP: " SERVER_IP < /dev/tty
SERVER_IP=${SERVER_IP:-192.168.100.10}
echo ""

# Validate IP format
if ! echo "$SERVER_IP" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    error "Invalid IP address format: $SERVER_IP"
    exit 1
fi

# Prompt for VPN configuration
info "Enter the router's WireGuard endpoint (format: IP:PORT)"
echo "  Example: 1.2.3.4:51820"
read -r -p "Endpoint: " WG_ENDPOINT < /dev/tty

if [[ -z "$WG_ENDPOINT" ]]; then
    error "Endpoint is required"
    exit 1
fi

info "Enter the router's WireGuard public key"
read -r -p "Router public key: " WG_SERVER_PUBKEY < /dev/tty

if [[ -z "$WG_SERVER_PUBKEY" ]]; then
    error "Router public key is required"
    exit 1
fi

info "Enter your VPN client IP address (assigned by admin)"
echo "  Example: 10.0.0.2"
read -r -p "Client VPN IP: " WG_CLIENT_IP < /dev/tty

if [[ -z "$WG_CLIENT_IP" ]]; then
    error "Client VPN IP is required"
    exit 1
fi

info "Enter allowed IPs (default: 192.168.100.0/24 for DMZ access only)"
read -r -p "Allowed IPs: " WG_ALLOWED_IPS < /dev/tty
WG_ALLOWED_IPS=${WG_ALLOWED_IPS:-192.168.100.0/24}

# Generate WireGuard configuration
WG_CONFIG="$WG_DIR/wg0.conf"
info "Generating WireGuard configuration..."

cat > "$WG_CONFIG" <<EOF
[Interface]
PrivateKey = $(cat "$WG_PRIVATE_KEY")
Address = $WG_CLIENT_IP/24

[Peer]
PublicKey = $WG_SERVER_PUBKEY
Endpoint = $WG_ENDPOINT
AllowedIPs = $WG_ALLOWED_IPS
PersistentKeepalive = 25
EOF

chmod 600 "$WG_CONFIG"
info "✓ WireGuard configuration generated: $WG_CONFIG"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}WireGuard Configuration:${NC}"
echo ""
cat "$WG_CONFIG"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Connection instructions
warn "Next Steps for VPN Connection:"
echo "  1. Wait for router admin confirmation (peer added)"
echo "  2. Import configuration: sudo wg-quick up wg0"
echo "     Or use WireGuard GUI app to import $WG_CONFIG"
echo "  3. Verify: wg show"
echo ""

read -r -p "Press Enter after you have connected to the VPN to continue..." < /dev/tty
echo ""

section_break "Environment Configuration"

# Step 6: Create ~/.ai-client directory
info "Creating configuration directory..."
CLIENT_DIR="$HOME/.ai-client"
mkdir -p "$CLIENT_DIR"
info "✓ Created: $CLIENT_DIR"

# Step 7: Generate environment file from template
info "Generating environment configuration..."

# Dual-mode strategy: local clone vs curl-pipe
ENV_TEMPLATE_CONTENT=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LOCAL_TEMPLATE="$SCRIPT_DIR/../config/env.template"

# Detect curl-pipe mode: $0 is bash/stdin or template doesn't exist
if [[ "$0" == "bash" || "$0" == "/dev/stdin" || ! -f "$LOCAL_TEMPLATE" ]]; then
    # Curl-pipe mode: use embedded template
    info "Using embedded env.template (curl-pipe mode)"
    ENV_TEMPLATE_CONTENT=$(cat <<'TEMPLATE_EOF'
# self-sovereign-ollama ai-client environment configuration
# Source: client/specs/API_CONTRACT.md
# Generated from env.template by install.sh -- do not edit manually
# NOTE: Requires active WireGuard VPN connection to reach server
export OLLAMA_API_BASE=http://__SERVER_IP__:11434
export OPENAI_API_BASE=http://__SERVER_IP__:11434/v1
export OPENAI_API_KEY=ollama
# export AIDER_MODEL=ollama/<model-name>

# Claude Code + Ollama (v2+, optional, uncomment if using claude-ollama alias)
# export ANTHROPIC_AUTH_TOKEN=ollama
# export ANTHROPIC_API_KEY=""
# export ANTHROPIC_BASE_URL=http://__SERVER_IP__:11434
TEMPLATE_EOF
)
else
    # Local clone mode: read from file
    info "Using env.template from local clone"
    ENV_TEMPLATE_CONTENT=$(cat "$LOCAL_TEMPLATE")
fi

# Substitute __SERVER_IP__ placeholder (or __HOSTNAME__ for backward compatibility)
ENV_FILE="$CLIENT_DIR/env"
echo "$ENV_TEMPLATE_CONTENT" | sed "s/__HOSTNAME__/$SERVER_IP/g; s/__SERVER_IP__/$SERVER_IP/g" > "$ENV_FILE"
info "✓ Created: $ENV_FILE"

# Step 8: Prompt for shell profile modification consent
echo ""
prompt "Update $SHELL_PROFILE to source the environment? (required for tools to work) [Y/n]:"
read -r CONSENT < /dev/tty
CONSENT=${CONSENT:-Y}
if [[ "$CONSENT" =~ ^[Yy]$ ]]; then
    info "Updating shell profile..."

    # Marker pattern for idempotency and clean removal
    MARKER_START="# >>> ai-client >>>"
    MARKER_END="# <<< ai-client <<<"

    # Check if markers already exist
    if grep -q "$MARKER_START" "$SHELL_PROFILE" 2>/dev/null; then
        info "Shell profile already configured (markers found), skipping"
    else
        # Create profile if it doesn't exist
        touch "$SHELL_PROFILE"

        # Append sourcing block with markers
        cat >> "$SHELL_PROFILE" <<PROFILE_EOF

$MARKER_START
# self-sovereign-ollama ai-client environment configuration
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi
$MARKER_END
PROFILE_EOF
        info "✓ Updated: $SHELL_PROFILE"
    fi
else
    warn "Shell profile not updated. You must manually source $ENV_FILE before using tools"
fi

section_break "Tool Installation"

# Step 9: Install pipx with Python version compatibility check
info "Checking for pipx..."
PIPX_NEEDS_REINSTALL=false

if ! command -v pipx &> /dev/null; then
    info "Installing pipx via Homebrew (this may take a minute)..."
    brew install pipx > /tmp/pipx-install.log 2>&1 || fatal "Failed to install pipx"
    info "✓ pipx installed"
else
    info "✓ pipx already installed"

    # Check if pipx's shared environment uses incompatible Python version
    if [[ -d "$HOME/.local/pipx/shared" ]]; then
        PIPX_SHARED_PYTHON="$HOME/.local/pipx/shared/bin/python"
        if [[ -x "$PIPX_SHARED_PYTHON" ]]; then
            PIPX_PYTHON_VERSION=$($PIPX_SHARED_PYTHON --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
            PIPX_PYTHON_MINOR=$(echo "$PIPX_PYTHON_VERSION" | cut -d. -f2)

            # Python 3.13+ causes compatibility issues with Aider dependencies (numpy 1.24.3 has no wheels)
            if [[ "$PIPX_PYTHON_MINOR" -ge 13 ]]; then
                warn "pipx is using Python $PIPX_PYTHON_VERSION which is incompatible with Aider"
                echo ""
                echo "Aider requires numpy 1.24.3 which has no pre-built wheels for Python 3.13+."
                echo "We need to reinstall pipx to use Python $PYTHON_VERSION instead."
                echo ""
                prompt "Reinstall pipx with Python $PYTHON_VERSION for compatibility? [Y/n]:"
                read -r REINSTALL_PIPX < /dev/tty
                REINSTALL_PIPX=${REINSTALL_PIPX:-Y}

                if [[ "$REINSTALL_PIPX" =~ ^[Yy]$ ]]; then
                    PIPX_NEEDS_REINSTALL=true
                else
                    warn "Continuing with Python $PIPX_PYTHON_VERSION - Aider installation WILL fail"
                fi
            else
                info "✓ pipx is using compatible Python $PIPX_PYTHON_VERSION"
            fi
        fi
    fi
fi

# Reinstall pipx if needed for compatibility
if [[ "$PIPX_NEEDS_REINSTALL" == "true" ]]; then
    info "Reinstalling pipx with Python $PYTHON_VERSION..."

    # Remove existing pipx shared environment
    if [[ -d "$HOME/.local/pipx/shared" ]]; then
        rm -rf "$HOME/.local/pipx/shared"
        info "✓ Removed old pipx shared environment"
    fi

    # Uninstall all pipx packages (they'll be reinstalled)
    if pipx list 2>/dev/null | grep -q "venvs"; then
        warn "Uninstalling existing pipx packages (will be reinstalled)..."
        pipx uninstall-all 2>/dev/null || true
    fi

    # Reinstall pipx via Homebrew
    brew reinstall pipx > /tmp/pipx-reinstall.log 2>&1 || fatal "Failed to reinstall pipx"
    info "✓ pipx reinstalled"
fi

# Always run ensurepath to ensure PATH is configured (suppress verbose output)
export PIPX_DEFAULT_PYTHON="$PYTHON_PATH"
pipx ensurepath > /dev/null 2>&1 || warn "pipx ensurepath failed (non-fatal)"

# Step 10: Install Aider with specific Python version
info "Checking for Aider..."

# Ensure pipx uses the correct Python version
export PIPX_DEFAULT_PYTHON="$PYTHON_PATH"

if pipx list 2>/dev/null | grep -q aider-chat; then
    info "✓ Aider already installed, upgrading..."
    pipx upgrade aider-chat > /tmp/aider-upgrade.log 2>&1 || warn "Failed to upgrade Aider (non-fatal)"
else
    info "Installing Aider (this may take a few minutes)..."
    # Use specific Python version to avoid compatibility issues
    if PIPX_DEFAULT_PYTHON="$PYTHON_PATH" pipx install aider-chat --python "$PYTHON_PATH" > /tmp/aider-install.log 2>&1; then
        info "✓ Aider installed"
    else
        error "Failed to install Aider"
        echo ""
        echo "Installation log saved to: /tmp/aider-install.log"
        echo "Common issues:"
        echo "  • Python version compatibility (requires 3.10-3.12, NOT 3.13+)"
        echo "  • Network connectivity during package download"
        echo "  • Disk space or permissions"
        echo ""
        echo "To debug, check the log file or try manually:"
        echo "  PIPX_DEFAULT_PYTHON=$PYTHON_PATH pipx install aider-chat --python $PYTHON_PATH --verbose"
        echo ""
        fatal "Aider installation failed"
    fi
fi

# Step 11: Optional Claude Code + Ollama integration (v2+)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Optional: Claude Code + Ollama Integration (v2+)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "You can use Claude Code with your local Ollama server."
echo ""
echo "Benefits:"
echo "  • Privacy: All inference stays on your network"
echo "  • Cost: No API charges"
echo "  • Speed: Low latency to local server"
echo ""
echo "Limitations:"
echo "  • Model quality lower than real Claude"
echo "  • No prompt caching (slower on repeated contexts)"
echo "  • Best for: Simple tasks, file reads, quick edits"
echo ""
echo "Note: This only creates a 'claude-ollama' shell alias."
echo "      Claude Code must already be installed separately."
echo ""
prompt "Create 'claude-ollama' shell alias? (y/N):"
read -r CLAUDE_CONSENT < /dev/tty

if [[ "$CLAUDE_CONSENT" =~ ^[Yy]$ ]]; then
    info "Adding claude-ollama alias to $SHELL_PROFILE..."

    # Marker pattern for the Claude Code alias
    CLAUDE_MARKER_START="# >>> claude-ollama >>>"
    CLAUDE_MARKER_END="# <<< claude-ollama <<<"

    # Check if Claude alias markers already exist
    if grep -q "$CLAUDE_MARKER_START" "$SHELL_PROFILE" 2>/dev/null; then
        info "Claude Code alias already configured (markers found), skipping"
    else
        # Append alias with markers
        cat >> "$SHELL_PROFILE" <<CLAUDE_PROFILE_EOF

$CLAUDE_MARKER_START
# Claude Code with local Ollama backend (requires WireGuard VPN)
alias claude-ollama='ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY="" ANTHROPIC_BASE_URL=http://$SERVER_IP:11434 claude --dangerously-skip-permissions'
$CLAUDE_MARKER_END
CLAUDE_PROFILE_EOF

        info "✓ Added claude-ollama alias to shell profile"

        echo ""
        info "To use Claude Code with Ollama:"
        echo "  • Connect to WireGuard VPN first"
        echo "  • Open a new terminal (or run: source $SHELL_PROFILE)"
        echo "  • Run: claude-ollama"
        echo ""
        info "To use Claude Code with Anthropic cloud (recommended for quality):"
        echo "  • Run: claude"
        echo ""
    fi
else
    info "Skipping Claude Code alias (you can use standard 'claude' with Anthropic cloud)"
fi

# Step 12: Copy uninstall.sh for curl-pipe users
UNINSTALL_SCRIPT="$CLIENT_DIR/uninstall.sh"

# Detect if we have local uninstall.sh
LOCAL_UNINSTALL="$SCRIPT_DIR/uninstall.sh"
if [[ -f "$LOCAL_UNINSTALL" ]]; then
    # Local clone mode: copy from repo
    cp "$LOCAL_UNINSTALL" "$UNINSTALL_SCRIPT"
    chmod +x "$UNINSTALL_SCRIPT"
else
    # Curl-pipe mode: download from GitHub
    UNINSTALL_URL="https://raw.githubusercontent.com/henriquefalconer/self-sovereign-ollama/master/client/scripts/uninstall.sh"
    if curl -fsSL "$UNINSTALL_URL" -o "$UNINSTALL_SCRIPT" 2>/dev/null; then
        chmod +x "$UNINSTALL_SCRIPT"
    else
        warn "Failed to download uninstall.sh (non-fatal)"
    fi
fi

section_break "Connectivity Test"

# Step 13: Run connectivity test
TEST_URL="http://$SERVER_IP:11434/v1/models"
SERVER_REACHABLE=false
if curl -sf --max-time 5 "$TEST_URL" &> /dev/null; then
    info "✓ Server connected: $TEST_URL"
    SERVER_REACHABLE=true
else
    warn "Server not reachable at $TEST_URL"
    echo "  → Ensure WireGuard VPN is connected and server is running"
    echo "  → Check with: wg show"
fi

# Final summary
echo ""
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║                  ✓  Installation Complete!                    ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Determine actual shell command for reload
RELOAD_CMD="exec $SHELL"
if [[ "$USER_SHELL" == "zsh" ]]; then
    RELOAD_CMD="exec zsh"
elif [[ "$USER_SHELL" == "bash" ]]; then
    RELOAD_CMD="exec bash"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Your WireGuard Public Key (for router admin):${NC}"
echo ""
cat "$WG_PUBLIC_KEY"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "$SERVER_REACHABLE" == "true" ]]; then
    echo -e "  ✓ Aider installed: ${GREEN}ready${NC}"
    echo -e "  ✓ Connected to server: ${GREEN}$SERVER_IP${NC}"
    echo -e "  ✓ WireGuard VPN: ${GREEN}connected${NC}"
    echo ""
    section_break
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ What's Next                                                 │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  1. Reload your shell:"
    echo ""
    echo -e "     ${BLUE}$RELOAD_CMD${NC}"
    echo ""
    echo "  2. Start using Aider:"
    echo ""
    echo -e "     ${BLUE}aider${NC}                          # Uses default model"
    echo -e "     ${BLUE}aider --model ollama/model-name${NC}    # Select specific model"
    echo ""
    echo "  3. VPN Management:"
    echo ""
    echo -e "     ${BLUE}wg show${NC}                        # Check VPN status"
    echo -e "     ${BLUE}sudo wg-quick down wg0${NC}        # Disconnect VPN"
    echo -e "     ${BLUE}sudo wg-quick up wg0${NC}          # Reconnect VPN"
    echo ""
else
    echo -e "  ✓ Aider installed: ${GREEN}ready${NC}"
    echo -e "  ⚠ Server: ${YELLOW}not reachable${NC}"
    echo ""
    section_break
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ What's Next                                                 │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  1. Connect to WireGuard VPN:"
    echo ""
    echo -e "     ${BLUE}sudo wg-quick up wg0${NC}"
    echo "     Or import $WG_CONFIG in WireGuard GUI app"
    echo ""
    echo "  2. Verify VPN connection:"
    echo ""
    echo -e "     ${BLUE}wg show${NC}"
    echo -e "     ${BLUE}curl http://$SERVER_IP:11434/v1/models${NC}"
    echo ""
    echo "  3. Reload your shell:"
    echo ""
    echo -e "     ${BLUE}$RELOAD_CMD${NC}"
    echo ""
    echo "  4. Start using Aider:"
    echo ""
    echo -e "     ${BLUE}aider --model ollama/model-name${NC}"
    echo ""
    echo "  Troubleshooting:"
    echo "  • Ensure router admin has added your public key as a VPN peer"
    echo "  • Check router firewall allows DMZ access (192.168.100.0/24)"
    echo "  • Verify server is running: ssh into server and check Ollama status"
    echo ""
fi
