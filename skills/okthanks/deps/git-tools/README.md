# git-tools (dependency of okthanks)

PowerShell 7 module that wraps `git commit` so a `VERSION` file (SemVer), a
Keep-a-Changelog `CHANGELOG.md` and a `## 📋 Latest Changes` block in
`README.md` stay in sync, in one atomic commit. okthanks calls it in Step 5.

## Load it

okthanks imports it on demand from the `git_tools_module` path in `config.json`.
To have it in every shell, add to your PowerShell profile (`$PROFILE`):

```powershell
Import-Module "$HOME/.claude/skills/okthanks/deps/git-tools/git-tools.psm1"
```

Verify: `Get-Command gcommit, init-changelog`

## Functions

| Name | Alias | Purpose |
|---|---|---|
| `Initialize-RepoChangelog` | `init-changelog` | One-time per repo. Creates `VERSION` (0.1.0), `CHANGELOG.md`, injects the Latest block into `README.md`. |
| `Save-Repo` | `gcommit` | Parses a conventional-commit message, bumps version, prepends CHANGELOG entry, refreshes README Latest, `git add -A` + commit. |
| `Get-RepoVersion` | - | Current `VERSION` (defaults `0.0.0`). |
| `Update-RepoLatest` | - | Re-sync README Latest from CHANGELOG. |

## Bump table

| Prefix | Bump | Category |
|---|---|---|
| `feat:` | minor | Added |
| `fix:` | patch | Fixed |
| `perf:` | patch | Performance |
| `refactor:` `docs:` `chore:` `style:` `test:` `build:` `ci:` `revert:` | patch | Changed / Documentation / Maintenance / ... |
| `<type>!:` or `BREAKING CHANGE:` in body | **major** | BREAKING |
| no prefix | patch | Changed |

`gcommit "feat: x" -DryRun` shows the plan without writing anything.
Plain `git commit` still works whenever you do not want a bump.

## Not PowerShell?

okthanks falls back to `git add -A && git commit -m "chore: session <date> <slug>"`
and skips the version bump. The module is PowerShell 7 only; a bash port is welcome.
