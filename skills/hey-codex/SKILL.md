---
name: hey-codex
description: 'Use when the user wants to reach OpenAI Codex CLI (GPT-6 Astra, GPT-5.6) — ask it a question, hand it a task by spec so it writes the code in the project, get a second opinion from another model, read an image or a screenshot, generate a picture; also updating Codex CLI itself and diagnosing its errors. Triggers: "ask codex", "call codex", "give codex a task", "let codex write it", "send this to codex", "ask codex to write/review/look at/draw", "what does codex say", "ask codex to clarify", "have codex generate an image", "hey codex", "update codex", "which codex version", "codex crashed", "codex is not responding", "codex error", hey-codex, codex, codex exec. Russian: «вызови кодекс», «спроси кодекса», «дай кодексу задачу», «отправь в кодекс», «попроси кодекса написать/проверить/посмотреть/нарисовать», «что скажет кодекс», «уточни у кодекса», «пусть кодекс сгенерирует картинку», «эй кодекс», «обнови кодекс», «какая версия кодекса», «кодекс упал», «кодекс не отвечает», «ошибка codex».'
---

# hey-codex — calling the OpenAI Codex CLI

Codex runs locally (`codex`, npm `@openai/codex`, sign-in through ChatGPT). This file is how to call it.
Rare flags, diagnostics and pitfalls live in `REFERENCE.md` next to it.

**What the machine needs:** Node.js and npm, `codex` installed (`npm install -g @openai/codex`)
with `codex login` done, a POSIX shell for `sh` and for stdin redirection (on Windows — Git Bash;
§2 has a separate PowerShell form), git for §3, network access. If `codex` is missing or not
logged in — tell the user and do not try to install it yourself.

## 0. Update check — first thing

`check_update.sh` sits next to this file. Run it at the start of a call:

```bash
for p in "${CLAUDE_SKILL_DIR}" ~/.claude/skills/hey-codex ~/.agents/skills/hey-codex \
         ./.claude/skills/hey-codex ./.agents/skills/hey-codex; do
  [ -n "$p" ] && [ -f "$p/check_update.sh" ] && { sh "$p/check_update.sh"; break; }
done; true
```

The line finds the script on its own. `CLAUDE_SKILL_DIR` is not an environment variable — Claude
Code substitutes the real skill directory into this file as it loads it, so the first candidate
points at wherever the skill was actually installed. An agent that does not substitute it leaves it
empty, `[ -n "$p" ]` skips that candidate, and the standard install locations are tried instead.
**If the script is not found, just skip the step and carry on** — do not fix paths or hunt for it
manually: without it the skill works fully, only the automatic version check is lost.

The script keeps a TTL: checked less than 24 h ago — instant `skipped`, nothing happens. Otherwise
it compares the version against npm and, when Codex is behind, runs the update without asking
(`codex update`, ~1 min).
Show the user this line **only** if there was an update or an error; `skipped`/`up to date` — stay quiet.

## 1. Defaults come from the config, not from flags

Model, reasoning effort and speed come from the user's `~/.codex/config.toml`. **Leave them out of
the command** — those are the user's settings, and it is their choice that counts here, not your own
ideas. Add flags only when the user explicitly asked for something else (see §6); the one
exception is reasoning effort on a heavy §3 task.

**The sandbox is the opposite — always set it.** The config may hold
`sandbox_mode = "danger-full-access"` together with `approval_policy = "never"`: then, without an
explicit flag, Codex gets full disk access and writes without asking. You cannot rely on a safe
value being there. So **the sandbox is set explicitly in every call**: `--sandbox read-only` (on `resume` — `-c sandbox_mode="read-only"`, §7); `workspace-write` only in §3 and for image generation in §5.

## 2. Normal call — question / analysis / second opinion

**The prompt goes in through stdin as a file, not as a command argument.** Write it to a temp
folder and pass it by redirect:

```bash
codex exec --sandbox read-only -c features.plugins=false \
  -C "<project root>" -o "<temp folder>/codex-answer-1.md" < "<temp folder>/prompt.txt"
```

- `-c features.plugins=false` — so Codex thinks for itself. Plugins slip it someone else's
  instructions ("first call the matching skill"), and it reads them on every call: in measurements
  the same question cost several times more. The flag mutes the plugin layer; the skills installed
  in Codex stay visible to it — those cannot be turned off this way
- stdin must be occupied by something, otherwise the command hangs waiting for input
- a prompt passed as an argument goes through `codex.cmd` on Windows: everything after the first
  newline is silently lost, together with the flags that follow it (`REFERENCE.md`, pitfall 1)
- `-o <file>` — the final Codex answer without the service noise; read **that**, do not parse stdout
- `-C` — the current project root, so Codex sees the code and `AGENTS.md`
- stdout stays visible: `session id: <uuid>` for §7 comes from there (the answer itself comes from
  the `-o` file)

The `<` operator is understood by POSIX shells only. If commands go through PowerShell, the prompt
is piped in, and the encoding line is mandatory (`REFERENCE.md`, pitfall 3).

```powershell
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Get-Content -Raw -Encoding UTF8 prompt.txt | codex exec --sandbox read-only -c features.plugins=false -C "<project root>" -o "<temp folder>/codex-answer-1.md"
```

Both lines are required: without `$OutputEncoding` the prompt arrives as `????`, Codex answers the
garbled prompt and exits with code 0 — the failure is invisible; without `-Encoding UTF8` the file
is read as ANSI and is transcoded twice. The other calls in this skill
(§3, §4, §5, §7) are assembled the same way in PowerShell — same pipe instead of `<`.

The flag comes off at the user's request — "let it work with its plugins". If a specific Codex skill
is needed, name it in the prompt: skills are visible to it either way.

The form `-c features.plugins=false` was chosen over `--disable plugins` on purpose: it does not
break the call on older CLI builds where the feature does not exist yet.

Before launching, write one line in chat — the whole line in the user's language, label included:
`Sending to Codex: <gist of the prompt>`. Do not wait for approval.

**What goes into the prompt.** By default — the user's question verbatim plus a 2–3 line header:
what the project is, which files to look at, what has already been established (Codex cannot see
our conversation). A bare question with no header — when the user asks to "ask it word for word",
or when the task is self-contained (write a prompt for an image generator, explain a concept, come
up with some copy). That case is §4.

## 3. A task by spec — Codex writes the code, only when explicitly asked

If the user said "let codex write it / fix it itself / give codex the task": you write the spec,
Codex implements it in the project, you rerun the done-check. Without that explicit request —
always `read-only` (§2), and you apply Codex's edits yourself.

```bash
codex exec --sandbox workspace-write -c features.plugins=false \
  -C "<project root>" --add-dir "<temp folder>/codex-tmp" \
  -o "<temp folder>/codex-task-1.md" < "<temp folder>/spec.md"
```

`--add-dir` gives Codex a writable scratch folder outside the project. Without it, on Windows the
sandbox cannot reach the system TEMP, so Codex puts pytest temp dirs and caches inside the
project (`.tmp/`, `.test-runs/`) — and is then refused deleting them. Name that folder in the
spec's Constraints (see the template).

Model and effort come from the config (§1). Heavy task — add `-c model_reasoning_effort="xhigh"`.
`ultra` only when the user hands Codex the whole organisation of the work: on `ultra` Codex
delegates to its own subagents by itself, past your spec, and spends the subscription fastest.
A long task goes to the background (§8).

**The spec** is the file on stdin. Every part is required — Codex cannot see our conversation:

```markdown
# Task: <name>

## Result
What exists when it is done. One testable sentence.

## Context
What the project is; which files or modules this touches; what has already been established.

## Constraints
Stack. Do not touch: … Out of scope: …
Temporary files, test temp dirs (`pytest --basetemp`) and caches go to `<temp folder>/codex-tmp`,
never inside the project.

## Check
The exact command(s) and the expected outcome; the manual scenario, if any.
Done when: … Run the check, fix, rerun — without asking. A money / data / outward / access
fork: stop with STATUS: BLOCKED and say what is needed.

## Subagents
<one of> Do it yourself. | You may use subagents. | Split into subagents, up to N: independent
pieces only, never two on the same files. <Which model and effort each gets is Codex's call.>

## Report
Up to 25 lines, no code, no diffs, no narration of the work:
STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
FILES: created and changed
CHECKS: command → result and exit code, verbatim, including the ones that failed
CONCERNS: done with an assumption or a workaround, and why
BLOCKERS: what was missing (decision, access, dependency)
```

If the check runs Python, name the interpreter path in Context: inside `workspace-write` on
Windows the `python` from the Microsoft Store alias is denied (`REFERENCE.md`, pitfall 10).

**After the answer** — do not take CHECKS on trust: rerun the done-check command yourself, then
show `git status` / `git diff --stat`. Reading the whole diff and review rounds are not required
unless the user asks. A fix round reuses the session so Codex keeps its context:

```bash
codex exec resume <session id> -c sandbox_mode="workspace-write" -c features.plugins=false \
  -c 'sandbox_workspace_write.writable_roots=["<temp folder>/codex-tmp"]' \
  -o "<temp folder>/codex-task-2.md" < "<temp folder>/findings.md"
```

`resume` has no `--add-dir`; the `writable_roots` key is the same scratch folder in config form —
without it the fix round writes its temp files into the project again.

`findings.md` is a list of what failed and what "fixed" means; the same Report form. Two rounds
at most — a third means the spec is wrong, rewrite it.

## 4. Bare question — no project

```bash
cd "<temp folder>" && codex exec --sandbox read-only --skip-git-repo-check \
  -c features.plugins=false -o "codex-answer-1.md" < "prompt.txt"
```

Running from an empty temp folder = Codex sees neither the project `AGENTS.md` nor its code. Its own
skills stay with it — there is nothing that isolates it completely. Codex records that folder as
trusted in the user's `config.toml` (`REFERENCE.md`, pitfall 11): mention it, the config stays theirs.

## 5. Images — looking and generating

Codex does both. This is not about code: reading a screenshot, a diagram or a table off a photo,
generating an illustration all belong here.

**Look at an image** — the `-i` flag, repeatable, sandbox as usual:

```bash
codex exec --sandbox read-only --skip-git-repo-check -c features.plugins=false \
  -i "<path.png>" -o "<temp folder>/codex-image.md" < "<temp folder>/prompt.txt"
```

It reads precisely: colours in hex, element positions, fine print. Good for working out an error
screenshot, pulling data off a photo of a document, describing a layout.

**Generate an image** — needs `workspace-write`: the result is saved to disk as a file, and in
`read-only` it cannot write it.

The line "Save it to `<name>.png`" goes into the same prompt file.

```bash
codex exec --sandbox workspace-write --skip-git-repo-check -c features.plugins=false \
  -C "<output folder>" -o "<temp folder>/codex-gen.md" < "<temp folder>/gen-prompt.txt"
```

- the drawing is done by the built-in Codex generator, not by code — this is real generation
- an image attached with `-i` acts as a reference: "in this style", "replace the background"
- it handles transparent backgrounds, editing an existing image, series of variants
- fine print and strict geometry do not always come out on the first try — check the result and ask
  for a redo if needed
- the path to the finished file is given in the answer; show it to the user as a link
- if what failed was the printing of the output, not the generation (`UnicodeEncodeError` on a
  character like `×`) — the image is already on disk and already paid for: check the folder before
  launching a retry

"Draw / generate / make me a picture" goes straight here, not to §2.

## 6. Overrides at the user's request

| Request | Flag |
|---|---|
| a different model | `-m gpt-5.6-sol` (options: `gpt-6-astra`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`; the live list is in `REFERENCE.md`) |
| "think harder" | `-c model_reasoning_effort="xhigh"` (scale: low, medium, high, xhigh, max, ultra — the top levels are not on every model, see `REFERENCE.md`) |
| "make it faster" | `-c service_tier="priority"` (1.5× speed, higher spend) |

## 7. Follow-ups — resume the session

A question on the same topic ("ask it to clarify", "what would it say about…") — resume, Codex
remembers its analysis and does not re-read the code:

```bash
codex exec resume --last -c sandbox_mode="read-only" -c features.plugins=false \
  -o "<temp folder>/codex-answer-2.md" < "<temp folder>/prompt-2.txt"
```

**Careful**: `resume` has no `--sandbox` and no `-C` — set the sandbox only through
`-c sandbox_mode="read-only"` (otherwise `danger-full-access` from the config kicks in), and the
working folder is inherited from that session. Its untrusted status is inherited too: a §4 session
ran in a temp folder, so its `resume` needs `--skip-git-repo-check`.

`--last` takes the most recent session filtered by the current cwd — if several branches of the
conversation ran in parallel, take the id from the output header (`session id: <uuid>`) and resume
it precisely: `codex exec resume <uuid> …`.

A new topic — a normal §2 call (clean session).

## 8. Long tasks — send them to the background

A question or an analysis — wait for the answer. A large task ("write a module", "refactor the
package", "make a series of images") — launch it in the background by whatever means your agent
has, carry on with your own work and report when it is done. Such runs take minutes and do not fit
the usual command timeout.

## 9. How to deliver the answer

The Codex answer comes from the `-o` file, verbatim, under a **Codex answer** heading — do not
retell it in your own words. Longer than ~40 lines — leave it in the file, give a clickable link
and a 3–5 line summary. Your own opinion, if it differs from Codex, goes in a **separate** block
afterwards — keep it out of the quoted Codex text.

## 10. Quick diagnostics

```bash
codex --version && codex login status
```

`400 … requires a newer version of Codex` → the CLI is behind, `codex update` (§0 does this itself).
Everything else — `REFERENCE.md`.
