Set-StrictMode -Version Latest

function Get-BlackCodeIndexHash([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-BlackCodeGitCommand {
    $git = Get-Command "git.exe" -ErrorAction SilentlyContinue
    if (-not $git) { $git = Get-Command "git" -ErrorAction SilentlyContinue }
    return $git
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
            schema_version = "1.0"
            project_root = $resolved
            cache_status = "NO_GIT"
            git_head = $null
            tracked_file_count = $null
            changed_files = @()
            package_roots = @()
            test_files = @()
            likely_tests = @()
        }
        $fallback | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $indexPath
        "# BLACK Code Repo Delta Context`n`nNo Git index available. Inspect only what the task requires." | Set-Content -Encoding UTF8 $contextPath
        return [ordered]@{ index = $fallback; index_path = $indexPath; context_path = $contextPath }
    }

    $head = (& $git.Source -C $resolved rev-parse HEAD 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $head) { $head = $null } else { $head = ([string]$head).Trim() }

    $cached = $null
    if (Test-Path -LiteralPath $indexPath) {
        try { $cached = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json -AsHashtable } catch {}
    }

    $working = @(& $git.Source -C $resolved status --porcelain=v1 -uno 2>$null)
    $dirtyFiles = @($working | ForEach-Object {
        $line = [string]$_
        if ($line.Length -ge 4) { $line.Substring(3).Trim() }
    } | Where-Object { $_ } | Sort-Object -Unique)

    $sameHead = $cached -and $cached.git_head -and $head -and ($cached.git_head -eq $head)
    $cleanReuse = $sameHead -and $dirtyFiles.Count -eq 0

    if ($cleanReuse) {
        $cached.cache_status = "HIT"
        $cached.last_used_at = (Get-Date).ToString("o")
        $cached | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $indexPath
        return [ordered]@{ index = $cached; index_path = $indexPath; context_path = $contextPath }
    }

    $tracked = @(& $git.Source -C $resolved ls-files 2>$null)
    if ($LASTEXITCODE -ne 0) { $tracked = @() }
    $tracked = @($tracked | ForEach-Object { ([string]$_).Replace('\','/') } | Where-Object { $_ } | Sort-Object -Unique)

    $packageRoots = @($tracked | Where-Object {
        $_ -match '(^|/)(package\.json|pyproject\.toml|Cargo\.toml|go\.mod)$'
    } | ForEach-Object {
        $parent = Split-Path -Parent $_
        if ([string]::IsNullOrWhiteSpace($parent)) { "." } else { $parent.Replace('\','/') }
    } | Sort-Object -Unique)

    $testFiles = @($tracked | Where-Object {
        $_ -match '(^|/)(__tests__|tests?|specs?)(/|$)' -or $_ -match '(\.test\.|\.spec\.|_test\.)'
    } | Sort-Object -Unique)

    $changed = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $dirtyFiles) { if ($f) { [void]$changed.Add($f.Replace('\','/')) } }
    if ($cached -and $cached.git_head -and $head -and $cached.git_head -ne $head) {
        $committedDelta = @(& $git.Source -C $resolved diff --name-only $cached.git_head $head 2>$null)
        if ($LASTEXITCODE -eq 0) {
            foreach ($f in $committedDelta) { if ($f) { [void]$changed.Add(([string]$f).Replace('\','/')) } }
        }
    }
    $changedFiles = @($changed | Sort-Object -Unique)

    $likely = [System.Collections.Generic.List[string]]::new()
    foreach ($changedFile in $changedFiles) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($changedFile)
        if (-not $stem) { continue }
        foreach ($testFile in $testFiles) {
            $testName = [IO.Path]::GetFileNameWithoutExtension($testFile)
            $sameStem = $testName -like "$stem*" -or $stem -like "$testName*"
            $sameDir = (Split-Path -Parent $testFile) -eq (Split-Path -Parent $changedFile)
            if ($sameStem -or $sameDir) { [void]$likely.Add($testFile) }
        }
    }
    $likelyTests = @($likely | Sort-Object -Unique | Select-Object -First 40)

    $record = [ordered]@{
        schema_version = "1.0"
        project_root = $resolved
        generated_at = (Get-Date).ToString("o")
        last_used_at = (Get-Date).ToString("o")
        cache_status = if ($cached) { "DELTA_REFRESH" } else { "MISS_BUILD" }
        git_head = $head
        previous_git_head = if ($cached) { $cached.git_head } else { $null }
        tracked_file_count = $tracked.Count
        changed_files = $changedFiles
        package_roots = $packageRoots
        test_file_count = $testFiles.Count
        test_files = @($testFiles | Select-Object -First 200)
        likely_tests = $likelyTests
    }
    $record | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $indexPath

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add("# BLACK Code Repo Delta Context")
    [void]$lines.Add("")
    [void]$lines.Add("Use this persistent index before re-discovering repository structure. Re-read files only when the task or changed paths require it.")
    [void]$lines.Add("")
    [void]$lines.Add("- Cache: $($record.cache_status)")
    [void]$lines.Add("- Git HEAD: $head")
    [void]$lines.Add("- Tracked files: $($record.tracked_file_count)")
    [void]$lines.Add("- Package roots: $([string]::Join(', ', @($packageRoots | Select-Object -First 30)))")
    [void]$lines.Add("")
    [void]$lines.Add("## Changed paths")
    if ($changedFiles.Count -eq 0) { [void]$lines.Add("- none detected") } else { foreach ($f in @($changedFiles | Select-Object -First 80)) { [void]$lines.Add("- $f") } }
    [void]$lines.Add("")
    [void]$lines.Add("## Likely affected tests")
    if ($likelyTests.Count -eq 0) { [void]$lines.Add("- none precomputed; infer from changed package only if needed") } else { foreach ($f in $likelyTests) { [void]$lines.Add("- $f") } }
    $lines | Set-Content -Encoding UTF8 $contextPath

    return [ordered]@{ index = $record; index_path = $indexPath; context_path = $contextPath }
}
