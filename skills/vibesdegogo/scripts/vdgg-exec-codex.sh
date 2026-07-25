#!/bin/sh
# Bundled executor for the builtin "codex" formation value.
# Contract: VDGG_EXECUTOR_INPUT is the prompt file; with VDGG_EXECUTOR_OUTPUT
# set this is an artifact seat (read-only sandbox, final message written to
# that file); without it this is the Step 6 editing seat (workspace-write).
set -eu

input=${VDGG_EXECUTOR_INPUT:-}
output=${VDGG_EXECUTOR_OUTPUT:-}
[ -f "$input" ] || { echo "vdgg-exec-codex: input is missing" >&2; exit 64; }
command -v codex >/dev/null 2>&1 || { echo "vdgg-exec-codex: codex CLI is required" >&2; exit 69; }

model=${VDGG_EXECUTOR_MODEL:-}
effort=${VDGG_EXECUTOR_EFFORT:-}

set -- exec --skip-git-repo-check --color never
[ -n "$model" ] && set -- "$@" -m "$model"
[ -n "$effort" ] && set -- "$@" -c "model_reasoning_effort=\"$effort\""

if [ -n "$output" ]; then
  codex "$@" -s read-only -o "$output" - < "$input" >/dev/null
else
  codex "$@" -s workspace-write - < "$input" >/dev/null
fi
