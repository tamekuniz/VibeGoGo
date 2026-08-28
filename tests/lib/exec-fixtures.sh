#!/bin/bash
# exec-fixtures.sh — shared executor fixtures for Formation fallback tests.
# Usage: `. tests/lib/exec-fixtures.sh; vdgg_install_exec_fixtures <bindir> <configdir>`

vdgg_install_exec_fixtures() {
  local bindir="$1" configdir="$2"
  mkdir -p "$bindir" "$configdir/executors"
  printf '#!/bin/sh\nprintf "ran-%%s\\n" "$VDGG_EXECUTOR_AI" > "$VDGG_EXECUTOR_OUTPUT"\n' > "$bindir/exec-ok"
  printf '#!/bin/sh\nexit 3\n' > "$bindir/exec-fail"
  printf '#!/bin/sh\n: > "$VDGG_EXECUTOR_OUTPUT"\n' > "$bindir/exec-empty"
  chmod +x "$bindir/exec-ok" "$bindir/exec-fail" "$bindir/exec-empty"
  printf 'COMMAND=%s\n' "$bindir/exec-ok" > "$configdir/executors/okexec.conf"
  printf 'COMMAND=%s\n' "$bindir/exec-fail" > "$configdir/executors/failexec.conf"
  printf 'COMMAND=%s\n' "$bindir/exec-empty" > "$configdir/executors/emptyexec.conf"
}
