# okthanks

Say **"ok thanks"** and Claude Code closes the session properly: archives a
session log to your Obsidian vault, writes a resumable handoff into every
project folder it touched, updates the README, commits with a SemVer bump and
CHANGELOG entry, then runs each project's declared test and deploy command.

The next session (terminal or VS Code) opens the right folder, reads
`.claude/SESSION.md`, and can `claude --resume` the exact conversation.

Bundled with the **Open Steps** skills by Pavlo Kharmanskyi (MIT) so the agent
also *reports* in plain language. See [Credits](#credits).

## What "ok thanks" does

1. Captures the session ID, launch folder and entrypoint (VS Code vs terminal).
2. Writes `Sessions/YYYY-MM-DD-<topic>.md` in your vault and appends one line to `log.md`.
3. Finds every project folder touched (nearest `.git/`, else immediate child of your workspace root).
4. Per folder: dated archive in `.claude/sessions/`, overwritten pointer `.claude/SESSION.md` with the `cd` + `claude --resume <id>` command and a history table, and a one-time continuity block appended to the project's `CLAUDE.md`.
5. Per folder: README section updates for anything user-facing that changed.
6. Per folder: `git init -b main` if needed, universal `.gitignore`, `init-changelog`, then `gcommit "<feat|fix|chore>: session <date> <slug>"`.
7. Per folder: runs the `run` and `deploy` commands declared in `.claude/okthanks.json`. Never invents one. No deploy if run fails.
8. Prints a one-block summary.

Hard rules: never `git push`, never `--force` / `--amend` / `--no-verify`, never
init at the workspace root, never write secrets into handoff files.

## Install

Requires Claude Code, git, and PowerShell 7 for the version-bump step (without
PowerShell the skill falls back to a plain commit).

```powershell
git clone https://github.com/<your-user>/okthanks-skill.git
Copy-Item -Recurse okthanks-skill/skills/* "$HOME/.claude/skills/"
Copy-Item "$HOME/.claude/skills/okthanks/config.example.json" "$HOME/.claude/skills/okthanks/config.json"
notepad "$HOME/.claude/skills/okthanks/config.json"   # edit every path
```

Config keys:

| Key | Meaning |
|---|---|
| `vault_path` | Obsidian vault root. Session logs go to `<vault>/Sessions/`, one line per session in `<vault>/log.md`. |
| `workspace_root` | Umbrella folder that holds your project repos. Never auto-initialized. |
| `git_tools_module` | Path to `deps/git-tools/git-tools.psm1` (ships in this repo). |
| `gitignore_template` | Path to `deps/gitignore-template.txt` (ships in this repo). |
| `claude_projects_dir` | Where Claude Code stores transcripts, normally `~/.claude/projects`. |
| `project_history_rows` | How many past sessions the pointer's history table keeps. |
| `inject_claude_md_pointer` | Append the continuity block to each project's `CLAUDE.md`. |

Then add the Open Steps routing block to `~/.claude/CLAUDE.md` so the `os-*`
skills fire on the right moments:

```bash
grep -q 'os-done-or-not' ~/.claude/CLAUDE.md 2>/dev/null || cat docs/open-steps-routing-block.md >> ~/.claude/CLAUDE.md
```

### Optional per-project `.claude/okthanks.json`

```json
{ "run": "npm test", "deploy": "pwsh ./deploy.ps1", "timeout_sec": 600 }
```

Both keys optional. `run` must be finite (test, build, smoke check), never a dev server.

## Workspace policy this skill assumes

okthanks carries a *standing authorization* to `git init`, `git add -A` and
`git commit` inside workspace subfolders. If your workspace `CLAUDE.md` has a
manual-commit rule (recommended), say there that "ok thanks" is the one
exception. Repos are treated as local-only; `git push` is never run.

## Layout

```
skills/okthanks/            the skill: SKILL.md + config.example.json
skills/okthanks/deps/       git-tools.psm1 (gcommit, init-changelog) + gitignore-template.txt
skills/os-*/                Open Steps skills, verbatim (MIT)
docs/open-steps-routing-block.md
third_party/open-steps/LICENSE
```

## Notes

- Handoff files (`.claude/SESSION.md`) are written in Spanish. Edit the template in Step 4b of `SKILL.md` for another language.
- Session resume is scoped to the launch folder: `/resume` and `claude --resume` only list sessions started from the folder you have open. The handoff names that folder explicitly for this reason.

## Credits

- okthanks skill and `git-tools` module: Hector M. Diaz, MIT, see [LICENSE](LICENSE).
- **Open Steps** (`skills/os-*`, routing block): [Pavlo Kharmanskyi](https://github.com/kharmanskyi), https://github.com/kharmanskyi/open-steps, MIT. Included unmodified; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Thank you, Pavlo.

---

## 📋 Latest Changes

<!-- LATEST:BEGIN -->
## [0.2.0] - 2026-11-01

### Added
- okthanks skill public release with bundled Open Steps skills (MIT, Pavlo Kharmanskyi) and git-tools dependency



## [0.1.0] - 2026-11-01

### Added
- Initial release. Project established with local-git versioning.
<!-- LATEST:END -->

See full [CHANGELOG.md](CHANGELOG.md) for complete history.


