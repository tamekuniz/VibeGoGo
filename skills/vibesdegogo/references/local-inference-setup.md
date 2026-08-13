# Local llama-server setup

This document walks a first-time user from a clean machine to a running
`llama-server` instance that VDGG can call as an executor. It covers macOS
launchd (the primary tested path) and Linux systemd (schema-compatible but
untested by the author — community verification welcome).

The moving parts:

- **`servers.conf`** — the declarative source of truth for each server
  instance (model, port, api key, chat template, extra flags). Schema:
  [`servers-conf.md`](servers-conf.md).
- **`vdgg-llm-start`** — a thin wrapper that reads `servers.conf` and either
  lints it (`--check`), prints the argv it would exec (`--dry-run`), or
  execs `llama-server`. Source: [`scripts/vdgg-llm-start.sh`](../scripts/vdgg-llm-start.sh).
- **Service unit** — `launchd` (macOS) or `systemd` (Linux) supervises the
  process. Neither VDGG nor the launcher tries to daemonize; that job stays
  with the OS.

## First-run order

Follow the steps in order. Every step ends in a checkable command.

1. **Install `llama-server`.** On macOS: `brew install llama.cpp`. On Linux:
   build from source per the upstream instructions at
   <https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md>
   — distro packages are not yet common. Confirm:

   ```bash
   which llama-server
   ```

2. **Put `vdgg-llm-start` on `$PATH`.** Copy or symlink the script from the
   skill's `scripts/` directory:

   ```bash
   sudo cp .agents/skills/vibesdegogo/scripts/vdgg-llm-start.sh \
           /usr/local/bin/vdgg-llm-start
   sudo chmod +x /usr/local/bin/vdgg-llm-start
   ```

   The service unit templates (below) still use the absolute path
   `/usr/local/bin/vdgg-llm-start` because `launchd` and `systemd` don't
   inherit the interactive `$PATH`.

3. **Create the config dir and the api key file.** The key file must be mode
   `600` — the launcher refuses to start otherwise.

   ```bash
   mkdir -p ~/.config/vdgg
   umask 077
   openssl rand -hex 32 > ~/.config/vdgg/llama-api-key
   chmod 600 ~/.config/vdgg/llama-api-key
   ```

4. **Copy the example `servers.conf` and edit the model paths and ports.**

   ```bash
   cp .agents/skills/vibesdegogo/references/servers.conf.example \
      ~/.config/vdgg/servers.conf
   ${EDITOR:-vi} ~/.config/vdgg/servers.conf
   ```

5. **Lint the config before you launch anything.** `--check` (no id) runs
   per-block checks plus port and alias uniqueness across the whole file.

   ```bash
   vdgg-llm-start --check
   ```

   Fix any reported issue (missing model file, wrong `api_key_file` mode,
   port collision) and re-run until this prints `servers.conf looks healthy`.

6. **Print the argv `--dry-run` would exec.** The service unit runs exactly
   this command.

   ```bash
   vdgg-llm-start --dry-run qwen
   ```

7. **Install the service unit.** See the OS-specific sections below.

8. **Confirm the server responds.** Read the port back from `--dry-run` so
   this works regardless of which port `servers.conf` picked:

   ```bash
   port=$(vdgg-llm-start --dry-run qwen | awk '/^--port$/ {getline; print}')
   api_key=$(cat ~/.config/vdgg/llama-api-key)
   curl -fsS -H "Authorization: Bearer $api_key" "http://127.0.0.1:${port}/health"
   ```

## macOS: launchd

Save this template as
`~/Library/LaunchAgents/com.<user>.vdgg.llama-<id>.plist`, replacing
`<user>` and `<id>` (e.g. `qwen`). The plist's `ProgramArguments` calls
`vdgg-llm-start` and nothing else — the argv it execs comes from
`servers.conf`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.YOUR_USER.vdgg.llama-qwen</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/vdgg-llm-start</string>
    <string>qwen</string>
  </array>
  <!-- launchd's default PATH is /usr/bin:/bin:/usr/sbin:/sbin — Homebrew's
       /opt/homebrew/bin is not on it, so the launcher's `exec llama-server`
       would fail with "command not found". Point at the absolute path. -->
  <key>EnvironmentVariables</key>
  <dict>
    <key>VDGG_LLAMA_SERVER_BIN</key>
    <string>/opt/homebrew/bin/llama-server</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>WorkingDirectory</key><string>/Users/YOUR_USER</string>
  <key>StandardOutPath</key><string>/Users/YOUR_USER/Library/Logs/vdgg/llama-qwen.out.log</string>
  <key>StandardErrorPath</key><string>/Users/YOUR_USER/Library/Logs/vdgg/llama-qwen.err.log</string>
</dict>
</plist>
```

Load and check:

```bash
mkdir -p ~/Library/Logs/vdgg
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.YOUR_USER.vdgg.llama-qwen.plist
launchctl print "gui/$(id -u)/com.YOUR_USER.vdgg.llama-qwen" | grep -E 'state =|pid ='
```

Expected: `state = running` and a positive `pid`.

To restart after editing `servers.conf`:

```bash
launchctl kickstart -k "gui/$(id -u)/com.YOUR_USER.vdgg.llama-qwen"
```

## Linux: systemd

The launcher is POSIX sh and the `servers.conf` schema is identical across
OSes; what follows is a schema-compatible unit template. If you use it,
please open an issue confirming it works or noting what needed to change.

`~/.config/systemd/user/vdgg-llama-qwen.service`:

```ini
[Unit]
Description=VDGG llama.cpp server (qwen)
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vdgg-llm-start qwen
Restart=on-failure
RestartSec=10s
StandardOutput=append:%h/.local/state/vdgg/llama-qwen.out.log
StandardError=append:%h/.local/state/vdgg/llama-qwen.err.log

[Install]
WantedBy=default.target
```

Enable and check:

```bash
mkdir -p ~/.local/state/vdgg
systemctl --user daemon-reload
systemctl --user enable --now vdgg-llama-qwen.service
systemctl --user status vdgg-llama-qwen.service
```

## API key rotation

Rotating the key is a two-step operation. Every client that already holds the
old key will stop working the moment the server picks up the new one; plan
the redistribution before rotating.

```bash
umask 077
openssl rand -hex 32 > ~/.config/vdgg/llama-api-key
chmod 600 ~/.config/vdgg/llama-api-key
# macOS
launchctl kickstart -k "gui/$(id -u)/com.YOUR_USER.vdgg.llama-qwen"
# Linux
systemctl --user restart vdgg-llama-qwen.service
```

Re-distribute the new key over an already-secure channel (AirDrop, SSH,
password manager). Never in email, chat, or version control.

## Reading the logs

When something isn't working, the server's stderr log usually tells you
directly.

**macOS.** Logs are wherever `StandardErrorPath` in the plist points; the
template above uses `~/Library/Logs/vdgg/`:

```bash
tail -F ~/Library/Logs/vdgg/llama-qwen.err.log
launchctl print "gui/$(id -u)/com.YOUR_USER.vdgg.llama-qwen" | grep -E 'state =|last exit code ='
```

**Linux.** systemd captures the log itself:

```bash
journalctl --user -u vdgg-llama-qwen.service -f
systemctl --user status vdgg-llama-qwen.service
```

If the server exits immediately with `mode ...; expected 600`, the launcher
refused to start because the `api_key_file` has the wrong permissions — fix
with `chmod 600 <path>` and restart.
