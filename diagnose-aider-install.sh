#!/bin/bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Aider Installation Diagnostics ===${NC}\n"

# 1. Check for installation log files
echo -e "${BLUE}[1] Checking for installation log files...${NC}"
if [ -f /tmp/pipx-install-aider.log ]; then
    echo -e "${GREEN}Found log file: /tmp/pipx-install-aider.log${NC}"
    echo -e "${YELLOW}--- Last 50 lines of log ---${NC}"
    tail -50 /tmp/pipx-install-aider.log
    echo -e "${YELLOW}--- End of log ---${NC}\n"
else
    echo -e "${YELLOW}No log file found at /tmp/pipx-install-aider.log${NC}\n"
fi

# 2. Check pipx status
echo -e "${BLUE}[2] Checking pipx status...${NC}"
if command -v pipx &> /dev/null; then
    echo -e "${GREEN}✓ pipx found: $(which pipx)${NC}"
    echo -e "${GREEN}✓ pipx version: $(pipx --version)${NC}"
else
    echo -e "${RED}✗ pipx not found in PATH${NC}"
fi
echo ""

# 3. Check Python environment
echo -e "${BLUE}[3] Checking Python environment...${NC}"
if command -v python3 &> /dev/null; then
    echo -e "${GREEN}✓ Python found: $(which python3)${NC}"
    echo -e "${GREEN}✓ Python version: $(python3 --version)${NC}"
    echo -e "${GREEN}✓ pip version: $(python3 -m pip --version)${NC}"
else
    echo -e "${RED}✗ Python not found${NC}"
fi
echo ""

# 4. Check PATH
echo -e "${BLUE}[4] Checking PATH configuration...${NC}"
echo "Current PATH:"
echo "$PATH" | tr ':' '\n' | nl
echo ""
if echo "$PATH" | grep -q "/Users/vm/.local/bin"; then
    echo -e "${GREEN}✓ ~/.local/bin is in PATH${NC}"
else
    echo -e "${YELLOW}⚠ ~/.local/bin is NOT in PATH${NC}"
fi
echo ""

# 5. Check if pipx environment is set up
echo -e "${BLUE}[5] Checking pipx environment...${NC}"
if [ -d "$HOME/.local/bin" ]; then
    echo -e "${GREEN}✓ ~/.local/bin exists${NC}"
    if [ -d "$HOME/.local/pipx/venvs" ]; then
        echo -e "${GREEN}✓ pipx venvs directory exists${NC}"
        echo "Installed pipx packages:"
        pipx list 2>/dev/null || echo -e "${YELLOW}No packages installed yet${NC}"
    else
        echo -e "${YELLOW}⚠ pipx venvs directory doesn't exist yet${NC}"
    fi
else
    echo -e "${RED}✗ ~/.local/bin doesn't exist${NC}"
fi
echo ""

# 6. Try manual pipx installation with verbose output
echo -e "${BLUE}[6] Attempting manual Aider installation...${NC}"
echo -e "${YELLOW}This will show the actual error if it fails:${NC}\n"
pipx install aider-chat --verbose

echo -e "\n${GREEN}If you see this message, installation succeeded!${NC}"
