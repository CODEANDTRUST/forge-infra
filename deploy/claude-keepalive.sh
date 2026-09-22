#!/bin/bash
# Keep-alive probe: refresh Claude + Codex OAuth before forge jobs need them.
# Fails loudly to log; Tron checks during heartbeats.
LOG="$HOME/.forge-pr/keepalive.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

# Claude: minimal authenticated call
C_OUT=$(/opt/homebrew/bin/claude -p "reply with exactly: ok" 2>&1 | tail -1)
C_RC=$?
if [ $C_RC -eq 0 ] && [ "$C_OUT" != "Failed to authenticate*" ]; then
  echo "$TS claude: ok" >> "$LOG"
else
  echo "$TS claude: FAIL ($C_OUT)" >> "$LOG"
fi

# Codex: minimal authenticated call
X_OUT=$(/opt/homebrew/bin/codex exec --ephemeral --skip-git-repo-check -m gpt-6-astra "reply with exactly: ok" 2>&1 | tail -1)
X_RC=$?
if [ $X_RC -eq 0 ]; then
  echo "$TS codex: ok" >> "$LOG"
else
  echo "$TS codex: FAIL ($X_OUT)" >> "$LOG"
fi
