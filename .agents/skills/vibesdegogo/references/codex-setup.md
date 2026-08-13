# VibesDeGoGo! for Codex Setup

## Install as a global skill

For normal cross-repository use, install the Codex edition into Codex's user skill directory:

```bash
mkdir -p "$HOME/.agents/skills"
cp -R .agents/skills/vibesdegogo "$HOME/.agents/skills/vibesdegogo"
```

If you do not copy the skill, set `VDGG_CODEX_SKILL_DIR` in the hook command to the absolute checkout path of `.agents/skills/vibesdegogo`.

## Use as a repo-local skill

Codex reads repo skills from `.agents/skills` under the current directory or repository root. This repository includes:

```text
.agents/skills/vibesdegogo/
```

Restart Codex if the skill does not appear after checkout or edits.

## Enable hooks globally

Recommended setup is global hooks, so VDGG rules apply in every repository without copying `.codex/hooks.json` into each project. The examples below assume the skill is installed at:

```text
$HOME/.agents/skills/vibesdegogo/
```

Then add the hook commands to `~/.codex/hooks.json` or the equivalent Codex hook config. The commands should point to the installed skill path. `UserPromptSubmit` makes VDGG the default workflow for coding work in any git repository; the tool hooks enforce state once VDGG starts.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -lc 'VDGG_CODEX_SKILL_DIR=\"${VDGG_CODEX_SKILL_DIR:-$HOME/.agents/skills/vibesdegogo}\"; bash \"$VDGG_CODEX_SKILL_DIR/scripts/vdgg-hook-pretool.sh\"'",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -lc 'VDGG_CODEX_SKILL_DIR=\"${VDGG_CODEX_SKILL_DIR:-$HOME/.agents/skills/vibesdegogo}\"; bash \"$VDGG_CODEX_SKILL_DIR/scripts/vdgg-hook-posttool.sh\"'",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash -lc 'VDGG_CODEX_SKILL_DIR=\"${VDGG_CODEX_SKILL_DIR:-$HOME/.agents/skills/vibesdegogo}\"; bash \"$VDGG_CODEX_SKILL_DIR/scripts/vdgg-hook-stop.sh\"'",
            "timeout": 5
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash -lc 'VDGG_CODEX_SKILL_DIR=\"${VDGG_CODEX_SKILL_DIR:-$HOME/.agents/skills/vibesdegogo}\"; bash \"$VDGG_CODEX_SKILL_DIR/scripts/vdgg-hook-userprompt.sh\"'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

The hook scripts no-op unless the current repository has `.codex/.vdgg-active`, so global registration is safe for non-VDGG work. One exception: a repository whose `.vdgg-target` sets `VDGG_REQUIRED=on` denies code-modifying tools while no session is armed (see "Entry Gate: VDGG_REQUIRED" in SKILL.md) — that is the key's purpose, and repositories without the key are untouched.

## Enable hooks repo-locally

The repository also includes `.codex/hooks.json`. Codex loads project-local hooks only after the project `.codex/` layer is trusted. Use `/hooks` in Codex to review and trust the hook definitions.

Repo-local hooks are useful for developing this repository, but they do not protect other repositories unless copied and trusted there. Use global hooks for normal VDGG operation across projects.

`jq` is required because the hook scripts parse Codex hook JSON.

## Upstream behavior (per Codex docs)

The Codex docs say:

- skills are directories with `SKILL.md` and optional `scripts/`, `references/`, `assets/`, and `agents/`;
- Codex reads repo skills from `.agents/skills`;
- Codex loads hook sources from `~/.codex/hooks.json`, `~/.codex/config.toml`, `<repo>/.codex/hooks.json`, and `<repo>/.codex/config.toml`;
- `PreToolUse` and `PostToolUse` can observe `Bash`, `apply_patch`, and MCP tool calls, but this is a guardrail rather than a complete enforcement boundary.

Sources:

- https://developers.openai.com/codex/skills
- https://developers.openai.com/codex/hooks
- https://github.com/openai/codex/releases/tag/rust-v0.124.0

## Known limitations

VibesDeGoGo! for Codex follows the Claude Code step model, but hook parity is not exact. The Codex hook docs explicitly warn that `PreToolUse` is a guardrail rather than a complete enforcement boundary. Treat hooks as safety rails, not a sandbox or proof of correctness.

- Scope: hooks are confirmed to fire in the interactive Codex CLI (checked
  against 0.139.0). In our testing, `codex exec` (non-interactive) did not
  fire hooks at all, so VDGG enforcement does not apply there.
- `PostToolUse` payload shape varies by Codex version: some versions deliver
  `tool_response` as an object with `exit_code`/`stderr`, others (e.g.
  0.139.0) as a plain string. With the string form there is no exit code, so
  Bash failure detection falls back to scanning the response text for error
  patterns — best-effort, not a reliable success/failure signal.
