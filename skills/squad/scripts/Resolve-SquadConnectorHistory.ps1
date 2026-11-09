# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

# Shared, read-only identity validation for ledger regeneration and state assurance.
. (Join-Path $PSScriptRoot 'Resolve-SquadConnectorDispatch.ps1')

function Get-SquadConnectorBindingIdentityModel {
    param(
        [AllowEmptyString()][string]$TeamContent,
        [Parameter(Mandatory)][string]$TeamPath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [System.Collections.IDictionary]$ManifestSnapshots
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $columns = @('Binding ID', 'Connector ID', 'Manifest', 'Endpoint Kind', 'Role Mode',
        'Target Kind', 'Target', 'Member Name', 'Added Role', 'Aligned Role', 'Default Execution')
    $tables = @(Get-MarkdownTablesFromContentLocal -Content $TeamContent)
    $candidates = @($tables | Where-Object { 'Binding ID' -in $_.Header -or 'Connector ID' -in $_.Header -or 'Role Mode' -in $_.Header })
    $bindingTables = @($candidates | Where-Object {
            $table = $_
            @($columns | Where-Object { $_ -notin $table.Header }).Count -eq 0
        })
    if ($candidates.Count -ne $bindingTables.Count) { $issues.Add('incomplete-binding-columns') }
    if ($bindingTables.Count -gt 1) { $issues.Add('multiple-binding-tables') }
    $primaryHeaders = @('Agent Name (Primary)', 'Primary Agent', 'Primary', 'Agent')
    $memberTables = @($tables | Where-Object {
            $table = $_
            'Role' -in $table.Header -and @($primaryHeaders | Where-Object { $_ -in $table.Header }).Count -gt 0
        })
    if ($memberTables.Count -ne 1) {
        $issues.Add('one-members-table-required')
        return [pscustomobject]@{ Bindings = @(); Issues = $issues.ToArray() }
    }

    $roster = Get-SquadConnectorRosterState -TeamPath $TeamPath -TeamContent $TeamContent
    if ($bindingTables.Count -eq 1 -and $bindingTables[0].Rows.Count -ne $roster.Bindings.Count) {
        $issues.Add('missing-binding-id')
    }
    foreach ($property in @('BindingId', 'MemberName')) {
        foreach ($group in @($roster.Bindings | Group-Object -Property $property)) {
            if ($group.Count -gt 1) { $issues.Add("duplicate:$property") }
        }
    }
    $cache = @{}
    foreach ($binding in $roster.Bindings) {
        $parameters = @{
            Binding = $binding; Members = $roster.Members; TeamPath = $TeamPath
            ManifestCache = $cache; ProjectRoot = $ProjectRoot
        }
        if ($PSBoundParameters.ContainsKey('ManifestSnapshots')) { $parameters.ManifestSnapshots = $ManifestSnapshots }
        foreach ($issue in @(Get-ConnectorBindingIssuesLocal @parameters)) { $issues.Add("$($binding.BindingId):$issue") }
        $target = Get-ConnectorTargetRoleLocal -Target $binding.Target
        $members = @()
        if ($binding.RoleMode -eq 'replace' -and $target.Kind -eq 'role') {
            $members = @($roster.Members | Where-Object { $_.Agent -cne 'Squad Connector' -and $_.Role -eq $target.Role })
            if ($target.MemberName) { $members = @($members | Where-Object MemberName -CEQ $target.MemberName) }
            if ($members.Count -ne 1) { $issues.Add("$($binding.BindingId):target-member-not-found-or-ambiguous") }
        }
        elseif ($binding.RoleMode -eq 'add') {
            if (-not $target.MemberName -or $target.MemberName -cne $binding.MemberName) {
                $issues.Add("$($binding.BindingId):invalid:add-target-member-mismatch")
            }
            $members = @($roster.Members | Where-Object {
                    $_.Agent -ceq 'Squad Connector' -and $_.Role -eq $binding.AddedRole -and $_.MemberName -ceq $binding.MemberName
                })
            if ($members.Count -ne 1) { $issues.Add("$($binding.BindingId):add-member-row-missing-or-ambiguous") }
        }
        $binding | Add-Member -NotePropertyName Role -NotePropertyValue $(if ($binding.RoleMode -eq 'add') { $binding.AddedRole } else { $target.Role })
        $binding | Add-Member -NotePropertyName TargetMemberName -NotePropertyValue $target.MemberName
        $binding | Add-Member -NotePropertyName Tier -NotePropertyValue $(if ($members.Count -eq 1) { $members[0].Tier } else { '' })
        $binding | Add-Member -NotePropertyName DeliverableRoot -NotePropertyValue $(if ($members.Count -eq 1) { $members[0].DeliverableRoot } else { '' })
    }
    [pscustomobject]@{ Bindings = @($roster.Bindings); Issues = $issues.ToArray() }
}

function Get-SquadConnectorRetirementModel {
    param(
        [AllowNull()][string]$Content,
        [Parameter(Mandatory)][string]$TeamPath,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $retirements = [System.Collections.Generic.List[object]]::new()
    $historyAuthority = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $required = @('team', 'manifests', 'confirmed', 'confirmationRef', 'historyEntries')
    foreach ($entry in [regex]::Matches([string]$Content, '(?ms)^## Connector Binding Retirement(?<heading>[^\r\n]*)\r?\n(?<body>.*?)(?=^##[ \t]|\z)')) {
        $issueCount = $issues.Count
        $heading = [regex]::Match($entry.Groups['heading'].Value.Trim(), '^(?<timestamp>\S+)\s+(?<bindingId>[a-z0-9]+(?:-[a-z0-9]+)*)$')
        $label = "Connector Binding Retirement $($entry.Groups['heading'].Value.Trim())"
        if (-not $heading.Success) {
            $issues.Add("${label}:invalid-heading")
            continue
        }
        $retiredAt = $null
        try { $retiredAt = [DateTimeOffset]::Parse($heading.Groups['timestamp'].Value, [Globalization.CultureInfo]::InvariantCulture) }
        catch [FormatException] { $issues.Add("${label}:invalid-timestamp") }
        $blocks = @([regex]::Matches($entry.Groups['body'].Value, '(?ms)^```json[ \t]*\r?\n(?<json>.*?)\r?\n```[ \t]*(?:\r?\n|\z)'))
        if ($blocks.Count -ne 1) {
            $issues.Add("${label}:one-json-record-required")
            continue
        }
        $record = $null
        try { $record = $blocks[0].Groups['json'].Value | ConvertFrom-Json -AsHashtable -Depth 64 }
        catch [System.ArgumentException] { $issues.Add("${label}:invalid-json") }
        if ($record -isnot [System.Collections.IDictionary]) {
            $issues.Add("${label}:object-required")
            continue
        }
        foreach ($issue in @(Get-ClosedSchemaIssuesLocal -Object $record -Required $required)) { $issues.Add("${label}:$issue") }
        foreach ($field in @('team', 'confirmationRef')) {
            if ($record[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$record[$field])) {
                $issues.Add("${label}:invalid:$field")
            }
        }
        if ($record['confirmed'] -isnot [bool] -or $record['confirmed'] -ne $true) { $issues.Add("${label}:operator-confirmation-required") }
        if ($record['manifests'] -isnot [System.Collections.IDictionary]) { $issues.Add("${label}:manifest-snapshots-required") }
        $titles = $record['historyEntries']
        if ($titles -isnot [array] -or $titles.Count -eq 0) { $issues.Add("${label}:completed-history-entries-required") }
        else {
            $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($title in $titles) {
                if ($title -isnot [string] -or [string]::IsNullOrWhiteSpace($title)) {
                    $issues.Add("${label}:invalid:history-entry")
                    continue
                }
                if (-not $seen.Add($title)) { $issues.Add("${label}:duplicate:history-entry") }
                try {
                    $completedAt = [DateTimeOffset]::Parse(($title -split '\s+', 2)[0], [Globalization.CultureInfo]::InvariantCulture)
                    if ($null -ne $retiredAt -and $completedAt -gt $retiredAt) { $issues.Add("${label}:history-postdates-retirement") }
                }
                catch [FormatException] { $issues.Add("${label}:invalid:history-entry-timestamp") }
            }
        }
        if ($issues.Count -ne $issueCount) { continue }

        $prior = Get-SquadConnectorBindingIdentityModel -TeamContent $record['team'] -TeamPath $TeamPath -ProjectRoot $ProjectRoot `
            -ManifestSnapshots $record['manifests']
        foreach ($issue in $prior.Issues) { $issues.Add("${label}:prior-binding:$issue") }
        $binding = @($prior.Bindings | Where-Object BindingId -CEQ $heading.Groups['bindingId'].Value)
        if ($binding.Count -ne 1) { $issues.Add("${label}:one-valid-prior-binding-required") }
        if ($issues.Count -ne $issueCount) { continue }
        foreach ($title in $titles) {
            if ($historyAuthority.Contains("$($binding[0].BindingId)`n$title")) {
                $issues.Add("${label}:duplicate:history-authority")
            }
        }
        if ($issues.Count -ne $issueCount) { continue }
        foreach ($title in $titles) { [void]$historyAuthority.Add("$($binding[0].BindingId)`n$title") }
        $binding[0] | Add-Member -NotePropertyName HistoryEntries -NotePropertyValue @($titles)
        $retirements.Add($binding[0])
    }
    [pscustomobject]@{ Retirements = $retirements.ToArray(); Issues = $issues.ToArray() }
}