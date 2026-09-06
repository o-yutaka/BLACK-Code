Set-StrictMode -Version Latest

# Persistent delta index: the per-repo cache carries HEAD, tracked and
# untracked delta, package roots, and likely affected tests across runs, so the
# boot capsule stays small while later queries still get full delta answers.

function Get-BlackCodeIndexHash([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-BlackCodeGitCommand {
    $git = Get-Command "git.exe" -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command "git" -ErrorAction SilentlyContinue }
    return $git
}

function Normalize-BlackCodePath([object]$Value) {
    if ($null -eq $Value) { return $null }
    $text = ([string]$Value).Trim()
    if (-not $text) { return $null }
    return $text.Replace('\\','/')
}

function Invoke-BlackCodeGitLines([object]$Git,[string]$Root,[string[]]$GitArgs) {
    $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { $rows = @(& $Git.Source -C $Root @GitArgs 2>$null) }
    finally { $ErrorActionPreference = $eap }
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($rows | ForEach-Object { Normalize-BlackCodePath $_ } | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-BlackCodeRepoIndex(
    [string]$ProjectRoot,
    [string]$IndexRoot
) {
    $resolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $repoKey = Get-BlackCodeIndexHash $resolved.ToLowerInvariant()
    $repoDir = Join-Path $IndexRoot $repoKey
    $indexPath = Join-Path $repoDir "index.json"
    $contextPath = Join-Path $repoDir "repo-context.md"
    New-Item -ItemType Directory -Force -Path $repoDir | Out-Null

    $git = Get-BlackCodeGitCommand
    if (-not $git) {
        $fallback = [ordered]@{
            schema_version = "2.0"
            project_root = $resolved
            cache_status = "NO_GIT"
            git_head = $null
            tracked_file_count = $null
            untracked_file_count = $null
            changed_files = @()
            untracked_files = @()
            package_roots = @()
            test_files = @()
            likely_tests = @()
        }
        $fallback | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $indexPath
        "# BLACK Repo Capsule`n`nNo Git index available. Use read-only inspection per task: read/grep only what the task requires." | Set-Content -Encoding UTF8 $contextPath
        return [ordered]@{ index = $fallback; index_path = $indexPath; context_path = $contextPath }
    }

    # Windows PowerShell 5.1 cannot invoke an application directly in the
    # middle of a parenthesized pipeline on some UNC-backed worktrees and
    # promotes native stderr to a terminating error under StrictMode/Stop.
    $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { $headRows = @(& $git.Source -C $resolved rev-parse HEAD 2>$null) }
    finally { $ErrorActionPreference = $eap }
    $head = $headRows | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $head) { $head = $null } else { $head = ([string]$head).Trim() }

    $cached = $null
    if (Test-Path -LiteralPath $indexPath) {
        try { $cached = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json -AsHashtable } catch {}
    }

    # Do not use `git status -uno`: new files are first-class BLACK Code delta.
    # `git diff HEAD` covers staged + unstaged tracked changes; ls-files covers untracked.
    $trackedWorkingDelta = if ($head) {
        @(Invoke-BlackCodeGitLines $git $resolved @("diff","--name-only","HEAD","--","."))
    } else { @() }
    $untrackedFiles = @(Invoke-BlackCodeGitLines $git $resolved @("ls-files","--others","--exclude-standard"))

    $sameHead = $cached -and $cached.git_head -and $head -and ($cached.git_head -eq $head)
    $cleanReuse = $sameHead -and @($trackedWorkingDelta).Count -eq 0 -and @($untrackedFiles).Count -eq 0

    if ($cleanReuse) {
        $cached.cache_status = "HIT"
        $cached.last_used_at = (Get-Date).ToString("o")
        if (-not $cached.ContainsKey("untracked_files")) { $cached["untracked_files"] = @() }
        if (-not $cached.ContainsKey("untracked_file_count")) { $cached["untracked_file_count"] = 0 }
        $cached | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $indexPath
        return [ordered]@{ index = $cached; index_path = $indexPath; context_path = $contextPath }
    }

    $tracked = @(Invoke-BlackCodeGitLines $git $resolved @("ls-files"))
    $currentFiles = @(@($tracked) + @($untrackedFiles) | Sort-Object -Unique)

    $packageRoots = @($currentFiles | Where-Object {
        $_ -match '(^|/)(package\.json|pyproject\.toml|Cargo\.toml|go\.mod|Directory\.Build\.props|[^/]+\.sln)$'
    } | ForEach-Object {
        $parent = Split-Path -Parent $_
        if ([string]::IsNullOrWhiteSpace($parent)) { "." } else { $parent.Replace('\\','/') }
    } | Sort-Object -Unique)

    $testFiles = @($currentFiles | Where-Object {
        $_ -match '(^|/)(__tests__|tests?|specs?)(/|$)' -or $_ -match '(\.test\.|\.spec\.|_test\.|Tests?\.)'
    } | Sort-Object -Unique)

    $changed = [System.Collections.Generic.List[string]]::new()
    foreach ($f in @($trackedWorkingDelta)) { if ($f) { [void]$changed.Add($f) } }
    foreach ($f in @($untrackedFiles)) { if ($f) { [void]$changed.Add($f) } }

    if ($cached -and $cached.git_head -and $head -and $cached.git_head -ne $head) {
        $committedDelta = @(Invoke-BlackCodeGitLines $git $resolved @("diff","--name-only",$cached.git_head,$head,"--","."))
        foreach ($f in @($committedDelta)) { if ($f) { [void]$changed.Add($f) } }
    }
    $changedFiles = @($changed | Sort-Object -Unique)

    # New/untracked files are first-class delta and affect likely-test mapping;
    # the capsule below keeps them visible without pre-injecting the full tree.
    $likely = [System.Collections.Generic.List[string]]::new()
    foreach ($changedFile in $changedFiles) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($changedFile)
        if (-not $stem) { continue }
        $changedDir = (Split-Path -Parent $changedFile).Replace('\\','/')
        foreach ($testFile in $testFiles) {
            $testName = [IO.Path]::GetFileNameWithoutExtension($testFile)
            $testDir = (Split-Path -Parent $testFile).Replace('\\','/')
            $sameStem = $testName -like "$stem*" -or $stem -like "$testName*"
            $sameDir = $testDir -eq $changedDir
            $samePackage = $false
            foreach ($root in $packageRoots) {
                if ($root -eq ".") { continue }
                $prefix = $root.TrimEnd('/') + '/'
                if ($changedFile.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and $testFile.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
                    $samePackage = $true; break
                }
            }
            if ($sameStem -or $sameDir -or $samePackage) { [void]$likely.Add($testFile) }
        }
    }
    $likelyTests = @($likely | Sort-Object -Unique | Select-Object -First 80)

    $record = [ordered]@{
        schema_version = "2.0"
        project_root = $resolved
        generated_at = (Get-Date).ToString("o")
        last_used_at = (Get-Date).ToString("o")
        cache_status = if ($cached) { "DELTA_REFRESH" } else { "MISS_BUILD" }
        git_head = $head
        previous_git_head = if ($cached) { $cached.git_head } else { $null }
        tracked_file_count = @($tracked).Count
        untracked_file_count = @($untrackedFiles).Count
        changed_files = $changedFiles
        untracked_files = @($untrackedFiles | Select-Object -First 200)
        package_roots = $packageRoots
        test_file_count = @($testFiles).Count
        test_files = @($testFiles | Select-Object -First 400)
        likely_tests = $likelyTests
    }
    $record | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $indexPath

    $lines = [System.Collections.Generic.List[string]]::new()
    $headLabel = if ($head) { [string]$head } else { "" }
    if ($headLabel.Length -gt 8) { $headLabel = $headLabel.Substring(0, 8) }
    $topDirs = @($currentFiles | ForEach-Object { if ($_ -match '^([^/]+)/') { $Matches[1] } else { "." } } | Sort-Object -Unique | Select-Object -First 16)

    [void]$lines.Add("# BLACK Repo Capsule (delta context; expand on demand)")
    [void]$lines.Add("")
    [void]$lines.Add("- Cache: $($record.cache_status) | Git HEAD: $headLabel")
    [void]$lines.Add("- Tracked: $($record.tracked_file_count) | Untracked: $($record.untracked_file_count) | Tests: $($record.test_file_count)")
    if ($packageRoots.Count -gt 0) { [void]$lines.Add("- Packages: $([string]::Join(', ', @($packageRoots | Select-Object -First 8)))") }
    if ($topDirs.Count -gt 0) { [void]$lines.Add("- Top dirs: $([string]::Join(', ', $topDirs))") }
    if (@($record.changed_files).Count -gt 0) {
        [void]$lines.Add("")
        [void]$lines.Add("## Changed (first 15)")
        foreach ($f in @($record.changed_files | Select-Object -First 15)) { [void]$lines.Add("- $f") }
        $extraChanged = @($record.changed_files).Count - 15
        if ($extraChanged -gt 0) { [void]$lines.Add("- ... +$extraChanged more (read `git status --short` or the index file for all)") }
    }
    if ($likelyTests.Count -gt 0) {
        [void]$lines.Add("")
        [void]$lines.Add("## Likely affected tests (first 6)")
        foreach ($f in @($likelyTests | Select-Object -First 6)) { [void]$lines.Add("- $f") }
    }
    [void]$lines.Add("")
    [void]$lines.Add("Do not pre-scan the repository. Read/grep only what the task requires. Full index: $indexPath")
    $lines | Set-Content -Encoding UTF8 $contextPath

    return [ordered]@{ index = $record; index_path = $indexPath; context_path = $contextPath }
}
