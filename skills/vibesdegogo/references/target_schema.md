# VibesDeGoGo! Reference: .vdgg-target Schema

`.vdgg-target` is an optional project-root file. It is a Bash-sourceable KEY=VALUE file that tells Step 8 and Step 9 how to update versions, validate changes, and push work.

## Fields

```bash
# Version files. Multiple entries are allowed.
VERSION_FILE_1_PATH=<path from project root>
VERSION_FILE_1_KEY=<key in that file>
VERSION_FILE_2_PATH=...
VERSION_FILE_2_KEY=...

# Human guidance for version generation.
VERSION_FORMAT="<description>"
VERSION_EXAMPLE="<example>"

# Validation/deployment guidance.
DEPLOY_COMMAND="<slash command or manual procedure>"
DEPLOY_TARGET="<device, local app, dev server, etc.>"
VERIFY_TYPE="<device preview, browser check, curl check, etc.>"

# Workflow. Default is branch-pr.
WORKFLOW=branch-pr

# Base branch for PRs. Optional; default is origin default branch, then main.
BASE_BRANCH=main

# Only used when WORKFLOW=trunk.
AUTO_PUSH=false

# Extra test command regex blocked during implementing phase.
TEST_COMMAND_PATTERN="<extended regex>"
```

## Example: iOS Or macOS App

```bash
VERSION_FILE_1_PATH=project.yml
VERSION_FILE_1_KEY=CURRENT_PROJECT_VERSION
VERSION_FORMAT="yyyymmdd plus two-letter sequence, starting at AA"
VERSION_EXAMPLE="20260527AA"
DEPLOY_COMMAND="/deploy-device"
DEPLOY_TARGET="physical device"
VERIFY_TYPE="device preview"
AUTO_PUSH=false
```

## Example: Web Backend Without Version Files

```bash
DEPLOY_COMMAND="npm run dev"
DEPLOY_TARGET="dev server"
VERIFY_TYPE="browser check"
AUTO_PUSH=false
```

## Workflow Behavior

`branch-pr` is the default:

1. Step 1 creates a feature branch named from the Step 0 Goal, in `{type}/{slug}` form (e.g., `feat/japanese-readme`). See Step 1 in `SKILL.md`.
2. Step 9 commits there.
3. Step 9 pushes the branch and creates a PR.
4. The agent stops. A human decides whether to merge.

`AUTO_PUSH` is ignored in `branch-pr` because pushing the feature branch is required to create a PR.

`trunk` is opt-in:

1. Work stays on the current branch.
2. Step 9 commits there.
3. Step 9 pushes only when `AUTO_PUSH=true`.
