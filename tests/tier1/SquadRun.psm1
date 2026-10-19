# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Drives a real, headless squad run and reduces what it left on disk to an observation.
#
# The run is nondeterministic. The observation is not: every field below is read from a
# file the run wrote, never from the prose it emitted. That separation is the whole
# reason Tier 1 can gate a release - a model that phrases its answer differently must
# not fail the suite, and a model that skipped a dispatch must.

#Requires -Version 7.4

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'SquadInstall.psm1') -Force

# State, not deliverables. Everything else the run created is a deliverable, including
# the rest of .copilot-tracking/, which is where several roster roots point.
$script:StatePrefix = '.copilot-tracking/squad/'

# Installed package and manifest, present before the run started.
$script:PackagePrefixes = @('.github/', '.agents/', 'apm.yml', 'install.log', 'apm_modules/')

function ConvertTo-ComparableName {
    <#
    .SYNOPSIS
        Normalizes a role, agent name, or history file name to one comparable token.
    #>
    param([string]$Value)

    if (-not $Value) { return '' }
    ($Value -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
}

function New-SquadWorkspace {
    <#
    .SYNOPSIS
        Builds a scratch repository with the package installed and the fixture on top.
    .DESCRIPTION
        The package is installed first because APM expects an empty directory; the
        fixture is copied over it. The result is committed so that everything the run
        subsequently writes is visible to `git status` as the run's own output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(Mandatory)]
        [string]$FixturePath,

        [string]$Ref,

        [string]$SourceRoot
    )

    if ($Ref -and $SourceRoot) { throw 'Supply -Ref or -SourceRoot, not both.' }
    if (-not $Ref -and -not $SourceRoot) { throw 'Supply -Ref or -SourceRoot.' }

    $install = if ($SourceRoot) {
        Install-SquadPackage -Destination $Destination -SourceRoot $SourceRoot
    }
    else {
        Install-SquadPackage -Destination $Destination -Ref $Ref
    }

    Copy-Item -Path (Join-Path $FixturePath '*') -Destination $install.Root -Recurse -Force

    Push-Location $install.Root
    try {
        & git init --quiet --initial-branch=main 2>&1 | Out-Null
        & git config user.name 'tier1-harness' | Out-Null
        & git config user.email 'tier1-harness@localhost' | Out-Null
        & git add -A 2>&1 | Out-Null
        & git commit --quiet -m 'fixture baseline' 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Failed to commit the fixture baseline; deliverable detection needs a clean starting tree.' }
    }
    finally {
        Pop-Location
    }

    $install
}

function ConvertTo-ProcessArgument {
    <#
    .SYNOPSIS
        Quotes one argument so a joined argument string survives as a single token.
    .DESCRIPTION
        Start-Process concatenates its argument list with spaces and does no quoting of
        its own, so any argument holding whitespace has to carry its own quotes. The
        backslash doubling follows the Windows argv rules, which PowerShell also applies
        when it tokenizes the string on Unix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($Value -ne '' -and $Value -notmatch '[\s"]') { return $Value }

    $escaped = $Value -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    '"' + $escaped + '"'
}

function Invoke-SquadTurn {
    <#
    .SYNOPSIS
        Runs one headless Copilot CLI turn in a workspace and captures its transcript.
    .DESCRIPTION
        The model is pinned, because a headless run does not read the `model:`
        frontmatter the VS Code host honors and results across runs are not comparable
        otherwise. A turn that exceeds the timeout is killed and reported as a timeout
        rather than being allowed to stall the release gate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Workspace,

        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter(Mandatory)]
        [string]$TranscriptPath,

        [string]$LogDir,

        [switch]$CaptureDispatchEvents,

        [int]$TimeoutMinutes = 20
    )

    $errorPath = [System.IO.Path]::ChangeExtension($TranscriptPath, '.err.log')
    $started = Get-Date
    if ($LogDir) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

    # Start-Process joins its argument list with spaces, so the prompt has to arrive
    # already quoted or the CLI reads each word as a separate argument.
    $argumentValues = @(
        '-p', (ConvertTo-ProcessArgument $Prompt)
        '--model', (ConvertTo-ProcessArgument $Model)
        '--allow-all-tools'
        '--deny-tool', (ConvertTo-ProcessArgument 'shell(rm)')
    )
    if ($CaptureDispatchEvents) {
        $argumentValues += @('--output-format', 'json')
    }
    if ($LogDir) {
        $argumentValues += @(
            '--log-dir', (ConvertTo-ProcessArgument $LogDir)
            '--log-level', 'debug'
        )
    }
    $arguments = $argumentValues -join ' '

    $process = Start-Process -FilePath 'copilot' -ArgumentList $arguments `
        -WorkingDirectory $Workspace -NoNewWindow -PassThru `
        -RedirectStandardOutput $TranscriptPath -RedirectStandardError $errorPath

    $timedOut = $false
    if (-not $process.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        $timedOut = $true
        try { $process.Kill($true) } catch { Write-Debug 'The run process exited between the timeout check and the kill; nothing to terminate.' }
        $process.WaitForExit(30 * 1000) | Out-Null
    }

    $transcript = if (Test-Path -LiteralPath $TranscriptPath) { Get-Content -LiteralPath $TranscriptPath -Raw } else { '' }

    [pscustomobject]@{
        ExitCode   = if ($timedOut) { 124 } else { $process.ExitCode }
        TimedOut   = $timedOut
        Seconds    = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        Transcript = $transcript
        Answer     = $transcript
        ErrorLog   = if (Test-Path -LiteralPath $errorPath) { Get-Content -LiteralPath $errorPath -Raw } else { '' }
        LogDir     = $LogDir
    }
}

function Publish-ConnectorConsumerResult {
    <#
    .SYNOPSIS
        Writes one deterministic external result for the Tier 1 connector resume scenario.
    .DESCRIPTION
        This helper is the consumer side only. It requires the real Squad Connector
        dispatch to have published both request and snapshot first, preserves both
        byte-for-byte, writes the requested task-owned artifact, and then publishes the
        matching result envelope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][string]$ConnectorId,
        [Parameter(Mandatory)][string]$ArtifactPath,
        [Parameter(Mandatory)][string]$ArtifactContent,
        [Parameter(Mandatory)][string]$Narrative
    )

    $dropPath = Join-Path $Workspace '.connector-drops' $ConnectorId
    $requests = @(Get-ChildItem -LiteralPath $dropPath -Filter '*.request.json' -File -ErrorAction SilentlyContinue)
    if ($requests.Count -ne 1) {
        throw "Expected one request in '$dropPath', found $($requests.Count)."
    }

    $requestPath = $requests[0].FullName
    $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    if ([string]$request.connectorId -cne $ConnectorId) {
        throw "Request connectorId '$($request.connectorId)' does not match '$ConnectorId'."
    }
    if (-not $request.taskId -or -not $request.deliverableRoot -or -not $request.bindingId) {
        throw 'The connector request is missing taskId, deliverableRoot, or bindingId.'
    }

    $snapshotPath = Join-Path $dropPath "$($request.taskId).snapshot.json"
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        throw "The connector request has no durable snapshot at '$snapshotPath'."
    }
    $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
    if ([string]$snapshot.taskId -cne [string]$request.taskId -or
        [string]$snapshot.deliverableRoot -cne [string]$request.deliverableRoot -or
        $snapshot.PSObject.Properties.Name -notcontains 'preExistingPaths') {
        throw 'The connector snapshot does not bind to the request or omits preExistingPaths.'
    }

    $requestHash = (Get-FileHash -LiteralPath $requestPath -Algorithm SHA256).Hash
    $snapshotHash = (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash
    $artifactRoot = if ([System.IO.Path]::IsPathRooted([string]$request.deliverableRoot)) {
        [string]$request.deliverableRoot
    }
    else {
        Join-Path $Workspace ([string]$request.deliverableRoot)
    }
    $deliveredPath = Join-Path $artifactRoot $ArtifactPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $deliveredPath) -Force | Out-Null
    Set-Content -LiteralPath $deliveredPath -Value $ArtifactContent -Encoding utf8NoBOM -NoNewline

    $result = [ordered]@{
        taskId      = [string]$request.taskId
        connectorId = [string]$request.connectorId
        bindingId   = [string]$request.bindingId
        role        = [string]$request.role
        status      = 'completed'
        artifacts   = @(
            [ordered]@{
                path = $ArtifactPath -replace '\\', '/'
                type = [System.IO.Path]::GetExtension($ArtifactPath).TrimStart('.').ToLowerInvariant()
            }
        )
        narrative   = $Narrative
        createdAt   = [DateTime]::UtcNow.ToString('o')
    }
    $resultPath = Join-Path $dropPath "$($request.taskId).result.json"
    $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $resultPath -Encoding utf8NoBOM

    [pscustomobject]@{
        TaskId       = [string]$request.taskId
        RequestPath  = $requestPath
        RequestHash  = $requestHash
        SnapshotPath = $snapshotPath
        SnapshotHash = $snapshotHash
        ResultPath   = $resultPath
        ArtifactPath = $deliveredPath
    }
}

function Get-SquadDispatchEvidence {
    <#
    .SYNOPSIS
        Finds machine-generated dispatch-start evidence for one agent.
    .DESCRIPTION
        Model prose is never evidence. JSON output is accepted only for start/invoke
        events whose serialized event contains the exact agent name. Debug logs are a
        fallback only when a line contains both a dispatch/tool marker and that name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TranscriptPath,
        [string]$LogDir,
        [Parameter(Mandatory)][string]$AgentName
    )

    $evidence = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $TranscriptPath) {
        foreach ($line in (Get-Content -LiteralPath $TranscriptPath)) {
            $trimmed = $line.Trim()
            if (-not $trimmed.StartsWith('{')) { continue }
            try { $event = $trimmed | ConvertFrom-Json -Depth 64 } catch { continue }
            $type = @('type', 'event', 'kind') |
                ForEach-Object { $event.PSObject.Properties[$_]?.Value } |
                Where-Object { $_ } |
                Select-Object -First 1
            if (-not $type -or [string]$type -notmatch '(?i)start|begin|invoke|dispatch') { continue }
            $serialized = $event | ConvertTo-Json -Depth 64 -Compress
            if ($serialized.Contains($AgentName, [System.StringComparison]::Ordinal)) {
                $evidence.Add("json:$type")
            }
        }
    }

    if ($evidence.Count -eq 0 -and $LogDir -and (Test-Path -LiteralPath $LogDir)) {
        foreach ($file in (Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -File -Recurse -ErrorAction SilentlyContinue)) {
            foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
                if ($line -notmatch '(?i)dispatch|subagent|tool|task|invoke') { continue }
                if ($line.Contains($AgentName, [System.StringComparison]::Ordinal)) {
                    $evidence.Add("log:$($file.Name)")
                }
            }
        }
    }
    $evidence.ToArray()
}

function Get-RosterMap {
    <#
    .SYNOPSIS
        Maps every agent and role name in a team.md Members table to its role.
    #>
    param([string]$TeamContent)

    $map = @{}
    if (-not $TeamContent) { return $map }

    foreach ($line in ($TeamContent -split '\r?\n')) {
        if ($line -notmatch '^\s*\|') { continue }
        if ($line -match '^\s*\|[\s\-:|]+\|\s*$') { continue }

        $cells = @(($line.Trim().Trim('|') -split '\|') | ForEach-Object { $_.Trim().Trim('`') })
        if ($cells.Count -lt 3) { continue }
        if ($cells[0] -match '^(Role|Member Name)$') { continue }

        $role = $cells[0]
        foreach ($candidate in @($cells[0], $cells[1], $cells[2])) {
            $key = ConvertTo-ComparableName $candidate
            if ($key) { $map[$key] = $role }
        }

        # Alternates resolve to the same role, so a fallback dispatch is still attributable.
        if ($cells.Count -ge 4) {
            foreach ($alternate in ($cells[3] -split ',')) {
                $key = ConvertTo-ComparableName $alternate
                if ($key -and $key -ne 'none') { $map[$key] = $role }
            }
        }
    }

    $map
}

function Get-GateVerdict {
    <#
    .SYNOPSIS
        Extracts the gate verdicts the Scribe stamped into decisions.md.
    #>
    param([string]$DecisionsContent)

    if (-not $DecisionsContent) { return @() }

    $pattern = '(?ms)^##\s+(?<gate>Council Verdict|Intake Readiness Verdict)\b(?<head>[^\r\n]*)$(?<body>.*?)(?=^##\s|\z)'
    @(foreach ($match in [regex]::Matches($DecisionsContent, $pattern)) {
            $verdict = [regex]::Match($match.Groups['body'].Value, '(?im)^\s*[*-]\s*(?:Verdict|Readiness)\s*:\s*(?<value>[^\r\n(]+)')
            [pscustomobject]@{
                Gate    = $match.Groups['gate'].Value
                Verdict = if ($verdict.Success) { $verdict.Groups['value'].Value.Trim() } else { 'unrecorded' }
            }
        })
}

function Get-RunObservation {
    <#
    .SYNOPSIS
        Reduces a completed run to the deterministic facts Tier 2 compares.
    .DESCRIPTION
        Four dimensions, matching the Tier 2 questions in the behavior contract: which
        roles ran, which deliverables landed and where, which gates fired with which
        verdict, and what the run answered. Only the last is prose, and only the last is
        ever judged.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Workspace,

        [Parameter(Mandatory)]
        [string]$ScenarioId,

        [string[]]$SquadRoot = @(),

        [string]$Answer = '',

        [hashtable]$Metadata = @{}
    )

    Push-Location $Workspace
    try {
        $changed = @(& git status --porcelain --untracked-files=all | ForEach-Object { ($_ -replace '^..\s+', '').Trim().Trim('"') })
    }
    finally {
        Pop-Location
    }

    $deliverables = @(
        foreach ($path in ($changed | Sort-Object -Unique)) {
            $normalized = $path -replace '\\', '/'
            if ($normalized.StartsWith($script:StatePrefix)) { continue }
            if (@($script:PackagePrefixes | Where-Object { $normalized.StartsWith($_) })) { continue }

            $directory = Split-Path $normalized -Parent
            [pscustomobject]@{
                Path      = $normalized
                Root      = if ($directory) { ($directory -replace '\\', '/') + '/' } else { './' }
                Extension = [System.IO.Path]::GetExtension($normalized)
            }
        }
    )

    $roots = @()
    $roles = @()
    $agents = @()
    $gates = @()
    $totalCost = $null
    $totalCredits = $null

    foreach ($root in $SquadRoot) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        $relative = [System.IO.Path]::GetRelativePath($Workspace, (Resolve-Path -LiteralPath $root).Path) -replace '\\', '/'
        $roots += $relative

        $teamPath = Join-Path $root 'team.md'
        $rosterMap = if (Test-Path -LiteralPath $teamPath) { Get-RosterMap (Get-Content -LiteralPath $teamPath -Raw) } else { @{} }

        $historyDirectory = Join-Path $root 'history'
        if (Test-Path -LiteralPath $historyDirectory) {
            foreach ($file in (Get-ChildItem -LiteralPath $historyDirectory -Filter '*.md' -File)) {
                $agents += $file.BaseName
                $key = ConvertTo-ComparableName $file.BaseName
                $roles += if ($rosterMap.ContainsKey($key)) { $rosterMap[$key] } else { $file.BaseName }
            }
        }

        $decisionsPath = Join-Path $root 'decisions.md'
        if (Test-Path -LiteralPath $decisionsPath) {
            $gates += Get-GateVerdict (Get-Content -LiteralPath $decisionsPath -Raw)
        }

        $ledgerPath = Join-Path $root 'consumption.md'
        if (Test-Path -LiteralPath $ledgerPath) {
            $total = [regex]::Match((Get-Content -LiteralPath $ledgerPath -Raw), '(?im)^\s*\|\s*\**Total\**\s*\|(?<cells>.*)$')
            if ($total.Success) {
                $numbers = @(($total.Groups['cells'].Value -split '\|') |
                        ForEach-Object { ($_ -replace '[*$,]', '').Trim() } |
                        Where-Object { $_ -match '^-?\d+(\.\d+)?$' } |
                        ForEach-Object { [double]$_ })
                if ($numbers.Count -ge 2) {
                    $totalCost = $numbers[-2]
                    $totalCredits = $numbers[-1]
                }
                elseif ($numbers.Count -eq 1) {
                    $totalCost = $numbers[0]
                }
            }
        }
    }

    [pscustomobject]@{
        schemaVersion    = 1
        scenario         = $ScenarioId
        capturedUtc      = (Get-Date).ToUniversalTime().ToString('o')
        metadata         = $Metadata
        squadRoots       = @($roots | Sort-Object)
        roles            = @($roles | Sort-Object -Unique)
        agents           = @($agents | Sort-Object -Unique)
        deliverables     = @($deliverables | Sort-Object Path)
        deliverableRoots = @($deliverables | ForEach-Object { $_.Root } | Sort-Object -Unique)
        gates            = @($gates | Sort-Object Gate, Verdict)
        consumption      = @{ estCostUsd = $totalCost; estCredits = $totalCredits }
        answer           = $Answer
    }
}

Export-ModuleMember -Function New-SquadWorkspace, Invoke-SquadTurn, Publish-ConnectorConsumerResult, Get-SquadDispatchEvidence, Get-RunObservation, Get-RosterMap, Get-GateVerdict, ConvertTo-ComparableName
