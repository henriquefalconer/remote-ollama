# private-ai-client – Setup Instructions (macOS)

## 1. Clone the repository

```bash
git clone https://github.com/yourusername/private-ai-api.git
cd private-ai-api/client
```

## 2. Run the installer

```bash
./scripts/install.sh
```

The installer will:
- Check/install Homebrew, Python, Tailscale
- Open Tailscale for login and device approval
- Prompt for server hostname (default: `private-ai-server`)
- Create `~/.private-ai-client/env` with required environment variables
- Update your shell profile (~/.zshrc) to source the environment
- Install Aider via pipx
- Run a connectivity test

## 3. Open a new terminal

```bash
exec $SHELL
```

Or simply open a new terminal window.

## 4. Verify installation

```bash
# Check environment variables
echo $OLLAMA_API_BASE          # http://private-ai-server:11434/v1
echo $OPENAI_API_BASE          # http://private-ai-server:11434/v1
echo $OPENAI_API_KEY           # ollama

# Check Aider
aider --version

# Test server connectivity (if server is running and you have access)
curl $OLLAMA_API_BASE/models
```

## 5. Use

```bash
aider                     # interactive mode - uses server automatically
aider --yes               # YOLO mode
```

## Uninstall

```bash
./scripts/uninstall.sh
```

## Troubleshooting

### "Connection refused" when testing connectivity

- Ensure Tailscale is connected and logged in
- Verify you have been granted the appropriate tag in Tailscale ACLs
- Check that the server hostname matches your Tailscale configuration
- Confirm the server is running and accessible

### Environment variables not set

- Ensure you opened a new terminal after installation
- Check that `~/.private-ai-client/env` exists
- Verify `~/.zshrc` has the sourcing line: `source ~/.private-ai-client/env`

### Aider not found

- Ensure pipx is installed: `brew install pipx`
- Ensure pipx path is in your PATH
- Try `pipx ensurepath` and open a new terminal

## The client is now fully configured

All tools respecting the OpenAI API contract will work with zero per-session configuration.
