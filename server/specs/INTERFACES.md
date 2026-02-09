# private-ai-server External Interfaces

## Primary Interface

- HTTP API at `http://<tailscale-assigned-ip>:11434/v1`
- Fully OpenAI-compatible schema (chat completions endpoint)
- No custom routes or extensions in v1

## Configuration Interface

- Environment variables (primarily OLLAMA_HOST)
- launchd plist for service persistence

## Management Interface (minimal)

- Tailscale admin console (external to this monorepo) for ACLs and device approval
- Optional boot script for model pre-warming

## Intended Client Consumption Patterns (informative only)

- CLI tools that support custom OpenAI base URL
- Code editors / IDE extensions with OpenAI-compatible provider settings
- Custom scripts using HTTP requests or OpenAI SDKs with base_url override
