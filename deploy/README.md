# Forge deployment artifacts

This directory is the source of truth for the path router, OAuth keepalive probe
and six macOS LaunchAgents. The scripts and plists are verbatim snapshots of the current
host. Keep `~/.forge-pr/router.js` as the runtime copy; sync it from this directory
when deploying changes.

The router listens on `127.0.0.1:8080` for the `forge.gitgraphs.dev` tunnel.
It matches prefixes in order: `/mcp` and `/webhooks/agentmail` go to
`127.0.0.1:3000` (forge-issue), then `/webhook` goes to `127.0.0.1:8787`
(forge-pr). Unmatched paths return 404; an unavailable upstream returns 502.

## Prerequisites

These plists use **host-specific absolute paths under `/Users/tron`**, including
HOME, working directories, scripts, configuration and logs. On another host,
adapt the paths in the source plists before installing. The commands below run
as that user in a logged-in macOS GUI session, without `sudo`.

Restore the applications, their dependencies and private configuration first:

| Agent | Required entry point | Working directory / configuration |
| --- | --- | --- |
| `com.forge-pr` | `/Users/tron/.forge-pr/start.sh` | `/Users/tron/forge/forge-pr` |
| `com.forge-issue` | `/Users/tron/.openclaw/workspace/forge-issue/start.sh` | `/Users/tron/.openclaw/workspace/forge-issue` |
| `com.forge-code` | `/Users/tron/.openclaw/workspace/forge-code/start.sh` | `/Users/tron/.openclaw/workspace/forge-code` |
| `com.forge-trace` | `/Users/tron/.openclaw/workspace/forge-issue/runtime/trace-sidecar.js` | `FORGE_CONFIG=/Users/tron/.openclaw/workspace/forge-issue/forge.config.json` |
| `com.forge-router` | `/Users/tron/.forge-pr/router.js` | No working directory required |

The three `start.sh` files run with `/bin/sh`; trace and router require Node at
`/opt/homebrew/bin/node`. These scripts and the other applications are not
provided by this directory. See the [project README](../README.md) for forge-pr
runtime and authentication requirements.

Keep `cf-token`, `cloudflared-config.yml`, `.env` files and all credentials out of
git. Restore them separately through your private provisioning process. The
Cloudflare tunnel must be configured separately to forward this hostname to
`http://127.0.0.1:8080`; its configuration and service are not included here.

## Install

Run from this repository's root after restoring the prerequisites. If replacing
loaded agents, stop them first using the commands below before copying plists.

```sh
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.forge-pr" "$HOME/.forge-trace"
mkdir -p "$HOME/.openclaw/workspace/forge-issue/data" "$HOME/.openclaw/workspace/forge-code/data"
cp deploy/router.js "$HOME/.forge-pr/router.js"
cp deploy/claude-keepalive.sh "$HOME/.forge-pr/claude-keepalive.sh"
cp deploy/com.forge-*.plist "$HOME/Library/LaunchAgents/"
chmod 644 "$HOME/Library/LaunchAgents/"com.forge-*.plist
node --check "$HOME/.forge-pr/router.js"
plutil -lint "$HOME/Library/LaunchAgents/"com.forge-*.plist
```

## Start and inspect

`id -u` selects the logged-in user's domain (for UID 501 this is `gui/501`, e.g.
`launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.forge-router.plist`).
Bootstrap only agents that are not already loaded. `RunAtLoad` starts them
immediately and `KeepAlive` restarts them if they exit.

```sh
for name in issue code pr trace router; do
  launchctl enable "gui/$(id -u)/com.forge-$name"
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.forge-$name.plist"
done
launchctl print "gui/$(id -u)/com.forge-router"
```

Use any of the five names with `print` to inspect its PID and last exit status.
Restart a loaded agent after syncing its runtime code:

```sh
launchctl kickstart -k "gui/$(id -u)/com.forge-router"
```

For plist changes, stop, copy, then bootstrap again so launchd reads the new
configuration.

## Stop

Unload the agents to stop them without `KeepAlive` immediately restarting them:

```sh
for name in router trace pr code issue; do
  launchctl bootout "gui/$(id -u)/com.forge-$name"
done
```

An agent that is already unloaded reports an error. Bootout stops it for the
current session; installed LaunchAgents load again at login. To keep a service
stopped across logins, also run (substitute each desired name):

```sh
launchctl disable "gui/$(id -u)/com.forge-router"
```

The start loop re-enables disabled agents before bootstrapping them.

## Logs

Each plist sends both stdout and stderr to the same file. Ensure their parent
directories exist before bootstrapping (the install commands create them).

| Agent | Log file |
| --- | --- |
| `com.forge-router` | `/Users/tron/.forge-pr/router.log` |
| `com.forge-pr` | `/Users/tron/.forge-pr/daemon.log` |
| `com.forge-issue` | `/Users/tron/.openclaw/workspace/forge-issue/data/daemon.log` |
| `com.forge-code` | `/Users/tron/.openclaw/workspace/forge-code/data/daemon.log` |
| `com.forge-trace` | `/Users/tron/.forge-trace/sidecar.log` |

For example: `tail -f "$HOME/.forge-pr/router.log"`.

## OAuth keepalive

`claude-keepalive.sh` makes minimal authenticated Claude and Codex calls daily
at 07:00 (host local time) to refresh their OAuth sessions during idle periods.
It requires existing interactive logins and the host-specific CLI paths
`/opt/homebrew/bin/claude` and `/opt/homebrew/bin/codex`; adapt these and the
plist's `/Users/tron` paths when deploying to another host.

Install from the repository root (UID 501 on this host):

```sh
mkdir -p "$HOME/.forge-pr" "$HOME/Library/LaunchAgents"
cp deploy/claude-keepalive.sh "$HOME/.forge-pr/claude-keepalive.sh"
cp deploy/com.forge-keepalive.plist "$HOME/Library/LaunchAgents/"
chmod 644 "$HOME/Library/LaunchAgents/com.forge-keepalive.plist"
launchctl bootstrap gui/501 "$HOME/Library/LaunchAgents/com.forge-keepalive.plist"
```

If already loaded, run `launchctl bootout gui/501/com.forge-keepalive` before
copying and bootstrapping the plist again. Unlike the five services above, this
job runs on its calendar schedule, without `RunAtLoad` or `KeepAlive`.

Probe results append to `~/.forge-pr/keepalive.log`; launchd stdout/stderr go to
`~/.forge-pr/keepalive-run.log`. A `FAIL` line means **re-authenticate the affected
CLI interactively on the host before forge jobs run**.

The script is a verbatim host snapshot: its pipelines report `tail`'s exit status,
and its Claude authentication comparison treats `*` literally. An `ok` line
therefore does not reliably rule out an authentication failure.

## Sync check

Run from the repository root. No output and exit status zero from each `cmp`
means the installed copies match the source:

```sh
cmp deploy/router.js "$HOME/.forge-pr/router.js"
cmp deploy/claude-keepalive.sh "$HOME/.forge-pr/claude-keepalive.sh"
for name in router pr issue code trace keepalive; do
  cmp "deploy/com.forge-$name.plist" "$HOME/Library/LaunchAgents/com.forge-$name.plist" || break
done
```

Before committing deployment updates, review the diff for credentials. A quick
scan is `rg -n -i 'token|secret|password|credential|private.key' deploy` (this
README deliberately mentions secret filenames; inspect any other matches).
Copy only the intended artifacts, never the entire runtime directory.
