# private-ai-client Scripts

## scripts/install.sh

- Checks / installs Homebrew, Python, Tailscale
- Opens Tailscale app for login + device approval
- Prompts for server hostname (default: private-ai-server)
- Creates `~/.private-ai-client/env` with exact variables from API_CONTRACT.md
- Appends `source ~/.private-ai-client/env` to `~/.zshrc` (with user consent)
- Installs Aider via pipx (isolated, no global pollution)
- Runs a connectivity test using the contract

## scripts/uninstall.sh

- Removes Aider
- Deletes `~/.private-ai-client`
- Comments out or removes the sourcing line from shell profile
- Leaves Tailscale and Homebrew untouched

## config/env.template

- Template showing the exact variables required by the contract
- Used by install.sh to create `~/.private-ai-client/env`
