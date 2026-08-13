# servers.conf schema

`servers.conf` declares one or more llama-server instances that
`vdgg-llm-start` can launch. This document is the **source of truth** for the
schema; the launcher script (`scripts/vdgg-llm-start.sh`) and the example file
(`references/servers.conf.example`) must stay consistent with what is written
here.

`vdgg-llm-start` is deliberately llama.cpp-only. If you run a different
inference server (Ollama, vLLM, mlx-server, LM Studio server), fork this
launcher and adapt it — the schema is not a portable abstraction, it is a thin
declarative wrapper over `llama-server`'s own flags.

## Location

By default the launcher reads:

```
${VDGG_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/vdgg}/servers.conf
```

Override with `VDGG_SERVERS_CONF=/path/to/servers.conf`.

## Syntax

- Each server is a `[id]` block header followed by `key=value` lines.
- `id` is an identifier used on the command line (`vdgg-llm-start <id>`); it
  should be short, lowercase, and unique.
- Blank lines and lines starting with `#` are ignored.
- Values are literal strings, without shell interpretation, with two
  exceptions:
  - A leading `$HOME`, `${HOME}`, or `~/` is expanded to the current user's
    home directory. No other variable is expanded.
  - Surrounding double quotes are stripped (`key="foo"` and `key=foo` are
    equivalent).

Example:

```
[qwen]
model=$HOME/models/qwen3-27b-q4_k_m.gguf
host=127.0.0.1
port=8081
alias=qwen-coder
ctx_size=65536
chat_template=chatml
api_key_file=$HOME/.config/vdgg/llama-api-key
extra_flags=--parallel 1 --no-ui --no-slots

[gemma]
model=$HOME/models/gemma-4-12b-q4_k_m.gguf
host=127.0.0.1
port=8082
alias=gemma-review
ctx_size=32768
api_key_file=$HOME/.config/vdgg/llama-api-key
```

## Required keys

Every server block must define these four keys. `--check` refuses a block
that omits any of them.

| Key         | Meaning                                                       |
|-------------|---------------------------------------------------------------|
| `model`     | Absolute path to the `.gguf` file, or an `-hf ...` / `hf:...` reference passed straight to `llama-server`. |
| `port`      | TCP port `llama-server` will listen on.                       |
| `alias`     | Model alias exposed to clients through the OpenAI-compatible API. |
| `ctx_size`  | Context window (tokens).                                      |

## Optional keys

| Key             | Meaning                                                                    |
|-----------------|----------------------------------------------------------------------------|
| `host`          | Bind address. Default: `127.0.0.1`. See "Security" below before changing this. |
| `chat_template` | Passed to `--chat-template`. Set to `chatml` for OpenAI-Responses-compatible clients (e.g. the Codex CLI). |
| `api_key_file`  | Path to a file whose only content is the Bearer token. The launcher **refuses to start** unless the file exists and its mode is exactly `600`. |
| `extra_flags`   | Any additional `llama-server` flags, space-separated. This is the escape hatch for flags the schema doesn't promote to a first-class key. |

`extra_flags` is a single line split on whitespace — put flag names and
their values as separate tokens (`--parallel 1`, not `--parallel=1`). Values
containing spaces are not supported.

## Security

- **`host` defaults to `127.0.0.1`.** Binding all interfaces (`0.0.0.0`,
  `::`) is legal but is treated as a deliberate choice: both `--check` and
  startup emit a warning that anyone on the LAN can reach the port. If the
  network is untrusted, front the server with Tailscale or a TLS reverse
  proxy — the API key alone is not enough on public Wi-Fi.
- **`api_key_file` must be mode `600`.** The launcher refuses to start
  otherwise (exit code 4). This is checked both at startup and by
  `--check <id>`.
- **Never write the key inline in `servers.conf`.** Point at a separate file
  and let file permissions do the work.

## CLI contract

The launcher exposes these subcommands (see `scripts/vdgg-llm-start.sh`):

| Command                       | Behavior                                                                                             |
|-------------------------------|------------------------------------------------------------------------------------------------------|
| `vdgg-llm-start --help`       | Print usage.                                                                                          |
| `vdgg-llm-start --list`       | Print each `[id]` header in the order it appears in the file.                                         |
| `vdgg-llm-start --dry-run <id>` | Print the exact `llama-server` argv it would exec, one token per line. **This is what `<id>` runs.** |
| `vdgg-llm-start --check <id>` | Lint a single block: missing keys, model file, `api_key_file` permissions, port range, host warning. |
| `vdgg-llm-start --check`      | Lint the whole file: per-block checks plus port and alias uniqueness across all blocks.               |
| `vdgg-llm-start <id>`         | `exec` `llama-server` with the argv from `--dry-run <id>`.                                            |

Exit codes:

| Code | Meaning                                                                                       |
|------|-----------------------------------------------------------------------------------------------|
| 0    | Success (`--check` clean; launch replaced by `llama-server`).                                 |
| 2    | The requested `<id>` is not defined in `servers.conf`, or a required key is missing.          |
| 4    | `api_key_file` is missing or has the wrong permissions.                                       |
| 64   | Usage error (`--dry-run` without an id, unknown option, no arguments).                        |

## Adding a new key

If you need to expose a new `llama-server` flag as a first-class key:

1. Update this document first — this file is the schema's source of truth.
2. Update `scripts/vdgg-llm-start.sh` to parse the key (in `_parse_block`),
   emit the flag (in `_emit_argv`), and lint it (in `_check_kv`).
3. Update `references/servers.conf.example` to demonstrate the key.
4. Add a test case in the launcher's verification script.

For a one-off `llama-server` flag that doesn't warrant its own key, use
`extra_flags`.
