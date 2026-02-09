# private-ai-server Architecture

## Core Principles

- Provide an OpenAI-compatible LLM inference API endpoint
- Run exclusively on a dedicated, always-on machine (separate from clients)
- Zero public internet exposure
- Zero third-party cloud dependencies
- Minimal external dependencies (primarily Ollama + secure network overlay)
- Native macOS service management via launchd
- Access restricted to explicitly authorized client devices only

## Intended Deployment Context

- Apple Silicon Mac (M-series) with high unified memory capacity (≥96 GB strongly recommended)
- 24/7 operation with uninterruptible power supply
- High upload bandwidth network connection (≥100 Mb/s recommended for low-latency streaming worldwide)
- The server machine is **not** the development or usage workstation — clients connect remotely

## Server Responsibilities

- Expose `/v1` OpenAI-compatible API routes (chat/completions, etc.)
- Bind the API listener to all network interfaces (including private overlay network)
- Handle model loading, inference, and unloading automatically
- Support streaming responses, JSON mode, tool calling (when model supports it)

## Network & Access Model

- Use Tailscale (or equivalent secure overlay VPN) for all remote access
- No port forwarding, no dynamic DNS, no public IP binding
- Tailscale ACLs enforce per-device or per-tag authorization

## Out of Scope for v1

- Built-in authentication proxy / API keys
- Web-based chat UI
- Automatic model quantization or conversion
- Load balancing across multiple inference nodes
- Monitoring / metrics endpoint
