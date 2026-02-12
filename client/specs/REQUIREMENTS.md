# self-sovereign-ollama ai-client Requirements (v2.0.0)

## macOS

- macOS 14 Sonoma or later
- zsh (default) or bash

## Prerequisites (installer enforces)

- Homebrew
- Python 3.10+ (installed via Homebrew if missing)
- **WireGuard client** (installed via Homebrew)

## No sudo required

Except for:
- Homebrew/WireGuard installation if chosen by user
- WireGuard VPN connection (may require elevated privileges depending on installation method)

## VPN Configuration

- **WireGuard keypair**: Generated during installation (client keeps private key)
- **Router admin step**: User must send public key to router admin to be added as VPN peer
- **VPN connection**: Required to access server (can be connected/disconnected as needed)

## Shell Profile Modification

The installer will modify your shell profile (`~/.zshrc` for zsh or `~/.bashrc` for bash) to automatically source the environment file (`~/.ai-client/env`). This modification:
- Requires explicit user consent during installation
- Uses marker comments for clean removal by uninstaller
- Ensures environment variables are available in all new shell sessions
- Optionally adds `claude-ollama` alias for easy backend switching
