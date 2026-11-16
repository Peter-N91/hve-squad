#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Verifies and renews Registered External Cast rows in roster-catalog.md using split-mode checks.
.DESCRIPTION
    Enforces the 60-day renewal window ahead of the 90-day Verified On backstop in
    squad-src/.github/skills/squad/references/roster-catalog.md:
      1. Auto-renews Verified On only when the upstream repository remains active, non-redirected,
         and under the same licence, the pinned path still resolves, frontmatter/hook/MCP checks
         pass, and the resource's file or directory blobs at upstream HEAD are byte-identical to
         its verified commit SHA.
      2. Refuses silent renewal whenever upstream content, paths, frontmatter, hooks, MCP manifests,
         archive status, repository ownership, or licences drift, emitting a structured Markdown
         adaptation brief and workflow outputs so CI can raise a reviewed adaptation issue.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$CatalogPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'squad-src/.github/skills/squad/references/roster-catalog.md'),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ApmPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'apm.yml'),

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$AsOf = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$RenewalWindowDays = 60,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$MaxAgeDays = 90,

    [Parameter(Mandatory = $false)]
    [string]$MarkdownPath,

    [Parameter(Mandatory = $false)]
    [string]$FixturePath,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$GitHubOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertFrom-SafeJson {
    param([Parameter(Mandatory)][string]$Json)
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        return $Json | ConvertFrom-Json -DateKind String
    }
    return $Json | ConvertFrom-Json
}

function Get-StringSha256Short {
    param([Parameter(Mandatory)][string]$InputText)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputText)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ([System.Convert]::ToHexString($hash)).ToLowerInvariant().Substring(0, 12)
}

function Get-BundledApmPinMap {
    param([Parameter(Mandatory)][string]$ManifestPath)
    $map = @{}
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return $map
    }
    foreach ($line in Get-Content -LiteralPath $ManifestPath) {
        $match = [regex]::Match($line, '^\s*-\s+(?<Entry>[^#\s]+#(?<Sha>[0-9a-f]{40}))\s*$')
        if ($match.Success) {
            $map[$match.Groups['Entry'].Value] = $match.Groups['Sha'].Value
        }
    }
    return $map
}

function Get-ExternalCastCatalogEntry {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][datetime]$AsOfDate
    )

    $inSection = $false
    $entries = [System.Collections.Generic.List[object]]::new()

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^####\s+Registered External Cast\s*$') {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match '^#{1,6}\s+') {
            break
        }
        if (-not $inSection -or -not $line.StartsWith('|')) {
            continue
        }
        if ($line -match '^\|\s*Role\s*\|' -or $line -match '^\|\s*-+\s*\|') {
            continue
        }

        $cells = @($line.Split('|'))
        if ($cells.Count -ne 12) {
            throw "Malformed Registered External Cast row at line $($i + 1): expected 10 columns, found $($cells.Count - 2)."
        }

        $role = $cells[1].Trim()
        $tier = $cells[2].Trim()
        $resource = $cells[3].Trim().Trim('`')
        $kind = $cells[4].Trim()
        $originRaw = $cells[5].Trim()
        $installRaw = $cells[6].Trim()
        $license = $cells[7].Trim()
        $prereq = $cells[8].Trim()
        $dispatchVerified = $cells[9].Trim()
        $verifiedOn = $cells[10].Trim()

        $originMatch = [regex]::Match($originRaw, '^`(?<Repo>[^`]+)` \(`(?<Class>vendor-official|github-marketplace|community)`\), `(?<Path>[^`]+)`$')
        if (-not $originMatch.Success) {
            throw "Invalid Origin cell for '$resource' at line $($i + 1): $originRaw"
        }

        $pinMatch = [regex]::Match($installRaw, '#(?<Sha>[0-9a-f]{40})\b')
        if (-not $pinMatch.Success) {
            $pinMatch = [regex]::Match($prereq, 'verified at `?(?<Sha>[0-9a-f]{40})`?')
        }
        if (-not $pinMatch.Success) {
            throw "External Cast row '$resource' ($role) at line $($i + 1) has no 40-char verified commit SHA in Install or Entry or Prerequisites."
        }

        $verifiedDate = [datetime]::ParseExact($verifiedOn, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $ageDays = [int][Math]::Floor(($AsOfDate - $verifiedDate).TotalDays)

        $entries.Add([pscustomobject]@{
                LineIndex = $i
                Role = $role
                Tier = $tier
                Resource = $resource
                ResourceKind = $kind
                OriginRepo = $originMatch.Groups['Repo'].Value
                OriginClass = $originMatch.Groups['Class'].Value
                OriginPath = $originMatch.Groups['Path'].Value
                InstallOrEntry = $installRaw
                License = $license
                Prerequisites = $prereq
                DispatchabilityVerified = $dispatchVerified
                VerifiedOn = $verifiedOn
                PinnedSha = $pinMatch.Groups['Sha'].Value
                AgeDays = $ageDays
            })
    }

    return $entries.ToArray()
}

function Invoke-GitHubApiJson {
    param([Parameter(Mandatory)][string]$Endpoint)

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $out = & gh api $Endpoint 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "gh api '$Endpoint' failed: $($out -join ' ')"
        }
        return ConvertFrom-SafeJson -Json ($out -join "`n")
    }

    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'hve-squad-external-cast-sync'
    }
    $token = if ($env:GH_TOKEN) { $env:GH_TOKEN } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { '' }
    if ($token) {
        $headers['Authorization'] = "Bearer $token"
    }
    $uri = "https://api.github.com/$($Endpoint.TrimStart('/'))"
    $response = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get
    return ConvertFrom-SafeJson -Json $response.Content
}

function Get-BlobTextFromApi {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Ref,
        [Parameter(Mandatory)][hashtable]$Cache
    )

    $cacheKey = "${Repo}@${Ref}:${Path}"
    if ($Cache.ContainsKey($cacheKey)) {
        return $Cache[$cacheKey]
    }
    $encodedPath = ($Path -split '/' | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
    $item = Invoke-GitHubApiJson -Endpoint "repos/$Repo/contents/${encodedPath}?ref=$Ref"
    $cleanBase64 = ($item.content -replace '\s+', '')
    $text = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($cleanBase64))
    $Cache[$cacheKey] = $text
    return $text
}

function Get-TreeBlobMapFromApi {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Ref
    )

    $treeResp = Invoke-GitHubApiJson -Endpoint "repos/$Repo/git/trees/${Ref}?recursive=1"
    if ($treeResp.PSObject.Properties['truncated'] -and [bool]$treeResp.truncated) {
        throw "Git tree response for '$Repo@$Ref' was truncated by the GitHub API."
    }
    $blobMap = @{}
    foreach ($node in @($treeResp.tree)) {
        if ($node.type -eq 'blob') {
            $blobMap[[string]$node.path] = [string]$node.sha
        }
    }
    return $blobMap
}

function Get-UpstreamRepositoryState {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$PinnedShaList,
        [hashtable]$FixtureMap
    )

    if ($null -ne $FixtureMap) {
        if (-not $FixtureMap.ContainsKey($Repo)) {
            return [pscustomobject]@{
                Reachable = $false
                Error = "Repository '$Repo' missing from fixture."
                FullName = $Repo
                Archived = $false
                SpdxId = ''
                HeadSha = ''
                Trees = @{}
                Contents = @{}
            }
        }
        $fx = $FixtureMap[$Repo]
        if ($fx.PSObject.Properties['reachable'] -and -not [bool]$fx.reachable) {
            return [pscustomobject]@{
                Reachable = $false
                Error = if ($fx.PSObject.Properties['error']) { [string]$fx.error } else { 'Unreachable in fixture.' }
                FullName = $Repo
                Archived = $false
                SpdxId = ''
                HeadSha = ''
                Trees = @{}
                Contents = @{}
            }
        }
        $trees = @{}
        if ($fx.PSObject.Properties['trees'] -and $null -ne $fx.trees) {
            foreach ($prop in $fx.trees.PSObject.Properties) {
                $inner = @{}
                foreach ($bProp in $prop.Value.PSObject.Properties) {
                    $inner[$bProp.Name] = [string]$bProp.Value
                }
                $trees[$prop.Name] = $inner
            }
        }
        $contents = @{}
        if ($fx.PSObject.Properties['contents'] -and $null -ne $fx.contents) {
            foreach ($cProp in $fx.contents.PSObject.Properties) {
                $contents["${Repo}@$($cProp.Name)"] = [string]$cProp.Value
            }
        }
        return [pscustomobject]@{
            Reachable = $true
            Error = ''
            FullName = [string]$fx.fullName
            Archived = [bool]$fx.archived
            SpdxId = [string]$fx.spdxId
            HeadSha = [string]$fx.headSha
            Trees = $trees
            Contents = $contents
        }
    }

    try {
        $meta = Invoke-GitHubApiJson -Endpoint "repos/$Repo"
        $defaultBranch = [string]$meta.default_branch
        $headCommit = Invoke-GitHubApiJson -Endpoint "repos/$Repo/commits/$defaultBranch"
        $headSha = [string]$headCommit.sha
        $spdx = if ($null -ne $meta.license -and $meta.license.PSObject.Properties['spdx_id']) {
            [string]$meta.license.spdx_id
        } else {
            ''
        }

        $trees = @{}
        $trees[$headSha] = Get-TreeBlobMapFromApi -Repo $Repo -Ref $headSha
        foreach ($sha in @($PinnedShaList | Select-Object -Unique)) {
            if (-not $trees.ContainsKey($sha)) {
                try {
                    $trees[$sha] = Get-TreeBlobMapFromApi -Repo $Repo -Ref $sha
                } catch {
                    $trees[$sha] = $null
                }
            }
        }

        return [pscustomobject]@{
            Reachable = $true
            Error = ''
            FullName = [string]$meta.full_name
            Archived = [bool]$meta.archived
            SpdxId = $spdx
            HeadSha = $headSha
            Trees = $trees
            Contents = @{}
        }
    } catch {
        return [pscustomobject]@{
            Reachable = $false
            Error = $_.Exception.Message
            FullName = $Repo
            Archived = $false
            SpdxId = ''
            HeadSha = ''
            Trees = @{}
            Contents = @{}
        }
    }
}

function Get-ScopedBlobSelection {
    param(
        [Parameter(Mandatory)][hashtable]$BlobMap,
        [Parameter(Mandatory)][pscustomobject]$Row
    )

    $selected = @{}
    if ($Row.ResourceKind -eq 'skill' -and $Row.OriginPath -match '/SKILL\.md$') {
        $skillDir = $Row.OriginPath.Substring(0, $Row.OriginPath.Length - '/SKILL.md'.Length)
        $prefix = "$skillDir/"
        foreach ($key in $BlobMap.Keys) {
            if ($key.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                $selected[$key] = $BlobMap[$key]
            }
        }
        if ($Row.InstallOrEntry -match 'copilot plugin install') {
            foreach ($key in $BlobMap.Keys) {
                if ($key.StartsWith('reference/', [System.StringComparison]::Ordinal) -or
                    ($key.StartsWith('docs/', [System.StringComparison]::Ordinal) -and $key.EndsWith('.md', [System.StringComparison]::Ordinal))) {
                    $selected[$key] = $BlobMap[$key]
                }
            }
        }
    } else {
        if ($BlobMap.ContainsKey($Row.OriginPath)) {
            $selected[$Row.OriginPath] = $BlobMap[$Row.OriginPath]
        }
    }
    return $selected
}

function Get-RootLicenseBlobSha {
    param([Parameter(Mandatory)][hashtable]$BlobMap)
    foreach ($candidate in @('LICENSE', 'LICENSE.md', 'LICENSE.txt')) {
        if ($BlobMap.ContainsKey($candidate)) {
            return "${candidate}:$($BlobMap[$candidate])"
        }
    }
    return ''
}

function Get-EntryContentText {
    param(
        [Parameter(Mandatory)][pscustomobject]$RepoState,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Ref,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][bool]$UseFixture
    )

    $key = "${Repo}@${Ref}:${Path}"
    if ($RepoState.Contents.ContainsKey($key)) {
        return $RepoState.Contents[$key]
    }
    if ($UseFixture) {
        return ''
    }
    return Get-BlobTextFromApi -Repo $Repo -Path $Path -Ref $Ref -Cache $RepoState.Contents
}

function Test-ExternalCastRow {
    param(
        [Parameter(Mandatory)][pscustomobject]$Row,
        [Parameter(Mandatory)][pscustomobject]$RepoState,
        [Parameter(Mandatory)][hashtable]$BundledPinMap,
        [Parameter(Mandatory)][int]$RenewalDays,
        [Parameter(Mandatory)][bool]$ForceCheck,
        [Parameter(Mandatory)][bool]$UseFixture
    )

    $hazards = [System.Collections.Generic.List[string]]::new()
    $changedPaths = [System.Collections.Generic.List[string]]::new()

    if ($Row.Tier -eq 'bundled') {
        $manifestMatch = [regex]::Match($Row.InstallOrEntry, '`(?<Entry>[^`]+#[0-9a-f]{40})`\s+in\s+apm\.yml')
        if (-not $manifestMatch.Success -or -not $BundledPinMap.ContainsKey($manifestMatch.Groups['Entry'].Value)) {
            $hazards.Add('bundled_manifest_mismatch')
        }
    }

    if (-not $RepoState.Reachable) {
        $hazards.Add("repo_unreachable ($($RepoState.Error))")
        return [pscustomobject]@{
            Row = $Row
            Status = 'NeedsReview'
            HeadSha = ''
            Hazards = $hazards.ToArray()
            ChangedPaths = @()
        }
    }

    if ($RepoState.Archived) {
        $hazards.Add('repo_archived')
    }
    if ($RepoState.FullName -cne $Row.OriginRepo) {
        $hazards.Add("repo_redirected ($($Row.OriginRepo) -> $($RepoState.FullName))")
    }

    $headTree = $RepoState.Trees[$RepoState.HeadSha]
    $pinTree = if ($RepoState.Trees.ContainsKey($Row.PinnedSha)) { $RepoState.Trees[$Row.PinnedSha] } else { $null }

    if ($null -eq $pinTree) {
        $hazards.Add("pinned_commit_missing ($($Row.PinnedSha))")
    } else {
        $pinLicense = Get-RootLicenseBlobSha -BlobMap $pinTree
        $headLicense = Get-RootLicenseBlobSha -BlobMap $headTree
        if ($pinLicense -ne $headLicense) {
            $hazards.Add("license_blob_changed ($pinLicense -> $headLicense)")
        }
    }

    if ($RepoState.SpdxId -and $RepoState.SpdxId -ne 'NOASSERTION' -and $RepoState.SpdxId -ne $Row.License) {
        $hazards.Add("license_spdx_mismatch (expected $($Row.License), found $($RepoState.SpdxId))")
    } elseif (-not $RepoState.SpdxId) {
        $headLic = Get-RootLicenseBlobSha -BlobMap $headTree
        if (-not $headLic) {
            $hazards.Add('license_missing')
        }
    }

    if ($null -ne $pinTree -and -not $pinTree.ContainsKey($Row.OriginPath)) {
        $hazards.Add("pinned_path_missing ($($Row.OriginPath))")
    }
    if (-not $headTree.ContainsKey($Row.OriginPath)) {
        $hazards.Add("head_path_missing ($($Row.OriginPath))")
    }

    $dueForRenewal = (($Row.Tier -eq 'opt-in' -and ($Row.AgeDays -ge $RenewalDays -or $ForceCheck)) -or ($Row.Tier -eq 'bundled' -and $ForceCheck))

    if (-not $dueForRenewal -and $hazards.Count -eq 0) {
        return [pscustomobject]@{
            Row = $Row
            Status = 'Fresh'
            HeadSha = $RepoState.HeadSha
            Hazards = @()
            ChangedPaths = @()
        }
    }

    if ($null -ne $pinTree -and $headTree.ContainsKey($Row.OriginPath)) {
        $pinScoped = Get-ScopedBlobSelection -BlobMap $pinTree -Row $Row
        $headScoped = Get-ScopedBlobSelection -BlobMap $headTree -Row $Row
        $allKeys = @(@($pinScoped.Keys) + @($headScoped.Keys) | Sort-Object -Unique)
        foreach ($pathKey in $allKeys) {
            $oldBlob = if ($pinScoped.ContainsKey($pathKey)) { $pinScoped[$pathKey] } else { '' }
            $newBlob = if ($headScoped.ContainsKey($pathKey)) { $headScoped[$pathKey] } else { '' }
            if ($oldBlob -ne $newBlob) {
                $changedPaths.Add($pathKey)
            }
        }
        if ($changedPaths.Count -gt 0) {
            $hazards.Add("content_changed ($($changedPaths.Count) file(s))")
        }

        if ($Row.ResourceKind -eq 'skill' -and $Row.OriginPath -match '/SKILL\.md$') {
            $skillDir = $Row.OriginPath.Substring(0, $Row.OriginPath.Length - '/SKILL.md'.Length)
            $skillPrefix = "$skillDir/"
            foreach ($pathKey in $headScoped.Keys) {
                if (-not $pathKey.StartsWith($skillPrefix, [System.StringComparison]::Ordinal)) {
                    continue
                }
                $rel = $pathKey.Substring($skillPrefix.Length)
                if ($rel -match '(^|/)(copilot-hooks\.json|hooks\.json|claude-hooks\.json|\.mcp\.json|mcp\.json)$') {
                    $hazards.Add("skill_hook_or_mcp_file ($pathKey)")
                }
                if ($rel -eq 'apm.yml') {
                    $apmContent = Get-EntryContentText -RepoState $RepoState -Repo $Row.OriginRepo -Ref $RepoState.HeadSha -Path $pathKey -UseFixture $UseFixture
                    if ($apmContent -match '(?m)^\s*mcp\s*:' -and $Row.Prerequisites -notmatch '\.github/mcp\.json') {
                        $hazards.Add("undisclosed_skill_apm_mcp ($pathKey)")
                    }
                }
            }
        }

        $entryText = Get-EntryContentText -RepoState $RepoState -Repo $Row.OriginRepo -Ref $RepoState.HeadSha -Path $Row.OriginPath -UseFixture $UseFixture
        if ($entryText) {
            $fmMatch = [regex]::Match($entryText, '\A---\r?\n(?<Fm>[\s\S]*?)\r?\n---')
            if (-not $fmMatch.Success) {
                $hazards.Add('missing_frontmatter')
            } else {
                $fm = $fmMatch.Groups['Fm'].Value
                if ($fm -match '(?m)^\s*disable-model-invocation\s*:\s*true\b') {
                    $hazards.Add('disable_model_invocation_true')
                }
            }
        }
    }

    if ($hazards.Count -gt 0) {
        return [pscustomobject]@{
            Row = $Row
            Status = 'NeedsReview'
            HeadSha = $RepoState.HeadSha
            Hazards = $hazards.ToArray()
            ChangedPaths = $changedPaths.ToArray()
        }
    }

    return [pscustomobject]@{
        Row = $Row
        Status = 'AutoRenew'
        HeadSha = $RepoState.HeadSha
        Hazards = @()
        ChangedPaths = @()
    }
}

function ConvertTo-UpdatedVerifiedOnLine {
    param(
        [Parameter(Mandatory)][string]$Line,
        [Parameter(Mandatory)][string]$NewDate
    )
    return ($Line -replace '(?<=\|\s*)\d{4}-\d{2}-\d{2}(?=\s*\|\s*$)', $NewDate)
}

function Format-ExternalCastDeltaMarkdown {
    param(
        [Parameter(Mandatory)][string]$AsOfDate,
        [Parameter(Mandatory)][int]$RenewalDays,
        [Parameter(Mandatory)][int]$MaxDays,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AutoRenewed,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$NeedsReview,
        [Parameter(Mandatory)][int]$TotalCount,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ReviewDigest
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('### External Cast Re-Verification Summary')
    $lines.Add('')
    $lines.Add("| Field | Value |")
    $lines.Add("| --- | --- |")
    $lines.Add("| As-of date | ``$AsOfDate`` |")
    $lines.Add("| Total registered rows | **$TotalCount** |")
    $lines.Add("| Renewal window / backstop | ``${RenewalDays}d`` / ``${MaxDays}d`` |")
    $lines.Add("| Auto-renewed (zero-diff) | **$($AutoRenewed.Count)** |")
    $lines.Add("| Escalated for gate review | **$($NeedsReview.Count)** |")
    if ($ReviewDigest) {
        $lines.Add("| Review digest | ``$ReviewDigest`` |")
    }
    $lines.Add('')

    if ($AutoRenewed.Count -gt 0) {
        $lines.Add('#### Zero-diff rows renewed')
        $lines.Add('')
        $lines.Add('| Role | Resource | Origin | Pinned SHA | Previous Verified On | New Verified On |')
        $lines.Add('| --- | --- | --- | --- | --- | --- |')
        foreach ($item in $AutoRenewed) {
            $r = $item.Row
            $lines.Add("| ``$($r.Role)`` | ``$($r.Resource)`` | ``$($r.OriginRepo)`` | ``$($r.PinnedSha.Substring(0, 7))`` | ``$($r.VerifiedOn)`` | ``$AsOfDate`` |")
        }
        $lines.Add('')
    }

    if ($NeedsReview.Count -gt 0) {
        $lines.Add('#### Rows requiring human or Watch Mode Verification Gate review')
        $lines.Add('')
        $lines.Add('| Role | Tier | Resource | Origin | Pinned SHA | Upstream HEAD | Verified On | Age (d) | Trigger / Hazard |')
        $lines.Add('| --- | --- | --- | --- | --- | --- | --- | ---: | --- |')
        foreach ($item in $NeedsReview) {
            $r = $item.Row
            $headShort = if ($item.HeadSha) { $item.HeadSha.Substring(0, 7) } else { 'n/a' }
            $reason = ($item.Hazards -join '; ')
            $lines.Add("| ``$($r.Role)`` | ``$($r.Tier)`` | ``$($r.Resource)`` | ``$($r.OriginRepo)`` (``$($r.OriginPath)``) | ``$($r.PinnedSha.Substring(0, 7))`` | ``$headShort`` | ``$($r.VerifiedOn)`` | $($r.AgeDays) | $reason |")
        }
        $lines.Add('')
        foreach ($item in @($NeedsReview | Where-Object { $_.ChangedPaths.Count -gt 0 })) {
            $r = $item.Row
            $lines.Add("- **``$($r.Resource)``** (``$($r.OriginRepo)``, ``$($r.PinnedSha.Substring(0, 7))..$($item.HeadSha.Substring(0, 7))``): ``$($item.ChangedPaths -join '``, ``')``")
        }
        if (@($NeedsReview | Where-Object { $_.ChangedPaths.Count -gt 0 }).Count -gt 0) {
            $lines.Add('')
        }
    }

    return ($lines -join "`n")
}

$resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath).Path
$rawCatalog = [System.IO.File]::ReadAllText($resolvedCatalogPath)
$lineEnding = if ($rawCatalog.Contains("`r`n")) { "`r`n" } else { "`n" }
$catalogLines = [System.Collections.Generic.List[string]]::new([string[]]($rawCatalog -split '\r?\n'))

$asOfDateTime = [datetime]::ParseExact($AsOf, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
$bundledMap = Get-BundledApmPinMap -ManifestPath $ApmPath
$rows = @(Get-ExternalCastCatalogEntry -Lines $catalogLines.ToArray() -AsOfDate $asOfDateTime)

$fixtureMap = $null
$useFixture = $false
if ($FixturePath) {
    $useFixture = $true
    $fixtureObj = ConvertFrom-SafeJson -Json ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $FixturePath).Path))
    $fixtureMap = @{}
    foreach ($prop in $fixtureObj.PSObject.Properties) {
        $fixtureMap[$prop.Name] = $prop.Value
    }
}

$repoStates = @{}
foreach ($group in @($rows | Group-Object OriginRepo)) {
    $repoName = [string]$group.Name
    $pins = @($group.Group | ForEach-Object { $_.PinnedSha } | Select-Object -Unique)
    $repoStates[$repoName] = Get-UpstreamRepositoryState -Repo $repoName -PinnedShaList $pins -FixtureMap $fixtureMap
}

$evaluations = [System.Collections.Generic.List[object]]::new()
foreach ($row in $rows) {
    $eval = Test-ExternalCastRow `
        -Row $row `
        -RepoState $repoStates[$row.OriginRepo] `
        -BundledPinMap $bundledMap `
        -RenewalDays $RenewalWindowDays `
        -ForceCheck ([bool]$Force) `
        -UseFixture $useFixture
    $evaluations.Add($eval)
}

$autoRenewed = @($evaluations | Where-Object { $_.Status -eq 'AutoRenew' })
$needsReview = @($evaluations | Where-Object { $_.Status -eq 'NeedsReview' })

$updated = $false
foreach ($item in $autoRenewed) {
    $idx = $item.Row.LineIndex
    $newLine = ConvertTo-UpdatedVerifiedOnLine -Line $catalogLines[$idx] -NewDate $AsOf
    if ($newLine -cne $catalogLines[$idx]) {
        $catalogLines[$idx] = $newLine
        $updated = $true
    }
}

if ($updated) {
    for ($i = 0; $i -lt [Math]::Min(15, $catalogLines.Count); $i++) {
        if ($catalogLines[$i] -match '^\s*last_updated:\s*"\d{4}-\d{2}-\d{2}"\s*$') {
            $catalogLines[$i] = "  last_updated: `"$AsOf`""
            break
        }
    }
}

if ($updated -and -not $DryRun) {
    if ($PSCmdlet.ShouldProcess($resolvedCatalogPath, "Renew $($autoRenewed.Count) zero-diff External Cast row(s) to $AsOf")) {
        $newText = ($catalogLines -join $lineEnding)
        [System.IO.File]::WriteAllText($resolvedCatalogPath, $newText, [System.Text.UTF8Encoding]::new($false))
    }
}

$overdueAfter = @(
    foreach ($eval in $evaluations) {
        if ($eval.Row.Tier -ne 'opt-in') { continue }
        $effectiveAge = if ($eval.Status -eq 'AutoRenew' -and $eval.Row.VerifiedOn -ne $AsOf) { 0 } else { $eval.Row.AgeDays }
        if ($effectiveAge -gt $MaxAgeDays) { $eval }
    }
)

$reviewDigest = ''
if ($needsReview.Count -gt 0) {
    $fingerprintLines = @(
        foreach ($item in @($needsReview | Sort-Object { "$($_.Row.Role):$($_.Row.Resource)" })) {
            "$($item.Row.Role)|$($item.Row.Resource)|$($item.Row.PinnedSha)|$($item.HeadSha)|$($item.Hazards -join ',')"
        }
    )
    $reviewDigest = Get-StringSha256Short -InputText ($fingerprintLines -join "`n")
}

$markdown = Format-ExternalCastDeltaMarkdown `
    -AsOfDate $AsOf `
    -RenewalDays $RenewalWindowDays `
    -MaxDays $MaxAgeDays `
    -AutoRenewed $autoRenewed `
    -NeedsReview $needsReview `
    -TotalCount $rows.Count `
    -ReviewDigest $reviewDigest

if ($MarkdownPath) {
    [System.IO.File]::WriteAllText($MarkdownPath, "$markdown`n", [System.Text.UTF8Encoding]::new($false))
}

if ($GitHubOutput -and $env:GITHUB_OUTPUT) {
    @(
        "as_of=$AsOf"
        "total_rows=$($rows.Count)"
        "auto_renewed_count=$($autoRenewed.Count)"
        "needs_review_count=$($needsReview.Count)"
        "overdue_count=$($overdueAfter.Count)"
        "updated=$($updated.ToString().ToLowerInvariant())"
        "needs_review=$(($needsReview.Count -gt 0).ToString().ToLowerInvariant())"
        "review_digest=$reviewDigest"
    ) | Add-Content -LiteralPath $env:GITHUB_OUTPUT
}

[pscustomobject]@{
    AsOf = $AsOf
    TotalRows = $rows.Count
    Updated = $updated
    AutoRenewedCount = $autoRenewed.Count
    NeedsReviewCount = $needsReview.Count
    OverdueCount = $overdueAfter.Count
    NeedsReview = ($needsReview.Count -gt 0)
    ReviewDigest = $reviewDigest
    AutoRenewedResources = @($autoRenewed | ForEach-Object { $_.Row.Resource })
    NeedsReviewResources = @($needsReview | ForEach-Object { $_.Row.Resource })
}
