#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available for manifest validation" >&2
    exit 0
fi

# Manifests parse as valid JSON.
jq -e . "$ROOT/.claude-plugin/plugin.json" >/dev/null || fail "plugin.json is not valid JSON"
jq -e . "$ROOT/.claude-plugin/marketplace.json" >/dev/null || fail "marketplace.json is not valid JSON"
jq -e . "$ROOT/hooks/hooks.json" >/dev/null || fail "hooks.json is not valid JSON"

# Required fields are present.
NAME=$(jq -r '.name' "$ROOT/.claude-plugin/plugin.json")
assert_eq "vibesdegogo" "$NAME" "plugin.json name"
MP_PLUGIN=$(jq -r '.plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")
assert_eq "vibesdegogo" "$MP_PLUGIN" "marketplace.json plugin entry"

# Every hook command references a script that exists in the repo.
while IFS= read -r cmd; do
    rel=${cmd#*\$\{CLAUDE_PLUGIN_ROOT\}\"/}
    rel=${rel%%[\"\ ]*}
    assert_file_exists "$ROOT/$rel" "hook script referenced by hooks.json exists"
done < <(jq -r '.hooks[][].hooks[].command' "$ROOT/hooks/hooks.json")

# plugin.json version matches SKILL.md version.
PLUGIN_VERSION=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
SKILL_VERSION=$(grep '^version:' "$ROOT/skills/vibesdegogo/SKILL.md" | awk '{print $2}')
assert_eq "$PLUGIN_VERSION" "$SKILL_VERSION" "plugin.json version matches SKILL.md"
