# VibesDeGoGo! Reference: Output Formats

## Step 0: Requirements Draft

```markdown
## VibesDeGoGo! Step 0: Requirements

- **Goal**:
  1. <what should be achieved>
- **Constraints**:
  1. <what must not change>
- **Acceptance criteria**:
  1. <testable completion criteria>
```

Rules:

- Include all three sections.
- Number items even when there is only one item.
- Keep each item concise.
- Goal should describe the desired state, not the implementation method.
- For code changes, include the Standard-First Contract in Constraints.
- Include an acceptance item that checks for non-standard/custom implementation and requires any remaining deviations to be documented.

## Step 1: Formation Declaration

```text
[VibesDeGoGo! Declaration] id=<vdgg_get_id output>

## Requirements
- Goal: <agreed goal>
- Constraints: <agreed constraints>
- Acceptance criteria: <agreed acceptance criteria>

## Operating Plan
- Step 0 has been agreed with the user.
- I will lead Steps 1, 2, 5, 8, and 9.
- I will execute Steps 3, 4, 6, and 7 directly by default, and delegate only when parallel work clearly helps.
- State is tracked in .claude/.vdgg-state-{id}.
- Task files are stored in tasks/vdgg/{id}/.
```

## Step Start Declaration

```text
[VibesDeGoGo! Step N Start] step=N, phase=PHASE_NAME, loop=LOOP_COUNT
```

## Delegate Line

```text
[VibesDeGoGo! Delegate] step=N, executor=<model or command>, role=<short role>
```

## requirements.md

```markdown
## Goal
<goal>

## Constraints
<constraints>

## Acceptance criteria
<criteria>
```

## investigation.md

Required headings:

1. `## 1. Related files`
2. `## 2. Existing implementation patterns`
3. `## 3. Impact surface`
4. `## 4. Prior similar implementations`
5. `## 5. Side effects and risks`
6. `## 6. Constraints`
7. `## 7. Verification strategy`
8. `## 8. Lessons applied`

## Reflection Entry In progress.md

After reading `investigation-r{loop_count}.md`, append:

1. **Root Cause Investigation**: cite the retry investigation and failure log.
2. **Pattern Analysis**: compare against working references or prior patterns.
3. **Hypothesis**: one hypothesis only.
4. **Implementation Plan**: one fix only.

## Build Or Version Output

When version files are configured, output:

```text
Build/version numbers:
- <file> <key>: <value>
```

If there are no version files, say:

```text
Build/version numbers:
- none configured
```

## Final Report: branch-pr

```text
Review request created.

What changed:
- <plain-language summary>

What I verified:
- <tests/build/smoke/manual checks>

Next action:
- Review the GitHub PR. If it looks good, tell me to merge it.
  (A pull request is GitHub's confirmation page for a proposed change:
   it shows exactly what would change, and nothing lands in your main
   branch until you approve the merge.)

Build/version numbers:
- <values or none configured>

Technical note:
- PR: <url>
- branch: <branch>
- commit: <summary or short hash>
```

## Final Report: trunk

```text
Done.

What changed:
- <plain-language summary>

What I verified:
- <tests/build/smoke/manual checks>

Next action:
- <none, or push needed>

Build/version numbers:
- <values or none configured>

Technical note:
- id: <vdgg_id>
- commit: <summary or short hash>
- GitHub sync: pushed / not pushed
```

## Intentional Stop

```text
I am stopping here.

Reason:
- <what is risky or blocked>

Decision needed:
- <what the user should decide>

Technical note:
- <minimal file/command/error details>
```

Include `[Intentional Stop]` in assistant text so the Stop hook allows the turn to end.
