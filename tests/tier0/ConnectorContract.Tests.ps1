#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Pins the Squad Connector contract (connector-contract.md / squad-connector.agent.md)
# and its worked example under docs/templates/connector-example/. CONN-01..CONN-12 in
# tests/squad-behavior-contract.md are this file's contract IDs. The agent and
# skill ship through APM; docs/templates/ is source-only consumer documentation.
# These cases run in -SourceRoot mode to validate both surfaces together.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside Pester BeforeDiscovery and BeforeAll blocks, which PSScriptAnalyzer treats as scopes unrelated to the param block.')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

BeforeAll {
    $script:Root = (Resolve-Path -LiteralPath $SourceRoot).Path
    $script:ExampleRoot = Join-Path $script:Root 'docs/templates/connector-example'
    $script:ContractPath = Join-Path $script:Root 'squad-src/.github/skills/squad/references/connector-contract.md'
    $script:AgentPath = Join-Path $script:Root 'squad-src/.github/agents/squad/squad-connector.agent.md'
    $script:DispatchHelperPath = Join-Path $script:Root 'squad-src/.github/skills/squad/scripts/Resolve-SquadConnectorDispatch.ps1'
    . $script:DispatchHelperPath

    function Get-ExampleJson {
        <#
        .SYNOPSIS
            Parses one JSON fixture under docs/templates/connector-example/.
        .PARAMETER Name
            File name, for example 'manifest.json'.
        #>
        param([Parameter(Mandatory)][string]$Name)
        $path = Join-Path $script:ExampleRoot $Name
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }

    function Get-ExampleText {
        param([Parameter(Mandatory)][string]$Name)
        return Get-Content -LiteralPath (Join-Path $script:ExampleRoot $Name) -Raw
    }

    function Invoke-DispatchHelperCli {
        param(
            [Parameter(Mandatory)][string]$Operation,
            [Parameter(Mandatory)][hashtable]$Payload
        )
        $json = $Payload | ConvertTo-Json -Depth 64 -Compress
        $raw = & pwsh -NoProfile -File $script:DispatchHelperPath -Operation $Operation -InputJson $json 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Resolve-SquadConnectorDispatch CLI '$Operation' failed: $raw"
        }
        $raw | ConvertFrom-Json
    }

    function Invoke-ResolveExecutionCli {
        param([Parameter(Mandatory)][hashtable]$Payload)
        Invoke-DispatchHelperCli -Operation 'resolve-execution' -Payload $Payload
    }

    function New-TempTeamFile {
        param([Parameter(Mandatory)][string]$Content)
        $path = Join-Path ([System.IO.Path]::GetTempPath()) ("connector-role-modes-{0}.md" -f [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($path, $Content, [System.Text.UTF8Encoding]::new($false))
        $path
    }

    function Test-ClosedSchema {
        <#
        .SYNOPSIS
            Checks an object's property names against a closed required/optional set.
        .DESCRIPTION
            Mirrors Write-SquadHandoff.ps1's Test-ObjectKeys shape: flags both a
            missing required key and any key outside Required+Optional, so a
            "command"/"exec"/"script"/"url"/"fetch" field or any other stray field is
            reported rather than silently passed through.
        .PARAMETER InputObject
            A PSCustomObject (typically from ConvertFrom-Json) to check.
        .PARAMETER Required
            Property names that must be present.
        .PARAMETER Optional
            Property names that may be present in addition to Required.
        #>
        param(
            [Parameter(Mandatory)][object]$InputObject,
            [string[]]$Required = @(),
            [string[]]$Optional = @()
        )

        $present = @($InputObject.PSObject.Properties.Name)
        $allowed = @($Required) + @($Optional)
        $missing = @($Required | Where-Object { $present -notcontains $_ })
        $extra = @($present | Where-Object { $allowed -notcontains $_ })

        return @{
            IsClosed = ($missing.Count -eq 0 -and $extra.Count -eq 0)
            Missing  = $missing
            Extra    = $extra
        }
    }

    function Test-PathUnderRoot {
        <#
        .SYNOPSIS
            Separator-aware prefix check: is $Candidate truly nested under $Root?
        .DESCRIPTION
            Implements connector-contract.md's "separator-aware prefix check
            (`deliverableRoot/` as a true path-segment prefix, not a bare string match
            that `deliverableRoot-evil/` would also satisfy)". A naive
            $Candidate.StartsWith($Root) would wrongly accept a sibling directory
            whose name merely extends $Root's last segment; this normalizes both
            sides to forward slashes and requires a `/` boundary immediately after
            $Root.
        #>
        param(
            [Parameter(Mandatory)][string]$Root,
            [Parameter(Mandatory)][string]$Candidate
        )

        $normalizedRoot = ($Root -replace '\\', '/').TrimEnd('/')
        $normalizedCandidate = ($Candidate -replace '\\', '/')
        return $normalizedCandidate.StartsWith("$normalizedRoot/", [System.StringComparison]::Ordinal)
    }

    function Test-ArtifactPathRejectReason {
        <#
        .SYNOPSIS
            Returns the name of the first Envelope Artifact-Path Validation Rule an
            artifact path violates, or $null when the path's shape is clean.
        .DESCRIPTION
            Implements connector-contract.md's "Envelope Artifact-Path Validation
            Rules" items 1, 2, 4, and 6 in the contract's own order: reject before
            resolution (absolute / UNC / drive-letter / traversal / ADS), then the
            prefix check against deliverableRoot, then the allowed-extension check,
            then reserved device names and trailing dot/space. Item 3 (symlink /
            junction) and item 5 (numeric caps) need filesystem state and are
            exercised by dedicated cases instead; item 7 (never-overwrite) likewise.
        .PARAMETER DeliverableRoot
            The dispatching role's Deliverable Root, as a forward- or back-slash path.
        .PARAMETER Candidate
            The artifact path to validate, exactly as a result envelope would carry
            it (relative to DeliverableRoot in the clean case).
        #>
        param(
            [Parameter(Mandatory)][string]$DeliverableRoot,
            [Parameter(Mandatory)][string]$Candidate
        )

        if ($Candidate -match '^[A-Za-z]:[\\/]' -or $Candidate -match '^/') { return 'absolute-path' }
        if ($Candidate -match '^\\\\' -or $Candidate -match '^//') { return 'unc-path' }
        if ($Candidate -match '^[A-Za-z]:') { return 'drive-letter' }
        if ($Candidate -split '[\\/]' | Where-Object { $_ -eq '..' }) { return 'path-traversal' }
        if ($Candidate -match ':[^\\/:]') { return 'alternate-data-stream' }

        $resolved = Join-Path $DeliverableRoot $Candidate
        if (-not (Test-PathUnderRoot -Root $DeliverableRoot -Candidate $resolved)) { return 'escapes-deliverable-root' }

        $extension = [System.IO.Path]::GetExtension($Candidate).TrimStart('.').ToLowerInvariant()
        if ($extension -notin @('md', 'json', 'txt')) { return 'disallowed-extension' }

        $reservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
        foreach ($segment in ($Candidate -split '[\\/]')) {
            if (-not $segment) { continue }
            $stem = $segment -replace '\.[^.]*$', ''
            if ($reservedNames -contains $stem.ToUpperInvariant()) { return 'reserved-device-name' }
            if ($segment -match '[. ]$') { return 'trailing-dot-or-space' }
        }

        return $null
    }

    # Verbatim from Write-SquadHandoff.ps1's $SecretPattern, reused rather than
    # reinvented so the connector's secret-pattern posture matches the squad's
    # existing one exactly, per connector-contract.md's own cross-reference.
    $script:SecretPattern = '(?i)(password|secret|token|api[_-]?key|private[_-]?key)\s*[:=]\s*\S{6,}' +
    '|bearer\s+[A-Za-z0-9._-]{10,}' +
    '|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' +
    '|AKIA[0-9A-Z]{16}' +
    '|ASIA[0-9A-Z]{16}' +
    '|xox[baprs]-[0-9A-Za-z-]{10,}' +
    '|[?&]sig=[A-Za-z0-9%]{10,}' +
    '|-----BEGIN [A-Z ]*PRIVATE KEY-----' +
    '|gh[pousr]_[A-Za-z0-9]{20,}' +
    '|github_pat_[A-Za-z0-9_]{20,}' +
    '|sk-[A-Za-z0-9]{20,}' +
    '|AccountKey=[A-Za-z0-9+/=]{20,}'

    function Test-SecretPatternMatch {
        param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
        return [bool]([regex]::IsMatch($Text, $script:SecretPattern))
    }

    function Test-VersionedRequestEnvelope {
        <#
        .SYNOPSIS
            Validates low-level 1.0 vs 1.1 request shape gates.
        .DESCRIPTION
            1.0 allows only the legacy single-role fields. 1.1 requires the
            binding-aware request fields and closed `allowedOutputs`.
        #>
        param(
            [Parameter(Mandatory)][object]$Request,
            [Parameter(Mandatory)][string]$SchemaVersion
        )

        $response = Test-SquadConnectorRequestShape -Request $Request -SchemaVersion $SchemaVersion
        @($response.Issues)
    }

    function Test-VersionedResultEnvelope {
        <#
        .SYNOPSIS
            Validates low-level 1.0 vs 1.1 result shape gates.
        .DESCRIPTION
            1.0 allows only legacy fields. 1.1 requires `bindingId` and
            orchestrator `outputs[]` with closed `outputId/artifacts` items.
        #>
        param(
            [Parameter(Mandatory)][object]$Result,
            [Parameter(Mandatory)][string]$SchemaVersion,
            [ValidateSet('agent', 'orchestrator')][string]$EndpointKind = 'orchestrator'
        )
        $response = Test-SquadConnectorResultShape -Result $Result -SchemaVersion $SchemaVersion -EndpointKind $EndpointKind
        @($response.Issues)
    }
}

Describe 'CONN-01 the example manifest, delegation-request, and result envelope round-trip against the contract schemas' {
    It 'manifest.json parses and carries every Manifest Schema required field' {
        $manifest = Get-ExampleJson -Name 'manifest.json'
        foreach ($field in @('connectorId', 'schemaVersion', 'transport', 'capabilities', 'roles', 'dropPath', 'deadlineMinutesDefault', 'retryCapDefault', 'contact', 'version')) {
            $manifest.PSObject.Properties.Name | Should -Contain $field -Because "Manifest Schema marks $field required"
        }
    }

    It 'delegation-request.sample.json parses and carries every Delegation-Request Envelope required field' {
        $request = Get-ExampleJson -Name 'delegation-request.sample.json'
        foreach ($field in @('taskId', 'connectorId', 'role', 'deliverableRoot', 'task', 'deadline', 'retryCap', 'createdAt')) {
            $request.PSObject.Properties.Name | Should -Contain $field -Because "Delegation-Request Envelope marks $field required"
        }
    }

    It 'result-envelope.sample.json parses and carries every Result Envelope required field' {
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'
        foreach ($field in @('taskId', 'connectorId', 'role', 'status', 'artifacts', 'narrative', 'createdAt')) {
            $result.PSObject.Properties.Name | Should -Contain $field -Because "Result Envelope marks $field required"
        }
        foreach ($artifact in $result.artifacts) {
            $artifact.PSObject.Properties.Name | Should -Contain 'path'
            $artifact.PSObject.Properties.Name | Should -Contain 'type'
            $artifact.type | Should -BeIn @('md', 'json', 'txt')
        }
    }

    It 'the request and result bind to the same taskId, connectorId, and role as the manifest' {
        $manifest = Get-ExampleJson -Name 'manifest.json'
        $request = Get-ExampleJson -Name 'delegation-request.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'

        $request.connectorId | Should -Be $manifest.connectorId
        $manifest.roles | Should -Contain $request.role
        $result.taskId | Should -Be $request.taskId
        $result.connectorId | Should -Be $request.connectorId
        $result.role | Should -Be $request.role
    }
}

Describe 'CONN-02 the schema is closed: unknown and action-naming fields are rejected' {
    BeforeAll {
        $script:ManifestRequired = @('connectorId', 'schemaVersion', 'transport', 'capabilities', 'roles', 'dropPath', 'deadlineMinutesDefault', 'retryCapDefault', 'contact', 'version')
        $script:RequestRequired = @('taskId', 'connectorId', 'role', 'deliverableRoot', 'task', 'deadline', 'retryCap', 'createdAt')
        $script:ResultRequired = @('taskId', 'connectorId', 'role', 'status', 'artifacts', 'narrative', 'createdAt')
    }

    It 'the clean manifest sample validates as closed' {
        (Test-ClosedSchema -InputObject (Get-ExampleJson -Name 'manifest.json') -Required $script:ManifestRequired).IsClosed | Should -BeTrue
    }

    It '<Field> added to a manifest is rejected as an unrecognized field' -ForEach @(
        @{ Field = 'command' }
        @{ Field = 'exec' }
        @{ Field = 'script' }
        @{ Field = 'url' }
        @{ Field = 'fetch' }
        @{ Field = 'webhook' }
    ) {
        $manifest = Get-ExampleJson -Name 'manifest.json'
        $manifest | Add-Member -NotePropertyName $Field -NotePropertyValue 'whatever' -Force
        $check = Test-ClosedSchema -InputObject $manifest -Required $script:ManifestRequired
        $check.IsClosed | Should -BeFalse -Because "connector-contract.md: the schema is closed"
        $check.Extra | Should -Contain $Field
    }

    It 'the clean delegation-request and result-envelope samples each validate as closed' {
        (Test-ClosedSchema -InputObject (Get-ExampleJson -Name 'delegation-request.sample.json') -Required $script:RequestRequired).IsClosed | Should -BeTrue
        (Test-ClosedSchema -InputObject (Get-ExampleJson -Name 'result-envelope.sample.json') -Required $script:ResultRequired).IsClosed | Should -BeTrue
    }

    It 'a command field added to a result envelope is rejected' {
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'
        $result | Add-Member -NotePropertyName 'exec' -NotePropertyValue 'rm -rf /' -Force
        (Test-ClosedSchema -InputObject $result -Required $script:ResultRequired).IsClosed | Should -BeFalse
    }
}

Describe 'CONN-03 transport is restricted to file' {
    It 'the example manifest declares transport: file' {
        (Get-ExampleJson -Name 'manifest.json').transport | Should -Be 'file'
    }

    It '<Transport> is rejected' -ForEach @(
        @{ Transport = 'mcp' }
        @{ Transport = 'http' }
        @{ Transport = 'grpc' }
        @{ Transport = '' }
    ) {
        $manifest = Get-ExampleJson -Name 'manifest.json'
        $manifest.transport = $Transport
        $manifest.transport | Should -Not -Be 'file' -Because 'connector-contract.md: transport is a closed enum where file is the only valid value'
    }
}

Describe 'CONN-04 structural path rejections are caught before resolution' {
    BeforeDiscovery {
        $script:StructuralCases = @(
            @{ Candidate = 'C:\temp\x.md'; Reason = 'absolute-path' }
            @{ Candidate = '/etc/passwd.md'; Reason = 'absolute-path' }
            @{ Candidate = '\\server\share\x.md'; Reason = 'unc-path' }
            @{ Candidate = '//server/share/x.md'; Reason = 'unc-path' }
            @{ Candidate = '../escape.md'; Reason = 'path-traversal' }
            @{ Candidate = 'a/../../escape.md'; Reason = 'path-traversal' }
            @{ Candidate = 'notes.md:hidden-stream'; Reason = 'alternate-data-stream' }
            @{ Candidate = 'CON.md'; Reason = 'reserved-device-name' }
            @{ Candidate = 'sub/NUL.txt'; Reason = 'reserved-device-name' }
            @{ Candidate = 'COM1.json'; Reason = 'reserved-device-name' }
            @{ Candidate = 'trailing-dot./x.md'; Reason = 'trailing-dot-or-space' }
            @{ Candidate = 'trailing-space /x.md'; Reason = 'trailing-dot-or-space' }
        )
    }

    It '<Candidate> is rejected as <Reason>' -ForEach $script:StructuralCases {
        $reason = Test-ArtifactPathRejectReason -DeliverableRoot '.copilot-tracking/squad/members/consumer-interop/changes' -Candidate $Candidate
        $reason | Should -Be $Reason -Because 'connector-contract.md, Envelope Artifact-Path Validation Rules, items 1 and 6'
    }

    It 'the example result envelope artifact path is clean' {
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'
        $request = Get-ExampleJson -Name 'delegation-request.sample.json'
        foreach ($artifact in $result.artifacts) {
            Test-ArtifactPathRejectReason -DeliverableRoot $request.deliverableRoot -Candidate $artifact.path | Should -BeNullOrEmpty
        }
    }
}

Describe 'CONN-05 the containment check is separator-aware' {
    It 'a path truly nested under the root passes' {
        Test-PathUnderRoot -Root 'root' -Candidate 'root/x.md' | Should -BeTrue
    }

    It 'a sibling directory that merely extends the root name is rejected' {
        Test-PathUnderRoot -Root 'root' -Candidate 'root-evil/x.md' | Should -BeFalse -Because 'a bare string prefix match would wrongly accept root-evil/ as nested under root'
    }

    It 'a path escaping deliverableRoot is rejected end to end' {
        $reason = Test-ArtifactPathRejectReason -DeliverableRoot 'deliverableRoot' -Candidate (Join-Path '..' 'deliverableRoot-evil/x.md')
        $reason | Should -Be 'path-traversal'
    }
}

Describe 'CONN-06 symlinks, disallowed extensions, and numeric caps are rejected' {
    It 'a disallowed file extension is rejected' {
        Test-ArtifactPathRejectReason -DeliverableRoot 'root' -Candidate 'payload.exe' | Should -Be 'disallowed-extension'
        Test-ArtifactPathRejectReason -DeliverableRoot 'root' -Candidate 'script.ps1' | Should -Be 'disallowed-extension'
    }

    It 'md, json, and txt extensions are each allowed' {
        foreach ($extension in @('md', 'json', 'txt')) {
            Test-ArtifactPathRejectReason -DeliverableRoot 'root' -Candidate "file.$extension" | Should -BeNullOrEmpty
        }
    }

    It 'a reparse-point link at an intermediate path component is detected' {
        $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "conn06-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $real = Join-Path $workDir 'real'
        $link = Join-Path $workDir 'linked'
        $LinkType = if ([System.OperatingSystem]::IsWindows()) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType Directory -Path $real -Force | Out-Null

        try {
            try {
                New-Item -ItemType $LinkType -Path $link -Target $real -ErrorAction Stop | Out-Null
            }
            catch {
                Set-ItResult -Skipped -Because "this environment cannot create a $LinkType link: $($_.Exception.Message)"
                return
            }

            $item = Get-Item -LiteralPath $link -Force
            ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) | Should -Not -Be 0 -Because 'connector-contract.md: reject any symlink, junction, or reparse point at any path component'
        }
        finally {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'an oversized string value fails the 10,000 character cap' {
        $oversizeNarrative = 'x' * 10001
        $oversizeNarrative.Length | Should -BeGreaterThan 10000
        ($oversizeNarrative.Length -le 10000) | Should -BeFalse -Because 'connector-contract.md: 10,000 characters maximum for any single string value'
    }

    It 'the example narrative stays within the string cap' {
        (Get-ExampleJson -Name 'result-envelope.sample.json').narrative.Length | Should -BeLessOrEqual 10000
    }
}

Describe 'CONN-07 credential-shaped content is rejected' {
    It 'the example manifest, request, and result carry no secret-shaped content' {
        foreach ($name in @('manifest.json', 'delegation-request.sample.json', 'result-envelope.sample.json')) {
            Test-SecretPatternMatch -Text (Get-ExampleText -Name $name) | Should -BeFalse -Because "$name must carry no credential-shaped content"
        }
    }

    It '<Sample> is flagged by the secret-pattern linter' -ForEach @(
        @{ Sample = 'api_key=AKIAABCDEFGHIJKLMNOP'; Label = 'aws-style key' }
        @{ Sample = 'password: Sup3rSecretValue!'; Label = 'password field' }
        @{ Sample = '-----BEGIN RSA PRIVATE KEY-----'; Label = 'PEM header' }
        @{ Sample = 'Authorization: Bearer abcdefghij0123456789'; Label = 'bearer token' }
        @{ Sample = 'ghp_abcdefghijklmnopqrstuvwxyz012345'; Label = 'GitHub token' }
    ) {
        Test-SecretPatternMatch -Text $Sample | Should -BeTrue -Because "a $Label must be caught, not accepted"
    }
}

Describe 'CONN-08 envelope binding and replay protection' {
    It 'a mismatched connectorId is rejected' {
        $request = Get-ExampleJson -Name 'delegation-request.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'
        $result.connectorId = 'a-different-connector'
        ($result.connectorId -eq $request.connectorId) | Should -BeFalse
    }

    It 'a mismatched taskId is rejected' {
        $request = Get-ExampleJson -Name 'delegation-request.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'
        $result.taskId = 'task-not-this-one'
        ($result.taskId -eq $request.taskId) | Should -BeFalse
    }

    It 'a mismatched role is rejected' {
        $request = Get-ExampleJson -Name 'delegation-request.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'
        $result.role = 'researcher'
        ($result.role -eq $request.role) | Should -BeFalse
    }

    # Durable replay rejection is exercised against the real library and separate
    # CLI processes in ConnectorDispatch.Tests.ps1, not an in-memory stand-in.
}

Describe 'CONN-09 squad-connector.agent.md frontmatter' {
    BeforeAll {
        $script:AgentRaw = Get-Content -LiteralPath $script:AgentPath -Raw
    }

    It 'declares user-invocable: false' {
        $script:AgentRaw | Should -Match '(?m)^user-invocable:\s*false\s*$'
    }

    It 'does not declare disable-model-invocation' {
        $script:AgentRaw | Should -Not -Match '(?m)^disable-model-invocation:'
    }
}

Describe 'CONN-10 the untrusted-data guard is stated in both the contract and the connector agent' {
    It 'connector-contract.md states its Untrusted-Data Guard' {
        $contract = Get-Content -LiteralPath $script:ContractPath -Raw
        $contract | Should -Match '## Untrusted-Data Guard'
        $contract | Should -Match '(?i)untrusted data'
    }

    It 'squad-connector.agent.md states the same guard in its own text' {
        $agent = Get-Content -LiteralPath $script:AgentPath -Raw
        $agent | Should -Match '(?i)untrusted data'
        $agent | Should -Match '(?i)never let it steer a gate'
    }
}

Describe 'CONN-11 the example history-entry narrative carries the accounting marker' {
    It 'docs/templates/connector-example/README.md carries the exact marker phrase' {
        $readme = Get-ExampleText -Name 'README.md'
        $readme | Should -Match 'External-unmetered: connector=acme-coordinator-v2'
    }

    It 'the result-envelope sample narrative also carries the marker, matching its own connectorId' {
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'
        $result.narrative | Should -Match ([regex]::Escape("External-unmetered: connector=$($result.connectorId)"))
    }
}

Describe 'CONN-12 the sample coordinator is never auto-run, and blank templates plus a checklist exist' {
    It 'sample-consumer-coordinator.md is a markdown file, not a runnable script' {
        $path = Join-Path $script:ExampleRoot 'sample-consumer-coordinator.md'
        [System.IO.Path]::GetExtension($path) | Should -Be '.md'
        (Get-Content -LiteralPath $path -Raw) | Should -Not -Match '^#!'
    }

    It 'no Tier 0 container or script - other than this file''s own assertions - references sample-consumer-coordinator.md' {
        $invokers = Get-ChildItem -LiteralPath (Join-Path $script:Root 'tests') -Recurse -Filter '*.ps1' |
            Where-Object { $_.Name -ne 'ConnectorContract.Tests.ps1' } |
            Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'sample-consumer-coordinator\.md' }
        @($invokers) | Should -BeNullOrEmpty -Because 'the sample coordinator is prose/pseudo-code for a consumer to read, never a script this suite or any harness runs'
    }

    It '<Name> blank template exists and parses as JSON' -ForEach @(
        @{ Name = 'manifest.template.json' }
        @{ Name = 'delegation-request.template.json' }
        @{ Name = 'result-envelope.template.json' }
    ) {
        $path = Join-Path $script:ExampleRoot $Name
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'COMPATIBILITY-CHECKLIST.md exists and restates the contract Compatibility Checklist' {
        $path = Join-Path $script:ExampleRoot 'COMPATIBILITY-CHECKLIST.md'
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw) | Should -Match 'Compatibility Checklist'
    }
}

Describe 'CONN-26 retry exhaustion preserves the runtime unreachable status' {
    It 'the thin connector agent delegates terminal classification to the lifecycle wrapper' {
        $agent = Get-Content -LiteralPath $script:AgentPath -Raw
        $agent | Should -Match 'Invoke-SquadConnectorDispatch\.ps1'
        $agent | Should -Match 'return its JSON verbatim'
        $agent | Should -Match 'retry/deadline bounds'
    }

    It 'the normative contract distinguishes unanswered exhaustion from a present failed result' {
        $contract = Get-Content -LiteralPath $script:ContractPath -Raw
        $contract | Should -Match ([regex]::Escape('At or after the deadline, or when `retryCap` is exhausted, it is `unreachable`.'))
        $contract | Should -Match ([regex]::Escape('A present-but-invalid envelope is `failed`.'))
        $contract | Should -Match ([regex]::Escape('`retryCap` also turns a stalled retry loop into `unreachable`'))
    }

    It 'the consumer checklist carries the same terminal-status split' {
        $checklist = Get-ExampleText -Name 'COMPATIBILITY-CHECKLIST.md'
        $checklist | Should -Match '(?s)a coordinator with a failure result\s+writes `status: "failed"`.*?an unanswered request reaches\s+`unreachable`'
    }
}

Describe 'CONN-28 ordinary resume preserves a durable collision snapshot' {
    It 'requires a native coordinator dispatch with the original id, not a direct wrapper call' {
        $coordinator = Get-Content -LiteralPath (Join-Path $script:Root 'squad-src/.github/agents/squad/squad-coordinator.agent.md') -Raw
        $coordinator | Should -Match 'Resume pending connectors first'
        $coordinator | Should -Match 'native `runSubagent` or `task` to dispatch\s+`Squad Connector`'
        $coordinator | Should -Match 'never run the wrapper inline'
        $coordinator | Should -Match 'original `taskId`'
        $coordinator | Should -Match 'never run the wrapper inline or\s+create a replacement request'
    }

    It 'preserves <_> pre-existing paths through library and CLI validation' -ForEach @(0, 1, 2, 3) {
        $pathCount = $_
        $request = Get-ExampleJson -Name 'delegation-request.agent.1.1.sample.json'
        $snapshot = [ordered]@{
            taskId          = $request.taskId
            deliverableRoot = $request.deliverableRoot
            preExistingPaths = @(
                for ($index = 0; $index -lt $pathCount; $index++) {
                    "$($request.deliverableRoot)/existing-$index.md"
                }
            )
            createdAt       = $request.createdAt
        }

        foreach ($inputSnapshot in @($snapshot, [pscustomobject]$snapshot)) {
            $direct = Test-SquadConnectorSnapshot -Snapshot $inputSnapshot -Request $request
            $direct.Status | Should -Be 'ok' -Because ($direct.Issues -join ', ')
            $direct.PreExistingPaths -is [array] | Should -BeTrue
            $direct.PreExistingPaths.Count | Should -Be $pathCount
            ($direct.PreExistingPaths -join ',') | Should -Be ($snapshot.preExistingPaths -join ',')
        }

        $cli = Invoke-DispatchHelperCli -Operation 'validate-snapshot' -Payload @{
            snapshot = $snapshot
            request  = $request
        }
        $cli.Status | Should -Be 'ok' -Because ($cli.Issues -join ', ')
        $cli.PreExistingPaths -is [array] | Should -BeTrue
        $cli.PreExistingPaths.Count | Should -Be $pathCount
        ($cli.PreExistingPaths -join ',') | Should -Be ($snapshot.preExistingPaths -join ',')
    }

    It 'rejects <Name> pre-existing paths through library and CLI validation' -ForEach @(
        @{ Name = 'a scalar string'; Value = '.copilot-tracking/research/existing.md' }
        @{ Name = 'an empty string'; Value = '' }
        @{ Name = 'a null value'; Value = $null }
        @{ Name = 'a number'; Value = 1 }
        @{ Name = 'an object'; Value = @{ path = '.copilot-tracking/research/existing.md' } }
    ) {
        $request = Get-ExampleJson -Name 'delegation-request.agent.1.1.sample.json'
        $snapshot = [ordered]@{
            taskId          = $request.taskId
            deliverableRoot = $request.deliverableRoot
            preExistingPaths = $Value
            createdAt       = $request.createdAt
        }

        foreach ($inputSnapshot in @($snapshot, [pscustomobject]$snapshot)) {
            $direct = Test-SquadConnectorSnapshot -Snapshot $inputSnapshot -Request $request
            $direct.Status | Should -Be 'error'
        }
        $cli = Invoke-DispatchHelperCli -Operation 'validate-snapshot' -Payload @{
            snapshot = $snapshot
            request  = $request
        }
        $cli.Status | Should -Be 'error'
    }

    It 'rejects missing bindings, extra fields, duplicate paths, and paths outside the request root' {
        $request = Get-ExampleJson -Name 'delegation-request.agent.1.1.sample.json'
        $snapshot = [ordered]@{
            taskId          = 'wrong-task'
            deliverableRoot = 'other/root'
            preExistingPaths = @(
                'other/root/existing.md'
                'other/root/existing.md'
                'outside.md'
            )
            createdAt       = 'not-a-date'
            regenerated     = $true
        }

        $check = Test-SquadConnectorSnapshot -Snapshot $snapshot -Request $request
        $check.Status | Should -Be 'error'
        @($check.Issues) | Should -Contain 'binding-mismatch:taskId'
        @($check.Issues) | Should -Contain 'binding-mismatch:deliverableRoot'
        @($check.Issues) | Should -Contain 'invalid:createdAt'
        @($check.Issues) | Should -Contain 'extra:regenerated'
        @($check.Issues | Where-Object { $_ -like 'duplicate:preExistingPath:*' }).Count | Should -Be 1
        @($check.Issues | Where-Object { $_ -like 'outside-deliverable-root:preExistingPath:*' }).Count | Should -Be 1
    }

    It 'routes snapshot publication and reuse through the deterministic lifecycle owner' {
        $agent = Get-Content -LiteralPath $script:AgentPath -Raw
        $contract = Get-Content -LiteralPath $script:ContractPath -Raw

        $agent | Should -Match 'Invoke-SquadConnectorDispatch\.ps1'
        $agent | Should -Match 'never reconstruct its baseline|Never\s+replace a pending task'
        $agent | Should -Match 'original request/snapshot hashes'
        $contract | Should -Match ([regex]::Escape('The snapshot schema is closed. It is internal collision evidence, not a consumer-authored envelope'))
        $contract | Should -Match ([regex]::Escape('A later dispatch must load the original sidecar'))
        $contract | Should -Match ([regex]::Escape('A missing, malformed, mismatched, or rewritten snapshot is a validation failure (`failed`)'))
    }
}

Describe 'CONN-29 confirmed binding changes preserve completed provenance' {
    It 'defines bounded, confirmed historical evidence without granting active execution authority' {
        $roleModes = Get-Content -LiteralPath (Join-Path $script:Root 'squad-src/.github/skills/squad/references/connector-role-modes.md') -Raw
        $roleModes | Should -Match ([regex]::Escape('## Connector Binding Retirement <timestamp> <binding-id>'))
        foreach ($field in @('team', 'manifests', 'confirmed', 'confirmationRef', 'historyEntries')) {
            $roleModes | Should -Match ([regex]::Escape("| ``$field`` |"))
        }
        $roleModes | Should -Match 'same\s+membership, manifest-shape, authorized-role, connector-id, and uniqueness rules'
        $roleModes | Should -Match 'Retirement evidence is historical only: it cannot dispatch a removed connector'
        $roleModes | Should -Match 'before replacing an identity-bearing|Before replacing an identity-bearing'
        $roleModes | Should -Match 'without editing history'
    }

    It 'requires the initialization writer to preserve history evidence before replacing active rows' {
        $coldInit = Get-Content -LiteralPath (Join-Path $script:Root 'squad-src/.github/skills/squad/references/scribe-cold-init-and-seeding.md') -Raw
        $coldInit | Should -Match 'Before a confirmed unbind or identity-changing rebind'
        $coldInit | Should -Match 'Write that evidence before replacing the\s+active rows'
        $coldInit | Should -Match ([regex]::Escape('`connector-role-modes.md`, section 10'))
    }
}

Describe 'CONN-34 shared manifest integer limits' {
    It 'rejects <Name> through library and CLI validation in both contract versions' -ForEach @(
        @{ Name = 'retry string'; Field = 'retryCapDefault'; Value = 'invalid' },
        @{ Name = 'numeric retry string'; Field = 'retryCapDefault'; Value = '2' },
        @{ Name = 'negative retries'; Field = 'retryCapDefault'; Value = -1 },
        @{ Name = 'boolean retries'; Field = 'retryCapDefault'; Value = $true },
        @{ Name = 'fractional retries'; Field = 'retryCapDefault'; Value = 1.5 },
        @{ Name = 'overflowing retries'; Field = 'retryCapDefault'; Value = 2147483648L },
        @{ Name = 'deadline string'; Field = 'deadlineMinutesDefault'; Value = 'invalid' },
        @{ Name = 'zero deadline'; Field = 'deadlineMinutesDefault'; Value = 0 },
        @{ Name = 'negative deadline'; Field = 'deadlineMinutesDefault'; Value = -1 },
        @{ Name = 'fractional deadline'; Field = 'deadlineMinutesDefault'; Value = 1.5 },
        @{ Name = 'overflowing deadline'; Field = 'deadlineMinutesDefault'; Value = 2147483648L }
    ) {
        foreach ($name in @('manifest.json', 'manifest.1.1.json')) {
            $manifest = Get-ExampleJson -Name $name
            $manifest.$Field = $Value
            $direct = Test-SquadConnectorManifestShape -Manifest $manifest
            $direct.Status | Should -Be 'error'
            $direct.Issues | Should -Contain "invalid:$Field"
            $cli = Invoke-DispatchHelperCli -Operation 'validate-manifest' -Payload @{ manifest = $manifest }
            $cli.Status | Should -Be 'error'
            $cli.Issues | Should -Contain "invalid:$Field"
        }
    }

    It 'accepts integer boundaries with Deadline=<Deadline> and Retry=<Retry>' -ForEach @(
        @{ Deadline = 1; Retry = 0 },
        @{ Deadline = 2147483647; Retry = 2147483647 }
    ) {
        foreach ($name in @('manifest.json', 'manifest.1.1.json')) {
            $manifest = Get-ExampleJson -Name $name
            $manifest.deadlineMinutesDefault = $Deadline
            $manifest.retryCapDefault = $Retry
            (Test-SquadConnectorManifestShape -Manifest $manifest).Status | Should -Be 'ok'
            (Invoke-DispatchHelperCli -Operation 'validate-manifest' -Payload @{ manifest = $manifest }).Status | Should -Be 'ok'
        }
    }
}

Describe 'CONN-35 native resume input and Scribe handoff fidelity' {
    It 'requires exact closed dispatch JSON and returns the first wrapper result without a child retry' {
        $agent = Get-Content -LiteralPath $script:AgentPath -Raw
        $modes = Get-Content -LiteralPath (Join-Path $script:Root 'squad-src/.github/skills/squad/references/connector-role-modes.md') -Raw
        $agent | Should -Match 'complete dispatch JSON'
        $agent | Should -Match 'Omit optional `task`, `allowedOutputs`, `deadline`, and `retryCap`'
        $agent | Should -Match 'Return the first JSON even when it reports failure'
        $agent | Should -Match 'do not correct inputs, debug, or invoke again'
        $modes | Should -Match 'machine-ready JSON dispatch'
        $modes | Should -Match 'not a prose list'
        $modes | Should -Match 'A model equal\s+to the parent/session model is not evidence of `session-inherited`'
    }

    It 'renders literal provenance bullets and keeps source changes out of report deliverables' {
        $modes = Get-Content -LiteralPath (Join-Path $script:Root 'squad-src/.github/skills/squad/references/connector-role-modes.md') -Raw
        $schema = Get-Content -LiteralPath (Join-Path $script:Root 'squad-src/.github/skills/squad/references/entry-schemas.md') -Raw
        $modes | Should -Match '(?ms)^```markdown\r?\n\* External provenance:[^\r\n]+\r?\n\* Verification: external, unverified\r?\n\* External-unmetered:'
        $modes | Should -Match 'Only wrapper-validated `artifacts` and `outputs\[\]\.artifacts`'
        $schema | Should -Match 'literal `\* ` bullets'
        $schema | Should -Match 'source changes go in `Outcome:`'
    }
}

Describe 'CONN-24 and CONN-25 version gates, binding checks, and allowed-output checks' {
    It 'accepts the legacy 1.0 fixtures and rejects 1.1-only fields under 1.0' {
        $manifest = Get-ExampleJson -Name 'manifest.json'
        $request = Get-ExampleJson -Name 'delegation-request.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'

        $manifest.schemaVersion | Should -Be '1.0'
        @(Test-VersionedRequestEnvelope -Request $request -SchemaVersion '1.0') | Should -Be @()
        @(Test-VersionedResultEnvelope -Result $result -SchemaVersion '1.0') | Should -Be @()

        $withV11RequestField = ($request | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
        $withV11RequestField | Add-Member -NotePropertyName bindingId -NotePropertyValue 'legacy-cannot-bind' -Force
        @(Test-VersionedRequestEnvelope -Request $withV11RequestField -SchemaVersion '1.0') | Should -Contain 'v11-field-under-v10:bindingId'

        $withV11ResultField = ($result | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
        $withV11ResultField | Add-Member -NotePropertyName outputs -NotePropertyValue @() -Force
        @(Test-VersionedResultEnvelope -Result $withV11ResultField -SchemaVersion '1.0') | Should -Contain 'v11-field-under-v10:outputs'
    }

    It 'accepts the 1.1 fixtures and requires binding/output fields' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'

        $manifest.schemaVersion | Should -Be '1.1'
        @(Test-VersionedRequestEnvelope -Request $request -SchemaVersion '1.1') | Should -Be @()
        @(Test-VersionedResultEnvelope -Result $result -SchemaVersion '1.1') | Should -Be @()

        $missingBinding = ($request | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
        $missingBinding.PSObject.Properties.Remove('bindingId')
        @(Test-VersionedRequestEnvelope -Request $missingBinding -SchemaVersion '1.1') | Should -Contain 'missing:bindingId'

        $missingOutputs = ($result | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
        $missingOutputs.PSObject.Properties.Remove('outputs')
        @(Test-VersionedResultEnvelope -Result $missingOutputs -SchemaVersion '1.1') | Should -Contain 'missing:outputs'
    }

    It 'accepts valid 1.0 and 1.1 manifests through the process-level CLI wrapper' {
        $legacy = Get-ExampleJson -Name 'manifest.json'
        $v11 = Get-ExampleJson -Name 'manifest.1.1.json'

        (Invoke-DispatchHelperCli -Operation 'validate-manifest' -Payload @{ manifest = $legacy }).Status | Should -Be 'ok'
        (Invoke-DispatchHelperCli -Operation 'validate-manifest' -Payload @{ manifest = $v11 }).Status | Should -Be 'ok'
    }

    It 'accepts a single-agent 1.1 result with optional outputs present=<IncludeOutputs>' -ForEach @(
        @{ IncludeOutputs = $false },
        @{ IncludeOutputs = $true }
    ) {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $manifest.endpointKind = 'agent'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $request.allowedOutputs = @($request.allowedOutputs[0])
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $result.artifacts = @($result.outputs[0].artifacts)
        $result.PSObject.Properties.Remove('outputs')
        if ($IncludeOutputs) { $result | Add-Member -NotePropertyName outputs -NotePropertyValue @() }

        $exchange = Test-SquadConnectorExchange -Manifest $manifest -Request $request -Result $result
        $exchange.Status | Should -Be 'ok'
        @($exchange.Issues) | Should -BeNullOrEmpty
        $cli = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $request; result = $result }
        $cli.Status | Should -Be 'ok'
        @($cli.Issues) | Should -BeNullOrEmpty
    }

    It 'enforces transport=file in imported and process-level manifest validation' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $manifest.transport = 'mcp'

        (Test-SquadConnectorManifestShape -Manifest $manifest).Issues | Should -Contain 'invalid:transport:mcp'

        $cli = Invoke-DispatchHelperCli -Operation 'validate-manifest' -Payload @{ manifest = $manifest }
        $cli.Status | Should -Be 'error'
        @($cli.Issues) | Should -Contain 'invalid:transport:mcp'
    }

    It 'fails closed when outputId is undeclared by request.allowedOutputs' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $result.outputs[0].outputId = 'not-declared'
        $exchange = Test-SquadConnectorExchange -Manifest $manifest -Request $request -Result $result
        @($exchange.Issues) | Should -Contain 'undeclared-output-id:not-declared'
    }

    It 'fails closed on request/result binding mismatch in 1.1' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $result.bindingId = 'different-binding'
        $exchange = Test-SquadConnectorExchange -Manifest $manifest -Request $request -Result $result
        @($exchange.Issues) | Should -Contain 'binding-mismatch:bindingId'
    }

    It 'fails closed on manifest/request/result connector-id mismatches' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $request.connectorId = 'connector-request-other'
        $result.connectorId = 'connector-result-other'

        $exchange = Test-SquadConnectorExchange -Manifest $manifest -Request $request -Result $result
        @($exchange.Issues) | Should -Contain 'binding-mismatch:manifest-request:connectorId'
        @($exchange.Issues) | Should -Contain 'binding-mismatch:manifest-result:connectorId'
        @($exchange.Issues) | Should -Contain 'binding-mismatch:connectorId'
    }

    It 'rejects nested unknown/action fields and output path/root violations' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'

        $request.allowedOutputs[0] | Add-Member -NotePropertyName url -NotePropertyValue 'https://example.invalid/drop' -Force
        @(Test-VersionedRequestEnvelope -Request $request -SchemaVersion '1.1') | Should -Contain 'action-field-refused:allowedOutputs.url'

        $result.outputs[0].artifacts[0].path = '../escape.md'
        $result.outputs[0].artifacts[0] | Add-Member -NotePropertyName script -NotePropertyValue 'Invoke-Unsafe' -Force
        $result.outputs[0].artifacts[0] | Add-Member -NotePropertyName unknown -NotePropertyValue 'unexpected' -Force
        $result.outputs += @(
            [pscustomobject]@{
                outputId = 'not-declared'
                artifacts = @(
                    [pscustomobject]@{
                        path = 'extra-note.md'
                        type = 'md'
                    }
                )
            }
        )

        $exchange = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $request; result = $result }
        $exchange.Status | Should -Be 'error'
        @($exchange.Issues) | Should -Contain 'request.action-field-refused:allowedOutputs.url'
        @($exchange.Issues) | Should -Contain 'result.action-field-refused:outputs.artifacts.script'
        @($exchange.Issues) | Should -Contain 'result.extra:outputs.artifacts.unknown'
        @($exchange.Issues) | Should -Contain 'undeclared-output-id:not-declared'
        @($exchange.Issues) | Should -Contain 'declared-output-artifact-path:implementation-note:path-traversal:../escape.md'
    }

    It 'refuses action-like fields in closed request/result shapes' {
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $request | Add-Member -NotePropertyName command -NotePropertyValue 'pwsh -c whoami' -Force
        @(Test-VersionedRequestEnvelope -Request $request -SchemaVersion '1.1') | Should -Contain 'action-field-refused:command'

        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $result.outputs[0] | Add-Member -NotePropertyName script -NotePropertyValue 'Invoke-Unsafe' -Force
        @(Test-VersionedResultEnvelope -Result $result -SchemaVersion '1.1' -EndpointKind 'orchestrator') | Should -Contain 'action-field-refused:outputs.script'
    }
}

Describe 'resolve-execution process CLI fail-closed guards (F-01/F-02/F-03/F-07)' {
    It 'rejects council original and both on additive-only connector routes' {
        $teamPath = Join-Path $script:ExampleRoot 'role-mode-bindings.1.1.md'

        $original = Invoke-ResolveExecutionCli -Payload @{
            teamPath = $teamPath
            role = 'gcp'
            execution = 'original'
            memberName = 'GCP Assessor'
            councilDispatch = $true
        }
        $original.Status | Should -Be 'error'
        $original.Reason | Should -Be 'original-missing-internal-member'

        $bothCouncil = Invoke-ResolveExecutionCli -Payload @{
            teamPath = $teamPath
            role = 'gcp'
            execution = 'both'
            memberName = 'GCP Assessor'
            councilDispatch = $true
            parallelEligible = $true
            admissionApproved = $true
            allowedOutputs = @(
                @{ outputId = 'a'; deliverableRoot = '.copilot-tracking/squad/members/consumer-interop/changes/gcp-a' },
                @{ outputId = 'b'; deliverableRoot = '.copilot-tracking/squad/members/consumer-interop/changes/gcp-b' }
            )
        }
        $bothCouncil.Status | Should -Be 'error'
        $bothCouncil.Reason | Should -Be 'both-missing-internal-original'
    }

    It 'rejects additive-only both when no distinct internal original exists' {
        $teamPath = Join-Path $script:ExampleRoot 'role-mode-bindings.1.1.md'
        $both = Invoke-ResolveExecutionCli -Payload @{
            teamPath = $teamPath
            role = 'gcp'
            execution = 'both'
            memberName = 'GCP Assessor'
            parallelEligible = $true
            admissionApproved = $true
            allowedOutputs = @(
                @{ outputId = 'a'; deliverableRoot = '.copilot-tracking/squad/members/consumer-interop/changes/gcp-a' },
                @{ outputId = 'b'; deliverableRoot = '.copilot-tracking/squad/members/consumer-interop/changes/gcp-b' }
            )
        }
        $both.Status | Should -Be 'error'
        $both.Reason | Should -Be 'both-missing-internal-original'
    }

    It 'rejects replace/coordinator bindings with blank connector Member Name before returning ok' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |
| coordinator | Lead | Squad Coordinator |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-replace | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma |  |  | developer | connector |
| coordinator-replace | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | coordinator | coordinator:Squad Coordinator |  |  | coordinator | connector |
'@
        try {
            $developer = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'connector:developer-replace'
            }
            $developer.Status | Should -Be 'error'
            $developer.Reason | Should -Be 'invalid-applicable-binding'
            @($developer.Issues) | Should -Contain 'developer-replace:missing:memberName'

            $coordinator = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'coordinator'
                memberName = 'Lead'
                execution = 'connector:coordinator-replace'
            }
            $coordinator.Status | Should -Be 'error'
            $coordinator.Reason | Should -Be 'connector-protected-role'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'rejects invalid connector identity/default enum/endpoint metadata on applicable bindings' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| invalid-binding |  | docs/templates/connector-example/manifest.1.1.json | service | replace | role | role:developer/Gamma | Partner Developer |  | developer | maybe |
'@
        try {
            $resolved = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'connector:invalid-binding'
            }
            $resolved.Status | Should -Be 'error'
            $resolved.Reason | Should -Be 'invalid-applicable-binding'
            @($resolved.Issues) | Should -Contain 'invalid-binding:missing:connectorId'
            @($resolved.Issues) | Should -Contain 'invalid-binding:invalid:endpointKind'
            @($resolved.Issues) | Should -Contain 'invalid-binding:invalid:defaultExecution'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'returns structured status when optional resolve-execution JSON fields are omitted and preserves first-row internal selection without connectors' {
        $singleMemberTeam = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |
'@
        $multiInternalTeam = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |
| developer | Delta | Squad Implementor |
'@
        $ambiguousTeam = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |
| developer | Delta | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-gamma | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Gamma |  | developer | connector |
| developer-delta | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Delta | Partner Delta |  | developer | connector |
'@
        try {
            $noBinding = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $singleMemberTeam
                role = 'developer'
            }
            $noBinding.Status | Should -Be 'ok'
            $noBinding.Choice | Should -Be 'original'

            $multiAttended = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $multiInternalTeam
                role = 'developer'
            }
            $multiAttended.Status | Should -Be 'ok'
            $multiAttended.Choice | Should -Be 'original'
            $multiAttended.Reason | Should -Be 'no-applicable-binding'
            $multiAttended.MemberName | Should -Be 'Gamma'
            $multiAttended.Agent | Should -Be 'Squad Implementor'

            $multiUnattended = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $multiInternalTeam
                role = 'developer'
                unattended = $true
            }
            $multiUnattended.Status | Should -Be 'ok'
            $multiUnattended.Choice | Should -Be 'original'
            $multiUnattended.Reason | Should -Be 'no-applicable-binding'
            $multiUnattended.MemberName | Should -Be 'Gamma'
            $multiUnattended.Agent | Should -Be 'Squad Implementor'

            $attended = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $ambiguousTeam
                role = 'developer'
            }
            $attended.Status | Should -Be 'clarify'
            $attended.Reason | Should -Be 'interactive-member-ambiguity'

            $unattended = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $ambiguousTeam
                role = 'developer'
                unattended = $true
            }
            $unattended.Status | Should -Be 'error'
            $unattended.Reason | Should -Be 'unattended-member-ambiguity'
        }
        finally {
            Remove-Item -LiteralPath $singleMemberTeam -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $multiInternalTeam -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $ambiguousTeam -ErrorAction SilentlyContinue
        }
    }

    It 'returns ConnectorId and BindingId separately for explicit and default both paths' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-both | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer |  | developer | both |
'@
        $allowedOutputs = @(
            @{ outputId = 'implementation-note'; deliverableRoot = 'changes/impl' },
            @{ outputId = 'validation-note'; deliverableRoot = 'changes/validation' }
        )
        try {
            $explicit = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'both'
                parallelEligible = $true
                admissionApproved = $true
                allowedOutputs = $allowedOutputs
            }
            $explicit.Status | Should -Be 'ok'
            $explicit.BindingId | Should -Be 'developer-both'
            $explicit.ConnectorId | Should -Be 'acme-delivery-orchestrator-v3'

            $defaulted = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                parallelEligible = $true
                admissionApproved = $true
                allowedOutputs = $allowedOutputs
            }
            $defaulted.Status | Should -Be 'ok'
            $defaulted.BindingId | Should -Be 'developer-both'
            $defaulted.ConnectorId | Should -Be 'acme-delivery-orchestrator-v3'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'exposes a distinct connector identity for explicit and default connector choices rather than the internal row (NR-001)' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-default | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer |  |  | connector |
'@
        try {
            $explicit = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'connector:developer-default'
            }
            $explicit.Status | Should -Be 'ok'
            $explicit.Agent | Should -Be 'Squad Connector'
            $explicit.MemberName | Should -Be 'Partner Developer'
            $explicit.MemberName | Should -Not -Be 'Gamma'

            $defaulted = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
            }
            $defaulted.Status | Should -Be 'ok'
            $defaulted.Reason | Should -Be 'binding-default-connector'
            $defaulted.Agent | Should -Be 'Squad Connector'
            $defaulted.MemberName | Should -Be 'Partner Developer'
            $defaulted.MemberName | Should -Not -Be 'Gamma'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'preserves the internal original identity alongside a distinct connector identity for both (NR-001)' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-both-identity | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer |  |  | both |
'@
        $allowedOutputs = @(
            @{ outputId = 'implementation-note'; deliverableRoot = 'changes/impl' },
            @{ outputId = 'validation-note'; deliverableRoot = 'changes/validation' }
        )
        try {
            $both = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'both'
                parallelEligible = $true
                admissionApproved = $true
                allowedOutputs = $allowedOutputs
            }
            $both.Status | Should -Be 'ok'
            $both.MemberName | Should -Be 'Gamma'
            $both.Agent | Should -Be 'Squad Implementor'
            $both.ConnectorAgent | Should -Be 'Squad Connector'
            $both.ConnectorMemberName | Should -Be 'Partner Developer'
            $both.ConnectorMemberName | Should -Not -Be 'Gamma'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'routes council dispatch to the canonical internal original regardless of a connector default/ask overlay, while explicit connector/both remain refused (NR-003)' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-ask | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer |  |  | ask |
'@
        try {
            $council = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                councilDispatch = $true
            }
            $council.Status | Should -Be 'ok'
            $council.Reason | Should -Be 'council-canonical-original'
            $council.Choice | Should -Be 'original'
            $council.Agent | Should -Be 'Squad Implementor'
            $council.MemberName | Should -Be 'Gamma'

            $explicitConnector = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'connector:developer-ask'
                councilDispatch = $true
            }
            $explicitConnector.Status | Should -Be 'error'
            $explicitConnector.Reason | Should -Be 'connector-refused-council'

            $explicitBoth = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'both'
                councilDispatch = $true
                parallelEligible = $true
                admissionApproved = $true
                allowedOutputs = @(
                    @{ outputId = 'a'; deliverableRoot = 'changes/a' },
                    @{ outputId = 'b'; deliverableRoot = 'changes/b' }
                )
            }
            $explicitBoth.Status | Should -Be 'error'
            $explicitBoth.Reason | Should -Be 'both-refused-council'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'routes council dispatch to the canonical internal original even when the only applicable binding is invalid/malformed (NR-003)' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| invalid-binding |  | docs/templates/connector-example/manifest.1.1.json | service | replace | role | role:developer/Gamma | Partner Developer |  | developer | maybe |
'@
        try {
            $attended = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
            }
            $attended.Status | Should -Be 'error'
            $attended.Reason | Should -Be 'invalid-applicable-binding'

            $council = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                councilDispatch = $true
            }
            $council.Status | Should -Be 'ok'
            $council.Reason | Should -Be 'council-canonical-original'
            $council.Choice | Should -Be 'original'
            $council.MemberName | Should -Be 'Gamma'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed on dot-segment escapes across both allowedOutputs roots before the pairwise collision check runs (NR-002)' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-both-escape | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer |  |  | both |
'@
        try {
            $both = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'both'
                parallelEligible = $true
                admissionApproved = $true
                allowedOutputs = @(
                    @{ outputId = 'implementation-note'; deliverableRoot = 'changes/impl/../../escape' },
                    @{ outputId = 'validation-note'; deliverableRoot = 'changes/validation' }
                )
            }
            $both.Status | Should -Be 'error'
            $both.Reason | Should -Be 'both-output-root-invalid-segments'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }
}

Describe 'validate-exchange process CLI hardened allowlist and boundary checks (F-04/F-05)' {
    It 'rejects undeclared top-level artifacts in orchestrator mode' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $result.artifacts = @(
            [pscustomobject]@{
                path = 'outside-output-allowlist.md'
                type = 'md'
            }
        )

        $exchange = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $request; result = $result }
        $exchange.Status | Should -Be 'error'
        @($exchange.Issues) | Should -Contain 'orchestrator-top-level-artifacts-refused'
    }

    It 'rejects request.allowedOutputs roots outside request.deliverableRoot' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $request.allowedOutputs[0].deliverableRoot = 'outside/declared-root'

        $exchange = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $request; result = $result }
        $exchange.Status | Should -Be 'error'
        @($exchange.Issues) | Should -Contain 'request-output-root-outside-deliverable-root:implementation-note'
    }

    It 'fails closed on a dot-segment/filesystem-equivalent escape in a single declared output root (NR-002)' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $request.allowedOutputs[0].deliverableRoot = "$($request.deliverableRoot)/../../escape"

        $exchange = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $request; result = $result }
        $exchange.Status | Should -Be 'error'
        @($exchange.Issues) | Should -Contain 'request-output-root-outside-deliverable-root:implementation-note'
    }

    It 'fails closed when the declared deliverableRoot itself contains a dot-segment escape (NR-002)' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $request.deliverableRoot = "$($request.deliverableRoot)/../escape"

        $exchange = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $request; result = $result }
        $exchange.Status | Should -Be 'error'
        @($exchange.Issues) | Should -Contain 'request-output-root-outside-deliverable-root:implementation-note'
        @($exchange.Issues) | Should -Contain 'request-output-root-outside-deliverable-root:validation-note'
    }

    It 'rejects non-manifest roles, unsupported statuses, and original-choice connector results' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'

        $requestRole = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $resultRole = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $requestRole.role = 'architect'
        $resultRole.role = 'architect'
        $roleExchange = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $requestRole; result = $resultRole }
        @($roleExchange.Issues) | Should -Contain 'manifest-role-not-allowed:request:architect'
        @($roleExchange.Issues) | Should -Contain 'manifest-role-not-allowed:result:architect'

        $requestStatus = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $resultStatus = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $resultStatus.status = 'approved'
        $statusExchange = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $requestStatus; result = $resultStatus }
        @($statusExchange.Issues) | Should -Contain 'unsupported-result-status:approved'

        $requestOriginal = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $resultOriginal = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $requestOriginal.executionChoice = 'original'
        $choiceExchange = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $requestOriginal; result = $resultOriginal }
        @($choiceExchange.Issues) | Should -Contain 'execution-choice-result-mismatch:original'
    }

    It 'validates task-owned deliverables in place under deliverableRoot while rejecting pre-existing collisions, missing files, and duplicate paths' {
        $workRoot = Join-Path $TestDrive 'in-place-exchange'
        $manifest = Get-ExampleJson -Name 'manifest.json'
        $request = Get-ExampleJson -Name 'delegation-request.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.sample.json'

        $deliverableDir = Join-Path $workRoot $request.deliverableRoot
        New-Item -ItemType Directory -Path $deliverableDir -Force | Out-Null
        $preExistingRel = 'pre-existing-note.md'
        Set-Content -LiteralPath (Join-Path $deliverableDir $preExistingRel) -Value 'Pre-existing report before task dispatch.' -Encoding utf8NoBOM

        # Missing task-owned file on disk is rejected when WorkspaceRoot is supplied
        $missingCheck = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{
            manifest         = $manifest
            request          = $request
            result           = $result
            workspaceRoot    = $workRoot
            preExistingPaths = @($preExistingRel)
        }
        $missingCheck.Status | Should -Be 'error'
        @($missingCheck.Issues) | Should -Contain "missing-delivered-artifact:$($result.artifacts[0].path)"

        # Producer writes task-owned deliverable under deliverableRoot before result publication -> passes in-place validation
        $deliveredPath = Join-Path $deliverableDir $result.artifacts[0].path
        New-Item -ItemType Directory -Path (Split-Path -Parent $deliveredPath) -Force | Out-Null
        Set-Content -LiteralPath $deliveredPath -Value 'Task-owned deliverable written under deliverableRoot.' -Encoding utf8NoBOM

        $validCheck = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{
            manifest         = $manifest
            request          = $request
            result           = $result
            workspaceRoot    = $workRoot
            preExistingPaths = @($preExistingRel)
        }
        $validCheck.Status | Should -Be 'ok' -Because ($validCheck | ConvertTo-Json -Depth 10)
        @($validCheck.Issues) | Should -BeNullOrEmpty
        $validCheck.TrustedProvenance.bindingId | Should -Be 'legacy-1.0'
        $validCheck.TrustedProvenance.connectorId | Should -Be $manifest.connectorId

        # Claiming a pre-existing file path is rejected as existing-file-collision
        $collisionResult = Get-ExampleJson -Name 'result-envelope.sample.json'
        $collisionResult.artifacts[0].path = $preExistingRel
        $collisionCheck = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{
            manifest         = $manifest
            request          = $request
            result           = $collisionResult
            workspaceRoot    = $workRoot
            preExistingPaths = @($preExistingRel)
        }
        $collisionCheck.Status | Should -Be 'error'
        @($collisionCheck.Issues) | Should -Contain "existing-file-collision:$preExistingRel"

        # Duplicate artifact path in the same result is rejected
        $dupResult = Get-ExampleJson -Name 'result-envelope.sample.json'
        $dupResult.artifacts = @($dupResult.artifacts[0], $dupResult.artifacts[0])
        $dupCheck = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{
            manifest      = $manifest
            request       = $request
            result        = $dupResult
            workspaceRoot = $workRoot
        }
        $dupCheck.Status | Should -Be 'error'
        @($dupCheck.Issues) | Should -Contain "duplicate-artifact-path:$($result.artifacts[0].path)"
    }
}

Describe 'connector binding manifest fail-closed admission (NR-004)' {
    It 'fails closed on a blank ManifestPath' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-blank-manifest | acme-delivery-orchestrator-v3 |  | orchestrator | replace | role | role:developer/Gamma | Partner Developer |  |  | connector |
'@
        try {
            $result = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'connector:developer-blank-manifest'
            }
            $result.Status | Should -Be 'error'
            $result.Reason | Should -Be 'invalid-applicable-binding'
            @($result.Issues) | Should -Contain 'developer-blank-manifest:missing:manifestPath'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed when ManifestPath does not resolve to an existing file' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-missing-manifest | acme-delivery-orchestrator-v3 | docs/templates/connector-example/does-not-exist.manifest.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer |  |  | connector |
'@
        try {
            $result = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'connector:developer-missing-manifest'
            }
            $result.Status | Should -Be 'error'
            $result.Reason | Should -Be 'invalid-applicable-binding'
            @($result.Issues) | Should -Contain 'developer-missing-manifest:manifest-not-found'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed on an unreadable/malformed manifest file' {
        $malformedManifestPath = Join-Path ([System.IO.Path]::GetTempPath()) "malformed-manifest-$([guid]::NewGuid().ToString('N')).json"
        Set-Content -LiteralPath $malformedManifestPath -Value '{ "connectorId": "acme-delivery-orchestrator-v3", "roles": [ "developer", ' -NoNewline
        $teamPath = New-TempTeamFile -Content @"
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-malformed-manifest | acme-delivery-orchestrator-v3 | $($malformedManifestPath -replace '\\', '/') | orchestrator | replace | role | role:developer/Gamma | Partner Developer |  |  | connector |
"@
        try {
            $result = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'connector:developer-malformed-manifest'
            }
            $result.Status | Should -Be 'error'
            $result.Reason | Should -Be 'invalid-applicable-binding'
            @($result.Issues) | Should -Contain 'developer-malformed-manifest:manifest-parse-failed'
            @($result.Issues) | Should -Contain 'developer-malformed-manifest:manifest-unreadable'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $malformedManifestPath -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed when the manifest connectorId does not match the binding connectorId' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-connectorid-mismatch | wrong-connector-id | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer |  |  | connector |
'@
        try {
            $result = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'connector:developer-connectorid-mismatch'
            }
            $result.Status | Should -Be 'error'
            $result.Reason | Should -Be 'invalid-applicable-binding'
            @($result.Issues) | Should -Contain 'developer-connectorid-mismatch:manifest-connectorId-mismatch'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed when the manifest endpointKind does not match the binding endpointKind' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| developer | Gamma | Squad Implementor |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| developer-endpointkind-mismatch | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | agent | replace | role | role:developer/Gamma | Partner Developer |  |  | connector |
'@
        try {
            $result = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'developer'
                memberName = 'Gamma'
                execution = 'connector:developer-endpointkind-mismatch'
            }
            $result.Status | Should -Be 'error'
            $result.Reason | Should -Be 'invalid-applicable-binding'
            @($result.Issues) | Should -Contain 'developer-endpointkind-mismatch:manifest-endpointKind-mismatch'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed when the target role is not authorized in the manifest roles list' {
        $teamPath = New-TempTeamFile -Content @'
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| architect | Ada | Squad Architect |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| architect-role-not-authorized | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:architect/Ada | Partner Architect |  |  | connector |
'@
        try {
            $result = Invoke-ResolveExecutionCli -Payload @{
                teamPath = $teamPath
                role = 'architect'
                memberName = 'Ada'
                execution = 'connector:architect-role-not-authorized'
            }
            $result.Status | Should -Be 'error'
            $result.Reason | Should -Be 'invalid-applicable-binding'
            @($result.Issues) | Should -Contain 'architect-role-not-authorized:manifest-role-missing:architect'
        }
        finally {
            Remove-Item -LiteralPath $teamPath -ErrorAction SilentlyContinue
        }
    }
}

Describe 'connector governance targets remain protected' -Tag 'Unit' {
    It 'refuses the retired coordinator target kind even for an orchestrator' {
        $manifest = Get-ExampleJson -Name 'manifest.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.1.1.sample.json'
        $manifest.roles | Should -Not -Contain 'coordinator'
        $request.targetKind = 'coordinator'
        (Test-SquadConnectorExchange -Manifest $manifest -Request $request -Result $result).Issues | Should -Contain 'request.invalid:targetKind'
        $cli = Invoke-DispatchHelperCli -Operation 'validate-exchange' -Payload @{ manifest = $manifest; request = $request; result = $result }
        $cli.Status | Should -Be 'error'
        $cli.Issues | Should -Contain 'request.invalid:targetKind'
    }

    It 'rejects governance role <_> in manifests, requests, results, and output slots' -ForEach @('scribe', 'coordinator', 'federation-coordinator', 'council') {
        foreach ($version in @('1.0', '1.1')) {
            $suffix = if ($version -eq '1.1') { '.1.1' } else { '' }
            $manifest = Get-ExampleJson -Name "manifest$suffix.json"
            $request = Get-ExampleJson -Name "delegation-request$suffix.sample.json"
            $result = Get-ExampleJson -Name "result-envelope$suffix.sample.json"
            $manifest.roles = @($_)
            $request.role = $_
            $result.role = $_
            (Test-SquadConnectorManifestShape -Manifest $manifest).Status | Should -Be 'error'
            (Test-SquadConnectorRequestShape -Request $request -SchemaVersion $version).Issues | Should -Contain 'invalid:reserved-role'
            (Test-SquadConnectorResultShape -Result $result -SchemaVersion $version).Issues | Should -Contain 'invalid:reserved-role'
        }
        $request = Get-ExampleJson -Name 'delegation-request.1.1.sample.json'
        $request.allowedOutputs[0].role = $_
        (Test-SquadConnectorRequestShape -Request $request -SchemaVersion '1.1').Issues | Should -Contain 'allowedOutputs.reserved-role'
    }

    It 'retains the internal Scribe when no connector binding exists' {
        $teamPath = New-TempTeamFile -Content "| Role | Member Name | Agent Name (Primary) |`n| --- | --- | --- |`n| scribe | Scribe | Squad Scribe |"
        try {
            $resolved = Resolve-SquadConnectorExecution -TeamPath $teamPath -Role 'scribe'
            $resolved.Status | Should -Be 'ok'
            $resolved.Choice | Should -Be 'original'
            $resolved.Agent | Should -Be 'Squad Scribe'
        }
        finally { Remove-Item -LiteralPath $teamPath }
    }
}

Describe 'connector skill security documentation' -Tag 'Unit' {
    It 'ships a registered model with explicit trust buckets and all STRIDE categories' {
        $modelPath = Join-Path $script:Root 'squad-src\.github\skills\squad\SECURITY.md'
        $registryPath = Join-Path $script:Root 'docs\security\security-model.md'
        $model = Get-Content -LiteralPath $modelPath -Raw
        $registry = Get-Content -LiteralPath $registryPath -Raw
        foreach ($field in @('title', 'description', 'author', 'ms.topic', 'ms.date', 'keywords', 'estimated_reading_time')) {
            $model | Should -Match "(?m)^$([regex]::Escape($field)):"
        }
        $outline = @([regex]::Matches($model, '(?m)^## (.+)\r?$') | ForEach-Object { $_.Groups[1].Value.Trim() })
        $outline | Should -Be @('Executive Summary', 'Contents', 'System Description', 'Trust Boundaries', 'Assets', 'Adversaries', 'Bucket B1: Configuration and Dispatch', 'Bucket B2: File Exchange and Persistence', 'Enterprise Readiness Gaps', 'References')
        foreach ($bucket in @('B1', 'B2')) {
            $body = [regex]::Match($model, "(?ms)^## Bucket ${bucket}:[^\n]*\n(?<body>.*?)(?=^## |\z)").Groups['body'].Value
            $categories = @([regex]::Matches($body, '(?m)^### (.+)\r?$') | ForEach-Object { $_.Groups[1].Value.Trim() })
            $categories | Should -Be @('Spoofing', 'Tampering', 'Repudiation', 'Information Disclosure', 'Denial of Service', 'Elevation of Privilege', 'Risk Rating')
        }
        $model | Should -Match 'flowchart TD'
        $model | Should -Not -Match '\.copilot-tracking/|session-state/'
        $registry | Should -Match 'squad-src/\.github/skills/squad/SECURITY\.md'
        $registry | Should -Match 'Primary residual gaps'
    }
}

Describe 'consumer agent and arbitrary additive connector examples' -Tag 'Unit' {
    It 'provides five parseable agent starters with a resolvable orchestrator worker list' {
        Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
        $agents = @(Get-ChildItem -LiteralPath (Join-Path $script:ExampleRoot 'agents') -Filter '*.agent.md' -File | ForEach-Object {
                Read-SquadArtifact -Path $_.FullName
            })
        $agents.Count | Should -Be 5
        $names = @($agents | ForEach-Object { $_.Meta['name'] })
        @($names | Sort-Object -Unique).Count | Should -Be 5
        foreach ($agent in $agents) {
            $agent.HasFront | Should -BeTrue
            $agent.Meta['name'] | Should -Not -BeNullOrEmpty
            $agent.Meta['description'] | Should -Not -BeNullOrEmpty
            $agent.Body | Should -Match '## Completion and boundaries'
        }

        $orchestrator = @($agents | Where-Object { $_.Meta['name'] -eq 'Consumer Implementation Orchestrator' })[0]
        @($orchestrator.Meta['agents']).Count | Should -Be 3
        foreach ($worker in $orchestrator.Meta['agents']) { $names | Should -Contain $worker }
    }

    It 'validates the single-agent manifests and the documented agent round trip' {
        foreach ($name in @('manifest.research-agent.1.1.json', 'manifest.implementation-agent.1.1.json', 'manifest.capability-assessor.1.1.json')) {
            $manifest = Get-ExampleJson -Name $name
            (Test-SquadConnectorManifestShape -Manifest $manifest).Status | Should -Be 'ok' -Because $name
            $manifest.endpointKind | Should -Be 'agent'
        }
        $manifest = Get-ExampleJson -Name 'manifest.research-agent.1.1.json'
        $request = Get-ExampleJson -Name 'delegation-request.agent.1.1.sample.json'
        $result = Get-ExampleJson -Name 'result-envelope.agent.1.1.sample.json'
        $result.PSObject.Properties.Name | Should -Not -Contain 'outputs'
        (Test-SquadConnectorExchange -Manifest $manifest -Request $request -Result $result).Status | Should -Be 'ok'
    }

    It 'resolves the documented <Role> endpoint <Binding> as member <Member>' -ForEach @(
        @{ Role = 'researcher'; Binding = 'research-org'; Member = 'Org Researcher' },
        @{ Role = 'developer'; Binding = 'implementation-org'; Member = 'Org Implementor' },
        @{ Role = 'developer'; Binding = 'developer-delivery-orchestrator'; Member = 'Partner Developer' },
        @{ Role = 'gcp'; Binding = 'gcp-assessor'; Member = 'GCP Assessor' },
        @{ Role = 'dotnet-practices'; Binding = 'dotnet-assessor'; Member = 'Dotnet Assessor' },
        @{ Role = 'data-quality'; Binding = 'data-quality-assessor'; Member = 'Data Assessor' }
    ) {
        $teamPath = Join-Path $script:ExampleRoot 'consumer-team.1.1.md'
        $resolved = Resolve-SquadConnectorExecution -TeamPath $teamPath -Role $Role -Execution "connector:$Binding"
        $resolved.Status | Should -Be 'ok' -Because ($resolved | ConvertTo-Json -Depth 10)
        $resolved.Agent | Should -Be 'Squad Connector'
        $resolved.MemberName | Should -Be $Member
        $resolved.BindingId | Should -Be $Binding
    }

    It 'uses the documented research and implementation defaults in autopilot without execution flags' {
        $teamPath = Join-Path $script:ExampleRoot 'consumer-team.1.1.md'
        $research = Invoke-ResolveExecutionCli -Payload @{ teamPath = $teamPath; role = 'researcher'; unattended = $true }
        $implementation = Invoke-ResolveExecutionCli -Payload @{ teamPath = $teamPath; role = 'developer'; unattended = $true }
        $research.Status | Should -Be 'ok'
        $research.Choice | Should -Be 'connector:research-org'
        $implementation.Status | Should -Be 'ok'
        $implementation.Choice | Should -Be 'connector:implementation-org'
        foreach ($role in @('gcp', 'dotnet-practices', 'data-quality')) {
            (Resolve-SquadConnectorExecution -TeamPath $teamPath -Role $role -Unattended $true).Status | Should -Be 'ok'
        }
    }

    It 'switches implementation to a persisted orchestrator default without changing the autopilot request' {
        $team = Get-ExampleText -Name 'consumer-team.1.1.md'
        $team = $team.Replace('| Org Implementor | | | connector |', '| Org Implementor | | | ask |')
        $team = $team.Replace('| Partner Developer | | | ask |', '| Partner Developer | | | connector |')
        $teamPath = New-TempTeamFile -Content $team
        try {
            $resolved = Invoke-ResolveExecutionCli -Payload @{ teamPath = $teamPath; role = 'developer'; unattended = $true }
            $resolved.Status | Should -Be 'ok'
            $resolved.Choice | Should -Be 'connector:developer-delivery-orchestrator'
            $resolved.EndpointKind | Should -Be 'orchestrator'
        }
        finally { Remove-Item -LiteralPath $teamPath }
    }

    It 'keeps bindings local after a simulated move to a federation member root' {
        $source = Join-Path $TestDrive 'single-squad'
        $members = Join-Path $TestDrive 'federation\members'
        New-Item -ItemType Directory -Path $source, $members -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:ExampleRoot 'consumer-team.1.1.md') -Destination (Join-Path $source 'team.md')
        $before = (Get-SquadConnectorRosterState -TeamPath (Join-Path $source 'team.md')).Bindings | ConvertTo-Json -Depth 8
        $member = Join-Path $members 'consumer'
        Move-Item -LiteralPath $source -Destination $member
        $teamPath = Join-Path $member 'team.md'
        ((Get-SquadConnectorRosterState -TeamPath $teamPath).Bindings | ConvertTo-Json -Depth 8) | Should -Be $before
        (Resolve-SquadConnectorExecution -TeamPath $teamPath -Role 'data-quality').MemberName | Should -Be 'Data Assessor'
        $otherTeam = Join-Path $TestDrive 'other-team.md'
        Set-Content -LiteralPath $otherTeam -Value "| Role | Member Name | Agent Name (Primary) |`n| --- | --- | --- |`n| developer | Gamma | Squad Implementor |"
        (Resolve-SquadConnectorExecution -TeamPath $otherTeam -Role 'developer' -Execution 'connector:implementation-org').Reason | Should -Be 'unknown-connector-binding'
    }

    It 'refuses connector targets for reserved governance identities' -ForEach @('scribe', 'council', 'coordinator') {
        $teamPath = New-TempTeamFile -Content @"
| Role | Member Name | Agent Name (Primary) |
| --- | --- | --- |
| $_ | Original | Squad Scribe |

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| reserved | acme-implementation-agent | docs/templates/connector-example/manifest.implementation-agent.1.1.json | agent | replace | role | role:$_/Original | External | | | connector |
"@
        try {
            $resolved = Resolve-SquadConnectorExecution -TeamPath $teamPath -Role $_ -Execution 'connector:reserved'
            $resolved.Status | Should -Be 'error'
            $resolved.Reason | Should -Be 'connector-protected-role'
            $roster = Get-SquadConnectorRosterState -TeamPath $teamPath
            $validation = Test-ApplicableBindingsLocal -Bindings $roster.Bindings -Members $roster.Members -TeamPath $teamPath
            $validation.Issues | Should -Contain 'reserved:invalid:reserved-role-target'
        }
        finally { Remove-Item -LiteralPath $teamPath }
    }
}
