# remote-ollama-proxy ai-client Repository Layout

## Core Files (v1 - Aider)

```
client/
├── specs/
│   ├── API_CONTRACT.md        # Server interface for OpenAI + Anthropic APIs
│   ├── ARCHITECTURE.md        # Client architecture and responsibilities
│   ├── FUNCTIONALITIES.md     # Core and extended functionalities
│   ├── REQUIREMENTS.md         # System requirements
│   ├── SCRIPTS.md              # Script specifications
│   ├── FILES.md                # This file
│   ├── CLAUDE_CODE.md          # Claude Code integration specification (v2+)
│   ├── ANALYTICS.md            # Ralph loop analytics infrastructure (v2+)
│   └── VERSION_MANAGEMENT.md   # Version compatibility management (v2+)
├── scripts/
│   ├── install.sh              # One-time installer (Aider + optional Claude Code setup)
│   ├── uninstall.sh            # Clean uninstaller
│   ├── test.sh                 # Comprehensive client functionality tests
│   ├── check-compatibility.sh  # Verify Claude Code + Ollama version compatibility (v2+)
│   ├── pin-versions.sh         # Pin tools to known-working versions (v2+)
│   └── downgrade-claude.sh     # Rollback Claude Code if update breaks (v2+)
├── config/
│   └── env.template            # Environment variable template
├── SETUP.md                    # User setup guide
└── README.md                   # Overview and quick start
```

## Ralph Loop Files (v2+ - Claude Code)

**Located in project root** (not client/ subdirectory):

```
./
├── PROMPT_plan.md              # Planning phase prompt (Opus)
├── PROMPT_build.md             # Build phase prompt (Sonnet)
├── loop.sh                     # Standard Ralph loop runner
├── loop-with-analytics.sh      # Enhanced loop runner with analytics
├── compare-analytics.sh        # Compare analytics between runs
├── ANALYTICS_README.md         # Analytics user guide
└── analytics/                  # Analytics output directory
    └── run-TIMESTAMP/          # Per-run directory
        ├── iteration-N.json    # Raw Claude Code output
        ├── iteration-N-analysis.txt  # Parsed metrics
        └── summary.md          # Aggregate report
```

**Rationale for root location**:
- Ralph loops orchestrate both client and server components
- PROMPT files are project-level, not client-specific
- Analytics measure full system behavior, not just client

## Runtime Artifacts

**Client-specific** (`~/.ai-client/`):
```
~/.ai-client/
├── env                         # Generated environment configuration
├── uninstall.sh                # Copied for curl-pipe users
└── .version-lock               # Version compatibility record (v2+)
```

**Shell profile modifications**:
```
~/.zshrc or ~/.bashrc
├── # >>> ai-client >>>
│   source ~/.ai-client/env
│   # <<< ai-client <<<
└── # >>> claude-ollama >>>    # Optional (v2+)
    alias claude-ollama='...'
    # <<< claude-ollama <<<
```

## No Compiled Code

All functionality implemented as:
- Shell scripts (bash)
- Python tools (Aider, installed via pipx)
- CLI tools (Claude Code, installed separately)
- Configuration files (text)

No binaries, no native code, no additional build dependencies.
