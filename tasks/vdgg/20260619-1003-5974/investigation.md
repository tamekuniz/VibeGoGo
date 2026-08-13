# Investigation: Step 0 GrillMe Integration

## Scope

Distribution-only change. Two repos:

- `tmknzz/VibesDeGoGo-for-Claude-Code` (current cwd for VDGG session)
- `tmknzz/VibesDeGoGo-for-Codex` (mirror change after)

## File layout

### for-Claude-Code
- `skills/vibesdegogo/SKILL.md` — has Step 0 Consultation section at lines 147–164. MAGI escalation lives at line 162 inside the Consultation loop.
- `skills/vibesdegogo/references/target_schema.md` — has explicit schema block (lines 7–50). Logical groups: Version → Deploy → Workflow/Push → Test pattern → Step 7 review/executor.

### for-Codex
- `.agents/skills/vibesdegogo/SKILL.md` — has Step 0 Consultation at lines 60–77 (parallel to Claude version). MAGI escalation at line 75. `.vdgg-target` schema is documented **inline** at lines 260–272 (no separate target_schema.md). The repo's `references/` only contains `codex-setup.md`.

## Insertion points

| Repo | File | Insertion point | What |
|---|---|---|---|
| Claude | `skills/vibesdegogo/SKILL.md` | after line 164 (end of Consultation, before "## Step 1") | New section `## Step 0 Helper: Grill Me (optional)` |
| Claude | `skills/vibesdegogo/references/target_schema.md` | between TEST_COMMAND_PATTERN (line 33) and REVIEW_COMMAND (line 35) | New `GRILLME` block with comment |
| Codex | `.agents/skills/vibesdegogo/SKILL.md` | after line 77 (end of Consultation, before "## Step 1") | New section, including inline `.vdgg-target` `GRILLME` block (Codex inlines schema, no separate file) |

## Constraint check (do not touch)

- MAGI lines (Claude line 162, Codex line 75) — keep verbatim. Grill Me section will only **reference** MAGI to describe ordering, not modify the Consultation loop.
- Existing `.vdgg-target` keys — additive only.
- Scripts (`scripts/*.sh`) — no expected change; `bash -n` will be a sanity check, not a real verification.

## Unknowns

- Whether Grill Me ever defines a canonical CLI invocation. The Matt Pocock original is a Claude Code **skill** (no shell entrypoint); detection is by skill presence. So `GRILLME=on` cannot map to a shell command — it has to be a **directive to the orchestrating agent** ("if installed and enabled, invoke the grill-me skill at Step 0 before drafting"). This mirrors how MAGI escalation is described: not a shell hook, but an agent instruction.
- Codex edition of Grill Me. `chaseai-yt/grill-me-codex` exists but the user's installed-base is unknown. The spec stays vendor-neutral: "if Grill Me / equivalent is installed".

## Design conclusion

- Add a new top-level section after Consultation, not a sub-bullet inside it. Keeps MAGI region untouched and makes the new toggle discoverable.
- `GRILLME=off` as default preserves all current behavior bit-for-bit.
- `auto` reuses the **same condition list** as the existing Consultation entry trigger (ambiguity / subjective / high-stakes / multiple defensible directions) — single source of truth.
- Grill Me runs **before** MAGI escalation. MAGI stays as the last-resort deeper deliberation for genuinely split forks.
