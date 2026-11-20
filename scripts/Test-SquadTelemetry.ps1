#!/usr/bin/env pwsh
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Checks reviewed, content-bound no-reporting coverage of a generated plugin.
.DESCRIPTION
    Offline only: never installs, builds, executes package code, or contacts a host.
    Enumerates EVERY file (including supplier, hidden, legal, and binary files).
    Review is an explicit human assertion, not a regex-derived proof of no egress.
    Concrete network call sites and reporting directives supplement that review.
    Candidates are grouped by file/kind, with all matching lines retained; every
    group needs a disposition. Bare documentation URLs, client names, and generic
    execution are not outbound evidence. Task-requested network is not telemetry.
    OccurrenceCount counts distinct matching lines, not runtime executions.

    An external JSON policy has schemaVersion=1, packageVersion, supplierCommit,
    reviewer, reviewedAt, and groups. Each group has id, origin (FirstParty or
    Supplier), classification (LocalOnly, TaskRequestedNetwork, ReferenceMaterial,
    ReviewedAsset, ReportingInstruction, or ReportingCollector), rationale, paths
    (package-relative wildcard selectors), inventorySha256, and dispositions.
    Each disposition has id (from Candidates), classification (LocalOnly,
    TaskRequestedNetwork, ReferenceOnly, ReportingInstruction, or ReportingCollector)
    and rationale. Reporting classifications always fail. Groups must partition
    every file exactly once; their hashes bind the exact path/content set.

    Start WITHOUT a policy to obtain an INCOMPLETE inventory and candidate IDs.
    After manual review, Get-SquadTelemetryInventoryHash computes a group's seal
    over its reviewed inventory subset. It does NOT approve or write a policy.
    Group hashes avoid committing thousands of individual hashes. Adding, removing,
    or changing a file invalidates its group. Policy changes require human review.
    Keep policy and report outside PluginRoot. Never regenerate seals automatically
    in a release gate. Output contains hashes/locations, not source text.
.PARAMETER PluginRoot
    Explicit generated plugin root, not an APM installed .agents tree.
.PARAMETER ReviewPolicyPath
    Trusted reviewed JSON policy outside the package. Omission is incomplete.
.PARAMETER ExpectedSupplierCommit
    Optional independent pin from the selected build source's apm.yml.
.PARAMETER Mode
    Package requires real plugin metadata and supplier provenance. SourceFixture
    is useful for source/unit fixtures but NEVER grants package assurance.
.PARAMETER OutputPath
    Optional JSON report outside PluginRoot; JSON is otherwise written to stdout.
.EXAMPLE
    .\scripts\Test-SquadTelemetry.ps1 -PluginRoot ..\hve-squad-plugin-build
.EXAMPLE
    .\scripts\Test-SquadTelemetry.ps1 -PluginRoot ..\hve-squad-plugin-build -ReviewPolicyPath .\review.json
.NOTES
    Exit 0: complete reviewed static coverage (or explicitly labelled fixture).
    Exit 1: reviewed reporting instruction/collector. Exit 2: incomplete/error.
    Does not prove runtime non-egress, validate reviewer identity, or replace host
    isolation. Non-PowerShell code and obfuscated/dynamic behavior require review.
#>
[CmdletBinding()]
param(
    [string]$PluginRoot,
    [string]$ReviewPolicyPath,
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ExpectedSupplierCommit,
    [ValidateSet('Package', 'SourceFixture')]
    [string]$Mode = 'Package',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

#region Functions

function Get-SquadTelemetryHash {
    <#
    .SYNOPSIS
        Hashes exact bytes with SHA256.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-SquadTelemetryInventoryHash {
    <#
    .SYNOPSIS
        Seals an exact reviewed path/content set, without assigning approval.
    .DESCRIPTION
        Uses ordinal path order and UTF8 JSON pairs to avoid locale, newline,
        and delimiter ambiguities. Call only on the intended review group.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Inventory)
    $paths = [string[]]@($Inventory | ForEach-Object { $_.Path })
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    $byPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Inventory) { $byPath.Add($entry.Path, $entry) }
    $rows = foreach ($path in $paths) {
        ConvertTo-Json -InputObject @($path, $byPath[$path].Sha256) -Compress
    }
    Get-SquadTelemetryHash -Bytes ([Text.Encoding]::UTF8.GetBytes(($rows -join "`n")))
}

function Get-SquadTelemetryCandidate {
    <#
    .SYNOPSIS
        Groups concrete call sites/directives by file/kind, not a telemetry verdict.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes
    )
    $findings = [Collections.Generic.List[object]]::new()
    $byKind = @{}
    $contentHash = Get-SquadTelemetryHash -Bytes $Bytes
    function Add-Candidate {
        param([string]$Kind, [int]$Line)
        if ($byKind.ContainsKey($Kind)) {
            $existing = $byKind[$Kind]
            if ($Line -notin $existing.Lines) {
                $existing.Lines += @($Line)
                $existing.OccurrenceCount++
                if ($Line -lt $existing.Line) { $existing.Line = $Line }
            }
            return
        }
        $idBytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @('FileKindContentV2', $Path, $Kind, $contentHash) -Compress))
        $finding = [pscustomobject]@{
            Id = Get-SquadTelemetryHash -Bytes $idBytes
            Path = $Path; Line = $Line; Lines = @($Line)
            Kind = $Kind; OccurrenceCount = 1
        }
        $byKind[$Kind] = $finding
        $findings.Add($finding)
    }
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
        if ($text.Contains([char]0)) { throw 'Opaque bytes.' }
    }
    catch {
        Add-Candidate -Kind 'OpaqueContent' -Line 0
        return $findings.ToArray()
    }

    $patterns = [ordered]@{
        ReportingDirective = '(?i)\b(?:send|upload|transmit|forward|export|report)\b[^\r\n]{0,100}\b(?:telemetry|usage\s+(?:data|metrics|events|statistics)|session\s+(?:data|contents?|transcripts?)|prompt\s+(?:text|contents?)|diagnostics?|traces?|metrics)\b[^\r\n]{0,120}(?:https?://|\b(?:collector|endpoint|remote|server|cloud)\b)'
        ReportingCollector = '(?i)(?:\b(?:trackEvent|trackException|trackDependency|capture_event|capture_exception|initTelemetry|initializeTelemetry|configure_azure_monitor)\s*\(|\b(?:OTEL_EXPORTER_OTLP_ENDPOINT|APPLICATIONINSIGHTS_CONNECTION_STRING)\s*[:=]|\bnew\s+(?:[a-z.]+\.)?TelemetryClient\s*\()'
    }
    $networkCall = '(?i)(?:\b(?:requests|httpx|axios)\.(?:get|post|put|patch|delete|request|stream)\s*\(|\b(?:urllib\.request\.)?urlopen\s*\(|\b(?:fetch|WebSocket|EventSource)\s*\(|\bhttps?\.(?:request|get)\s*\(|\b(?:socket|client|session|conn|connection)\.(?:connect|connect_async|sendall)\s*\(|\b(?:client|http_client)\.(?:get|post|put|patch|delete|request)\s*\(|\.\s*(?:SendAsync|PostAsync|PutAsync|PatchAsync|GetStringAsync|GetByteArrayAsync|DownloadString|DownloadData|DownloadFile|UploadString|UploadData|UploadFile)\s*\(|\b(?:curl_exec|file_get_contents)\s*\(\s*["'']https?://)'
    $networkCommand = '(?i)(?:^\s*(?:\$\s+)?|`)(?:Invoke-RestMethod|Invoke-WebRequest|Send-MailMessage)\s+-|(?:^\s*(?:\$\s+)?|`)(?:curl|wget)(?:\.exe)?\s+(?:-|["'']?https?://)|(?:^\s*(?:\$\s+)?|`)(?:git\s+(?:fetch|pull|push|clone|ls-remote)|gh\s+api|az\s+rest)\b'
    $isPowerShell = [IO.Path]::GetExtension($Path) -in @('.ps1', '.psm1', '.psd1')
    $lines = $text -split '\r?\n'
    for ($index = 0; $index -lt $lines.Count; $index++) {
        foreach ($kind in $patterns.Keys) {
            if ($lines[$index] -match $patterns[$kind]) {
                Add-Candidate -Kind $kind -Line ($index + 1)
            }
        }
        if (-not $isPowerShell -and ($lines[$index] -match $networkCall -or $lines[$index] -match $networkCommand)) {
            Add-Candidate -Kind 'NetworkSink' -Line ($index + 1)
        }
    }

    if ($isPowerShell) {
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
        foreach ($parseError in $parseErrors) {
            Add-Candidate -Kind 'UnparsedPowerShell' -Line $parseError.Extent.StartLineNumber
        }
        $isCandidate = {
            param($item)
            $item -is [Management.Automation.Language.CommandAst] -or
            $item -is [Management.Automation.Language.InvokeMemberExpressionAst]
        }
        $nodes = $ast.FindAll($isCandidate, $true)
        foreach ($node in $nodes) {
            if ($node -is [Management.Automation.Language.CommandAst]) {
                $name = $node.GetCommandName()
                if ($name -match '(?i)(?:^|\\)(?:Invoke-RestMethod|Invoke-WebRequest|iwr|irm|curl(?:\.exe)?|wget(?:\.exe)?|Send-MailMessage|ssh|scp|nc)$' -or
                    ($name -in @('git', 'gh', 'az') -and $node.Extent.Text -match '\b(?:git\s+(?:fetch|pull|push|clone|ls-remote)|gh\s+api|az\s+rest)\b')) {
                    Add-Candidate -Kind 'PowerShellSink' -Line $node.Extent.StartLineNumber
                }
            }
            elseif ($node.Member -is [Management.Automation.Language.StringConstantExpressionAst] -and
                $node.Member.Value -match '(?i)^(?:Send|SendAsync|PostAsync|PutAsync|PatchAsync|GetAsync|GetStringAsync|GetByteArrayAsync|Download(?:String|Data|File)|Upload(?:String|Data|File)|Connect|ConnectAsync)$') {
                Add-Candidate -Kind 'MemberSink' -Line $node.Extent.StartLineNumber
            }
        }
    }
    foreach ($finding in $findings) { $finding.Lines = @($finding.Lines | Sort-Object) }
    $findings.ToArray()
}

function Test-SquadTelemetryRelativePath {
    <#
    .SYNOPSIS
        Checks canonical package-relative provenance paths.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()][string]$Path)
    return ($Path -and $Path -notmatch '[\\\r\n]' -and
        -not [IO.Path]::IsPathRooted($Path) -and $Path -notmatch '(^|/)\.\.?(/|$)')
}

function Invoke-SquadTelemetryConformance {
    <#
    .SYNOPSIS
        Returns complete inventory, candidates, reviewed coverage, and exit status.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$PluginRoot,
        [string]$ReviewPolicyPath,
        [string]$ExpectedSupplierCommit,
        [ValidateSet('Package', 'SourceFixture')][string]$Mode = 'Package'
    )
    $root = (Get-Item -LiteralPath $PluginRoot -Force).FullName
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'PluginRoot must be a directory.' }
    if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Linked package roots cannot be inventoried completely.'
    }
    $issues = [Collections.Generic.List[string]]::new()
    $inventory = [Collections.Generic.List[object]]::new()
    $candidates = [Collections.Generic.List[object]]::new()
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($root)
    while ($queue.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
            $relative = [IO.Path]::GetRelativePath($root, $item.FullName).Replace('\', '/')
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $issues.Add("Linked entry prevents complete inventory: $relative")
                if (-not $item.PSIsContainer) {
                    $inventory.Add([pscustomobject]@{ Path = $relative; Sha256 = $null; Origin = 'Unknown'; Reviewed = $false; Group = $null })
                }
                continue
            }
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName); continue }
            $bytes = [IO.File]::ReadAllBytes($item.FullName)
            $entry = [pscustomobject]@{
                Path = $relative; Sha256 = Get-SquadTelemetryHash -Bytes $bytes
                Origin = 'FirstParty'; Reviewed = $false; Group = $null
            }
            $inventory.Add($entry)
            foreach ($candidate in Get-SquadTelemetryCandidate -Path $relative -Bytes $bytes) { $candidates.Add($candidate) }
        }
    }
    if (-not $inventory.Count) { $issues.Add('Package inventory is empty.') }
    $byPath = @{}
    foreach ($entry in $inventory) { $byPath[$entry.Path] = $entry }
    $version = 'source-fixture'
    $pin = ''
    $supplierTargets = @{}
    if ($Mode -eq 'Package') {
        foreach ($required in @('plugin.json', '.github/plugin/plugin.json', 'hooks.json', '.github/plugin/marketplace.json', '.github/plugin/hve-core-source.json')) {
            if (-not $byPath.ContainsKey($required) -or -not $byPath[$required].Sha256) {
                $issues.Add("Missing package metadata: $required")
            }
        }
        if ($byPath.ContainsKey('plugin.json') -and $byPath['plugin.json'].Sha256) {
            $manifest = Get-Content -LiteralPath (Join-Path $root 'plugin.json') -Raw | ConvertFrom-Json -AsHashtable
            $version = [string]$manifest['version']
            if ($manifest['name'] -ne 'hve-squad' -or -not $version) { $issues.Add('Invalid hve-squad package identity.') }
        }
        if ($byPath.ContainsKey('.github/plugin/hve-core-source.json') -and $byPath['.github/plugin/hve-core-source.json'].Sha256) {
            $provenance = Get-Content -LiteralPath (Join-Path $root '.github/plugin/hve-core-source.json') -Raw | ConvertFrom-Json -AsHashtable
            $pin = [string]$provenance['commit']
            if ($provenance['repository'] -ne 'microsoft/hve-core' -or $pin -notmatch '^[0-9a-f]{40}$') {
                $issues.Add('Invalid supplier identity/pin.')
            }
            foreach ($file in @($provenance['files'])) {
                $target = [string]$file['target']
                if (-not (Test-SquadTelemetryRelativePath $target) -or
                    -not (Test-SquadTelemetryRelativePath ([string]$file['source']))) {
                    $issues.Add('Invalid supplier provenance path.')
                    continue
                }
                if ($supplierTargets.ContainsKey($target)) { $issues.Add("Duplicate supplier target: $target") }
                $supplierTargets[$target] = $true
                if (-not $byPath.ContainsKey($target)) { $issues.Add("Missing shipped supplier file: $target") }
            }
            if (-not $supplierTargets.Count) { $issues.Add('Supplier provenance contains no shipped files.') }
        }
        if ($ExpectedSupplierCommit -and $pin -cne $ExpectedSupplierCommit) { $issues.Add('Supplier pin differs from selected source pin.') }
    }
    foreach ($entry in $inventory) {
        if ($supplierTargets.ContainsKey($entry.Path) -or $entry.Path -like 'third-party/hve-core/*' -or
            ($Mode -eq 'Package' -and $entry.Path -match '^\.github/(?:agents|instructions|skills|extensions|prompts)/')) {
            $entry.Origin = 'Supplier'
            if ($Mode -eq 'Package' -and $entry.Path -notlike 'third-party/hve-core/*' -and
                -not $supplierTargets.ContainsKey($entry.Path)) {
                $issues.Add("Supplier file missing from provenance: $($entry.Path)")
            }
        }
    }

    $policy = $null
    $policySha256 = $null
    if ($ReviewPolicyPath) {
        $policyPath = (Resolve-Path -LiteralPath $ReviewPolicyPath).Path
        $relativePolicy = [IO.Path]::GetRelativePath($root, $policyPath)
        if (-not [IO.Path]::IsPathRooted($relativePolicy) -and $relativePolicy -ne '..' -and $relativePolicy -notmatch '^\.\.[\\/]') {
            throw 'Review policy must be outside PluginRoot.'
        }
        $policyBytes = [IO.File]::ReadAllBytes($policyPath)
        $policySha256 = Get-SquadTelemetryHash -Bytes $policyBytes
        $policy = [Text.Encoding]::UTF8.GetString($policyBytes) | ConvertFrom-Json -AsHashtable
    }
    $policyValid = $false
    if ($policy) {
        $identityValid = $policy['schemaVersion'] -eq 1 -and $policy['packageVersion'] -ceq $version -and $policy['supplierCommit'] -ceq $pin
        $reviewerValid = -not [string]::IsNullOrWhiteSpace($policy['reviewer']) -and -not [string]::IsNullOrWhiteSpace($policy['reviewedAt'])
        $policyValid = $identityValid -and $reviewerValid
        if (-not $policyValid) { $issues.Add('Review policy identity/version/pin/reviewer metadata is missing or stale.') }
    }
    else { $issues.Add('No reviewed policy: inventory is NOT no-reporting assurance.') }

    $groupResults = [Collections.Generic.List[object]]::new()
    $dispositions = @{}
    $reporting = [Collections.Generic.List[string]]::new()
    $groupIds = @{}
    $matched = @{}
    $candidateById = @{}
    foreach ($candidate in $candidates) { $candidateById[$candidate.Id] = $candidate }
    $reviewGroups = if ($policy) { @($policy['groups']) } else { @() }
    foreach ($group in @($reviewGroups | Where-Object { $null -ne $_ })) {
        $id = [string]$group['id']
        $valid = $policyValid
        if (-not $id -or $groupIds.ContainsKey($id)) { $valid = $false; $issues.Add("Missing/duplicate review group: $id") }
        if ($id) { $groupIds[$id] = $true }
        if ($group['origin'] -notin @('FirstParty', 'Supplier') -or
            $group['classification'] -notin @('LocalOnly', 'TaskRequestedNetwork', 'ReferenceMaterial', 'ReviewedAsset', 'ReportingInstruction', 'ReportingCollector') -or
            [string]::IsNullOrWhiteSpace($group['rationale']) -or -not @($group['paths']).Count) {
            $valid = $false
            $issues.Add("Unclassified review group: $id")
        }
        $selectGroup = {
            $path = $_.Path
            @($group['paths'] | Where-Object { $path -clike $_ }).Count -gt 0
        }
        $selected = @($inventory | Where-Object $selectGroup)
        $selectedPaths = @{}
        foreach ($entry in $selected) { $selectedPaths[$entry.Path] = $true }
        $digest = Get-SquadTelemetryInventoryHash -Inventory $selected
        if (-not $selected.Count -or $group['inventorySha256'] -cne $digest) {
            $valid = $false
            $issues.Add("Changed/new/missing or unreviewed content in group: $id")
        }
        if ($group['classification'] -in @('ReportingInstruction', 'ReportingCollector')) { $reporting.Add("Review group $id permits $($group['classification']).") }
        foreach ($entry in $selected) {
            if ($matched.ContainsKey($entry.Path)) { $issues.Add("Overlapping review groups: $($entry.Path)") }
            $matched[$entry.Path] = $true
            if ($entry.Origin -ne $group['origin'] -or -not $entry.Sha256) {
                $issues.Add("Incorrect origin/unreadable content: $($entry.Path)")
                continue
            }
            if ($valid) { $entry.Reviewed = $true; $entry.Group = $id }
        }
        foreach ($disposition in @($group['dispositions'] | Where-Object { $null -ne $_ })) {
            $candidateId = [string]$disposition['id']
            $candidate = $candidateById[$candidateId]
            if (-not $candidate -or -not $selectedPaths.ContainsKey($candidate.Path) -or
                $dispositions.ContainsKey($candidateId) -or
                $disposition['classification'] -notin @('LocalOnly', 'TaskRequestedNetwork', 'ReferenceOnly', 'ReportingInstruction', 'ReportingCollector') -or
                [string]::IsNullOrWhiteSpace($disposition['rationale'])) {
                $issues.Add("Invalid/stale/duplicate candidate disposition in group: $id")
                continue
            }
            if ($disposition['classification'] -in @('ReportingInstruction', 'ReportingCollector')) {
                $reporting.Add("Reporting candidate $candidateId in $($candidate.Path).")
            }
            if ($valid) { $dispositions[$candidateId] = $disposition }
        }
        $groupResult = [pscustomobject]@{
            Id = $id; Origin = $group['origin']; Classification = $group['classification']
            Rationale = $group['rationale']; FileCount = $selected.Count
            InventorySha256 = $digest; SealMatches = $valid
        }
        $groupResults.Add($groupResult)
    }
    $unreviewedFiles = @($inventory | Where-Object { -not $_.Reviewed })
    if ($unreviewedFiles.Count) {
        $issues.Add("Unreviewed files: $($unreviewedFiles.Count). See Inventory entries with Reviewed=false and Summary.ByOrigin.")
    }
    $candidateOccurrences = 0
    foreach ($candidate in $candidates) {
        $candidateOccurrences += $candidate.OccurrenceCount
        $candidate | Add-Member -NotePropertyName Disposition -NotePropertyValue $null
        if ($dispositions.ContainsKey($candidate.Id)) { $candidate.Disposition = $dispositions[$candidate.Id]['classification'] }
    }
    $unclassified = @($candidates | Where-Object { -not $_.Disposition })
    if ($unclassified.Count) {
        $issues.Add("Unclassified candidate groups: $($unclassified.Count). See Candidates entries with Disposition=null and Summary.ByKind.")
    }
    $byOrigin = foreach ($origin in @('FirstParty', 'Supplier', 'Unknown')) {
        $files = @($inventory | Where-Object Origin -EQ $origin)
        if ($files.Count) {
            [pscustomobject]@{
                Origin = $origin; FileCount = $files.Count
                ReviewedFileCount = @($files | Where-Object Reviewed).Count
                UnreviewedFileCount = @($files | Where-Object { -not $_.Reviewed }).Count
            }
        }
    }
    $byCandidateKind = foreach ($kind in @($candidates | ForEach-Object Kind | Sort-Object -Unique)) {
        $kindCandidates = @($candidates | Where-Object Kind -EQ $kind)
        [pscustomobject]@{
            Kind = $kind; CandidateCount = $kindCandidates.Count
            OccurrenceCount = [int]($kindCandidates | Measure-Object OccurrenceCount -Sum).Sum
            UnclassifiedCandidateCount = @($kindCandidates | Where-Object { -not $_.Disposition }).Count
        }
    }
    if ($Mode -eq 'Package' -and -not @($inventory | Where-Object Origin -EQ 'Supplier').Count) {
        $issues.Add('Missing full supplier inventory/coverage.')
    }
    $exitCode = if ($reporting.Count) { 1 } elseif ($issues.Count) { 2 } else { 0 }
    [pscustomobject]@{
        SchemaVersion = 1; Mode = $Mode
        Status = $(if ($exitCode -eq 1) { 'Failed' } elseif ($exitCode -eq 2) { 'Incomplete' } else { 'Complete' })
        ExitCode = $exitCode
        PackageAssurance = ($Mode -eq 'Package' -and $exitCode -eq 0)
        AssuranceScope = $(if ($Mode -eq 'Package') { 'Reviewed static package content; NOT runtime non-egress proof' } else { 'SOURCE FIXTURE ONLY; NOT package assurance' })
        PackageVersion = $version; SupplierCommit = $pin
        ReviewPolicySha256 = $policySha256
        FileCount = $inventory.Count; ReviewedFileCount = @($inventory | Where-Object Reviewed).Count
        SupplierFileCount = @($inventory | Where-Object Origin -EQ 'Supplier').Count
        Summary = [pscustomobject]@{
            CandidateModel = 'FileKindContentV2'
            UnreviewedFileCount = $unreviewedFiles.Count
            CandidateCount = $candidates.Count
            CandidateOccurrenceCount = $candidateOccurrences
            CandidateFileCount = @($candidates | ForEach-Object Path | Sort-Object -Unique).Count
            UnclassifiedCandidateCount = $unclassified.Count
            ByOrigin = @($byOrigin | Where-Object { $null -ne $_ })
            ByKind = @($byCandidateKind | Where-Object { $null -ne $_ })
            NextAction = $(if ($exitCode -eq 1) { 'Remove reporting instructions/collectors; then obtain a fresh human content review.' } elseif ($exitCode -eq 2) { 'Resolve structural issues and obtain human review for every file seal and candidate disposition. Do not auto-approve.' } else { 'Reviewed static coverage only; runtime non-egress is not established.' })
        }
        InventorySha256 = Get-SquadTelemetryInventoryHash -Inventory $inventory.ToArray()
        Inventory = @($inventory | Sort-Object Path); Candidates = @($candidates | Sort-Object Path, Line, Kind)
        Groups = $groupResults.ToArray(); Issues = $issues.ToArray(); Reporting = $reporting.ToArray()
    }
}

#endregion Functions

#region Main Execution

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not $PluginRoot) { throw 'Supply -PluginRoot explicitly. No implicit package install or source-only assurance.' }
        $PluginRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PluginRoot)
        if ($ReviewPolicyPath) {
            $ReviewPolicyPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReviewPolicyPath)
        }
        if ($OutputPath) {
            $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
            $outputRelative = [IO.Path]::GetRelativePath($PluginRoot, $OutputPath)
            if (-not [IO.Path]::IsPathRooted($outputRelative) -and $outputRelative -ne '..' -and $outputRelative -notmatch '^\.\.[\\/]') {
                throw 'OutputPath must be outside PluginRoot.'
            }
        }
        $result = Invoke-SquadTelemetryConformance -PluginRoot $PluginRoot -ReviewPolicyPath $ReviewPolicyPath `
            -ExpectedSupplierCommit $ExpectedSupplierCommit -Mode $Mode
        $json = $result | ConvertTo-Json -Depth 15
        if ($OutputPath) { Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8NoBOM }
        else { $json }
        exit $result.ExitCode
    }
    catch {
        [pscustomobject]@{
            Status = 'Incomplete'; ExitCode = 2; PackageAssurance = $false
            Issues = @($_.Exception.Message)
        } | ConvertTo-Json -Depth 4
        exit 2
    }
}

#endregion Main Execution
