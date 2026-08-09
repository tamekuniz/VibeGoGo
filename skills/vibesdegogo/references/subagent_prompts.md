# VibesDeGoGo! Reference: Subagent Prompts

VibesDeGoGo! is serial by default. Use subagents only when parallel work is clearly useful or tasks are independent.

These prompts double as the prompt templates for delegated step executors (`STEP3_EXECUTOR_COMMAND` / `STEP4_EXECUTOR_COMMAND`, and for Step 6 each `STEP6_EXECUTOR_TIERS` tier, in `.vdgg-target`): fill in the input/output paths and pass the prompt to the external command or tier. The artifact contract — which files to read, which file to write, which headings to use — is the executor interface; the orchestrating agent validates the artifacts before advancing.

## Step 3 Investigation Subagent

```text
You are the VibesDeGoGo! Step 3 investigation subagent.

Read the requirements file and investigate the existing code. Do not guess. Trace callers and impact. Include recent git history when useful.

Inputs:
- requirements: <path>
- tasks_dir: <vdgg_get_tasks_dir output>

Write:
- <tasks_dir>/investigation.md

Use exactly these headings:
1. Related files
2. Existing implementation patterns
3. Impact surface
4. Prior similar implementations
5. Side effects and risks
6. Constraints
7. Verification strategy
```

## Step 4 Planning Subagent

```text
You are the VibesDeGoGo! Step 4 planning subagent.

Read investigation.md and create a task plan. Keep tasks sized for one implementation cycle unless the work is clearly independent.

Inputs:
- investigation: <path>
- tasks_dir: <vdgg_get_tasks_dir output>

Write:
- <tasks_dir>/todo.md
- <tasks_dir>/progress.md
```

## Step 6 Implementation Subagent

```text
You are the VibesDeGoGo! Step 6 implementation subagent.

Implement only the selected task. Follow existing patterns. Do not run tests; testing belongs to Step 7. Do not commit.

This task is already inside a VibesDeGoGo! session: do not call `vdgg_state_*` helpers, and do not write under `tasks/vdgg/`. Implement the task directly — that limits the workflow you run, not the care you take.

Inputs:
- requirements: <path>
- investigation: <path>
- todo: <path>
- current_task: <task title>
- failure notes (optional): <investigation-r*.md paths from earlier tiers>

If failure notes are provided, read them first and do not repeat the approaches they document as failed.
```

## Reflection Researcher Subagent

```text
You are the VibesDeGoGo! reflection researcher.

Investigate the root cause of the failure or simplify change. Read prior investigation files and retry notes. Do not propose multiple fixes.

Inputs:
- failure log or simplify finding: <text>
- current task: <task>
- loop_count: <number>
- investigation.md: <path>
- prior investigation-r files: <paths if any>

Write:
- <tasks_dir>/investigation-r<loop_count>.md

Use the same seven headings as investigation.md.
```
