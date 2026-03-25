#!/usr/bin/env python3
"""Discord bot that wakes/sleeps a Mac and manages Claude Code remote-control sessions."""

import os
import time
import subprocess
import logging
import asyncio

import paramiko
import discord
from wakeonlan import send_magic_packet

# Config from environment
DISCORD_TOKEN = os.environ["DISCORD_TOKEN"]
MAC_ADDRESS = os.environ["MAC_ADDRESS"]
MAC_IP = os.environ["MAC_IP"]
MAC_USER = os.environ["MAC_USER"]
SSH_KEY_PATH = os.environ["SSH_KEY_PATH"]
# Paths on the Mac — override via env if non-standard
TMUX_PATH = os.environ.get("TMUX_PATH", "/opt/homebrew/bin/tmux")
TRIGGER_FILE = os.environ.get("TRIGGER_FILE", f"/Users/{MAC_USER}/.claude-wake-trigger")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("wake-bot")

intents = discord.Intents.default()
intents.message_content = True
client = discord.Client(intents=intents)


def ping_mac(timeout=2):
    """Return True if Mac responds to ping."""
    try:
        result = subprocess.run(
            ["ping", "-c", "1", "-W", str(timeout), MAC_IP],
            capture_output=True, timeout=timeout + 2
        )
        return result.returncode == 0
    except Exception:
        return False


def ssh_command(cmd, timeout=10):
    """Run a command on the Mac via SSH. Returns (stdout, stderr, exit_code)."""
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(
            MAC_IP, username=MAC_USER,
            key_filename=SSH_KEY_PATH, timeout=timeout
        )
        stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
        exit_code = stdout.channel.recv_exit_status()
        return stdout.read().decode().strip(), stderr.read().decode().strip(), exit_code
    except Exception as e:
        return "", str(e), -1
    finally:
        ssh.close()


def check_claude_session():
    """Check if tmux claude session exists on Mac."""
    out, err, code = ssh_command(f"{TMUX_PATH} has-session -t claude 2>/dev/null && echo YES || echo NO")
    return out == "YES"


def start_claude_remote():
    """Trigger Claude remote-control on the Mac by touching a trigger file.
    A launchd agent on the Mac watches for this file and starts
    claude remote-control in the user's GUI context (keychain access)."""
    # Kill any existing session
    ssh_command(f"{TMUX_PATH} kill-session -t claude 2>/dev/null", 5)
    time.sleep(1)
    # Touch the trigger file — launchd will pick it up
    ssh_command(f"touch {TRIGGER_FILE}", 5)
    # Wait for launchd to start remote-control
    time.sleep(15)


def send_wol(count=3, delay=2):
    """Send multiple WoL packets for Wi-Fi reliability."""
    for i in range(count):
        send_magic_packet(MAC_ADDRESS)
        log.info(f"WoL packet {i+1}/{count} sent to {MAC_ADDRESS}")
        if i < count - 1:
            time.sleep(delay)


async def handle_wake(message):
    await message.channel.send("🚀 Sending wake packets...")
    await asyncio.to_thread(send_wol, count=3, delay=2)

    await message.channel.send("⏳ Waiting for Mac to come online...")
    start = time.time()
    online = False
    while time.time() - start < 90:
        if await asyncio.to_thread(ping_mac):
            online = True
            break
        await asyncio.sleep(3)

    if not online:
        await message.channel.send("❌ Mac didn't respond after 90s. Try again or check Wi-Fi WoL settings.")
        return

    await message.channel.send("✅ Mac is online. Starting Claude remote-control...")
    await asyncio.to_thread(start_claude_remote)
    if await asyncio.to_thread(check_claude_session):
        await message.channel.send("🎉 Claude remote-control is running! Connect at https://claude.ai/code")
    else:
        await message.channel.send("⚠️ Remote-control may not have started. Check the Mac.")


async def handle_sleep(message):
    if not await asyncio.to_thread(ping_mac):
        await message.channel.send("💤 Mac is already asleep.")
        return
    await asyncio.to_thread(ssh_command, "sudo /usr/bin/pmset sleepnow")
    await message.channel.send("💤 Mac is going to sleep.")


async def handle_status(message):
    if not await asyncio.to_thread(ping_mac):
        await message.channel.send("😴 Mac is **asleep** (not responding to ping).")
        return
    has_session = await asyncio.to_thread(check_claude_session)
    if has_session:
        await message.channel.send("🟢 Mac is **awake**. Claude session: **active**.")
    else:
        await message.channel.send("🟡 Mac is **awake**. Claude session: **none**.")


async def handle_reset(message):
    if not await asyncio.to_thread(ping_mac):
        await message.channel.send("❌ Mac is not reachable. Wake it first.")
        return
    await message.channel.send("🔄 Restarting Claude remote-control...")
    await asyncio.to_thread(start_claude_remote)
    if await asyncio.to_thread(check_claude_session):
        await message.channel.send("🎉 Claude remote-control restarted! Connect at https://claude.ai/code")
    else:
        await message.channel.send("⚠️ Remote-control may not have started. Check the Mac.")


COMMANDS = {
    "wake": handle_wake,
    "sleep": handle_sleep,
    "status": handle_status,
    "reset": handle_reset,
    "ping": lambda m: m.channel.send("✅ Bot is alive!"),
    "help": lambda m: m.channel.send(
        "**Available commands:**\n"
        "• `wake` — Wake the Mac and start Claude remote-control\n"
        "• `sleep` — Put the Mac to sleep\n"
        "• `status` — Check if Mac is awake and Claude session status\n"
        "• `reset` — Restart Claude remote-control\n"
        "• `ping` — Check if the bot is running\n"
        "• `help` — Show this message"
    ),
}


@client.event
async def on_ready():
    log.info(f"Bot connected as {client.user}")


@client.event
async def on_message(message):
    # Ignore own messages
    if message.author == client.user:
        return

    # Only respond to DMs
    if not isinstance(message.channel, discord.DMChannel):
        return

    text = message.content.strip().lower()
    cmd = text.split()[0] if text else ""
    handler = COMMANDS.get(cmd)

    if handler:
        await handler(message)
    else:
        await message.channel.send(f"Unknown command: `{cmd}`. Type `help` for available commands.")


if __name__ == "__main__":
    log.info("Starting Wake Bot...")
    client.run(DISCORD_TOKEN)
