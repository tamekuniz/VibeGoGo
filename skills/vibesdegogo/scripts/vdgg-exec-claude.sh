#!/bin/sh
# Bundled executor for the builtin "claude" formation value.
# Contract: VDGG_EXECUTOR_INPUT is the prompt file; with VDGG_EXECUTOR_OUTPUT
# set this is an artifact seat (effectively read-only: -p denies permission
# requests) writing the final message to that file; without it this is the
# Step 6 editing seat and may edit the working tree.
set -eu

input=${VDGG_EXECUTOR_INPUT:-}
output=${VDGG_EXECUTOR_OUTPUT:-}
[ -f "$input" ] || { echo "vdgg-exec-claude: input is missing" >&2; exit 64; }
command -v claude >/dev/null 2>&1 || { echo "vdgg-exec-claude: claude CLI is required" >&2; exit 69; }

model=${VDGG_EXECUTOR_MODEL:-sonnet}
effort=${VDGG_EXECUTOR_EFFORT:-}

set -- -p --model "$model"
[ -n "$effort" ] && set -- "$@" --effort "$effort"

if [ -n "$output" ]; then
  claude "$@" < "$input" > "$output"
else
  claude "$@" --permission-mode acceptEdits < "$input" >/dev/null
fi
