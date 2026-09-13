# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Test-SquadRepoExchange.psm1
# Purpose: Read-only validation of advisory repository exchanges.
#Requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RepositoryRoot = '.copilot-tracking/squad/'
$script:Utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Stop-SquadExchange {
    <# .SYNOPSIS
        Raises a sanitized protocol failure for the public result boundary.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Raises a sanitized validation exception; changes no system state.')]
    [CmdletBinding()]
    param([string]$Code = 'invalid', [string]$Reason = 'invalid-document')
    $Failure = [System.IO.InvalidDataException]::new($Reason)
    $Failure.Data['ExchangeCode'] = $Code
    throw $Failure
}

function Get-SquadByteHash {
    <# .SYNOPSIS
        Hashes exact saved bytes without JSON normalization.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([byte[]]$Bytes)
    [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertFrom-SquadJsonElement {
    <# .SYNOPSIS
        Preserves JSON types while rejecting duplicate and case-colliding keys.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param([System.Text.Json.JsonElement]$Element)
    switch ($Element.ValueKind.ToString()) {
        'Object' {
            $Value = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
            $Names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($Property in $Element.EnumerateObject()) {
                if (-not $Names.Add($Property.Name)) { Stop-SquadExchange -Reason 'duplicate-key' }
                $Value.Add($Property.Name, (ConvertFrom-SquadJsonElement $Property.Value))
            }
            return ,$Value
        }
        'Array' {
            $Items = @(foreach ($Item in $Element.EnumerateArray()) { ConvertFrom-SquadJsonElement $Item })
            return ,$Items
        }
        'String' { return $Element.GetString() }
        'Number' {
            $Integer = 0L
            if ($Element.TryGetInt64([ref]$Integer)) { return $Integer }
            return $Element.GetDouble()
        }
        'True' { return $true }
        'False' { return $false }
        'Null' { return $null }
        default { Stop-SquadExchange }
    }
}

function ConvertFrom-SquadJsonBytes {
    <# .SYNOPSIS
        Parses a bounded UTF-8 object at a maximum JSON depth of eight.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Bytes denotes the exact byte-array input, not multiple documents.')]
    [CmdletBinding()]
    [OutputType([object])]
    param([byte[]]$Bytes)
    if ($Bytes.Length -eq 0 -or $Bytes.Length -gt 131072) { Stop-SquadExchange -Reason 'document-size' }
    $Document = $null
    try {
        $Text = $script:Utf8.GetString($Bytes)
        $Options = [System.Text.Json.JsonDocumentOptions]::new()
        $Options.MaxDepth = 8
        $Document = [System.Text.Json.JsonDocument]::Parse($Text, $Options)
        if ($Document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { Stop-SquadExchange }
        return ,(ConvertFrom-SquadJsonElement $Document.RootElement)
    }
    finally { if ($null -ne $Document) { $Document.Dispose() } }
}

function Assert-SquadRelativePath {
    <# .SYNOPSIS
        Rejects paths with ambiguous, provider, device or traversal semantics.
    #>
    [CmdletBinding()]
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 1024 -or
        [System.IO.Path]::IsPathRooted($Path) -or $Path -match '[\\:\x00-\x1f<>"|?*]') {
        Stop-SquadExchange -Reason 'unsafe-path'
    }
    foreach ($Segment in $Path.Split('/')) {
        if ($Segment -in @('', '.', '..') -or $Segment -match '[. ]$' -or
            $Segment -match '^(?i:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)') {
            Stop-SquadExchange -Reason 'unsafe-path'
        }
    }
}

function Resolve-SquadPath {
    <# .SYNOPSIS
        Resolves a contained path after checking every existing ancestor for links.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$TopLevel, [string]$Path)
    Assert-SquadRelativePath $Path
    $Full = [System.IO.Path]::GetFullPath($Path, $TopLevel)
    $Relative = [System.IO.Path]::GetRelativePath($TopLevel, $Full).Replace('\', '/')
    if ($Relative -cne $Path) { Stop-SquadExchange -Reason 'unsafe-path' }
    $Ancestor = $Full
    while ($Ancestor) {
        try {
            $Attributes = [System.IO.File]::GetAttributes($Ancestor)
            if (($Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Stop-SquadExchange -Reason 'reparse-path'
            }
        }
        catch [System.IO.FileNotFoundException] { $Ancestor = [System.IO.Path]::GetDirectoryName($Ancestor); continue }
        catch [System.IO.DirectoryNotFoundException] { $Ancestor = [System.IO.Path]::GetDirectoryName($Ancestor); continue }
        $Ancestor = [System.IO.Path]::GetDirectoryName($Ancestor)
    }
    return $Full
}

function Read-SquadBytes {
    <# .SYNOPSIS
        Reads a contained file with an optional allocation bound.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Bytes denotes one exact saved byte array.')]
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([string]$TopLevel, [string]$Path, [long]$Limit = 131072)
    $Full = Resolve-SquadPath $TopLevel $Path
    $Stream = [System.IO.File]::Open($Full, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        if ($Stream.Length -gt $Limit) { Stop-SquadExchange -Reason 'document-size' }
        $Bytes = [byte[]]::new([int]$Stream.Length)
        $Stream.ReadExactly($Bytes)
        return ,$Bytes
    }
    finally { $Stream.Dispose() }
}

$script:BindingFields = @('correlationId', 'sourceRepository', 'sourceRevision', 'targetRepository', 'targetRevision', 'taskId')
$script:Shapes = @{
    Packet = 'schemaVersion kind correlationId sourceRepository sourceRevision targetRepository targetRevision taskId createdAt expiresAt request constraints'
    Receipt = 'schemaVersion kind correlationId packetSha256 sourceRepository sourceRevision targetRepository targetRevision taskId reportedAt status outcome resultRevision summary evidence'
    Intake = 'schemaVersion kind correlationId packetSha256 targetRepository targetRevision taskId squadRoot acceptedAt'
    Claim = 'schemaVersion kind correlationId packetSha256 targetRepository targetRevision taskId executionRoot executionKind claimedAt claimAttemptId'
    Audit = 'schemaVersion kind attemptId operation recordedAt squadRoot correlationId taskId registryAlias packetSha256 receiptSha256 sourceRepository targetRepository sourceRevision targetRevision resultRevision disposition reason artifacts stateAdvance'
    Commit = 'schemaVersion kind attemptId operation squadRoot correlationId packetSha256 receiptSha256 auditSha256 stateAdvance committedAt'
}

function Assert-SquadFields {
    <# .SYNOPSIS
        Enforces an ordinal, closed object key set.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Validates the complete closed field set together.')]
    [CmdletBinding()]
    param($Value, [string]$Fields)
    $Keys = $Fields.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    if ($Value -isnot [System.Collections.IDictionary] -or $Value.Count -ne $Keys.Count) { Stop-SquadExchange -Reason 'object-fields' }
    foreach ($Key in $Keys) {
        if (-not $Value.ContainsKey($Key)) { Stop-SquadExchange -Reason 'object-fields' }
    }
}

function Assert-SquadString {
    <# .SYNOPSIS
        Requires a genuine bounded JSON string, optionally allowing an empty value.
    #>
    [CmdletBinding()]
    param($Value, [int]$Limit = 128, [switch]$AllowEmpty)
    if ($Value -isnot [string] -or $Value.Length -gt $Limit -or
        (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) { Stop-SquadExchange -Reason 'string-value' }
}

function Assert-SquadArray {
    <# .SYNOPSIS
        Requires a genuine bounded array.
    #>
    [CmdletBinding()]
    param($Value, [int]$Minimum = 0)
    if ($Value -isnot [object[]] -or $Value.Count -lt $Minimum -or $Value.Count -gt 20) { Stop-SquadExchange -Reason 'array-value' }
}

function ConvertTo-SquadTime {
    <# .SYNOPSIS
        Validates an invariant UTC RFC3339 timestamp.
    #>
    [CmdletBinding()]
    [OutputType([DateTimeOffset])]
    param($Value)
    Assert-SquadString $Value
    $Parsed = [DateTimeOffset]::MinValue
    if ($Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$' -or
        -not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
        Stop-SquadExchange -Reason 'timestamp'
    }
    return $Parsed
}

function Assert-SquadIdentity {
    <# .SYNOPSIS
        Requires the canonical GitHub HTTPS repository identity.
    #>
    [CmdletBinding()]
    param($Value)
    Assert-SquadString $Value -Limit 160
    if ($Value -cnotmatch '^https://github\.com/(?<owner>[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?)/(?<repo>[a-z0-9_.-]{1,100})$') {
        Stop-SquadExchange -Reason 'repository-identity'
    }
    if ($Matches.owner.Contains('--') -or $Matches.repo -match '^\.+$' -or $Matches.repo.EndsWith('.git', [StringComparison]::Ordinal)) {
        Stop-SquadExchange -Reason 'repository-identity'
    }
}

function Assert-SquadStateAdvance {
    <# .SYNOPSIS
        Checks the closed evidence of one ordinary state turn.
    #>
    [CmdletBinding()]
    param($Value)
    Assert-SquadFields $Value 'fromTurn toTurn updated stateSha256'
    foreach ($Key in @('fromTurn', 'toTurn')) {
        if ($Value[$Key] -isnot [long] -or $Value[$Key] -lt 0 -or $Value[$Key] -ge [long]::MaxValue) { Stop-SquadExchange -Reason 'state-turn' }
    }
    if ($Value.toTurn -ne ($Value.fromTurn + 1)) { Stop-SquadExchange -Reason 'state-turn' }
    $null = ConvertTo-SquadTime $Value.updated
    Assert-SquadString $Value.stateSha256
    if ($Value.stateSha256 -cnotmatch '^[a-f0-9]{64}$') { Stop-SquadExchange -Reason 'digest' }
}

function Assert-SquadShape {
    <# .SYNOPSIS
        Checks the six closed exchange record shapes and all nested values.
    #>
    [CmdletBinding()]
    param($Value, [string]$Type)
    Assert-SquadFields $Value $script:Shapes[$Type]
    $Kind = @{ Packet = 'task'; Receipt = 'receipt'; Intake = 'intake'; Claim = 'claim'; Audit = 'audit'; Commit = 'commit' }[$Type]
    if ($Value.schemaVersion -isnot [string] -or $Value.schemaVersion -cne '1.0' -or $Value.kind -cne "squad-repo-$Kind") { Stop-SquadExchange -Reason 'schema-version-kind' }
    foreach ($Key in $Value.Keys) {
        if ($Key -in @('request', 'constraints', 'evidence', 'artifacts', 'stateAdvance')) { continue }
        $EmptyAllowed = ($Type -in @('Audit', 'Commit')) -and $Key -in @('correlationId', 'taskId', 'registryAlias', 'packetSha256', 'receiptSha256', 'sourceRepository', 'targetRepository', 'sourceRevision', 'targetRevision', 'resultRevision', 'reason')
        $Limit = if ($Key -eq 'summary') { 4000 } elseif ($Key -in @('squadRoot', 'executionRoot')) { 1024 } elseif ($Key.EndsWith('Repository')) { 160 } else { 128 }
        Assert-SquadString $Value[$Key] -Limit $Limit -AllowEmpty:$EmptyAllowed
        if ($EmptyAllowed -and $Value[$Key] -ceq '') { continue }
        switch -Regex ($Key) {
            '^(correlationId|attemptId|claimAttemptId)$' {
                if ($Value[$Key] -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') { Stop-SquadExchange -Reason 'identifier' }
            }
            'Sha256$' { if ($Value[$Key] -cnotmatch '^[a-f0-9]{64}$') { Stop-SquadExchange -Reason 'digest' } }
            'Revision$' { if ($Value[$Key] -cnotmatch '^[a-f0-9]{40}$') { Stop-SquadExchange -Reason 'revision' } }
            'Repository$' { Assert-SquadIdentity $Value[$Key] }
            'At$' { $null = ConvertTo-SquadTime $Value[$Key] }
            '^taskId$' { if ($Value[$Key] -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$') { Stop-SquadExchange -Reason 'task-id' } }
            '^(squadRoot|executionRoot)$' {
                if ($Value[$Key] -cnotmatch '^\.copilot-tracking/squad/(?:members/[a-z0-9][a-z0-9-]{0,63}/)?$') { Stop-SquadExchange -Reason 'execution-root' }
            }
        }
    }
    switch ($Type) {
        'Packet' {
            if ($Value.sourceRepository -ceq $Value.targetRepository) { Stop-SquadExchange -Reason 'same-repository' }
            Assert-SquadFields $Value.request 'summary acceptanceCriteria inputs'
            Assert-SquadString $Value.request.summary -Limit 4000
            Assert-SquadArray $Value.request.acceptanceCriteria -Minimum 1
            foreach ($Criterion in $Value.request.acceptanceCriteria) { Assert-SquadString $Criterion -Limit 2000 }
            Assert-SquadArray $Value.request.inputs
            foreach ($InputValue in $Value.request.inputs) {
                Assert-SquadFields $InputValue 'label content'
                Assert-SquadString $InputValue.label
                Assert-SquadString $InputValue.content -Limit 16000
            }
            Assert-SquadFields $Value.constraints 'execution transport authority'
            foreach ($Key in @('execution', 'transport', 'authority')) { Assert-SquadString $Value.constraints[$Key] }
            if ($Value.constraints.execution -cne 'advisory-only' -or $Value.constraints.transport -cne 'user' -or $Value.constraints.authority -cne 'target-local') { Stop-SquadExchange -Reason 'constraints' }
            $Created = ConvertTo-SquadTime $Value.createdAt
            $Expires = ConvertTo-SquadTime $Value.expiresAt
            if ($Expires -le $Created -or $Expires -gt $Created.AddDays(7)) { Stop-SquadExchange -Reason 'ttl' }
        }
        'Receipt' {
            if ($Value.status -cne 'reported' -or $Value.outcome -cnotin @('completed', 'blocked', 'declined')) { Stop-SquadExchange -Reason 'receipt-status' }
            Assert-SquadArray $Value.evidence
        }
        'Claim' { if ($Value.executionKind -cnotin @('single', 'member')) { Stop-SquadExchange -Reason 'execution-kind' } }
        'Audit' {
            if ($Value.disposition -cnotin @('pending', 'accepted', 'reported', 'rejected', 'human-verified')) { Stop-SquadExchange -Reason 'disposition' }
            Assert-SquadArray $Value.artifacts
            Assert-SquadStateAdvance $Value.stateAdvance
        }
        'Commit' { Assert-SquadStateAdvance $Value.stateAdvance }
    }
    if ($Type -in @('Audit', 'Commit') -and $Value.operation -cnotin @('Register', 'Issue', 'Claim', 'Accept', 'Report', 'Import', 'Verify')) { Stop-SquadExchange -Reason 'operation' }
    if ($Type -in @('Receipt', 'Audit')) {
        $Refs = if ($Type -eq 'Receipt') { $Value.evidence } else { $Value.artifacts }
        $Paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($Ref in $Refs) {
            Assert-SquadFields $Ref 'path sha256'
            Assert-SquadString $Ref.path -Limit 1024
            Assert-SquadRelativePath $Ref.path
            Assert-SquadString $Ref.sha256
            if ($Ref.sha256 -cnotmatch '^[a-f0-9]{64}$' -or -not $Paths.Add($Ref.path)) { Stop-SquadExchange -Reason 'artifact-reference' }
        }
        if ($Type -eq 'Receipt' -and $Value.outcome -ceq 'completed') {
            $HistoryRefs = @($Refs | Where-Object { $_.path -cmatch '^\.copilot-tracking/squad/(?:members/[a-z0-9][a-z0-9-]{0,63}/)?history/Squad Scribe\.md$' })
            $ArtifactRefs = @($Refs | Where-Object {
                    $_.path -cnotmatch '^\.copilot-tracking/squad/(?:members/[a-z0-9][a-z0-9-]{0,63}/)?(?:history/|exchanges/|state\.json$|decisions\.md$|federation\.md$|consumption\.md$|team\.md$|routing\.md$|notifications\.md$|meta-routing\.md$|consumption-rates\.md$)'
                })
            if ($HistoryRefs.Count -ne 1 -or $ArtifactRefs.Count -eq 0) { Stop-SquadExchange -Reason 'completion-evidence' }
        }
    }
}

function Read-SquadDocument {
    <# .SYNOPSIS
        Reads, hashes and validates one contained exchange record.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string]$TopLevel, [string]$Path, [string]$Type)
    $Bytes = Read-SquadBytes $TopLevel $Path
    $Value = ConvertFrom-SquadJsonBytes $Bytes
    Assert-SquadShape $Value $Type
    [pscustomobject]@{ Value = $Value; Hash = Get-SquadByteHash $Bytes; Path = $Path }
}

function Get-SquadFileDigest {
    <# .SYNOPSIS
        Streams a contained evidence file without executing or interpreting it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$TopLevel, [string]$Path)
    $Full = Resolve-SquadPath $TopLevel $Path
    $Stream = [IO.File]::Open($Full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Stream)).ToLowerInvariant() }
    finally { $Stream.Dispose() }
}

function Invoke-SquadGitProcess {
    <# .SYNOPSIS
        Executes only the already constructed read-only Git child.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    $Process = [Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo
    try {
        $null = $Process.Start()
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        if (-not $Process.WaitForExit(10000)) {
            $Process.Kill($true)
            Stop-SquadExchange -Code 'wrong-context' -Reason 'offline-git-unavailable'
        }
        $null = $ErrorTask.GetAwaiter().GetResult()
        return [pscustomobject]@{ ExitCode = $Process.ExitCode; Output = $OutputTask.GetAwaiter().GetResult() }
    }
    finally { $Process.Dispose() }
}

function Invoke-SquadGit {
    <# .SYNOPSIS
        Constructs every Git command with child-only offline isolation.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([ValidateSet('Version', 'Root', 'Origin', 'Head', 'Commit')][string]$Command, [string]$Revision)
    $Arguments = switch ($Command) {
        'Version' { @('--version') }
        'Root' { @('rev-parse', '--show-toplevel') }
        'Origin' { @('config', '--local', '--get-all', 'remote.origin.url') }
        'Head' { @('rev-parse', '--verify', 'HEAD') }
        'Commit' {
            if ($Revision -cnotmatch '^[a-f0-9]{40}$') { Stop-SquadExchange -Reason 'revision' }
            @('cat-file', '-e', ($Revision + '^{commit}'))
        }
    }
    $StartInfo = [Diagnostics.ProcessStartInfo]::new('git')
    $StartInfo.UseShellExecute = $false
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $StartInfo.CreateNoWindow = $true
    $StartInfo.WorkingDirectory = (Get-Location).ProviderPath
    foreach ($Argument in (@('--no-lazy-fetch', '-c', 'credential.helper=', '-c', 'core.askPass=') + $Arguments)) {
        $StartInfo.ArgumentList.Add($Argument)
    }
    foreach ($Key in @($StartInfo.Environment.Keys)) {
        if ($Key -match '^GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE|OBJECT_DIRECTORY|ALTERNATE_OBJECT_DIRECTORIES|CONFIG_PARAMETERS|CONFIG_COUNT|CONFIG_KEY_\d+|CONFIG_VALUE_\d+)$') {
            $null = $StartInfo.Environment.Remove($Key)
        }
    }
    foreach ($Entry in @{ GIT_NO_LAZY_FETCH = '1'; GIT_TERMINAL_PROMPT = '0'; GIT_ASKPASS = ''; SSH_ASKPASS = ''; GIT_ALLOW_PROTOCOL = ''; GIT_OPTIONAL_LOCKS = '0' }.GetEnumerator()) {
        $StartInfo.Environment[$Entry.Key] = $Entry.Value
    }
    try {
        $Result = Invoke-SquadGitProcess $StartInfo
        if ($Result.ExitCode -ne 0) { throw 'git-failed' }
        return $Result.Output
    }
    catch { Stop-SquadExchange -Code 'wrong-context' -Reason 'offline-git-unavailable' }
}

function Get-SquadLocalContext {
    <# .SYNOPSIS
        Observes repository root, unique origin and HEAD independently of JSON.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    try {
        $null = Invoke-SquadGit Version
        $TopLevel = (Invoke-SquadGit Root).TrimEnd("`r", "`n")
        $Location = Get-Location
        if ($Location.Provider.Name -ne 'FileSystem' -or $TopLevel.Contains("`n")) { throw 'context' }
        $TopLevel = [IO.Path]::GetFullPath($TopLevel)
        $Comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        if (-not [string]::Equals($TopLevel, [IO.Path]::GetFullPath($Location.ProviderPath), $Comparison)) { throw 'context' }
        $Origins = @((Invoke-SquadGit Origin).TrimEnd("`r", "`n") -split '\r?\n')
        if ($Origins.Count -ne 1) { throw 'origin' }
        $Identity = $Origins[0].ToLowerInvariant()
        if ($Identity.EndsWith('.git', [StringComparison]::Ordinal)) { $Identity = $Identity.Substring(0, $Identity.Length - 4) }
        elseif ($Identity.EndsWith('/', [StringComparison]::Ordinal)) { $Identity = $Identity.Substring(0, $Identity.Length - 1) }
        Assert-SquadIdentity $Identity
        $Head = (Invoke-SquadGit Head).TrimEnd("`r", "`n")
        if ($Head -cnotmatch '^[a-f0-9]{40}$') { throw 'head' }
        return [pscustomobject]@{ TopLevel = $TopLevel; Repository = $Identity; Head = $Head }
    }
    catch { Stop-SquadExchange -Code 'wrong-context' -Reason 'offline-git-unavailable' }
}

function Get-SquadClock {
    <# .SYNOPSIS
        Supplies the private clock used by deterministic fixtures.
    #>
    [CmdletBinding()]
    [OutputType([DateTimeOffset])]
    param()
    [DateTimeOffset]::UtcNow
}

function Test-SquadPathExists {
    <# .SYNOPSIS
        Distinguishes absence from unsafe or unreadable local paths.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Exists is a predicate on one path, not a plural noun.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$TopLevel, [string]$Path)
    $Full = Resolve-SquadPath $TopLevel $Path
    try { $null = [IO.File]::GetAttributes($Full); return $true }
    catch [IO.FileNotFoundException] { return $false }
    catch [IO.DirectoryNotFoundException] { return $false }
}

function Get-SquadExecutionKind {
    <# .SYNOPSIS
        Checks a selected or claimed execution root against the local registry.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$TopLevel, [string]$Root, [switch]$Bookkeeping)
    if ($Root -cnotmatch '^\.copilot-tracking/squad/(?:members/(?<member>[a-z0-9][a-z0-9-]{0,63})/)?$') {
        Stop-SquadExchange -Code 'wrong-context' -Reason 'execution-root'
    }
    $Member = $Matches['member']
    $null = Resolve-SquadPath $TopLevel $Root.TrimEnd('/')
    $RegistryPath = $script:RepositoryRoot + 'federation.md'
    $Federated = Test-SquadPathExists $TopLevel $RegistryPath
    if (-not $Federated) {
        if ($Member) { Stop-SquadExchange -Code 'wrong-context' -Reason 'root-relocated' }
        return 'single'
    }
    if (-not $Member -and $Bookkeeping) { return 'federation' }
    if (-not $Member) { Stop-SquadExchange -Code 'wrong-context' -Reason 'root-relocated' }
    $Registry = $script:Utf8.GetString((Read-SquadBytes $TopLevel $RegistryPath))
    $Names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $Repositories = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $Found = $false
    $Header = $false
    foreach ($Line in ($Registry -split '\r?\n')) {
        if ($Line -notmatch '^\s*\|') { continue }
        $Cells = @($Line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if (($Cells -join '|') -ceq 'Sub-squad|Profile|Kind|Location|Owner|Description') { $Header = $true; continue }
        if ($Line -match '^\s*\|[\s|:-]+\|\s*$') { continue }
        if (-not $Header -or $Cells.Count -ne 6 -or $Cells[0] -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$' -or -not $Names.Add($Cells[0])) {
            Stop-SquadExchange -Code 'wrong-context' -Reason 'registry-shape'
        }
        if ($Cells[2] -ceq 'repo') {
            Assert-SquadIdentity $Cells[3]
            if ($Cells[1] -cne 'advisory' -or -not $Repositories.Add($Cells[3])) { Stop-SquadExchange -Code 'wrong-context' -Reason 'registry-shape' }
        }
        elseif ($Cells[2] -ceq 'in-repo') {
            if ($Cells[3] -cne "members/$($Cells[0])/") { Stop-SquadExchange -Code 'wrong-context' -Reason 'registry-shape' }
            if ($Cells[0] -ceq $Member) { $Found = $true }
        }
        else { Stop-SquadExchange -Code 'wrong-context' -Reason 'registry-kind' }
    }
    if (-not $Found -or -not (Test-SquadPathExists $TopLevel ($Root + 'state.json')) -or (Test-SquadPathExists $TopLevel ($Root + 'federation.md'))) {
        Stop-SquadExchange -Code 'wrong-context' -Reason 'root-relocated'
    }
    return 'member'
}

function Read-SquadAuditLine {
    <# .SYNOPSIS
        Reads one bounded line without allocating an unbounded audit record.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([IO.StreamReader]$Reader)
    $Line = [Text.StringBuilder]::new()
    while (($Character = $Reader.Read()) -ne -1) {
        if ($Character -eq 10) { return $Line.ToString().TrimEnd("`r") }
        if ($Line.Length -ge 131072) { Stop-SquadExchange -Code 'incomplete' -Reason 'audit-line-size' }
        $null = $Line.Append([char]$Character)
    }
    if ($Line.Length -gt 0) { return $Line.ToString() }
    return $null
}

function Read-SquadAuditFile {
    <# .SYNOPSIS
        Reads complete unique machine blocks without treating prose as evidence.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param([string]$TopLevel, [string]$Path)
    $Records = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    if (-not (Test-SquadPathExists $TopLevel $Path)) { return ,$Records }
    $Full = Resolve-SquadPath $TopLevel $Path
    $Stream = [IO.File]::Open($Full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $Reader = [IO.StreamReader]::new($Stream, $script:Utf8, $false)
    try {
        while ($null -ne ($Line = Read-SquadAuditLine $Reader)) {
            if (-not $Line.Contains('<!-- squad-repo-audit:')) { continue }
            if ($Line -cnotmatch '^<!-- squad-repo-audit:([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}):begin -->$') { Stop-SquadExchange -Code 'incomplete' -Reason 'audit-marker' }
            $Attempt = $Matches[1]
            $JsonLine = Read-SquadAuditLine $Reader
            if ($null -eq $JsonLine -or $JsonLine.Length -gt 131072) { Stop-SquadExchange -Code 'incomplete' -Reason 'audit-record' }
            $End = Read-SquadAuditLine $Reader
            if ($End -cne "<!-- squad-repo-audit:${Attempt}:end -->" -or $Records.ContainsKey($Attempt)) { Stop-SquadExchange -Code 'incomplete' -Reason 'audit-marker' }
            $Bytes = $script:Utf8.GetBytes($JsonLine)
            $Value = ConvertFrom-SquadJsonBytes $Bytes
            Assert-SquadShape $Value Audit
            if ($Value.attemptId -cne $Attempt) { Stop-SquadExchange -Code 'incomplete' -Reason 'audit-attempt' }
            $Records.Add($Attempt, [pscustomobject]@{ Value = $Value; Hash = Get-SquadByteHash $Bytes })
        }
        return ,$Records
    }
    finally { $Reader.Dispose() }
}

function Get-SquadAudits {
    <# .SYNOPSIS
        Requires identical audit sets in the two fixed append-only files.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Returns the paired complete audit set for a single root.')]
    [CmdletBinding()]
    [OutputType([object])]
    param($Session, [string]$Root)
    if (-not $Session.Audits.ContainsKey($Root)) {
        try {
            $Decisions = Read-SquadAuditFile $Session.Context.TopLevel ($Root + 'decisions.md')
            $History = Read-SquadAuditFile $Session.Context.TopLevel ($Root + 'history/repo-exchange/audit.md')
            if ($Decisions.Count -ne $History.Count) { throw 'audit-pair' }
            foreach ($Attempt in $Decisions.Keys) {
                if (-not $History.ContainsKey($Attempt) -or $Decisions[$Attempt].Hash -cne $History[$Attempt].Hash -or $Decisions[$Attempt].Value.squadRoot -cne $Root) { throw 'audit-pair' }
            }
            $Session.Audits[$Root] = $Decisions
        }
        catch { Stop-SquadExchange -Code 'incomplete' -Reason 'audit-incomplete' }
    }
    return ,$Session.Audits[$Root]
}

function Assert-SquadCurrentState {
    <# .SYNOPSIS
        Checks existing state structure and the sealed state advancement.
    #>
    [CmdletBinding()]
    param($Session, [string]$Root, $Advance)
    $Bytes = Read-SquadBytes $Session.Context.TopLevel ($Root + 'state.json')
    $State = ConvertFrom-SquadJsonBytes $Bytes
    $Federated = Test-SquadPathExists $Session.Context.TopLevel ($Root + 'federation.md')
    if ($Federated) {
        $Fields = 'schemaVersion updated turn mode subSquads activeSubSquads openEscalations currentRun'
        if ($State.ContainsKey('notify')) { $Fields += ' notify' }
        Assert-SquadFields $State $Fields
        if ($State.schemaVersion -cne '1.2' -or $State.mode -cnotin @('interactive', 'autopilot')) { Stop-SquadExchange -Reason 'state-schema' }
        foreach ($Key in @('subSquads', 'activeSubSquads')) {
            if ($State[$Key] -isnot [object[]]) { Stop-SquadExchange -Reason 'state-schema' }
            foreach ($Name in $State[$Key]) { Assert-SquadString $Name }
        }
    }
    else {
        $Fields = 'schemaVersion updated turn mode activeRoles openEscalations currentRun notify'
        if ($State.ContainsKey('trigger')) {
            $Fields += ' trigger'
            Assert-SquadFields $State.trigger 'source ref eventId actor receivedAt runId'
            if ($State.trigger.source -cnotin @('issue', 'pull_request', 'issue_comment', 'schedule', 'workflow_dispatch', 'push')) { Stop-SquadExchange -Reason 'state-trigger' }
            foreach ($Key in @('ref', 'eventId', 'actor', 'runId')) { Assert-SquadString $State.trigger[$Key] -Limit 1024 }
            $null = ConvertTo-SquadTime $State.trigger.receivedAt
        }
        Assert-SquadFields $State $Fields
        if ($State.schemaVersion -cne '1.3' -or $State.mode -cnotin @('interactive', 'autonomous', 'autopilot') -or $State.activeRoles -isnot [object[]]) { Stop-SquadExchange -Reason 'state-schema' }
        foreach ($Name in $State.activeRoles) { Assert-SquadString $Name }
    }
    if ($State.ContainsKey('notify')) {
        Assert-SquadFields $State.notify 'approvalChannel enabled email github'
        Assert-SquadString $State.notify.approvalChannel
        if ($State.notify.approvalChannel -cnotin @('in-chat', 'github-issue', 'webhook') -or $State.notify.enabled -isnot [bool]) { Stop-SquadExchange -Reason 'state-schema' }
        Assert-SquadString $State.notify.email -Limit 1024 -AllowEmpty
        Assert-SquadFields $State.notify.github 'handle repo'
        foreach ($Key in @('handle', 'repo')) { Assert-SquadString $State.notify.github[$Key] -Limit 1024 -AllowEmpty }
    }
    if ($State.openEscalations -isnot [object[]] -or $State.turn -isnot [long] -or $State.turn -lt $Advance.toTurn) { Stop-SquadExchange -Reason 'state-turn' }
    Assert-SquadFields $State.currentRun 'sessionModel modelOverrides estCostUsd estCreditsTotal'
    Assert-SquadString $State.currentRun.sessionModel -AllowEmpty
    if ($State.currentRun.modelOverrides -isnot [Collections.IDictionary]) { Stop-SquadExchange -Reason 'state-schema' }
    foreach ($Name in $State.currentRun.modelOverrides.Keys) { Assert-SquadString $State.currentRun.modelOverrides[$Name] }
    foreach ($Key in @('estCostUsd', 'estCreditsTotal')) {
        $Number = $State.currentRun[$Key]
        if (($Number -isnot [long] -and $Number -isnot [double]) -or -not [double]::IsFinite($Number) -or $Number -lt 0) { Stop-SquadExchange -Reason 'state-schema' }
    }
    $Updated = ConvertTo-SquadTime $State.updated
    if ($Updated -lt (ConvertTo-SquadTime $Advance.updated) -or $Updated -gt $Session.Now.AddMinutes(5)) { Stop-SquadExchange -Reason 'state-time' }
    if ($State.turn -eq $Advance.toTurn -and ((Get-SquadByteHash $Bytes) -cne $Advance.stateSha256 -or $State.updated -cne $Advance.updated)) { Stop-SquadExchange -Reason 'state-hash' }
}

function Assert-SquadBinding {
    <# .SYNOPSIS
        Compares every applicable packet field with ordinal exact values.
    #>
    [CmdletBinding()]
    param($Value, $Packet, [string[]]$Fields = $script:BindingFields)
    foreach ($Key in $Fields) {
        if ($Value[$Key] -cne $Packet.Value[$Key]) { Stop-SquadExchange -Reason 'packet-binding' }
    }
    if ($Value.ContainsKey('packetSha256') -and $Value.packetSha256 -cne $Packet.Hash) { Stop-SquadExchange -Code 'conflict' -Reason 'packet-digest' }
}

function Assert-SquadRecordTime {
    <# .SYNOPSIS
        Checks an operation timestamp against the packet lifetime and local clock.
    #>
    [CmdletBinding()]
    param($Session, $Packet, [string]$Timestamp)
    $Time = ConvertTo-SquadTime $Timestamp
    if ($Time -lt (ConvertTo-SquadTime $Packet.Value.createdAt) -or $Time -ge (ConvertTo-SquadTime $Packet.Value.expiresAt) -or $Time -gt $Session.Now.AddMinutes(5)) {
        Stop-SquadExchange -Reason 'operation-time'
    }
}

function Assert-SquadCommittedOperation {
    <# .SYNOPSIS
        Checks immutable artifacts, paired audit, state read-back evidence and seal.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param($Session, [string]$Operation, [string]$Root, $Packet, [object[]]$Artifacts, $Receipt = $null, $Predecessor = $null)
    try {
        $Records = Get-SquadAudits $Session $Root
        $Candidates = @($Records.Values | Where-Object { $_.Value.correlationId -ceq $Packet.Value.correlationId -and $_.Value.operation -ceq $Operation })
        if ($Candidates.Count -ne 1) { throw 'audit-count' }
        $Record = $Candidates[0]
        $Audit = $Record.Value
        Assert-SquadBinding $Audit $Packet
        if ($Audit.packetSha256 -cne $Packet.Hash) { throw 'packet-hash' }
        $ReceiptHash = if ($null -ne $Receipt) { $Receipt.Hash } else { '' }
        $ResultRevision = if ($null -ne $Receipt) { $Receipt.Value.resultRevision } else { '' }
        $Disposition = @{ Issue = 'pending'; Claim = 'pending'; Accept = 'accepted'; Report = 'reported'; Import = 'reported' }[$Operation]
        if ($Audit.receiptSha256 -cne $ReceiptHash -or $Audit.resultRevision -cne $ResultRevision -or $Audit.disposition -cne $Disposition) { throw 'audit-binding' }
        if ($Operation -in @('Issue', 'Import') -and [string]::IsNullOrWhiteSpace($Audit.registryAlias)) { throw 'registry-alias' }
        Assert-SquadRecordTime $Session $Packet $Audit.recordedAt
        if ($null -ne $Predecessor) {
            if ((ConvertTo-SquadTime $Audit.recordedAt) -lt (ConvertTo-SquadTime $Predecessor.committedAt)) { throw 'predecessor-time' }
            if ($Predecessor.squadRoot -ceq $Root -and $Audit.stateAdvance.fromTurn -lt $Predecessor.stateAdvance.toTurn) { throw 'predecessor-turn' }
        }
        if ($Audit.artifacts.Count -ne $Artifacts.Count) { throw 'artifact-count' }
        foreach ($Artifact in $Artifacts) {
            $ArtifactMatches = @($Audit.artifacts | Where-Object { $_.path -ceq $Artifact.Path -and $_.sha256 -ceq $Artifact.Hash })
            if ($ArtifactMatches.Count -ne 1 -or (Get-SquadFileDigest $Session.Context.TopLevel $Artifact.Path) -cne $Artifact.Hash) { throw 'artifact-hash' }
        }
        $Seal = (Read-SquadDocument $Session.Context.TopLevel ($Root + "exchanges/operations/$($Audit.attemptId)/commit.json") Commit).Value
        foreach ($Key in @('attemptId', 'operation', 'squadRoot', 'correlationId', 'packetSha256', 'receiptSha256')) {
            if ($Seal[$Key] -cne $Audit[$Key]) { throw 'seal-binding' }
        }
        if ($Seal.auditSha256 -cne $Record.Hash) { throw 'audit-hash' }
        foreach ($Key in @('fromTurn', 'toTurn', 'updated', 'stateSha256')) {
            if ($Seal.stateAdvance[$Key] -cne $Audit.stateAdvance[$Key]) { throw 'seal-state' }
        }
        if ((ConvertTo-SquadTime $Seal.committedAt) -lt (ConvertTo-SquadTime $Audit.recordedAt) -or
            (ConvertTo-SquadTime $Seal.committedAt) -gt $Session.Now.AddMinutes(5) -or
            (ConvertTo-SquadTime $Audit.stateAdvance.updated) -lt (ConvertTo-SquadTime $Audit.recordedAt) -or
            (ConvertTo-SquadTime $Audit.stateAdvance.updated) -gt (ConvertTo-SquadTime $Seal.committedAt)) { throw 'seal-time' }
        Assert-SquadCurrentState $Session $Root $Seal.stateAdvance
        return $Seal
    }
    catch { Stop-SquadExchange -Code 'incomplete' -Reason 'operation-incomplete' }
}

function Assert-SquadAcceptance {
    <# .SYNOPSIS
        Resolves the one repository claim and its committed pinned acceptance.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param($Session, $Packet)
    $TopLevel = $Session.Context.TopLevel
    $ClaimPath = $script:RepositoryRoot + "exchanges/claims/$($Packet.Value.correlationId)/claim.json"
    try { $Claim = Read-SquadDocument $TopLevel $ClaimPath Claim }
    catch { Stop-SquadExchange -Code 'incomplete' -Reason 'claim-incomplete' }
    if ($Claim.Value.packetSha256 -cne $Packet.Hash) { Stop-SquadExchange -Code 'conflict' -Reason 'claim-conflict' }
    $Kind = Get-SquadExecutionKind $TopLevel $Claim.Value.executionRoot
    if ($Kind -cne $Claim.Value.executionKind) { Stop-SquadExchange -Code 'wrong-context' -Reason 'root-relocated' }
    try {
        Assert-SquadBinding $Claim.Value $Packet @('correlationId', 'targetRepository', 'targetRevision', 'taskId')
        Assert-SquadRecordTime $Session $Packet $Claim.Value.claimedAt
        $ClaimSeal = Assert-SquadCommittedOperation $Session Claim $script:RepositoryRoot $Packet @($Claim)
        if ($ClaimSeal.attemptId -cne $Claim.Value.claimAttemptId -or (ConvertTo-SquadTime $ClaimSeal.committedAt) -lt (ConvertTo-SquadTime $Claim.Value.claimedAt)) { throw 'claim-attempt' }
        $Root = $Claim.Value.executionRoot
        $Inbox = $Root + "exchanges/inbox/$($Packet.Value.correlationId)/"
        $Saved = Read-SquadDocument $TopLevel ($Inbox + 'packet.json') Packet
        if ($Saved.Hash -cne $Packet.Hash) { throw 'saved-packet' }
        $Intake = Read-SquadDocument $TopLevel ($Inbox + 'intake.json') Intake
        Assert-SquadBinding $Intake.Value $Packet @('correlationId', 'targetRepository', 'targetRevision', 'taskId')
        Assert-SquadRecordTime $Session $Packet $Intake.Value.acceptedAt
        if ($Intake.Value.squadRoot -cne $Root -or (ConvertTo-SquadTime $Intake.Value.acceptedAt) -lt (ConvertTo-SquadTime $ClaimSeal.committedAt)) { throw 'intake-root' }
        $AcceptSeal = Assert-SquadCommittedOperation $Session Accept $Root $Packet @($Saved, $Intake, $Claim) -Predecessor $ClaimSeal
        if ((ConvertTo-SquadTime $AcceptSeal.committedAt) -lt (ConvertTo-SquadTime $Intake.Value.acceptedAt)) { throw 'intake-time' }
        return [pscustomobject]@{ Root = $Root; Packet = $Saved; Intake = $Intake; Claim = $Claim; Seal = $AcceptSeal }
    }
    catch { Stop-SquadExchange -Code 'incomplete' -Reason 'acceptance-incomplete' }
}

function Assert-SquadFresh {
    <# .SYNOPSIS
        Enforces expiry only for new operations, never reviving historical work.
    #>
    [CmdletBinding()]
    param($Session, $Packet)
    if ($Session.Now -ge (ConvertTo-SquadTime $Packet.Value.expiresAt)) { Stop-SquadExchange -Code 'stale' -Reason 'expired' }
}

function Assert-SquadCandidatePath {
    <# .SYNOPSIS
        Allows only a Scribe-generated staging attempt at the owning root.
    #>
    [CmdletBinding()]
    param([string]$Path, [string]$Root, [string]$Leaf)
    $Pattern = '^' + [regex]::Escape($Root) + 'exchanges/staging/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/' + [regex]::Escape($Leaf) + '$'
    if ($Path -cnotmatch $Pattern) { Stop-SquadExchange -Reason 'candidate-path' }
}

function Assert-SquadNoAudit {
    <# .SYNOPSIS
        Rejects orphaned provenance instead of repairing a previous attempt.
    #>
    [CmdletBinding()]
    param($Session, [string]$Root, $Packet, [string]$Operation = '')
    $Records = Get-SquadAudits $Session $Root
    foreach ($Record in $Records.Values) {
        if ($Record.Value.correlationId -ceq $Packet.Value.correlationId -and (-not $Operation -or $Record.Value.operation -ceq $Operation)) { Stop-SquadExchange -Code 'incomplete' -Reason 'orphaned-audit' }
    }
}

function Test-SquadRepoExchange {
    <#
    .SYNOPSIS
        Validates an advisory repository exchange without persisting or executing it.
    .DESCRIPTION
        Observes local Git context and checks strict JSON, byte binding and committed
        predecessors. A valid candidate grants neither a reservation nor approval.
    .PARAMETER Operation
        Issue, Accept, Report or Import. Historical no-ops never authorize dispatch.
    .PARAMETER PacketPath
        Explicit repository-relative packet path; Issue requires a staged candidate.
    .PARAMETER ReceiptPath
        Required for Report and Import. Report requires a staged or committed receipt.
    .PARAMETER SquadRoot
        Local root or explicitly selected registered member, never a transported root.
    .EXAMPLE
        Test-SquadRepoExchange -Operation Accept -PacketPath .copilot-tracking/squad/transfers/task.json
    .NOTES
        Requires PowerShell 7.4+ and Git supporting --no-lazy-fetch. Writes are Scribe-owned.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$PacketPath,
        [string]$ReceiptPath = '',
        [string]$SquadRoot = '.copilot-tracking/squad/'
    )
    $Result = [pscustomobject]@{ Valid = $false; Code = 'invalid'; Errors = @(); CorrelationId = $null; PacketSha256 = $null; ExecutionRoot = $null }
    try {
        if ($Operation -cnotin @('Issue', 'Accept', 'Report', 'Import') -or
            ($Operation -in @('Report', 'Import') -and -not $ReceiptPath) -or
            ($Operation -in @('Issue', 'Accept') -and $ReceiptPath)) { Stop-SquadExchange -Reason 'operation-arguments' }
        $Context = Get-SquadLocalContext
        $Session = @{ Context = $Context; Now = Get-SquadClock; Audits = @{} }
        $TopLevel = $Context.TopLevel
        if (-not $SquadRoot.EndsWith('/')) { $SquadRoot += '/' }
        $null = Get-SquadExecutionKind $TopLevel $SquadRoot -Bookkeeping:($Operation -in @('Issue', 'Import'))
        $Packet = Read-SquadDocument $TopLevel $PacketPath Packet
        $Result.CorrelationId = $Packet.Value.correlationId
        $Result.PacketSha256 = $Packet.Hash
        if ((ConvertTo-SquadTime $Packet.Value.createdAt) -gt $Session.Now.AddMinutes(5)) { Stop-SquadExchange -Reason 'future-packet' }
        $ExpectedRepository = if ($Operation -in @('Issue', 'Import')) { $Packet.Value.sourceRepository } else { $Packet.Value.targetRepository }
        if ($Context.Repository -cne $ExpectedRepository) { Stop-SquadExchange -Code 'wrong-context' -Reason 'repository-mismatch' }
        $Correlation = $Packet.Value.correlationId
        $Outbox = $SquadRoot + "exchanges/outbox/$Correlation/"
        $Inbox = $SquadRoot + "exchanges/inbox/$Correlation/"
        if ($Operation -eq 'Issue') {
            Assert-SquadCandidatePath $PacketPath $SquadRoot 'packet.json'
            if ($Context.Head -cne $Packet.Value.sourceRevision) { Stop-SquadExchange -Code 'wrong-context' -Reason 'revision-mismatch' }
            if (Test-SquadPathExists $TopLevel $Outbox.TrimEnd('/')) { Stop-SquadExchange -Code 'conflict' -Reason 'outbox-collision' }
            Assert-SquadNoAudit $Session $SquadRoot $Packet
            Assert-SquadFresh $Session $Packet
        }
        elseif ($Operation -eq 'Accept') {
            $ClaimDirectory = $script:RepositoryRoot + "exchanges/claims/$Correlation"
            if (Test-SquadPathExists $TopLevel $ClaimDirectory) {
                $Acceptance = Assert-SquadAcceptance $Session $Packet
                $Result.ExecutionRoot = $Acceptance.Root
                $Result.Code = 'already-accepted'
            }
            else {
                if (Test-SquadPathExists $TopLevel $Inbox.TrimEnd('/')) { Stop-SquadExchange -Code 'incomplete' -Reason 'unclaimed-inbox' }
                Assert-SquadNoAudit $Session $script:RepositoryRoot $Packet
                if ($SquadRoot -cne $script:RepositoryRoot) { Assert-SquadNoAudit $Session $SquadRoot $Packet }
                if ($Context.Head -cne $Packet.Value.targetRevision) { Stop-SquadExchange -Code 'wrong-context' -Reason 'revision-mismatch' }
                Assert-SquadFresh $Session $Packet
                $Result.ExecutionRoot = $SquadRoot
            }
        }
        else {
            $Receipt = Read-SquadDocument $TopLevel $ReceiptPath Receipt
            Assert-SquadBinding $Receipt.Value $Packet
            Assert-SquadRecordTime $Session $Packet $Receipt.Value.reportedAt
            if ($Operation -eq 'Report') {
                $Acceptance = Assert-SquadAcceptance $Session $Packet
                if ($Acceptance.Root -cne $SquadRoot -or $PacketPath -cne ($Inbox + 'packet.json')) { Stop-SquadExchange -Code 'wrong-context' -Reason 'pinned-root' }
                $Result.ExecutionRoot = $Acceptance.Root
                $FinalPath = $Inbox + 'receipt.json'
                $Artifacts = @($Acceptance.Packet, $Acceptance.Intake, $Receipt)
                $Predecessor = $Acceptance.Seal
            }
            else {
                if ($PacketPath -cne ($Outbox + 'packet.json')) { Stop-SquadExchange -Code 'wrong-context' -Reason 'original-packet-required' }
                $Predecessor = Assert-SquadCommittedOperation $Session Issue $SquadRoot $Packet @($Packet)
                $null = Invoke-SquadGit Commit -Revision $Packet.Value.sourceRevision
                $FinalPath = $Outbox + 'receipt.json'
                $Artifacts = @($Packet, $Receipt)
            }
            if (Test-SquadPathExists $TopLevel $FinalPath) {
                try { $SavedReceipt = Read-SquadDocument $TopLevel $FinalPath Receipt }
                catch { Stop-SquadExchange -Code 'incomplete' -Reason 'receipt-incomplete' }
                if ($SavedReceipt.Hash -cne $Receipt.Hash) { Stop-SquadExchange -Code 'conflict' -Reason 'receipt-conflict' }
                $Artifacts[-1] = $SavedReceipt
                $null = Assert-SquadCommittedOperation $Session $Operation $SquadRoot $Packet $Artifacts -Receipt $SavedReceipt -Predecessor $Predecessor
                $Result.Code = 'already-reported'
            }
            else {
                Assert-SquadNoAudit $Session $SquadRoot $Packet $Operation
                Assert-SquadFresh $Session $Packet
                if ((ConvertTo-SquadTime $Receipt.Value.reportedAt) -lt (ConvertTo-SquadTime $Predecessor.committedAt)) { Stop-SquadExchange -Reason 'report-before-predecessor' }
                if ($Operation -eq 'Report') {
                    Assert-SquadCandidatePath $ReceiptPath $SquadRoot 'receipt.json'
                    if ($Receipt.Value.resultRevision -cne $Context.Head) { Stop-SquadExchange -Code 'wrong-context' -Reason 'result-revision' }
                    $History = $false
                    $Artifact = $false
                    foreach ($Evidence in $Receipt.Value.evidence) {
                        if ((Get-SquadFileDigest $TopLevel $Evidence.path) -cne $Evidence.sha256) { Stop-SquadExchange -Reason 'evidence-digest' }
                        if ($Evidence.path -ceq ($SquadRoot + 'history/Squad Scribe.md')) { $History = $true }
                        elseif (-not $Evidence.path.StartsWith(($SquadRoot + 'history/'), [StringComparison]::Ordinal) -and
                            -not $Evidence.path.StartsWith(($SquadRoot + 'exchanges/'), [StringComparison]::Ordinal) -and
                            $Evidence.path -cnotin @(($SquadRoot + 'state.json'), ($SquadRoot + 'decisions.md'))) { $Artifact = $true }
                    }
                    if ($Receipt.Value.outcome -ceq 'completed' -and (-not $History -or -not $Artifact)) { Stop-SquadExchange -Reason 'completion-evidence' }
                }
            }
        }
        $Result.Valid = $true
        if ($Result.Code -eq 'invalid') { $Result.Code = 'valid' }
    }
    catch {
        $Failure = $_.Exception
        while ($null -ne $Failure.InnerException -and -not $Failure.Data.Contains('ExchangeCode')) { $Failure = $Failure.InnerException }
        if ($Failure.Data.Contains('ExchangeCode')) { $Result.Code = $Failure.Data['ExchangeCode']; $Result.Errors = @($Failure.Message) }
        else { $Result.Code = 'invalid'; $Result.Errors = @('unreadable-exchange') }
    }
    return $Result
}

Export-ModuleMember -Function @('Test-SquadRepoExchange')