# private-ai-client Functionalities (v1)

## Core Functionality

- One-time installer that makes the private-ai-server API contract immediately usable by OpenAI-compatible tools
- Sets all required environment variables (see API_CONTRACT.md)
- Installs Aider and ensures it reads the contract automatically
- Uninstaller that removes only client-side changes

## After Installation

- User can run `aider` or `aider --yes` and it will connect to the server contract
- Any other tool that honors `OPENAI_API_BASE` + `OPENAI_API_KEY` will work without extra flags

## Client Responsibilities

- Guarantee that after `./scripts/install.sh`, the environment matches API_CONTRACT.md exactly
- Verify connectivity (optional test curl in installer)
- Provide clear error messages if Tailscale is not joined or tag is missing
