# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:RuntimeOverlayPaths = @(
    '.github/agents'
    '.github/prompts'
    '.github/instructions'
    '.agents'
)

function Copy-SquadWatchDirectoryContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    foreach ($directory in Get-ChildItem -LiteralPath $Source -Directory -Recurse -Force) {
        $relative = [System.IO.Path]::GetRelativePath($Source, $directory.FullName)
        New-Item -ItemType Directory -Path (Join-Path $Destination $relative) -Force | Out-Null
    }

    foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse -Force) {
        $relative = [System.IO.Path]::GetRelativePath($Source, $file.FullName)
        $target = Join-Path $Destination $relative
        $parent = Split-Path -Parent $target
        if ($parent) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
}

function Enable-SquadWatchRuntimeOverlay {
    <#
    .SYNOPSIS
        Merges the installed Squad runtime into a workspace while backing up any
        pre-existing runtime paths for exact restoration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageRoot,

        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$BackupRoot
    )

    $package = (Resolve-Path -LiteralPath $PackageRoot).Path
    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $backup = [System.IO.Path]::GetFullPath($BackupRoot)

    if (Test-Path -LiteralPath $backup) {
        Remove-Item -LiteralPath $backup -Recurse -Force
    }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($relativePath in $script:RuntimeOverlayPaths) {
        $source = Join-Path $package $relativePath
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            continue
        }

        $destination = Join-Path $workspace $relativePath
        if ((Test-Path -LiteralPath $destination) -and
            -not (Test-Path -LiteralPath $destination -PathType Container)) {
            throw "Squad Watch runtime destination '$relativePath' exists but is not a directory."
        }

        $existed = Test-Path -LiteralPath $destination -PathType Container
        $originalFiles = @()
        $originalDirectories = @()
        if ($existed) {
            $original = Join-Path $backup (Join-Path 'original' $relativePath)
            Copy-SquadWatchDirectoryContent -Source $destination -Destination $original
            $originalFiles = @(
                Get-ChildItem -LiteralPath $original -File -Recurse -Force |
                    Sort-Object FullName |
                    ForEach-Object {
                        [pscustomobject]@{
                            Path   = ([System.IO.Path]::GetRelativePath($original, $_.FullName) -replace '\\', '/')
                            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                        }
                    }
            )
            $originalDirectories = @(
                Get-ChildItem -LiteralPath $original -Directory -Recurse -Force |
                    ForEach-Object {
                        [System.IO.Path]::GetRelativePath($original, $_.FullName) -replace '\\', '/'
                    } |
                    Sort-Object
            )
        }

        $entries.Add([pscustomobject]@{
                Path                = ($relativePath -replace '\\', '/')
                Existed             = $existed
                OriginalFiles       = $originalFiles
                OriginalDirectories = $originalDirectories
            })
    }

    $manifestPath = Join-Path $backup 'manifest.json'
    [ordered]@{
        version = 1
        entries = @($entries)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

    foreach ($entry in $entries) {
        $source = Join-Path $package $entry.Path
        $destination = Join-Path $workspace $entry.Path
        Copy-SquadWatchDirectoryContent -Source $source -Destination $destination
    }

    [pscustomobject]@{
        BackupRoot  = $backup
        Entries     = @($entries)
        ManifestHash = $manifestHash
    }
}

function Restore-SquadWatchRuntimeOverlay {
    <#
    .SYNOPSIS
        Removes only the runtime paths owned by the overlay and restores their exact
        pre-run contents.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [string]$ExpectedManifestHash
    )

    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $backup = [System.IO.Path]::GetFullPath($BackupRoot)
    $manifestPath = Join-Path $backup 'manifest.json'

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return
    }

    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedManifestHash -and $manifestHash -ne $ExpectedManifestHash.ToLowerInvariant()) {
        throw 'Squad Watch runtime backup manifest changed after provisioning; refusing cleanup.'
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $validationFailures = [System.Collections.Generic.List[string]]::new()
    $manifestPaths = @($manifest.entries | ForEach-Object { ([string]$_.Path) -replace '\\', '/' })
    foreach ($relativePath in $manifestPaths) {
        if ($relativePath -notin $script:RuntimeOverlayPaths) {
            $validationFailures.Add("unexpected runtime path '$relativePath'")
        }
    }
    foreach ($duplicate in @($manifestPaths | Group-Object | Where-Object Count -gt 1)) {
        $validationFailures.Add("duplicate runtime path '$($duplicate.Name)'")
    }

    foreach ($entry in @($manifest.entries)) {
        $relativePath = ([string]$entry.Path) -replace '\\', '/'
        if ($relativePath -notin $script:RuntimeOverlayPaths) {
            continue
        }

        $original = Join-Path $backup (Join-Path 'original' $relativePath)
        if ([bool]$entry.Existed) {
            if (-not (Test-Path -LiteralPath $original -PathType Container)) {
                $validationFailures.Add("missing backup for pre-existing runtime path '$relativePath'")
                continue
            }

            $expectedFiles = @{}
            foreach ($file in @($entry.OriginalFiles)) {
                $path = ([string]$file.Path) -replace '\\', '/'
                $expectedFiles[$path] = ([string]$file.Sha256).ToLowerInvariant()
            }
            $actualFiles = @(
                Get-ChildItem -LiteralPath $original -File -Recurse -Force |
                    ForEach-Object {
                        [pscustomobject]@{
                            Path   = ([System.IO.Path]::GetRelativePath($original, $_.FullName) -replace '\\', '/')
                            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                        }
                    }
            )
            if ($actualFiles.Count -ne $expectedFiles.Count) {
                $validationFailures.Add("backup file inventory changed for '$relativePath'")
            }
            foreach ($file in $actualFiles) {
                if (-not $expectedFiles.ContainsKey($file.Path) -or $expectedFiles[$file.Path] -ne $file.Sha256) {
                    $validationFailures.Add("backup file changed for '$relativePath/$($file.Path)'")
                }
            }

            $expectedDirectories = @($entry.OriginalDirectories | ForEach-Object { ([string]$_) -replace '\\', '/' } | Sort-Object)
            $actualDirectories = @(
                Get-ChildItem -LiteralPath $original -Directory -Recurse -Force |
                    ForEach-Object {
                        [System.IO.Path]::GetRelativePath($original, $_.FullName) -replace '\\', '/'
                    } |
                    Sort-Object
            )
            if (($expectedDirectories -join "`n") -ne ($actualDirectories -join "`n")) {
                $validationFailures.Add("backup directory inventory changed for '$relativePath'")
            }
        }
        elseif (Test-Path -LiteralPath $original) {
            $validationFailures.Add("unexpected backup content for new runtime path '$relativePath'")
        }
    }

    if ($validationFailures.Count -gt 0) {
        throw "Squad Watch runtime backup validation failed:`n- $($validationFailures -join "`n- ")"
    }

    foreach ($entry in @($manifest.entries)) {
        $relativePath = ([string]$entry.Path) -replace '\\', '/'
        $destination = Join-Path $workspace $relativePath
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }

        if ([bool]$entry.Existed) {
            $original = Join-Path $backup (Join-Path 'original' $relativePath)
            Copy-SquadWatchDirectoryContent -Source $original -Destination $destination
        }
    }

    Remove-Item -LiteralPath $backup -Recurse -Force
}

function Get-SquadWatchStageRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Summary
    )

    $sections = @([regex]::Matches(
            $Summary,
            '(?ms)^## Stages\s*\r?\n(?<body>.*?)(?=^## |\z)'
        ))
    if ($sections.Count -eq 0) {
        return @()
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($sections[-1].Groups['body'].Value -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') {
            continue
        }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') {
            continue
        }

        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 5 -or $cells[0] -eq 'Stage') {
            continue
        }

        $rows.Add([pscustomobject]@{
                Stage          = $cells[0]
                Roles          = $cells[1]
                DispatchRecord = $cells[2]
                Result         = $cells[3]
                Gate           = $cells[4]
            })
    }

    @($rows)
}

function Get-SquadWatchHistoryReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Rows
    )

    @(
        foreach ($row in $Rows) {
            foreach ($match in [regex]::Matches(
                    [string]$row.DispatchRecord,
                    '`(?<path>history[/\\][^`]+\.md)`'
                )) {
                $match.Groups['path'].Value -replace '\\', '/'
            }
        }
    ) | Sort-Object -Unique
}

function Get-SquadWatchLatestHistoryDeliverable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw
    $headings = @([regex]::Matches($raw, '(?m)^#{2,3}[ \t]+.+$'))
    if ($headings.Count -eq 0) {
        return @()
    }

    $body = $raw.Substring($headings[-1].Index)
    @(
        foreach ($line in [regex]::Matches($body, '(?m)^\s*\*\s*Deliverable:\s*(?<value>.+)$')) {
            $value = $line.Groups['value'].Value
            $tokens = @([regex]::Matches($value, '`(?<path>[^`]+)`') | ForEach-Object {
                    $_.Groups['path'].Value
                })
            if ($tokens.Count -eq 0) {
                $bare = ($value -split '\s\(')[0].Trim().TrimEnd(',', ';', '.')
                if ($bare -match '[/\\]' -and $bare -match '\.[A-Za-z0-9]{1,5}$') {
                    $tokens = @($bare)
                }
            }

            foreach ($token in $tokens) {
                $normalized = $token.Trim().TrimEnd(',', ';', '.') -replace '\\', '/'
                if ($normalized -and $normalized -notmatch '[*?{}]') {
                    $normalized
                }
            }
        }
    )
}

function Test-SquadWatchLifecycle {
    <#
    .SYNOPSIS
        Verifies that a change-producing Watch Mode run completed the selected
        sub-squad lifecycle and left auditable stage, history, state, and deliverable
        evidence before a patch crosses into the write-capable job.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MemberRoot,

        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [string]$StateModulePath,

        [string]$ExpectedStateModuleHash
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $MemberRoot -PathType Container)) {
        throw "Squad Watch lifecycle handoff blocked: member root '$MemberRoot' does not exist."
    }

    $member = (Resolve-Path -LiteralPath $MemberRoot).Path
    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $stateModule = if ($StateModulePath) {
        [System.IO.Path]::GetFullPath($StateModulePath)
    }
    else {
        Join-Path $workspace 'tests/tier1/SquadState.psm1'
    }
    if (-not (Test-Path -LiteralPath $stateModule -PathType Leaf)) {
        throw "Squad Watch lifecycle handoff blocked: state parser not found at '$stateModule'."
    }
    if ($ExpectedStateModuleHash) {
        $actualStateModuleHash = (Get-FileHash -LiteralPath $stateModule -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualStateModuleHash -ne $ExpectedStateModuleHash.ToLowerInvariant()) {
            throw 'Squad Watch lifecycle handoff blocked: state parser changed after checkout.'
        }
    }

    Import-Module $stateModule -Force -Scope Local
    $model = Get-SquadStateModel -SquadRoot $member

    foreach ($file in @(
            'team.md'
            'routing.md'
            'decisions.md'
            'state.json'
            'notifications.md'
            'consumption.md'
            'consumption-rates.md'
        )) {
        if (-not (Test-Path -LiteralPath (Join-Path $member $file) -PathType Leaf)) {
            $failures.Add("missing required state file '$file'")
        }
    }

    if (-not $model.State) {
        $failures.Add('state.json is missing or invalid')
    }

    foreach ($role in @('researcher', 'lead', 'developer', 'tester', 'scribe')) {
        if (-not $model.RoleAgents.ContainsKey($role) -or @($model.RoleAgents[$role]).Count -eq 0) {
            $failures.Add("team.md is missing the required '$role' role")
        }
    }

    foreach ($directory in @('research', 'plans', 'changes', 'reviews')) {
        $path = Join-Path $member $directory
        $hasArtifact = (Test-Path -LiteralPath $path -PathType Container) -and
        $null -ne (Get-ChildItem -LiteralPath $path -File -Recurse -Force | Select-Object -First 1)
        if (-not $hasArtifact) {
            $failures.Add("missing lifecycle artifact under '$directory/'")
        }
    }

    $historyRoot = Join-Path $member 'history'
    $summaries = @(
        if (Test-Path -LiteralPath $historyRoot -PathType Container) {
            Get-ChildItem -LiteralPath $historyRoot -Filter 'autopilot-run-*.md' -File |
                Sort-Object -Property LastWriteTimeUtc, Name -Descending
        }
    )
    if ($summaries.Count -eq 0) {
        $failures.Add("missing 'history/autopilot-run-*.md' summary")
    }

    $stageRows = @()
    $historyReferences = @()
    if ($summaries.Count -gt 0) {
        $summaryText = Get-Content -LiteralPath $summaries[0].FullName -Raw
        $outcomes = @([regex]::Matches($summaryText, '(?m)^\*\s*Outcome:\s*(?<value>.+)$'))
        if ($outcomes.Count -eq 0 -or $outcomes[-1].Groups['value'].Value -notmatch '^completed\b') {
            $failures.Add("latest autopilot summary does not report a completed outcome")
        }

        $stageRows = @(Get-SquadWatchStageRow -Summary $summaryText)
        foreach ($stage in @('research', 'plan', 'council', 'implement', 'review')) {
            $stageMatches = @($stageRows | Where-Object {
                    ([string]$_.Stage).Split(':')[0].Trim().ToLowerInvariant() -eq $stage
                })
            if ($stageMatches.Count -eq 0) {
                $failures.Add("latest autopilot summary is missing the '$stage' stage row")
            }
        }

        $historyReferences = @(Get-SquadWatchHistoryReference -Rows $stageRows)
        foreach ($relativePath in $historyReferences) {
            if ($relativePath -match '(^|/)\.\.(/|$)') {
                $failures.Add("autopilot summary contains unsafe history path '$relativePath'")
                continue
            }
            if (-not (Test-Path -LiteralPath (Join-Path $member $relativePath) -PathType Leaf)) {
                $failures.Add("autopilot summary references missing '$relativePath'")
            }
        }

        foreach ($stage in @('research', 'plan', 'review')) {
            $row = @($stageRows | Where-Object {
                    ([string]$_.Stage).Split(':')[0].Trim().ToLowerInvariant() -eq $stage
                } | Select-Object -First 1)
            if ($row.Count -eq 0) {
                continue
            }

            $role = if ($stage -eq 'plan') { 'lead' } elseif ($stage -eq 'review') { 'tester' } else { 'researcher' }
            $allowedAgents = @($model.RoleAgents[$role])
            $rowReferences = @(Get-SquadWatchHistoryReference -Rows $row)
            $recordedAgents = @($rowReferences | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })
            if ($recordedAgents.Count -eq 0 -or
                @($recordedAgents | Where-Object { $_ -in $allowedAgents }).Count -eq 0) {
                $failures.Add("'$stage' has no dispatch history for the roster's '$role' agent")
            }
        }

        $implementRows = @($stageRows | Where-Object {
                ([string]$_.Stage).Split(':')[0].Trim().ToLowerInvariant() -eq 'implement'
            })
        $implementReferences = @(Get-SquadWatchHistoryReference -Rows $implementRows)
        $implementAgents = @($implementReferences | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })
        if ($implementAgents.Count -eq 0 -or
            @($implementAgents | Where-Object { $_ -in $model.RosterAgents }).Count -eq 0) {
            $failures.Add('implement has no dispatch history for a selected roster agent')
        }

        $councilRows = @($stageRows | Where-Object {
                ([string]$_.Stage).Split(':')[0].Trim().ToLowerInvariant() -eq 'council'
            })
        if ($councilRows.Count -gt 0) {
            $councilSkipped = @($councilRows | Where-Object {
                    $_.Result -match '(?i)\b(skipped|not required|not applicable)\b'
                }).Count -eq $councilRows.Count

            if ($councilSkipped) {
                foreach ($row in $councilRows) {
                    if ($row.DispatchRecord -notmatch '^(?i:n/?a|not applicable|not required|skipped|[-\u2014])$') {
                        $failures.Add('skipped council row must use an explicit non-dispatch marker')
                    }
                }
            }
            else {
                $councilReferences = @(Get-SquadWatchHistoryReference -Rows $councilRows)
                $councilAgents = @($councilReferences | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })
                $allowedCouncilAgents = @(
                    foreach ($role in @('architect', 'security', 'cost-manager', 'product-owner', 'rai')) {
                        if ($model.RoleAgents.ContainsKey($role)) {
                            @($model.RoleAgents[$role])
                        }
                    }
                ) | Sort-Object -Unique

                if ($councilAgents.Count -eq 0 -or
                    @($councilAgents | Where-Object { $_ -in $allowedCouncilAgents }).Count -eq 0) {
                    $failures.Add('council has no dispatch history for a selected council agent')
                }
                if ($model.Decisions -notmatch '(?m)^## Council Verdict\b') {
                    $failures.Add("council ran without a recorded '## Council Verdict' decision")
                }
            }
        }
    }

    if ($model.RoleAgents.ContainsKey('scribe')) {
        $scribeHistory = @($model.RoleAgents['scribe'] | Where-Object {
                Test-Path -LiteralPath (Join-Path $historyRoot "$_.md") -PathType Leaf
            })
        if ($scribeHistory.Count -eq 0) {
            $failures.Add("history is missing the selected 'scribe' agent")
        }
    }

    foreach ($historyReference in $historyReferences) {
        $historyPath = Join-Path $member $historyReference
        if (-not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
            continue
        }

        $agent = [System.IO.Path]::GetFileNameWithoutExtension($historyPath)
        $deliverables = @(Get-SquadWatchLatestHistoryDeliverable -Path $historyPath)
        if ($deliverables.Count -eq 0) {
            $failures.Add("dispatch history '$historyReference' names no deliverable in its latest entry")
            continue
        }

        $root = if ($model.AgentRoots.ContainsKey($agent)) { $model.AgentRoots[$agent] } else { $null }
        foreach ($deliverable in $deliverables) {
            if ($deliverable -match '(^|/)\.\.(/|$)') {
                $failures.Add("$historyReference contains unsafe deliverable '$deliverable'")
                continue
            }

            $tail = Get-DeliverableTail $deliverable
            $resolved = @(
                Join-Path $workspace $deliverable
                Join-Path $member $deliverable
                Join-Path $member $tail
            ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
            if (-not $resolved) {
                $failures.Add("$historyReference references missing deliverable '$deliverable'")
                continue
            }

            if ($root) {
                $declaredPath = Get-DeliverableTail $deliverable
                $prefix = (Get-DeliverableTail (($root -split '<')[0])).TrimEnd('/')
                if (-not $declaredPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                    $failures.Add("$historyReference deliverable '$deliverable' is outside '$root'")
                }
            }
        }
    }

    if ($failures.Count -gt 0) {
        throw "Squad Watch lifecycle handoff blocked:`n- $($failures -join "`n- ")"
    }

    [pscustomobject]@{
        MemberRoot         = $member
        Summary            = if ($summaries.Count -gt 0) { $summaries[0].FullName } else { $null }
        Stages             = @($stageRows | ForEach-Object { $_.Stage })
        HistoryReferences  = $historyReferences
    }
}

function Invoke-SquadWatchGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = @(& git -C $WorkspaceRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join "`n")"
    }

    @($output)
}

function New-SquadWatchHandoff {
    <#
    .SYNOPSIS
        Stages a Watch Mode run, treats an unchanged workspace as a legitimate
        no-change outcome, validates lifecycle evidence for material changes, and
        writes the binary patch consumed by the write-capable job.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [string]$MemberRoot,

        [Parameter(Mandatory)]
        [string]$PatchPath,

        [string]$StateModulePath,

        [string]$ExpectedStateModuleHash
    )

    $workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
    $patch = [System.IO.Path]::GetFullPath($PatchPath)

    if (-not $PSCmdlet.ShouldProcess($workspace, 'Stage Watch Mode changes and create the handoff patch')) {
        return
    }

    Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments @('add', '-A') | Out-Null
    $stagedPaths = @(
        Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments @(
            'diff', '--cached', '--name-only', '--diff-filter=ACDMRTUXB'
        ) | Where-Object { $_ }
    )

    if ($stagedPaths.Count -eq 0) {
        if (Test-Path -LiteralPath $patch) {
            Remove-Item -LiteralPath $patch -Force
        }
        return [pscustomobject]@{
            HasChanges      = $false
            StagedPaths     = @()
            MaterialChanges = @()
            PatchPath       = $null
        }
    }

    $materialChanges = @($stagedPaths | Where-Object {
            $normalized = $_ -replace '\\', '/'
            $normalized -notmatch '^\.copilot-tracking/squad(?:/|$)' -and
            $normalized -notmatch '^\.changes/unreleased(?:/|$)'
        })

    if ($materialChanges.Count -gt 0) {
        Test-SquadWatchLifecycle `
            -MemberRoot $MemberRoot `
            -WorkspaceRoot $workspace `
            -StateModulePath $StateModulePath `
            -ExpectedStateModuleHash $ExpectedStateModuleHash | Out-Null
    }

    $parent = Split-Path -Parent $patch
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Invoke-SquadWatchGit -WorkspaceRoot $workspace -Arguments @(
        'diff', '--cached', '--binary', "--output=$patch"
    ) | Out-Null

    [pscustomobject]@{
        HasChanges      = $true
        StagedPaths     = $stagedPaths
        MaterialChanges = $materialChanges
        PatchPath       = $patch
    }
}

Export-ModuleMember -Function @(
    'Enable-SquadWatchRuntimeOverlay'
    'Restore-SquadWatchRuntimeOverlay'
    'Test-SquadWatchLifecycle'
    'New-SquadWatchHandoff'
)
