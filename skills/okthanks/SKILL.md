---
name: okthanks
description: Auto-archive the current Claude Code session to the user's Obsidian vault, drop a resumable continuity file inside every workspace folder touched this session, AND commit the work. Use when the user says "ok thanks", "okthanks", "/okthanks", "save this session", or signals end of session. Writes a dated vault log, appends to log.md, writes .claude/SESSION.md with the exact `claude --resume` command per project, then per-touched-folder: update README docs, git init if needed, init-changelog if needed, gcommit (commit + CHANGELOG + SemVer bump), then run the project's declared run/test command and, if it passes, its declared deploy command.
---

# okthanks — save session + hand off + commit work

This skill carries the user's **standing authorization** for actions that are otherwise blocked by the workspace-level `CLAUDE.md` (the "manual-commit" policy):
- Running `git init` inside a workspace subfolder that has no repo yet.
- Running `git add -A` + `git commit` (via `gcommit`) without re-asking each time.
- Writing/overwriting `.claude/SESSION.md`, `.claude/sessions/*.md`, and appending a marked continuity block to `CLAUDE.md` inside those same folders.
- Editing `README.md` documentation sections to reflect this session's work.
- Running the `run` and `deploy` commands a project declares in `.claude/okthanks.json` (Step 5.5). Never an undeclared deploy.

The trigger phrase itself ("ok thanks") IS the permission. No further confirmation needed during the flow. If the user types just "save the session" with no commit intent, still run the full skill — that's the point of this skill existing.

This is a **rigid** skill. Follow the steps in order. Do not adapt.

---

## Step 0 — Load config

Read `~/.claude/skills/okthanks/config.json` (copy `config.example.json` and edit the paths on first use). Every path below is a config key — never hardcode them. Use:
- `vault_path` — Obsidian vault root
- `sessions_subdir`, `wiki_subdir`, `log_file` — vault layout
- `workspace_root` — the umbrella folder holding all your project repos (never auto-init this)
- `git_tools_module` — path to `git-tools.psm1`
- `gitignore_template` — path to universal `.gitignore`
- `project_pointer_file` — `.claude/SESSION.md` (per-project handoff, overwritten each session)
- `project_sessions_subdir` — `.claude/sessions` (per-project dated archive)
- `project_history_rows` — how many past sessions to keep in the pointer's history table
- `inject_claude_md_pointer` — whether to add the continuity block to the project's `CLAUDE.md`
- `claude_projects_dir` — where Claude Code stores session transcripts

---

## Step 1 — Capture session identity (needed to resume)

You need three values. Get them **before** writing anything.

**`SESSION_ID`** — resolve in this order:
1. `$env:CLAUDE_CODE_SESSION_ID` — authoritative, set by the runtime. Use this.
2. Your own scratchpad path in the system prompt, shaped
   `...\Temp\claude\<project-key>\<SESSION_ID>\scratchpad` — the second-to-last segment.
3. Newest `.jsonl` in `<claude_projects_dir>/<project-key>/` (the live transcript).

```powershell
$sid = $env:CLAUDE_CODE_SESSION_ID
if (-not $sid) {
    $key     = "<LAUNCH_CWD>" -replace '[:\\/]', '-'   # the LAUNCH cwd, not a subfolder
    $projDir = Join-Path "<claude_projects_dir>" $key
    $sid     = (Get-ChildItem $projDir -Filter *.jsonl |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1).BaseName
}
```

**`LAUNCH_CWD`** — the working directory this session was started in
(e.g. `C:\dev\my-workspace`). **Not** the touched subfolder. In the VS Code extension
this is the folder VS Code has open.

**`ENTRYPOINT`** — `$env:CLAUDE_CODE_ENTRYPOINT`. `claude-vscode` means the VS Code
extension; anything else means the terminal CLI. This decides which resume
instructions go first in the handoff — but **always write both**, because the user
may switch.

> **The constraint that governs everything here.** Claude Code indexes sessions by
> the directory the session was launched from (`<claude_projects_dir>/<cwd with `:`,
> `\`, `/` → `-`>`). The `/resume` picker and `claude --resume` only see sessions
> belonging to the **current** folder. A session launched at `<workspace_root>`
> is invisible from `<workspace_root>\some-project`, and vice versa.
>
> So the handoff must name **the exact folder to open**, not just a session ID.
> Getting this wrong produces a file that looks helpful and silently doesn't work.

Build both resume forms once and reuse them verbatim in every file:

**VS Code:** open `<LAUNCH_CWD>` as the workspace folder → Claude panel → type
`/resume` → pick the entry matching `<SESSION_ID>` (the picker is a list; no UUID
typing needed).

**Terminal:**
```bash
cd <LAUNCH_CWD posix form>
claude --resume <SESSION_ID>
```

---

## Step 2 — Save session log to vault

Pick a short kebab-case topic slug (3–6 words) summarizing the session's main thread.

Write `<vault_path>/<sessions_subdir>/YYYY-MM-DD-<topic>.md` with sections:
- `## Summary` — 2–3 sentence recap
- `## Files Changed` — bulleted list with absolute paths
- `## Decisions` — non-obvious choices and why
- `## Follow-ups` — open items for next session
- `## Resume` — both resume forms from Step 1 (VS Code folder + `/resume`, and the
  `cd` + `claude --resume <SESSION_ID>` terminal block)

Append one line to `<vault_path>/<log_file>`:
```
- YYYY-MM-DD HH:MM — <topic> — see [[YYYY-MM-DD-<topic>]]
```

For each `[[wikilink]]` candidate, leave it as-is. Obsidian will resolve existing pages and mark unresolved ones as page-stubs to write later. **Do not modify existing wiki pages.**

---

## Step 3 — Identify folders touched this session

Build a set of distinct project roots from files edited, written, or created during this session. For each touched file path:

1. Walk up the directory tree looking for an existing `.git/` folder.
2. If found → use that repo root.
3. If not found before reaching the drive root → use the **immediate child of `workspace_root`** as the candidate root (i.e. `<workspace_root>/<some-folder>/`).
4. If the candidate root **equals** `workspace_root` itself → **skip it.** Never auto-init the umbrella.
5. If a file lives entirely outside `workspace_root` and has no enclosing `.git/` → **skip it.** Only auto-init inside the workspace.

Deduplicate. The result is the per-folder list used by Steps 4 and 5.

Also skip:
- The vault path itself (`<vault_path>`) — that's the session log target, not project work.
- Anything under `~/.claude/` — these are Claude config dirs.

---

## Step 4 — Write the per-folder continuity files

**Run this BEFORE Step 5.** The commit phase does `git add -A`, so these files must
exist first or they land in the *next* session's commit.

For **each** project root from Step 3:

### 4a. Dated archive entry

Create `<repo>/<project_sessions_subdir>/` if missing, then write
`<repo>/<project_sessions_subdir>/YYYY-MM-DD-<slug>.md`. If that filename already
exists, suffix `-2`, `-3`, … Never overwrite a past archive entry.

Content: the same four sections as the vault log, but **scoped to this folder** —
`## Files Changed` lists only paths inside this repo.

### 4b. Pointer file (overwritten every session)

Before overwriting, **read the existing `<repo>/<project_pointer_file>`** and pull out
its `## Historial` table rows so they carry forward.

Write `<repo>/<project_pointer_file>` with exactly this shape:

```markdown
# 🔄 Última sesión — <slug>

## ▶ Retomar la conversación completa

**En VS Code** (abre esta carpeta, no otra):

> `<LAUNCH_CWD>`
>
> Panel de Claude → escribe `/resume` → elige la sesión `<SESSION_ID>`.

**En terminal:**

> ```bash
> cd <LAUNCH_CWD posix form>
> claude --resume <SESSION_ID>
> ```

> ⚠ La carpeta importa: el picker de `/resume` solo muestra sesiones lanzadas
> desde **esa misma carpeta**. Si abres una subcarpeta o el padre, la sesión no
> aparece — no está borrada, está indexada en otro sitio.

| | |
|---|---|
| **Fecha** | YYYY-MM-DD HH:MM |
| **Sesión** | `<SESSION_ID>` |
| **Carpeta a abrir** | `<LAUNCH_CWD>` |
| **Entorno** | VS Code / terminal |
| **Log completo** | `<vault_path>/<sessions_subdir>/YYYY-MM-DD-<slug>.md` |
| **Archivo local** | `<project_sessions_subdir>/YYYY-MM-DD-<slug>.md` |

## Dónde nos quedamos
<2–4 frases: estado real del proyecto al cerrar, no un resumen de lo que hiciste>

## Qué se tocó en esta carpeta
- `ruta/relativa.ext` — qué cambió y por qué

## Decisiones
- <decisión> — <razón>

## Próximos pasos
- [ ] <acción concreta>

## Historial
| Fecha | Tema | Resume ID |
|---|---|---|
| YYYY-MM-DD | <slug> | `<SESSION_ID>` |
<...hasta `project_history_rows` filas anteriores, más nuevas arriba...>
```

Rules for the pointer:
- **"Dónde nos quedamos" describes state, not activity.** "El endpoint `/sync` funciona
  pero no tiene tests" is useful. "Trabajamos en el endpoint de sync" is not.
- Keep it under ~60 lines. It is a handoff, not a transcript.
- Trim the history table to `project_history_rows` rows.

### 4c. Make the new terminal actually read it

Only if `inject_claude_md_pointer` is true.

`.claude/SESSION.md` is **not** auto-loaded by Claude Code — only `CLAUDE.md` is. So the
pointer has to be advertised there, or a fresh terminal will never look at it.

Check `<repo>/CLAUDE.md` for the marker `<!-- OKTHANKS:CONTINUITY:START -->`.
- If present → leave the file completely alone.
- If absent → **append** (never prepend, never rewrite) this block. Create `CLAUDE.md`
  with just this block if the file doesn't exist.

```markdown

<!-- OKTHANKS:CONTINUITY:START -->
## 🔄 Continuidad de sesión

Antes de responder cualquier cosa en este proyecto, lee `.claude/SESSION.md`.
Contiene el estado real al cerrar la última sesión, los próximos pasos, y el
comando exacto (`cd` + `claude --resume <id>`) para retomar la conversación
anterior con todo su contexto. El historial por fecha vive en `.claude/sessions/`.
<!-- OKTHANKS:CONTINUITY:END -->
```

---

## Step 4.5 — Document (README)

For each project root, make `README.md` describe what the project does **now**:
- New feature, command, env var, port, endpoint or setup step this session → add/update it in the matching README section (Usage, Setup, Config…). Create the section if missing.
- Removed/renamed things → update or delete their mention.
- Env vars by **name only**, never values.
- Do **not** touch the `## 📋 Latest Changes` block — `gcommit` owns it.
- Nothing user-facing changed (pure refactor, notes) → leave README alone.

Minimal, factual edits. No rewrites of sections the session didn't touch. This runs **before** Step 5 so docs ride in the same commit.

---

## Step 5 — Per-folder commit phase

For **each** project root in the list, in order, run this exact PowerShell sequence via the `Bash` or `PowerShell` tool:

```powershell
# Always load the git-tools module first (idempotent).
Import-Module "<git_tools_module>" -Force   # from config.json; ships in deps/git-tools/

# --- 5a. Ensure repo exists ---
$repo = "<absolute-folder-path>"
if (-not (Test-Path (Join-Path $repo ".git"))) {
    git -C $repo init -b main
    # Copy universal .gitignore only if none present.
    if (-not (Test-Path (Join-Path $repo ".gitignore"))) {
        Copy-Item "<gitignore_template>" (Join-Path $repo ".gitignore")   # from config.json; ships in deps/
    }
}

# --- 5b. Guard: the continuity files must not be silently ignored ---
# If this repo's .gitignore excludes .claude/, `git add -A` would drop the
# handoff without a word. Force-add once: tracked files ignore .gitignore
# from then on, so this self-heals after the first session.
git -C $repo check-ignore -q ".claude/SESSION.md" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "NOTE: .claude/ is gitignored in $repo — force-adding continuity files."
    git -C $repo add -f ".claude/SESSION.md" ".claude/sessions"
}

# --- 5c. Quick gate: any changes? ---
$pending = git -C $repo status --porcelain
if (-not $pending) {
    Write-Host "Nothing to commit in $repo — skipping."
    continue   # move to next folder
}

# --- 5d. Ensure changelog scaffolding ---
$hasVersion   = Test-Path (Join-Path $repo "VERSION")
$hasChangelog = Test-Path (Join-Path $repo "CHANGELOG.md")
if (-not $hasVersion -or -not $hasChangelog) {
    Initialize-RepoChangelog -Path $repo
}

# --- 5e. Commit via gcommit ---
$slug   = "<topic-slug-from-step-2>"
$today  = (Get-Date).ToString('yyyy-MM-dd')
$prefix = "<feat|fix|chore>"   # feat: new capability (minor), fix: bug fix (patch), else chore (patch)
Save-Repo -Message "${prefix}: session $today $slug" -Path $repo
```

Notes:
- Use `git init -b main` — default branch policy from the workspace `CLAUDE.md`.
- `Initialize-RepoChangelog` creates `VERSION` (0.1.0), `CHANGELOG.md` (with `<!-- CHANGELOG:ENTRIES -->` marker), and injects the `## 📋 Latest Changes` block into `README.md` (creating `README.md` if missing).
- Pick `$prefix` from what the session did in **this folder**: shipped a new capability → `feat:`; fixed a bug → `fix:`; docs/notes/refactor → `chore:`. Never `!`/`BREAKING CHANGE` unless the user said so.
- `Save-Repo` (alias `gcommit`) parses the prefix → SemVer bump, prepends a CHANGELOG entry, refreshes README Latest, then `git add -A` + commits in one atomic step.
- If the brand-new repo has no commits yet, `Save-Repo`'s `git add -A` + `git commit` becomes the initial commit. That's correct.
- The Step 4 files are already on disk, so they ride along in this same commit.

Do **not** `git push`. These repos are local-only by policy.

---

## Step 5.5 — Run + deploy (declared only)

Read `<repo>/.claude/okthanks.json`. Format:

```json
{
  "run":    "npm test",
  "deploy": "pwsh ./deploy.ps1",
  "timeout_sec": 600
}
```

Both keys optional. No file → skip both, summary says `run/deploy: not declared`.

1. **Run** — if `run` exists, execute it in `$repo` (timeout `timeout_sec`, default 600). Must be finite: a test, build or smoke check, never a dev server that never exits. Capture exit code + last ~20 lines.
2. **Deploy** — only if `deploy` exists **and** the commit in 5e succeeded (or nothing to commit) **and** `run` passed (or isn't declared). Execute in `$repo`, same timeout. Capture exit code + last ~20 lines.
3. Run failed → **do not deploy**. Report the failing output; don't try to fix it.

Never invent a run or deploy command from package.json, Dockerfile, etc. If a folder looks deployable but has no `okthanks.json`, suggest the file in the summary — don't create it.

---

## Step 6 — Summary output

Print a one-block summary at the end:

```
✓ Session archived
  Vault:   <vault relative path of session file>
  Log:     appended to <log_file>
  Resume:  VS Code → abre <LAUNCH_CWD> → /resume → <SESSION_ID>
           terminal → cd <LAUNCH_CWD> && claude --resume <SESSION_ID>

✓ Handoff written
  - <folder-1>/.claude/SESSION.md   (+ CLAUDE.md pointer added)
  - <folder-2>/.claude/SESSION.md   (CLAUDE.md pointer already present)

✓ Commits
  - <folder-1>   v<old> → v<new>   <short-sha>
  - <folder-2>   v<old> → v<new>   <short-sha>
  - <folder-3>   skipped (nothing to commit)
  - <folder-4>   skipped (outside workspace)

✓ Docs
  - <folder-1>   README: updated Usage, Config
  - <folder-2>   README: no user-facing change

✓ Run / Deploy
  - <folder-1>   run ✓ (npm test)   deploy ✓ (pwsh ./deploy.ps1)
  - <folder-2>   run ✗ exit 1 → deploy skipped   <last error line>
  - <folder-3>   not declared (suggest .claude/okthanks.json)
```

---

## Hard rules

- **Never** `git push` to a remote. Workspace policy: local-only. (A declared `deploy` command is the only outward action allowed.)
- **Never** deploy without a declared `deploy` command, or after a failed run/commit.
- **Never** use `--force`, `--hard`, `--no-verify`, or `--amend`.
- **Never** init a repo at `workspace_root` itself.
- **Never** touch existing `.git/` internals.
- **Never** stage files inside the vault path or `~/.claude/` (those aren't project code).
- **Never** write secrets into `.claude/SESSION.md` or `.claude/sessions/*` — no API keys,
  passwords, tokens, or `.env` values. Reference them by variable name only
  (`STRIPE_SECRET_KEY en .env`). These files are committed and a repo can gain a remote later.
- **Never** rewrite an existing `CLAUDE.md`. Append the marked block once, or do nothing.
- **Never** overwrite a dated file in `.claude/sessions/` — suffix instead.
- Write the Step 4 files **before** the Step 5 commit, never after.
- If `git-tools.psm1` can't be imported (e.g. shell isn't PowerShell), fall back to plain `git -C <repo> add -A && git -C <repo> commit -m "chore: session <date> <slug>"` and **skip the version-bump/changelog step entirely** — note this in the summary.
- If any step fails for a folder (commit hook failure, etc.): stop on that folder, report the error in the summary, but continue with remaining folders. Do not try to "fix" hook failures silently.
- Do not phone home.

---

## Companion skills — Open Steps (credit)

This repository bundles the nine `os-*` skills from **Open Steps** by
[Pavlo Kharmanskyi](https://github.com/kharmanskyi) —
<https://github.com/kharmanskyi/open-steps> — MIT License, copied verbatim
(see `third_party/open-steps/LICENSE`). They are not part of this skill's steps;
they shape how the agent *talks* to the person running the work:

| Moment | Skill |
|---|---|
| "what's next / what's left / what's blocked" | `os-whats-next` |
| Any technical question or options offered to the user | `os-ask-simple` |
| Something hard to undo is about to be agreed | `os-what-could-go-wrong` |
| Asking the user to run, paste, approve, click | `os-step-by-step` |
| Other sessions, accepting finished work | `os-check-work` |
| Work is finished, "how did it go", ticket status | `os-done-or-not` |
| "I don't understand", "shorter", "what does this mean" | `os-say-simple` |
| "where are we", "what's in the project", "what went stale" | `os-big-picture` |

Suggested pairing: after Step 6 of okthanks, if the user asks how it went,
`os-done-or-not` produces the plain-language report. Add the routing block in
`docs/open-steps-routing-block.md` to your `~/.claude/CLAUDE.md` so these skills
fire reliably.
