#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Behavioral coverage for the deterministic hand-off writer, squad skill
# scripts/Write-SquadHandoff.ps1. Runs it as a child process against TestDrive copies of
# the scribe-benchmark seed fixture, because it calls `exit`. Invokes no model.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    $skillRoot = Join-Path $PackageRoot '.agents/skills/squad'
    $script:Writer = Join-Path $skillRoot 'scripts/Write-SquadHandoff.ps1'
    $script:Ledger = Join-Path $skillRoot 'scripts/Measure-SquadLedger.ps1'
    $script:Seeder = Join-Path $skillRoot 'scripts/Initialize-SquadConsumptionRates.ps1'
    $script:FixtureRoot = Join-Path $PSScriptRoot '../fixtures/scribe-benchmark'
    # An empty COPILOT_HOME keeps `-SessionLog auto` from reading a real developer session.
    $env:COPILOT_HOME = Join-Path $TestDrive 'copilot-home'

    function Set-RoutingLine {
        # The script is economy-only; the line sits directly beneath team.md's H1, as model-routing.md defines.
        param([string]$Root, [AllowEmptyString()][string]$Line = 'Model routing: economy')
        $team = Join-Path $Root 'team.md'
        $text = (Get-Content -LiteralPath $team -Raw) -replace "`r`n", "`n" -replace '(?m)^Model routing:[^\n]*\n\n?', ''
        if ($Line) { $text = [regex]::Replace($text, '(?m)^(# [^\n]*\n)', "`$1`n$Line`n", 1) }
        [System.IO.File]::WriteAllText($team, $text, [System.Text.UTF8Encoding]::new($false))
    }

    # Snapshot and verify modes check the same team.md before touching anything.
    $script:SnapRoot = Join-Path $TestDrive 'snap-squad'
    New-Item -ItemType Directory -Path $script:SnapRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:SnapRoot 'team.md') -Value "# Squad Roster`n`nModel routing: economy`n" -Encoding utf8NoBOM

    function New-Root {
        # A repository whose .copilot-tracking/squad root is a copy of the seed fixture, with the two agent
        # files the attribution checks read. -Member roots the squad under a federation (members/alpha).
        param([switch]$Member)
        $repo = Join-Path $TestDrive "repo-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $tracking = Join-Path $repo '.copilot-tracking/squad'
        if ($Member) { New-Item -ItemType Directory -Path (Join-Path $tracking 'members') -Force | Out-Null; $root = Join-Path $tracking 'members/alpha' }
        else { New-Item -ItemType Directory -Path (Join-Path $repo '.copilot-tracking') -Force | Out-Null; $root = $tracking }
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'seed') -Destination $root -Recurse
        Remove-Item -LiteralPath (Join-Path $root 'history/.gitkeep') -ErrorAction SilentlyContinue
        $agents = Join-Path $repo '.github/agents/squad'
        New-Item -ItemType Directory -Path $agents -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $agents 'squad-researcher.agent.md') -Value "---`nname: Squad Researcher`nmodel: Claude Sonnet 4.6 (copilot)`n---`n# Researcher`n"
        Set-Content -LiteralPath (Join-Path $agents 'squad-scribe.agent.md') -Value "---`nname: Squad Scribe`nmodel: Claude Haiku 4.5 (copilot)`n---`n# Scribe`n"
        (Get-Item -LiteralPath (Join-Path $root 'research/2026-09-27-fixture-topic.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T09:30:00Z').ToUniversalTime()
        Set-RoutingLine -Root $root
        $root
    }

    function New-Payload {
        param([hashtable]$Override = @{})
        $consumption = [ordered]@{ model = 'Claude Sonnet 4.6'; model_source = 'session-inherited'; priced_as = 'Claude Sonnet 4.6'; model_tier = 'default'; internal_turns = 12; input_tokens = 9600; cached_tokens = 38400; cache_write_tokens = 8000; output_tokens = 15000; basis = 'estimated' }
        $orchestration = [ordered]@{ model = 'Claude Haiku 4.5'; model_source = 'session-inherited'; priced_as = 'Claude Haiku 4.5'; model_tier = 'fast'; internal_turns = 4; input_tokens = 3000; cached_tokens = 12000; cache_write_tokens = 1250; output_tokens = 3200; basis = 'estimated' }
        $payload = [ordered]@{
            runId          = 'rp-fixture-01'
            turn           = 2
            mode           = 'interactive'
            timestamp      = '2026-09-27T10:00:00Z'
            route          = 'standard'
            decision       = [ordered]@{ title = 'Adopt the two-role fixture'; rationale = 'A full profile adds no coverage the checks need.'; adrNoted = $false }
            historyRecords = @([ordered]@{ agent = 'Squad Researcher'; request = 'Survey the fixture-topic conventions.'; deliverable = 'research/2026-09-27-fixture-topic.md (~1,800 words)'; outcome = 'Surveyed three fixtures.'; consumption = $consumption })
            orchestration  = [ordered]@{ consumption = $orchestration }
            stateAdvance   = [ordered]@{ activeRoles = @('Squad Researcher') }
        }
        foreach ($key in $Override.Keys) { $payload[$key] = $Override[$key] }
        $payload
    }

    function Invoke-Writer {
        param([string]$Root, $Payload)
        $json = $Payload | ConvertTo-Json -Depth 8
        $file = Join-Path $TestDrive "payload-$([guid]::NewGuid().ToString('N')).json"
        Set-Content -LiteralPath $file -Value $json -Encoding utf8NoBOM
        $output = & pwsh -NoProfile -File $script:Writer -SquadRoot $Root -PayloadPath $file *>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    function Get-TreeHash {
        param([string]$Root)
        (Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
                '{0}:{1}' -f [System.IO.Path]::GetRelativePath($Root, $_.FullName), (Get-FileHash -LiteralPath $_.FullName).Hash
            }) -join "`n"
    }

    function Invoke-LedgerCheck {
        param([string]$Root, [string]$Counts)
        $output = & pwsh -NoProfile -File $script:Ledger -SquadRoot $Root -Check -ExpectedHistoryCounts $Counts *>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }
}

Describe 'Write-SquadHandoff.ps1 writes an ordinary hand-off and verifies the ledger' {
    It 'records a host substitution truthfully while preserving the different requested model' {
        $root = New-Root
        $payload = New-Payload
        $record = $payload.historyRecords[0]
        $record.passedModel = 'gpt-5.3-codex'
        $record.consumption.model_source = 'dispatch-reported'
        $record.routingIdentity = @{
            requestedModel = 'gpt-5.3-codex'; effectiveModel = 'Claude Sonnet 4.6'; observedModel = 'Claude Sonnet 4.6'
            routeRationale = 'Route: economy; owning role researcher; floor default; identity-mismatch: requested gpt-5.3-codex, observed Claude Sonnet 4.6'
        }
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $history = Get-Content -LiteralPath (Join-Path $root 'history\Squad Researcher.md') -Raw
        $history | Should -Match '"model_source": "dispatch-reported"'
        $history | Should -Match '\*\*Requested model\*\*.*gpt-5.3-codex'
        $history | Should -Match '\*\*Observed model\*\*.*Claude Sonnet 4.6'
        (Invoke-LedgerCheck -Root $root -Counts 'Squad Researcher=1;Squad Scribe=1').ExitCode | Should -Be 0
    }

    It 'refuses success-shaped identity bullets that price a substituted model as the request' {
        $root = New-Root
        $payload = New-Payload
        $record = $payload.historyRecords[0]
        $record.passedModel = 'gpt-5.3-codex'
        $record.consumption.model_source = 'dispatch-reported'
        $record.routingIdentity = @{
            requestedModel = 'gpt-5.3-codex'; effectiveModel = 'gpt-5.3-codex'; observedModel = 'gpt-5.3-codex'
            routeRationale = 'Route: economy; owning role researcher'
        }
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'effectiveModel must equal consumption.model'
        $result.Output | Should -Match 'observedModel must equal the host-reported'
        Get-TreeHash $root | Should -Be $before
    }

    It 'keeps explicit auto requests distinct from unresolved attribution and refuses a claimed pin under auto' {
        $root = New-Root
        $payload = New-Payload
        $payload.stateAdvance.sessionModel = 'auto'
        $payload.orchestration.consumption.model = 'unknown'
        $payload.orchestration.consumption.model_source = 'unresolved'
        $payload.orchestration.consumption.basis = 'tier-default'
        $payload.orchestration.consumption.Remove('priced_as')
        $record = $payload.historyRecords[0]
        $record.passedModel = 'gpt-5.3-codex'
        $record.consumption.model = 'unknown'
        $record.consumption.model_source = 'unresolved'
        $record.consumption.basis = 'tier-default'
        $record.consumption.Remove('priced_as')
        $record.routingIdentity = @{
            requestedModel = 'gpt-5.3-codex'; effectiveModel = 'unknown'; observedModel = 'unreported'
            routeRationale = 'Route: economy; owning role researcher; auto-unreported'
        }
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $history = Get-Content -LiteralPath (Join-Path $root 'history\Squad Researcher.md') -Raw
        $history | Should -Match '"model": "unknown"'
        $history | Should -Match '"model_source": "unresolved"'
        $history | Should -Match '\*\*Requested model\*\*.*gpt-5.3-codex'

        $root = New-Root
        $payload = New-Payload
        $payload.stateAdvance.sessionModel = 'auto'
        $payload.historyRecords[0].consumption.model_source = 'agent-pinned'
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'under auto without a host report'
        Get-TreeHash $root | Should -Be $before
    }

    It 'ships in the squad skill' {
        Test-Path -LiteralPath $script:Writer -PathType Leaf | Should -BeTrue
    }

    It 'writes the expected files, passes -Check, and matches the checked-in applied fixture figures' {
        $root = New-Root
        $before = (Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName) })
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Measure-SquadLedger -Check: PASS'
        $after = (Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName) })
        @($after | Where-Object { $_ -notin $before } | Sort-Object) | Should -Be @((Join-Path 'history' 'Squad Researcher.md'), (Join-Path 'history' 'Squad Scribe.md') | Sort-Object)

        $check = Invoke-LedgerCheck -Root $root -Counts 'Squad Researcher=1;Squad Scribe=1'
        $check.ExitCode | Should -Be 0 -Because $check.Output

        $researcher = (Get-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Raw) -replace "`r`n", "`n"
        $applied = (Get-Content -LiteralPath (Join-Path $script:FixtureRoot 'applied/history/Squad Researcher.md') -Raw) -replace "`r`n", "`n"
        $block = [regex]::Match($applied, '(?s)#### Consumption\n\n```json\n.*?\n```').Value
        $researcher | Should -Match '(?m)^# History: Squad Researcher$'
        $researcher | Should -Match ([regex]::Escape($block))
        $scribe = (Get-Content -LiteralPath (Join-Path $root 'history/Squad Scribe.md') -Raw) -replace "`r`n", "`n"
        $scribe | Should -Match '(?m)^#### Consumption — Orchestration$'

        $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json
        $state.currentRun.estCostUsd | Should -Be 0.3171
        $state.currentRun.estCreditsTotal | Should -Be 31.71
        (Get-Content -LiteralPath (Join-Path $root 'consumption.md') -Raw) | Should -Match '# Squad Consumption Ledger \(Run: rp-fixture-01\)'
    }

    It 'advances state.json with the closed key set intact and every untouched field preserved' {
        $root = New-Root
        $seedState = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json
        $payload = New-Payload
        $payload.stateAdvance = [ordered]@{ activeRoles = @('Squad Researcher'); openEscalationsRaised = @('esc-1'); sessionModel = 'Claude Haiku 4.5'; modelOverrides = [ordered]@{ researcher = 'Claude Sonnet 4.6' } }
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json
        @($state.PSObject.Properties.Name) | Should -Be @($seedState.PSObject.Properties.Name)
        @($state.currentRun.PSObject.Properties.Name) | Should -Be @($seedState.currentRun.PSObject.Properties.Name)
        $state.turn | Should -Be 2
        $state.mode | Should -Be 'interactive'
        @($state.activeRoles) | Should -Be @('Squad Researcher')
        @($state.openEscalations) | Should -Be @('esc-1')
        $state.currentRun.sessionModel | Should -Be 'Claude Haiku 4.5'
        $state.currentRun.modelOverrides.researcher | Should -Be 'Claude Sonnet 4.6'
        ($state.currentRun.costPreflight | ConvertTo-Json -Depth 4) | Should -Be ($seedState.currentRun.costPreflight | ConvertTo-Json -Depth 4)
        ($state.notify | ConvertTo-Json -Depth 4) | Should -Be ($seedState.notify | ConvertTo-Json -Depth 4)
    }

    It 'rejects an illegal model_source, an unknown field, a non-integer count, and a combined basis without writing' {
        $cases = @{
            'illegal model_source' = { param($p) $p.historyRecords[0].consumption.model_source = 'guessed' }
            'unknown field'        = { param($p) $p.historyRecords[0].consumption['est_cost_usd'] = 1 }
            'non-integer count'    = { param($p) $p.historyRecords[0].consumption.input_tokens = 1.5 }
            'combined basis'       = { param($p) $p.historyRecords[0].consumption.basis = 'estimated|tier-default' }
        }
        foreach ($name in $cases.Keys) {
            $root = New-Root
            $payload = New-Payload
            & $cases[$name] $payload
            $before = Get-TreeHash $root
            $result = Invoke-Writer -Root $root -Payload $payload
            $result.ExitCode | Should -Be 1 -Because "$name : $($result.Output)"
            Get-TreeHash $root | Should -Be $before -Because "$name must write nothing"
        }
    }

    It 'sends payloads it cannot validate to the Scribe without writing: slug agent, ceiling, federation, secret-like text' {
        $slug = New-Payload
        $slug.historyRecords[0].agent = 'squad-researcher'
        $secret = New-Payload
        $secret.historyRecords[0].outcome = 'Set the api_key= value in config.'
        foreach ($case in @(@{ Name = 'slug agent'; Root = (New-Root); Payload = $slug }, @{ Name = 'secret-like text'; Root = (New-Root); Payload = $secret })) {
            $before = Get-TreeHash $case.Root
            $result = Invoke-Writer -Root $case.Root -Payload $case.Payload
            $result.ExitCode | Should -Be 2 -Because "$($case.Name): $($result.Output)"
            Get-TreeHash $case.Root | Should -Be $before
        }

        $ceilingRoot = New-Root
        $statePath = Join-Path $ceilingRoot 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $state.currentRun.costPreflight.ceilingUsd = 5
        $state.currentRun.costPreflight.decision = 'within-ceiling'
        $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        $before = Get-TreeHash $ceilingRoot
        (Invoke-Writer -Root $ceilingRoot -Payload (New-Payload)).ExitCode | Should -Be 2
        Get-TreeHash $ceilingRoot | Should -Be $before

        $federationRoot = New-Root
        Set-Content -LiteralPath (Join-Path $federationRoot 'federation.md') -Value '# Federation'
        $before = Get-TreeHash $federationRoot
        (Invoke-Writer -Root $federationRoot -Payload (New-Payload)).ExitCode | Should -Be 2
        Get-TreeHash $federationRoot | Should -Be $before
    }

    It 'refuses a malformed operator rate row with exit 4 and writes nothing' {
        $root = New-Root
        $seed = & pwsh -NoProfile -File $script:Seeder -SquadRoot $root *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $seed
        $path = Join-Path $root 'consumption-rates.md'
        $bad = '| Mystery | mystery | bogus | x | 0.30 | 3.75 | 15.00 | none (flat rate) | n/a | n/a | n/a | n/a | bad |'
        $text = ((Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n") -replace '(?m)^\| \(additional\)', ($bad + "`n| (additional)")
        [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 4 -Because $result.Output
        $result.Output | Should -Match 'Mystery'
        Get-TreeHash $root | Should -Be $before
    }

    It 'refuses the same payload twice: a replay writes nothing more' {
        $root = New-Root
        (Invoke-Writer -Root $root -Payload (New-Payload)).ExitCode | Should -Be 0
        $before = Get-TreeHash $root
        $replay = Invoke-Writer -Root $root -Payload (New-Payload)
        $replay.ExitCode | Should -Be 1 -Because $replay.Output
        Get-TreeHash $root | Should -Be $before
    }

    It 'restores every touched file, including a hand-written consumption.md that was reseeded, when a later step fails' {
        $root = New-Root
        $ledgerPath = Join-Path $root 'consumption.md'
        [System.IO.File]::WriteAllText($ledgerPath, "# Hand-written notes`n`nNo ledger sections here.`n", [System.Text.UTF8Encoding]::new($false))
        # A second numeric estCostUsd in state.json makes the ledger -Write refuse after the reseed.
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $state.notify | Add-Member -NotePropertyName estCostUsd -NotePropertyValue 1
        $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 3 -Because $result.Output
        $result.Output | Should -Match 'restored'
        Get-TreeHash $root | Should -Be $before
        (Get-Content -LiteralPath $ledgerPath -Raw) | Should -Match 'No ledger sections here'
        Test-Path -LiteralPath (Join-Path $root 'history/Squad Researcher.md') | Should -BeFalse
    }

    It 'accepts a roster whose primary column is headed Primary' {
        $root = New-Root
        $team = Join-Path $root 'team.md'
        $text = (Get-Content -LiteralPath $team -Raw) -replace 'Agent Name \(Primary\)', 'Primary'
        $text | Should -Not -Match 'Agent Name \(Primary\)'
        [System.IO.File]::WriteAllText($team, $text, [System.Text.UTF8Encoding]::new($false))
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        Test-Path -LiteralPath (Join-Path $root 'history/Squad Researcher.md') | Should -BeTrue
    }

    It 'adds the exact unset default to a state without costPreflight: 1.3 becomes 1.4, 1.4 stays 1.4' -ForEach @(
        @{ From = '1.3'; To = '1.4' }
        @{ From = '1.4'; To = '1.4' }
    ) {
        $root = New-Root
        $statePath = Join-Path $root 'state.json'
        $seed = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $expected = $seed.currentRun.costPreflight | ConvertTo-Json -Depth 4 -Compress
        $seed.schemaVersion = $From
        $seed.currentRun.PSObject.Properties.Remove('costPreflight')
        $seed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $state.schemaVersion | Should -Be $To
        ($state.currentRun.costPreflight | ConvertTo-Json -Depth 4 -Compress) | Should -Be $expected
        $state.currentRun.costPreflight.ceilingUsd | Should -BeNullOrEmpty
        $state.currentRun.costPreflight.decision | Should -Be 'not-requested'
    }

    It 'still sends a configured ceiling to the Scribe at 1.3 and refuses a non-object costPreflight, writing nothing' {
        foreach ($case in @(
                @{ Version = '1.3'; Mutate = { param($s) $s.currentRun.costPreflight.ceilingUsd = 5; $s.currentRun.costPreflight.decision = 'within-ceiling' } }
                @{ Version = '1.4'; Mutate = { param($s) $s.currentRun.costPreflight = 'none' } }
            )) {
            $root = New-Root
            $statePath = Join-Path $root 'state.json'
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $state.schemaVersion = $case.Version
            & $case.Mutate $state
            $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
            $before = Get-TreeHash $root
            $result = Invoke-Writer -Root $root -Payload (New-Payload)
            $result.ExitCode | Should -Be 2 -Because $result.Output
            Get-TreeHash $root | Should -Be $before
        }
    }

    It 're-seeds a hand-written consumption.md without the ledger sections from the template, and -Check passes' {
        $root = New-Root
        $ledgerPath = Join-Path $root 'consumption.md'
        [System.IO.File]::WriteAllText($ledgerPath, "# Hand-written notes`n`nNo ledger sections here.`n", [System.Text.UTF8Encoding]::new($false))
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'RESEEDED consumption.md'
        $ledger = (Get-Content -LiteralPath $ledgerPath -Raw) -replace "`r`n", "`n"
        $ledger | Should -Match '(?m)^## Attribution\s*$'
        $ledger | Should -Match '(?m)^## Usage & Cost\s*$'
        $ledger | Should -Match '(?m)^### Derivation\s*$'
        $ledger | Should -Match '# Squad Consumption Ledger \(Run: rp-fixture-01\)'
        $ledger | Should -Not -Match 'No ledger sections here|<run-id>'
        $check = Invoke-LedgerCheck -Root $root -Counts 'Squad Researcher=1;Squad Scribe=1'
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }
}

Describe 'Write-SquadHandoff.ps1 reads only the roster table, prices from the model''s own row, and guards ledger and timestamp' {
    It 'ignores an Agent table before the roster and rows after it, while still admitting the real roster agent' {
        $root = New-Root
        $team = Join-Path $root 'team.md'
        $text = (Get-Content -LiteralPath $team -Raw) -replace "`r`n", "`n"
        $text = $text.Replace('## Members', "## Pins`n`n| Agent | Pin |`n| --- | --- |`n| Bogus Agent | none |`n`n## Members")
        $text += "`nTrailing notes`n`n| Name | Agent |`n| --- | --- |`n| Injected Name | x |`n"
        [System.IO.File]::WriteAllText($team, $text, [System.Text.UTF8Encoding]::new($false))
        foreach ($name in @('Bogus Agent', 'Injected Name')) {
            $payload = New-Payload
            $payload.historyRecords[0].agent = $name
            $before = Get-TreeHash $root
            $result = Invoke-Writer -Root $root -Payload $payload
            $result.ExitCode | Should -Be 2 -Because "$name : $($result.Output)"
            Get-TreeHash $root | Should -Be $before
        }
        $ok = Invoke-Writer -Root $root -Payload (New-Payload)
        $ok.ExitCode | Should -Be 0 -Because $ok.Output
    }

    It 'prices at the model''s own rate row, and at the tier fallback row only for a model with no row, correcting a supplied mismatch' {
        $other = New-Payload
        $other.historyRecords[0].consumption.priced_as = 'Claude Haiku 4.5'
        $root = New-Root
        $result = Invoke-Writer -Root $root -Payload $other
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match ([regex]::Escape("priced_as 'Claude Haiku 4.5' replaced by 'Claude Sonnet 4.6'"))
        (Get-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Raw) | Should -Match '"priced_as": "Claude Sonnet 4\.6"'

        foreach ($priced in 'Claude Haiku 4.5', 'Claude Sonnet 4.6') {
            $unlisted = New-Payload
            $c = $unlisted.historyRecords[0].consumption
            $c.model = 'Unlisted Model X'; $c.model_source = 'dispatch-reported'; $c.priced_as = $priced
            $fresh = New-Root
            $result = Invoke-Writer -Root $fresh -Payload $unlisted
            $result.ExitCode | Should -Be 0 -Because "$($priced): $($result.Output)"
            (Get-Content -LiteralPath (Join-Path $fresh 'history/Squad Researcher.md') -Raw) | Should -Match '"priced_as": "Claude Sonnet 4\.6"'
        }

        $byId = New-Payload
        $byId.historyRecords[0].consumption.model = 'claude-sonnet-4.6'
        $ok = Invoke-Writer -Root (New-Root) -Payload $byId
        $ok.ExitCode | Should -Be 0 -Because $ok.Output
    }

    It 'sends a consumption.md with only some ledger headings to the Scribe, and reseeds only one with none' -ForEach @(
        @{ Name = 'double-space Attribution only'; Body = "# Squad Consumption Ledger (Run: x)`n`n##  Attribution`n`nOperator note.`n" }
        @{ Name = 'Usage and Cost only'; Body = "# Notes`n`n## Usage & Cost`n`nhand total `$0.40`n" }
        @{ Name = 'Derivation only'; Body = "# Notes`n`n### Derivation`n" }
    ) {
        $root = New-Root
        [System.IO.File]::WriteAllText((Join-Path $root 'consumption.md'), $Body, [System.Text.UTF8Encoding]::new($false))
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 2 -Because "$Name : $($result.Output)"
        $result.Output | Should -Match 'some but not all'
        Get-TreeHash $root | Should -Be $before
    }

    It 'refuses a timestamp earlier than a deliverable''s last write, allowing 5 s of skew' {
        $root = New-Root
        $artifact = Join-Path $root 'research/2026-09-27-fixture-topic.md'
        (Get-Item -LiteralPath $artifact).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T10:00:30Z').ToUniversalTime()
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'precedes the last write'
        Get-TreeHash $root | Should -Be $before

        (Get-Item -LiteralPath $artifact).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T10:00:04Z').ToUniversalTime()
        $ok = Invoke-Writer -Root $root -Payload (New-Payload)
        $ok.ExitCode | Should -Be 0 -Because $ok.Output
    }

    It 'strips only a vendor suffix from a model pin: a (fast mode) model is not its base model' {
        $payload = New-Payload
        $c = $payload.historyRecords[0].consumption
        $c.model = 'Claude Opus 4.8 (fast mode)'; $c.model_source = 'cli-pinned'; $c.priced_as = 'Claude Opus 4.8 (fast mode)'; $c.model_tier = 'extended'
        $payload.historyRecords[0].passedModel = 'claude-opus-4.8'
        $root = New-Root
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'must equal the passedModel'
        Get-TreeHash $root | Should -Be $before

        $vendor = New-Payload
        $vendor.historyRecords[0].consumption.model_source = 'cli-pinned'
        $vendor.historyRecords[0].passedModel = 'claude-sonnet-4.6 (copilot)'
        $ok = Invoke-Writer -Root (New-Root) -Payload $vendor
        $ok.ExitCode | Should -Be 0 -Because $ok.Output
    }
}

Describe 'Write-SquadHandoff.ps1 derives priced_as and checks the closing review saw the final files' {
    BeforeAll {
        function New-ReviewRoot {
            # The fixture root plus a tester row (Squad Reviewer, pinned Claude Haiku 4.5) and its review artifact.
            $root = New-Root
            $repo = (Resolve-Path (Join-Path $root '../..')).Path
            $team = Join-Path $root 'team.md'
            $text = (Get-Content -LiteralPath $team -Raw) -replace "`r`n", "`n"
            $text = $text -replace '(?m)^(\| scribe .*)$', "`$1`n| tester     | Beta        | Squad Reviewer        | —                  | —              | runSubagent / task | fast       | reviews/           |"
            [System.IO.File]::WriteAllText($team, $text, [System.Text.UTF8Encoding]::new($false))
            Set-Content -LiteralPath (Join-Path $repo '.github/agents/squad/squad-reviewer.agent.md') -Value "---`nname: Squad Reviewer`nmodel: Claude Haiku 4.5 (copilot)`n---`n# Reviewer`n"
            New-Item -ItemType Directory -Path (Join-Path $root 'reviews') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'reviews/review.md') -Value 'review'
            (Get-Item -LiteralPath (Join-Path $root 'reviews/review.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T09:40:00Z').ToUniversalTime()
            $root
        }

        function New-ReviewPayload {
            param([string]$Model = 'Claude Haiku 4.5', [string]$Source = 'agent-pinned', [string]$Passed)
            $payload = New-Payload
            $review = [ordered]@{ agent = 'Squad Reviewer'; request = 'Review the final files.'; deliverable = 'reviews/review.md'; outcome = 'Approved.'
                consumption = [ordered]@{ model = $Model; model_source = $Source; model_tier = 'fast'; internal_turns = 3; input_tokens = 1000; cached_tokens = 2000; cache_write_tokens = 500; output_tokens = 800; basis = 'estimated' } }
            if ($Passed) { $review['passedModel'] = $Passed }
            $payload.historyRecords = @($payload.historyRecords[0], $review)
            $payload
        }
    }

    It 'derives an omitted priced_as and still writes it, in contractual order, into the history block' {
        $payload = New-Payload
        $payload.historyRecords[0].consumption.Remove('priced_as')
        $payload.orchestration.consumption.Remove('priced_as')
        $root = New-Root
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Measure-SquadLedger -Check: PASS'
        $history = (Get-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Raw) -replace "`r`n", "`n"
        $history | Should -Match '"model": "Claude Sonnet 4\.6",\n  "model_source": "session-inherited",\n  "priced_as": "Claude Sonnet 4\.6",\n  "model_tier": "default"'

        $unlisted = New-Payload
        $c = $unlisted.historyRecords[0].consumption
        $c.model = 'Unlisted Model X'; $c.model_source = 'dispatch-reported'; $c.Remove('priced_as')
        $fresh = New-Root
        $ok = Invoke-Writer -Root $fresh -Payload $unlisted
        $ok.ExitCode | Should -Be 0 -Because $ok.Output
        (Get-Content -LiteralPath (Join-Path $fresh 'history/Squad Researcher.md') -Raw) | Should -Match '"priced_as": "Claude Sonnet 4\.6"'
    }

    It 'accepts a backticked model id and a missing cli-pinned passedModel, deriving both' {
        $payload = New-Payload
        $c = $payload.historyRecords[0].consumption
        $c.model = '`claude-sonnet-4.6`'; $c.model_source = 'cli-pinned'; $c.priced_as = '`claude-sonnet-4.6`'
        $root = New-Root
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'passedModel omitted'
        (Get-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Raw) | Should -Match '"model": "claude-sonnet-4\.6",\n  "model_source": "cli-pinned",\n  "priced_as": "Claude Sonnet 4\.6"'
    }

    It 'refuses with exit 1 and writes nothing when an owner deliverable changed after the closing review' {
        $root = New-ReviewRoot
        $owner = Join-Path $root 'research/2026-09-27-fixture-topic.md'
        (Get-Item -LiteralPath $owner).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T09:45:00Z').ToUniversalTime()
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload (New-ReviewPayload)
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'owner deliverable research/2026-09-27-fixture-topic\.md changed after the closing review; re-dispatch the review'
        Get-TreeHash $root | Should -Be $before
    }

    It 'admits an owner deliverable within 2 s of the review and one older than it, and omits priced_as for the review' {
        $root = New-ReviewRoot
        $owner = Join-Path $root 'research/2026-09-27-fixture-topic.md'
        (Get-Item -LiteralPath $owner).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T09:40:02Z').ToUniversalTime()
        $result = Invoke-Writer -Root $root -Payload (New-ReviewPayload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        @($result.Output -split "`n" | Where-Object { $_ -match 'WARN' -and $_ -notmatch 'economy consent not recorded|no routingIdentity' }) | Should -BeNullOrEmpty

        $older = New-ReviewRoot
        $ok = Invoke-Writer -Root $older -Payload (New-ReviewPayload)
        $ok.ExitCode | Should -Be 0 -Because $ok.Output
    }
}

Describe 'Write-SquadHandoff.ps1 runs only under Model routing: economy (G2)' {
    It 'refuses a hand-off with exit 7 and changes nothing when team.md records <Case>' -ForEach @(
        @{ Case = 'Model routing: ranked'; Line = 'Model routing: ranked' }
        @{ Case = 'Model routing: manual'; Line = 'Model routing: manual' }
        @{ Case = 'no Model routing line'; Line = '' }
    ) {
        $root = New-Root
        Set-RoutingLine -Root $root -Line $Line
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 7 -Because $result.Output
        $result.Output | Should -Match 'economy-only'
        Get-TreeHash $root | Should -BeExactly $before
    }

    It 'refuses snapshot and verify modes with exit 7 outside economy' {
        $off = Join-Path $TestDrive 'snap-off'
        New-Item -ItemType Directory -Path (Join-Path $off 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $off 'team.md') -Value "# Squad Roster`n" -Encoding utf8NoBOM
        Set-Content -LiteralPath (Join-Path $off 'src/a.txt') -Value 'a'
        $snapshot = Join-Path $TestDrive 'snap-off.json'
        $record = & pwsh -NoProfile -File $script:Writer -SquadRoot $off -SnapshotPath $snapshot -Path 'src' -RepoRoot $off *>&1 | Out-String
        $LASTEXITCODE | Should -Be 7 -Because $record
        Test-Path -LiteralPath $snapshot | Should -BeFalse
        $verify = & pwsh -NoProfile -File $script:Writer -SquadRoot $off -VerifySnapshotPath $snapshot *>&1 | Out-String
        $LASTEXITCODE | Should -Be 7 -Because $verify
    }

    It 'accepts the literal payload example in economy-mode.md' {
        $doc = (Get-Content -LiteralPath (Join-Path $PackageRoot '.agents/skills/squad/references/economy-mode.md') -Raw) -replace "`r`n", "`n"
        $example = [regex]::Match($doc, '(?s)This is a complete, valid payload:\n\n```json\n(?<json>.*?)\n```').Groups['json'].Value
        $example | Should -Not -BeNullOrEmpty
        $root = New-Root
        $file = Join-Path $TestDrive "example-$([guid]::NewGuid().ToString('N')).json"
        [System.IO.File]::WriteAllText($file, $example, [System.Text.UTF8Encoding]::new($false))
        $output = & pwsh -NoProfile -File $script:Writer -SquadRoot $root -PayloadPath $file *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output | Should -Match 'Measure-SquadLedger -Check: PASS'
    }

    It 'refuses a handoff value other than script' {
        $root = New-Root
        $payload = New-Payload
        $payload['handoff'] = 'manual'
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match "payload.handoff must be 'script'"
    }

    It 'waits for the per-root lock and exits 8, writing nothing, when it is never released' {
        $root = New-Root
        $full = (Get-Item -LiteralPath $root).FullName.TrimEnd('\', '/').ToLowerInvariant()
        $key = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($full))).Substring(0, 16)
        $lockPath = Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-handoff-$key.lock"
        $before = Get-TreeHash $root
        $held = [System.IO.FileStream]::new($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $file = Join-Path $TestDrive "lock-$([guid]::NewGuid().ToString('N')).json"
            Set-Content -LiteralPath $file -Value (New-Payload | ConvertTo-Json -Depth 8) -Encoding utf8NoBOM
            $blocked = & pwsh -NoProfile -File $script:Writer -SquadRoot $root -PayloadPath $file -LockTimeoutSeconds 1 *>&1 | Out-String
            $LASTEXITCODE | Should -Be 8 -Because $blocked
            Get-TreeHash $root | Should -BeExactly $before
        }
        finally { $held.Dispose() }
        $after = & pwsh -NoProfile -File $script:Writer -SquadRoot $root -PayloadPath $file -LockTimeoutSeconds 1 *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because "the lock is released with its handle: $after"
    }
}

Describe 'Write-SquadHandoff.ps1 deliverable snapshot' {
    It 'reports UNCHANGED, then exit 5 after a deliverable changes, and refuses paths outside the repo root' {
        $repo = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'src/app.txt') -Value 'one'
        $snapshot = Join-Path $TestDrive 'snapshot.json'
        $record = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath $snapshot -Path 'src' -RepoRoot $repo *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $record
        $same = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -VerifySnapshotPath $snapshot *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $same
        $same | Should -Match 'SNAPSHOT: UNCHANGED'
        Set-Content -LiteralPath (Join-Path $repo 'src/app.txt') -Value 'two'
        $changed = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -VerifySnapshotPath $snapshot *>&1 | Out-String
        $LASTEXITCODE | Should -Be 5 -Because $changed
        $changed | Should -Match 'src/app.txt'
        $outside = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath (Join-Path $TestDrive 'bad.json') -Path '../escape.txt' -RepoRoot $repo *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1 -Because $outside
    }

    It 'detects a new file in a snapshotted directory and a removed file' {
        $repo = Join-Path $TestDrive 'repo-dir'
        New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'src/a.txt') -Value 'a'
        Set-Content -LiteralPath (Join-Path $repo 'src/b.txt') -Value 'b'
        $snapshot = Join-Path $TestDrive 'snapshot-dir.json'
        & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath $snapshot -Path 'src' -RepoRoot $repo *>&1 | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'src/new.txt') -Value 'new'
        $added = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -VerifySnapshotPath $snapshot *>&1 | Out-String
        $LASTEXITCODE | Should -Be 5 -Because $added
        $added | Should -Match 'src/new.txt is new'
        Remove-Item -LiteralPath (Join-Path $repo 'src/new.txt')
        Remove-Item -LiteralPath (Join-Path $repo 'src/b.txt')
        $removed = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -VerifySnapshotPath $snapshot *>&1 | Out-String
        $LASTEXITCODE | Should -Be 5 -Because $removed
        $removed | Should -Match 'src/b.txt was removed'
    }

    It '-WaitStable returns only after the write set stops changing and records the final state' {
        $repo = Join-Path $TestDrive 'repo-wait'
        New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
        $target = Join-Path $repo 'src/work.txt'
        Set-Content -LiteralPath $target -Value '0'
        $marker = Join-Path $TestDrive 'wait-started'
        $job = Start-Job -ScriptBlock {
            param($file, $flag)
            foreach ($i in 1..6) { Set-Content -LiteralPath $file -Value $i; if ($i -eq 1) { Set-Content -LiteralPath $flag -Value 'go' }; Start-Sleep -Milliseconds 400 }
        } -ArgumentList $target, $marker
        $waited = 0
        while (-not (Test-Path -LiteralPath $marker) -and $waited -lt 100) { Start-Sleep -Milliseconds 100; $waited++ }
        $snapshot = Join-Path $TestDrive 'snapshot-wait.json'
        $started = [DateTime]::UtcNow
        $result = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath $snapshot -Path 'src' -RepoRoot $repo -WaitStable 2 -MaxWaitSeconds 60 *>&1 | Out-String
        $elapsed = ([DateTime]::UtcNow - $started).TotalSeconds
        Wait-Job $job | Out-Null
        Remove-Job $job -Force
        $LASTEXITCODE | Should -Be 0 -Because $result
        (Get-Content -LiteralPath $target -Raw).Trim() | Should -Be '6'
        $elapsed | Should -BeGreaterThan 2
        $verify = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -VerifySnapshotPath $snapshot *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because "the snapshot was taken after the last write: $verify"
    }

    It '-WaitStable exits 6 when the write set never settles within -MaxWaitSeconds' {
        $repo = Join-Path $TestDrive 'repo-nostable'
        New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
        $target = Join-Path $repo 'src/busy.txt'
        Set-Content -LiteralPath $target -Value '0'
        $job = Start-Job -ScriptBlock {
            param($file)
            foreach ($i in 1..40) { Set-Content -LiteralPath $file -Value $i; Start-Sleep -Milliseconds 150 }
        } -ArgumentList $target
        Start-Sleep -Milliseconds 800
        $result = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath (Join-Path $TestDrive 'snapshot-busy.json') -Path 'src' -RepoRoot $repo -WaitStable 3 -MaxWaitSeconds 2 *>&1 | Out-String
        $code = $LASTEXITCODE
        Wait-Job $job | Out-Null
        Remove-Job $job -Force
        $code | Should -Be 6 -Because $result
    }

    It 'splits a comma-joined -Path from a pwsh -File host and detects a change in each listed file' {
        $repo = Join-Path $TestDrive 'repo-comma'
        New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'src/a.txt') -Value 'a'
        Set-Content -LiteralPath (Join-Path $repo 'CHANGES.md') -Value 'c'
        $snapshot = Join-Path $TestDrive 'snapshot-comma.json'
        $record = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath $snapshot -Path 'src/a.txt,CHANGES.md' -RepoRoot $repo *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $record
        $record | Should -Match 'recorded 2 existing file'
        Set-Content -LiteralPath (Join-Path $repo 'src/a.txt') -Value 'edited'
        $changed = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -VerifySnapshotPath $snapshot *>&1 | Out-String
        $LASTEXITCODE | Should -Be 5 -Because $changed
        $changed | Should -Match 'src/a.txt changed'
    }

    It 'exits 1 when any listed -Path does not exist, for the comma form and the in-process array form' {
        $repo = Join-Path $TestDrive 'repo-missing'
        New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'src/a.txt') -Value 'a'
        $snapshot = Join-Path $TestDrive 'snapshot-missing.json'
        $comma = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath $snapshot -Path 'src/a.txt,typo/nope.md' -RepoRoot $repo *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1 -Because $comma
        $comma | Should -Match 'does not exist'
        $typo = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath $snapshot -Path 'typo/nope.md' -RepoRoot $repo -WaitStable 1 *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1 -Because $typo

        $wrapper = Join-Path $TestDrive "snap-wrapper-$([guid]::NewGuid().ToString('N')).ps1"
        $body = "& '$($script:Writer)' -SquadRoot '$($script:SnapRoot)' -SnapshotPath '$snapshot' -Path 'src','CHANGES.md' -RepoRoot '$repo'`nexit `$LASTEXITCODE`n"
        [System.IO.File]::WriteAllText($wrapper, $body, [System.Text.UTF8Encoding]::new($false))
        $inProcess = & pwsh -NoProfile -File $wrapper *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1 -Because $inProcess
        $ok = "& '$($script:Writer)' -SquadRoot '$($script:SnapRoot)' -SnapshotPath '$snapshot' -Path 'src','src/a.txt' -RepoRoot '$repo'`nexit `$LASTEXITCODE`n"
        [System.IO.File]::WriteAllText($wrapper, $ok, [System.Text.UTF8Encoding]::new($false))
        $good = & pwsh -NoProfile -File $wrapper *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $good
    }

    It 'accepts an 8.3 short -RepoRoot and still refuses a path outside it' -Skip:(-not $IsWindows) {
        $repo = Join-Path $TestDrive 'repo-short-name-directory'
        New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'src/a.txt') -Value 'a'
        $short = $null
        try { $short = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($repo).ShortPath } catch { $short = $null }
        if (-not $short -or $short -eq $repo) { Set-ItResult -Skipped -Because 'this volume has no 8.3 short name for the test folder'; return }
        $snapshot = Join-Path $TestDrive 'snapshot-short.json'
        $result = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath $snapshot -Path 'src' -RepoRoot $short *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $result
        $outside = & pwsh -NoProfile -File $script:Writer -SquadRoot $script:SnapRoot -SnapshotPath $snapshot -Path '../escape.txt' -RepoRoot $short *>&1 | Out-String
        $LASTEXITCODE | Should -Be 1 -Because $outside
    }
}

Describe 'Write-SquadHandoff.ps1 refuses what it cannot admit or verify' {
    It 'sends a Cost Preflight ref or slot, or a federation ceiling above a sub-squad root, to the Scribe unchanged' {
        $refRoot = New-Root
        $payload = New-Payload
        $payload.historyRecords[0].costPreflightRef = 'decisions.md#cost-preflight-x'
        $payload.historyRecords[0].costPreflightSlot = 'slot-1'
        $before = Get-TreeHash $refRoot
        (Invoke-Writer -Root $refRoot -Payload $payload).ExitCode | Should -Be 2
        Get-TreeHash $refRoot | Should -Be $before

        $memberRoot = New-Root -Member
        $federationState = Join-Path (Split-Path -Parent (Split-Path -Parent $memberRoot)) 'state.json'
        $ceiling = '{"currentRun":{"costPreflight":{"ceilingUsd":5,"decision":"within-ceiling"}}}'
        [System.IO.File]::WriteAllText($federationState, $ceiling)
        $before = Get-TreeHash $memberRoot
        $blocked = Invoke-Writer -Root $memberRoot -Payload (New-Payload)
        $blocked.ExitCode | Should -Be 2 -Because $blocked.Output
        Get-TreeHash $memberRoot | Should -Be $before
        [System.IO.File]::WriteAllText($federationState, '{"currentRun":{"costPreflight":{"ceilingUsd":null,"decision":"not-requested"}}}')
        $open = Invoke-Writer -Root $memberRoot -Payload (New-Payload)
        $open.ExitCode | Should -Be 0 -Because $open.Output
    }

    It 'sends secret-like text anywhere in the payload to the Scribe, including stateAdvance, unchanged' {
        $values = @(
            'Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345',
            'sent header Bearer abcdefghijklmnopqrstuvwxyz012345',
            'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl',
            'key AKIAIOSFODNN7EXAMPLE leaked',
            'password=hunter2'
        )
        foreach ($value in $values) {
            foreach ($where in @('outcome', 'escalation', 'sessionModel')) {
                $root = New-Root
                $payload = New-Payload
                switch ($where) {
                    'outcome' { $payload.historyRecords[0].outcome = $value }
                    'escalation' { $payload.stateAdvance.openEscalationsRaised = @($value) }
                    'sessionModel' { $payload.stateAdvance.sessionModel = $value }
                }
                $before = Get-TreeHash $root
                $result = Invoke-Writer -Root $root -Payload $payload
                $result.ExitCode | Should -Be 2 -Because "$where / $value : $($result.Output)"
                Get-TreeHash $root | Should -Be $before
            }
        }
    }

    It 'rejects a decision rationale that forges a heading: setext underline, unbalanced fence, or a line starting with #' {
        $fence3 = '`' * 3
        $fence4 = '`' * 4
        $forgeries = @("Forged`n---", "Forged`n===", "Para`nForged H2`n-", "Text`n$($fence3)powershell`nnever closed", "Text`n$($fence4)x`nbody`n$fence3", "Text`n~~~`nbody`n$fence3", "Text`n<!-- hidden", "Text`n<pre>", "Text`n# Injected", "Text`n  ## indented")
        foreach ($rationale in $forgeries) {
            $root = New-Root
            $payload = New-Payload
            $payload.decision.rationale = $rationale
            $before = Get-TreeHash $root
            $result = Invoke-Writer -Root $root -Payload $payload
            $result.ExitCode | Should -Be 1 -Because "$rationale : $($result.Output)"
            Get-TreeHash $root | Should -Be $before
        }
        $root = New-Root
        $payload = New-Payload
        $payload.decision.rationale = "Plain first line`n`n``````text`nbalanced`n``````"
        (Invoke-Writer -Root $root -Payload $payload).ExitCode | Should -Be 0
    }

    It 'rejects a deliverable that is missing, a directory, outside the repository, or older than the previous hand-off' {
        $cases = [ordered]@{
            'missing'   = { param($root, $p) $p.historyRecords[0].deliverable = 'research/nope.md (1 word)' }
            'directory' = { param($root, $p) $p.historyRecords[0].deliverable = 'research (folder)' }
            'outside'   = {
                param($root, $p)
                $repo = Split-Path -Parent (Split-Path -Parent $root)
                Set-Content -LiteralPath (Join-Path (Split-Path -Parent $repo) 'outside.md') -Value 'x'
                $p.historyRecords[0].deliverable = '../outside.md (1 word)'
            }
            'stale'     = { param($root, $p) (Get-Item -LiteralPath (Join-Path $root 'research/2026-09-27-fixture-topic.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-01-01T00:00:00Z').ToUniversalTime() }
        }
        foreach ($name in $cases.Keys) {
            $root = New-Root
            $payload = New-Payload
            & $cases[$name] $root $payload
            $before = Get-TreeHash $root
            $result = Invoke-Writer -Root $root -Payload $payload
            $result.ExitCode | Should -Be 1 -Because "$name : $($result.Output)"
            Get-TreeHash $root | Should -Be $before
        }
    }

    It 'bounds payload.since to this turn: it tightens the freshness floor and can never reopen a stale artifact' {
        $root = New-Root
        (Get-Item -LiteralPath (Join-Path $root 'research/2026-09-27-fixture-topic.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T09:30:00Z').ToUniversalTime()
        $payload = New-Payload
        $payload['since'] = '2026-09-27T09:20:00Z'
        $ok = Invoke-Writer -Root $root -Payload $payload
        $ok.ExitCode | Should -Be 0 -Because $ok.Output

        $tighter = New-Root
        (Get-Item -LiteralPath (Join-Path $tighter 'research/2026-09-27-fixture-topic.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T09:30:00Z').ToUniversalTime()
        $payload = New-Payload
        $payload['since'] = '2026-09-27T09:45:00Z'
        (Invoke-Writer -Root $tighter -Payload $payload).ExitCode | Should -Be 1

        foreach ($since in @('1970-01-01T00:00:00Z', '2026-09-27T10:30:00Z')) {
            $bad = New-Root
            (Get-Item -LiteralPath (Join-Path $bad 'research/2026-09-27-fixture-topic.md')).LastWriteTimeUtc = [DateTime]::Parse('2020-01-01T00:00:00Z').ToUniversalTime()
            $payload = New-Payload
            $payload['since'] = $since
            $before = Get-TreeHash $bad
            $result = Invoke-Writer -Root $bad -Payload $payload
            $result.ExitCode | Should -Be 1 -Because "$since : $($result.Output)"
            $result.Output | Should -Match 'payload.since'
            Get-TreeHash $bad | Should -Be $before
        }
    }

    It 'refuses the same heading at the next turn (the duplicate-heading guard, not only the turn check)' {
        $root = New-Root
        (Invoke-Writer -Root $root -Payload (New-Payload)).ExitCode | Should -Be 0
        $again = New-Payload
        $again.turn = 3
        $again.Remove('decision')
        $again.Remove('route')
        (Get-Item -LiteralPath (Join-Path $root 'research/2026-09-27-fixture-topic.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T10:00:00Z').ToUniversalTime()
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload $again
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'already holds'
        Get-TreeHash $root | Should -Be $before
    }

    It 'refuses a timestamp that precedes the last hand-off' {
        $root = New-Root
        $payload = New-Payload
        $payload.timestamp = '2020-01-01T00:00:00Z'
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'precedes'
        Get-TreeHash $root | Should -Be $before
    }

    It 'ignores a future state.json updated as an ordering floor, warns, and still writes' {
        $root = New-Root
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $future = [DateTime]::UtcNow.AddHours(2).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $state.updated = $future
        Set-Content -LiteralPath $statePath -Value ($state | ConvertTo-Json -Depth 20) -Encoding utf8NoBOM
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match ([regex]::Escape("WARN future timestamp $future in state.json ignored as an ordering floor (likely local time labelled UTC)"))
    }

    It 'refuses a payload timestamp more than 120 s in the future' {
        $root = New-Root
        $payload = New-Payload
        $payload.timestamp = [DateTime]::UtcNow.AddHours(2).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'timestamp is in the future; stamp with the current UTC time'
        Get-TreeHash $root | Should -Be $before
    }

    It 'checks attribution: agent pin, cli passed model, rate row, and Alternate cue; records Member Name' {
        $bad = [ordered]@{
            'agent-pinned mismatch'     = { param($p) $c = $p.historyRecords[0].consumption; $c.model_source = 'agent-pinned'; $c.model = 'Totally Made Up' }
            'cli-pinned mismatch'       = { param($p) $c = $p.historyRecords[0].consumption; $c.model_source = 'cli-pinned'; $p.historyRecords[0].passedModel = 'GPT-5.4' }
            'unknown member'            = { param($p) $p.historyRecords[0].memberName = 'Omega' }
        }
        foreach ($name in $bad.Keys) {
            $root = New-Root
            $payload = New-Payload
            & $bad[$name] $payload
            $before = Get-TreeHash $root
            $result = Invoke-Writer -Root $root -Payload $payload
            $result.ExitCode | Should -Be 1 -Because "$name : $($result.Output)"
            Get-TreeHash $root | Should -Be $before
        }

        $good = New-Root
        $payload = New-Payload
        $payload.historyRecords[0].consumption.model_source = 'agent-pinned'
        $payload.historyRecords[0].memberName = 'Alpha'
        $ok = Invoke-Writer -Root $good -Payload $payload
        $ok.ExitCode | Should -Be 0 -Because $ok.Output
        (Get-Content -LiteralPath (Join-Path $good 'history/Squad Researcher.md') -Raw) | Should -Match '\* Member Name: Alpha'

        $cli = New-Root
        $payload = New-Payload
        $payload.historyRecords[0].consumption.model_source = 'cli-pinned'
        $payload.historyRecords[0].passedModel = 'Claude Sonnet 4.6'
        (Invoke-Writer -Root $cli -Payload $payload).ExitCode | Should -Be 0

        $alternate = New-Root
        Add-Content -LiteralPath (Join-Path $alternate 'team.md') -Value '| planner |  | Squad Lead | Squad Reviewer | when the plan needs review | runSubagent / task | default | plans/ |'
        $payload = New-Payload
        $payload.historyRecords[0].agent = 'Squad Reviewer'
        $before = Get-TreeHash $alternate
        $noCue = Invoke-Writer -Root $alternate -Payload $payload
        $noCue.ExitCode | Should -Be 1 -Because $noCue.Output
        $noCue.Output | Should -Match 'selectionCue'
        Get-TreeHash $alternate | Should -Be $before
        $payload.historyRecords[0].selectionCue = 'the plan needs an independent review'
        $withCue = Invoke-Writer -Root $alternate -Payload $payload
        $withCue.ExitCode | Should -Be 0 -Because $withCue.Output
        (Get-Content -LiteralPath (Join-Path $alternate 'history/Squad Reviewer.md') -Raw) | Should -Match '\* Selection Cue: the plan needs an independent review'
    }

    It 'keeps an existing Cost Comparison consistent: squad figures and saving follow the new total, never going stale' {
        $root = New-Root
        $path = Join-Path $root 'consumption.md'
        $full = 'This run consumed an estimated **$9.99 (~999 AI credits)** across 3 specialized agents. Reproducing it manually with GPT-5.4 across roughly 12 turns is estimated at **$20.00 (~2000 AI credits)**, a saving of about **50%**.'
        $text = [regex]::Replace(((Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"), '(?m)^This run has not yet dispatched[^\n]*', { $full })
        [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $after = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
        $after | Should -Match ([regex]::Escape('This run consumed an estimated **$0.3171 (~31.71 AI credits)** across 3 specialized agents.'))
        $after | Should -Match ([regex]::Escape('estimated at **$20.00 (~2000 AI credits)**, a saving of about **98%**.'))
        $after | Should -Not -Match 'squad figure only'
        $result.Output | Should -Not -Match 'NOTE Cost Comparison'
        (Invoke-LedgerCheck -Root $root -Counts 'Squad Researcher=1;Squad Scribe=1').ExitCode | Should -Be 0
        $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json
        $state.currentRun.estCostUsd | Should -Be 0.3171

        # A second hand-off moves the total again; the comparison follows it instead of going stale.
        $next = New-Payload
        $next.turn = 3
        $next.timestamp = '2026-09-27T11:00:00Z'
        $next.Remove('decision')
        $next.Remove('route')
        $next.historyRecords[0].request = 'Survey a second topic.'
        (Get-Item -LiteralPath (Join-Path $root 'research/2026-09-27-fixture-topic.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T10:30:00Z').ToUniversalTime()
        $second = Invoke-Writer -Root $root -Payload $next
        $second.ExitCode | Should -Be 0 -Because $second.Output
        $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json
        $again = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
        $again | Should -Match ([regex]::Escape([string]::Format([cultureinfo]::InvariantCulture, 'This run consumed an estimated **${0:F4} (~{1:F2} AI credits)**', [double]$state.currentRun.estCostUsd, [double]$state.currentRun.estCreditsTotal)))
        $state.currentRun.estCostUsd | Should -BeGreaterThan 0.3171
        # A baseline below the squad cost cannot yield a saving: the paragraph is marked stale.
        $lowRoot = New-Root
        $low = $full.Replace('$20.00 (~2000 AI credits)', '$0.10 (~10 AI credits)')
        $lowText = [regex]::Replace(((Get-Content -LiteralPath (Join-Path $lowRoot 'consumption.md') -Raw) -replace "`r`n", "`n"), '(?m)^This run has not yet dispatched[^\n]*', { $low })
        [System.IO.File]::WriteAllText((Join-Path $lowRoot 'consumption.md'), $lowText, [System.Text.UTF8Encoding]::new($false))
        (Invoke-Writer -Root $lowRoot -Payload (New-Payload)).ExitCode | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $lowRoot 'consumption.md') -Raw) | Should -Match 'stale — refreshed at run end'

        $seedRoot = New-Root
        (Invoke-Writer -Root $seedRoot -Payload (New-Payload)).ExitCode | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $seedRoot 'consumption.md') -Raw) | Should -Match 'squad figure only'
    }

    It 'prices the orchestration entry at the session model with session-inherited and refuses agent-pinned' {
        $root = New-Root
        $pinned = New-Payload
        $pinned.orchestration.consumption.model_source = 'agent-pinned'
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload $pinned
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'must not be agent-pinned'
        Get-TreeHash $root | Should -Be $before

        $mismatch = New-Payload
        $mismatch.stateAdvance = [ordered]@{ activeRoles = @('Squad Researcher'); sessionModel = 'Claude Sonnet 4.6' }
        $wrong = Invoke-Writer -Root $root -Payload $mismatch
        $wrong.ExitCode | Should -Be 1 -Because $wrong.Output
        $wrong.Output | Should -Match "session model 'Claude Sonnet 4.6'"
        Get-TreeHash $root | Should -Be $before

        $match = New-Payload
        $match.orchestration.consumption.model = 'Claude Sonnet 4.6'
        $match.orchestration.consumption.priced_as = 'Claude Sonnet 4.6'
        $match.orchestration.consumption.model_tier = 'default'
        $match.stateAdvance = [ordered]@{ activeRoles = @('Squad Researcher'); sessionModel = 'Claude Sonnet 4.6' }
        $ok = Invoke-Writer -Root $root -Payload $match
        $ok.ExitCode | Should -Be 0 -Because $ok.Output
    }

    It 'finds an agent pin in an installed plugin agents/ folder when the repository has none' {
        $plugin = Join-Path $TestDrive "plugin-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path (Join-Path $plugin 'skills') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PackageRoot '.agents/skills/squad') -Destination (Join-Path $plugin 'skills/squad') -Recurse
        New-Item -ItemType Directory -Path (Join-Path $plugin 'agents') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $plugin 'agents/squad-researcher.agent.md') -Value "---`nname: Squad Researcher`nmodel: Claude Sonnet 4.6 (copilot)`n---`n# Researcher`n"
        $root = New-Root
        Remove-Item -LiteralPath (Join-Path (Split-Path -Parent (Split-Path -Parent $root)) '.github') -Recurse -Force
        $payload = New-Payload
        $payload.historyRecords[0].consumption.model_source = 'agent-pinned'
        $file = Join-Path $TestDrive "plugin-payload-$([guid]::NewGuid().ToString('N')).json"
        Set-Content -LiteralPath $file -Value ($payload | ConvertTo-Json -Depth 8) -Encoding utf8NoBOM
        $output = & pwsh -NoProfile -File (Join-Path $plugin 'skills/squad/scripts/Write-SquadHandoff.ps1') -SquadRoot $root -PayloadPath $file *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
    }

    It 'appends without rewriting existing bytes: a BOM and CRLF line endings survive' {
        $root = New-Root
        foreach ($name in @('decisions.md')) {
            $path = Join-Path $root $name
            $crlf = ((Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n").Replace("`n", "`r`n")
            [System.IO.File]::WriteAllBytes($path, ([byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.UTF8Encoding]::new($false).GetBytes($crlf))))
        }
        $historyPath = Join-Path $root 'history/Squad Researcher.md'
        New-Item -ItemType Directory -Path (Split-Path -Parent $historyPath) -Force | Out-Null
        $header = "---`r`ndescription: `"Append-only dispatch history for a single squad agent`"`r`n---`r`n`r`n# History: Squad Researcher`r`n`r`nEach entry records a request this agent handled, the findings or outcome it returned, and the turn it was dispatched on. Entries are appended in chronological order and never edited.`r`n`r`n<!-- Append each new dispatch entry at the end of this file, after the last entry. -->`r`n"
        [System.IO.File]::WriteAllBytes($historyPath, ([byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.UTF8Encoding]::new($false).GetBytes($header))))
        $originals = @{}
        foreach ($path in @((Join-Path $root 'decisions.md'), $historyPath)) { $originals[$path] = [System.IO.File]::ReadAllBytes($path) }
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        foreach ($path in $originals.Keys) {
            $now = [System.IO.File]::ReadAllBytes($path)
            $now.Length | Should -BeGreaterThan $originals[$path].Length
            ([System.Linq.Enumerable]::SequenceEqual([byte[]]$now[0..($originals[$path].Length - 1)], [byte[]]$originals[$path])) | Should -BeTrue -Because "$path keeps every original byte"
            @($now[0..2]) | Should -Be @(0xEF, 0xBB, 0xBF)
            $tail = [System.Text.UTF8Encoding]::new($false).GetString($now[$originals[$path].Length..($now.Length - 1)])
            $tail | Should -Not -Match '(?<!\r)\n'
        }
    }

    It 'reports an accurate rollback when a later write fails on a read-only state.json' -Skip:(-not $IsWindows) {
        $root = New-Root
        $statePath = Join-Path $root 'state.json'
        Set-ItemProperty -LiteralPath $statePath -Name IsReadOnly -Value $true
        try {
            $before = Get-TreeHash $root
            $result = Invoke-Writer -Root $root -Payload (New-Payload)
            $result.ExitCode | Should -Be 3 -Because $result.Output
            $result.Output | Should -Match 'restored'
            $result.Output | Should -Not -Match 'RESTORE FAILED'
            Get-TreeHash $root | Should -Be $before
        }
        finally { Set-ItemProperty -LiteralPath $statePath -Name IsReadOnly -Value $false }
    }

    It 'takes the payload as a single-quoted here-string in-process, so $ and backticks survive' {
        $root = New-Root
        $payload = New-Payload
        $payload.historyRecords[0].outcome = 'Kept $x and $(Get-Date) and `code` literal.'
        $json = $payload | ConvertTo-Json -Depth 8
        $wrapper = Join-Path $TestDrive "wrapper-$([guid]::NewGuid().ToString('N')).ps1"
        $text = "`$p = @'`n" + $json + "`n'@`n& '" + $script:Writer + "' -SquadRoot '" + $root + "' -PayloadJson `$p`nexit `$LASTEXITCODE`n"
        [System.IO.File]::WriteAllText($wrapper, $text, [System.Text.UTF8Encoding]::new($false))
        $output = & pwsh -NoProfile -File $wrapper *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        (Get-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Raw) | Should -Match ([regex]::Escape('Kept $x and $(Get-Date) and `code` literal.'))
    }
}

Describe 'Write-SquadHandoff.ps1 appends a missing Cost Comparison (cost fixes)' {
    It 'appends the template section with the squad figure when consumption.md has none, with no Scribe note, and the ledger check and identity guard pass' {
        $root = New-Root
        $path = Join-Path $root 'consumption.md'
        $text = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
        $text = [regex]::Replace($text, '(?s)\n## Cost Comparison \(illustrative\).*$', "`n")
        $text | Should -Not -Match 'Cost Comparison'
        [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Not -Match 'Squad Scribe writes it'
        $result.Output | Should -Match 'APPENDED Cost Comparison'
        $after = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
        ([regex]::Matches($after, '(?m)^## Cost Comparison \(illustrative\)$')).Count | Should -Be 1
        $after | Should -Match ([regex]::Escape('This run consumed an estimated **$0.3171 (~31.71 AI credits)** across 1 specialized agent(s) (squad figure only;'))
        $after | Should -Match '(?m)^> Estimates only\.'
        (Invoke-LedgerCheck -Root $root -Counts 'Squad Researcher=1;Squad Scribe=1').ExitCode | Should -Be 0

        # A later hand-off refreshes the appended line instead of appending a second section.
        $next = New-Payload
        $next.turn = 3
        $next.timestamp = '2026-09-27T10:05:00Z'
        $next.Remove('decision'); $next.Remove('route')
        $next.since = '2026-09-27T10:00:00Z'
        (Get-Item -LiteralPath (Join-Path $root 'research/2026-09-27-fixture-topic.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T10:03:00Z').ToUniversalTime()
        $second = Invoke-Writer -Root $root -Payload $next
        $second.ExitCode | Should -Be 0 -Because $second.Output
        $final = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
        ([regex]::Matches($final, '(?m)^## Cost Comparison \(illustrative\)$')).Count | Should -Be 1
        (Invoke-LedgerCheck -Root $root -Counts 'Squad Researcher=2;Squad Scribe=2').ExitCode | Should -Be 0
    }
}

Describe 'Write-SquadHandoff.ps1 derives omitted payload fields' {
    BeforeAll {
        function New-MinimalPayload {
            # Only what the dispatch result carries: no turn, mode, timestamp, consumption, or orchestration.
            [ordered]@{
                runId          = 'rp-derive-01'
                historyRecords = @([ordered]@{ agent = 'Squad Researcher'; request = 'Survey the fixture-topic conventions.'; deliverable = 'research/2026-09-27-fixture-topic.md (~1,800 words)'; outcome = 'Surveyed three fixtures.' })
                stateAdvance   = [ordered]@{ activeRoles = @('Squad Researcher') }
            }
        }

        function Get-Block {
            # The first consumption JSON block of a history file, as a hashtable.
            param([string]$Root, [string]$Agent)
            $text = (Get-Content -LiteralPath (Join-Path $Root "history/$Agent.md") -Raw) -replace "`r`n", "`n"
            $json = [regex]::Match($text, '(?s)#### Consumption[^\n]*\n\n```json\n(.*?)\n```').Groups[1].Value
            $json | ConvertFrom-Json -AsHashtable
        }
    }

    It 'derives turn, timestamp, mode and both consumption blocks from a minimal payload, and the ledger check passes' {
        $root = New-Root
        $result = Invoke-Writer -Root $root -Payload (New-MinimalPayload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Measure-SquadLedger -Check: PASS'

        $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json
        $state.turn | Should -Be 2
        $state.mode | Should -Be 'interactive'
        # ConvertFrom-Json turns the ISO string into a local DateTime, so read the written text.
        $updated = [regex]::Match((Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw), '"updated":\s*"([^"]+)"').Groups[1].Value
        $updated | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
        ([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse($updated, [System.Globalization.CultureInfo]::InvariantCulture)).TotalSeconds | Should -BeLessThan 120
        (Get-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Raw) | Should -Match '(?m)^\* Turn: 2$'

        # Research class floors (12 / 40,000 / 4,000 / 1,250) on the agent's own pin (Claude Sonnet 4.6).
        $block = Get-Block -Root $root -Agent 'Squad Researcher'
        $block.model | Should -Be 'claude-sonnet-4.6'
        $block.model_source | Should -Be 'agent-pinned'
        $block.priced_as | Should -Be 'Claude Sonnet 4.6'
        $block.model_tier | Should -Be 'default'
        $block.internal_turns | Should -Be 12
        $block.input_tokens | Should -Be 148800
        $block.cached_tokens | Should -Be 595200
        $block.cache_write_tokens | Should -Be 84000
        $block.output_tokens | Should -Be 15000
        $block.basis | Should -Be 'estimated'

        # Orchestration share: bookkeeping floors (4 / 15,000 / 3,000 / 800); the fixture records no session model.
        $orch = Get-Block -Root $root -Agent 'Squad Scribe'
        $orch.model | Should -Be 'unknown'
        $orch.model_source | Should -Be 'unresolved'
        $orch.model_tier | Should -Be 'default'
        $orch.priced_as | Should -Be 'Claude Sonnet 4.6'
        $orch.internal_turns | Should -Be 4
        $orch.input_tokens | Should -Be 15600
        $orch.cached_tokens | Should -Be 62400
        $orch.cache_write_tokens | Should -Be 24000
        $orch.output_tokens | Should -Be 3200

        (Invoke-LedgerCheck -Root $root -Counts 'Squad Researcher=1;Squad Scribe=1').ExitCode | Should -Be 0
    }

    It 'keeps the state mode, prices the orchestration at the session model, and derives a passedModel as cli-pinned' {
        $root = New-Root
        $statePath = Join-Path $root 'state.json'
        ((Get-Content -LiteralPath $statePath -Raw) -replace '"mode": "interactive"', '"mode": "autopilot"') | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM -NoNewline
        $payload = New-MinimalPayload
        $payload.historyRecords[0].passedModel = 'gpt-5.4-mini'
        $payload.stateAdvance.sessionModel = 'Claude Haiku 4.5'
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).mode | Should -Be 'autopilot'

        $block = Get-Block -Root $root -Agent 'Squad Researcher'
        $block.model | Should -Be 'gpt-5.4-mini'
        $block.model_source | Should -Be 'cli-pinned'
        $block.priced_as | Should -Be 'GPT-5.4 mini'
        $block.model_tier | Should -Be 'fast'
        $block.cache_write_tokens | Should -Be 0

        $orch = Get-Block -Root $root -Agent 'Squad Scribe'
        $orch.model | Should -Be 'Claude Haiku 4.5'
        $orch.model_source | Should -Be 'session-inherited'
        $orch.model_tier | Should -Be 'fast'
        $orch.priced_as | Should -Be 'Claude Haiku 4.5'
    }

    It 'derives from the record role class: a closing review uses the review floors' {
        $root = New-Root
        $repo = (Resolve-Path (Join-Path $root '../..')).Path
        $team = Join-Path $root 'team.md'
        $text = (Get-Content -LiteralPath $team -Raw) -replace "`r`n", "`n"
        $text = $text -replace '(?m)^(\| scribe .*)$', "`$1`n| tester     | Beta        | Squad Reviewer        | —                  | —              | runSubagent / task | fast       | reviews/           |"
        [System.IO.File]::WriteAllText($team, $text, [System.Text.UTF8Encoding]::new($false))
        Set-Content -LiteralPath (Join-Path $repo '.github/agents/squad/squad-reviewer.agent.md') -Value "---`nname: Squad Reviewer`nmodel: Claude Haiku 4.5 (copilot)`n---`n# Reviewer`n"
        New-Item -ItemType Directory -Path (Join-Path $root 'reviews') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'reviews/review.md') -Value 'review'
        (Get-Item -LiteralPath (Join-Path $root 'reviews/review.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T09:40:00Z').ToUniversalTime()
        $payload = New-MinimalPayload
        $payload.historyRecords += [ordered]@{ agent = 'Squad Reviewer'; request = 'Review the final files.'; deliverable = 'reviews/review.md'; outcome = 'Approved.' }
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $block = Get-Block -Root $root -Agent 'Squad Reviewer'
        $block.model | Should -Be 'claude-haiku-4.5'
        $block.model_tier | Should -Be 'fast'
        $block.internal_turns | Should -Be 18
        $block.input_tokens | Should -Be 302400
        $block.cached_tokens | Should -Be 1209600
        $block.cache_write_tokens | Should -Be 118000
        $block.output_tokens | Should -Be 27000
    }

    It 'reads the floors from the squad rate file rather than from fixed numbers' {
        $root = New-Root
        $rates = Join-Path $root 'consumption-rates.md'
        $raw = (Get-Content -LiteralPath $rates -Raw) -replace "`r`n", "`n"
        $edited = $raw -replace '(?m)^\| Research / file survey\s*\|[^\n]*$', '| Research / file survey    | 6              | 10,000       | 1,000       | 500         |'
        $edited | Should -Not -Be $raw
        [System.IO.File]::WriteAllText($rates, $edited, [System.Text.UTF8Encoding]::new($false))
        $result = Invoke-Writer -Root $root -Payload (New-MinimalPayload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $block = Get-Block -Root $root -Agent 'Squad Researcher'
        $block.internal_turns | Should -Be 6
        $block.input_tokens | Should -Be 15000
        $block.cached_tokens | Should -Be 60000
        $block.cache_write_tokens | Should -Be 15000
        $block.output_tokens | Should -Be 3000
    }

    It 'never alters a supplied block and still refuses what is supplied wrongly' {
        $root = New-Root
        $payload = New-Payload
        $payload.Remove('turn'); $payload.Remove('mode'); $payload.Remove('timestamp')
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Get-Block -Root $root -Agent 'Squad Researcher').input_tokens | Should -Be 9600

        $bad = @{
            'wrong turn'      = { param($p) $p.turn = 7 }
            'illegal mode'    = { param($p) $p.mode = 'turbo' }
            'bad timestamp'   = { param($p) $p.timestamp = 'yesterday' }
            'future timestamp' = { param($p) $p.timestamp = [DateTime]::UtcNow.AddHours(2).ToString('yyyy-MM-ddTHH:mm:ssZ') }
        }
        foreach ($name in $bad.Keys) {
            $fresh = New-Root
            $p = New-Payload
            & $bad[$name] $p
            $before = Get-TreeHash $fresh
            $r = Invoke-Writer -Root $fresh -Payload $p
            $r.ExitCode | Should -Be 1 -Because "$name : $($r.Output)"
            Get-TreeHash $fresh | Should -Be $before -Because "$name must write nothing"
        }
    }

    It 'sends an omitted block it cannot derive to the Scribe with nothing written' {
        $root = New-Root
        $team = Join-Path $root 'team.md'
        $text = (Get-Content -LiteralPath $team -Raw) -replace "`r`n", "`n"
        $text = $text -replace '(?m)^(\| scribe .*)$', "`$1`n| developer  | Gamma       | Squad Implementor     | —                  | —              | runSubagent / task | default    | changes/           |"
        [System.IO.File]::WriteAllText($team, $text, [System.Text.UTF8Encoding]::new($false))
        New-Item -ItemType Directory -Path (Join-Path $root 'changes') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'changes/edit.md') -Value 'change'
        (Get-Item -LiteralPath (Join-Path $root 'changes/edit.md')).LastWriteTimeUtc = [DateTime]::Parse('2026-09-27T09:30:00Z').ToUniversalTime()
        $payload = New-MinimalPayload
        $payload.historyRecords += [ordered]@{ agent = 'Squad Implementor'; request = 'Apply the named edit.'; deliverable = 'changes/edit.md'; outcome = 'Edited.' }
        $before = Get-TreeHash $root
        $result = Invoke-Writer -Root $root -Payload $payload
        $result.ExitCode | Should -Be 2 -Because $result.Output
        $result.Output | Should -Match "no agent file named 'Squad Implementor'"
        Get-TreeHash $root | Should -Be $before
    }
}

Describe 'Write-SquadHandoff.ps1 economy Scribe read set (H1)' {
    BeforeAll {
        $script:EconomyScribePath = Join-Path $PackageRoot '.agents/skills/squad/references/economy-scribe.md'
        Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
        $script:HandoffModel = Get-SquadPackageModel -PackageRoot $PackageRoot
    }

    It 'ships economy-scribe.md within 3,072 LF bytes with the command, every exit code, and the fallback' {
        Test-Path -LiteralPath $script:EconomyScribePath -PathType Leaf | Should -BeTrue
        $text = (Get-Content -LiteralPath $script:EconomyScribePath -Raw) -replace "`r`n", "`n"
        [System.Text.Encoding]::UTF8.GetByteCount($text) | Should -BeLessOrEqual 3072
        $text | Should -Match ([regex]::Escape('pwsh -NoProfile -File <skill>/scripts/Write-SquadHandoff.ps1 -SquadRoot <squadRoot> -PayloadPath <payload.json>'))
        foreach ($code in 0, 1, 2, 3, 4, 7, 8) { $text | Should -Match "(?m)^\| $code \|" -Because "exit $code needs a row" }
        $text | Should -Match 'RESTORE FAILED'
        $text | Should -Match 'WARN ledger-only:'
        $text | Should -Match ([regex]::Escape('read the normal hot core'))
    }

    It 'the Scribe agent reads only economy-scribe.md first for a handoff: script payload' {
        $scribe = @($script:HandoffModel.SquadAgents | Where-Object Name -eq 'squad-scribe.agent.md')[0].Body
        $scribe | Should -Match ([regex]::Escape('Exception: a payload carrying `"handoff": "script"` (economy only) reads only `references/economy-scribe.md` first; read the hot core above only on its fallback.'))
    }

    It 'the Cold-File Dispatch Table and economy-mode.md point the Scribe at economy-scribe.md' {
        $procedure = (Get-Content -LiteralPath (Join-Path $PackageRoot '.agents/skills/squad/references/scribe-procedure.md') -Raw) -replace "`r`n", "`n"
        $procedure | Should -Match ([regex]::Escape('| ordinary payload carrying `handoff: script` (economy only) | [economy-scribe.md](economy-scribe.md), read first instead of this hot core |'))
        $procedure | Should -Not -Match 'economy-mode\.md'
        $economy = (Get-Content -LiteralPath (Join-Path $PackageRoot '.agents/skills/squad/references/economy-mode.md') -Raw) -replace "`r`n", "`n"
        $economy | Should -Match ([regex]::Escape('lives in [economy-scribe.md](economy-scribe.md)'))
        $economy | Should -Not -Match 'v0\.18\.0'
    }
}

Describe 'Write-SquadHandoff.ps1 keeps v0.18.1 ledger-only semantics (H2)' {
    BeforeAll {
        function New-StubSkill {
            # A copy of the installed squad skill whose Measure-SquadLedger.ps1 forwards -Write to the real script and answers -Check
            # with the failure class in $env:HANDOFF_STUB_CLASS (ledger-only, history-integrity, none, or crash).
            $skill = Join-Path $TestDrive "stub-$([guid]::NewGuid().ToString('N').Substring(0, 8))/squad"
            New-Item -ItemType Directory -Path (Split-Path -Parent $skill) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $PackageRoot '.agents/skills/squad') -Destination $skill -Recurse
            $real = Join-Path $skill 'scripts/Measure-SquadLedger.real.ps1'
            Move-Item -LiteralPath (Join-Path $skill 'scripts/Measure-SquadLedger.ps1') -Destination $real
            $stub = @'
[CmdletBinding()]
param([string]$SquadRoot, [switch]$Write, [switch]$Check, [string]$SessionLog, [string]$ExpectedHistoryCounts)
if ($Check) {
    switch ($env:HANDOFF_STUB_CLASS) {
        'crash' { throw 'stub crash' }
        'none' { Write-Host 'Measure-SquadLedger -Check: FAIL (1 mismatch(es))'; Write-Host '  - stub mismatch.'; exit 1 }
        default {
            Write-Host 'Measure-SquadLedger -Check: FAIL (2 mismatch(es))'
            Write-Host '  - Usage & Cost run-total row: expected 0.3171, found 0.4171.'
            Write-Host '  - state.json estCostUsd: expected 0.3171, found 0.4171.'
            Write-Host "Measure-SquadLedger -Check: failure class: $env:HANDOFF_STUB_CLASS"
            exit 1
        }
    }
}
$forward = @{ SquadRoot = $SquadRoot }
if ($Write) { $forward.Write = $true }
if ($SessionLog) { $forward.SessionLog = $SessionLog }
& (Join-Path $PSScriptRoot 'Measure-SquadLedger.real.ps1') @forward
exit $LASTEXITCODE
'@
            Set-Content -LiteralPath (Join-Path $skill 'scripts/Measure-SquadLedger.ps1') -Value $stub -Encoding utf8NoBOM
            Join-Path $skill 'scripts/Write-SquadHandoff.ps1'
        }

        function Invoke-StubWriter {
            param([string]$Root, [string]$Writer, [string]$Class)
            $file = Join-Path $TestDrive "payload-$([guid]::NewGuid().ToString('N')).json"
            Set-Content -LiteralPath $file -Value ((New-Payload) | ConvertTo-Json -Depth 8) -Encoding utf8NoBOM
            $env:HANDOFF_STUB_CLASS = $Class
            try { $output = & pwsh -NoProfile -File $Writer -SquadRoot $Root -PayloadPath $file *>&1 | Out-String }
            finally { Remove-Item Env:HANDOFF_STUB_CLASS -ErrorAction SilentlyContinue }
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }
        $script:StubWriter = New-StubSkill
    }

    It 'keeps the writes and exits 0 with WARN ledger-only on a ledger-only -Check failure' {
        $root = New-Root
        $result = Invoke-StubWriter -Root $root -Writer $script:StubWriter -Class 'ledger-only'
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'WARN ledger-only: Usage & Cost run-total row: expected 0\.3171, found 0\.4171\. \| state\.json estCostUsd'
        $result.Output | Should -Not -Match 'Measure-SquadLedger -Check: PASS'
        Test-Path -LiteralPath (Join-Path $root 'history/Squad Researcher.md') | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json).turn | Should -Be 2
    }

    It 'rolls back and exits 3 on <Class>' -ForEach @(
        @{ Class = 'history-integrity' }
        @{ Class = 'none' }
        @{ Class = 'crash' }
    ) {
        $root = New-Root
        $before = Get-TreeHash $root
        $result = Invoke-StubWriter -Root $root -Writer $script:StubWriter -Class $Class
        $result.ExitCode | Should -Be 3 -Because $result.Output
        $result.Output | Should -Match 'Measure-SquadLedger -Check failed'
        Get-TreeHash $root | Should -Be $before
    }
}

Describe 'Write-SquadHandoff.ps1 lands concurrent ordinary hand-offs (H3) and keys its lock by the canonical root (H4)' {
    BeforeAll {
        function New-TwoAgentRoot {
            $root = New-Root
            $repo = Split-Path -Parent (Split-Path -Parent $root)
            Set-Content -LiteralPath (Join-Path $repo '.github/agents/squad/squad-developer.agent.md') -Value "---`nname: Squad Developer`nmodel: Claude Sonnet 4.6 (copilot)`n---`n# Developer`n"
            $team = Join-Path $root 'team.md'
            $text = (Get-Content -LiteralPath $team -Raw) -replace "`r`n", "`n"
            $text = $text -replace '(?m)^(\| scribe .*)$', "| developer  | Beta        | Squad Developer       | —                  | —              | runSubagent / task | default    | src/               |`n`$1"
            [System.IO.File]::WriteAllText($team, $text, [System.Text.UTF8Encoding]::new($false))
            $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json
            $state.updated = [DateTime]::UtcNow.AddSeconds(-60).ToString('yyyy-MM-ddTHH:mm:ssZ')
            [System.IO.File]::WriteAllText((Join-Path $root 'state.json'), ($state | ConvertTo-Json -Depth 8))
            New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'research/parallel-research.md') -Value "# Research`n"
            Set-Content -LiteralPath (Join-Path $repo 'src/parallel-change.md') -Value "# Change`n"
            $root
        }

        function Get-HandoffLockPath {
            # Mirrors Write-SquadHandoff.ps1: SHA-256 of the canonical, lower-cased root; first 16 hex digits.
            param([string]$CanonicalRoot)
            $key = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($CanonicalRoot.TrimEnd('\', '/').ToLowerInvariant()))).Substring(0, 16)
            Join-Path ([System.IO.Path]::GetTempPath()) "hve-squad-handoff-$key.lock"
        }

        function Start-Writer {
            param([string]$Root, [hashtable]$Payload, [int]$LockTimeoutSeconds = 120)
            $file = Join-Path $TestDrive "payload-$([guid]::NewGuid().ToString('N')).json"
            Set-Content -LiteralPath $file -Value ($Payload | ConvertTo-Json -Depth 8) -Encoding utf8NoBOM
            $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
            foreach ($a in @('-NoProfile', '-File', $script:Writer, '-SquadRoot', $Root, '-PayloadPath', $file, '-LockTimeoutSeconds', "$LockTimeoutSeconds")) { $psi.ArgumentList.Add($a) }
            $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
            $process = [System.Diagnostics.Process]::Start($psi)
            [pscustomobject]@{ Process = $process; Stdout = $process.StandardOutput.ReadToEndAsync(); Stderr = $process.StandardError.ReadToEndAsync() }
        }

        function Wait-Writer {
            param($Started)
            $Started.Process.WaitForExit()
            [pscustomobject]@{ ExitCode = $Started.Process.ExitCode; Output = ($Started.Stdout.Result + $Started.Stderr.Result) }
        }

        function Lock-Root {
            param([string]$Root)
            [System.IO.FileStream]::new((Get-HandoffLockPath -CanonicalRoot (Get-Item -LiteralPath $Root).FullName), [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        }

        $script:ResearchPayload = @{ runId = 'parallel'; historyRecords = @(@{ agent = 'Squad Researcher'; request = 'Research.'; deliverable = 'research/parallel-research.md'; outcome = 'Done.' }); stateAdvance = @{ activeRoles = @('Squad Researcher') } }
        $script:DeveloperPayload = @{ runId = 'parallel'; historyRecords = @(@{ agent = 'Squad Developer'; request = 'Change.'; deliverable = 'src/parallel-change.md'; outcome = 'Done.' }); stateAdvance = @{ activeRoles = @('Squad Developer') } }
    }

    It 'lands both of two ordinary hand-offs that wait on the lock together: turn +2 and -Check passes' {
        $root = New-TwoAgentRoot
        $lock = Lock-Root -Root $root
        try {
            $a = Start-Writer -Root $root -Payload $script:ResearchPayload
            $b = Start-Writer -Root $root -Payload $script:DeveloperPayload
            Start-Sleep -Seconds 4
        }
        finally { $lock.Dispose() }
        $results = @((Wait-Writer $a), (Wait-Writer $b))
        foreach ($result in $results) { $result.ExitCode | Should -Be 0 -Because $result.Output }
        (Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json).turn | Should -Be 3
        $check = Invoke-LedgerCheck -Root $root -Counts 'Squad Researcher=1;Squad Developer=1;Squad Scribe=2'
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'lands both when started at the same moment without a held lock' {
        $root = New-TwoAgentRoot
        $a = Start-Writer -Root $root -Payload $script:ResearchPayload
        $b = Start-Writer -Root $root -Payload $script:DeveloperPayload
        $results = @((Wait-Writer $a), (Wait-Writer $b))
        foreach ($result in $results) { $result.ExitCode | Should -Be 0 -Because $result.Output }
        (Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json).turn | Should -Be 3
        (Invoke-LedgerCheck -Root $root -Counts 'Squad Researcher=1;Squad Developer=1;Squad Scribe=2').ExitCode | Should -Be 0
    }

    It 'refuses, with exit 1, a deliverable the hand-off that landed during the wait already credited' {
        $root = New-TwoAgentRoot
        $same = @{ runId = 'parallel'; historyRecords = @(@{ agent = 'Squad Developer'; request = 'Change again.'; deliverable = 'research/parallel-research.md'; outcome = 'Done.' }); stateAdvance = @{ activeRoles = @('Squad Developer') } }
        $lock = Lock-Root -Root $root
        try {
            $a = Start-Writer -Root $root -Payload $script:ResearchPayload
            Start-Sleep -Milliseconds 1500
            $b = Start-Writer -Root $root -Payload $same
            Start-Sleep -Seconds 3
        }
        finally { $lock.Dispose() }
        $first = Wait-Writer $a
        $second = Wait-Writer $b
        @($first.ExitCode, $second.ExitCode) | Sort-Object | Should -Be @(0, 1) -Because "$($first.Output) / $($second.Output)"
        (@($first, $second) | Where-Object ExitCode -eq 1).Output | Should -Match 'already credited in history/Squad (Researcher|Developer)\.md .* by the hand-off that landed while this one waited for the lock, and has not changed since; a deliverable is credited once'
        (Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json).turn | Should -Be 2
    }

    It 'waits on the same lock when the root is reached by its 8.3 short path' -Skip:(-not $IsWindows) {
        $root = New-TwoAgentRoot
        $long = (Get-Item -LiteralPath $root).FullName
        $short = (& cmd /c "for %I in (`"$long`") do @echo %~sI" | Select-Object -Last 1).Trim()
        if (-not $short -or $short -eq $long) { Set-ItResult -Skipped -Because '8.3 short names are not available on this volume'; return }
        $lock = Lock-Root -Root $long
        try { $held = Wait-Writer (Start-Writer -Root $short -Payload $script:ResearchPayload -LockTimeoutSeconds 2) }
        finally { $lock.Dispose() }
        $held.ExitCode | Should -Be 8 -Because "the short path $short must share the lock of $long. $($held.Output)"
        (Wait-Writer (Start-Writer -Root $short -Payload $script:ResearchPayload)).ExitCode | Should -Be 0
    }

    It 'waits on the same lock when the root is reached through a directory junction' -Skip:(-not $IsWindows) {
        $root = New-TwoAgentRoot
        $repo = (Get-Item -LiteralPath (Split-Path -Parent (Split-Path -Parent $root))).FullName
        $junction = Join-Path $TestDrive "junction-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Junction -Path $junction -Target $repo | Out-Null
        $viaJunction = Join-Path $junction '.copilot-tracking/squad'
        $lock = Lock-Root -Root $root
        try { $held = Wait-Writer (Start-Writer -Root $viaJunction -Payload $script:ResearchPayload -LockTimeoutSeconds 2) }
        finally { $lock.Dispose() }
        $held.ExitCode | Should -Be 8 -Because "the junction path must share the lock of the real root. $($held.Output)"
    }
}

Describe 'Measure-SquadLedger.ps1 -Write never leaves one file updated alone (H5)' {
    # A read-only target makes the replace fail only on Windows; Linux and macOS replace it through the directory entry.
    It 'restores consumption.md when the state.json write fails, and leaves no temp file' -Skip:(-not $IsWindows) {
        $root = New-Root
        (Invoke-Writer -Root $root -Payload (New-Payload)).ExitCode | Should -Be 0
        $consumption = Join-Path $root 'consumption.md'
        $stale = ((Get-Content -LiteralPath $consumption -Raw) -replace '\*\*Total\*\* \| \*\*\d', '**Total** | **9')
        [System.IO.File]::WriteAllText($consumption, $stale)
        $before = (Get-FileHash -LiteralPath $consumption).Hash
        $statePath = Join-Path $root 'state.json'
        (Get-Item -LiteralPath $statePath).IsReadOnly = $true
        try { $output = & pwsh -NoProfile -File $script:Ledger -SquadRoot $root -Write *>&1 | Out-String; $exit = $LASTEXITCODE }
        finally { (Get-Item -LiteralPath $statePath).IsReadOnly = $false }
        $exit | Should -Not -Be 0 -Because $output
        $output | Should -Match 'could not write state\.json'
        $output | Should -Match 'consumption\.md restored to its original bytes'
        (Get-FileHash -LiteralPath $consumption).Hash | Should -Be $before
        @(Get-ChildItem -LiteralPath $root -Force -Filter '*.tmp').Count | Should -Be 0
    }
}

Describe 'Write-SquadHandoff.ps1 Route markers (H6) and consent warning (H7)' {
    BeforeAll {
        function New-RoutedPayload {
            param([string]$Rationale, [string]$Route = 'standard')
            $payload = New-Payload
            $payload.route = $Route
            $payload.historyRecords[0].routingIdentity = [ordered]@{ requestedModel = 'claude-sonnet-4.6'; effectiveModel = 'Claude Sonnet 4.6'; observedModel = 'unreported'; routeRationale = $Rationale }
            $payload
        }
    }

    It 'prefixes Route: economy to a routeRationale without a marker, with a WARN' {
        $root = New-Root
        $result = Invoke-Writer -Root $root -Payload (New-RoutedPayload -Rationale 'economy pick: rank 1 of 3')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match "WARN Squad Researcher: routeRationale did not start with a Route marker; recorded as 'Route: economy; \.\.\.'"
        (Get-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Raw) | Should -Match ([regex]::Escape('* **Route rationale** — Route: economy; economy pick: rank 1 of 3'))
    }

    It 'prefixes Route: bounded when the payload route is bounded' {
        $root = New-Root
        $result = Invoke-Writer -Root $root -Payload (New-RoutedPayload -Rationale 'rank 1 of 3' -Route 'bounded')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Get-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Raw) | Should -Match ([regex]::Escape('* **Route rationale** — Route: bounded; rank 1 of 3'))
    }

    It 'keeps a rationale that already starts with its marker, without a marker WARN' {
        $root = New-Root
        $result = Invoke-Writer -Root $root -Payload (New-RoutedPayload -Rationale 'Route: economy; economy pick')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Not -Match 'routeRationale did not start'
        (Get-Content -LiteralPath (Join-Path $root 'history/Squad Researcher.md') -Raw) | Should -Match ([regex]::Escape('* **Route rationale** — Route: economy; economy pick'))
    }

    It 'warns, and still writes, when a record has no routingIdentity' {
        $root = New-Root
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'WARN Squad Researcher: no routingIdentity; under economy every history entry carries Route: economy'
    }

    It 'warns economy consent not recorded and continues when decisions.md has no Economy Mode Accepted entry' {
        $root = New-Root
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'WARN economy consent not recorded'
    }

    It 'does not warn about consent once the entry is recorded' {
        $root = New-Root
        Add-Content -LiteralPath (Join-Path $root 'decisions.md') -Value "`n## Economy Mode Accepted 2026-09-27T08:00:00Z`n`n* User: Fixture User`n* Previous mode: ranked`n* Trade accepted: cheaper allowlisted picks`n* Never weakened: every gate`n"
        $result = Invoke-Writer -Root $root -Payload (New-Payload)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Not -Match 'economy consent not recorded'
    }
}

Describe 'Default role charters carry no economy text (H8)' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
        $script:CharterModel = Get-SquadPackageModel -PackageRoot $PackageRoot
    }

    It '<Name> has no Status: complete line and no economy procedure' -ForEach @(
        @{ Name = 'squad-implementor.agent.md' }
        @{ Name = 'squad-lead.agent.md' }
        @{ Name = 'squad-reviewer.agent.md' }
        @{ Name = 'squad-technical-writer.agent.md' }
    ) {
        $agent = @($script:CharterModel.SquadAgents | Where-Object Name -eq $Name)[0]
        $agent | Should -Not -BeNullOrEmpty
        $agent.Body | Should -Not -Match 'Status: complete'
        $agent.Body | Should -Not -Match '(?i)economy|handoff: script|Write-SquadHandoff'
    }
}
