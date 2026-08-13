#!/bin/bash
# vdgg-llm-start: launch a llama-server instance defined in servers.conf.
#
# Schema and CLI contract are the source-of-truth in
# ../references/servers-conf.md. This is a thin wrapper around llama-server;
# it does not daemonize, and start/stop/status remain the launchd/systemd job.
#
# Usage:
#   vdgg-llm-start --help
#   vdgg-llm-start --list
#   vdgg-llm-start --dry-run <id>
#   vdgg-llm-start --check [<id>]
#   vdgg-llm-start <id>
set -euo pipefail

VDGG_CONFIG_DIR="${VDGG_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/vdgg}"
VDGG_SERVERS_CONF="${VDGG_SERVERS_CONF:-${VDGG_CONFIG_DIR}/servers.conf}"
VDGG_LLAMA_SERVER_BIN="${VDGG_LLAMA_SERVER_BIN:-llama-server}"

_prog=$(basename "$0")

_die() { printf '%s: error: %s\n' "$_prog" "$*" >&2; exit "${2:-1}"; }
_warn() { printf '%s: warning: %s\n' "$_prog" "$*" >&2; }
_info() { printf '%s: %s\n' "$_prog" "$*" >&2; }

_help() {
    cat <<EOF
Usage: $_prog [subcommand]

Launch a llama-server instance defined in servers.conf.

Subcommands:
  --help            Show this message.
  --list            List defined server ids in servers.conf.
  --dry-run <id>    Print the llama-server argv that would be exec'd, one flag per line.
  --check           Sanity-check the whole servers.conf (port/alias collisions + every id).
  --check <id>      Sanity-check a single server id.
  <id>              exec llama-server with the arguments derived from <id>.

Environment:
  VDGG_CONFIG_DIR       Config root (default: \${XDG_CONFIG_HOME:-\$HOME/.config}/vdgg).
  VDGG_SERVERS_CONF     Path to servers.conf (default: \$VDGG_CONFIG_DIR/servers.conf).
  VDGG_LLAMA_SERVER_BIN llama-server binary (default: 'llama-server' on PATH).

Files:
  servers.conf schema : references/servers-conf.md (source of truth)
  example             : references/servers.conf.example
  full setup guide    : references/local-inference-setup.md
EOF
}

# _perm_of <file>: print the file's mode as three octal digits ("600").
# macOS/Linux stat differs; this is the only OS split in this script.
_perm_of() {
    case "$(uname)" in
        Darwin) stat -f "%OLp" "$1" ;;
        *)      stat -c "%a"   "$1" ;;
    esac
}

# _expand_home <value>: expand leading $HOME / ${HOME} to the real home path.
# Only $HOME is expanded — no eval, no arbitrary variable substitution.
_expand_home() {
    case "$1" in
        '$HOME'*)   printf '%s\n' "${HOME}${1#\$HOME}" ;;
        '${HOME}'*) printf '%s\n' "${HOME}${1#\$\{HOME\}}" ;;
        '~/'*)      printf '%s\n' "${HOME}/${1#\~/}" ;;
        *)          printf '%s\n' "$1" ;;
    esac
}

_require_conf() {
    [ -f "$VDGG_SERVERS_CONF" ] || _die "servers.conf not found: $VDGG_SERVERS_CONF (see references/servers-conf.md)"
}

# _list_ids: print every [id] header from the conf, in file order.
_list_ids() {
    _require_conf
    awk '
        /^\[[^]]+\][[:space:]]*$/ {
            id = $0
            sub(/^\[/, "", id); sub(/\][[:space:]]*$/, "", id)
            print id
        }
    ' "$VDGG_SERVERS_CONF"
}

# _load_block <id>: print key=value lines for the [id] block, ignoring
# comments and blank lines. Value keeps its raw form (pre-$HOME-expansion).
_load_block() {
    local id="$1"
    _require_conf
    awk -v want="$id" '
        /^\[[^]]+\][[:space:]]*$/ {
            cur = $0
            sub(/^\[/, "", cur); sub(/\][[:space:]]*$/, "", cur)
            in_block = (cur == want)
            next
        }
        !in_block { next }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { print }
    ' "$VDGG_SERVERS_CONF"
}

# Parse a block into KV_* globals. Keys not in the schema are silently kept
# in KV_extra as raw "key=value" lines so --check can flag them.
KV_model=""
KV_host=""
KV_port=""
KV_alias=""
KV_ctx_size=""
KV_chat_template=""
KV_api_key_file=""
KV_extra_flags=""
KV_extra=""

_reset_kv() {
    KV_model=""; KV_host=""; KV_port=""; KV_alias=""; KV_ctx_size=""
    KV_chat_template=""; KV_api_key_file=""; KV_extra_flags=""; KV_extra=""
}

_parse_block() {
    local id="$1" line key val
    _reset_kv
    local body
    body=$(_load_block "$id")
    [ -n "$body" ] || _die "no such server id in $VDGG_SERVERS_CONF: [$id]" 2
    while IFS= read -r line; do
        # split at the first '='
        case "$line" in
            *=*) key="${line%%=*}"; val="${line#*=}" ;;
            *)   _die "malformed line in [$id]: $line" 2 ;;
        esac
        # trim surrounding whitespace on key
        key="${key# }"; key="${key% }"
        # strip a single pair of surrounding double quotes on val, then expand $HOME
        case "$val" in
            \"*\") val="${val#\"}"; val="${val%\"}" ;;
        esac
        val=$(_expand_home "$val")
        case "$key" in
            model)         KV_model=$val ;;
            host)          KV_host=$val ;;
            port)          KV_port=$val ;;
            alias)         KV_alias=$val ;;
            ctx_size)      KV_ctx_size=$val ;;
            chat_template) KV_chat_template=$val ;;
            api_key_file)  KV_api_key_file=$val ;;
            extra_flags)   KV_extra_flags=$val ;;
            *)             KV_extra="${KV_extra}${key}=${val}"$'\n' ;;
        esac
    done <<EOF
$body
EOF
    # host defaults to loopback — this is a stance, not an oversight.
    [ -n "$KV_host" ] || KV_host="127.0.0.1"
}

# _check_api_key_perm <path> <id> <mode>
# mode: 'refuse' (exit non-zero on violation) | 'warn' (stderr only)
# _warn_if_public_host <id>: shared LAN-exposure warning used by --check and startup.
# Single-sourced so wording can't drift between the two call sites.
_warn_if_public_host() {
    local id="$1"
    case "$KV_host" in
        0.0.0.0|::|0::0|[::])
            _warn "[$id] host=$KV_host binds all interfaces. Anyone on this LAN can reach port $KV_port; ensure api_key_file is set and use Tailscale/TLS for untrusted networks."
            ;;
    esac
}

# _find_dups <tab-separated key<TAB>id lines>: print "key<TAB>id1,id2,..." for
# every key that appears more than once. Called by _report_dups (below).
_find_dups() {
    printf '%s' "$1" | awk -F'\t' '
        NF==2 && $1!="" {
            seen[$1] = seen[$1] ? seen[$1] "," $2 : $2
            count[$1]++
        }
        END {
            for (k in count) if (count[k] > 1) printf "%s\t%s\n", k, seen[k]
        }'
}

# _report_dups <label> <input>: emit a "design buddy" message per collision on
# stderr. Returns non-zero iff any collision was found. `label` reads naturally
# in the message (e.g. "port", "alias").
_report_dups() {
    local label="$1" input="$2" ok=0 key ids dups
    dups=$(_find_dups "$input")
    [ -n "$dups" ] || return 0
    while IFS=$'\t' read -r key ids; do
        [ -n "$key" ] || continue
        printf '%s %s: %s all claim it. Pick a different %s for all but one.\n' \
            "$label" "$key" "$ids" "$label" >&2
        ok=1
    done <<EOF
$dups
EOF
    return $ok
}

_check_api_key_perm() {
    local f="$1" id="$2" mode="$3" perm
    if [ ! -f "$f" ]; then
        if [ "$mode" = "refuse" ]; then
            _die "[$id] api_key_file not found: $f" 4
        fi
        _warn "[$id] api_key_file not found: $f"
        return 1
    fi
    perm=$(_perm_of "$f")
    if [ "$perm" != "600" ]; then
        if [ "$mode" = "refuse" ]; then
            _die "[$id] api_key_file $f has mode $perm; expected 600. Run: chmod 600 '$f'" 4
        fi
        _warn "[$id] api_key_file $f has mode $perm; expected 600. Run: chmod 600 '$f'"
        return 1
    fi
    return 0
}

_check_id() {
    _parse_block "$1"
    _check_kv "$1"
}

# _check_kv <id>: run the per-id checks against KV_* globals. Assumes
# _parse_block has already been called for this id. Splitting parse from
# check lets _check_all reuse one parse per id.
_check_kv() {
    local id="$1" ok=0

    # required keys
    for k in model port alias ctx_size; do
        eval "v=\$KV_$k"
        if [ -z "$v" ]; then
            printf '[%s] missing required key: %s\n' "$id" "$k" >&2
            ok=1
        fi
    done

    # (a) model file existence — skip for -hf style
    case "$KV_model" in
        -hf*|hf:*|"") : ;;
        *)
            [ -f "$KV_model" ] || {
                printf '[%s] model file not found: %s\n' "$id" "$KV_model" >&2
                ok=1
            }
            ;;
    esac

    # (b) api_key_file: refuse mode
    if [ -n "$KV_api_key_file" ]; then
        _check_api_key_perm "$KV_api_key_file" "$id" refuse || ok=1
    fi

    # (c) port range
    case "$KV_port" in
        ''|*[!0-9]*)
            printf '[%s] port not numeric: %s\n' "$id" "$KV_port" >&2
            ok=1
            ;;
        *)
            if [ "$KV_port" -lt 1 ] || [ "$KV_port" -gt 65535 ]; then
                printf '[%s] port out of range (1-65535): %s\n' "$id" "$KV_port" >&2
                ok=1
            elif [ "$KV_port" -lt 1024 ]; then
                _warn "[$id] port $KV_port is a privileged port (<1024); llama-server usually cannot bind it."
            fi
            ;;
    esac

    # (d) host warnings
    _warn_if_public_host "$id"

    # unknown keys — surface them, but do not fail (extra_flags escape hatch is the sanctioned path)
    if [ -n "$KV_extra" ]; then
        while IFS= read -r extra_line; do
            [ -n "$extra_line" ] || continue
            _warn "[$id] unknown key ignored: $extra_line (see references/servers-conf.md; put spare llama-server flags in extra_flags)"
        done <<EOF
$KV_extra
EOF
    fi

    return $ok
}

_check_all() {
    _require_conf
    local ids id ok=0 ports="" aliases=""
    ids=$(_list_ids)
    if [ -z "$ids" ]; then
        _info "no server ids defined in $VDGG_SERVERS_CONF"
        return 0
    fi

    # Single parse per id: collect the port/alias for global collision
    # detection and run the per-id checks in the same pass.
    while IFS= read -r id; do
        _parse_block "$id"
        [ -n "$KV_port" ]  && ports="${ports}${KV_port}	${id}"$'\n'
        [ -n "$KV_alias" ] && aliases="${aliases}${KV_alias}	${id}"$'\n'
        _check_kv "$id" || ok=1
    done <<EOF
$ids
EOF

    _report_dups "port"  "$ports"   || ok=1
    _report_dups "alias" "$aliases" || ok=1

    if [ $ok -eq 0 ]; then
        _info "servers.conf looks healthy ($(printf '%s\n' "$ids" | wc -l | tr -d ' ') server(s))."
    fi
    return $ok
}

# _emit_argv: print the llama-server argv, one token per line. The single
# source of truth for both --dry-run and startup, so what --dry-run prints
# is exactly what _start execs. Assumes _parse_block already ran.
_emit_argv() {
    printf '%s\n' "$VDGG_LLAMA_SERVER_BIN"
    printf -- '--model\n%s\n'    "$KV_model"
    printf -- '--host\n%s\n'     "$KV_host"
    printf -- '--port\n%s\n'     "$KV_port"
    printf -- '--alias\n%s\n'    "$KV_alias"
    printf -- '--ctx-size\n%s\n' "$KV_ctx_size"
    [ -n "$KV_api_key_file" ]  && printf -- '--api-key-file\n%s\n'  "$KV_api_key_file"
    [ -n "$KV_chat_template" ] && printf -- '--chat-template\n%s\n' "$KV_chat_template"
    if [ -n "$KV_extra_flags" ]; then
        # shellcheck disable=SC2086
        for tok in $KV_extra_flags; do
            printf '%s\n' "$tok"
        done
    fi
}

_dry_run() {
    _parse_block "$1"
    _emit_argv
}

_start() {
    local id="$1" old_IFS argv
    _parse_block "$id"
    # startup enforcement matches --check: refuse on mode!=600 or missing file
    if [ -n "$KV_api_key_file" ]; then
        _check_api_key_perm "$KV_api_key_file" "$id" refuse
    fi
    _warn_if_public_host "$id"

    # Emit under DEFAULT IFS so `for tok in $KV_extra_flags` inside _emit_argv
    # word-splits on whitespace as intended. Only then switch to newline-only
    # IFS for the final `set --` expansion, which needs to keep any argv value
    # that contains a space (paths, prompts) as one positional.
    argv=$(_emit_argv)
    old_IFS=$IFS
    IFS='
'
    # shellcheck disable=SC2046,SC2086
    set -- $argv
    IFS=$old_IFS
    exec "$@"
}

# --- dispatch ---------------------------------------------------------

if [ $# -eq 0 ]; then
    _help
    exit 64
fi

case "$1" in
    -h|--help)
        _help
        ;;
    --list)
        _require_conf
        _list_ids
        ;;
    --dry-run)
        [ $# -ge 2 ] || _die "--dry-run needs an <id> argument" 64
        _dry_run "$2"
        ;;
    --check)
        if [ $# -ge 2 ]; then
            _check_id "$2"
        else
            _check_all
        fi
        ;;
    -*)
        _die "unknown option: $1 (try --help)" 64
        ;;
    *)
        _start "$1"
        ;;
esac
