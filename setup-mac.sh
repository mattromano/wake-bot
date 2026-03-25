#!/bin/bash
set -e

echo "=== Wake Bot — Mac Setup ==="
echo ""

USERNAME=$(whoami)
HOME_DIR="$HOME"

# 1. Check prerequisites
echo "Checking prerequisites..."

if ! command -v claude &>/dev/null; then
  echo "ERROR: Claude Code CLI not found. Install it first: https://claude.ai/download"
  exit 1
fi

WOL=$(pmset -g | grep womp | awk '{print $2}')
if [ "$WOL" != "1" ]; then
  echo "WARNING: Wake-on-LAN is not enabled."
  echo "Enable it: System Settings → Energy → Wake for network access"
  echo ""
fi

# 2. Collect Mac info
MAC_ADDR=$(ifconfig en0 | grep ether | awk '{print $2}')
MAC_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "NOT_FOUND")
echo ""
echo "=== Mac Info ==="
echo "MAC address: $MAC_ADDR"
echo "Current IP:  $MAC_IP"
echo "Username:    $USERNAME"
echo ""
echo "Save these values — you'll need them for the Pi setup."
echo ""

# 3. Install SleepWatcher
if ! command -v sleepwatcher &>/dev/null; then
  echo "Installing SleepWatcher..."
  brew install sleepwatcher
fi
brew services start sleepwatcher 2>/dev/null || true
echo "SleepWatcher: installed and running"

# 4. Install wake scripts
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cp "$SCRIPT_DIR/mac/wakeup" "$HOME_DIR/.wakeup"
chmod +x "$HOME_DIR/.wakeup"
echo "Installed ~/.wakeup"

cp "$SCRIPT_DIR/mac/claude-wake-launcher.sh" "$HOME_DIR/.claude-wake-launcher.sh"
chmod +x "$HOME_DIR/.claude-wake-launcher.sh"
echo "Installed ~/.claude-wake-launcher.sh"

# 5. Install launchd agent
PLIST_NAME="com.${USERNAME}.claude-wake"
PLIST_PATH="$HOME_DIR/Library/LaunchAgents/${PLIST_NAME}.plist"

sed -e "s|__USERNAME__|${USERNAME}|g" -e "s|__HOME__|${HOME_DIR}|g" \
  "$SCRIPT_DIR/mac/claude-wake.plist.template" > "$PLIST_PATH"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
echo "Installed and loaded launchd agent: $PLIST_NAME"

# 6. Passwordless sudo for pmset sleepnow
SUDOERS_FILE="/etc/sudoers.d/pmset-wake-bot"
if [ ! -f "$SUDOERS_FILE" ]; then
  echo ""
  echo "Setting up passwordless sudo for 'pmset sleepnow'..."
  echo "(This only allows the sleep command — nothing else)"
  echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pmset sleepnow" | sudo tee "$SUDOERS_FILE" >/dev/null
  sudo chmod 440 "$SUDOERS_FILE"
  echo "Created $SUDOERS_FILE"
fi

# 7. Prepare SSH authorized_keys
mkdir -p "$HOME_DIR/.ssh"
chmod 700 "$HOME_DIR/.ssh"
touch "$HOME_DIR/.ssh/authorized_keys"
chmod 600 "$HOME_DIR/.ssh/authorized_keys"
echo "Prepared ~/.ssh/authorized_keys"

# 8. Pre-accept Claude workspace trust
echo ""
echo "=== IMPORTANT: Accept Workspace Trust ==="
echo "Run this in a separate terminal to pre-accept the trust dialog for ~:"
echo ""
echo "  cd ~ && claude"
echo ""
echo "Accept the trust prompt, then type /exit."
echo "This only needs to be done once."

# 9. Remind about SSH
echo ""
echo "=== Manual Steps ==="
echo "1. Enable SSH: System Settings → General → Sharing → Remote Login → ON"
echo "2. Set a DHCP reservation for IP $MAC_IP → MAC $MAC_ADDR in your router"
echo "3. After Pi setup, add the Pi's SSH public key to ~/.ssh/authorized_keys"
echo ""
echo "=== Mac setup complete ==="
