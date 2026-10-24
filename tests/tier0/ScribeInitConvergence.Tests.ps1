#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# AI cost: none; inspects init/repair contracts without launching the Scribe.

# 0.18.1 hotfix: pins the Init and ledger-repair contract that stops the Scribe
# looping on a fresh squad. GATE-38..GATE-41 in tests/squad-behavior-contract.md are
# this file's contract IDs.
#
# Observed on 0.18.0: the Init Scribe composed generic agent names (the cast catalog
# left the auto-applied roster instructions in 0.18.0 and the Init payload carried
# role ids only), and the Init contract told the Scribe both to leave history/ empty
# and, through the floor, to record its own orchestration block there, with no
# ledgerCommand on the Init payload. The coordinator's next -Check then failed, and
# every corrective Scribe pass appended another block the hand-written ledger missed.
#
# GATE-38..40 are static text pins; GATE-41 runs the shipped Measure-SquadLedger.ps1
# against a seeded fixture to prove the scripted path converges in one pass.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot

    function Get-SquadReferenceBody {
        param([Parameter(Mandatory)][string]$Name)
        Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot "references/$Name") -Raw
    }

    $script:Coordinator = Get-SquadReferenceBody -Name 'coordinator-legacy.md'
    $script:ScribeHot = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-scribe.agent.md')[0].Body
    $script:Scribe = Get-SquadReferenceBody -Name 'scribe-cold-charter.md'
    $script:InitCold = Get-SquadReferenceBody -Name 'scribe-cold-init-and-seeding.md'
    $script:PayloadTemplate = Get-SquadReferenceBody -Name 'scribe-payload-template.md'
    $script:ScribeProcedure = Get-SquadReferenceBody -Name 'scribe-procedure.md'
    $script:OperatingProcedure = Get-SquadReferenceBody -Name 'operating-procedure.md'
    $script:GatesAndModes = Get-SquadReferenceBody -Name 'gates-and-modes.md'
    $script:LedgerScript = Join-Path $script:Model.SquadSkillRoot 'scripts/Measure-SquadLedger.ps1'

    function Invoke-Ledger {
        param(
            [Parameter(Mandatory)][ValidateSet('Write', 'Check')][string]$Mode,
            [string]$ExpectedScribeEntries
        )
        $arguments = @('-NoProfile', '-File', $script:LedgerScript, '-SquadRoot', $script:Root, "-$Mode")
        if ($ExpectedScribeEntries) {
            $arguments = @('-NoProfile', '-Command', "& '$($script:LedgerScript)' -SquadRoot '$($script:Root)' -Check -ExpectedHistoryCounts @{ 'Squad Scribe' = $ExpectedScribeEntries }")
        }
        $output = & pwsh @arguments 2>&1
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
    }

    function Format-OrchestrationEntry {
        param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][int]$Turn)
        $fence = '```'
        @(
            ''
            "### 2026-10-07T09:0${Turn}:00Z $Title"
            ''
            "* Turn: $Turn"
            "* Request: $Title."
            '* Deliverable: `state.json`'
            "* Outcome: $Title recorded."
            ''
            '#### Consumption — Orchestration'
            ''
            "${fence}json"
            '{'
            '  "model": "Claude Haiku 4.5",'
            '  "model_source": "agent-pinned",'
            '  "priced_as": "Claude Haiku 4.5",'
            '  "model_tier": "fast",'
            '  "internal_turns": 4,'
            '  "input_tokens": 3000,'
            '  "cached_tokens": 12000,'
            '  "cache_write_tokens": 1250,'
            '  "output_tokens": 3200,'
            '  "basis": "estimated"'
            '}'
            $fence
            ''
        ) -join "`n"
    }

    function Get-MarkdownHeadersLocal {
        param([Parameter(Mandatory)][string]$Content)
        $headers = [System.Collections.Generic.List[object]]::new()
        $lines = $Content -split '\r?\n'
        for ($i = 0; $i -lt ($lines.Count - 1); $i++) {
            if ($lines[$i].TrimStart().StartsWith('|') -and $lines[$i + 1] -match '^\s*\|[\s:|-]+\|\s*$') {
                $header = $lines[$i].Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() }
                $headers.Add($header)
            }
        }
        $headers.ToArray()
    }
}

Describe 'GATE-38 Init copies roster rows from the payload and never derives an agent name' {
    It 'routes fresh Init to one brief before the full cold branch' {
        $script:ScribeHot | Should -Match 'references/scribe-init\.md'
        $script:ScribeHot.IndexOf('references/scribe-init.md') | Should -BeLessThan $script:ScribeHot.IndexOf('references/scribe-cold-charter.md')
        $script:ScribeHot | Should -Match 'read `references/scribe-cold-charter\.md` in full'
        foreach ($reference in @('00-index.md', 'scribe-procedure.md', 'entry-schemas.md', 'scribe-payload-template.md')) {
            $script:Scribe | Should -Match ([regex]::Escape("references/$reference"))
        }
        $script:ScribeHot | Should -Match 'Cold loading is not a validation bypass'
        $script:Coordinator | Should -Match 'never for fresh Init or `Initialize-Squad`'
        $script:Coordinator | Should -Match 'dispatch the actual Squad Scribe via `task`/`runSubagent`'
        $script:Coordinator | Should -Match 'only the child runs the helper and returns its validated status'
        (Get-SquadReferenceBody 'coordinator-init.md') | Should -Match 'Initialize-Squad\.ps1.+-Direct'
        $script:Coordinator | Should -Match 'ordinary direct-writer orchestration stays in Scribe history without inventing a Scribe actor'
        $script:Coordinator | Should -Match 'Set `stateAdvance.activeRoles` to actually dispatched agents, or `\[\]` when none; running the script never makes Scribe an active actor'
    }
    It 'the payload template carries a roster field for initialization and roster refresh' {
        $script:PayloadTemplate | Should -Match '(?m)^roster: <initialization/roster refresh only'
    }

    It 'the Init cold file requires verbatim rows and a failure note when they are missing' {
        $script:InitCold | Should -Match ([regex]::Escape('**Copy the roster rows from the payload; never derive them.**'))
        $script:InitCold | Should -Match 'When `roster` is absent, or a row lacks its `Agent Name \(Primary\)`, write nothing and return a failure note'
    }

    It 'the Scribe charter binds verbatim row copying at Step 3' {
        $script:Scribe | Should -Match 'Copy each `team.md` row verbatim from the payload `roster`; never derive an agent name\.'
    }

    It 'the coordinator fills roster with the resolved catalog rows' {
        $script:Coordinator | Should -Match 'Init payload: `roster` rows plus `ledgerCommand`'
        $script:OperatingProcedure | Should -Match ([regex]::Escape('**The Init payload carries full roster shape, not just role ids.**'))
    }

    It 'Init carries connector-bindings convergence: copy the section when provided and preserve refresh edits unless explicitly changed' {
        $script:InitCold | Should -Match ([regex]::Escape('If payload `connectorBindings` is present and non-empty, also write `## Connector Bindings` with the exact seed-template header; omit the section entirely when empty or absent.'))
        $script:InitCold | Should -Match ([regex]::Escape('Apply the same preserve rule to existing `connectorBindings` rows and custom routing rows: keep them as-is unless the payload explicitly edits or removes them.'))
    }

    It 'seed-templates.md publishes the canonical Connector Bindings header including Member Name' {
        $headers = @(Get-MarkdownHeadersLocal -Content (Get-SquadReferenceBody -Name 'seed-templates.md') | Where-Object { $_ -contains 'Binding ID' })
        $headers.Count | Should -BeGreaterThan 0
        $headers[0] | Should -Be @('Binding ID', 'Connector ID', 'Manifest', 'Endpoint Kind', 'Role Mode', 'Target Kind', 'Target', 'Member Name', 'Added Role', 'Aligned Role', 'Default Execution')
    }

    It 'seed-templates.md keeps routed roster column placement self-contained for the Scribe' {
        $seedTemplates = Get-SquadReferenceBody -Name 'seed-templates.md'
        $seedTemplates | Should -Match ([regex]::Escape('a `Model` column between `Model Tier` and `Deliverable Root`, filled with each role''s Model ID as the coordinator resolved it'))
    }
}

Describe 'Deterministic fresh Init' -Tag 'Unit' {
    BeforeAll {
        $script:InitScript = Join-Path $script:Model.SquadSkillRoot 'scripts/Initialize-Squad.ps1'
        function Get-InitPayload {
            param([string]$Root = '.copilot-tracking/squad')
            $Rows = @(
                [ordered]@{ Role = 'developer'; 'Member Name' = 'Delta'; 'Agent Name (Primary)' = 'Squad Implementor'; 'Alternate Agents' = 'Confirmed Alternate'; 'Selection Cue' = 'confirmed cue'; Invocation = 'runSubagent / task'; 'Model Tier' = 'default'; Model = 'confirmed-model'; 'Deliverable Root' = '.copilot-tracking/changes/' }
                [ordered]@{ Role = 'developer'; 'Member Name' = 'Alpha'; 'Agent Name (Primary)' = 'Squad Implementor'; 'Alternate Agents' = 'Confirmed Alternate'; 'Selection Cue' = 'confirmed cue'; Invocation = 'runSubagent / task'; 'Model Tier' = 'default'; Model = ''; 'Deliverable Root' = 'outputs/' }
                [ordered]@{ Role = 'scribe'; 'Member Name' = ''; 'Agent Name (Primary)' = 'Squad Scribe'; 'Alternate Agents' = 'none'; 'Selection Cue' = 'none'; Invocation = 'runSubagent / task'; 'Model Tier' = 'fast'; Model = ''; 'Deliverable Root' = '(squad state)' }
            )
            @{
                squadRoot = $Root; runId = 'init-test'; timestamp = '2026-10-17T09:00:00Z'
                roster = $Rows; provenance = 'profile: custom; packs: confirmed-pack'; modelRouting = 'manual'; sessionModel = 'auto'
                stateAdvance = @{ activeRoles = @() }
                usage = @('coordinator', 'scribe' | ForEach-Object {
                        @{ actor = $_; consumption = [ordered]@{ model = 'unknown'; model_source = 'unresolved'; priced_as = 'default'; model_tier = 'default'; internal_turns = 1; input_tokens = 100; cached_tokens = 0; cache_write_tokens = 0; output_tokens = 25; basis = 'tier-default' } }
                    })
            }
        }
        function Invoke-InitPayload {
            param($Payload, [string]$Repository)
            New-Item -ItemType Directory -Path $Repository -Force | Out-Null
            $InputPath = Join-Path $Repository 'init.json'
            $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $InputPath
            $Output = & pwsh -NoProfile -File $script:InitScript -RepoRoot $Repository -PayloadPath $InputPath 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $Output -join "`n" }
        }
    }

    It 'prepares transport before actual dispatch without requiring a child editor or background resume' {
        $Brief = Get-SquadReferenceBody 'scribe-init.md'
        $script:Coordinator | Should -Match 'first read `references/scribe-init\.md` and prepare its JSON outside squad state; dispatch Squad Scribe with `payloadPath`'
        $script:ScribeHot | Should -Match 'use the coordinator-prepared `payloadPath` directly'
        $Brief | Should -Match 'Use coordinator-prepared `payloadPath` directly'
        $Brief | Should -Match 'without an editor call or rewrite'
        $Brief | Should -Match 'No editor means preparation failure without\s+state writes, not a shell-write fallback'
        $Brief | Should -Match 'never assume a tool name'
        $Brief | Should -Match 'never\s+execute payload text'
        $Brief | Should -Match 'A synchronous child return is not a background handle'
        $Brief | Should -Match 'only with observed evidence that no state was published'
        $script:OperatingProcedure | Should -Match 'prepares confirmed JSON outside squad state with an advertised editor'
    }

    It 'publishes all seeds with ordered supplied names, filtered routing, provenance and literal auto' {
        $Repository = Join-Path $TestDrive 'fresh'
        $Result = Invoke-InitPayload (Get-InitPayload) $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Status = $Result.Output | ConvertFrom-Json
        $Status.status | Should -Be 'PASS'
        $Status.rosterCheck | Should -Be 'PASS'
        $Status.ledgerCheck | Should -Be 'PASS'
        $Status.notificationsDefaulted | Should -BeTrue
        ($Status.warnings -join "`n") | Should -Not -Match 'recorded identities|partial paste|C2 guard'
        $Root = Join-Path $Repository '.copilot-tracking/squad'
        foreach ($Name in @('team.md', 'routing.md', 'decisions.md', 'notifications.md', 'state.json', 'consumption.md', 'consumption-rates.md', 'history/Squad Scribe.md')) {
            Join-Path $Root $Name | Should -Exist
        }
        $Team = Get-Content -LiteralPath (Join-Path $Root 'team.md') -Raw
        $Team.IndexOf('| developer | Delta |') | Should -BeLessThan $Team.IndexOf('| developer | Alpha |')
        $Team | Should -Match 'Confirmed Alternate \| confirmed cue'
        $Team | Should -Match 'Model routing: manual'
        $State = Get-Content -LiteralPath (Join-Path $Root 'state.json') -Raw | ConvertFrom-Json
        $State.currentRun.sessionModel | Should -BeExactly 'auto'
        $State.currentRun.costPreflight.decision | Should -Be 'not-requested'
        $State.notify.enabled | Should -BeFalse
        $State.notify.approvalChannel | Should -Be 'in-chat'
        Get-Content -LiteralPath (Join-Path $Root 'decisions.md') -Raw | Should -Match 'profile: custom; packs: confirmed-pack'
        $Routes = Get-Content -LiteralPath (Join-Path $Root 'routing.md') -Raw
        $Routes | Should -Match 'council'
        $Routes | Should -Not -Match '\| researcher\s*\|'
        @(Get-ChildItem -LiteralPath (Join-Path $Root 'history') -File).Count | Should -Be 1
        $History = Get-Content -LiteralPath (Join-Path $Root 'history/Squad Scribe.md') -Raw
        $History | Should -Match 'Initialization coordinator'
        $History | Should -Match 'Initialization scribe'
        $History | Should -Not -Match '"model": "auto"'
        $Ledger = Get-Content -LiteralPath (Join-Path $Root 'consumption.md') -Raw
        $Ledger | Should -Match '(?m)^Squad Scribe\.md — 2 block\(s\) — identities: [0-9a-f]{8},[0-9a-f]{8}$'
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $Root -Check -ExpectedHistoryCounts 'Squad Scribe=2' *> $null
        $LASTEXITCODE | Should -Be 0
    }

    It 'still refuses a fresh post-write ledger whose Scribe identities are missing' {
        $Repository = Join-Path $TestDrive 'missing-scribe-identities'
        $Result = Invoke-InitPayload (Get-InitPayload) $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Root = Join-Path $Repository '.copilot-tracking/squad'
        $LedgerPath = Join-Path $Root 'consumption.md'
        $Ledger = Get-Content -LiteralPath $LedgerPath -Raw
        ($Ledger -replace '(?m)^(Squad Scribe\.md — 2 block\(s\)) — identities: .*$', '$1') |
            Set-Content -LiteralPath $LedgerPath
        $Output = & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $Root -Check -ExpectedHistoryCounts 'Squad Scribe=2' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($Output -join "`n") | Should -Match 'History identity guard:.*no history-entry identities'
    }

    It 'uses the helper UTC clock when Init timestamp is omitted, keeping subsequent artifacts fresh' {
        $Payload = Get-InitPayload
        $Payload.Remove('timestamp')
        $Repository = Join-Path $TestDrive 'clock-init'
        $Before = [DateTimeOffset]::UtcNow
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Root = Join-Path $Repository $Payload.squadRoot
        $StateDocument = [System.Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText((Join-Path $Root 'state.json')))
        try { $Started = $StateDocument.RootElement.GetProperty('updated').GetDateTimeOffset() }
        finally { $StateDocument.Dispose() }
        $Started.ToUnixTimeSeconds() | Should -BeGreaterOrEqual $Before.ToUnixTimeSeconds()
        $Started.ToUnixTimeSeconds() | Should -BeLessOrEqual ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        $Artifact = Join-Path $Repository 'research.md'
        Set-Content -LiteralPath $Artifact -Value 'Actual subsequent research'
        ([IO.File]::GetLastWriteTimeUtc($Artifact)) | Should -BeGreaterOrEqual $Started.UtcDateTime
    }

    It 'refuses a future Init timestamp before publishing state' {
        $Payload = Get-InitPayload
        $Payload.timestamp = [DateTimeOffset]::UtcNow.AddMinutes(2).ToString('o')
        $Repository = Join-Path $TestDrive 'future-init'
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 1
        $Result.Output | Should -Match 'Future Init timestamp refused'
        Join-Path $Repository $Payload.squadRoot | Should -Not -Exist
        @(Get-ChildItem -LiteralPath $Repository -Directory -Recurse -Force).Count | Should -Be 0
    }

    It 'accepts legacy absent usage with estimator floors and unresolved auto without partial state' {
        $Payload = Get-InitPayload
        $Payload.Remove('usage')
        $Repository = Join-Path $TestDrive 'legacy-absent-usage'
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Status = $Result.Output | ConvertFrom-Json
        $Status.historyEntries | Should -Be 2
        $Status.ledgerCheck | Should -Be 'PASS'
        ($Status.warnings -join ' ') | Should -Match 'Estimator-derived setup usage.*not measured tokens or billed telemetry'
        $Root = Join-Path $Repository $Payload.squadRoot
        (Get-Content -LiteralPath (Join-Path $Root 'state.json') -Raw | ConvertFrom-Json).currentRun.sessionModel | Should -BeExactly 'auto'
        $History = Get-Content -LiteralPath (Join-Path $Root 'history/Squad Scribe.md') -Raw
        $History | Should -Match 'Initialization coordinator'
        $History | Should -Match 'Initialization scribe'
        $Blocks = @([regex]::Matches($History, '(?ms)^```json\n(.*?)\n```') | ForEach-Object { $_.Groups[1].Value | ConvertFrom-Json })
        $Blocks.Count | Should -Be 2
        $Blocks.model | Should -Be @('unknown', 'unknown')
        $Blocks.model_source | Should -Be @('unresolved', 'unresolved')
        $Blocks.basis | Should -Be @('tier-default', 'tier-default')
        $Blocks.model_tier | Should -Be @('default', 'fast')
        $Blocks.priced_as | Should -Be @('Claude Sonnet 4.6', 'Claude Haiku 4.5')
        foreach ($Block in $Blocks) {
            $Block.internal_turns | Should -Be 4
            $Block.input_tokens | Should -Be 15600
            $Block.cached_tokens | Should -Be 62400
            $Block.cache_write_tokens | Should -Be 24000
            $Block.output_tokens | Should -Be 3200
        }
        @(Get-ChildItem -LiteralPath $Repository -Directory -Filter '.squad-init-*' -Recurse -Force).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $Repository -Filter state.json -File -Recurse -Force).Count | Should -Be 1
    }

    It 'preserves supplied <Supplied> usage and estimates only the missing <Missing> actor' -ForEach @(
        @{ Supplied = 'coordinator'; Missing = 'scribe' }
        @{ Supplied = 'scribe'; Missing = 'coordinator' }
    ) {
        $Payload = Get-InitPayload
        $Payload.usage = @($Payload.usage | Where-Object { $_.actor -eq $Supplied })
        $Repository = Join-Path $TestDrive "one-actor-$Supplied"
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Status = $Result.Output | ConvertFrom-Json
        $Status.historyEntries | Should -Be 2
        $Status.ledgerCheck | Should -Be 'PASS'
        ($Status.warnings -join ' ') | Should -Match "Estimator-derived setup usage for ${Missing}:"
        $History = Get-Content -LiteralPath (Join-Path $Repository "$($Payload.squadRoot)/history/Squad Scribe.md") -Raw
        $History | Should -Match 'Initialization coordinator'
        $History | Should -Match 'Initialization scribe'
        $History | Should -Match "Setup usage recorded for $Supplied\."
        $History | Should -Match "Estimator-derived setup usage for $Missing;"
        $History | Should -Not -Match "Estimator-derived setup usage for $Supplied;"
        $History | Should -Match '"input_tokens": 100'
    }

    It 'derives only permitted coordinator session attribution for <Session>' -ForEach @(
        @{ Session = 'GPT-5.4'; Identity = 'GPT-5.4'; Source = 'session-inherited'; Price = 'GPT-5.4'; Basis = 'estimated'; CacheWrite = 0 }
        @{ Session = ''; Identity = 'unknown'; Source = 'unresolved'; Price = 'Claude Sonnet 4.6'; Basis = 'tier-default'; CacheWrite = 24000 }
        @{ Session = 'Claude Opus 5 (Copilot)'; Identity = 'Claude Opus 5 (Copilot)'; Source = 'session-inherited'; Price = 'Claude Opus 5'; Basis = 'estimated'; CacheWrite = 24000 }
    ) {
        $Payload = Get-InitPayload
        $Payload.Remove('usage')
        $Payload.sessionModel = $Session
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $History = Get-Content -LiteralPath (Join-Path $Repository "$($Payload.squadRoot)/history/Squad Scribe.md") -Raw
        $Blocks = @([regex]::Matches($History, '(?ms)^```json\n(.*?)\n```') | ForEach-Object { $_.Groups[1].Value | ConvertFrom-Json })
        $Blocks[0].model | Should -BeExactly $Identity
        $Blocks[0].model_source | Should -Be $Source
        $Blocks[0].priced_as | Should -Be $Price
        $Blocks[0].basis | Should -Be $Basis
        $Blocks[0].cache_write_tokens | Should -Be $CacheWrite
        $Blocks[1].model | Should -Be 'unknown'
        $Blocks[1].model_source | Should -Be 'unresolved'
        $Blocks[1].model_tier | Should -Be 'fast'
    }

    It 'rejects absent usage when the shipped estimator is unavailable without partial state' {
        $HelperDirectory = Join-Path $TestDrive 'missing-estimator-helper'
        Copy-Item -LiteralPath $script:Model.SquadSkillRoot -Destination $HelperDirectory -Recurse
        $Template = Join-Path $HelperDirectory 'references/consumption-rates-template.md'
        $Text = Get-Content -LiteralPath $Template -Raw
        Set-Content -LiteralPath $Template -Value $Text.Replace('Scribe state write', 'Unavailable state write') -NoNewline
        $Payload = Get-InitPayload
        $Payload.Remove('usage')
        $Repository = Join-Path $TestDrive 'missing-estimator'
        $OriginalInit = $script:InitScript
        try {
            $script:InitScript = Join-Path $HelperDirectory 'scripts/Initialize-Squad.ps1'
            $Result = Invoke-InitPayload $Payload $Repository
        }
        finally { $script:InitScript = $OriginalInit }
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Missing shipped setup orchestration estimator floor'
        @(Get-ChildItem -LiteralPath $Repository -Filter state.json -File -Recurse -Force).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $Repository -Directory -Filter '.squad-init-*' -Recurse -Force).Count | Should -Be 0
    }

    It 'refuses re-init without altering any state bytes' {
        $Repository = Join-Path $TestDrive 'reinit-refusal'
        $Result = Invoke-InitPayload (Get-InitPayload) $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Root = Join-Path $Repository '.copilot-tracking/squad'
        $Before = @(Get-ChildItem -LiteralPath $Root -File -Recurse | Get-FileHash | ForEach-Object Hash) -join ','
        $Result = Invoke-InitPayload (Get-InitPayload) $Repository
        $Result.ExitCode | Should -Not -Be 0
        $After = @(Get-ChildItem -LiteralPath $Root -File -Recurse | Get-FileHash | ForEach-Object Hash) -join ','
        $After | Should -BeExactly $Before
    }

    It 'supports a member root, preserves outputs, and records supplied notifications' {
        $Repository = Join-Path $TestDrive 'member'
        $Payload = Get-InitPayload '.copilot-tracking/squad/members/product'
        $Payload.notify = @{ approvalChannel = 'github-issue'; enabled = $true; github = @{ handle = 'confirmed'; repo = 'owner/repo' } }
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Root = Join-Path $Repository $Payload.squadRoot
        $Team = Get-Content -LiteralPath (Join-Path $Root 'team.md') -Raw
        $Team | Should -Match '\.copilot-tracking/squad/members/product/changes/'
        $Team | Should -Match '\| outputs/ \|'
        $State = Get-Content -LiteralPath (Join-Path $Root 'state.json') -Raw | ConvertFrom-Json
        $State.notify.github.handle | Should -Be 'confirmed'
        $State.notify.enabled | Should -BeTrue
    }

    It 'accepts webhook selection without persisting transport credentials and keeps email courtesy-only' {
        $Payload = Get-InitPayload
        $Payload.notify = @{ approvalChannel = 'webhook'; enabled = $true; email = 'courtesy@example.test' }
        $Repository = Join-Path $TestDrive 'webhook'
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $State = Get-Content -LiteralPath (Join-Path $Repository "$($Payload.squadRoot)/state.json") -Raw | ConvertFrom-Json
        $State.notify.approvalChannel | Should -Be 'webhook'
        $State.notify.email | Should -Be 'courtesy@example.test'
        @($State.notify.PSObject.Properties.Name) | Should -Be @('approvalChannel', 'enabled', 'email', 'github')
    }

    It 'preserves a legal unnamed roster with empty alternates verbatim' {
        $Payload = Get-InitPayload
        $Payload.roster = @($Payload.roster[0], $Payload.roster[2])
        foreach ($Row in $Payload.roster) { $Row['Member Name'] = ''; $Row['Alternate Agents'] = '' }
        $Repository = Join-Path $TestDrive 'empty-alternates'
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Team = Get-Content -LiteralPath (Join-Path $Repository "$($Payload.squadRoot)/team.md") -Raw
        $Team | Should -Match '\| developer \|  \| Squad Implementor \|  \| confirmed cue \|'
        $Team | Should -Match '\| scribe \|  \| Squad Scribe \|  \| none \|'
    }

    It 'confines and canonicalizes member deliverable shape <Root>' -ForEach @(
        @{ Root = './.copilot-tracking/changes/'; Expected = '.copilot-tracking/squad/members/product/changes/' }
        @{ Root = 'changes/'; Expected = '.copilot-tracking/squad/members/product/changes/' }
        @{ Root = '.copilot-tracking/squad/members/product/changes/'; Expected = '.copilot-tracking/squad/members/product/changes/' }
        @{ Root = '.\.copilot-tracking\changes\'; Expected = '.copilot-tracking/squad/members/product/changes/' }
        @{ Root = '`./.copilot-tracking/changes/`'; Expected = '.copilot-tracking/squad/members/product/changes/' }
        @{ Root = './docs/architecture/'; Expected = 'docs/architecture/' }
        @{ Root = './outputs/'; Expected = 'outputs/' }
        @{ Root = '.copilot-tracking/workitems/execution/<date>/ (ADO) or .copilot-tracking/jira-issues/execution/<date>/ (Jira)'; Expected = '.copilot-tracking/squad/members/product/workitems/execution/<date>/ (ADO) or .copilot-tracking/squad/members/product/jira-issues/execution/<date>/ (Jira)' }
    ) {
        $Payload = Get-InitPayload '.copilot-tracking/squad/members/product'
        $Payload.roster[0]['Deliverable Root'] = $Root
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        Get-Content -LiteralPath (Join-Path $Repository "$($Payload.squadRoot)/team.md") -Raw | Should -Match ([regex]::Escape("| $Expected |"))
    }

    It 'rejects member escape shape <Root> without publishing state' -ForEach @(
        @{ Root = '.copilot-tracking/squad/members/other/changes/' }
        @{ Root = './.copilot-tracking/squad/members/other/changes/' }
        @{ Root = '.copilot-tracking/squad/members/product-other/changes/' }
        @{ Root = '.\.copilot-tracking\squad\members\other\changes\' }
        @{ Root = '`.copilot-tracking/squad/members/other/changes/`' }
        @{ Root = 'docs/ (ADO) or .copilot-tracking/squad/members/other/changes/ (Jira)' }
    ) {
        $Payload = Get-InitPayload '.copilot-tracking/squad/members/product'
        $Payload.roster[0]['Deliverable Root'] = $Root
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'selected member'
        @(Get-ChildItem -LiteralPath $Repository -Filter state.json -File -Recurse).Count | Should -Be 0
    }

    It 'preserves member sentinel <Root> verbatim while still rebasing ordinary and reviewer roots' -ForEach @(
        @{ Root = [string][char]0x2014 }
        @{ Root = '(squad state)' }
    ) {
        $Payload = Get-InitPayload '.copilot-tracking/squad/members/product'
        $Payload.roster[0]['Deliverable Root'] = $Root
        $Payload.roster[1]['Deliverable Root'] = '.copilot-tracking/reviews/'
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Team = Get-Content -LiteralPath (Join-Path $Repository "$($Payload.squadRoot)/team.md") -Raw
        $Team | Should -Match ([regex]::Escape("| $Root |"))
        $Team | Should -Match '\| \.copilot-tracking/squad/members/product/reviews/ \|'
    }

    It 'RQ-04 rejects an unusable intake capture root <Root> before any state publication' -ForEach @(
        @{ Root = [string][char]0x2014 }
        @{ Root = '(squad state)' }
        @{ Root = '.copilot-tracking/squad/' }
        @{ Root = '.copilot-tracking/squad/state.json/' }
        @{ Root = '.copilot-tracking/squad/history/' }
        @{ Root = '' }
        @{ Root = '../outside/' }
        @{ Root = '/absolute/reviews/' }
    ) {
        $Payload = Get-InitPayload
        $Payload.roster[1].Role = 'intake-validator'
        $Payload.roster[1]['Agent Name (Primary)'] = 'Confirmed Read Only Reviewer'
        $Payload.roster[1]['Deliverable Root'] = $Root
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Not -Be 0
        Join-Path $Repository $Payload.squadRoot | Should -Not -Exist
        @(Get-ChildItem -LiteralPath $Repository -Force -Recurse -File |
                Where-Object Name -ne 'init.json').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $Repository -Force -Recurse -Directory).Count | Should -Be 0
    }

    It 'RQ-04 preserves a custom capture root and actual reviewer name under <SquadRoot>' -ForEach @(
        @{ SquadRoot = '.copilot-tracking/squad'; Expected = '.copilot-tracking/custom-reviews/' }
        @{ SquadRoot = '.copilot-tracking/squad/members/product'; Expected = '.copilot-tracking/squad/members/product/custom-reviews/' }
    ) {
        $Payload = Get-InitPayload $SquadRoot
        $Payload.roster[1].Role = 'intake-validator'
        $Payload.roster[1]['Agent Name (Primary)'] = 'Confirmed Read Only Reviewer'
        $Payload.roster[1]['Deliverable Root'] = '.copilot-tracking/custom-reviews/'
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Team = Get-Content -LiteralPath (Join-Path $Repository "$SquadRoot/team.md") -Raw
        $Team | Should -Match ([regex]::Escape('| intake-validator | Alpha | Confirmed Read Only Reviewer |'))
        $Team | Should -Match ([regex]::Escape("| $Expected |"))
        @(Get-ChildItem -LiteralPath (Join-Path $Repository "$SquadRoot/history") -File).Name | Should -Be 'Squad Scribe.md'
    }

    It 'accepts an absent or empty-directory-only root: <Case>' -ForEach @(
        @{ Case = 'empty root'; Dirs = @('.') }
        @{ Case = 'nested empty scaffold'; Dirs = @('history', 'a/b/c') }
    ) {
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        foreach ($Dir in $Dirs) { New-Item -ItemType Directory -Path (Join-Path (Join-Path $Repository '.copilot-tracking/squad') $Dir) -Force | Out-Null }
        $Result = Invoke-InitPayload (Get-InitPayload) $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        Test-Path -LiteralPath (Join-Path $Repository '.copilot-tracking/squad/state.json') | Should -BeTrue
        @(Get-ChildItem -LiteralPath $Repository -Force -Filter '.squad-init-*' -Recurse).Count | Should -Be 0
    }

    It 'refuses an unsafe existing root <Case> and leaves it unchanged' -ForEach @(
        @{ Case = 'hidden file'; Kind = 'hidden' }
        @{ Case = 'linked subtree'; Kind = 'link' }
        @{ Case = 'dangling link'; Kind = 'dangling' }
        @{ Case = 'populated state'; Kind = 'file' }
        @{ Case = 'invalid payload over empty scaffold'; Kind = 'invalid' }
    ) {
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Root = Join-Path $Repository '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Join-Path $Root 'sub') -Force | Out-Null
        switch ($Kind) {
            'hidden' { Set-Content -LiteralPath (Join-Path $Root 'sub/.keep') -Value 'x' }
            'file' { Set-Content -LiteralPath (Join-Path $Root 'state.json') -Value '{}' }
            'link' {
                New-Item -ItemType Directory -Path (Join-Path $Repository 'target') -Force | Out-Null
                try { New-Item -ItemType SymbolicLink -Path (Join-Path $Root 'sub/link') -Target (Join-Path $Repository 'target') -ErrorAction Stop | Out-Null }
                catch [UnauthorizedAccessException] { Set-ItResult -Skipped -Because 'Symbolic-link creation requires an unavailable OS privilege.'; return }
            }
            'dangling' {
                try { New-Item -ItemType SymbolicLink -Path (Join-Path $Root 'sub/link') -Target (Join-Path $Repository 'missing') -ErrorAction Stop | Out-Null }
                catch [UnauthorizedAccessException] { Set-ItResult -Skipped -Because 'Symbolic-link creation requires an unavailable OS privilege.'; return }
            }
        }
        $Payload = Get-InitPayload
        if ($Kind -eq 'invalid') { $Payload.roster[0]['Model Tier'] = 'bogus' }
        $Before = @(Get-ChildItem -LiteralPath $Root -Force -Recurse | ForEach-Object { $_.FullName.Substring($Root.Length) }) -join ','
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Not -Be 0
        $After = @(Get-ChildItem -LiteralPath $Root -Force -Recurse | ForEach-Object { $_.FullName.Substring($Root.Length) }) -join ','
        $After | Should -BeExactly $Before
        Test-Path -LiteralPath (Join-Path $Root 'team.md') | Should -BeFalse
    }

    It 'accepts coherent pricing for <ModelName> without changing actual attribution' -ForEach @(
        @{ ModelName = 'Claude Opus 5'; Price = 'Claude Opus 5'; Tier = 'fast'; Source = 'dispatch-reported'; Basis = 'estimated' }
        @{ ModelName = 'claude-haiku-4.5'; Price = 'Claude Haiku 4.5'; Tier = 'fast'; Source = 'dispatch-reported'; Basis = 'estimated' }
        @{ ModelName = 'Unlisted Actual Model'; Price = 'Claude Sonnet 4.6'; Tier = 'default'; Source = 'operator-declared'; Basis = 'estimated' }
        @{ ModelName = 'unknown'; Price = 'Claude Haiku 4.5'; Tier = 'fast'; Source = 'unresolved'; Basis = 'tier-default' }
    ) {
        $Payload = Get-InitPayload
        $Block = $Payload.usage[0].consumption
        $Block.model = $ModelName; $Block.priced_as = $Price; $Block.model_tier = $Tier; $Block.model_source = $Source; $Block.basis = $Basis
        $Repository = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $History = Get-Content -LiteralPath (Join-Path $Repository "$($Payload.squadRoot)/history/Squad Scribe.md") -Raw
        $History | Should -Match ([regex]::Escape('"model": "' + $ModelName + '"'))
        $History | Should -Match ([regex]::Escape('"model_source": "' + $Source + '"'))
    }

    It 'rejects contradictory pricing <Case> and removes staged state' -ForEach @(
        @{ Case = 'known model cheap real row'; ModelName = 'Claude Opus 5'; Price = 'Claude Haiku 4.5'; Source = 'dispatch-reported'; Basis = 'estimated' }
        @{ Case = 'known model tier label'; ModelName = 'Claude Opus 5'; Price = 'default'; Source = 'dispatch-reported'; Basis = 'estimated' }
        @{ Case = 'unlisted wrong fallback'; ModelName = 'Unlisted Actual Model'; Price = 'Claude Haiku 4.5'; Source = 'dispatch-reported'; Basis = 'estimated' }
        @{ Case = 'unknown wrong fallback'; ModelName = 'unknown'; Price = 'Claude Haiku 4.5'; Source = 'unresolved'; Basis = 'tier-default' }
        @{ Case = 'unknown estimated'; ModelName = 'unknown'; Price = 'default'; Source = 'unresolved'; Basis = 'estimated' }
        @{ Case = 'resolved tier-default'; ModelName = 'Claude Opus 5'; Price = 'Claude Opus 5'; Source = 'dispatch-reported'; Basis = 'tier-default' }
        @{ Case = 'unlisted tier-default'; ModelName = 'Unlisted Actual Model'; Price = 'default'; Source = 'dispatch-reported'; Basis = 'tier-default' }
        @{ Case = 'invented tier identity'; ModelName = 'default'; Price = 'default'; Source = 'dispatch-reported'; Basis = 'estimated' }
        @{ Case = 'normalized auto'; ModelName = ' auto '; Price = 'default'; Source = 'dispatch-reported'; Basis = 'estimated' }
        @{ Case = 'unresolved concrete identity'; ModelName = 'Claude Opus 5'; Price = 'Claude Opus 5'; Source = 'unresolved'; Basis = 'estimated' }
        @{ Case = 'inherited mismatch'; ModelName = 'Claude Opus 5'; Price = 'Claude Opus 5'; Source = 'session-inherited'; Basis = 'estimated' }
    ) {
        $Payload = Get-InitPayload
        $Block = $Payload.usage[0].consumption
        $Block.model = $ModelName; $Block.priced_as = $Price; $Block.model_source = $Source; $Block.basis = $Basis
        $Repository = Join-Path $TestDrive $Case.Replace(' ', '-')
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Not -Be 0
        @(Get-ChildItem -LiteralPath $Repository -Filter state.json -File -Recurse).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $Repository -Directory -Filter '.squad-init-*' -Recurse -Force).Count | Should -Be 0
    }

    It 'rejects invalid notify <Case> without persisting credentials' -ForEach @(
        @{ Case = 'email approval'; Notify = @{ approvalChannel = 'email'; enabled = $true; email = 'courtesy@example.test' } }
        @{ Case = 'github alias'; Notify = @{ approvalChannel = 'github'; enabled = $true } }
        @{ Case = 'missing github details'; Notify = @{ approvalChannel = 'github-issue'; enabled = $true } }
        @{ Case = 'webhook url'; Notify = @{ approvalChannel = 'webhook'; enabled = $true; webhook = @{ url = 'https://example.test/private-token' } } }
        @{ Case = 'webhook credentials'; Notify = @{ approvalChannel = 'webhook'; enabled = $true; credentials = 'private-token' } }
    ) {
        $Payload = Get-InitPayload
        $Payload.notify = $Notify
        $Repository = Join-Path $TestDrive $Case.Replace(' ', '-')
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Not -Be 0
        @(Get-ChildItem -LiteralPath $Repository -Filter state.json -File -Recurse).Count | Should -Be 0
    }

    It 'returns complete colored child warnings with explicit notify' {
        $HelperDirectory = Join-Path $TestDrive 'colored-helper'
        Copy-Item -LiteralPath $script:Model.SquadSkillRoot -Destination $HelperDirectory -Recurse
        $Seeder = Join-Path $HelperDirectory 'scripts/Initialize-SquadConsumptionRates.ps1'
        $SeederText = Get-Content -LiteralPath $Seeder -Raw
        $SeederText = $SeederText.Replace("if (`$Check -and `$Reseed)", "[Console]::WriteLine(`"``e[33;1mWARNING: WARN:example complete warning``e[0m`")`nif (`$Check -and `$Reseed)")
        Set-Content -LiteralPath $Seeder -Value $SeederText -NoNewline
        $Payload = Get-InitPayload
        $Payload.notify = @{ approvalChannel = 'in-chat'; enabled = $false }
        $OriginalInit = $script:InitScript
        try {
            $script:InitScript = Join-Path $HelperDirectory 'scripts/Initialize-Squad.ps1'
            $Result = Invoke-InitPayload $Payload (Join-Path $TestDrive 'colored-warning')
        }
        finally { $script:InitScript = $OriginalInit }
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Status = $Result.Output | ConvertFrom-Json
        $Status.notificationsDefaulted | Should -BeFalse
        $Status.warnings | Should -Contain 'WARNING: WARN:example complete warning'
        $Status.warnings | Should -Not -Contain 'Notifications defaulted to disabled in-chat.'
        ($Status.warnings -join '') | Should -Not -Match '\x1b'
    }

    It 'fails closed for <Case>' -ForEach @(
        @{ Case = 'missing roster' }, @{ Case = 'missing roster and usage' }, @{ Case = 'missing primary' }, @{ Case = 'duplicate names' }, @{ Case = 'traversal' }, @{ Case = 'deliverable traversal' }, @{ Case = 'invalid usage' }, @{ Case = 'empty usage' }, @{ Case = 'null usage' }, @{ Case = 'malformed usage' }, @{ Case = 'invalid source' }, @{ Case = 'unknown attribution' }, @{ Case = 'invalid notifications' }
    ) {
        $Payload = Get-InitPayload
        switch ($Case) {
            'missing roster' { $Payload.Remove('roster') }
            'missing roster and usage' { $Payload.Remove('roster'); $Payload.Remove('usage') }
            'missing primary' { $Payload.roster[0].Remove('Agent Name (Primary)') }
            'duplicate names' { $Payload.roster[1]['Member Name'] = 'Delta' }
            'traversal' { $Payload.squadRoot = '.copilot-tracking/squad/../escape' }
            'deliverable traversal' { $Payload.roster[0]['Deliverable Root'] = '../outside' }
            'invalid usage' { $Payload.usage[0].consumption.input_tokens = -1 }
            'empty usage' { $Payload.usage = @() }
            'null usage' { $Payload.usage = $null }
            'malformed usage' { $Payload.usage = @{} }
            'invalid source' { $Payload.usage[0].consumption.model_source = 'fictional' }
            'unknown attribution' { $Payload.usage[0].consumption.model_source = 'dispatch-reported' }
            'invalid notifications' { $Payload.notify = @{ enabled = $true; approvalChannel = 'github' } }
        }
        $Repository = Join-Path $TestDrive $Case.Replace(' ', '-')
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Not -Be 0 -Because $Result.Output
        @(Get-ChildItem -LiteralPath $Repository -Filter state.json -File -Recurse -Force).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $Repository -Directory -Filter '.squad-init-*' -Recurse -Force).Count | Should -Be 0
    }

    It 'does not execute legacy command strings and refuses symlink boundaries' {
        $Repository = Join-Path $TestDrive 'hostile'
        $Payload = Get-InitPayload
        $Payload.ledgerCommand = 'throw "DO NOT EXECUTE"'
        $Result = Invoke-InitPayload $Payload $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $LinkedRepository = Join-Path $TestDrive 'linked'
        New-Item -ItemType Directory -Path $LinkedRepository | Out-Null
        try { New-Item -ItemType SymbolicLink -Path (Join-Path $LinkedRepository '.copilot-tracking') -Target $Repository -ErrorAction Stop | Out-Null }
        catch [UnauthorizedAccessException] { Set-ItResult -Skipped -Because 'Symbolic-link creation requires an unavailable OS privilege.'; return }
        $Result = Invoke-InitPayload (Get-InitPayload) $LinkedRepository
        $Result.ExitCode | Should -Not -Be 0
        $Result.Output | Should -Match 'Linked path refused'
    }

    It 'ledger owns the initialization comparison and detects tampering or a missing section' {
        $Repository = Join-Path $TestDrive 'ledger-comparison-tampering'
        $Result = Invoke-InitPayload (Get-InitPayload) $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Root = Join-Path $Repository '.copilot-tracking/squad'
        $LedgerPath = Join-Path $Root 'consumption.md'
        $Original = Get-Content -LiteralPath $LedgerPath -Raw
        $Original | Should -Match 'n/a \(initialization\)'
        foreach ($Changed in @($Original.Replace('n/a (initialization)', 'fictional baseline'), ($Original -replace '(?ms)^## Cost Comparison.*', ''))) {
            Set-Content -LiteralPath $LedgerPath -Value $Changed -NoNewline
            & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $Root -Check *> $null
            $LASTEXITCODE | Should -Not -Be 0
        }
        Set-Content -LiteralPath $LedgerPath -Value $Original -NoNewline
    }

    It 'keeps the brief below 8KB and makes success terminal without template reads' {
        $Brief = Get-SquadReferenceBody 'scribe-init.md'
        [System.Text.Encoding]::UTF8.GetByteCount($Brief) | Should -BeLessThan 8000
        $Brief | Should -Match 'Return the compact JSON status and warnings, then stop'
        $Brief | Should -Match 'do not read the'
        $Brief | Should -Match 'Optional `usage`'
        $Brief | Should -Match 'documented estimates, not measured tokens or'
        $Brief | Should -Match 'cold path for omitted usage'
        $script:ScribeHot | Should -Match 'no extra reads or accounting audit'
    }

    It 'seeds routing off without a Model column and retains supplied unnamed members' {
        $Payload = Get-InitPayload
        $Payload.modelRouting = 'off'
        foreach ($Row in $Payload.roster) { $Row.Remove('Model') }
        $Payload.roster[0]['Member Name'] = 'Delta'
        $Payload.roster[1]['Member Name'] = 'Alpha'
        $Result = Invoke-InitPayload $Payload (Join-Path $TestDrive 'off')
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Team = Get-Content -LiteralPath (Join-Path $TestDrive 'off/.copilot-tracking/squad/team.md') -Raw
        $Team | Should -Not -Match 'Model routing:|\| Model \|'
        $Team | Should -Match '\| scribe \|  \| Squad Scribe \|'
    }

    It 'transitions to the first actual work comparison without duplicate sections or fictional baselines' {
        $Repository = Join-Path $TestDrive 'first-work-comparison'
        $Result = Invoke-InitPayload (Get-InitPayload) $Repository
        $Result.ExitCode | Should -Be 0 -Because $Result.Output
        $Root = Join-Path $Repository '.copilot-tracking/squad'
        $WorkDirectory = Join-Path $Repository '.copilot-tracking/changes'
        New-Item -ItemType Directory -Path $WorkDirectory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $WorkDirectory 'work.md') -Value '# Actual work'
        $Consumption = (Get-InitPayload).usage[0].consumption
        $Payload = @{
            runId = 'init-test'; timestamp = [DateTimeOffset]::UtcNow.ToString('o')
            historyRecords = @(@{ agent = 'Squad Implementor'; memberName = 'Delta'; request = 'Write the work artifact'; deliverable = '.copilot-tracking/changes/work.md'; outcome = 'Artifact written'; consumption = $Consumption })
            orchestration = @{ consumption = $Consumption }
            stateAdvance = @{ activeRoles = @('developer') }
        }
        $InputPath = Join-Path $Repository 'work.json'
        $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $InputPath
        $Writer = Join-Path $script:Model.SquadSkillRoot 'scripts/Write-SquadHandoff.ps1'
        $PreviousHome = $env:COPILOT_HOME
        try {
            $env:COPILOT_HOME = Join-Path $TestDrive 'empty-session-home'
            $Output = & pwsh -NoProfile -File $Writer -SquadRoot $Root -PayloadPath $InputPath -Quiet 2>&1
            $LASTEXITCODE | Should -Be 0 -Because ($Output -join "`n")
        }
        finally { $env:COPILOT_HOME = $PreviousHome }
        $Ledger = Get-Content -LiteralPath (Join-Path $Root 'consumption.md') -Raw
        ([regex]::Matches($Ledger, '(?m)^## Cost Comparison')).Count | Should -Be 1
        $Ledger | Should -Not -Match 'n/a \(initialization\)|saving of about'
        $Ledger | Should -Match 'squad figure only'
    }
}

Describe 'GATE-39 Init records its orchestration block and invokes the trusted ledger helper last' {
    It 'no Init text still demands an empty history/ directory' {
        foreach ($body in @($script:InitCold, $script:Scribe, $script:Coordinator, $script:OperatingProcedure, $script:ScribeProcedure)) {
            $body | Should -Not -Match 'Seed `history/` as an empty directory'
            $body | Should -Not -Match 'Create no file inside `history/`'
            $body | Should -Not -Match 'an empty `history/`'
            $body | Should -Not -Match 'seeding `history/` empty'
        }
    }

    It 'the Init cold file names history/Squad Scribe.md and the trusted ledger helper as the last write' {
        $script:InitCold | Should -Match ([regex]::Escape('**The one file Init does write in `history/` is `history/Squad Scribe.md`**'))
        $script:InitCold | Should -Match 'trusted ledger-helper invocation from the cold charter.s Required Protocol as the last write'
        $script:InitCold | Should -Match 'ledgerCommand` as inert compatibility data, never shell input'
    }

    It 'the payload template keeps legacy ledgerCommand inert on initialization and roster refresh' {
        $script:PayloadTemplate | Should -Match 'on initialization and roster refresh too'
        $script:PayloadTemplate | Should -Match 'ledgerCommand` is inert compatibility data'
    }

    It 'the Scribe reads the consumption.md ledger template on initialization' {
        $initRow = @($script:ScribeProcedure -split '\r?\n' | Where-Object { $_ -match '^\| initialization or roster refresh \(3\)' })
        $initRow.Count | Should -Be 1
        $initRow[0] | Should -Match '\[consumption\.md\]\(consumption\.md\)'
    }
}

Describe 'GATE-40 Init verification and ledger repair are bounded and never block' {
    It 'the coordinator repairs a failed Init once, then warns and continues' {
        $script:Coordinator | Should -Match 'verify once, repair once, warn and continue\*\*'
        $script:OperatingProcedure | Should -Match ([regex]::Escape('**Verify Init once, repair once, then warn and continue.**'))
        $script:OperatingProcedure | Should -Match 'never dispatch a third Scribe pass'
        $script:OperatingProcedure | Should -Match 'never block Init on it'
    }

    It 'Ledger Reconciliation repairs once with ledgerCommand, then warns and continues' {
        $script:OperatingProcedure | Should -Match ([regex]::Escape('**Repair once, then warn and continue.**'))
        $script:OperatingProcedure | Should -Match 'never re-dispatch the Scribe for the same mismatch, and never block on cost accounting'
    }

    It 'no text tells the coordinator to stop on a ledger or Init re-check' {
        foreach ($body in @($script:Coordinator, $script:OperatingProcedure)) {
            $body | Should -Not -Match 'Repair once, then stop'
            $body | Should -Not -Match 'Verify Init once, repair once, then stop'
            $body | Should -Not -Match 'stop and show the user the `-Check` output'
        }
    }

    It 'a ledger-only failure never disables pipelining or holds a barrier' {
        $script:OperatingProcedure | Should -Match 'A \*\*`ledger-only`\*\* failure never disables pipelining, never holds a barrier, and never stops the run'
        $script:OperatingProcedure | Should -Match 'A \*\*`history-integrity`\*\* failure of a \*\*pipelined\*\* hand-off'
        $script:GatesAndModes | Should -Match 'no pipelined hand-off has failed verification with `failure class: history-integrity` this run'
        $script:GatesAndModes | Should -Match 'reports only `failure class: ledger-only` counts as verified for the barrier'
    }
}

Describe 'GATE-41 The scripted ledger converges after Init and after one corrective hand-off' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Split-Path $script:Root) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'fixtures', 'scribe-benchmark', 'seed') -Destination $script:Root -Recurse
        $script:ScribeHistory = Join-Path $script:Root 'history/Squad Scribe.md'

        $header =  "---`ndescription: `"Append-only dispatch history for a single squad agent`"`n---`n`n# History: Squad Scribe`n"
        Set-Content -LiteralPath $script:ScribeHistory -Value ($header + (Format-OrchestrationEntry -Title 'Initialization state seed' -Turn 1)) -NoNewline -Encoding utf8
    }

    It 'fails -Check as ledger-only when the Init block is on disk but the ledger was left at its seed (the 0.18.0 trap)' {
        $check = Invoke-Ledger -Mode Check
        $check.ExitCode | Should -Not -Be 0
        $check.Output | Should -Match 'failure class: ledger-only' -Because 'an unpriced block is cost accounting, never a reason to block the run or disable pipelining'
    }

    It 'passes -Check once the Init hand-off runs ledgerCommand last' {
        (Invoke-Ledger -Mode Write).ExitCode | Should -Be 0
        $check = Invoke-Ledger -Mode Check
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'converges in one corrective pass when that pass appends its own block before -Write' {
        Add-Content -LiteralPath $script:ScribeHistory -Value (Format-OrchestrationEntry -Title 'Roster refresh' -Turn 2) -NoNewline -Encoding utf8
        (Invoke-Ledger -Mode Write).ExitCode | Should -Be 0
        $check = Invoke-Ledger -Mode Check
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'is one block behind when a pass appends its block without -Write' {
        Add-Content -LiteralPath $script:ScribeHistory -Value (Format-OrchestrationEntry -Title 'Hand-written repair' -Turn 3) -NoNewline -Encoding utf8
        $check = Invoke-Ledger -Mode Check
        $check.ExitCode | Should -Not -Be 0 -Because 'a hand-written ledger never folds the block its own hand-off appends'
        $check.Output | Should -Match 'failure class: ledger-only'
    }
}

Describe 'GATE-42 -Check separates history-integrity failures from ledger-only ones' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'integrity/.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Split-Path $script:Root) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'fixtures', 'scribe-benchmark', 'applied') -Destination $script:Root -Recurse
        $script:ScribeHistory = Join-Path $script:Root 'history/Squad Scribe.md'
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -Write *> $null
    }

    It 'passes on the applied fixture once -Write has run' {
        $check = Invoke-Ledger -Mode Check -ExpectedScribeEntries 1
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'reports history-integrity when an expected history entry is missing' {
        $check = Invoke-Ledger -Mode Check -ExpectedScribeEntries 2
        $check.ExitCode | Should -Not -Be 0
        $check.Output | Should -Match 'failure class: history-integrity'
    }

    It 'reports history-integrity when a recorded entry is overwritten in place' {
        $content = Get-Content -LiteralPath $script:ScribeHistory -Raw
        Set-Content -LiteralPath $script:ScribeHistory -Value ($content -replace 'Recording the research-stage history entry and decision', 'Rewritten heading') -NoNewline -Encoding utf8
        $check = Invoke-Ledger -Mode Check
        $check.ExitCode | Should -Not -Be 0
        $check.Output | Should -Match 'failure class: history-integrity'
    }
}

# Observed on the e621b5e build (test-hve-squad-local, run ap-20261007-001): the
# history template ended with an `<!-- Append each new ... -->` marker, the Scribe
# wrote each entry above it, and the pipelined -Check -BaselinePath reported the
# turn-4 entry as "inserted inside the file". That latched pipelining off although
# no byte was lost and the entry order was intact.
Describe 'GATE-43 A trailing marker comment never latches pipelining off' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'marker/.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Split-Path $script:Root) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'fixtures', 'scribe-benchmark', 'applied') -Destination $script:Root -Recurse
        $script:ScribeHistory = Join-Path $script:Root 'history/Squad Scribe.md'
        $script:Marker = '<!-- Append each new orchestration entry at the end of this file, after the last entry. -->'
        $original = (Get-Content -LiteralPath $script:ScribeHistory -Raw).TrimEnd()
        Set-Content -LiteralPath $script:ScribeHistory -Value ($original + "`n`n" + $script:Marker + "`n") -NoNewline -Encoding utf8
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -Write *> $null

        function Invoke-BaselineCheck {
            param([Parameter(Mandatory)][string]$BaselinePath)
            $output = & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -Check -BaselinePath $BaselinePath 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
        }

        function Format-OrchestrationEntryText {
            param([Parameter(Mandatory)][string]$Title)
            $fence = '```'
            @(
                "### 2026-10-07T13:20:00+02:00 $Title"
                ''
                '* Turn: 4'
                "* Request: $Title."
                '* Deliverable: `state.json`'
                "* Outcome: $Title recorded."
                ''
                '#### Consumption — Orchestration'
                ''
                "${fence}json"
                '{'
                '  "model": "Claude Haiku 4.5",'
                '  "model_source": "agent-pinned",'
                '  "priced_as": "Claude Haiku 4.5",'
                '  "model_tier": "fast",'
                '  "internal_turns": 4,'
                '  "input_tokens": 3000,'
                '  "cached_tokens": 12000,'
                '  "cache_write_tokens": 1250,'
                '  "output_tokens": 3200,'
                '  "basis": "estimated"'
                '}'
                $fence
                ''
                ''
            ) -join "`n"
        }
    }

    It 'no append-only template ends with a marker comment' {
        $schemas = Get-SquadReferenceBody -Name 'entry-schemas.md'
        $schemas | Should -Not -Match '<!-- Append each new'
        (Get-SquadReferenceBody -Name 'scribe-cold-gates-and-verdicts.md') | Should -Not -Match '<!-- Append each new'
        (Get-SquadReferenceBody -Name 'federation-templates.md') | Should -Not -Match '<!-- Append each new'
        $script:ScribeProcedure | Should -Match 'add each entry at the very end of the file, below any trailing marker comment'
    }

    It 'warns, never fails, when a new entry lands just above a trailing marker' {
        $baseline = Join-Path $TestDrive 'marker-baseline.json'
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -EmitBaseline $baseline *> $null
        $raw = Get-Content -LiteralPath $script:ScribeHistory -Raw
        Set-Content -LiteralPath $script:ScribeHistory -Value $raw.Replace($script:Marker, (Format-OrchestrationEntryText -Title 'Entry above the marker') + $script:Marker) -NoNewline -Encoding utf8
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -Write *> $null

        $check = Invoke-BaselineCheck -BaselinePath $baseline
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $check.Output | Should -Match 'just above its trailing marker comment'
    }

    It 'still fails as history-integrity when a new entry lands above an older entry' {
        $baseline = Join-Path $TestDrive 'reorder-baseline.json'
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -EmitBaseline $baseline *> $null
        $raw = Get-Content -LiteralPath $script:ScribeHistory -Raw
        Set-Content -LiteralPath $script:ScribeHistory -Value $raw.Replace('# History: Squad Scribe', "# History: Squad Scribe`n`n" + (Format-OrchestrationEntryText -Title 'Entry above an older entry').TrimEnd()) -NoNewline -Encoding utf8

        $check = Invoke-BaselineCheck -BaselinePath $baseline
        $check.ExitCode | Should -Not -Be 0
        $check.Output | Should -Match 'inserted inside the file, not appended'
        $check.Output | Should -Match 'failure class: history-integrity'
    }
}
# Observed on the ace73d0 build (test-hve-squad-local, run run-20261007-1404): the
# intake Scribe wrote its orchestration block through a PowerShell double-quoted
# here-string, which collapsed the ```json fence to `json. The next pipelined
# Scribe hand-off re-typed that earlier entry with a correct fence, the baseline
# prefix hash changed, -Check reported history-integrity, and pipelining latched
# off after the plan stage although no content was lost.
Describe 'GATE-44 A collapsed fence is read, and repairing one never latches pipelining off' {
    BeforeAll {
        $script:Root = Join-Path $TestDrive 'fence/.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Split-Path $script:Root) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'fixtures', 'scribe-benchmark', 'applied') -Destination $script:Root -Recurse
        $script:ScribeHistory = Join-Path $script:Root 'history/Squad Scribe.md'
        $script:Healthy = (Get-Content -LiteralPath $script:ScribeHistory -Raw) -replace '\r\n', "`n"
        $script:Collapsed = $script:Healthy.Replace("``````json", '`json').Replace("}`n``````", "}`n``")

        function Write-ScribeHistory {
            param([Parameter(Mandatory)][string]$Text)
            [System.IO.File]::WriteAllText($script:ScribeHistory, $Text)
        }

        function Invoke-LedgerCheck {
            param([string]$BaselinePath)
            $arguments = @('-NoProfile', '-File', $script:LedgerScript, '-SquadRoot', $script:Root, '-Check')
            if ($BaselinePath) { $arguments += @('-BaselinePath', $BaselinePath) }
            $output = & pwsh @arguments 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
        }
    }

    It 'the Scribe and coordinator are told never to repair or restate a collapsed fence' {
        $script:ScribeProcedure | Should -Match 'never edit, re-type, reorder, or remove a prior entry, not even to fix its fence'
        $script:OperatingProcedure | Should -Match 'never ask the Scribe to repair, re-type, or restate it'
    }

    It 'counts a collapsed-fence block and only warns' {
        Write-ScribeHistory -Text $script:Collapsed
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -Write *> $null
        $check = Invoke-LedgerCheck
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $check.Output | Should -Match 'collapsed code fence'
        (Get-Content -LiteralPath (Join-Path $script:Root 'consumption.md') -Raw) | Should -Match 'Squad Scribe\.md — 1 block\(s\)'
    }

    It 'warns, never fails, when a later hand-off restores the fence and appends' {
        Write-ScribeHistory -Text $script:Collapsed
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -Write *> $null
        $baseline = Join-Path $TestDrive 'fence-baseline.json'
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -EmitBaseline $baseline *> $null

        $appended = $script:Healthy.TrimEnd() + "`n`n" + (Format-OrchestrationEntry -Title 'Later hand-off' -Turn 3).TrimStart()
        Write-ScribeHistory -Text $appended
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -Write *> $null

        $check = Invoke-LedgerCheck -BaselinePath $baseline
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $check.Output | Should -Match 'collapsed code fence in an earlier entry restored'
    }

    It 'still fails as history-integrity when an earlier entry''s content is rewritten' {
        Write-ScribeHistory -Text $script:Healthy
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -Write *> $null
        $baseline = Join-Path $TestDrive 'rewrite-baseline.json'
        & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $script:Root -EmitBaseline $baseline *> $null

        Write-ScribeHistory -Text ($script:Healthy -replace '"output_tokens": 3200', '"output_tokens": 1')
        $check = Invoke-LedgerCheck -BaselinePath $baseline
        $check.ExitCode | Should -Not -Be 0
        $check.Output | Should -Match 'failure class: history-integrity'
    }
}