#!/bin/bash
# Launched by launchd when ~/.claude-wake-trigger is created.
# Runs in the GUI user context so keychain access works.

USER_HOME="$HOME"
TRIGGER="$USER_HOME/.claude-wake-trigger"
LOG="$USER_HOME/.wakeup.log"

# Detect tmux and claude paths
TMUX="$(command -v tmux || echo /opt/homebrew/bin/tmux)"
CLAUDE="$(command -v claude || echo "$USER_HOME/.local/bin/claude")"

# Remove trigger file immediately
rm -f "$TRIGGER"

echo "$(date): Wake launcher triggered" >> "$LOG"

# Skip if remote-control is already running
if $TMUX has-session -t claude 2>/dev/null; then
  echo "$(date): Claude session already exists, skipping" >> "$LOG"
  exit 0
fi

# Start claude remote-control as a persistent server
# Trust was pre-accepted by running `claude` once in ~
$TMUX new-session -d -s claude
SESSION_NAME="Mac Wake $(date '+%b %d %-I:%M%p')"
$TMUX send-keys -t claude "unset CLAUDECODE; cd ~ && $CLAUDE remote-control --name '$SESSION_NAME'" Enter

echo "$(date): Claude remote-control started" >> "$LOG"
