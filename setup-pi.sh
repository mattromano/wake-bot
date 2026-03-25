#!/bin/bash
set -e

echo "=== Wake Bot — Pi Setup ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Install system deps
echo "Installing system dependencies..."
sudo apt update -qq
sudo apt install -y -qq wakeonlan python3-pip python3-venv

# 2. Create venv and install Python deps
echo "Setting up Python environment..."
cd "$SCRIPT_DIR"
python3 -m venv venv
./venv/bin/pip install --quiet -r pi/requirements.txt
echo "Python dependencies installed"

# 3. Generate SSH key
if [ ! -f ~/.ssh/mac_wake ]; then
  echo "Generating SSH key for Mac access..."
  mkdir -p ~/.ssh
  ssh-keygen -t ed25519 -f ~/.ssh/mac_wake -N ""
fi
echo ""
echo "=== Add this public key to the Mac's ~/.ssh/authorized_keys ==="
cat ~/.ssh/mac_wake.pub
echo ""

# 4. Create .env from template if not exists
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  cp "$SCRIPT_DIR/pi/.env.example" "$SCRIPT_DIR/.env"
  echo "Created .env from template — edit it with your values"
else
  echo ".env already exists, skipping"
fi

# 5. Install systemd service
echo "Installing systemd service..."
# Update service file paths to match actual install location
sed -e "s|WorkingDirectory=.*|WorkingDirectory=$SCRIPT_DIR|" \
    -e "s|EnvironmentFile=.*|EnvironmentFile=$SCRIPT_DIR/.env|" \
    -e "s|ExecStart=.*|ExecStart=$SCRIPT_DIR/venv/bin/python $SCRIPT_DIR/pi/wake_bot.py|" \
    -e "s|User=.*|User=$(whoami)|" \
    "$SCRIPT_DIR/pi/wake-bot.service" | sudo tee /etc/systemd/system/wake-bot.service >/dev/null

sudo systemctl daemon-reload
sudo systemctl enable wake-bot
echo "Service installed and enabled"

echo ""
echo "=== Next Steps ==="
echo "1. Add the SSH public key above to the Mac's ~/.ssh/authorized_keys"
echo "2. Test SSH: ssh -i ~/.ssh/mac_wake <MAC_USER>@<MAC_IP> echo OK"
echo "3. Test WoL: wakeonlan <MAC_ADDRESS>"
echo "4. Edit $SCRIPT_DIR/.env with your Discord token and Mac details"
echo "5. Start the bot: sudo systemctl start wake-bot"
echo "6. Check status: sudo systemctl status wake-bot"
echo ""
echo "=== Pi setup complete ==="
