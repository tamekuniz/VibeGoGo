# Investigation: Codex Mirror of GrillMe Step 0 Integration

## Source of truth

`tmknzz/VibesDeGoGo-for-Claude-Code` PR #6 (merged or pending review at session start). The Codex mirror should be semantically identical, only adjusting for Codex edition conventions.

## Codex edition structural diffs to honor

- `.agents/skills/vibesdegogo/SKILL.md` houses the entire skill text plus inline `.vdgg-target` schema (lines 260–272 already document REVIEW_COMMAND and STEP*_EXECUTOR_COMMAND inline).
- No `references/target_schema.md`; Codex repo only ships `references/codex-setup.md`.
- Step 0 Consultation section is at lines 60–77, with MAGI escalation at line 75 (parallel to Claude line 162).
- Step 1 starts at line 79.

## Insertion plan

Single file: `.agents/skills/vibesdegogo/SKILL.md`.

After line 77 (end of Consultation), before "## Step 1: Formation", add `## Step 0 Helper: Grill Me (optional)`. The section includes:

1. Narrative paragraphs matching Claude PR #6 (3層構造、pre-filter 性質、未インストール skip)
2. **Inline** `.vdgg-target` `GRILLME` block (Codex convention; no separate schema file to reference)

The Claude version references `target_schema.md`; the Codex version inlines the schema directly in the new section.

## Out of scope

- No change to MAGI line (Consultation step 4).
- No change to scripts/*.sh.
- No change to existing inline `.vdgg-target` schema block at lines 260–272.
