#!/bin/bash
# Registers this Mac as a Gitea Actions runner (host mode, label `macos-arm64`) and keeps it
# running with launchd, so pushes to the Gitea repo build the app automatically.
#
#   GITEA_URL=https://gitea.parseit.net RUNNER_TOKEN=<registration token> ./scripts/setup-macos-runner.sh
#
# Get the registration token in Gitea: Site Administration (or the repo/org) › Actions › Runners ›
# Create new runner.
set -euo pipefail

GITEA_URL="${GITEA_URL:-https://gitea.parseit.net}"
RUNNER_NAME="${RUNNER_NAME:-$(scutil --get LocalHostName)-macos}"
RUNNER_LABELS="${RUNNER_LABELS:-macos-arm64:host}"
RUNNER_HOME="${RUNNER_HOME:-$HOME/.gitea-runner}"
: "${RUNNER_TOKEN:?Set RUNNER_TOKEN to a runner registration token from Gitea}"

# Homebrew ships the runner as `gitea-runner` (formerly `act_runner`).
RUNNER_BIN="$(command -v gitea-runner || command -v act_runner || true)"
if [[ -z "$RUNNER_BIN" ]]; then
    echo "Installing gitea-runner with Homebrew…"
    brew install gitea-runner
    RUNNER_BIN="$(command -v gitea-runner)"
fi
# JavaScript actions (actions/checkout, upload-artifact) need node on the host.
NODE_DIR="$(dirname "$(command -v node || echo /opt/homebrew/bin/node)")"

mkdir -p "$RUNNER_HOME"
cd "$RUNNER_HOME"
if [[ ! -f .runner ]]; then
    "$RUNNER_BIN" register --no-interactive \
        --instance "$GITEA_URL" --token "$RUNNER_TOKEN" \
        --name "$RUNNER_NAME" --labels "$RUNNER_LABELS"
fi

PLIST="$HOME/Library/LaunchAgents/net.parseit.gitea-runner.plist"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>net.parseit.gitea-runner</string>
    <key>ProgramArguments</key>
    <array><string>$RUNNER_BIN</string><string>daemon</string></array>
    <key>WorkingDirectory</key><string>$RUNNER_HOME</string>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>$NODE_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$RUNNER_HOME/runner.log</string>
    <key>StandardErrorPath</key><string>$RUNNER_HOME/runner.log</string>
</dict>
</plist>
PLIST
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Runner '$RUNNER_NAME' ($RUNNER_LABELS) is running. Log: $RUNNER_HOME/runner.log"
