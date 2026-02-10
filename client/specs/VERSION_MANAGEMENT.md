# Version Compatibility Management Specification

## Problem Statement

### The Compatibility Challenge

When using Claude Code with Ollama's Anthropic compatibility layer:

1. **Claude Code updates frequently** - New features, API changes, bug fixes
2. **Ollama's Anthropic API is experimental** - Compatibility layer under active development
3. **Anthropic API evolves** - Anthropic may add required fields, change behaviors
4. **No guarantees** - Ollama may lag behind Anthropic API changes

**Risk**: Claude Code update may require Anthropic API features that Ollama doesn't support yet, breaking the integration.

### Failure Modes

**Scenario A: Required API field**
```
Claude Code 2.2.0 released
  → Adds required `anthropic-client-id` header
  → Ollama doesn't support it yet
  → Integration breaks until Ollama catches up (days-weeks)
```

**Scenario B: tool_choice enforcement**
```
Claude Code starts requiring tool_choice for reliability
  → Ollama doesn't support tool_choice parameter
  → Tool use becomes unreliable or fails
  → Ralph loops break
```

**Scenario C: Authentication changes**
```
Anthropic API changes auth flow
  → Claude Code adopts new flow
  → Ollama still uses old pattern
  → Authentication fails
```

### Risk Assessment

**Probability over 12 months**:
- 15% - Claude Code requires new Anthropic feature
- 10% - Tool use API changes
- 5% - Authentication changes
- **~30% total** - Some breaking change

**Impact**:
- Development blocked until fix
- Time lost troubleshooting
- Potential data loss if breaking mid-task
- Lost confidence in local backend option

## Solution Architecture

Three-layer defense:

1. **Version pinning** - Lock to known-working versions
2. **Compatibility checking** - Verify versions before use
3. **Quick rollback** - Downgrade if update breaks

## Components

### 1. Compatibility Matrix

**Data structure** (embedded in `check-compatibility.sh`):
```bash
declare -A COMPATIBLE_VERSIONS=(
    ["2.1.38"]="0.5.4"  # Claude Code 2.1.38 works with Ollama 0.5.4
    ["2.1.39"]="0.5.5"  # Add entries as combinations tested
)
```

**Update procedure**:
1. Test new Claude Code version with current Ollama
2. If works, add to matrix
3. If breaks, document issue and wait for Ollama update
4. Re-test and add when fixed

### 2. Check Script

**`client/scripts/check-compatibility.sh`**

**Purpose**: Verify current Claude Code and Ollama versions are tested together

**Usage**:
```bash
./client/scripts/check-compatibility.sh
```

**Output**:
```
=== Claude Code + Ollama Compatibility Checker ===

✓ Claude Code installed: v2.1.38
✓ Ollama server reachable: v0.5.4

✓ COMPATIBLE
Claude Code v2.1.38 works with Ollama v0.5.4
```

**Exit codes**:
- `0` - Compatible
- `1` - Tool not found / server unreachable
- `2` - Version mismatch (wrong Ollama version for Claude Code version)
- `3` - Unknown compatibility (not tested)

**Behavior on mismatch**:
```
⚠ VERSION MISMATCH
Claude Code v2.1.39 is tested with Ollama v0.5.5
But your server has v0.5.4

Recommendation: Update Ollama on server to v0.5.5
  On the server, run: brew upgrade ollama
```

**Behavior on unknown**:
```
⚠ UNKNOWN COMPATIBILITY
Claude Code v2.2.0 has not been tested with Ollama

Proceed with caution. Test basic functionality:
  claude-ollama --model qwen3-coder

If it works, add to compatibility matrix:
  Edit client/scripts/check-compatibility.sh
  Add: ["2.2.0"]="0.5.5"
```

### 3. Pin Script

**`client/scripts/pin-versions.sh`**

**Purpose**: Lock Claude Code and Ollama to current versions

**Usage**:
```bash
./client/scripts/pin-versions.sh
```

**Actions**:

**For Claude Code (client machine)**:
```bash
# If installed via npm
npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION}

# If installed via Homebrew
brew pin claude-code
```

**For Ollama (server machine)**:
```bash
# Display instructions (user must run on server)
echo "Run this on your server (ai-server):"
echo "  brew pin ollama"
echo ""
echo "Or for Docker:"
echo "  docker pull ollama/ollama:${OLLAMA_VERSION}"
```

**Creates version lock file** (`~/.ai-client/.version-lock`):
```bash
# Version lock for Claude Code + Ollama compatibility
# Generated: 2026-02-10 14:30:22
CLAUDE_CODE_VERSION=2.1.38
OLLAMA_VERSION=0.5.4
TESTED_DATE=2026-02-10
STATUS=working
```

**Purpose of lock file**:
- Reference for known-working versions
- Used by downgrade script
- Historical record for troubleshooting

### 4. Downgrade Script

**`client/scripts/downgrade-claude.sh`**

**Purpose**: Rollback Claude Code to last known-working version

**Usage**:
```bash
./client/scripts/downgrade-claude.sh
```

**Prerequisites**: `.version-lock` file must exist (created by pin-versions.sh)

**Behavior**:
```
=== Claude Code Downgrade Tool ===

This will downgrade Claude Code to last known working version
  Target version: v2.1.38

Continue? (y/N)
```

If confirmed:
```bash
# If npm installation
npm install -g @anthropic-ai/claude-code@2.1.38

# If Homebrew
echo "Homebrew doesn't support easy downgrades"
echo "Manual steps:"
echo "  1. brew unlink claude-code"
echo "  2. brew install https://raw.githubusercontent.com/.../claude-code.rb"
echo ""
echo "Or install via npm instead:"
echo "  npm install -g @anthropic-ai/claude-code@2.1.38"
```

**Verification**:
```bash
NEW_VERSION=$(claude --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
if [[ "$NEW_VERSION" == "$CLAUDE_CODE_VERSION" ]]; then
    echo "✓ Successfully downgraded to v${NEW_VERSION}"
else
    echo "✗ Downgrade failed. Current version: v${NEW_VERSION}"
fi
```

## Operational Procedures

### Initial Setup

**When first configuring Ollama backend**:

```bash
# 1. Test basic functionality
claude-ollama --model qwen3-coder
# Try simple prompt: "Hello, count from 1 to 5"

# 2. If works, record versions
./client/scripts/pin-versions.sh

# 3. Add to compatibility matrix
edit client/scripts/check-compatibility.sh
# Add: ["2.1.38"]="0.5.4"
```

### Before Updating Claude Code

**Always check compatibility first**:

```bash
# 1. Check current status
./client/scripts/check-compatibility.sh

# 2. Update Claude Code
npm update -g @anthropic-ai/claude-code

# 3. Check again
./client/scripts/check-compatibility.sh
# If UNKNOWN, proceed to testing

# 4. Test with Ollama
claude-ollama --model qwen3-coder
# Try simple task

# 5. If works, update matrix and re-pin
# If breaks, downgrade immediately
./client/scripts/downgrade-claude.sh
```

### After Breaking Update

**Recovery procedure**:

```bash
# 1. Downgrade to last working version
./client/scripts/downgrade-claude.sh

# 2. Verify working again
claude-ollama --model qwen3-coder

# 3. Document the issue
# Edit IMPLEMENTATION_PLAN.md or create GitHub issue

# 4. Monitor for fix
# Check Ollama releases for compatibility update
gh release list --repo ollama/ollama | grep anthropic

# 5. Re-test when fix available
# Update Ollama on server
On the server, run: brew upgrade ollama

# Test again
claude-ollama --model qwen3-coder

# 6. Update matrix if fixed
# Add new compatible versions to check-compatibility.sh
```

### Periodic Maintenance

**Monthly check** (recommended):

```bash
# 1. Check for updates
npm outdated -g @anthropic-ai/claude-code
On the server, run: brew outdated ollama

# 2. If updates available, check compatibility
./client/scripts/check-compatibility.sh

# 3. Read release notes
# Claude Code: https://github.com/anthropics/claude-code/releases
# Ollama: https://github.com/ollama/ollama/releases

# 4. Test in staging first (if critical)
# Create separate test directory
mkdir ~/claude-ollama-test
cd ~/claude-ollama-test
# Test new versions

# 5. Update production if stable
# Update, pin, add to matrix
```

## Failure Detection

### Symptoms of Breaking Change

**Tool use failures**:
```
Error: Tool use failed
Error: Invalid tool_use block
Error: Unsupported parameter: tool_choice
```

**Authentication failures**:
```
Error: Invalid API key format
Error: Missing required header: anthropic-client-id
Error: Authentication failed
```

**API incompatibility**:
```
Error: Unsupported endpoint: /v1/messages/count_tokens
Error: Invalid request format
Error: Missing required field: metadata
```

**Silent degradation**:
- Tool calls ignored
- No streaming (despite request)
- Missing thinking blocks
- Lower quality output (hard to detect)

### Diagnostic Steps

1. **Check versions**:
   ```bash
   ./client/scripts/check-compatibility.sh
   ```

2. **Test with known-good model**:
   ```bash
   echo "Hello" | claude-ollama --model qwen3-coder
   ```

3. **Check Ollama server logs**:
   ```bash
   On the server, run: tail -100 /tmp/ollama.stderr.log
   ```

4. **Test with Anthropic cloud API**:
   ```bash
   claude --model sonnet  # Should work if Claude Code is fine
   ```

5. **Compare versions with compatibility matrix**:
   - Check `client/scripts/check-compatibility.sh`
   - Look for your Claude Code version

## Stability Guarantees

### What This System Provides

✅ **Detection**: Know immediately when versions incompatible
✅ **Rollback**: Quick recovery to last working state
✅ **Documentation**: Clear record of tested combinations
✅ **Procedure**: Step-by-step response to breaks

### What This System Does NOT Provide

❌ **Prevention**: Cannot prevent Anthropic or Ollama from making breaking changes
❌ **Automatic fixing**: Manual intervention required to test and update
❌ **Perfect compatibility**: No guarantee any version pair will work forever
❌ **Anthropic parity**: Ollama will always lag behind real Anthropic API

## Alternative: Hybrid Approach

### Strategy

Instead of relying entirely on Ollama backend compatibility:

**Keep Anthropic cloud API as primary**:
```bash
claude --model opus-4-6          # Cloud (always works)
```

**Use Ollama for non-critical tasks only**:
```bash
claude-ollama --model qwen3-coder  # Local (may break)
```

**Benefits**:
- No critical dependency on Ollama compatibility
- Breaking changes only affect optional workflow
- Can wait for fixes without blocking work

**Trade-offs**:
- Still pay for Anthropic API
- Don't get full privacy benefit
- More complex mental model

## Recommended Practice

### Production Environments

1. **Pin everything**:
   ```bash
   ./client/scripts/pin-versions.sh
   ```

2. **Test updates in staging first**
3. **Keep fallback to Anthropic cloud API**
4. **Monitor release notes**:
   - https://github.com/anthropics/claude-code/releases
   - https://github.com/ollama/ollama/releases

5. **Document all version changes in version control**

### Development Environments

1. **More flexibility** - Can test updates immediately
2. **Still check compatibility** before critical work
3. **Report issues** to respective projects
4. **Contribute to compatibility matrix**

## Future Improvements

### Potential Enhancements

1. **Automated testing**: CI job that tests new versions
2. **Compatibility API**: Central registry of known-working versions
3. **Notification system**: Alert when new compatible versions available
4. **Compatibility score**: Beyond binary (works/doesn't), rate quality
5. **Community matrix**: Crowdsourced compatibility data

### Out of Scope

- Building compatibility shims (too complex, fragile)
- Forking Claude Code or Ollama (maintenance burden)
- Implementing Anthropic API ourselves (massive undertaking)

## Summary

Version management provides:
- **Safety**: Detect incompatibilities before they break workflows
- **Stability**: Pin to known-working versions
- **Recovery**: Quick rollback if updates break
- **Confidence**: Use Ollama backend knowing you can recover

**Critical for production use** of Ollama backend with Claude Code.
