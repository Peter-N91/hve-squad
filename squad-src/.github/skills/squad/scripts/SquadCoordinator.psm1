# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SkillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Resolve-SquadConnectorDispatch.ps1')

function Read-SquadTables {
    param([Parameter(Mandatory)][string]$Path)
    Get-MarkdownTablesFromContentLocal -Content ([IO.File]::ReadAllText($Path))
}

function Get-SquadReferenceSection {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Heading)
    $text = [IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $pattern = '(?m)^' + [regex]::Escape($Heading) + '[ \t]*$'
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) { throw "Missing section '$Heading' in $Path." }
    $level = [regex]::Match($Heading, '^#+').Length
    $tail = $text.Substring($match.Index + $match.Length)
    $next = [regex]::Match($tail, "(?m)^#{1,$level} ")
    if ($next.Success) { $tail = $tail.Substring(0, $next.Index) }
    $match.Value + $tail
}

function Get-SquadRulePath {
    param([Parameter(Mandatory)][string]$Name, [string]$RepoRoot = (Get-Location).ProviderPath)
    $artifactRoot = Split-Path -Parent (Split-Path -Parent $script:SkillRoot)
    foreach ($path in @(
            (Join-Path $artifactRoot 'instructions' 'squad' "$Name.instructions.md"),
            (Join-Path $artifactRoot 'instructions' "$Name.instructions.md"),
            (Join-Path (Split-Path -Parent $artifactRoot) '.github' 'instructions' "$Name.instructions.md"),
            (Join-Path $script:SkillRoot 'references' 'rules' "$Name.md"),
            (Join-Path $RepoRoot '.github' 'instructions' 'squad' "$Name.instructions.md"),
            (Join-Path $RepoRoot '.github' 'instructions' "$Name.instructions.md")
        )) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
    throw "The selected Squad installation is missing rule '$Name'."
}

function Resolve-SquadRepositoryPath {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowMissing
    )
    $repository = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($Path -match '(^|[\\/])\.\.([\\/]|$)|[\r\n\x00]' -or $Path -match '^[a-z]+://') {
        throw "Unsafe repository path: $Path"
    }
    $resolved = [IO.Path]::GetFullPath($Path, $repository)
    $relative = [IO.Path]::GetRelativePath($repository, $resolved)
    if ($relative -eq '..' -or $relative -match '^\.\.[\\/]' -or [IO.Path]::IsPathRooted($relative)) {
        throw "Path leaves the repository: $Path"
    }
    $cursor = $resolved
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Linked repository path refused: $cursor"
        }
        if ($cursor -eq $repository) { break }
        $cursor = Split-Path -Parent $cursor
    }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $resolved)) { throw "Path not found: $Path" }
    $resolved
}

function Get-SquadAgentIndex {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $artifactRoot = Split-Path -Parent (Split-Path -Parent $script:SkillRoot)
    $index = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $bases = @(
        (Join-Path $RepoRoot '.github' 'agents'),
        (Join-Path $RepoRoot '.agents' 'agents'),
        (Join-Path $RepoRoot '.claude' 'agents'),
        (Join-Path $artifactRoot 'agents'),
        (Join-Path (Split-Path -Parent $artifactRoot) 'agents'),
        (Join-Path (Split-Path -Parent $artifactRoot) 'hve-squad-hve-core' '.github' 'agents'),
        (Join-Path (Split-Path -Parent $artifactRoot) 'hve-core' '.github' 'agents'),
        (Join-Path (Split-Path -Parent $artifactRoot) 'hve-core' 'agents')
    ) | Select-Object -Unique
    foreach ($base in $bases) {
        if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.agent.md' | Sort-Object FullName) {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $text = [IO.File]::ReadAllText($file.FullName).TrimStart([char]0xfeff) -replace "`r`n", "`n"
            $match = [regex]::Match($text, '\A---\n(?<front>.*?)\n---(?:\n|$)', 'Singleline')
            if (-not $match.Success) { continue }
            $front = $match.Groups['front'].Value
            $name = [regex]::Match($front, '(?m)^name:[ \t]*(?<value>[^\n]+)$')
            if (-not $name.Success) { continue }
            $identity = $name.Groups['value'].Value.Trim().Trim('"', "'")
            if ($index.ContainsKey($identity)) { continue }
            $pin = [regex]::Match($front, '(?m)^model:[ \t]*(?<value>[^\n]+)$')
            $index.Add($identity, [pscustomobject]@{
                    name = $identity
                    path = $file.FullName
                    dispatchable = $front -notmatch '(?m)^disable-model-invocation:[ \t]*true[ \t]*(?:#.*)?$'
                    model = $(if ($pin.Success) { $pin.Groups['value'].Value.Trim().Trim('"', "'") } else { '' })
                })
        }
    }
    return ,$index
}

function Get-SquadRoster {
    param([Parameter(Mandatory)][string]$SquadRoot)
    $tables = @(Read-SquadTables (Join-Path $SquadRoot 'team.md'))
    $members = @($tables | Where-Object { 'Role' -in $_.Header -and 'Agent Name (Primary)' -in $_.Header })
    if ($members.Count -ne 1) { throw 'Expected exactly one Members roster table.' }
    $members[0].Rows
}

function Invoke-SquadLocalScript {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 120
    )
    if ($Name -notmatch '^[A-Za-z][A-Za-z0-9-]+\.ps1$') { throw 'A shipped script name is required.' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSHOME 'pwsh'
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', (Join-Path $PSScriptRoot $Name)) + $Arguments) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "$Name exceeded its $TimeoutSeconds-second local execution timeout."
        }
        [pscustomobject]@{ exitCode = $process.ExitCode; stdout = $stdout.GetAwaiter().GetResult(); stderr = $stderr.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}

function Get-SquadInitData {
    param([string]$RepoRoot = (Get-Location).ProviderPath)
    $rulesPath = Get-SquadRulePath -Name 'squad-roster' -RepoRoot $RepoRoot
    $tables = @(Read-SquadTables $rulesPath)
    $profiles = @($tables | Where-Object { 'Profile' -in $_.Header -and 'Members (roles)' -in $_.Header })
    $packs = @($tables | Where-Object { 'Pack' -in $_.Header -and 'Adds (roles)' -in $_.Header })
    $roots = @($tables | Where-Object { 'Role' -in $_.Header -and 'Deliverable Root' -in $_.Header -and $_.Header.Count -eq 2 })
    $cast = @(Read-SquadTables (Join-Path $script:SkillRoot 'references' 'roster-catalog.md') |
            Where-Object { 'Primary Agent (`name:`)' -in $_.Header })
    $seeds = @(Read-SquadTables (Join-Path $script:SkillRoot 'references' 'seed-templates.md') |
            Where-Object { 'Agent Name (Primary)' -in $_.Header })
    if ($profiles.Count -ne 1 -or $packs.Count -ne 1 -or $roots.Count -ne 1 -or $cast.Count -ne 1 -or $seeds.Count -ne 1) {
        throw 'The selected installation has ambiguous or missing profile, pack, cast, root, or seed tables.'
    }
    $aliasesSection = Get-SquadReferenceSection $rulesPath '#### Deterministic Alias Wordlist'
    $aliasesMatch = [regex]::Match($aliasesSection, '(?s)```text\s*\n(?<names>.*?)\n```')
    if (-not $aliasesMatch.Success) { throw 'Missing canonical alias wordlist.' }
    [pscustomobject]@{
        profiles = $profiles[0].Rows
        packs = $packs[0].Rows
        cast = $cast[0].Rows
        roots = $roots[0].Rows
        seeds = $seeds[0].Rows
        aliases = @($aliasesMatch.Groups['names'].Value -split ',\s*')
    }
}

function New-SquadInitPayload {
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Choices,
        [Parameter(Mandatory)][string]$RepoRoot
    )
    $required = @('confirmed', 'squadRoot', 'runId', 'profile', 'naming', 'notify')
    $optional = @('packs', 'roles', 'excludeRoles', 'names', 'modelRouting', 'models', 'mode', 'sessionModel', 'modelOverrides', 'usage')
    foreach ($key in $required) {
        if (-not $Choices.Contains($key)) { throw "Missing confirmed Init choice: $key" }
    }
    foreach ($key in $Choices.Keys) {
        if ($key -notin ($required + $optional)) { throw "Unsupported Init choice: $key" }
    }
    if ($Choices.confirmed -isnot [bool] -or -not $Choices.confirmed) { throw 'Init requires explicit user confirmation.' }
    if ($Choices.naming -notin @('skip', 'aliases', 'custom', 'mixed')) { throw 'Supply the answered naming policy: skip, aliases, custom, or mixed.' }
    if ($Choices.notify -isnot [Collections.IDictionary]) { throw 'Supply the answered or inherited notify object.' }
    $root = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $Choices.squadRoot -AllowMissing
    $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($RepoRoot), $root) -replace '\\', '/'
    if ($relative -notmatch '^\.copilot-tracking/squad(?:/members/[a-z0-9][a-z0-9-]*)?$') { throw 'Invalid single-squad/member root.' }
    $data = Get-SquadInitData -RepoRoot $RepoRoot
    $profiles = @($data.profiles | Where-Object { $_.Profile -ceq $Choices.profile })
    if ($Choices.profile -eq 'custom') {
        if (-not $Choices.Contains('roles') -or $Choices.roles -isnot [array] -or $Choices.roles.Count -eq 0) { throw 'Custom Init requires confirmed role IDs.' }
        $roles = @($Choices.roles)
    }
    else {
        if ($profiles.Count -ne 1 -or $Choices.Contains('roles')) { throw 'Select a known profile, or use custom with role IDs.' }
        $roles = @($profiles[0]['Members (roles)'] -split ',\s*')
    }
    $packNames = @()
    if ($Choices.Contains('packs')) {
        if ($Choices.packs -isnot [array]) { throw 'packs must be an array.' }
        foreach ($name in $Choices.packs) {
            $pack = @($data.packs | Where-Object { $_.Pack -ceq $name })
            if ($pack.Count -ne 1 -or $name -in $packNames) { throw "Unknown or duplicate pack: $name" }
            $packNames += $name
            $roles += @($pack[0]['Adds (roles)'] -split ',\s*')
        }
    }
    $roles = @($roles | Select-Object -Unique)
    if ($Choices.Contains('excludeRoles')) {
        if ($Choices.excludeRoles -isnot [array]) { throw 'excludeRoles must be an array.' }
        foreach ($role in $Choices.excludeRoles) {
            if ($role -notin $roles -or $role -in @('researcher', 'lead', 'developer', 'tester', 'scribe')) {
                throw "Cannot exclude missing or methodology role: $role"
            }
        }
        $roles = @($roles | Where-Object { $_ -notin $Choices.excludeRoles })
    }
    foreach ($role in @('researcher', 'lead', 'developer', 'tester', 'scribe')) {
        if ($role -notin $roles) { throw "Confirmed roster is missing methodology role: $role" }
    }
    $names = if ($Choices.Contains('names')) { $Choices.names } else { @{} }
    if ($names -isnot [Collections.IDictionary]) { throw 'names must be a role-to-name object.' }
    foreach ($role in $names.Keys) {
        if ($role -notin $roles -or $names[$role] -isnot [string] -or $names[$role] -match '[\r\n|]' -or [string]::IsNullOrWhiteSpace($names[$role])) {
            throw "Invalid confirmed member name for $role."
        }
    }
    if ($Choices.naming -eq 'skip' -and $names.Count -gt 0) { throw 'Skip naming cannot carry supplied names.' }
    if ($Choices.naming -eq 'custom' -and $names.Count -ne $roles.Count) { throw 'Custom naming requires a supplied name for every role.' }
    $models = if ($Choices.Contains('models')) { $Choices.models } else { @{} }
    if ($models -isnot [Collections.IDictionary]) { throw 'models must be a role-to-model object.' }
    $routing = if ($Choices.Contains('modelRouting')) { $Choices.modelRouting } else { 'off' }
    if ($routing -notin @('off', 'ranked', 'economy', 'manual')) { throw 'Invalid modelRouting.' }
    foreach ($role in $models.Keys) {
        if ($role -notin $roles -or $models[$role] -isnot [string] -or $routing -eq 'off') { throw "Invalid confirmed model cell for $role." }
    }
    $agents = Get-SquadAgentIndex $RepoRoot
    $usedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $names.Values) { $null = $usedNames.Add($name) }
    $aliasIndex = 0
    $roster = @(
        foreach ($role in $roles) {
            $cast = @($data.cast | Where-Object { $_.Role -ceq $role })
            if ($cast.Count -ne 1) { throw "Unknown or ambiguous catalog role: $role" }
            $primary = $cast[0]['Primary Agent (`name:`)']
            if (-not $agents.ContainsKey($primary) -or -not $agents[$primary].dispatchable) {
                throw "Role '$role' has no installed dispatchable Primary '$primary'; confirm another roster or install it."
            }
            $name = if ($names.Contains($role)) { $names[$role] } else { '' }
            if (-not $name -and $Choices.naming -in @('aliases', 'mixed')) {
                do {
                    $cycle = [int][Math]::Floor($aliasIndex / $data.aliases.Count)
                    $name = $data.aliases[$aliasIndex % $data.aliases.Count] + $(if ($cycle) { "-$($cycle + 1)" })
                    $aliasIndex++
                } while (-not $usedNames.Add($name))
            }
            $seed = @($data.seeds | Where-Object { $_.Role -ceq $role })
            $rootRows = @($data.roots | Where-Object { $role -cin @($_.Role -split ',\s*') })
            if ($rootRows.Count -gt 1) { throw "Ambiguous canonical Deliverable Root for $role." }
            $deliverable = if ($role -eq 'scribe') { '(squad state)' } elseif ($rootRows.Count) { $rootRows[0]['Deliverable Root'] } else { [string][char]0x2014 }
            $row = [ordered]@{
                Role = $role
                'Member Name' = $name
                'Agent Name (Primary)' = $primary
                'Alternate Agents' = $cast[0]['Alternate Agents (`name:`)']
                'Selection Cue' = $cast[0]['Selection Cue']
                Invocation = 'runSubagent / task'
                'Model Tier' = $(if ($seed.Count) { $seed[0]['Model Tier'] } else { 'default' })
            }
            if ($routing -ne 'off') { $row['Model'] = $(if ($models.Contains($role)) { $models[$role] } else { '' }) }
            $row['Deliverable Root'] = $deliverable
            $row
        }
    )
    $payload = [ordered]@{
        squadRoot = $relative
        runId = $Choices.runId
        roster = $roster
        provenance = $Choices.profile + (($packNames | ForEach-Object { " +$_" }) -join '')
        modelRouting = $routing
        notify = $Choices.notify
    }
    foreach ($key in @('mode', 'sessionModel', 'modelOverrides', 'usage')) {
        if ($Choices.Contains($key)) { $payload[$key] = $Choices[$key] }
    }
    $payload
}

function Write-SquadTransportJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SquadRoot,
        [Parameter(Mandatory)]$Value
    )
    $destination = [IO.Path]::GetFullPath($Path)
    $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($SquadRoot), $destination)
    if ([IO.Path]::GetExtension($destination) -ne '.json' -or
        ($relative -ne '..' -and $relative -notmatch '^\.\.[\\/]' -and -not [IO.Path]::IsPathRooted($relative))) {
        throw 'Transport JSON must be a new file outside squad state.'
    }
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Transport parent must already exist.' }
    $cursor = $parent
    while ($cursor) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked transport directory refused.' }
        $cursor = Split-Path -Parent $cursor
    }
    $stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 30))
        $stream.Write($bytes)
    }
    finally { $stream.Dispose() }
    $destination
}

function Get-SquadFederationSnapshot {
    param([Parameter(Mandatory)][string]$SquadRoot, [Parameter(Mandatory)][string]$RepoRoot)
    $tables = @(Read-SquadTables (Join-Path $SquadRoot 'federation.md') | Where-Object { 'Sub-squad' -in $_.Header -and 'Location' -in $_.Header })
    if ($tables.Count -ne 1) { throw 'Missing federation registry.' }
    $members = [ordered]@{}
    foreach ($row in $tables[0].Rows) {
        $name = $row['Sub-squad']
        if ($name -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $members.Contains($name) -or $row.Kind -ne 'in-repo' -or
            ($row.Location -replace '\\', '/').TrimEnd('/') -cne "members/$name") { throw 'Invalid or duplicate federation member.' }
        $path = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $SquadRoot 'members' $name 'state.json')
        $stateBytes = [IO.File]::ReadAllBytes($path)
        $state = [Text.Encoding]::UTF8.GetString($stateBytes).TrimStart([char]0xfeff) | ConvertFrom-Json -AsHashtable
        foreach ($field in @('estCostUsd', 'estCreditsTotal')) {
            $value = $state.currentRun[$field]
            if ($value -isnot [ValueType] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -lt 0) { throw 'Invalid member totals.' }
        }
        $members[$name] = [ordered]@{ stateHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stateBytes)); costUsd = $state.currentRun.estCostUsd; credits = $state.currentRun.estCreditsTotal }
    }
    $files = [ordered]@{}
    $paths = @(
        Get-ChildItem -LiteralPath $SquadRoot -File -Force
        $history = Join-Path $SquadRoot 'history'
        if (Test-Path -LiteralPath $history) { Get-ChildItem -LiteralPath $history -File -Force }
    )
    foreach ($file in $paths | Sort-Object FullName) {
        $path = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $file.FullName
        $files[[IO.Path]::GetRelativePath($SquadRoot, $path) -replace '\\', '/'] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    foreach ($name in $members.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $SquadRoot 'members' $name 'state.json') -Algorithm SHA256).Hash -cne $members[$name].stateHash) {
            throw 'A member changed while its federation snapshot was being captured.'
        }
    }
    [ordered]@{ schemaVersion = 1; squadRoot = $SquadRoot; files = $files; members = $members }
}

function New-SquadOrchestrationConsumption {
    param(
        [Parameter(Mandatory)][string]$RatesPath,
        [AllowEmptyString()][string]$SessionModel,
        [ValidateSet('fast', 'default', 'extended')][string]$FallbackTier = 'default'
    )
    $tables = @(Read-SquadTables $RatesPath)
    $modelTables = @($tables | Where-Object { 'Model (as routed)' -in $_.Header })
    $fallbackTables = @($tables | Where-Object { 'Priced as' -in $_.Header -and 'Tier' -in $_.Header })
    $floorTables = @($tables | Where-Object { 'Dispatch class' -in $_.Header })
    if ($modelTables.Count -ne 1 -or $fallbackTables.Count -ne 1 -or $floorTables.Count -ne 1) { throw 'Missing or ambiguous orchestration rate/estimator tables.' }
    $floors = @($floorTables[0].Rows | Where-Object { $_['Dispatch class'] -eq 'Scribe state write' })
    if ($floors.Count -ne 1) { throw 'Missing orchestration estimator floor.' }
    $sizes = @(
        foreach ($field in @('Internal turns', 'Base context', 'Growth/turn', 'Output/turn')) {
            $number = 0L
            if (-not [long]::TryParse(($floors[0][$field] -replace ',', ''), [ref]$number) -or $number -le 0) { throw 'Invalid orchestration estimator number.' }
            $number
        }
    )
    $concrete = $SessionModel.Trim() -notin @('', 'auto', 'unknown', 'fast', 'default', 'extended')
    $model = if ($concrete) { $SessionModel } else { 'unknown' }
    $key = ($model -replace '\s*\((?:copilot|github|anthropic|openai)\)\s*$', '' -replace '[\s_]+', '-').ToLowerInvariant()
    if ($key -in @('hydrafusion', 'hydrafusion-balance', 'hydrafusion-efficiency')) { $key = 'hydrafusion-max' }
    $own = @($modelTables[0].Rows | Where-Object { $key -in @(($_['Model (as routed)'] -replace '\s+', '-').ToLowerInvariant(), $_['Model ID'].Trim('`').ToLowerInvariant()) } | Select-Object -First 1)
    $tier = if ($own.Count) { $own[0].Tier } else { $FallbackTier }
    $fallback = @($fallbackTables[0].Rows | Where-Object { $_.Tier -eq $tier })
    if ($fallback.Count -ne 1) { throw 'Missing orchestration tier fallback.' }
    $price = if ($own.Count) { $own[0]['Model (as routed)'] } else { $fallback[0]['Priced as'] }
    $priceRows = @($modelTables[0].Rows | Where-Object { $_['Model (as routed)'] -eq $price })
    if ($priceRows.Count -ne 1) { throw 'Missing orchestration price row.' }
    $turns, $base, $growth, $output = $sizes
    $factor = if ($key -eq 'hydrafusion-max') { 0.35 } else { 1.0 }
    $gross = $turns * ($base + $growth * ($turns - 1) / 2.0) * $factor
    [ordered]@{
        model = $model; model_source = $(if ($concrete) { 'session-inherited' } else { 'unresolved' })
        priced_as = $price; model_tier = $tier; internal_turns = [long]$turns
        input_tokens = [long][Math]::Round($gross * 0.20); cached_tokens = [long][Math]::Round($gross * 0.80)
        cache_write_tokens = $(if ([double]$priceRows[0]['Cache write'] -gt 0) { [long][Math]::Round(($base + $growth * ($turns - 1)) * $factor) } else { 0L })
        output_tokens = [long]($turns * $output); basis = $(if ($concrete) { 'estimated' } else { 'tier-default' })
    }
}

function ConvertTo-SquadModelKey {
    param([AllowEmptyString()][AllowNull()][string]$Value)
    if (-not $Value) { return '' }
    $key = ($Value.Trim().Trim('`') -replace '\s*\((?:copilot|github|anthropic|openai)\)\s*$', '' -replace '[\s_]+', '-').ToLowerInvariant()
    if ($key -in @('hydrafusion', 'hydrafusion-balance', 'hydrafusion-efficiency')) { return 'hydrafusion-max' }
    $key
}

function Get-SquadRoleClassMap {
    param([string]$Path = (Join-Path $script:SkillRoot 'references' 'model-routing.md'))
    $section = Get-SquadReferenceSection -Path $Path -Heading '## Assignment Classes'
    $map = @{}
    foreach ($line in ($section -split '\r?\n')) {
        $match = [regex]::Match($line, '^\|\s*`(?<class>[a-z]+)`\s*\|(?<roles>.*)\|\s*$')
        if (-not $match.Success) { continue }
        foreach ($role in [regex]::Matches($match.Groups['roles'].Value, '`([a-z][a-z0-9-]*)`')) {
            if (-not $map.ContainsKey($role.Groups[1].Value)) {
                $map[$role.Groups[1].Value] = $match.Groups['class'].Value
            }
        }
    }
    $map
}

function Get-SquadDispatchReservation {
    <#
    .SYNOPSIS
        Prices one future dispatch from its actual role class and resolved model.
    #>
    param(
        [Parameter(Mandatory)][string]$RatesPath,
        [Parameter(Mandatory)][string]$Model,
        [ValidateSet('research', 'planning', 'implementation', 'review', 'council', 'intake', 'bookkeeping', 'coordinator')]
        [string]$AssignmentClass = 'implementation',
        [string]$DispatchClass,
        [ValidateRange(1, 1000)][int]$Count = 1
    )

    $tables = @(Read-SquadTables $RatesPath)
    $modelTables = @($tables | Where-Object { 'Model (as routed)' -in $_.Header -and 'Model ID' -in $_.Header })
    $floorTables = @($tables | Where-Object { 'Dispatch class' -in $_.Header -and 'Internal turns' -in $_.Header })
    if ($modelTables.Count -ne 1 -or $floorTables.Count -ne 1) { throw 'Missing or ambiguous model-rate or dispatch-class table.' }

    if (-not $DispatchClass) {
        $DispatchClass = switch ($AssignmentClass) {
            'research' { 'Research / file survey' }
            'planning' { 'Plan / synthesis' }
            'implementation' { 'Implement / edit loop' }
            'review' { 'Review / verification' }
            'intake' { 'Review / verification' }
            'council' { 'Council member opinion' }
            'bookkeeping' { 'Scribe state write' }
            'coordinator' { 'Lookup / single-file read' }
        }
    }

    $floor = @($floorTables[0].Rows | Where-Object { $_['Dispatch class'] -eq $DispatchClass })
    if ($floor.Count -ne 1) { throw "No unique dispatch estimator row for '$DispatchClass'." }
    $numbers = @()
    foreach ($field in @('Internal turns', 'Base context', 'Growth/turn', 'Output/turn')) {
        $value = 0L
        if (-not [long]::TryParse(($floor[0][$field] -replace ',', ''), [ref]$value) -or $value -le 0) {
            throw "Invalid '$field' in dispatch estimator row '$DispatchClass'."
        }
        $numbers += $value
    }
    $turns, $base, $growth, $outputPerTurn = $numbers

    $modelKey = ConvertTo-SquadModelKey $Model
    if (-not $modelKey -or $modelKey -in @('auto', 'unknown', 'fast', 'default', 'extended')) {
        throw "A concrete priced model is required for '$DispatchClass'; got '$Model'."
    }
    $modelRows = @($modelTables[0].Rows | Where-Object {
            $modelKey -in @(
                (ConvertTo-SquadModelKey $_['Model ID']),
                (ConvertTo-SquadModelKey $_['Model (as routed)'])
            )
        })
    if ($modelRows.Count -ne 1) { throw "No unique rate row for model '$Model'." }
    $rate = $modelRows[0]

    $threshold = $null
    $thresholdMatch = [regex]::Match([string]$rate['LC Threshold'], '(?<value>\d+(?:\.\d+)?)K')
    if ($thresholdMatch.Success) {
        $threshold = [double]$thresholdMatch.Groups['value'].Value * 1000.0
    }
    $largestContext = $base + $growth * ($turns - 1)
    $longContext = $null -ne $threshold -and $largestContext -gt $threshold
    $columns = if ($longContext) {
        @{ input = 'LC Input'; cached = 'LC Cached'; cacheWrite = 'LC Cache write'; output = 'LC Output' }
    }
    else {
        @{ input = 'Input'; cached = 'Cached'; cacheWrite = 'Cache write'; output = 'Output' }
    }
    $prices = @{}
    foreach ($name in $columns.Keys) {
        $raw = [string]$rate[$columns[$name]]
        $value = [decimal]0
        if ($raw -in @('', 'n/a') -or -not [decimal]::TryParse($raw, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or $value -lt 0) {
            throw "Invalid $($columns[$name]) rate for model '$Model'."
        }
        $prices[$name] = $value
    }

    $tokenFactor = if ($modelKey -eq 'hydrafusion-max') { [decimal]0.35 } else { [decimal]1 }
    $gross = [decimal]$turns * ([decimal]$base + [decimal]$growth * ($turns - 1) / 2) * $tokenFactor
    $inputTokens = [long][Math]::Round([double]($gross * [decimal]0.20))
    $cached = [long][Math]::Round([double]($gross * [decimal]0.80))
    $cacheWrite = if ($prices.cacheWrite -gt 0) {
        [long][Math]::Round([double](([decimal]$base + [decimal]$growth * ($turns - 1)) * $tokenFactor))
    }
    else { 0L }
    $output = [long]($turns * $outputPerTurn)
    $singleCost = (
        [decimal]$inputTokens * $prices.input +
        [decimal]$cached * $prices.cached +
        [decimal]$cacheWrite * $prices.cacheWrite +
        [decimal]$output * $prices.output
    ) / [decimal]1e6

    [pscustomobject][ordered]@{
        model = ([string]$rate['Model ID']).Trim('`')
        pricedAs = $rate['Model (as routed)']
        assignmentClass = $AssignmentClass
        dispatchClass = $DispatchClass
        count = $Count
        longContext = $longContext
        internalTurns = $turns
        inputTokens = $inputTokens * $Count
        cachedTokens = $cached * $Count
        cacheWriteTokens = $cacheWrite * $Count
        outputTokens = $output * $Count
        projectedCostUsd = $singleCost * $Count
    }
}

function Get-SquadDecision {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$SquadRoot,
        [Parameter(Mandatory)][string]$Reference
    )
    if ($Reference -notmatch '^(?<path>[^#]+)#(?<anchor>[^#\s]+)$') { throw 'A concrete decision anchor is required.' }
    $path = $Matches.path
    $anchor = $Matches.anchor
    $expected = Join-Path $SquadRoot 'decisions.md'
    $resolved = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $path -AllowMissing
    if ($resolved -ne $expected) {
        $resolved = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $SquadRoot $path)
        if ($resolved -ne $expected) { throw 'Decision references must belong to the selected squad.' }
    }
    $found = @(
        foreach ($section in [regex]::Matches([IO.File]::ReadAllText($resolved), '(?ms)^## (?<heading>[^\r\n]+)\r?\n(?<body>.*?)(?=^## |\z)')) {
            $slug = ($section.Groups['heading'].Value.ToLowerInvariant() -replace '[^\p{L}\p{Nd}_ -]', '') -replace ' ', '-'
            if ($slug -ceq $anchor) { $section }
        }
    )
    if ($found.Count -ne 1) { throw 'Decision anchor is missing or ambiguous.' }
    $found[0]
}

function Get-SquadPendingConnectors {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$SquadRoot)
    $tables = @(Read-SquadTables (Join-Path $SquadRoot 'team.md') | Where-Object { 'Manifest' -in $_.Header -and 'Binding ID' -in $_.Header })
    $tasks = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($table in $tables) {
        foreach ($binding in $table.Rows) {
            $manifestPath = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $binding.Manifest
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
            if (-not $manifest.Contains('dropPath') -or $manifest.dropPath -isnot [string]) { throw 'Registered connector manifest is missing dropPath.' }
            $drop = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $manifest.dropPath -AllowMissing
            $privateRoot = Join-Path $drop '.squad-connector'
            if (-not (Test-Path -LiteralPath $privateRoot -PathType Container)) { continue }
            $null = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $privateRoot
            foreach ($file in Get-ChildItem -LiteralPath $privateRoot -File -Filter '*.state.json') {
                $path = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path $file.FullName
                if (-not $seen.Add($path)) { continue }
                $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
                if (-not $state.Contains('consumed') -or $state.consumed -isnot [bool] -or -not $state.Contains('taskId')) { throw 'Malformed connector dispatch state; resolve its pending identity before new work.' }
                if ($state.consumed) { continue }
                $id = $state.taskId
                if ($id -isnot [string] -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid pending connector task id.' }
                $requestPath = Resolve-SquadRepositoryPath -RepoRoot $RepoRoot -Path (Join-Path $drop "$id.request.json")
                $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json -AsHashtable
                if ($request.taskId -cne $id -or $request.connectorId -cne $manifest.connectorId) { throw 'Pending connector request identity mismatch.' }
                $tasks.Add([ordered]@{
                        taskId = $id; connectorId = $request.connectorId; role = $request.role
                        requestPath = $requestPath; statePath = $path; manifestPath = $manifestPath
                        resultAvailable = Test-Path -LiteralPath (Join-Path $drop "$id.result.json") -PathType Leaf
                    })
            }
        }
    }
    $tasks.ToArray()
}

Export-ModuleMember -Function Read-SquadTables, Get-SquadReferenceSection, Get-SquadRulePath, Resolve-SquadRepositoryPath, Get-SquadAgentIndex, Get-SquadRoster, Invoke-SquadLocalScript, Get-SquadInitData, New-SquadInitPayload, Resolve-SquadConnectorExecution, Write-SquadTransportJson, Get-SquadFederationSnapshot, New-SquadOrchestrationConsumption, ConvertTo-SquadModelKey, Get-SquadRoleClassMap, Get-SquadDispatchReservation, Get-SquadDecision, Get-SquadPendingConnectors
