# AGENTS.md

Guidance for AI coding agents working in this repository.

## Ground truth

Always treat these documents as the source of truth for what Lagaw is and what it must do:

- [`docs/pitch.md`](docs/pitch.md) — the approved pitch: scope, AI feature, database schema, tech stack, and environment plan.
- [`docs/official-instructions.md`](docs/official-instructions.md) — the official course instructions: requirements, sprints, and grading rubrics.

Read them before planning or changing anything. If code, comments, or other docs conflict with them, follow these documents and flag the conflict rather than working around it.

## Codebase traversal (mandatory)

For Roel's #56 Flutter recommendation/generation integration, first read
[`ROEL_START_HERE.md`](ROEL_START_HERE.md). It documents the agreed #54 API,
replacement confirmation, response parsing and saved-plan reload flow. Keep the
approved pitch/course instructions above as ground truth and keep #56 frontend
implementation separate from #54 backend/evidence work.

This repository is indexed with CodeGraph. Use these tools, in this order:

1. **CodeGraph for anything structural** — how something works, what calls what, dependencies, imports, blast radius. Prefer the CodeGraph MCP tool (`codegraph_explore`); without MCP, use the CLI (`codegraph explore`, `codegraph callers`, `codegraph impact`). Treat returned source as already read; don't re-verify it with search.
2. **`rg` (ripgrep) for content search** — never `grep`, or the built-in grep tool.
3. **`fd` for finding files** — never `find`, glob patterns, or the built-in glob tool.
4. Only if a tool is genuinely missing (`where rg` on Windows, `which rg` elsewhere): fall back to shell `grep`/`find`, never the built-in tools.

If `.codegraph/` is missing, run `codegraph init` in the repository root first. Setup for all of this: [`docs/tooling.md`](docs/tooling.md).

## Secrets and environment files (mandatory)

Never read raw values from `.env` or any other secret store; a value that reaches a command output, log, or transcript is exposed, so treat transcripts as public. Reading `.env` with `read_file`, `cat`/`type`/`Get-Content`, `git show`, or `echo` is forbidden. The variable names and their purpose live in [`docs/pitch.md`](docs/pitch.md) §6 and `.env.example`.

Work with secrets like this instead:

1. **Read the shape, not the values.** Learn names from `.env.example`; never open `.env` itself.
2. **Check presence by name only.** `rg -o "^[A-Za-z_][A-Za-z0-9_]*=" .env` lists `NAME=` lines with no values; `rg -c "^DEEPSEEK_API_KEY=" .env` prints a match count. If a masked view is truly unavoidable, scrub it first with `sed -E "s/=.*/=<redacted>/" .env` — lines without `=` pass through unredacted, so prefer the name-only checks.
3. **Let the shell carry secrets.** When a command needs a value, reference it through the environment (`$env:DEEPSEEK_API_KEY` in PowerShell, `$DEEPSEEK_API_KEY` elsewhere); the shell expands it and the value never passes through the agent.
4. **Exercise the app, not the key.** To verify provider connectivity, run the backend or its tests — they read the environment themselves — and inspect the result, not the key.
5. **React to leaks.** If a real secret ever appears in output, a commit, or a transcript, stop, tell the user, and treat the key as compromised — rotate it.

Only `.env.example` (placeholders) is committed; `.env` and real keys stay out of Git history.

## Sprint log (mandatory)

Keep [`docs/sprint-log.md`](docs/sprint-log.md) current as work happens, following the existing dated-entry format:

- Record each project activity as it occurs: accounts and infrastructure set up, credential handoffs, provider or hosting decisions, and scope changes with their reasons.
- Name who holds a credential, never the credential itself — secret values never go in the log.
- Fill in the plan, standup, and retrospective sections as each sprint progresses. The log is evidence for consultations, so record what actually happened, not filler.

## Git conventions

Follow the branch strategy in [`README.md`](README.md#branch-strategy):

- Never commit directly to `main`; every change goes through a pull request.
- Name branches `feat/<name>`, `fix/<name>`, `chore/<name>`, `docs/<name>`, or `test/<name>`.
- Keep `main` stable and deployable; wait for CI to pass before merging.
