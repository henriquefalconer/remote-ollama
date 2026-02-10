#!/bin/bash
set -euo pipefail

# pin-versions.sh
# Lock Claude Code and Ollama to current versions
# Source: client/specs/VERSION_MANAGEMENT.md lines 133-178
# Creates ~/.ai-client/.version-lock file for reference and downgrade

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
echo "=== Claude Code + Ollama Version Pinning ==="
echo ""

# Step 1: Detect Claude Code version and installation method
if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "unknown")

    if [[ "$CLAUDE_VERSION" == "unknown" ]]; then
        error "Could not detect Claude Code version"
        echo "  Run: claude --version"
        exit 1
    fi

    info "Detected Claude Code: v${CLAUDE_VERSION}"

    # Detect installation method
    if command -v npm &> /dev/null && npm list -g @anthropic-ai/claude-code &> /dev/null; then
        CLAUDE_INSTALL_METHOD="npm"
        info "Installation method: npm (global)"
    elif command -v brew &> /dev/null && brew list claude-code &> /dev/null 2>&1; then
        CLAUDE_INSTALL_METHOD="brew"
        info "Installation method: Homebrew"
    else
        CLAUDE_INSTALL_METHOD="unknown"
        warn "Could not determine installation method"
    fi
else
    error "Claude Code not found"
    echo ""
    echo "Install Claude Code first:"
    echo "  npm install -g @anthropic-ai/claude-code"
    exit 1
fi

# Step 2: Detect Ollama version (from server)
# Load environment if available
ENV_FILE="$HOME/.ai-client/env"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

# Determine Ollama server URL
if [[ -n "${ANTHROPIC_BASE_URL:-}" ]]; then
    OLLAMA_SERVER="$ANTHROPIC_BASE_URL"
elif [[ -n "${OLLAMA_API_BASE:-}" ]]; then
    OLLAMA_SERVER="$OLLAMA_API_BASE"
else
    OLLAMA_SERVER="http://localhost:11434"
fi

# Try to get Ollama version from server
OLLAMA_RESPONSE=$(curl -sf "${OLLAMA_SERVER}/api/version" 2>/dev/null || echo "")

if [[ -n "$OLLAMA_RESPONSE" ]]; then
    OLLAMA_VERSION=$(echo "$OLLAMA_RESPONSE" | jq -r '.version' 2>/dev/null || echo "unknown")

    if [[ "$OLLAMA_VERSION" != "unknown" && "$OLLAMA_VERSION" != "null" ]]; then
        info "Detected Ollama server: v${OLLAMA_VERSION}"
    else
        error "Ollama server reachable but version not detected"
        echo "  Check: ${OLLAMA_SERVER}/api/version"
        exit 1
    fi
else
    error "Ollama server unreachable: ${OLLAMA_SERVER}"
    echo ""
    echo "Ensure server is running and accessible"
    exit 1
fi

echo ""

# Step 3: Pin Claude Code
echo "=== Pinning Claude Code ==="
echo ""

if [[ "$CLAUDE_INSTALL_METHOD" == "npm" ]]; then
    info "Pinning Claude Code to v${CLAUDE_VERSION} via npm..."
    if npm install -g "@anthropic-ai/claude-code@${CLAUDE_VERSION}" &> /dev/null; then
        success "Claude Code pinned to v${CLAUDE_VERSION}"
    else
        warn "Failed to pin via npm (may already be at this version)"
    fi
elif [[ "$CLAUDE_INSTALL_METHOD" == "brew" ]]; then
    info "Pinning Claude Code via Homebrew..."
    if brew pin claude-code &> /dev/null; then
        success "Claude Code pinned via Homebrew"
    else
        warn "Failed to pin via brew (may already be pinned)"
    fi
else
    warn "Unknown installation method - skipping automatic pin"
    echo "  Manual pinning may be required"
fi

echo ""

# Step 4: Display Ollama pinning instructions
echo "=== Ollama Pinning Instructions ==="
echo ""
info "Ollama must be pinned on the server (cannot be done remotely)"
echo ""
echo "Run this on your server (ai-server):"
echo ""
echo "  # Via Homebrew (recommended)"
echo "  brew pin ollama"
echo ""
echo "  # Or record current version for manual management"
echo "  echo \"Ollama pinned at v${OLLAMA_VERSION}\" >> ~/.ollama-version"
echo ""
echo "  # Or use Docker with specific tag"
echo "  docker pull ollama/ollama:${OLLAMA_VERSION}"
echo ""

# Step 5: Create version lock file
LOCK_FILE="$HOME/.ai-client/.version-lock"
info "Creating version lock file: ${LOCK_FILE}"

# Ensure directory exists
mkdir -p "$HOME/.ai-client"

# Generate timestamp
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Write lock file
cat > "$LOCK_FILE" <<LOCK_EOF
# Version lock for Claude Code + Ollama compatibility
# Generated: ${TIMESTAMP}
CLAUDE_CODE_VERSION=${CLAUDE_VERSION}
OLLAMA_VERSION=${OLLAMA_VERSION}
TESTED_DATE=$(date +"%Y-%m-%d")
STATUS=working
CLAUDE_INSTALL_METHOD=${CLAUDE_INSTALL_METHOD}
OLLAMA_SERVER=${OLLAMA_SERVER}
LOCK_EOF

success "Version lock file created"
echo ""

# Step 6: Summary
echo "=== Summary ==="
echo ""
echo "Versions recorded:"
echo "  • Claude Code: v${CLAUDE_VERSION} (${CLAUDE_INSTALL_METHOD})"
echo "  • Ollama:      v${OLLAMA_VERSION} (server)"
echo ""
echo "Lock file: ${LOCK_FILE}"
echo ""
echo "Next steps:"
echo "  1. Pin Ollama on the server (see instructions above)"
echo "  2. Test your setup: ./client/scripts/check-compatibility.sh"
echo "  3. If updates break, downgrade: ./client/scripts/downgrade-claude.sh"
echo ""
success "Version pinning complete!"
