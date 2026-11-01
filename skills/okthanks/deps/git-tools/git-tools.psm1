# =====================================================================
# git-tools.psm1  —  Local-git versioning + CHANGELOG + README automation
# =====================================================================
# Workspace-local PowerShell module for a folder of local-only git repos.
# Provides a wrapper around `git commit` that maintains a SemVer
# VERSION file, a Keep-a-Changelog CHANGELOG.md, and a "Latest"
# section in README.md — all in one atomic commit.
#
# Functions exported:
#   Initialize-RepoChangelog (alias: init-changelog)
#       One-time per-repo opt-in. Creates VERSION + CHANGELOG.md and
#       injects a "## 📋 Latest" section into README.md.
#
#   Save-Repo (alias: gcommit)
#       Wrapper around `git commit`. Bumps version per conventional
#       commit type, prepends to CHANGELOG, refreshes Latest section.
#       Usage: gcommit "feat: add search bar"
#
#   Get-RepoVersion       Read current VERSION (defaults to 0.0.0 if missing).
#   Update-RepoLatest     Re-sync README Latest section from CHANGELOG.
#
# Convention: conventional-commits message format
#   <type>(<optional scope>)<!>: <subject>
#       feat  → minor bump → ### Added
#       fix   → patch bump → ### Fixed
#       perf  → patch bump → ### Performance
#       refactor/docs/chore/style/test/build/ci → patch → ### Changed/etc.
#       `!` after type OR "BREAKING CHANGE:" in body → MAJOR bump
# =====================================================================

# --- internal helpers ---------------------------------------------------

$script:BumpMap = @{
    'feat'     = 'minor'; 'fix'      = 'patch'; 'perf'     = 'patch'
    'refactor' = 'patch'; 'docs'     = 'patch'; 'chore'    = 'patch'
    'style'    = 'patch'; 'test'     = 'patch'; 'build'    = 'patch'
    'ci'       = 'patch'; 'revert'   = 'patch'
}

$script:CategoryMap = @{
    'feat'     = 'Added';         'fix'      = 'Fixed';      'perf'     = 'Performance'
    'refactor' = 'Changed';       'docs'     = 'Documentation'
    'chore'    = 'Maintenance';   'style'    = 'Style';      'test'     = 'Tests'
    'build'    = 'Build';         'ci'       = 'CI';         'revert'   = 'Reverted'
}

function script:Assert-GitRepo {
    param([string]$Path)
    $isRepo = git -C $Path rev-parse --is-inside-work-tree 2>$null
    if (-not $isRepo) {
        throw "Not inside a git repository: $Path"
    }
}

function script:Get-RepoRoot {
    param([string]$Path)
    return (git -C $Path rev-parse --show-toplevel 2>$null).Trim()
}

function script:Parse-Conventional {
    param([string]$Message)
    $type = 'chore'; $subject = $Message; $breaking = $false
    if ($Message -match '^(?<type>\w+)(\((?<scope>[\w\-\.\/]+)\))?(?<bang>!)?:\s*(?<subject>.+)$') {
        $type = $Matches['type'].ToLower()
        $subject = $Matches['subject'].Trim()
        $breaking = $Matches['bang'] -eq '!'
    }
    if ($Message -match 'BREAKING\s*CHANGE') { $breaking = $true }

    $bump = if ($breaking) { 'major' } else {
        if ($script:BumpMap.ContainsKey($type)) { $script:BumpMap[$type] } else { 'patch' }
    }
    $category = if ($breaking) { 'BREAKING' } else {
        if ($script:CategoryMap.ContainsKey($type)) { $script:CategoryMap[$type] } else { 'Changed' }
    }

    return [PSCustomObject]@{
        Type     = $type
        Subject  = $subject
        Breaking = $breaking
        Bump     = $bump
        Category = $category
    }
}

function script:Step-Version {
    param([string]$Current, [string]$Bump)
    $parts = $Current.Split('.') | ForEach-Object { [int]$_ }
    while ($parts.Count -lt 3) { $parts += 0 }
    switch ($Bump) {
        'major' { return "$($parts[0]+1).0.0" }
        'minor' { return "$($parts[0]).$($parts[1]+1).0" }
        'patch' { return "$($parts[0]).$($parts[1]).$($parts[2]+1)" }
    }
    throw "Unknown bump type: $Bump"
}

# --- public functions ---------------------------------------------------

function Get-RepoVersion {
    [CmdletBinding()]
    param([string]$Path = (Get-Location).Path)
    Assert-GitRepo $Path
    $root = Get-RepoRoot $Path
    $vfile = Join-Path $root 'VERSION'
    if (Test-Path $vfile) {
        return (Get-Content $vfile -Raw).Trim()
    }
    return '0.0.0'
}

function Initialize-RepoChangelog {
    [CmdletBinding()]
    [Alias('init-changelog')]
    param(
        [string]$Path = (Get-Location).Path,
        [string]$InitialVersion = '0.1.0'
    )
    Assert-GitRepo $Path
    $root = Get-RepoRoot $Path
    $name = Split-Path $root -Leaf

    $vfile = Join-Path $root 'VERSION'
    $clfile = Join-Path $root 'CHANGELOG.md'
    $rdfile = Join-Path $root 'README.md'

    # VERSION
    if (-not (Test-Path $vfile)) {
        Set-Content -Path $vfile -Value $InitialVersion -NoNewline -Encoding utf8
        Write-Host "  + VERSION ($InitialVersion)" -ForegroundColor Green
    } else {
        Write-Host "  = VERSION (already exists: $(Get-RepoVersion -Path $Path))" -ForegroundColor Yellow
    }

    # CHANGELOG.md
    if (-not (Test-Path $clfile)) {
        $today = (Get-Date).ToString('yyyy-MM-dd')
        $tpl = @"
# Changelog

All notable changes to this project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org).

<!-- CHANGELOG:ENTRIES -->

## [$InitialVersion] - $today

### Added
- Initial release. Project established with local-git versioning.
"@
        Set-Content -Path $clfile -Value $tpl -Encoding utf8
        Write-Host "  + CHANGELOG.md" -ForegroundColor Green
    } else {
        Write-Host "  = CHANGELOG.md (already exists, untouched)" -ForegroundColor Yellow
    }

    # README.md — inject Latest section
    $latestBlock = @"

---

## 📋 Latest Changes

<!-- LATEST:BEGIN -->
*Run ``gcommit "type: message"`` to record changes here.*
<!-- LATEST:END -->

See full [CHANGELOG.md](CHANGELOG.md) for complete history.
"@

    if (-not (Test-Path $rdfile)) {
        $rdNew = "# $name`n`n_Add a project description here._`n$latestBlock`n"
        Set-Content -Path $rdfile -Value $rdNew -Encoding utf8
        Write-Host "  + README.md (with Latest section)" -ForegroundColor Green
    } else {
        $current = Get-Content $rdfile -Raw
        if ($current -match '<!-- LATEST:BEGIN -->') {
            Write-Host "  = README.md (Latest section already present)" -ForegroundColor Yellow
        } else {
            $current = $current.TrimEnd() + "`n" + $latestBlock + "`n"
            Set-Content -Path $rdfile -Value $current -Encoding utf8
            Write-Host "  + README.md (Latest section appended)" -ForegroundColor Green
        }
    }

    Write-Host "Repo '$name' is changelog-enabled. Use ``gcommit ""type: message""`` to commit." -ForegroundColor Cyan
}

function Update-RepoLatest {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path,
        [int]$Entries = 5
    )
    Assert-GitRepo $Path
    $root = Get-RepoRoot $Path
    $clfile = Join-Path $root 'CHANGELOG.md'
    $rdfile = Join-Path $root 'README.md'
    if (-not (Test-Path $clfile)) {
        Write-Warning "No CHANGELOG.md in $root — run Initialize-RepoChangelog first."
        return
    }
    if (-not (Test-Path $rdfile)) {
        Write-Warning "No README.md in $root."
        return
    }

    # Pull the last N version sections from CHANGELOG (everything after CHANGELOG:ENTRIES marker)
    $clContent = Get-Content $clfile -Raw
    $afterMarker = if ($clContent -match '<!-- CHANGELOG:ENTRIES -->\s*(?<rest>[\s\S]+)$') { $Matches['rest'] } else { $clContent }

    # Split by "## [" headings (version sections)
    $sections = [System.Text.RegularExpressions.Regex]::Split($afterMarker, '(?=^## \[)', [System.Text.RegularExpressions.RegexOptions]::Multiline) `
        | Where-Object { $_ -match '^## \[' } `
        | Select-Object -First $Entries
    $latestText = if ($sections.Count -eq 0) { '*No entries yet.*' } else { ($sections -join "`n").TrimEnd() }

    # Replace inside LATEST:BEGIN/END markers
    $rd = Get-Content $rdfile -Raw
    if ($rd -notmatch '<!-- LATEST:BEGIN -->[\s\S]*?<!-- LATEST:END -->') {
        Write-Warning "README.md has no LATEST:BEGIN/END markers. Run Initialize-RepoChangelog to add them."
        return
    }
    $newBlock = "<!-- LATEST:BEGIN -->`n$latestText`n<!-- LATEST:END -->"
    $rdUpdated = [regex]::Replace($rd, '<!-- LATEST:BEGIN -->[\s\S]*?<!-- LATEST:END -->', { param($m) $newBlock })
    Set-Content -Path $rdfile -Value $rdUpdated -Encoding utf8
}

function Save-Repo {
    [CmdletBinding()]
    [Alias('gcommit')]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Message,

        [string]$Path = (Get-Location).Path,

        [switch]$DryRun,

        [int]$LatestEntries = 5
    )

    Assert-GitRepo $Path
    $root = Get-RepoRoot $Path
    $name = Split-Path $root -Leaf
    $vfile = Join-Path $root 'VERSION'
    $clfile = Join-Path $root 'CHANGELOG.md'

    if (-not (Test-Path $clfile) -or -not (Test-Path $vfile)) {
        Write-Warning "Repo '$name' is not changelog-enabled. Run Initialize-RepoChangelog first, or use plain ``git commit``."
        return
    }

    $pending = git -C $root status --porcelain 2>$null
    if (-not $pending) {
        Write-Host "Nothing to commit in '$name'." -ForegroundColor Yellow
        return
    }

    $parsed = Parse-Conventional $Message
    $current = Get-RepoVersion -Path $root
    $next = Step-Version -Current $current -Bump $parsed.Bump
    $today = (Get-Date).ToString('yyyy-MM-dd')

    # Build CHANGELOG entry
    $entry = "## [$next] - $today`n`n### $($parsed.Category)`n- $($parsed.Subject)`n"
    if ($parsed.Breaking -and $parsed.Category -ne 'BREAKING') {
        $entry += "`n### BREAKING CHANGES`n- This release contains breaking changes.`n"
    }

    Write-Host "=== gcommit summary ===" -ForegroundColor Cyan
    Write-Host "  Repo:     $name"
    Write-Host "  Type:     $($parsed.Type)$(if($parsed.Breaking){'!'}) → $($parsed.Bump) bump"
    Write-Host "  Version:  $current → $next"
    Write-Host "  Category: $($parsed.Category)"
    Write-Host "  Subject:  $($parsed.Subject)"
    Write-Host "  Pending:  $((($pending | Measure-Object -Line).Lines)) files"

    if ($DryRun) {
        Write-Host "DRY RUN — no changes written." -ForegroundColor Yellow
        return
    }

    # Update VERSION
    Set-Content -Path $vfile -Value $next -NoNewline -Encoding utf8

    # Prepend entry to CHANGELOG (after CHANGELOG:ENTRIES marker)
    $cl = Get-Content $clfile -Raw
    if ($cl -match '<!-- CHANGELOG:ENTRIES -->') {
        $cl = $cl -replace '<!-- CHANGELOG:ENTRIES -->', "<!-- CHANGELOG:ENTRIES -->`n`n$entry"
    } else {
        $cl = $entry + "`n" + $cl
    }
    Set-Content -Path $clfile -Value $cl -Encoding utf8

    # Refresh README Latest
    Update-RepoLatest -Path $root -Entries $LatestEntries

    # Stage everything and commit
    git -C $root add -A 2>&1 | Out-Null
    $commitMsg = "$($parsed.Type)$(if($parsed.Breaking){'!'}): $($parsed.Subject) [v$next]"
    $out = git -C $root commit -m $commitMsg 2>&1
    if ($LASTEXITCODE -eq 0) {
        $sha = (git -C $root rev-parse --short HEAD).Trim()
        Write-Host "✓ Committed $sha — v$next" -ForegroundColor Green
    } else {
        Write-Host "✗ Commit failed: $out" -ForegroundColor Red
    }
}

Export-ModuleMember -Function Save-Repo, Initialize-RepoChangelog, Get-RepoVersion, Update-RepoLatest -Alias gcommit, init-changelog
