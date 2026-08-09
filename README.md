> **⚠️ This repository is superseded and no longer maintained.**
> Its contents are frozen at 2026-06-07 and are missing every feature added since.
> The maintained editions are
> [VibesDeGoGo-for-Claude-Code](https://github.com/tmknzz/VibesDeGoGo-for-Claude-Code)
> and [VibesDeGoGo-for-Codex](https://github.com/tmknzz/VibesDeGoGo-for-Codex).
> Do not read this repository as the current specification.

**English** | [日本語](README.ja.md)

# VibesDeGoGo!

VibesDeGoGo! is a state-and-hook workflow that keeps AI coding agents moving until the work is actually done, while stopping only before constraint violations.

This repository currently contains two editions:

- **VibesDeGoGo! for Claude Code:** the original Claude Code skill and hook workflow in `skills/vibesdegogo/`.
- **VibesDeGoGo! for Codex:** the Codex skill and hook workflow in `.agents/skills/vibesdegogo/`, with global hooks recommended and `.codex/hooks.json` available for this repository.

It exists because vibe coding is powerful, but AI agents can skip the boring parts: requirements, investigation, verification, and clear handoff. VibesDeGoGo! turns those parts into rails.

The core idea:

- do not stop for progress confirmation
- do stop before constraint violations
- write requirements before implementation
- investigate existing code before planning
- verify before completion
- use state files and hooks so the workflow is enforced mechanically, not just by prompt text

## What It Is

VibesDeGoGo! is designed for practical AI-assisted coding sessions where the user wants to make one request and have the agent carry it through:

1. agree on Goal / Constraints / Acceptance criteria
2. write `requirements.md`
3. investigate the codebase and write `investigation.md`
4. create `todo.md` and `progress.md`
5. implement one task at a time
6. test or otherwise verify
7. reflect and retry on failures
8. update progress and version metadata
9. commit, and optionally push

It is intentionally strict on the agent side and lightweight on the user side.

## Key Rules

- **No progress confirmation:** the agent must not stop with "Can I continue?"
- **Constraint confirmation required:** the agent must stop before changing constraints, adding dependencies, using non-standard implementations, changing persistence/API/billing/analytics contracts, touching security-sensitive behavior, or performing destructive operations.
- **Standard-first:** use the platform/framework standard components, APIs, and patterns first. If that is not enough, report the reason and alternatives before implementation.
- **Verification required:** do not mark a task complete without tests, build verification, smoke checks, or explicit manual verification steps where automation is not possible.
- **Push behavior is workflow-specific:** default `branch-pr` pushes the feature branch to create a PR; `trunk` pushes only when `.vdgg-target` sets `AUTO_PUSH=true`.

## Modes

- **Full flow:** default for normal coding work.
- **Self-maintenance mode:** only for changes under `skills/vibesdegogo/`; keeps VibesDeGoGo! self-edits focused while preserving core checks.
- **Lightweight mode:** for small, closed changes in general projects. It still requires fixed scope, existing patterns, no new dependencies, and explicit verification. It escalates to full flow when tests fail twice, scope expands, or specification judgment is needed.
- **Friendly completion reports:** final messages start with plain-language status and next steps, with Git details separated into a short technical note.

## Repository Layout

```text
skills/vibesdegogo/
  SKILL.md
  scripts/
    vdgg-state.sh
    vdgg-hook-pretool.sh
    vdgg-hook-posttool.sh
    vdgg-hook-stop.sh
  references/
    setup.md
    output_formats.md
    target_schema.md
    hook_rules.md
    state_helpers.md
    subagent_prompts.md
```

## Install: VibesDeGoGo! for Claude Code

Copy the skill folder into Claude Code's skills directory:

```bash
mkdir -p "$HOME/.claude/skills"
cp -R skills/vibesdegogo "$HOME/.claude/skills/vibesdegogo"
```

Then register the hooks shown in:

```text
skills/vibesdegogo/references/setup.md
```

`jq` is required because the hooks parse Claude Code hook JSON. If it is not
already installed, pick the command for your platform:

```bash
brew install jq               # macOS
sudo apt-get install jq       # Debian / Ubuntu / WSL
apk add jq                    # Alpine
sudo dnf install jq           # Fedora / RHEL
```

## Install: VibesDeGoGo! for Codex

For cross-repository use, install the Codex edition as a user skill:

```bash
mkdir -p "$HOME/.codex/skills"
cp -R .agents/skills/vibesdegogo "$HOME/.codex/skills/vibesdegogo"
```

Codex also reads repository skills from `.agents/skills`, so the Codex edition is present in this repository for development:

```text
.agents/skills/vibesdegogo/
```

For normal Codex use, install global hooks in `~/.codex/hooks.json` or `~/.codex/config.toml` so VDGG rules apply across repositories. The hook scripts no-op unless the current repository has `.codex/.vdgg-active`.

This repository also includes project-local hooks in `.codex/hooks.json` after the project hook definitions are reviewed and trusted:

```text
.codex/hooks.json
```

In Codex, use `/hooks` to review and trust the hook definitions. See:

```text
.agents/skills/vibesdegogo/references/codex-setup.md
```

`jq` is required because the hooks parse Codex hook JSON. See the Claude Code
section above for per-platform install commands.

## Project Configuration

For each project, optionally create `.vdgg-target` in the project root. See:

```text
skills/vibesdegogo/references/target_schema.md
```

The most important optional workflow fields are:

```bash
WORKFLOW=branch-pr
AUTO_PUSH=false
```

With the default `WORKFLOW=branch-pr`, Step 9 pushes the feature branch so it can open a PR. `AUTO_PUSH=true` only affects `WORKFLOW=trunk`.

## Why Free

VibesDeGoGo! is free and open source.

Vibe coding gave me a way to build with joy. This project is my small thank-you back to that world: a set of safety rails so more people can enjoy building with AI without feeling lost or unsafe.

## Status

This is an opinionated workflow extracted from real daily use. It is not a general-purpose CI/CD system. It is a guardrailed operating procedure for AI coding agents.
