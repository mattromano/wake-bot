# Wake Bot

Wake a sleeping Mac and start a [Claude Code](https://claude.ai/code) remote-control session by sending a Discord message. A Raspberry Pi on the same LAN listens for commands, sends Wake-on-LAN packets, and triggers `claude remote-control` on the Mac.

## Architecture

```
Phone (Discord DM) → Discord API → Raspberry Pi → WoL magic packet → Mac wakes
                                                                       ↓
Phone (claude.ai/code) ← Anthropic relay ← claude remote-control ← launchd trigger
```

## Prerequisites

- **Mac** with Claude Code CLI installed and authenticated
- **Raspberry Pi** (or any always-on Linux box) on the same LAN as the Mac
- **Discord** account (for the bot)

## Quick Start

### 1. Create a Discord Bot

1. Go to [discord.com/developers/applications](https://discord.com/developers/applications) → **New Application** → name it "Wake Bot"
2. **Bot** tab → Reset Token → copy the token
3. Enable **Message Content Intent** under Privileged Gateway Intents
4. **OAuth2** → URL Generator → select `bot` scope + `Send Messages` permission → open the generated URL to invite to your server

### 2. Set Up the Mac

```bash
git clone https://github.com/YOUR_USERNAME/wake-bot.git
cd wake-bot
./setup-mac.sh
```

The script will:
- Verify Wake-on-LAN is enabled
- Install and start SleepWatcher
- Create the wake trigger scripts and launchd agent
- Set up passwordless `pmset sleepnow` for remote sleep
- Prepare `~/.ssh/authorized_keys` for the Pi's SSH key
- Pre-accept the Claude Code workspace trust dialog

**You must also:**
- Enable SSH: System Settings → General → Sharing → Remote Login → ON
- Set a static IP / DHCP reservation for the Mac in your router

### 3. Set Up the Raspberry Pi

```bash
# Copy the repo to the Pi (or clone it there)
scp -r wake-bot/ pi@<PI_IP>:/home/pi/wake-bot/

# SSH in and run setup
ssh pi@<PI_IP>
cd /home/pi/wake-bot
./setup-pi.sh
```

The script will:
- Install system dependencies (`wakeonlan`, `python3-venv`)
- Create a Python venv and install packages
- Generate an SSH key for Mac access
- Create a `.env` template for you to fill in
- Install the systemd service

### 4. Connect the Pi to the Mac

1. Copy the Pi's public key (printed by `setup-pi.sh`) to the Mac's `~/.ssh/authorized_keys`
2. Test SSH: `ssh -i ~/.ssh/mac_wake <MAC_USER>@<MAC_IP> echo "OK"`
3. Test WoL: `wakeonlan <MAC_ADDRESS>`
4. Fill in `/home/pi/wake-bot/.env` with your Discord token and Mac details
5. Start the bot: `sudo systemctl start wake-bot`

### 5. Test

DM "Wake Bot" on Discord:
- `status` — should report Mac is awake, no Claude session
- `sleep` — puts the Mac to sleep
- `wake` — wakes the Mac, starts `claude remote-control`
- Open [claude.ai/code](https://claude.ai/code) to connect

## Commands

| Command | Description |
|---------|-------------|
| `wake` | Wake the Mac + start claude remote-control |
| `sleep` | Put the Mac to sleep |
| `status` | Check if Mac is awake and session status |
| `reset` | Restart claude remote-control |
| `ping` | Check if the bot is running |
| `help` | Show available commands |

## How It Works

### The Keychain Problem

`claude remote-control` needs access to the macOS login keychain for authentication. SSH sessions from the Pi don't have keychain access. The solution:

1. Pi SSHes into Mac and touches a **trigger file** (`~/.claude-wake-trigger`)
2. A **launchd agent** watches for this file and runs a launcher script
3. The launcher runs in the GUI user context → has keychain access
4. It starts `claude remote-control` inside a tmux session

### The Trust Prompt

Claude Code shows a workspace trust dialog the first time you run it in a directory. The Mac setup script pre-accepts this by running `claude` once in `~`. If you see trust prompts after setup, run `claude` manually in `~`, accept, then `/exit`.

## File Layout

```
wake-bot/
├── README.md
├── pi/
│   ├── wake_bot.py          # Discord bot
│   ├── requirements.txt     # Python dependencies
│   ├── .env.example         # Environment template
│   └── wake-bot.service     # systemd unit
├── mac/
│   ├── claude-wake-launcher.sh    # Launched by launchd
│   ├── claude-wake.plist          # launchd agent (template)
│   └── wakeup                     # SleepWatcher hook
├── setup-mac.sh             # Mac setup script
└── setup-pi.sh              # Pi setup script
```

## Troubleshooting

**WoL doesn't wake the Mac:**
- Wi-Fi WoL is less reliable than Ethernet. The bot sends 3 packets with 2s delays.
- Verify WoL is enabled: `pmset -g | grep womp` (should be 1)
- Try Ethernet if Wi-Fi consistently fails

**"Unable to create remote session":**
- Claude can't access the keychain. Make sure the launchd agent is loaded: `launchctl list | grep claude-wake`
- Reload: `launchctl unload ~/Library/LaunchAgents/com.USER.claude-wake.plist && launchctl load ~/Library/LaunchAgents/com.USER.claude-wake.plist`

**Trust prompt blocks automation:**
- Run `claude` manually in `~`, accept the trust dialog, then `/exit`

**Bot not responding on Discord:**
- Check Pi: `sudo systemctl status wake-bot`
- Check logs: `journalctl -u wake-bot -f`
