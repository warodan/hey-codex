# Codex CLI — reference

Details behind `SKILL.md`: installation, config, rare flags, pitfalls. Read this when the basic call
did not work or the user asks for something non-standard.

- [Where things live](#where-things-live) — paths, authentication, model cache
- [Updating](#updating) — `codex update` and how it gets triggered
- [Config](#config-codexconfigtoml) — what affects calls, **sandbox warning**
- [Models and effort](#models-and-effort) — model list, the `model_reasoning_effort` scale
- [`codex exec` flags](#codex-exec-flags) — full table
- [Other subcommands](#other-subcommands) — `resume`, `review`, `apply`, `doctor`, `mcp`
- [Pitfalls](#pitfalls) — **prompt as an argument on Windows**, hanging at start, encoding,
  unknown feature flag, untrusted directory, error 400, YAML
- [Cost](#cost) — subscription spend

## Where things live

| | |
|---|---|
| binary | npm package `@openai/codex`; the path on a given machine — `command -v codex` |
| authentication | ChatGPT account (`codex login status` → `Logged in using ChatGPT`), not an API key |
| config | `~/.codex/config.toml`, or `$CODEX_HOME/config.toml` if the variable is set |
| sessions | `~/.codex/sessions/`, index `~/.codex/session_index.jsonl`, logs `~/.codex/log/` |
| Codex skills | `~/.agents/skills/` (shared with Claude Code) |
| model cache | `~/.codex/models_cache.json` (refreshed from the server, holds `client_version`) |

## Updating

```bash
codex update            # runs npm install -g @openai/codex
codex --version         # verify
```

- `npm warn cleanup … EPERM … codex.exe` during an update is **normal** (the old exe is in use), the update goes through.
- `check_update.sh` does this automatically (TTL 24 h, stamp `~/.codex/.claude-skill-update-check`).
- To reset the TTL and force a check: `rm ~/.codex/.claude-skill-update-check` and run the script.
- Manual route if `codex update` did not work: `npm install -g @openai/codex`.

## Config (`~/.codex/config.toml`)

The config belongs to the user and the skill does not write to it. The values below are the ones that
affect calls; what a particular person has set is something to look at, not to assume:

```toml
model = "gpt-5.6-sol"                 # the default model
model_reasoning_effort = "high"       # low → medium → high → xhigh → max → ultra
sandbox_mode = "workspace-write"      # see the warning below
approval_policy = "on-request"
service_tier = "default"              # "priority" = 1.5x speed
```

**Warning.** If the config holds `sandbox_mode = "danger-full-access"` together with
`approval_policy = "never"`, Codex gets full disk access and works without a single confirmation —
in every mode, including the interactive TUI, not just through this skill. The skill defends against
that by passing `--sandbox read-only` in every call, but the defence covers its own calls only.
The safe combination is `workspace-write` + `on-request`; the skill works exactly the same with it.

Plus `[projects.'<path>'] trust_level = "trusted"` sections — trusted folders. In an untrusted folder
without `--skip-git-repo-check` you get `Not inside a trusted directory`.

Do not edit the config silently: it is the user's shared file, also used by the interactive TUI.

## Models and effort

From `~/.codex/models_cache.json` (check there for the current list):

- `gpt-5.6-sol` — the main agentic model (default), `gpt-5.6-luna`, `gpt-5.6-terra`
- `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini` — previous ones

`model_reasoning_effort` levels: `low` → `medium` → `high` → `xhigh` → `max` → `ultra`
(`ultra` = maximum plus automatic delegation of subtasks). The model's own default is `low`;
the user's config may say otherwise — that is their choice, do not change it unasked.

Speed: `service_tier = "default"` (normal) or `"priority"` (called Fast in the UI, 1.5×).

## `codex exec` flags

| Flag | What for |
|---|---|
| `-o, --output-last-message <FILE>` | final answer into a file — the main way to collect the result |
| `--json` | JSONL event stream on stdout (only needed to parse the run as it goes) |
| `-s, --sandbox <read-only\|workspace-write\|danger-full-access>` | disk permissions |
| `-C, --cd <DIR>` | the agent's working root |
| `--add-dir <DIR>` | an extra folder made writable |
| `--skip-git-repo-check` | run outside a git repository |
| `-m, --model`, `-c key=value` | model and any config overrides (a TOML value) |
| `--enable/--disable <FEATURE>` | feature flags, the same as `-c features.<name>=true/false`. List — `codex features list`. `plugins` mutes the plugin layer; nothing turns Codex skills off, and `skill_search` does not hide them |
| `-i, --image <FILE>` | attach an image to the prompt |
| `--ephemeral` | do not save the session to disk (then `resume --last` will not see it) |
| `--ignore-user-config` | do not read `config.toml` (model and effort fall away — set them by hand) |
| `--output-schema <FILE>` | JSON Schema for the shape of the final answer |
| `-p, --profile <NAME>` | profile `$CODEX_HOME/<name>.config.toml` layered over the base one |

`PROMPT` is positional; if the prompt is not passed, or is given as `-`, it is read from stdin — that
is the main way to pass it, see pitfall 1.

## Other subcommands

- `codex exec resume --last [PROMPT]` / `resume <SESSION_ID>` — resume a session (`--all` drops the cwd filter).
  `resume` has **no** `--sandbox` and no `-C`: the sandbox is set with `-c sandbox_mode="read-only"`,
  and the working folder is inherited from the original session. It does have: `-m`, `-c`, `-o`, `--json`,
  `-i`, `--enable/--disable`, `--skip-git-repo-check`, `--ephemeral`, `--ignore-user-config`, `--output-schema`
- `codex review` — non-interactive code review of a repository
- `codex apply` — apply the agent's last diff to the working tree as `git apply`
- `codex fork` — fork a past session
- `codex doctor` — diagnostics for the installation, config and authentication
- `codex mcp` — manage external MCP servers for Codex; `codex mcp-server` — run Codex itself as an MCP server (stdio)
- `codex features list|enable|disable` — feature flags
- `codex sandbox <cmd>` — run a command inside the Codex sandbox
- `codex` with no arguments — the interactive TUI (for the user, not for an agent)

## Pitfalls

1. **A prompt passed as an argument breaks on Windows.** The call goes through `codex.cmd` there,
   and cmd.exe parses the command line. Three outcomes, all out of nowhere:
   - a multi-line prompt arrives as **its first line only**, and everything that stood after it in
     the command — including `-o` — is lost. Exit code 0, a plausible answer but to the wrong
     question, and no answer file. The most expensive case: the failure is completely invisible;
   - a prompt starting with an empty line disappears entirely — Codex goes looking for it on stdin
     and hits `/dev/null`: `Reading prompt from stdin...` → `No prompt provided via stdin.`,
     exit code 1;
   - an `&` in the text splits the command, and the tail goes to cmd.exe as a separate line.

   Cured by passing the prompt on stdin, with no positional argument: `codex exec … < prompt.txt`,
   or from Python — `subprocess.run(cmd, input=prompt, text=True, encoding="utf-8", errors="replace")`.
   From Git Bash a multi-line argument goes through fine, which is why manual runs never show the
   pitfall while a script hits it consistently.
2. **Hangs at start** — nothing is occupying stdin: exec waits for input ("Reading additional input
   from stdin"). Either a prompt file, or `< /dev/null`.
3. **Encoding on Windows — three different places, each cured differently:**
   - the Codex answer arrives through a pipe as mojibake (cp1251) — collect it with `-o <file>` and
     read the file instead of stdout;
   - printing Codex output from your own script kills the script: `UnicodeEncodeError: 'charmap' codec
     can't encode character '\xd7'` — the output holds characters outside cp1251 (`×`, `—`). The crash
     happens **after** the work is done and paid for, and looks like the work failed. Cured in the
     calling code: `sys.stdout.reconfigure(encoding="utf-8", errors="replace")`;
   - a prompt piped into stdin from PowerShell 5.1 arrives as `????`: `$OutputEncoding` there
     defaults to ASCII. Cured with a line before the pipe:
     `$OutputEncoding = [System.Text.UTF8Encoding]::new($false)`.
4. **`Error: Unknown feature flag: <name>`, exit code 1** — the CLI build is older than the feature
   itself: `--disable` on an unknown name kills the whole call and leaves no `-o` file. That is why
   the skill body uses the `-c features.<name>=false` form — an old CLI simply ignores an unknown
   config key. The radical cure is `codex update`.
5. **`Not inside a trusted directory`** — add `--skip-git-repo-check` or run from a trusted folder.
   `resume` has this flag too, and needs it too if the original session ran in an untrusted folder.
6. **`400 … model requires a newer version of Codex`** — the CLI is behind the server-side model
   catalogue (`client_version` in `models_cache.json` is higher than `codex --version`). Cured by
   `codex update`; the temporary workaround is `-m gpt-5.5`.
7. **The sandbox from the config may be unsafe** — pass `--sandbox` explicitly in every call, do not
   rely on what the user has set (see the "Config" section).
8. **An unquoted `description:` can stop a skill from loading** — a colon-space inside the value
   (for example `Triggers: …`) is not valid YAML for a strict parser, and the skill is dropped with
   `failed to load skill … invalid YAML: mapping values are not allowed in this context`. Codex
   0.147 swallows it, earlier builds did not, so single quotes around the whole value stay the safe
   habit rather than a fix for one version. The error goes to stderr on any run, catch it like this:
   `codex exec --sandbox read-only "ok" < /dev/null 2>&1 | grep "failed to load"`.
9. **`codex update` emits an EPERM warning** about deleting the old `codex.exe` — harmless, the version changes.

## Cost

The work runs on the user's ChatGPT subscription, not on an API key. The spend is shown at the end of
the output (`tokens used`). Heavy runs (`ultra`, large refactors) burn through the subscription limit —
if a task is obviously big, say so before launching.
