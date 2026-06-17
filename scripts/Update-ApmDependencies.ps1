#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#Requires -Version 7.0

<#
.SYNOPSIS
    Regenerates dependencies.apm entries in apm.yml from microsoft/hve-core and
    the local squad source tree.
.DESCRIPTION
    Clones the hve-core repository for a ref, filters files under selected
    .github folders, then enumerates the locally authored squad source tree, and
    rewrites only the dependencies.apm list. hve-core entries are listed first;
    squad entries are appended afterwards.

    Every hve-core entry is pinned to the exact commit SHA that the requested ref
    resolves to (appended as '#<sha>'), so the generated manifest stays
    reproducible for downstream consumers even after hve-core's default branch
    moves on. Squad self-references are pinned to -SquadRef when provided.
.PARAMETER ApmFile
    Path to apm.yml to update.
.PARAMETER RepoSlug
    Repository slug in owner/repo format.
.PARAMETER Ref
    Git ref to read hve-core from (branch, tag, or commit SHA). The ref is
    resolved to a concrete commit SHA, which is what every hve-core dependency is
    pinned to.
.PARAMETER IncludeRoots
    Repository-relative roots under which files are discovered.
.PARAMETER IncludeRegex
    Regex used to keep matching file paths.
.PARAMETER SquadSourceRoot
    Local path to the squad source tree containing .github/{agents,prompts,
    instructions,skills}. Enumerated from the local filesystem (not cloned). If
    the path does not exist, squad enumeration is skipped without error.
.PARAMETER SquadRepoSlug
    Repository slug (owner/repo) that hosts the squad source. Squad virtual
    paths are emitted as <SquadRepoSlug>/<SquadSourceRoot>/.github/...
.PARAMETER SquadRef
    Optional git ref (release tag or commit SHA) to pin squad self-references to,
    appended as '#<ref>'. Use the release tag you are about to cut (for example
    v0.7.0): commit the manifest, then create that tag on the same commit. When
    omitted, squad entries are left unpinned.
.PARAMETER HveCoreRef
    Optional git ref (release tag or commit SHA in THIS repo) to pin hve-core mirror
    entries to, appended as '#<ref>'. When omitted, entries are left unpinned so that
    consumers who install via a release tag (e.g. sohamda/hve-squad#v0.6.1) have APM
    resolve all files at that tag automatically.
.PARAMETER DryRun
    If set, prints generated dependencies without updating apm.yml.
.EXAMPLE
    ./scripts/Update-ApmDependencies.ps1 -ApmFile apm.yml
.EXAMPLE
    ./scripts/Update-ApmDependencies.ps1 -DryRun
.EXAMPLE
    ./scripts/Update-ApmDependencies.ps1 -SquadRef v0.7.0 -HveCoreRef v0.7.0
.EXAMPLE
    ./scripts/Update-ApmDependencies.ps1 -SquadSourceRoot squad-src -SquadRepoSlug myorg/hve-squad
.NOTES
    Intended for use with: apm run sync-deps
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ApmFile = 'apm.yml',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$RepoSlug = 'microsoft/hve-core',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Ref = 'main',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$IncludeRoots = @(
        '.github/agents',
        '.github/prompts',
        '.github/skills',
        '.github/instructions'
    ),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$IncludeRegex = '\.md$',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$HveCoreLocalRoot = 'hve-core',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SquadSourceRoot = 'squad-src',

    [Parameter(Mandatory = $false)]
    [string]$SquadRepoSlug,

    [Parameter(Mandatory = $false)]
    [string]$HveCoreRef,

    [Parameter(Mandatory = $false)]
    [string]$SquadRef,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Auto-detect SquadRepoSlug from the git remote when not explicitly provided.
# Parses 'git remote get-url origin' and converts the URL to owner/repo format.
if ([string]::IsNullOrWhiteSpace($SquadRepoSlug)) {
    $remoteUrl = & git remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($remoteUrl)) {
        $remoteUrl = $remoteUrl.Trim()
        # Handle both HTTPS (https://github.com/owner/repo.git) and SSH (git@github.com:owner/repo.git)
        if ($remoteUrl -match 'github\.com[:/]([^/]+/[^/]+?)(\.git)?$') {
            $SquadRepoSlug = $matches[1]
        }
    }
    if ([string]::IsNullOrWhiteSpace($SquadRepoSlug)) {
        throw "Could not detect SquadRepoSlug from git remote. Pass -SquadRepoSlug owner/repo explicitly."
    }
    Write-Host "Auto-detected SquadRepoSlug: $SquadRepoSlug" -ForegroundColor Cyan
}

#region Functions
function Get-LeadingSpaceCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    $match = [regex]::Match($Line, '^(\s*)')
    return $match.Groups[1].Value.Length
}

function Get-RepoTreePaths {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$GitRef,

        [Parameter(Mandatory = $true)]
        [string[]]$Roots
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("apm-tree-" + [Guid]::NewGuid().ToString('N'))
    $repoUrl = "https://github.com/$Repository.git"

    try {
        # Use init + fetch (rather than 'clone --branch') so that $GitRef may be a
        # branch, a tag, or a bare commit SHA. 'clone --branch' rejects commit
        # SHAs, which the pinned-release flow depends on.
        $null = & git init --quiet $tempRoot 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git init failed for temp clone of '$Repository'."
        }

        Push-Location $tempRoot
        try {
            $null = & git remote add origin $repoUrl 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git remote add failed for '$Repository'."
            }

            $null = & git fetch --depth 1 --filter=blob:none origin $GitRef 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git fetch failed for '$Repository@$GitRef'. The ref must be a branch, tag, or commit SHA."
            }

            $revParse = & git rev-parse FETCH_HEAD 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git could not resolve a commit for '$Repository@$GitRef'."
            }
            $resolvedCommit = @($revParse) |
                Where-Object { $_ -match '^[0-9a-f]{7,40}$' } |
                Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace($resolvedCommit)) {
                throw "git could not resolve a commit for '$Repository@$GitRef'."
            }
            $resolvedCommit = $resolvedCommit.Trim()

            $result = [System.Collections.Generic.List[string]]::new()
            foreach ($root in $Roots) {
                $entries = & git ls-tree -r --name-only FETCH_HEAD -- $root 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "git ls-tree failed for root '$root'."
                }

                foreach ($entry in $entries) {
                    if ([string]::IsNullOrWhiteSpace($entry)) {
                        continue
                    }

                    $result.Add($entry.Trim())
                }
            }

            return [pscustomobject]@{
                ResolvedCommit = $resolvedCommit
                Paths          = @($result)
            }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

function Build-DependencyList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string[]]$Roots,

        [Parameter(Mandatory = $true)]
        [string]$PathFilterRegex,

        [Parameter(Mandatory = $false)]
        [string]$Ref
    )

    # APM accepts only these file package extensions:
    # .agent.md, .prompt.md, .instructions.md, .chatmode.md
    # Skills should be referenced as subdirectory packages (no file extension).
    $agentDeps = @(
        $Paths | Where-Object {
            $_.StartsWith('.github/agents/', [StringComparison]::OrdinalIgnoreCase) -and
            ($_ -match '\.agent\.md$')
        }
    )

    $promptDeps = @(
        $Paths | Where-Object {
            $_.StartsWith('.github/prompts/', [StringComparison]::OrdinalIgnoreCase) -and
            (($_ -match '\.prompt\.md$') -or ($_ -match '\.chatmode\.md$'))
        }
    )

    $instructionDeps = @(
        $Paths | Where-Object {
            $_.StartsWith('.github/instructions/', [StringComparison]::OrdinalIgnoreCase) -and
            ($_ -match '\.instructions\.md$')
        }
    )

    $skillDeps = @(
        $Paths |
            Where-Object {
                $_.StartsWith('.github/skills/', [StringComparison]::OrdinalIgnoreCase) -and
                ([string]::Equals([System.IO.Path]::GetFileName($_), 'SKILL.md', [StringComparison]::OrdinalIgnoreCase))
            } |
                ForEach-Object { (Split-Path -Path $_ -Parent).Replace('\', '/') } |
            Sort-Object -Unique
    )

    $refSuffix = if ([string]::IsNullOrWhiteSpace($Ref)) { '' } else { "#$Ref" }
    $selected = @($agentDeps + $promptDeps + $instructionDeps + $skillDeps)
    return @($selected | Sort-Object -Unique | ForEach-Object { "$Repository/$_$refSuffix" })
}

function Get-SquadSourcePaths {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Roots
    )

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        Write-Verbose "Squad source root '$SourceRoot' not found; skipping squad enumeration."
        return @()
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot).ProviderPath
    $normalizedPrefix = $SourceRoot.Replace('\', '/').TrimEnd('/')

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $Roots) {
        $searchDir = Join-Path $resolvedRoot $root
        if (-not (Test-Path -LiteralPath $searchDir)) {
            continue
        }

        $files = Get-ChildItem -LiteralPath $searchDir -Recurse -File
        foreach ($file in $files) {
            $relative = [System.IO.Path]::GetRelativePath($resolvedRoot, $file.FullName).Replace('\', '/')
            $result.Add("$normalizedPrefix/$relative")
        }
    }

    return @($result)
}

function Build-SquadDependencyList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Paths,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string]$SourcePrefix,

        [Parameter(Mandatory = $false)]
        [string]$Ref
    )

    # Squad paths are repo-relative and retain the squad source prefix, e.g.
    # squad-src/.github/agents/squad/squad-coordinator.agent.md. Filtering mirrors
    # Build-DependencyList but matches the prefixed .github roots.
    $prefix = $SourcePrefix.Replace('\', '/').TrimEnd('/')

    $agentDeps = @(
        $Paths | Where-Object {
            $_.StartsWith("$prefix/.github/agents/", [StringComparison]::OrdinalIgnoreCase) -and
            ($_ -match '\.agent\.md$')
        }
    )

    $promptDeps = @(
        $Paths | Where-Object {
            $_.StartsWith("$prefix/.github/prompts/", [StringComparison]::OrdinalIgnoreCase) -and
            (($_ -match '\.prompt\.md$') -or ($_ -match '\.chatmode\.md$'))
        }
    )

    $instructionDeps = @(
        $Paths | Where-Object {
            $_.StartsWith("$prefix/.github/instructions/", [StringComparison]::OrdinalIgnoreCase) -and
            ($_ -match '\.instructions\.md$')
        }
    )

    $skillDeps = @(
        $Paths |
            Where-Object {
                $_.StartsWith("$prefix/.github/skills/", [StringComparison]::OrdinalIgnoreCase) -and
                ([string]::Equals([System.IO.Path]::GetFileName($_), 'SKILL.md', [StringComparison]::OrdinalIgnoreCase))
            } |
                ForEach-Object { (Split-Path -Path $_ -Parent).Replace('\', '/') } |
            Sort-Object -Unique
    )

    $refSuffix = if ([string]::IsNullOrWhiteSpace($Ref)) { '' } else { "#$Ref" }
    $selected = @($agentDeps + $promptDeps + $instructionDeps + $skillDeps)
    return @($selected | Sort-Object -Unique | ForEach-Object { "$Repository/$_$refSuffix" })
}

function Update-ApmDependencyList {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$Dependencies
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "APM file not found: $Path"
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lines.Add($line)
    }

    $apmIndex = -1
    $apmIndent = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\s*)apm:\s*(\[\])?\s*$') {
            $apmIndex = $i
            $apmIndent = $matches[1].Length
            break
        }
    }

    if ($apmIndex -lt 0) {
        throw "Could not find 'dependencies.apm' key in $Path"
    }

    $nextSibling = $lines.Count
    for ($j = $apmIndex + 1; $j -lt $lines.Count; $j++) {
        $line = $lines[$j]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $indent = Get-LeadingSpaceCount -Line $line
        if (($indent -eq $apmIndent) -and ($line.Trim() -match '^[A-Za-z0-9_-]+:\s*')) {
            $nextSibling = $j
            break
        }
    }

    $removeCount = $nextSibling - ($apmIndex + 1)
    if ($removeCount -gt 0) {
        $lines.RemoveRange($apmIndex + 1, $removeCount)
    }

    $itemIndent = ' ' * ($apmIndent + 2)
    $insertion = [System.Collections.Generic.List[string]]::new()
    foreach ($dep in $Dependencies) {
        $insertion.Add("$itemIndent- $dep")
    }

    if ($insertion.Count -eq 0) {
        $insertion.Add("$itemIndent# No matching files were found")
    }

    $lines.InsertRange($apmIndex + 1, $insertion)
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
}

function Get-LocalRepoTreePaths {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Roots
    )

    if (-not (Test-Path -LiteralPath $LocalRoot)) {
        throw "Local hve-core mirror not found at '$LocalRoot'. Run scripts/Sync-HveCore.ps1 first."
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $LocalRoot).ProviderPath
    $versionFile = Join-Path $resolvedRoot '.version'

    if (-not (Test-Path -LiteralPath $versionFile)) {
        throw "Version file not found at '$versionFile'. The mirror may be incomplete. Run scripts/Sync-HveCore.ps1 first."
    }

    $resolvedCommit = (Get-Content -LiteralPath $versionFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedCommit)) {
        throw "Version file '$versionFile' is empty. Run scripts/Sync-HveCore.ps1 first."
    }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($root in $Roots) {
        $searchDir = Join-Path $resolvedRoot $root
        if (-not (Test-Path -LiteralPath $searchDir)) {
            continue
        }

        $files = Get-ChildItem -LiteralPath $searchDir -Recurse -File
        foreach ($file in $files) {
            $relative = [System.IO.Path]::GetRelativePath($resolvedRoot, $file.FullName).Replace('\', '/')
            $result.Add($relative)
        }
    }

    return [pscustomobject]@{
        ResolvedCommit = $resolvedCommit
        Paths          = @($result)
    }
}
#endregion Functions

#region Main Execution
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Write-Host "Reading hve-core tree from local mirror '$HveCoreLocalRoot'..." -ForegroundColor Cyan
        $tree = Get-LocalRepoTreePaths -LocalRoot $HveCoreLocalRoot -Roots $IncludeRoots
        $paths = $tree.Paths
        $resolvedCommit = $tree.ResolvedCommit
        Write-Host "Local mirror pinned to commit $resolvedCommit." -ForegroundColor Green

        $hveCoreMirrorPrefix = "$SquadRepoSlug/$HveCoreLocalRoot"
        Write-Host "Emitting hve-core refs as '$hveCoreMirrorPrefix/...'..." -ForegroundColor Cyan

        # Resolve the ref to use for hve-core mirror entries in apm.yml.
        # Entries are left unpinned by default so that consumers who install via a
        # release tag (e.g. sohamda/hve-squad#v0.6.1) have APM resolve all files at
        # that tag automatically. Pass -HveCoreRef only when explicit pinning is needed.
        if (-not [string]::IsNullOrWhiteSpace($HveCoreRef)) {
            $hveCorePinRef = $HveCoreRef
            Write-Host "Pinning hve-core mirror entries to provided ref: $hveCorePinRef" -ForegroundColor Green
        }
        else {
            $hveCorePinRef = ''
            Write-Host "hve-core mirror entries left unpinned (pass -HveCoreRef <tag> to pin)." -ForegroundColor Yellow
        }

        $deps = Build-DependencyList -Paths $paths -Repository $hveCoreMirrorPrefix -Roots $IncludeRoots -PathFilterRegex $IncludeRegex -Ref $hveCorePinRef
        if ($null -eq $deps) {
            $deps = @()
        }
        Write-Host "Found $($deps.Count) dependencies." -ForegroundColor Green

        $squadDeps = @()
        if (Test-Path -LiteralPath $SquadSourceRoot) {
            Write-Host "Reading squad source from $SquadSourceRoot..." -ForegroundColor Cyan
            $squadPaths = Get-SquadSourcePaths -SourceRoot $SquadSourceRoot -Roots $IncludeRoots
            $squadDeps = Build-SquadDependencyList -Paths $squadPaths -Repository $SquadRepoSlug -SourcePrefix $SquadSourceRoot -Ref $SquadRef
            if ($null -eq $squadDeps) {
                $squadDeps = @()
            }
            if ([string]::IsNullOrWhiteSpace($SquadRef)) {
                Write-Host "Squad dependencies left unpinned (pass -SquadRef <tag> to pin)." -ForegroundColor Yellow
            }
            else {
                Write-Host "Pinned squad dependencies to $SquadRef." -ForegroundColor Green
            }
            Write-Host "Found $($squadDeps.Count) squad dependencies." -ForegroundColor Green
        }
        else {
            Write-Host "Squad source root '$SquadSourceRoot' not found; skipping squad enumeration." -ForegroundColor Yellow
        }

        # hve-core entries remain first; squad entries are appended afterwards.
        $allDeps = @($deps + $squadDeps)

        if ($DryRun) {
            Write-Host "hve-core dependencies ($($deps.Count)):" -ForegroundColor Cyan
            $deps | ForEach-Object { Write-Host "- $_" }
            Write-Host "squad dependencies ($($squadDeps.Count)):" -ForegroundColor Cyan
            $squadDeps | ForEach-Object { Write-Host "- $_" }
            exit 0
        }

        Update-ApmDependencyList -Path $ApmFile -Dependencies $allDeps
        Write-Host "Updated dependencies.apm in $ApmFile" -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Update-ApmDependencies failed: $($_.Exception.Message)"
        exit 1
    }
}
#endregion Main Execution
