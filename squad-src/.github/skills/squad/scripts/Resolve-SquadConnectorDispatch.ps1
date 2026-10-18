# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Deterministic connector role-mode resolver and envelope validator.
.DESCRIPTION
    Shared helper for connector role-mode contracts:
    * resolve member/binding/execution choice without first-row fallback
    * enforce `both` collision/admission guards
    * validate 1.0 vs 1.1 manifest/request/result shape gates
    * validate request/result binding (`taskId`, `connectorId`, `role`,
      `bindingId`) and `outputId` allowlist matching

    This script is intentionally side-effect free: it reads input and returns
    a structured result only.
.PARAMETER Operation
    Optional CLI operation:
    * `resolve-execution`
    * `validate-manifest`
    * `validate-request`
    * `validate-result`
    * `validate-exchange`
.PARAMETER InputPath
    Path to JSON input for `-Operation`.
.PARAMETER InputJson
    Raw JSON input for `-Operation` (alternative to `-InputPath`).
#>

[CmdletBinding(DefaultParameterSetName = 'Library')]
param(
    [Parameter(ParameterSetName = 'Run', Mandatory)]
    [ValidateSet('resolve-execution', 'validate-manifest', 'validate-request', 'validate-result', 'validate-exchange')]
    [string]$Operation,

    [Parameter(ParameterSetName = 'Run')]
    [string]$InputPath,

    [Parameter(ParameterSetName = 'Run')]
    [string]$InputJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ConnectorBoolLocal {
    param(
        [AllowNull()]$Value,
        [bool]$Default = $false
    )
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
    if ($text -match '^(?i:true|yes|1)$') { return $true }
    if ($text -match '^(?i:false|no|0)$') { return $false }
    return $Default
}

function Split-ConnectorCellsLocal {
    param([Parameter(Mandatory)][string]$Line)
    @($Line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim().Trim('`').Trim() })
}

function Get-MarkdownTablesFromPathLocal {
    param([Parameter(Mandatory)][string]$Path)

    $tables = [System.Collections.Generic.List[pscustomobject]]::new()
    $lines = [System.IO.File]::ReadAllLines($Path)
    $run = $null
    foreach ($line in ($lines + @(''))) {
        if ($line -match '^\s*\|') {
            if ($null -eq $run) { $run = [System.Collections.Generic.List[string]]::new() }
            $run.Add($line)
            continue
        }
        if ($null -eq $run) { continue }
        if ($run.Count -ge 2) {
            $header = Split-ConnectorCellsLocal -Line $run[0]
            $rows = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($rowLine in ($run | Select-Object -Skip 1)) {
                if ($rowLine -match '^\s*\|\s*:?-') { continue }
                $cells = Split-ConnectorCellsLocal -Line $rowLine
                $row = @{}
                for ($i = 0; $i -lt $header.Count; $i++) {
                    $row[$header[$i]] = if ($i -lt $cells.Count) { $cells[$i] } else { '' }
                }
                $rows.Add($row)
            }
            $tables.Add([pscustomobject]@{ Header = $header; Rows = $rows.ToArray() })
        }
        $run = $null
    }
    $tables.ToArray()
}

function ConvertTo-ConnectorPathKeyLocal {
    param([AllowEmptyString()][string]$Path)
    $normalized = ([string]$Path).Trim().Replace('\', '/').Trim()
    while ($normalized.Contains('//')) { $normalized = $normalized.Replace('//', '/') }
    $normalized = $normalized.TrimEnd('/')
    if (-not $normalized) { return '' }
    $normalized.ToLowerInvariant()
}

function Test-ConnectorRootSegmentsValidLocal {
    <#
    .SYNOPSIS
        Fails closed on `.`/`..` segments (and filesystem-equivalent all-dot or
        trailing-dot escapes) anywhere in a declared output root, before any
        containment or collision check is attempted.
    #>
    param([AllowEmptyString()][string]$Path)
    $text = ([string]$Path).Trim().Replace('\', '/')
    if (-not $text) { return $true }
    foreach ($segment in ($text -split '/')) {
        if (-not $segment) { continue }
        $trimmed = $segment.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed -match '^\.+$') { return $false }
        if ($trimmed -ne $trimmed.TrimEnd('.', ' ')) { return $false }
    }
    $true
}

function Test-ConnectorRootsCollideLocal {
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )
    if (-not (Test-ConnectorRootSegmentsValidLocal -Path $Left)) { return $true }
    if (-not (Test-ConnectorRootSegmentsValidLocal -Path $Right)) { return $true }
    $a = ConvertTo-ConnectorPathKeyLocal -Path $Left
    $b = ConvertTo-ConnectorPathKeyLocal -Path $Right
    if (-not $a -or -not $b) { return $false }
    if ($a -eq $b) { return $true }
    if ($a.StartsWith("$b/", [StringComparison]::Ordinal)) { return $true }
    if ($b.StartsWith("$a/", [StringComparison]::Ordinal)) { return $true }
    $false
}

function Get-ConnectorObjectPropertyNamesLocal {
    param([Parameter(Mandatory)]$Object)
    if ($null -eq $Object) { return @() }
    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys | ForEach-Object { [string]$_ })
    }
    @($Object.PSObject.Properties.Name)
}

function Get-ConnectorInputValueLocal {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()]$Default = $null
    )
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Test-ConnectorArrayLikeLocal {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return $false }
    return ($Value -is [System.Collections.IEnumerable])
}

function Test-ConnectorPathUnderRootLocal {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Candidate
    )
    if (-not (Test-ConnectorRootSegmentsValidLocal -Path $Root)) { return $false }
    $normalizedRoot = ConvertTo-ConnectorPathKeyLocal -Path $Root
    if (-not $normalizedRoot) { return $false }
    $resolved = ConvertTo-ConnectorPathKeyLocal -Path (Join-Path -Path $normalizedRoot -ChildPath $Candidate)
    if (-not $resolved) { return $false }
    return $resolved.StartsWith("$normalizedRoot/", [System.StringComparison]::Ordinal)
}

function Test-ConnectorRootContainedLocal {
    param(
        [Parameter(Mandatory)][string]$ParentRoot,
        [Parameter(Mandatory)][string]$ChildRoot
    )
    if (-not (Test-ConnectorRootSegmentsValidLocal -Path $ParentRoot)) { return $false }
    if (-not (Test-ConnectorRootSegmentsValidLocal -Path $ChildRoot)) { return $false }
    $parent = ConvertTo-ConnectorPathKeyLocal -Path $ParentRoot
    $child = ConvertTo-ConnectorPathKeyLocal -Path $ChildRoot
    if (-not $parent -or -not $child) { return $false }
    if ($child -eq $parent) { return $true }
    $child.StartsWith("$parent/", [System.StringComparison]::Ordinal)
}

function Get-ConnectorArtifactPathIssueLocal {
    param(
        [Parameter(Mandatory)][string]$DeliverableRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ArtifactPath
    )
    if (-not (Test-ConnectorRootSegmentsValidLocal -Path $DeliverableRoot)) { return 'invalid-deliverable-root' }
    $candidate = ([string]$ArtifactPath).Trim()
    if (-not $candidate) { return 'missing-path' }
    if ($candidate -match '^[A-Za-z]:[\\/]') { return 'absolute-path' }
    if ($candidate -match '^/') { return 'absolute-path' }
    if ($candidate -match '^\\\\' -or $candidate -match '^//') { return 'unc-path' }
    if ($candidate -match '^[A-Za-z]:') { return 'drive-letter' }
    $segments = @($candidate -split '[\\/]')
    if (@($segments | Where-Object { $_ -eq '..' }).Count -gt 0) { return 'path-traversal' }
    if ($candidate -match ':[^\\/:]') { return 'alternate-data-stream' }
    if (-not (Test-ConnectorPathUnderRootLocal -Root $DeliverableRoot -Candidate $candidate)) { return 'escapes-deliverable-root' }
    $extension = [System.IO.Path]::GetExtension($candidate).TrimStart('.').ToLowerInvariant()
    if ($extension -notin @('md', 'json', 'txt')) { return 'disallowed-extension' }
    $null
}

function Get-SquadConnectorRosterState {
    <#
    .SYNOPSIS
        Reads `team.md` and returns members + connector bindings.
    #>
    param([Parameter(Mandatory)][string]$TeamPath)

    $tables = @(Get-MarkdownTablesFromPathLocal -Path $TeamPath)
    $primaryHeaders = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent')
    $membersTable = @(
        $tables | Where-Object {
            $table = $_
            if ('Role' -notin $table.Header) { return $false }
            @($primaryHeaders | Where-Object { $_ -in $table.Header }).Count -gt 0
        } | Select-Object -First 1
    )
    if ($membersTable.Count -eq 0) {
        throw "Resolve-SquadConnectorDispatch: no Members table with Role and a primary-agent column found in '$TeamPath'."
    }

    $primaryHeader = @($primaryHeaders | Where-Object { $_ -in $membersTable[0].Header } | Select-Object -First 1)[0]
    $memberHeader = @('Member Name' | Where-Object { $_ -in $membersTable[0].Header } | Select-Object -First 1)[0]
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($row in $membersTable[0].Rows) {
        $role = ([string]$row['Role']).Trim().ToLowerInvariant()
        $agent = ([string]$row[$primaryHeader]).Trim()
        if (-not $role -or -not $agent -or $agent -in '—', '-') { continue }
        $member = if ($memberHeader) { ([string]$row[$memberHeader]).Trim() } else { '' }
        $rows.Add([pscustomobject]@{
                Role       = $role
                MemberName = $member
                Agent      = $agent
            })
    }

    $connectorHeader = @('Binding ID', 'Connector ID', 'Manifest', 'Endpoint Kind', 'Role Mode', 'Target Kind', 'Target', 'Member Name', 'Added Role', 'Aligned Role', 'Default Execution')
    $connectorTable = @(
        $tables | Where-Object {
            $table = $_
            @($connectorHeader | Where-Object { $_ -in $table.Header }).Count -eq $connectorHeader.Count
        } | Select-Object -First 1
    )

    $bindings = [System.Collections.Generic.List[pscustomobject]]::new()
    if ($connectorTable.Count -gt 0) {
        foreach ($binding in $connectorTable[0].Rows) {
            $bindingId = ([string]$binding['Binding ID']).Trim().Trim('`').Trim()
            if (-not $bindingId -or $bindingId -in '—', '-') { continue }
            $bindings.Add([pscustomobject]@{
                    BindingId        = $bindingId
                    ConnectorId      = ([string]$binding['Connector ID']).Trim().Trim('`').Trim()
                    ManifestPath     = ([string]$binding['Manifest']).Trim().Trim('`').Trim()
                    EndpointKind     = ([string]$binding['Endpoint Kind']).Trim().Trim('`').Trim().ToLowerInvariant()
                    RoleMode         = ([string]$binding['Role Mode']).Trim().Trim('`').Trim().ToLowerInvariant()
                    TargetKind       = ([string]$binding['Target Kind']).Trim().Trim('`').Trim().ToLowerInvariant()
                    Target           = ([string]$binding['Target']).Trim().Trim('`').Trim()
                    MemberName       = ([string]$binding['Member Name']).Trim().Trim('`').Trim()
                    AddedRole        = ([string]$binding['Added Role']).Trim().Trim('`').Trim().ToLowerInvariant()
                    AlignedRole      = ([string]$binding['Aligned Role']).Trim().Trim('`').Trim().ToLowerInvariant()
                    DefaultExecution = ([string]$binding['Default Execution']).Trim().Trim('`').Trim().ToLowerInvariant()
                })
        }
    }

    [pscustomobject]@{
        Members        = $rows.ToArray()
        Bindings       = $bindings.ToArray()
        HasBindings    = ($connectorTable.Count -gt 0)
        ConnectorTable = if ($connectorTable.Count -gt 0) { $connectorTable[0] } else { $null }
    }
}

function Test-ConnectorGovernanceRoleLocal {
    param([AllowNull()][string]$Role)
    ([string]$Role).Trim().ToLowerInvariant() -in @('scribe', 'coordinator', 'federation-coordinator', 'council')
}

function Get-ConnectorTargetRoleLocal {
    param([AllowEmptyString()][string]$Target)
    $text = ([string]$Target).Trim()
    if (-not $text) {
        return [pscustomobject]@{ Kind = 'invalid'; Role = ''; MemberName = '' }
    }
    if ($text -match '^(?i)role:(?<role>[a-z0-9-]+)(?:/(?<member>.+))?$') {
        return [pscustomobject]@{
            Kind       = 'role'
            Role       = $Matches['role'].ToLowerInvariant()
            MemberName = ($Matches['member'] | ForEach-Object { ([string]$_).Trim() } | Select-Object -First 1)
        }
    }
    [pscustomobject]@{ Kind = 'invalid'; Role = ''; MemberName = '' }
}

function Get-ApplicableBindingsForMemberRowLocal {
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Bindings
    )
    $role = ([string]$Row.Role).Trim().ToLowerInvariant()
    $member = ([string]$Row.MemberName).Trim()
    $agent = ([string]$Row.Agent).Trim()
    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($binding in $Bindings) {
        if ($binding.RoleMode -eq 'add') {
            if ($agent -ceq 'Squad Connector' -and $binding.AddedRole -eq $role -and $binding.MemberName -ceq $member) {
                $matches.Add($binding)
            }
            continue
        }
        if ($binding.RoleMode -ne 'replace') { continue }
        if ($binding.TargetKind -eq 'role') {
            $target = Get-ConnectorTargetRoleLocal -Target $binding.Target
            if ($target.Kind -ne 'role') { continue }
            if ($target.Role -ne $role) { continue }
            if ($target.MemberName -and $target.MemberName -cne $member) { continue }
            $matches.Add($binding)
            continue
        }
    }
    $matches.ToArray()
}

function Get-ConnectorBindingIssuesLocal {
    param(
        [Parameter(Mandatory)]$Binding,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Members,
        [Parameter(Mandatory)][string]$TeamPath,
        [Parameter(Mandatory)][hashtable]$ManifestCache
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $bindingId = ([string]$Binding.BindingId).Trim()
    $connectorId = ([string]$Binding.ConnectorId).Trim()
    $endpointKind = ([string]$Binding.EndpointKind).Trim().ToLowerInvariant()
    $roleMode = ([string]$Binding.RoleMode).Trim().ToLowerInvariant()
    $targetKind = ([string]$Binding.TargetKind).Trim().ToLowerInvariant()
    $targetValue = ([string]$Binding.Target).Trim()
    $memberName = ([string]$Binding.MemberName).Trim()
    $addedRole = ([string]$Binding.AddedRole).Trim().ToLowerInvariant()
    $alignedRole = ([string]$Binding.AlignedRole).Trim().ToLowerInvariant()
    $defaultExecution = ([string]$Binding.DefaultExecution).Trim().ToLowerInvariant()
    $target = Get-ConnectorTargetRoleLocal -Target $targetValue

    if (-not $bindingId) { $issues.Add('missing:bindingId') }
    elseif ($bindingId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $issues.Add('invalid:bindingId') }
    if (-not $connectorId) { $issues.Add('missing:connectorId') }
    if ($endpointKind -notin @('agent', 'orchestrator')) { $issues.Add('invalid:endpointKind') }
    if ($roleMode -notin @('replace', 'add')) { $issues.Add('invalid:roleMode') }
    if ($targetKind -ne 'role') { $issues.Add('invalid:targetKind') }
    if ($defaultExecution -notin @('original', 'connector', 'ask', 'both')) { $issues.Add('invalid:defaultExecution') }

    if ($targetKind -eq 'role' -and $target.Kind -ne 'role') { $issues.Add('invalid:target') }
    if (Test-ConnectorGovernanceRoleLocal -Role $target.Role) { $issues.Add('invalid:reserved-role-target') }
    if (Test-ConnectorGovernanceRoleLocal -Role $addedRole) { $issues.Add('invalid:reserved-added-role') }
    if (Test-ConnectorGovernanceRoleLocal -Role $alignedRole) { $issues.Add('invalid:reserved-aligned-role') }

    if ($roleMode -eq 'replace') {
        if (-not $memberName) { $issues.Add('missing:memberName') }
    }
    if ($roleMode -eq 'add') {
        if (-not $memberName) { $issues.Add('missing:memberName') }
        if (-not $addedRole) { $issues.Add('missing:addedRole') }
        elseif ($addedRole -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $issues.Add('invalid:addedRole') }
        if (-not $alignedRole) { $issues.Add('missing:alignedRole') }
        if ($targetKind -ne 'role' -or $target.Kind -ne 'role') { $issues.Add('invalid:add-target') }
        elseif ($target.Role -and $addedRole -and $target.Role -ne $addedRole) { $issues.Add('invalid:add-target-role-mismatch') }
        if ($target.MemberName -and $memberName -and $target.MemberName -cne $memberName) { $issues.Add('invalid:add-target-member-mismatch') }
        if ($defaultExecution -in @('original', 'both')) { $issues.Add('invalid:defaultExecution-for-add') }
    }

    $internalRows = @($Members | Where-Object { ([string]$_.Agent).Trim() -cne 'Squad Connector' })
    if ($targetKind -eq 'role' -and $target.Kind -eq 'role') {
        $targetRows = @($internalRows | Where-Object { ([string]$_.Role).Trim().ToLowerInvariant() -eq $target.Role })
        if ($target.MemberName) {
            $targetRows = @($targetRows | Where-Object { ([string]$_.MemberName).Trim() -ceq $target.MemberName })
        }
        if ($roleMode -eq 'replace' -and -not $target.MemberName -and $targetRows.Count -gt 1) {
            $issues.Add('ambiguous:replace-target-member-required')
        }
        if ($memberName -and @($targetRows | Where-Object { ([string]$_.MemberName).Trim() -ceq $memberName }).Count -gt 0) {
            $issues.Add('invalid:memberName-collides-with-target')
        }
    }

    $manifestPath = ([string]$Binding.ManifestPath).Trim()
    if (-not $manifestPath) {
        $issues.Add('missing:manifestPath')
    }
    else {
        $resolvedManifestPath = $manifestPath
        if (-not [System.IO.Path]::IsPathRooted($manifestPath)) {
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                $resolvedManifestPath = (Resolve-Path -LiteralPath $manifestPath).Path
            }
            else {
                $resolvedManifestPath = Join-Path -Path (Split-Path -Parent $TeamPath) -ChildPath $manifestPath
            }
        }
        if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
            # Fail closed: an applicable binding may never be admitted as `ok` against a
            # manifest path that does not resolve to a readable file (NR-004).
            $issues.Add('manifest-not-found')
        }
        else {
            if (-not $ManifestCache.ContainsKey($resolvedManifestPath)) {
                try {
                    $manifestJson = Get-Content -LiteralPath $resolvedManifestPath -Raw
                    $ManifestCache[$resolvedManifestPath] = $manifestJson | ConvertFrom-Json -AsHashtable -Depth 64
                }
                catch {
                    $ManifestCache[$resolvedManifestPath] = $null
                    $issues.Add('manifest-parse-failed')
                }
            }
            $manifest = $ManifestCache[$resolvedManifestPath]
            if (-not $manifest) {
                $issues.Add('manifest-unreadable')
            }
            else {
                $manifestShape = Test-SquadConnectorManifestShape -Manifest $manifest
                foreach ($shapeIssue in @($manifestShape.Issues)) { $issues.Add("manifest-shape:$shapeIssue") }

                $manifestConnectorId = ([string](Get-ConnectorInputValueLocal -Object $manifest -Name 'connectorId' -Default '')).Trim()
                if (-not $manifestConnectorId) {
                    $issues.Add('manifest-missing:connectorId')
                }
                elseif ($connectorId -and $manifestConnectorId -cne $connectorId) {
                    $issues.Add('manifest-connectorId-mismatch')
                }

                $manifestEndpointKind = ([string](Get-ConnectorInputValueLocal -Object $manifest -Name 'endpointKind' -Default '')).Trim().ToLowerInvariant()
                if (-not $manifestEndpointKind) {
                    $issues.Add('manifest-missing:endpointKind')
                }
                elseif ($endpointKind -and $manifestEndpointKind -ne $endpointKind) {
                    $issues.Add('manifest-endpointKind-mismatch')
                }

                $manifestRoles = @((Get-ConnectorInputValueLocal -Object $manifest -Name 'roles' -Default @()) | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
                if ($manifestRoles.Count -eq 0) {
                    $issues.Add('manifest-missing:roles')
                }
                else {
                    if ($roleMode -eq 'replace' -and $targetKind -eq 'role' -and $target.Role -and $manifestRoles -notcontains $target.Role) {
                        $issues.Add("manifest-role-missing:$($target.Role)")
                    }
                    if ($roleMode -eq 'add' -and $addedRole -and $manifestRoles -notcontains $addedRole) {
                        $issues.Add("manifest-role-missing:$addedRole")
                    }
                }
            }
        }
    }

    $issues.ToArray()
}

function Test-ApplicableBindingsLocal {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Bindings,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Members,
        [Parameter(Mandatory)][string]$TeamPath
    )

    $manifestCache = @{}
    $issues = [System.Collections.Generic.List[string]]::new()
    foreach ($binding in @($Bindings)) {
        $bindingId = ([string]$binding.BindingId).Trim()
        $bindingLabel = if ($bindingId) { $bindingId } else { '<missing-binding-id>' }
        foreach ($issue in @(Get-ConnectorBindingIssuesLocal -Binding $binding -Members $Members -TeamPath $TeamPath -ManifestCache $manifestCache)) {
            $issues.Add(("{0}:{1}" -f $bindingLabel, $issue))
        }
    }

    [pscustomobject]@{
        Status = if ($issues.Count -eq 0) { 'ok' } else { 'error' }
        Issues = $issues.ToArray()
    }
}

function Test-BothOutputIndependenceLocal {
    param([AllowEmptyCollection()][object[]]$AllowedOutputs)

    $outputs = @($AllowedOutputs)
    if ($outputs.Count -lt 2) {
        return [pscustomobject]@{ Status = 'error'; Reason = 'both-missing-independent-outputs' }
    }

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $outputs) {
        $outputId = ([string]$item.outputId).Trim()
        $root = ([string]$item.deliverableRoot).Trim()
        if (-not $outputId -or -not $root) {
            return [pscustomobject]@{ Status = 'error'; Reason = 'both-missing-independent-outputs' }
        }
        if (-not $ids.Add($outputId)) {
            return [pscustomobject]@{ Status = 'error'; Reason = 'both-output-id-collision' }
        }
        if (-not (Test-ConnectorRootSegmentsValidLocal -Path $root)) {
            return [pscustomobject]@{ Status = 'error'; Reason = 'both-output-root-invalid-segments' }
        }
        $roots.Add($root)
    }

    for ($i = 0; $i -lt $roots.Count; $i++) {
        for ($j = $i + 1; $j -lt $roots.Count; $j++) {
            if (Test-ConnectorRootsCollideLocal -Left $roots[$i] -Right $roots[$j]) {
                return [pscustomobject]@{ Status = 'error'; Reason = 'both-output-root-collision' }
            }
        }
    }

    [pscustomobject]@{ Status = 'ok'; Reason = 'both' }
}

function Resolve-SquadConnectorExecution {
    <#
    .SYNOPSIS
        Resolves role member + connector binding + execution mode together.
    .DESCRIPTION
        Enforces contract precedence and fail-closed ambiguity behavior:
        explicit `owner` and explicit `connector:<binding-id>` can disambiguate;
        otherwise ambiguity returns `clarify` in interactive mode and `error`
        in unattended mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TeamPath,
        [Parameter(Mandatory)][string]$Role,
        [AllowNull()][string]$Owner,
        [AllowNull()][string]$MemberName,
        [AllowNull()][string]$Execution,
        [AllowEmptyCollection()][object[]]$AllowedOutputs = @(),
        [bool]$Unattended = $false,
        [bool]$ParallelEligible = $false,
        [bool]$CouncilDispatch = $false,
        [bool]$AdmissionApproved = $false
    )

    $roster = Get-SquadConnectorRosterState -TeamPath $TeamPath
    $roleKey = ([string]$Role).Trim().ToLowerInvariant()
    if ((Test-ConnectorGovernanceRoleLocal -Role $roleKey) -and $Execution -and $Execution -ne 'original') {
        return [pscustomobject]@{ Status = 'error'; Reason = 'connector-protected-role'; Role = $roleKey }
    }
    $rows = @($roster.Members | Where-Object { $_.Role -eq $roleKey })
    if ($rows.Count -eq 0) {
        return [pscustomobject]@{ Status = 'error'; Reason = 'role-not-found'; Role = $roleKey }
    }

    $ownerHint = ''
    if ($Owner) { $ownerHint = ([string]$Owner).Trim() }
    elseif ($MemberName) { $ownerHint = ([string]$MemberName).Trim() }
    if ($ownerHint) {
        $rows = @($rows | Where-Object { ([string]$_.MemberName).Trim() -ceq $ownerHint })
        if ($rows.Count -eq 0) {
            return [pscustomobject]@{ Status = 'error'; Reason = 'member-not-found'; Role = $roleKey; Owner = $ownerHint }
        }
    }

    $explicitBindingId = $null
    if ($Execution -and $Execution -like 'connector:*') {
        $explicitBindingId = ([string]$Execution).Substring('connector:'.Length).Trim()
        $rows = @($rows | Where-Object {
                @((Get-ApplicableBindingsForMemberRowLocal -Row $_ -Bindings @($roster.Bindings)) | Where-Object BindingId -eq $explicitBindingId).Count -gt 0
            })
        if ($rows.Count -eq 0) {
            return [pscustomobject]@{ Status = 'error'; Reason = 'unknown-connector-binding'; BindingId = $explicitBindingId; Role = $roleKey }
        }
    }

    if ($rows.Count -gt 1) {
        $hasConnectorCandidate = @($rows | Where-Object { ([string]$_.Agent).Trim() -ceq 'Squad Connector' }).Count -gt 0
        $hasApplicableBinding = @($rows | ForEach-Object { Get-ApplicableBindingsForMemberRowLocal -Row $_ -Bindings @($roster.Bindings) }).Count -gt 0
        if (-not $Execution -and -not $hasConnectorCandidate -and -not $hasApplicableBinding) {
            # CONN-24: when neither applicable connector bindings nor an execution override exists,
            # preserve ordinary member selection (first matching internal row in document order).
            $rows = @($rows[0])
        }
        elseif ($Unattended) {
            return [pscustomobject]@{
                Status  = 'error'
                Reason  = 'unattended-member-ambiguity'
                Role    = $roleKey
                Members = @($rows | ForEach-Object { $_.MemberName })
            }
        }
        else {
            return [pscustomobject]@{
                Status  = 'clarify'
                Reason  = 'interactive-member-ambiguity'
                Role    = $roleKey
                Members = @($rows | ForEach-Object { $_.MemberName })
            }
        }
    }

    $row = $rows[0]
    $applicable = @(Get-ApplicableBindingsForMemberRowLocal -Row $row -Bindings @($roster.Bindings))
    $originalRow = if (([string]$row.Agent).Trim() -cne 'Squad Connector') { $row } else { $null }

    if (-not $CouncilDispatch -and $applicable.Count -gt 0) {
        # NR-003: council dispatch never gates on binding validity here. Every execution
        # branch that can actually hand work to a connector on a council route already
        # checks `$CouncilDispatch` itself and refuses explicitly; a council route that
        # falls through to the canonical internal original (below) must never be blocked
        # by a connector default/overlay/binding that happens to be invalid or missing.
        $bindingValidation = Test-ApplicableBindingsLocal -Bindings @($applicable) -Members @($roster.Members) -TeamPath $TeamPath
        if ($bindingValidation.Status -ne 'ok') {
            return [pscustomobject]@{
                Status            = 'error'
                Reason            = 'invalid-applicable-binding'
                Role              = $roleKey
                MemberName        = $row.MemberName
                ApplicableBinding = @($applicable | ForEach-Object { $_.BindingId })
                Issues            = @($bindingValidation.Issues)
            }
        }
    }

    $validateBoth = {
        param($Binding)
        if ($CouncilDispatch) { return [pscustomobject]@{ Status = 'error'; Reason = 'both-refused-council' } }
        if (-not $ParallelEligible) { return [pscustomobject]@{ Status = 'error'; Reason = 'both-not-parallel-eligible' } }
        if (-not $AdmissionApproved) { return [pscustomobject]@{ Status = 'error'; Reason = 'both-admission-refused' } }
        return (Test-BothOutputIndependenceLocal -AllowedOutputs $AllowedOutputs)
    }

    if ($Execution) {
        if ($Execution -eq 'original') {
            if (-not $originalRow) {
                return [pscustomobject]@{ Status = 'error'; Reason = 'original-missing-internal-member'; Role = $roleKey; MemberName = $row.MemberName }
            }
            return [pscustomobject]@{
                Status            = 'ok'
                Reason            = 'explicit-original'
                Choice            = 'original'
                Role              = $roleKey
                MemberName        = $originalRow.MemberName
                Agent             = $originalRow.Agent
                ApplicableBinding = @($applicable | ForEach-Object { $_.BindingId })
            }
        }
        if ($Execution -eq 'both') {
            if (-not $originalRow) {
                return [pscustomobject]@{ Status = 'error'; Reason = 'both-missing-internal-original'; Role = $roleKey; MemberName = $row.MemberName }
            }
            $connectorBinding = $null
            if ($explicitBindingId) {
                $connectorBinding = @($applicable | Where-Object BindingId -eq $explicitBindingId | Select-Object -First 1)[0]
            }
            elseif ($applicable.Count -eq 1) {
                $connectorBinding = $applicable[0]
            }
            elseif ($applicable.Count -gt 1) {
                if ($Unattended) {
                    return [pscustomobject]@{ Status = 'error'; Reason = 'unattended-binding-ambiguity'; Role = $roleKey; MemberName = $row.MemberName }
                }
                return [pscustomobject]@{ Status = 'clarify'; Reason = 'interactive-binding-ambiguity'; Role = $roleKey; MemberName = $row.MemberName }
            }
            if (-not $connectorBinding) {
                return [pscustomobject]@{ Status = 'error'; Reason = 'both-missing-connector-binding'; Role = $roleKey; MemberName = $row.MemberName }
            }
            $both = & $validateBoth $connectorBinding
            if ($both.Status -ne 'ok') { return $both }
            return [pscustomobject]@{
                Status             = 'ok'
                Reason             = 'explicit-both'
                Choice             = 'both'
                Role               = $roleKey
                MemberName         = $originalRow.MemberName
                Agent              = $originalRow.Agent
                BindingId          = if ($connectorBinding) { $connectorBinding.BindingId } else { '' }
                ConnectorId        = if ($connectorBinding) { $connectorBinding.ConnectorId } else { '' }
                EndpointKind       = if ($connectorBinding) { $connectorBinding.EndpointKind } else { '' }
                RoleMode           = if ($connectorBinding) { $connectorBinding.RoleMode } else { '' }
                TargetKind         = if ($connectorBinding) { $connectorBinding.TargetKind } else { '' }
                BindingTarget      = if ($connectorBinding) { $connectorBinding.Target } else { '' }
                ConnectorAgent     = 'Squad Connector'
                ConnectorMemberName = if ($connectorBinding) { $connectorBinding.MemberName } else { '' }
            }
        }
        if ($Execution -like 'connector:*') {
            if ($CouncilDispatch) { return [pscustomobject]@{ Status = 'error'; Reason = 'connector-refused-council' } }
            $bindingId = ([string]$Execution).Substring('connector:'.Length).Trim()
            $match = @($applicable | Where-Object BindingId -eq $bindingId)
            if ($match.Count -ne 1) { return [pscustomobject]@{ Status = 'error'; Reason = 'unknown-connector-binding'; BindingId = $bindingId } }
            return [pscustomobject]@{
                # NR-001: a connector dispatch exposes its own distinct connector identity
                # (`Agent='Squad Connector'`, the binding's own `MemberName`) rather than
                # reusing the internal role-row identity it is replacing/defaulting to. This
                # keeps the internal and connector units separately attributable and matches
                # what `Write-SquadHandoff.ps1` requires for a connector history record.
                Status        = 'ok'
                Reason        = 'explicit-connector'
                Choice        = "connector:$bindingId"
                Role          = $roleKey
                MemberName    = $match[0].MemberName
                Agent         = 'Squad Connector'
                BindingId     = $match[0].BindingId
                ConnectorId   = $match[0].ConnectorId
                BindingTarget = $match[0].Target
                EndpointKind  = $match[0].EndpointKind
                RoleMode      = $match[0].RoleMode
                TargetKind    = $match[0].TargetKind
            }
        }
        return [pscustomobject]@{ Status = 'error'; Reason = 'invalid-execution-choice'; Choice = $Execution }
    }

    if ($CouncilDispatch) {
        # NR-003: normal council routing always selects the validated canonical internal
        # original and ignores connector defaults, `ask`, missing/invalid overlays, and
        # replacement bindings. Only an explicit `execution=connector:*`/`execution=both`
        # request (handled above, before this point) remains refused for council dispatch.
        if (-not $originalRow) {
            return [pscustomobject]@{ Status = 'error'; Reason = 'council-requires-internal-original'; Role = $roleKey; MemberName = $row.MemberName }
        }
        return [pscustomobject]@{
            Status     = 'ok'
            Reason     = 'council-canonical-original'
            Choice     = 'original'
            Role       = $roleKey
            MemberName = $originalRow.MemberName
            Agent      = $originalRow.Agent
        }
    }

    if (-not $roster.HasBindings -or $applicable.Count -eq 0) {
        if (-not $originalRow) {
            return [pscustomobject]@{ Status = 'error'; Reason = 'original-missing-internal-member'; Role = $roleKey; MemberName = $row.MemberName }
        }
        return [pscustomobject]@{
            Status     = 'ok'
            Reason     = 'no-applicable-binding'
            Choice     = 'original'
            Role       = $roleKey
            MemberName = $originalRow.MemberName
            Agent      = $originalRow.Agent
        }
    }

    $defaults = @($applicable | Where-Object { $_.DefaultExecution -and $_.DefaultExecution -ne 'ask' })
    if ($defaults.Count -eq 1) {
        $default = [string]$defaults[0].DefaultExecution
        if ($default -eq 'connector') {
            # NR-001: expose the connector's own identity, not the internal role-row
            # identity it is replacing/defaulting to (CouncilDispatch is already handled
            # and returned above, so this branch is only reached for non-council routes).
            return [pscustomobject]@{
                Status        = 'ok'
                Reason        = 'binding-default-connector'
                Choice        = "connector:$($defaults[0].BindingId)"
                Role          = $roleKey
                MemberName    = $defaults[0].MemberName
                Agent         = 'Squad Connector'
                BindingId     = $defaults[0].BindingId
                ConnectorId   = $defaults[0].ConnectorId
                EndpointKind  = $defaults[0].EndpointKind
                BindingTarget = $defaults[0].Target
                RoleMode      = $defaults[0].RoleMode
                TargetKind    = $defaults[0].TargetKind
            }
        }
        if ($default -eq 'both') {
            if (-not $originalRow) {
                return [pscustomobject]@{ Status = 'error'; Reason = 'both-missing-internal-original'; Role = $roleKey; MemberName = $row.MemberName }
            }
            $both = & $validateBoth $defaults[0]
            if ($both.Status -ne 'ok') { return $both }
            return [pscustomobject]@{
                Status              = 'ok'
                Reason              = 'binding-default-both'
                Choice              = 'both'
                Role                = $roleKey
                MemberName          = $originalRow.MemberName
                Agent               = $originalRow.Agent
                BindingId           = $defaults[0].BindingId
                ConnectorId         = $defaults[0].ConnectorId
                EndpointKind        = $defaults[0].EndpointKind
                RoleMode            = $defaults[0].RoleMode
                TargetKind          = $defaults[0].TargetKind
                BindingTarget       = $defaults[0].Target
                ConnectorAgent      = 'Squad Connector'
                ConnectorMemberName = $defaults[0].MemberName
            }
        }
        if ($default -eq 'original' -and -not $originalRow) {
            return [pscustomobject]@{ Status = 'error'; Reason = 'original-missing-internal-member'; Role = $roleKey; MemberName = $row.MemberName }
        }
        return [pscustomobject]@{
            Status     = 'ok'
            Reason     = 'binding-default'
            Choice     = $default
            Role       = $roleKey
            MemberName = if ($originalRow) { $originalRow.MemberName } else { $row.MemberName }
            Agent      = if ($originalRow) { $originalRow.Agent } else { $row.Agent }
        }
    }

    if ($Unattended) {
        return [pscustomobject]@{
            Status     = 'error'
            Reason     = 'unattended-ambiguity'
            Role       = $roleKey
            MemberName = $row.MemberName
        }
    }
    [pscustomobject]@{
        Status     = 'clarify'
        Reason     = 'interactive-clarification'
        Role       = $roleKey
        MemberName = $row.MemberName
    }
}

function Get-ClosedSchemaIssuesLocal {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string[]]$Required,
        [string[]]$Optional = @(),
        [string]$Prefix = ''
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Object) {
        $issues.Add('object-null')
        return $issues.ToArray()
    }

    $present = @(Get-ConnectorObjectPropertyNamesLocal -Object $Object)
    foreach ($name in $Required) {
        if ($present -notcontains $name) {
            $issues.Add("missing:$Prefix$name")
        }
    }
    $allowed = @($Required + $Optional)
    $actionFields = [System.Collections.Generic.HashSet[string]]::new([string[]]@('command', 'exec', 'script', 'url', 'fetch', 'webhook'), [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $present) {
        if ($allowed -contains $name) { continue }
        if ($actionFields.Contains($name)) {
            $issues.Add("action-field-refused:$Prefix$name")
        }
        else {
            $issues.Add("extra:$Prefix$name")
        }
    }
    $issues.ToArray()
}

function Test-ConnectorArtifactsShapeLocal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Artifacts,
        [Parameter(Mandatory)][string]$Prefix
    )
    $issues = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-ConnectorArrayLikeLocal -Value $Artifacts)) {
        $issues.Add("$Prefix-not-array")
        return $issues.ToArray()
    }

    foreach ($artifact in @($Artifacts)) {
        foreach ($issue in (Get-ClosedSchemaIssuesLocal -Object $artifact -Required @('path', 'type') -Optional @() -Prefix "$Prefix.")) { $issues.Add($issue) }
        if ($null -eq $artifact) { continue }
        $type = ([string]$artifact.type).Trim().ToLowerInvariant()
        if ($type -and $type -notin @('md', 'json', 'txt')) { $issues.Add("$Prefix.invalid-type:$type") }
    }
    $issues.ToArray()
}

function Test-SquadConnectorManifestShape {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Manifest)

    $issues = [System.Collections.Generic.List[string]]::new()
    $base = @('connectorId', 'schemaVersion', 'transport', 'capabilities', 'roles', 'dropPath', 'deadlineMinutesDefault', 'retryCapDefault', 'contact', 'version')
    $version = ([string]$Manifest.schemaVersion).Trim()
    if ($version -eq '1.0') {
        foreach ($issue in (Get-ClosedSchemaIssuesLocal -Object $Manifest -Required $base)) { $issues.Add($issue) }
        if ((Get-ConnectorObjectPropertyNamesLocal -Object $Manifest) -contains 'endpointKind') { $issues.Add('v11-field-under-v10:endpointKind') }
    }
    elseif ($version -eq '1.1') {
        foreach ($issue in (Get-ClosedSchemaIssuesLocal -Object $Manifest -Required @($base + 'endpointKind'))) { $issues.Add($issue) }
        $endpointKind = ([string]$Manifest.endpointKind).Trim().ToLowerInvariant()
        if ($endpointKind -notin @('agent', 'orchestrator')) { $issues.Add('invalid:endpointKind') }
    }
    else {
        $issues.Add("unsupported-version:$version")
    }

    $transport = ([string]$Manifest.transport).Trim().ToLowerInvariant()
    if ($transport -ne 'file') { $issues.Add("invalid:transport:$transport") }

    if (-not (Test-ConnectorArrayLikeLocal -Value $Manifest.capabilities)) { $issues.Add('invalid:capabilities-not-array') }
    else {
        foreach ($item in @($Manifest.capabilities)) {
            if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace(([string]$item).Trim())) { $issues.Add('invalid:capabilities-item') }
        }
    }
    if (-not (Test-ConnectorArrayLikeLocal -Value $Manifest.roles)) { $issues.Add('invalid:roles-not-array') }
    else {
        foreach ($item in @($Manifest.roles)) {
            if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace(([string]$item).Trim())) { $issues.Add('invalid:roles-item') }
            elseif (Test-ConnectorGovernanceRoleLocal -Role $item) { $issues.Add("invalid:reserved-role:$item") }
        }
    }
    if ($Manifest.contact -isnot [string] -or [string]::IsNullOrWhiteSpace(([string]$Manifest.contact).Trim())) {
        $issues.Add('invalid:contact')
    }

    [pscustomobject]@{
        Status = if ($issues.Count -eq 0) { 'ok' } else { 'error' }
        Issues = $issues.ToArray()
    }
}

function Test-SquadConnectorRequestShape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][ValidateSet('1.0', '1.1')][string]$SchemaVersion
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $v10 = @('taskId', 'connectorId', 'role', 'deliverableRoot', 'task', 'deadline', 'retryCap', 'createdAt')
    $v11 = @('bindingId', 'targetKind', 'executionChoice', 'allowedOutputs')
    if (Test-ConnectorGovernanceRoleLocal -Role (Get-ConnectorInputValueLocal -Object $Request -Name 'role')) {
        $issues.Add('invalid:reserved-role')
    }

    if ($SchemaVersion -eq '1.0') {
        foreach ($issue in (Get-ClosedSchemaIssuesLocal -Object $Request -Required $v10)) { $issues.Add($issue) }
        foreach ($field in $v11) {
            if ((Get-ConnectorObjectPropertyNamesLocal -Object $Request) -contains $field) { $issues.Add("v11-field-under-v10:$field") }
        }
    }
    else {
        foreach ($issue in (Get-ClosedSchemaIssuesLocal -Object $Request -Required @($v10 + $v11))) { $issues.Add($issue) }
        if ((Get-ConnectorObjectPropertyNamesLocal -Object $Request) -contains 'targetKind') {
            $targetKind = ([string]$Request.targetKind).Trim().ToLowerInvariant()
            if ($targetKind -ne 'role') { $issues.Add('invalid:targetKind') }
        }
        if ((Get-ConnectorObjectPropertyNamesLocal -Object $Request) -contains 'executionChoice') {
            $executionChoice = ([string]$Request.executionChoice).Trim()
            $choiceLower = $executionChoice.ToLowerInvariant()
            if (-not $executionChoice) {
                $issues.Add('invalid:executionChoice')
            }
            elseif ($choiceLower -ne 'original' -and $choiceLower -ne 'both' -and -not $choiceLower.StartsWith('connector:')) {
                $issues.Add('invalid:executionChoice')
            }
            elseif ($choiceLower.StartsWith('connector:') -and -not $choiceLower.Substring('connector:'.Length).Trim()) {
                $issues.Add('invalid:executionChoice')
            }
        }
        if ((Get-ConnectorObjectPropertyNamesLocal -Object $Request) -contains 'allowedOutputs') {
            if (-not (Test-ConnectorArrayLikeLocal -Value $Request.allowedOutputs)) {
                $issues.Add('allowedOutputs-not-array')
            }
            else {
                foreach ($item in @($Request.allowedOutputs)) {
                    foreach ($issue in (Get-ClosedSchemaIssuesLocal -Object $item -Required @('outputId', 'role', 'deliverableRoot') -Optional @('memberName') -Prefix 'allowedOutputs.')) { $issues.Add($issue) }
                    if (Test-ConnectorGovernanceRoleLocal -Role (Get-ConnectorInputValueLocal -Object $item -Name 'role')) {
                        $issues.Add('allowedOutputs.reserved-role')
                    }
                }
            }
        }
    }

    [pscustomobject]@{
        Status = if ($issues.Count -eq 0) { 'ok' } else { 'error' }
        Issues = $issues.ToArray()
    }
}

function Test-SquadConnectorResultShape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][ValidateSet('1.0', '1.1')][string]$SchemaVersion,
        [ValidateSet('agent', 'orchestrator')][string]$EndpointKind = 'agent'
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $v10 = @('taskId', 'connectorId', 'role', 'status', 'artifacts', 'narrative', 'createdAt')
    $v11 = @('bindingId', 'outputs')
    if (Test-ConnectorGovernanceRoleLocal -Role (Get-ConnectorInputValueLocal -Object $Result -Name 'role')) {
        $issues.Add('invalid:reserved-role')
    }

    if ($SchemaVersion -eq '1.0') {
        foreach ($issue in (Get-ClosedSchemaIssuesLocal -Object $Result -Required $v10)) { $issues.Add($issue) }
        foreach ($field in $v11) {
            if ((Get-ConnectorObjectPropertyNamesLocal -Object $Result) -contains $field) { $issues.Add("v11-field-under-v10:$field") }
        }
    }
    else {
        $required = if ($EndpointKind -eq 'orchestrator') { @($v10 + $v11) } else { @($v10 + 'bindingId') }
        $optional = if ($EndpointKind -eq 'orchestrator') { @() } else { @('outputs') }
        foreach ($issue in (Get-ClosedSchemaIssuesLocal -Object $Result -Required $required -Optional $optional)) { $issues.Add($issue) }
        if ((Get-ConnectorObjectPropertyNamesLocal -Object $Result) -contains 'outputs') {
            if (-not (Test-ConnectorArrayLikeLocal -Value $Result.outputs)) {
                $issues.Add('outputs-not-array')
            }
            else {
                foreach ($item in @($Result.outputs)) {
                    foreach ($issue in (Get-ClosedSchemaIssuesLocal -Object $item -Required @('outputId', 'artifacts') -Prefix 'outputs.')) { $issues.Add($issue) }
                    foreach ($issue in (Test-ConnectorArtifactsShapeLocal -Artifacts $item.artifacts -Prefix 'outputs.artifacts')) { $issues.Add($issue) }
                }
            }
        }
    }
    foreach ($issue in (Test-ConnectorArtifactsShapeLocal -Artifacts $Result.artifacts -Prefix 'artifacts')) { $issues.Add($issue) }

    [pscustomobject]@{
        Status = if ($issues.Count -eq 0) { 'ok' } else { 'error' }
        Issues = $issues.ToArray()
    }
}

function Test-ConnectorReparsePointInChainLocal {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$TargetPath
    )
    $rootFull = [System.IO.Path]::GetFullPath($RootPath)
    $current = [System.IO.Path]::GetFullPath($TargetPath)
    while ($current -and $current.Length -ge $rootFull.Length) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
            if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                return $true
            }
        }
        if ($current.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = Split-Path -Path $current -Parent
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
    $false
}

function Test-SquadConnectorExchange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Result,
        [AllowEmptyString()][string]$WorkspaceRoot = '',
        [AllowEmptyCollection()][string[]]$PreExistingPaths = @()
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $manifestCheck = Test-SquadConnectorManifestShape -Manifest $Manifest
    foreach ($issue in @($manifestCheck.Issues)) { $issues.Add("manifest.$issue") }
    $schemaVersion = ([string]$Manifest.schemaVersion).Trim()
    if ($schemaVersion -notin @('1.0', '1.1')) {
        return [pscustomobject]@{ Status = 'error'; Issues = $issues.ToArray() }
    }

    $endpointKind = if ($schemaVersion -eq '1.1') { ([string]$Manifest.endpointKind).Trim().ToLowerInvariant() } else { 'agent' }
    if (-not $endpointKind) { $endpointKind = 'agent' }

    $requestCheck = Test-SquadConnectorRequestShape -Request $Request -SchemaVersion $schemaVersion
    foreach ($issue in @($requestCheck.Issues)) { $issues.Add("request.$issue") }
    $resultCheck = Test-SquadConnectorResultShape -Result $Result -SchemaVersion $schemaVersion -EndpointKind $endpointKind
    foreach ($issue in @($resultCheck.Issues)) { $issues.Add("result.$issue") }

    if ($Manifest.connectorId -and $Request.connectorId -and ([string]$Manifest.connectorId -cne [string]$Request.connectorId)) { $issues.Add('binding-mismatch:manifest-request:connectorId') }
    if ($Manifest.connectorId -and $Result.connectorId -and ([string]$Manifest.connectorId -cne [string]$Result.connectorId)) { $issues.Add('binding-mismatch:manifest-result:connectorId') }
    if ($Request.taskId -and $Result.taskId -and ([string]$Request.taskId -cne [string]$Result.taskId)) { $issues.Add('binding-mismatch:taskId') }
    if ($Request.connectorId -and $Result.connectorId -and ([string]$Request.connectorId -cne [string]$Result.connectorId)) { $issues.Add('binding-mismatch:connectorId') }
    if ($Request.role -and $Result.role -and ([string]$Request.role -cne [string]$Result.role)) { $issues.Add('binding-mismatch:role') }

    $manifestRoles = @((Get-ConnectorInputValueLocal -Object $Manifest -Name 'roles' -Default @()) | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    if ($manifestRoles.Count -gt 0) {
        $requestRole = ([string]$Request.role).Trim().ToLowerInvariant()
        $resultRole = ([string]$Result.role).Trim().ToLowerInvariant()
        if ($requestRole -and $manifestRoles -notcontains $requestRole) { $issues.Add("manifest-role-not-allowed:request:$requestRole") }
        if ($resultRole -and $manifestRoles -notcontains $resultRole) { $issues.Add("manifest-role-not-allowed:result:$resultRole") }
    }

    $resultStatus = ([string]$Result.status).Trim().ToLowerInvariant()
    if ($resultStatus -and $resultStatus -notin @('awaiting', 'completed', 'failed', 'unreachable')) {
        $issues.Add("unsupported-result-status:$resultStatus")
    }

    $declaredArtifactSlots = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($artifact in @($Result.artifacts)) {
        $path = if ($null -eq $artifact) { '' } else { [string]$artifact.path }
        $pathIssue = Get-ConnectorArtifactPathIssueLocal -DeliverableRoot ([string]$Request.deliverableRoot) -ArtifactPath $path
        if ($pathIssue) { $issues.Add("result-artifact-path:${pathIssue}:$path") }
        else {
            $declaredArtifactSlots.Add([pscustomobject]@{
                    Root     = [string]$Request.deliverableRoot
                    Path     = $path
                    OutputId = ''
                })
        }
    }

    if ($schemaVersion -eq '1.1') {
        if ($Request.bindingId -and $Result.bindingId -and ([string]$Request.bindingId -cne [string]$Result.bindingId)) { $issues.Add('binding-mismatch:bindingId') }
        $executionChoice = ([string]$Request.executionChoice).Trim().ToLowerInvariant()
        if ($executionChoice -eq 'original') {
            $issues.Add('execution-choice-result-mismatch:original')
        }
        elseif ($executionChoice.StartsWith('connector:')) {
            $expectedBinding = $executionChoice.Substring('connector:'.Length).Trim()
            if (-not $expectedBinding) {
                $issues.Add('execution-choice-invalid:connector-binding-id-missing')
            }
            elseif ($Request.bindingId -and $Request.bindingId -cne $expectedBinding) {
                $issues.Add('execution-choice-binding-mismatch:request')
            }
            elseif ($Result.bindingId -and $Result.bindingId -cne $expectedBinding) {
                $issues.Add('execution-choice-binding-mismatch:result')
            }
        }

        if ($endpointKind -eq 'orchestrator' -and @($Result.artifacts).Count -gt 0) {
            $issues.Add('orchestrator-top-level-artifacts-refused')
        }

        $allowedByOutputId = @{}
        $allowed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in @($Request.allowedOutputs)) {
            $outputId = ([string]$item.outputId).Trim()
            if (-not $outputId) { continue }
            if (-not $allowed.Add($outputId)) { $issues.Add("request-output-duplicate:$outputId") }
            $allowedByOutputId[$outputId] = [string]$item.deliverableRoot
            if (-not (Test-ConnectorRootContainedLocal -ParentRoot ([string]$Request.deliverableRoot) -ChildRoot ([string]$item.deliverableRoot))) {
                $issues.Add("request-output-root-outside-deliverable-root:$outputId")
            }
        }
        $resultSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in @((Get-ConnectorInputValueLocal -Object $Result -Name 'outputs' -Default @()))) {
            $outputId = ([string]$item.outputId).Trim()
            if (-not $outputId) { continue }
            if (-not $resultSeen.Add($outputId)) { $issues.Add("result-output-duplicate:$outputId") }
            if (-not $allowed.Contains($outputId)) {
                $issues.Add("undeclared-output-id:$outputId")
                continue
            }
            $root = [string]$allowedByOutputId[$outputId]
            foreach ($artifact in @($item.artifacts)) {
                $path = if ($null -eq $artifact) { '' } else { [string]$artifact.path }
                $pathIssue = Get-ConnectorArtifactPathIssueLocal -DeliverableRoot $root -ArtifactPath $path
                if ($pathIssue) { $issues.Add("declared-output-artifact-path:${outputId}:${pathIssue}:$path") }
                else {
                    $declaredArtifactSlots.Add([pscustomobject]@{
                            Root     = $root
                            Path     = $path
                            OutputId = $outputId
                        })
                }
            }
        }
    }

    $preExistingKeySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $requestRootKey = ConvertTo-ConnectorPathKeyLocal -Path ([string]$Request.deliverableRoot)
    foreach ($pre in @($PreExistingPaths)) {
        $preKey = ConvertTo-ConnectorPathKeyLocal -Path ([string]$pre)
        if (-not $preKey) { continue }
        [void]$preExistingKeySet.Add($preKey)
        if ($requestRootKey -and -not $preKey.StartsWith("$requestRootKey/", [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$preExistingKeySet.Add((ConvertTo-ConnectorPathKeyLocal -Path (Join-Path ([string]$Request.deliverableRoot) ([string]$pre))))
        }
    }

    $seenResolvedTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $totalBytes = 0L
    foreach ($slot in $declaredArtifactSlots) {
        $resolvedKey = ConvertTo-ConnectorPathKeyLocal -Path (Join-Path $slot.Root $slot.Path)
        if ($resolvedKey -and -not $seenResolvedTargets.Add($resolvedKey)) {
            $issues.Add("duplicate-artifact-path:$($slot.Path)")
        }
        if ($resolvedKey -and $preExistingKeySet.Contains($resolvedKey)) {
            $issues.Add("existing-file-collision:$($slot.Path)")
        }
        if ($WorkspaceRoot -and $resultStatus -eq 'completed') {
            $diskRoot = if ([System.IO.Path]::IsPathRooted($slot.Root)) { $slot.Root } else { Join-Path $WorkspaceRoot $slot.Root }
            $diskPath = Join-Path $diskRoot $slot.Path
            if (-not (Test-Path -LiteralPath $diskPath -PathType Leaf)) {
                $issues.Add("missing-delivered-artifact:$($slot.Path)")
            }
            else {
                if (Test-ConnectorReparsePointInChainLocal -RootPath $diskRoot -TargetPath $diskPath) {
                    $issues.Add("reparse-point-artifact:$($slot.Path)")
                }
                $length = (Get-Item -LiteralPath $diskPath -Force).Length
                if ($length -gt 1048576) {
                    $issues.Add("oversize-artifact:$($slot.Path)")
                }
                $totalBytes += $length
            }
        }
    }
    if ($totalBytes -gt 5242880) {
        $issues.Add('oversize-envelope-artifacts')
    }

    $trustedProvenance = $null
    if ($issues.Count -eq 0 -and $resultStatus -eq 'completed') {
        $roleKey = ([string]$Request.role).Trim().ToLowerInvariant()
        $trustedProvenance = [ordered]@{
            connectorId  = [string]$Manifest.connectorId
            bindingId    = if ($schemaVersion -eq '1.1') { [string]$Request.bindingId } else { 'legacy-1.0' }
            endpointKind = $endpointKind
            roleMode     = 'replace'
            targetKind   = 'role'
            target       = "role:$roleKey"
            verification = 'external-unverified'
            metering     = 'external-unmetered'
        }
    }

    [pscustomobject]@{
        Status            = if ($issues.Count -eq 0) { 'ok' } else { 'error' }
        Issues            = $issues.ToArray()
        TrustedProvenance = $trustedProvenance
    }
}

if ($PSCmdlet.ParameterSetName -eq 'Run') {
    try {
        if ([string]::IsNullOrWhiteSpace($InputPath) -and [string]::IsNullOrWhiteSpace($InputJson)) {
            throw "Resolve-SquadConnectorDispatch: provide -InputPath or -InputJson with -Operation."
        }
        if ($InputPath -and $InputJson) {
            throw "Resolve-SquadConnectorDispatch: specify either -InputPath or -InputJson, not both."
        }

        $json = if ($InputPath) { Get-Content -LiteralPath $InputPath -Raw } else { $InputJson }
        $input = $json | ConvertFrom-Json -AsHashtable -Depth 64
        $result = switch ($Operation) {
            'resolve-execution' {
                Resolve-SquadConnectorExecution `
                    -TeamPath ([string](Get-ConnectorInputValueLocal -Object $input -Name 'teamPath' -Default '')) `
                    -Role ([string](Get-ConnectorInputValueLocal -Object $input -Name 'role' -Default '')) `
                    -Owner ([string](Get-ConnectorInputValueLocal -Object $input -Name 'owner' -Default '')) `
                    -MemberName ([string](Get-ConnectorInputValueLocal -Object $input -Name 'memberName' -Default '')) `
                    -Execution ([string](Get-ConnectorInputValueLocal -Object $input -Name 'execution' -Default '')) `
                    -AllowedOutputs @((Get-ConnectorInputValueLocal -Object $input -Name 'allowedOutputs' -Default @())) `
                    -Unattended (Get-ConnectorBoolLocal -Value (Get-ConnectorInputValueLocal -Object $input -Name 'unattended')) `
                    -ParallelEligible (Get-ConnectorBoolLocal -Value (Get-ConnectorInputValueLocal -Object $input -Name 'parallelEligible')) `
                    -CouncilDispatch (Get-ConnectorBoolLocal -Value (Get-ConnectorInputValueLocal -Object $input -Name 'councilDispatch')) `
                    -AdmissionApproved (Get-ConnectorBoolLocal -Value (Get-ConnectorInputValueLocal -Object $input -Name 'admissionApproved'))
            }
            'validate-manifest' {
                Test-SquadConnectorManifestShape -Manifest (Get-ConnectorInputValueLocal -Object $input -Name 'manifest' -Default $null)
            }
            'validate-request' {
                Test-SquadConnectorRequestShape `
                    -Request (Get-ConnectorInputValueLocal -Object $input -Name 'request' -Default $null) `
                    -SchemaVersion ([string](Get-ConnectorInputValueLocal -Object $input -Name 'schemaVersion' -Default ''))
            }
            'validate-result' {
                Test-SquadConnectorResultShape `
                    -Result (Get-ConnectorInputValueLocal -Object $input -Name 'result' -Default $null) `
                    -SchemaVersion ([string](Get-ConnectorInputValueLocal -Object $input -Name 'schemaVersion' -Default '')) `
                    -EndpointKind ([string](Get-ConnectorInputValueLocal -Object $input -Name 'endpointKind' -Default ''))
            }
            'validate-exchange' {
                Test-SquadConnectorExchange `
                    -Manifest (Get-ConnectorInputValueLocal -Object $input -Name 'manifest' -Default $null) `
                    -Request (Get-ConnectorInputValueLocal -Object $input -Name 'request' -Default $null) `
                    -Result (Get-ConnectorInputValueLocal -Object $input -Name 'result' -Default $null) `
                    -WorkspaceRoot ([string](Get-ConnectorInputValueLocal -Object $input -Name 'workspaceRoot' -Default '')) `
                    -PreExistingPaths @((Get-ConnectorInputValueLocal -Object $input -Name 'preExistingPaths' -Default @()) | ForEach-Object { [string]$_ })
            }
        }
    }
    catch {
        $result = [pscustomobject]@{
            Status    = 'error'
            Reason    = 'operation-failed'
            Operation = $Operation
            Message   = $_.Exception.Message
        }
    }
    $result | ConvertTo-Json -Depth 32
}
