# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

Set-StrictMode -Version Latest

$script:SquadBuilderTemplateRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '../templates/builders')
)

function Assert-SquadBuilderIdentifier {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Value -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "$Name must use lower-kebab-case."
    }
}

function Resolve-SquadBuilderWorkspace {
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
        throw "WorkspaceRoot '$WorkspaceRoot' is not a directory."
    }
    (Resolve-Path -LiteralPath $WorkspaceRoot).Path
}

function Resolve-SquadBuilderChildPath {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath -match '^[A-Za-z]:' -or
        $RelativePath -match ':') {
        throw "Generated path '$RelativePath' must be repository-relative."
    }
    $segments = @($RelativePath.Replace('\', '/').Split('/', [StringSplitOptions]::RemoveEmptyEntries))
    if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -in '.', '..' }).Count -gt 0) {
        throw "Generated path '$RelativePath' contains an unsafe segment."
    }

    $root = [IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $candidate = [IO.Path]::GetFullPath((Join-Path $root ($segments -join [IO.Path]::DirectorySeparatorChar)))
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $candidate.StartsWith("$root$([IO.Path]::DirectorySeparatorChar)", $comparison)) {
        throw "Generated path '$RelativePath' escapes WorkspaceRoot."
    }
    $candidate
}

function Get-SquadBuilderTemplate {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -notmatch '^[a-z0-9-]+\.template\.(?:md|ps1)$') {
        throw "Invalid builder template name '$Name'."
    }
    $path = Join-Path $script:SquadBuilderTemplateRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Builder template '$Name' was not installed."
    }
    Get-Content -LiteralPath $path -Raw
}

function Expand-SquadBuilderTemplate {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Tokens
    )

    $content = Get-SquadBuilderTemplate -Name $Name
    foreach ($key in $Tokens.Keys) {
        $content = $content.Replace("{{$key}}", [string]$Tokens[$key])
    }
    $unresolved = @([regex]::Matches($content, '\{\{[A-Z0-9_]+\}\}') | ForEach-Object Value | Sort-Object -Unique)
    if ($unresolved.Count -gt 0) {
        throw "Template '$Name' has unresolved token(s): $($unresolved -join ', ')."
    }
    if (-not $content.EndsWith("`n")) { $content += "`n" }
    $content
}

function ConvertTo-SquadBuilderDisplayName {
    param([Parameter(Mandatory)][string]$Identifier)

    $textInfo = [Globalization.CultureInfo]::InvariantCulture.TextInfo
    ($Identifier.Split('-') | ForEach-Object { $textInfo.ToTitleCase($_) }) -join ' '
}

function ConvertTo-SquadBuilderYamlText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    ($Value -replace '\s+', ' ').Trim().Replace('\', '\\').Replace('"', '\"')
}

function ConvertTo-SquadBuilderBulletList {
    param(
        [Parameter(Mandatory)][string[]]$Values,
        [string]$Fallback = 'TODO: describe this requirement before production use.'
    )

    $items = @($Values | ForEach-Object { ([string]$_ -replace '\s+', ' ').Trim() } | Where-Object { $_ })
    if ($items.Count -eq 0) { $items = @($Fallback) }
    ($items | ForEach-Object { "* $_" }) -join "`n"
}

function New-SquadBuilderPlanEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    [pscustomobject]@{
        Path    = $Path.Replace('\', '/')
        Content = if ($Content.EndsWith("`n")) { $Content } else { "$Content`n" }
    }
}

function ConvertTo-SquadBuilderJson {
    param([Parameter(Mandatory)]$Value)

    ($Value | ConvertTo-Json -Depth 32) + "`n"
}

function New-SquadConnectorManifestObject {
    param(
        [Parameter(Mandatory)][string]$ConnectorId,
        [Parameter(Mandatory)][ValidateSet('agent', 'orchestrator')][string]$EndpointKind,
        [Parameter(Mandatory)][string[]]$Capabilities,
        [Parameter(Mandatory)][string[]]$Roles,
        [Parameter(Mandatory)][string]$Contact,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][int]$DeadlineMinutes,
        [Parameter(Mandatory)][int]$RetryCap
    )

    [ordered]@{
        connectorId           = $ConnectorId
        schemaVersion         = '1.1'
        transport             = 'file'
        endpointKind          = $EndpointKind
        capabilities          = @($Capabilities)
        roles                 = @($Roles)
        dropPath              = ".connector-drops/$ConnectorId/"
        deadlineMinutesDefault = $DeadlineMinutes
        retryCapDefault       = $RetryCap
        contact               = $Contact
        version               = $Version
    }
}

function New-SquadConnectorRequestExample {
    param(
        [Parameter(Mandatory)][string]$ConnectorId,
        [Parameter(Mandatory)][ValidateSet('agent', 'orchestrator')][string]$EndpointKind,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][int]$RetryCap
    )

    $bindingId = "$ConnectorId-binding"
    $outputs = if ($EndpointKind -eq 'orchestrator') {
        @(
            [ordered]@{
                outputId       = 'primary-note'
                role           = $Role
                deliverableRoot = "connector-output/$ConnectorId/primary"
            },
            [ordered]@{
                outputId       = 'validation-note'
                role           = $Role
                deliverableRoot = "connector-output/$ConnectorId/validation"
            }
        )
    }
    else {
        @([ordered]@{
                outputId       = 'agent-result'
                role           = $Role
                deliverableRoot = "connector-output/$ConnectorId"
            })
    }

    [ordered]@{
        taskId          = "example-$ConnectorId-001"
        connectorId     = $ConnectorId
        role            = $Role
        deliverableRoot = "connector-output/$ConnectorId"
        bindingId       = $bindingId
        targetKind      = 'role'
        executionChoice = "connector:$bindingId"
        allowedOutputs  = $outputs
        task            = 'Demonstrate one bounded connector exchange using the generated removable runner.'
        deadline        = '2099-01-01T00:00:00Z'
        retryCap        = $RetryCap
        createdAt       = '2026-10-24T00:00:00Z'
    }
}

function New-SquadConnectorResultExample {
    param(
        [Parameter(Mandatory)][string]$ConnectorId,
        [Parameter(Mandatory)][ValidateSet('agent', 'orchestrator')][string]$EndpointKind,
        [Parameter(Mandatory)][string]$Role
    )

    $result = [ordered]@{
        taskId     = "example-$ConnectorId-001"
        connectorId = $ConnectorId
        bindingId  = "$ConnectorId-binding"
        role       = $Role
        status     = 'completed'
        artifacts  = @()
    }
    if ($EndpointKind -eq 'orchestrator') {
        $result.outputs = @(
            [ordered]@{
                outputId = 'primary-note'
                artifacts = @([ordered]@{ path = "connector-example-example-$ConnectorId-001-primary-note.md"; type = 'md' })
            },
            [ordered]@{
                outputId = 'validation-note'
                artifacts = @([ordered]@{ path = "connector-example-example-$ConnectorId-001-validation-note.md"; type = 'md' })
            }
        )
    }
    else {
        $result.artifacts = @(
            [ordered]@{ path = "connector-example-example-$ConnectorId-001-agent-result.md"; type = 'md' }
        )
    }
    $result.narrative = 'The removable example runner completed a transport demonstration.'
    $result.createdAt = '2026-10-24T00:01:00Z'
    $result
}

function Get-SquadConnectorScaffoldPlan {
    [CmdletBinding()]
    param(
        [string]$ConnectorId,
        [ValidateSet('agent', 'orchestrator')][string]$EndpointKind = 'agent',
        [string[]]$Capabilities = @(),
        [string[]]$Roles = @(),
        [string]$Contact = '',
        [string]$Version = '0.1.0',
        [ValidateRange(1, [int]::MaxValue)][int]$DeadlineMinutes = 60,
        [ValidateRange(0, [int]::MaxValue)][int]$RetryCap = 2,
        [switch]$EditableTemplate
    )

    if ($EditableTemplate) {
        $manifestConnectorId = 'REPLACE_CONNECTOR_ID'
        $fileStem = 'connector-template'
        $manifestPath = 'connectors/connector.template.json'
        $capabilityValues = @('REPLACE_CAPABILITY')
        $roleValues = @('REPLACE_ROLE')
        $contactValue = 'REPLACE_CONTACT'
    }
    else {
        Assert-SquadBuilderIdentifier -Value $ConnectorId -Name 'ConnectorId'
        $capabilityValues = @($Capabilities | ForEach-Object { ([string]$_ -replace '\s+', ' ').Trim() } | Where-Object { $_ })
        $roleValues = @($Roles | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        if ($capabilityValues.Count -eq 0) { throw 'At least one capability is required.' }
        if ($roleValues.Count -eq 0) { throw 'At least one role is required.' }
        foreach ($role in $roleValues) { Assert-SquadBuilderIdentifier -Value $role -Name 'Role' }
        if ([string]::IsNullOrWhiteSpace($Contact)) { throw 'Contact is required.' }
        if ([string]::IsNullOrWhiteSpace($Version)) { throw 'Version is required.' }
        $manifestConnectorId = $ConnectorId
        $fileStem = $ConnectorId
        $manifestPath = "connectors/$ConnectorId.json"
        $contactValue = $Contact.Trim()
    }

    $runnerPath = "scripts/Run-$fileStem-Connector.ps1"
    $requestExamplePath = "connectors/examples/$fileStem.request.example.json"
    $resultExamplePath = "connectors/examples/$fileStem.result.example.json"
    $runbookPath = "docs/$fileStem-connector-runbook.md"
    $manifest = New-SquadConnectorManifestObject `
        -ConnectorId $manifestConnectorId `
        -EndpointKind $EndpointKind `
        -Capabilities $capabilityValues `
        -Roles $roleValues `
        -Contact $contactValue `
        -Version $Version `
        -DeadlineMinutes $DeadlineMinutes `
        -RetryCap $RetryCap
    $request = New-SquadConnectorRequestExample `
        -ConnectorId $manifestConnectorId `
        -EndpointKind $EndpointKind `
        -Role $roleValues[0] `
        -RetryCap $RetryCap
    $result = New-SquadConnectorResultExample `
        -ConnectorId $manifestConnectorId `
        -EndpointKind $EndpointKind `
        -Role $roleValues[0]

    @(
        New-SquadBuilderPlanEntry -Path $manifestPath -Content (ConvertTo-SquadBuilderJson $manifest)
        New-SquadBuilderPlanEntry -Path '.connector-drops/README.md' -Content (
            Get-SquadBuilderTemplate -Name 'connector-drop-root.template.md'
        )
        New-SquadBuilderPlanEntry -Path ".connector-drops/$manifestConnectorId/README.md" -Content (
            Expand-SquadBuilderTemplate -Name 'connector-drop-endpoint.template.md' -Tokens @{
                CONNECTOR_ID = $manifestConnectorId
                MANIFEST_PATH = $manifestPath
                RUNNER_PATH = $runnerPath
            }
        )
        New-SquadBuilderPlanEntry -Path $runnerPath -Content (
            Expand-SquadBuilderTemplate -Name 'connector-runner.template.ps1' -Tokens @{
                CONNECTOR_ID = $manifestConnectorId
                MANIFEST_PATH = $manifestPath
            }
        )
        New-SquadBuilderPlanEntry -Path $requestExamplePath -Content (ConvertTo-SquadBuilderJson $request)
        New-SquadBuilderPlanEntry -Path $resultExamplePath -Content (ConvertTo-SquadBuilderJson $result)
        New-SquadBuilderPlanEntry -Path $runbookPath -Content (
            Expand-SquadBuilderTemplate -Name 'connector-runbook.template.md' -Tokens @{
                CONNECTOR_ID = $manifestConnectorId
                MANIFEST_PATH = $manifestPath
                RUNNER_PATH = $runnerPath
                REQUEST_EXAMPLE_PATH = $requestExamplePath
                RESULT_EXAMPLE_PATH = $resultExamplePath
                ENDPOINT_KIND = $EndpointKind
                ROLES = ($roleValues -join ', ')
            }
        )
    )
}

function Get-SquadExternalEndpointScaffoldPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Create', 'Adapt')][string]$Mode,
        [Parameter(Mandatory)][string]$ConnectorId,
        [Parameter(Mandatory)][ValidateSet('agent', 'orchestrator')][string]$EndpointKind,
        [Parameter(Mandatory)][string[]]$Capabilities,
        [Parameter(Mandatory)][string[]]$Roles,
        [Parameter(Mandatory)][string[]]$Responsibilities,
        [string[]]$SkillRequirements = @(),
        [Parameter(Mandatory)][string]$Contact,
        [string]$EndpointName,
        [string]$ExistingPath,
        [string]$Version = '0.1.0',
        [ValidateRange(1, [int]::MaxValue)][int]$DeadlineMinutes = 60,
        [ValidateRange(0, [int]::MaxValue)][int]$RetryCap = 2,
        [Parameter(Mandatory)][string]$WorkspaceRoot
    )

    Assert-SquadBuilderIdentifier -Value $ConnectorId -Name 'ConnectorId'
    $name = if ([string]::IsNullOrWhiteSpace($EndpointName)) {
        ConvertTo-SquadBuilderDisplayName -Identifier $ConnectorId
    }
    else {
        ($EndpointName -replace '\s+', ' ').Trim()
    }
    $responsibilityValues = @($Responsibilities | ForEach-Object { ([string]$_ -replace '\s+', ' ').Trim() } | Where-Object { $_ })
    if ($responsibilityValues.Count -eq 0) { throw 'At least one responsibility is required.' }

    $plan = [Collections.Generic.List[object]]::new()
    foreach ($entry in @(Get-SquadConnectorScaffoldPlan `
            -ConnectorId $ConnectorId `
            -EndpointKind $EndpointKind `
            -Capabilities $Capabilities `
            -Roles $Roles `
            -Contact $Contact `
            -Version $Version `
            -DeadlineMinutes $DeadlineMinutes `
            -RetryCap $RetryCap)) {
        $plan.Add($entry)
    }

    $runnerPath = "scripts/Run-$ConnectorId-Connector.ps1"
    $manifestPath = "connectors/$ConnectorId.json"
    $connectorRunbookPath = "docs/$ConnectorId-connector-runbook.md"
    if ($Mode -eq 'Adapt') {
        if ([string]::IsNullOrWhiteSpace($ExistingPath)) { throw 'ExistingPath is required in Adapt mode.' }
        $workspace = Resolve-SquadBuilderWorkspace -WorkspaceRoot $WorkspaceRoot
        $resolvedExisting = if ([IO.Path]::IsPathRooted($ExistingPath)) {
            [IO.Path]::GetFullPath($ExistingPath)
        }
        else {
            [IO.Path]::GetFullPath((Join-Path $workspace $ExistingPath))
        }
        if (-not (Test-Path -LiteralPath $resolvedExisting)) {
            throw "ExistingPath '$ExistingPath' does not exist."
        }
        $displayPath = if ($resolvedExisting.StartsWith(
                "$workspace$([IO.Path]::DirectorySeparatorChar)",
                $(if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal })
            )) {
            [IO.Path]::GetRelativePath($workspace, $resolvedExisting).Replace('\', '/')
        }
        else {
            $resolvedExisting
        }
        $content = Expand-SquadBuilderTemplate -Name 'external-adapt-runbook.template.md' -Tokens @{
            EXISTING_PATH = $displayPath
            CONNECTOR_ID = $ConnectorId
            ENDPOINT_KIND = $EndpointKind
            MANIFEST_PATH = $manifestPath
            RUNNER_PATH = $runnerPath
            CONNECTOR_RUNBOOK_PATH = $connectorRunbookPath
        }
        if (@($SkillRequirements | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            $content += "`n## Skill requirements to map`n`n$(ConvertTo-SquadBuilderBulletList -Values $SkillRequirements)`n"
        }
        $plan.Add((New-SquadBuilderPlanEntry -Path "docs/$ConnectorId-adaptation-runbook.md" -Content $content))
        return $plan.ToArray()
    }

    $skillName = $ConnectorId
    $endpointPath = ".github/agents/$ConnectorId.agent.md"
    $description = ConvertTo-SquadBuilderYamlText -Value (
        "Consumer-owned $EndpointKind for $($responsibilityValues -join '; ')."
    )
    $workerEntries = [Collections.Generic.List[object]]::new()
    if ($EndpointKind -eq 'orchestrator') {
        for ($index = 0; $index -lt $responsibilityValues.Count; $index++) {
            $number = $index + 1
            $workerName = "$name Worker $number"
            $workerPath = ".github/agents/$ConnectorId-worker-$number.agent.md"
            $workerContent = Expand-SquadBuilderTemplate -Name 'external-worker.template.md' -Tokens @{
                WORKER_NAME = $workerName
                DESCRIPTION = ConvertTo-SquadBuilderYamlText -Value $responsibilityValues[$index]
                SKILL_NAME = $skillName
                RESPONSIBILITY = $responsibilityValues[$index]
            }
            $workerEntries.Add([pscustomobject]@{
                    Name = $workerName
                    Path = $workerPath
                    Content = $workerContent
                })
        }
        $agentList = ($workerEntries | ForEach-Object { "  - $($_.Name)" }) -join "`n"
        $endpointContent = Expand-SquadBuilderTemplate -Name 'external-orchestrator.template.md' -Tokens @{
            ENDPOINT_NAME = $name
            DESCRIPTION = $description
            AGENTS = $agentList
            RESPONSIBILITIES = ConvertTo-SquadBuilderBulletList -Values $responsibilityValues
        }
    }
    else {
        $endpointContent = Expand-SquadBuilderTemplate -Name 'external-agent.template.md' -Tokens @{
            ENDPOINT_NAME = $name
            DESCRIPTION = $description
            SKILL_NAME = $skillName
            RESPONSIBILITIES = ConvertTo-SquadBuilderBulletList -Values $responsibilityValues
        }
    }
    $plan.Add((New-SquadBuilderPlanEntry -Path $endpointPath -Content $endpointContent))
    foreach ($worker in $workerEntries) {
        $plan.Add((New-SquadBuilderPlanEntry -Path $worker.Path -Content $worker.Content))
    }

    $skillContent = Expand-SquadBuilderTemplate -Name 'external-skill.template.md' -Tokens @{
        SKILL_NAME = $skillName
        DESCRIPTION = ConvertTo-SquadBuilderYamlText -Value "Guidance for the $name external endpoint."
        ENDPOINT_NAME = $name
        CAPABILITIES = ConvertTo-SquadBuilderBulletList -Values $Capabilities
        SKILL_REQUIREMENTS = ConvertTo-SquadBuilderBulletList -Values $SkillRequirements
    }
    $skillPath = ".github/skills/$skillName/SKILL.md"
    $plan.Add((New-SquadBuilderPlanEntry -Path $skillPath -Content $skillContent))

    $artifactLines = @(
        "* Endpoint: ``$endpointPath``"
        "* Skill: ``$skillPath``"
        $workerEntries | ForEach-Object { "* Worker: ``$($_.Path)``" }
    )
    $createRunbook = Expand-SquadBuilderTemplate -Name 'external-create-runbook.template.md' -Tokens @{
        ENDPOINT_NAME = $name
        ENDPOINT_KIND = $EndpointKind
        CONNECTOR_ID = $ConnectorId
        ENDPOINT_ARTIFACTS = $artifactLines -join "`n"
        CONNECTOR_RUNBOOK_PATH = $connectorRunbookPath
        RUNNER_PATH = $runnerPath
        ENDPOINT_PATH = $endpointPath
    }
    $plan.Add((New-SquadBuilderPlanEntry -Path "docs/$ConnectorId-external-endpoint-runbook.md" -Content $createRunbook))
    $plan.ToArray()
}

function Test-SquadBuilderManifestValues {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Raw
    )

    $issues = [Collections.Generic.List[string]]::new()
    if ($Raw -match 'REPLACE_[A-Z0-9_]+') { $issues.Add('unresolved-placeholder') }
    $connectorId = [string]$Manifest.connectorId
    if ($connectorId -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        $issues.Add('invalid:connectorId-lower-kebab-case')
    }
    $expectedDropPath = ".connector-drops/$connectorId/"
    if ([string]$Manifest.dropPath -cne $expectedDropPath) {
        $issues.Add("invalid:dropPath-expected:$expectedDropPath")
    }
    if (@($Manifest.capabilities).Count -eq 0) { $issues.Add('invalid:capabilities-empty') }
    if (@($Manifest.roles).Count -eq 0) { $issues.Add('invalid:roles-empty') }
    foreach ($role in @($Manifest.roles)) {
        if ([string]$role -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            $issues.Add("invalid:role-lower-kebab-case:$role")
        }
    }
    $issues.ToArray()
}

function Write-SquadBuilderPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][object[]]$Plan
    )

    $workspace = Resolve-SquadBuilderWorkspace -WorkspaceRoot $WorkspaceRoot
    $byPath = [ordered]@{}
    foreach ($entry in $Plan) {
        if ($byPath.Contains($entry.Path)) {
            if ($byPath[$entry.Path].Content -cne $entry.Content) {
                throw "Scaffold plan contains conflicting content for '$($entry.Path)'."
            }
            continue
        }
        $byPath[$entry.Path] = $entry
    }

    $conflicts = [Collections.Generic.List[string]]::new()
    $states = [Collections.Generic.List[object]]::new()
    foreach ($entry in $byPath.Values) {
        $target = Resolve-SquadBuilderChildPath -WorkspaceRoot $workspace -RelativePath $entry.Path
        $state = 'create'
        if (Test-Path -LiteralPath $target) {
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                $state = 'conflict'
            }
            else {
                $existing = Get-Content -LiteralPath $target -Raw
                $state = if ($existing -ceq $entry.Content) { 'unchanged' } else { 'conflict' }
            }
        }
        if ($state -eq 'conflict') { $conflicts.Add($entry.Path) }
        $states.Add([pscustomobject]@{
                Path = $entry.Path
                Target = $target
                Content = $entry.Content
                Action = $state
            })
    }
    if ($conflicts.Count -gt 0) {
        throw "Refusing to overwrite customized file(s): $($conflicts -join ', ')."
    }

    foreach ($item in @($states | Where-Object Action -eq 'create')) {
        $parent = Split-Path -Parent $item.Target
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $temporary = Join-Path $parent ".$([IO.Path]::GetFileName($item.Target)).$([guid]::NewGuid().ToString('N')).tmp"
        try {
            [IO.File]::WriteAllText($temporary, $item.Content, [Text.UTF8Encoding]::new($false))
            [IO.File]::Move($temporary, $item.Target)
        }
        finally {
            if (Test-Path -LiteralPath $temporary) {
                Remove-Item -LiteralPath $temporary -Force
            }
        }
    }
    @($states | Select-Object Path, Action)
}