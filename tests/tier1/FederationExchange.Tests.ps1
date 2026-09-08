#!/usr/bin/env pwsh
#Requires -Version 7.4
#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester consumes SourceRoot and PluginRoot in discovery and run blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester It and AfterAll blocks consume variables established in BeforeAll and BeforeEach; static analysis cannot follow those runtime scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Private fixture helpers generate contained synthetic state during an explicitly invoked test run.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', 'Write-ExchangeFixtureBytes', Justification = 'Writes one byte array in the synthetic fixture harness.')]
[CmdletBinding()]
param(
    [string]$SourceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')),
    [string]$PluginRoot = ''
)

BeforeDiscovery {
    Import-Module (Join-Path $SourceRoot 'squad-src/.github/skills/squad/scripts/Test-SquadRepoExchange.psm1') -Force
}

BeforeAll {
    Import-Module (Join-Path $SourceRoot 'squad-src/.github/skills/squad/scripts/Test-SquadRepoExchange.psm1') -Force
}

Describe 'Target exchange entrypoint wiring' -Tag 'Unit', 'Wiring' {
    BeforeAll {
        $Prompt = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/prompts/squad/squad.prompt.md') -Raw
        $AgentText = [IO.File]::ReadAllText((Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-coordinator.agent.md'))
        $Coordinator = [regex]::Replace($AgentText, '\A---\r?\n.*?\r?\n---\r?\n', '', [Text.RegularExpressions.RegexOptions]::Singleline)
        $Gate = [regex]::Match($Coordinator, '(?s)### Step 0: Target Handoff Gate\r?\n(?<Body>.*?)### Step 1: Read or Initialize State').Groups['Body'].Value
    }

    It 'Forwards the explicit target <Argument> input' -ForEach @(
        @{ Argument = 'handoff' }, @{ Argument = 'exchange' }, @{ Argument = 'squadRoot' }
    ) {
        $Prompt | Should -Match ([regex]::Escape('${input:' + $Argument + '}'))
        ($Prompt -split '## Requirements', 2)[1] | Should -Match ([regex]::Escape('${input:' + $Argument + '}'))
    }

    It 'Loads the protocol as an explicit conditional allowlist exception' {
        $Coordinator | Should -Match 'When `handoff` or `exchange` is supplied, also read `references/repo-exchange.md` before Init'
        $Coordinator | Should -Match 'scripts/Test-SquadRepoExchange.psm1'
        $Prompt | Should -Match 'references/repo-exchange.md.*before Init, federation deferral, ledger backfill or dispatch'
    }

    It 'Validates before initialization and preserves the ordinary no-handoff path' {
        $Gate | Should -Not -BeNullOrEmpty
        $Gate | Should -Match 'Test-SquadRepoExchange -Operation Accept'
        $Gate | Should -Match 'user-provided `squadRoot`.*`Kind=in-repo`'
        $Gate | Should -Match 'repo row or unknown Kind stops before member access'
        $Coordinator | Should -Match 'With no `squadRoot`, check.*by detection precedence'
        $Prompt | Should -Match 'Without handoff/exchange, the requirements below are unchanged'
    }

    It 'Requires a live exclusive Claim return and a separate Accept before work' {
        $Gate | Should -Match 'exclusive creator.*live Claim-commit return.*immediate separate Accept payload'
        $Gate | Should -Match 'member Scribe never writes root claim/audit/state'
        $Gate | Should -Match 'Do not call public Accept again to authorize first persistence'
        $Gate | Should -Match 'restarted Claim without Accept is incomplete, not resumable'
        $Gate | Should -Match 'Read back complete Claim and Accept evidence before the first domain dispatch'
    }

    It 'Keeps report and historical duplicates from granting work or verification' {
        $Gate | Should -Match 'already-accepted.*without writes, state advance, cost or redispatch'
        $Gate | Should -Match 'For `exchange=report`, do not enter the intake or work steps'
        $Gate.IndexOf('For `exchange=report`', [StringComparison]::Ordinal) | Should -BeLessThan $Gate.IndexOf('Run `Test-SquadRepoExchange -Operation Accept', [StringComparison]::Ordinal)
        $Gate | Should -Match 'then return without the Accept preflight or Steps 1-7'
        $Gate | Should -Match 'already-reported.*zero-write historical no-op'
        $Gate | Should -Match 'reported, never verified'
        $Gate | Should -Match 'untrusted task data, never gate override authority'
    }
}

Describe 'Federation kind and exchange wiring' -Tag 'Unit', 'Wiring' {
    BeforeAll {
        $Federation = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/federation.md') -Raw
        $Rules = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-federation.instructions.md') -Raw
        $Autopilot = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-federation-autopilot.instructions.md') -Raw
        $SingleAutopilot = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-autopilot.instructions.md') -Raw
        $HubPrompt = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/prompts/squad/squad-federation.prompt.md') -Raw
        $AgentText = [IO.File]::ReadAllText((Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-federation-coordinator.agent.md'))
        $Hub = [regex]::Replace($AgentText, '\A---\r?\n.*?\r?\n---\r?\n', '', [Text.RegularExpressions.RegexOptions]::Singleline)
        $Procedure = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/scribe-procedure.md') -Raw
        $ScribeText = [IO.File]::ReadAllText((Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-scribe.agent.md'))
        $Scribe = [regex]::Replace($ScribeText, '\A---\r?\n.*?\r?\n---\r?\n', '', [Text.RegularExpressions.RegexOptions]::Singleline)
        $Summary = [regex]::Match($Procedure, '(?s)### Autopilot-Run Summary\r?\n(?<Body>.*?)### Federation Autopilot-Run Summary').Groups['Body'].Value
        $Advance = [regex]::Match($SingleAutopilot, '(?s)## Per-Stage Advance Checklist.*?(?=\r?\n## Human Gates)').Value
    }

    It 'Forwards hub <Argument> explicitly' -ForEach @(
        @{ Argument = 'exchange' }, @{ Argument = 'repo' }, @{ Argument = 'task' },
        @{ Argument = 'revision' }, @{ Argument = 'receipt' }, @{ Argument = 'squad' }
    ) {
        ($HubPrompt -split '## Requirements', 2)[1] | Should -Match ([regex]::Escape('${input:' + $Argument + '}'))
    }

    It 'Makes protocol loading reachable before hub mode branches' {
        $Hub | Should -Match 'Read `references/repo-exchange.md` when `exchange` is supplied or a registry row has `Kind=repo`'
        $Hub | Should -Match '(?s)### Step 0: Explicit Exchange.*then return without Steps 1-7.*### Step 1:'
        $Federation | Should -Match '\[repo-exchange.md\]\(repo-exchange.md\)'
        $HubPrompt | Should -Match 'before any mode or member-tree branch, then return'
    }

    It 'Guards each direct dispatch and recovery branch before member resolution' {
        $Hub | Should -Match '(?s)### Step 3: Dispatch.*Recheck Kind.*before path resolution or recovery.*For each selected sub-squad'
        $Hub | Should -Match '(?s)## Watch Mode Bootstrap Mode.*Check Kind before explicit targeting, name reuse, profile inference, repair or resume.*When the turn carries'
        $Hub | Should -Match '(?s)## Federation Autopilot Mode.*Check Kind before single-target forwarding, fan-out and built-tree preconditions.*When the user passes'
        $Hub | Should -Match '(?s)### Step 7: Verify.*only to actual in-repo runs.*Before reporting any sub-squad'
    }

    It 'Preserves in-repo recovery while keeping repo consumers pending' {
        $Rules | Should -Match 'member reads and same-turn recovery apply only to `in-repo`'
        $Rules | Should -Match 'none of the recovery/assumption cases below overrides that boundary'
        $Rules | Should -Match 'One producer run per handoff per turn'
        $Federation | Should -Match 'no same-turn member recovery or assumption shortcut applies'
        $Autopilot | Should -Match 'no eligible inner runs is not success'
        $Autopilot | Should -Match 'Aggregate only actual `in-repo` inner runs'
    }

    It 'Binds all four explicit actions to Scribe and local evidence gates' {
        $Federation | Should -Match 'Register requires.*unique across all kinds.*unique across repo rows'
        $Federation | Should -Match 'No member Init or member history'
        $Federation | Should -Match 'calls `Issue` before final outbox creation'
        $Federation | Should -Match 'Validate closed receipt shape before deriving its outbox correlation'
        $Federation | Should -Match 'separate explicit current human attestation'
        $Federation | Should -Match 'No exchange fields are added to `state.json`'
        $Rules | Should -Not -Match 'repo.*reserved for the deferred'
    }

    It 'Retains claims during both promotion paths and stops relocated bindings' {
        foreach ($Text in @($Hub, $Rules, $Federation)) {
            $Text | Should -Match 'exchanges/claims/'
            $Text | Should -Match 'root-relocated'
        }
        $Federation | Should -Match 'including automatic Promotion'
        $Rules | Should -Match 'never same-ID reacceptance'
    }

    It 'Routes promotion audit ownership to the canonical retention exception' {
        foreach ($Text in @($Hub, $Rules)) {
            $Text | Should -Match 'Promotion Audit Ownership'
        }
        $Rules | Should -Match 'Retain the complete root `decisions.md`'
    }

    It 'Checks actual federation completion with activeSubSquads, not local activeRoles' -Tag 'Correction' {
        $Checklist = [regex]::Match($Hub, '(?s)### Step 7: Verify.*?(?=\r?\n## Federation Autopilot Mode)').Value
        $Checklist | Should -Match 'Apply this checklist only to actual in-repo runs'
        $Checklist | Should -Match 'its `updated` and `turn` moved and its `activeSubSquads` name the sub-squad\(s\) that ran'
        $Checklist | Should -Not -Match '\bactiveRoles\b'
        $LocalState = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/instructions/squad/squad-state.instructions.md') -Raw
        $LocalState | Should -Match '\bactiveRoles\b'
        $ScribeStep = [regex]::Match($Scribe, '(?m)^13\. [^\r\n]*').Value
        $ScribeStep | Should -Match 'use `activeSubSquads` for actual local members that ran at a federation root and `activeRoles` for dispatched roles at an ordinary or member root'
        $StateWriter = ($Procedure -split '### Advancing `state.json`', 2)[1]
        $LocalWrite = [regex]::Match($StateWriter, '(?m)^1\. [^\r\n]*').Value
        $LocalWrite | Should -Match 'At an ordinary or member root, set `activeRoles` to the roles dispatched this turn; a federation-root payload uses step 4 for activity instead'
        $RootWrite = [regex]::Match($StateWriter, '(?m)^4\. [^\r\n]*').Value
        $RootWrite | Should -Match 'Set `activeSubSquads` to the actual local `in-repo` sub-squad\(s\) that ran this turn'
        $RootWrite | Should -Not -Match '\bactiveRoles\b'
        $RootWrite | Should -Match 'a member payload never writes federation-root state'
        $StateWriter | Should -Match 'Never add both fields'
        $LocalAgent = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-coordinator.agent.md') -Raw
        $LocalCheck = [regex]::Match($LocalAgent, '(?s)### Step 7: Verify.*?(?=\r?\n## |\z)').Value
        $LocalCheck | Should -Match '`activeRoles` names the dispatched roles'
        $LocalCheck | Should -Not -Match '\bactiveSubSquads\b'
        $Templates = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/federation-templates.md') -Raw
        $RootJson = [regex]::Match($Templates, '(?s)### state\.json \(federation root\).*?```json\s*(?<Json>.*?)```').Groups['Json'].Value | ConvertFrom-Json -AsHashtable
        $RootJson.Keys | Should -Contain 'activeSubSquads'
        $RootJson.Keys | Should -Not -Contain 'activeRoles'
        $Validator = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/scripts/Test-SquadRepoExchange.psm1') -Raw
        $StateValidator = [regex]::Match($Validator, '(?s)function Assert-SquadCurrentState \{.*?(?=\r?\nfunction |\z)').Value
        $FieldSets = @([regex]::Matches($StateValidator, '\$Fields = ''([^'']+)'''))
        $FieldSets.Count | Should -Be 2
        ($FieldSets[0].Groups[1].Value -split ' ') | Should -Contain 'activeSubSquads'
        ($FieldSets[0].Groups[1].Value -split ' ') | Should -Not -Contain 'activeRoles'
        ($FieldSets[1].Groups[1].Value -split ' ') | Should -Contain 'activeRoles'
        ($FieldSets[1].Groups[1].Value -split ' ') | Should -Not -Contain 'activeSubSquads'
    }

    It 'Keeps exchange-only Scribe bookkeeping out of role and member activity' -Tag 'Correction' {
        $StateWriter = ($Procedure -split '### Advancing `state.json`', 2)[1]
        $StateWriter | Should -Match 'Exchange-only bookkeeping creates no role or member activity'
        $StateWriter | Should -Match 'A historical no-op writes nothing'
        $Scribe | Should -Match 'No-op exchanges write nothing and do not advance state'
        $Scribe | Should -Match 'never estimated remote work or invented active sub-squads'
    }

    It 'Conditions pre-implementation Council evidence without weakening triggered or validator gates' -Tag 'Correction' {
        $CouncilStage = [regex]::Match($SingleAutopilot, '(?m)^3\. \*\*Pre-implementation council\.\*\*[^\r\n]*').Value
        $CouncilStage | Should -Match 'When the work crosses two or more council-member domains \(architecture, security, cost, product-fit, RAI\)'
        $CouncilStage | Should -Match 'before any implementation dispatch'
        $CouncilStage | Should -Match 'A `Stop` verdict fires a Human Gate'
        $CouncilStage | Should -Match 'A `Go` or `Go-With-Conditions` verdict permits the implementation stage with the conditions attached as inputs'
        $CouncilStage | Should -Match 'When this trigger does not apply, record the stage as not applicable through the Scribe without creating a Council Verdict'
        $CouncilRow = [regex]::Match($SingleAutopilot, '(?m)^\| council\s+\|[^\r\n]*').Value
        $CouncilRow | Should -Match 'a `## Council Verdict` in `decisions.md`.*a plan artifact exists and stage 3 applies'
        $ImplementRow = [regex]::Match($SingleAutopilot, '(?m)^\| implement\s+\|[^\r\n]*').Value
        $ImplementRow | Should -Match 'a plan artifact exists; when stage 3 applies, a recorded non-`Stop` Council Verdict with its conditions also exists'
        $SingleAutopilot | Should -Match 'council re-validation, max two cycles, divergence detection'
        $SingleAutopilot | Should -Match 'Any action the implementer cannot self-validate.*fires a Human Gate rather than proceeding'
        $SingleAutopilot | Should -Match 'Any `Stop` verdict from the council or any individual council role'
        $SingleAutopilot | Should -Match 'Any `Risk: High` finding from `security`, `cost-manager`, or `rai`'
        $SingleAutopilot | Should -Match 'Any compliance violation flagged by `rai` or `security`'
        $CouncilStage | Should -Match 'When triggered, a missing recorded verdict blocks implementation'
        $SingleAutopilot | Should -Match 'Divergence: two consecutive validator cycles producing different verdicts'
        $SingleAutopilot | Should -Match 'Before performing any impactful or irreversible action, autopilot stops and requires explicit human approval for that specific action'
        $SingleAutopilot | Should -Match 'The coordinator waits for human validation'
    }

    It 'Aligns the always-loaded Council reference with canonical pre-implementation applicability' -Tag 'Correction' {
        $GateReference = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/gates-and-modes.md') -Raw
        $ArtifactGates = [regex]::Match($GateReference, '(?s)### Artifact Gates \(Evidence Required\).*?(?=\r?\n### Per-Stage Advance Checklist)').Value
        $CouncilRow = [regex]::Match($ArtifactGates, '(?m)^5\. \*\*council\*\*[^\r\n]*').Value
        $CouncilRow | Should -Match 'a `## Council Verdict` in `decisions.md`.*a plan artifact exists and pre-implementation stage 3 applies'
        $ImplementRow = [regex]::Match($ArtifactGates, '(?m)^6\. \*\*implement\*\*[^\r\n]*').Value
        $ImplementRow | Should -Match 'a plan artifact exists; when pre-implementation stage 3 applies, its own recorded `Go` or `Go-With-Conditions` Council Verdict and conditions also exist before implementation'
        $ArtifactGates | Should -Match '\*Pipeline Contract\* stage 3 and \*Per-Stage Advance Checklist\* in `squad-autopilot.instructions.md`'
        $ArtifactGates | Should -Match '\[Autopilot-Run Summary\]\(scribe-procedure.md#autopilot-run-summary\).*pre-implementation Council rows and the checklist below'
        $ArtifactGates | Should -Match 'Only a Scribe-recorded trigger assessment and reason in this run''s `decisions.md` entry permits the non-applicable no-dispatch exception'
        $ArtifactGates | Should -Match 'confirm that evidence before advancing, without creating a Council Verdict or counting an executed stage'
        $ArtifactGates | Should -Match 'Missing or unjustified applicability evidence blocks the exception'
        $ArtifactGates | Should -Match 'When applicable, a missing verdict blocks implementation and `Stop` fires the Human Gate'
        $ArtifactGates | Should -Match 'implementation validator-loop Council is unchanged and cannot supply the pre-implementation prerequisite verdict'
        $GateReference | Should -Match 'implement \(via the autonomous validator loop\)'
    }

    It 'Records only documented non-applicable Council as no-dispatch summary evidence' -Tag 'Correction' {
        $CouncilStage = [regex]::Match($SingleAutopilot, '(?m)^3\. \*\*Pre-implementation council\.\*\*[^\r\n]*').Value
        $CouncilStage | Should -Match 'trigger assessment and reason in this run''s ordinary decision entry in `decisions.md`'
        $CouncilStage | Should -Match 'not a domain dispatch or domain-consumption record'
        $Summary | Should -Match 'pre-implementation `council` row only, read this run''s Scribe-recorded applicability decision'
        $Summary | Should -Match 'existing stage-3 trigger does not apply and gives the reason'
        $Summary | Should -Match '`Role\(s\)` as `none`, `Result` as `skipped \(not applicable: <reason>\)`'
        $Summary | Should -Match '`Dispatch Record` as `not applicable \(no dispatch\): <decision ref>`'
        $Summary | Should -Match 'not a Council Verdict, domain dispatch or domain-consumption proof'
        $Summary | Should -Match 'specializes the template''s missing-dispatch rule without changing its columns or verdict schema'
        $Summary | Should -Match 'Exclude only the documented non-applicable pre-implementation Council row from required-dispatch failure and executed-stage counts'
        $Summary | Should -Match 'non-applicable row alone does not force an incomplete summary'
        $Advance | Should -Match 'confirm the Scribe-recorded trigger assessment and reason'
        $Advance | Should -Match 'Do not count the documented no-dispatch row as an executed stage'
        $Advance | Should -Match 'Only the documented non-applicable pre-implementation Council row uses `not applicable \(no dispatch\): <decision ref>`'
        ($SingleAutopilot -split '## History Entries', 2)[1] | Should -Match 'A skipped row is not a verdict or a claimed execution; applicable stages retain their own dispatch evidence'
    }

    It 'Keeps applicable or claimed stages incomplete when their own evidence is missing' -Tag 'Correction' {
        $Summary | Should -Match 'Missing or unjustified applicability evidence does not qualify for the exception; neither does a required or claimed execution'
        $Summary | Should -Match 'every `history/<agent>.md` file with this run''s entry for that stage and its consumption block, and check its required artifact'
        $Summary | Should -Match 'An existing file from another run or stage is not evidence'
        $Summary | Should -Match 'Missing artifacts or consumption blocks also remain blockers'
        $Summary | Should -Match 'When any other row reads `[^`]*none recorded`, the outcome is `incomplete \(<n> stage\(s\) without a dispatch record\)`, never `completed`'
        $Summary | Should -Match 'cannot clear another stage''s missing evidence, an escalation or a stop'
        $Advance | Should -Match 'Missing or unjustified applicability evidence blocks this exception'
        $Advance | Should -Match 'For every required or claimed executed stage.*required artifact.*this run''s `history/<agent>.md` entry for that stage with its consumption block'
        $Advance | Should -Match 'When either is absent, re-dispatch the owning role or fire the Risk Gate'
        $Advance | Should -Match 'may not report a run as completed over an `incomplete` summary'
    }

    It 'Keeps implementation-loop Council separate from the pre-implementation prerequisite' -Tag 'Correction' {
        $Summary | Should -Match 'Keep implementation validator-loop Council entries attributed to their own stage and cycle'
        $Summary | Should -Match 'cannot fill the pre-implementation `council` row or supply its prerequisite verdict'
        $Summary | Should -Match 'When stage 3 applies, require its own recorded `Go` or `Go-With-Conditions` verdict and conditions before implementation'
        $Summary | Should -Match 'missing verdict blocks advancement, and `Stop` fires the Human Gate'
        $Summary | Should -Match 'Completion still awaits final human validation'
        $Advance | Should -Match 'An implementation validator-loop verdict cannot substitute for pre-implementation evidence'
        $Scribe | Should -Match 'The label is exactly `Go`, `Go-With-Conditions`, or `Stop`'
    }

    It 'Records promotion consumption at the canonical Squad Scribe history destination' -Tag 'Correction' {
        $Promotion = [regex]::Match($Rules, '(?m)^7\. \*\*Carry the consumption ledger across the boundary\.\*\*[^\r\n]*').Value
        $Promotion | Should -Match 'the Scribe writes.*`members/<name>/history/Squad Scribe\.md`'
        $Promotion | Should -Not -Match 'history/scribe\.md'
        $Promotion | Should -Match 'rewrites `members/<name>/consumption.md` from the relocated history'
        $Promotion | Should -Match 'currentRun` cost totals from that ledger'
        $Rules | Should -Match 'Append-only history and consumption blocks move intact, never edited or truncated'
        $ScribePromotion = [regex]::Match($Procedure, '(?s)### Federation Promotion.*?(?=\r?\n### Federation Expansion)').Value
        $ScribePromotion | Should -Match 'scoped to `members/<name>/`: append the promotion''s `orchestration` block to that root''s `history/Squad Scribe.md`'
        $ScribePromotion | Should -Match 'rewrite its `consumption.md` from every block in the relocated `history/`'
        $ScribePromotion | Should -Match 'seed the federation `state.json` totals from that ledger''s total row'
        $ScribePromotion | Should -Match 'history/` are not rewritten'
        $Accounting = [regex]::Match($Procedure, '(?s)### Consumption Accounting.*?(?=\r?\n### Federation Promotion)').Value
        $Accounting | Should -Match 'Append it as a `#### Consumption [^`]*Orchestration` block to `history/Squad Scribe.md`'
        $Contract = Get-Content -LiteralPath (Join-Path $SourceRoot 'tests/squad-behavior-contract.md') -Raw
        $Fd20 = [regex]::Match($Contract, '(?m)^\| FD-20 \|[^\r\n]*').Value
        $Fd20 | Should -Match '`members/<name>/history/Squad Scribe.md` carries the promotion''s orchestration consumption block'
        $Fd20 | Should -Match 'federation `state.json` `currentRun` totals are seeded from the relocated ledger total row'
        foreach ($Text in @($Promotion, $ScribePromotion, $Accounting, $Fd20)) {
            $Text | Should -Not -Match 'history/scribe\.md'
        }
    }
}

Describe 'Scribe exchange persistence wiring' -Tag 'Unit', 'Wiring' {
    BeforeAll {
        $Procedure = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/scribe-procedure.md') -Raw
        $AgentText = [IO.File]::ReadAllText((Join-Path $SourceRoot 'squad-src/.github/agents/squad/squad-scribe.agent.md'))
        $Scribe = [regex]::Replace($AgentText, '\A---\r?\n.*?\r?\n---\r?\n', '', [Text.RegularExpressions.RegexOptions]::Singleline)
    }

    It 'Loads protocol and validator only for the bounded exchange procedure' {
        $Scribe | Should -Match 'references/repo-exchange.md.*exchange operation'
        $Scribe | Should -Match 'scripts/Test-SquadRepoExchange.psm1'
        $Procedure | Should -Match '\[repo-exchange.md\]\(repo-exchange.md\)'
        $Procedure | Should -Match 'exchange operation.*Exchange Persistence'
        $Scribe | Should -Match 'instead of the ordinary append/Init/expansion steps'
    }

    It 'Limits each of the seven operation writes to a defined payload' -ForEach @(
        @{ Operation = 'Register' }, @{ Operation = 'Issue' }, @{ Operation = 'Claim' },
        @{ Operation = 'Accept' }, @{ Operation = 'Report' }, @{ Operation = 'Import' }, @{ Operation = 'Verify' }
    ) {
        $Procedure | Should -Match ('(?m)^\| ' + $Operation + ' \|')
    }

    It 'Separates the exclusive root Claim from the immediate member Accept' {
        $Procedure | Should -Match 'Only a separate RepositoryRoot payload'
        $Procedure | Should -Match 'Repeat public `Accept` preflight before claim creation'
        $Procedure | Should -Match 'A losing creator writes no exchange artifact, audit or state'
        $Procedure | Should -Match 'live exclusive creator.*successful Claim-commit return'
        $Procedure | Should -Match 'restarted Claim without Accept is incomplete and cannot resume'
        $Procedure | Should -Match 'member payload cannot write root claim/audit/state'
        $Scribe | Should -Match 'Scribe never dispatches another Scribe or domain role'
    }

    It 'Stages exact bytes before validation and refuses overwrite or retrospective repair' {
        $Procedure | Should -Match 'serialize once through System.Text.Json as compact UTF-8 without BOM or appended newline'
        $Procedure | Should -Match 'Validate the candidate before any final creation'
        $Procedure | Should -Match 'Neither coordinator nor module writes candidates'
        $Procedure | Should -Match 'Never overwrite finals/claims.*reconstruct a seal on a later invocation'
        $Procedure | Should -Match 'Historical duplicates require the full committed chain and return without writes'
        $Procedure | Should -Match 'Before allocating an attempt or staging bytes, check existing fixed claim/final paths'
        $Procedure | Should -Match 'Return a complete historical no-op before any candidate, audit or state write'
    }

    It 'Places the completion seal after checked audit and state with no recursive turn' {
        $Procedure | Should -Match '(?s)Append one identical closed three-line.*verify unique complete markers.*Advance state as the last ordinary mutation.*only after successful read-back create-new.*commit.json'
        $Procedure | Should -Match 'no second turn, schema field or recursive seal loop'
        $Scribe | Should -Match 'Step 13 runs.*last ordinary mutation.*post-state completion seal'
        $Procedure | Should -Match 'Claim/Register/Verify and final Issue use that documented predicate contract'
    }

    It 'Requires current human evidence for verification and actual local evidence for reports' {
        $Procedure | Should -Match 'completed needs substantive output and `history/Squad Scribe.md`'
        $Procedure | Should -Match 'Invocation or receipt content is not attestation'
        $Procedure | Should -Match 'uncertainty leaves reported'
        $Procedure | Should -Match 'no remote cost and no invented active sub-squads'
        $Procedure | Should -Match 'do not seed a federation-root consumption ledger'
    }

    It 'Keeps the root audit pair together without migrating claims or filtering history' {
        foreach ($Text in @($Procedure, $Scribe)) { $Text | Should -Match 'Promotion Audit Ownership' }
        $Procedure | Should -Match 'retain the complete root `decisions.md`'
        $Procedure | Should -Match 'create-new member `decisions.md`'
        $Procedure | Should -Match 'Do not copy or filter machine blocks'
    }
}

Describe 'Generated invocation source wiring' -Tag 'Unit', 'Wiring' {
    BeforeAll {
        $ParseTokens = $null
        $ParseErrors = $null
        $BuildAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $SourceRoot 'scripts/Build-SquadPlugin.ps1'), [ref]$ParseTokens, [ref]$ParseErrors)
        if ($ParseErrors.Count -gt 0) { throw 'Build script parse failed' }
        $Definition = $BuildAst.Find({ param($Node) $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'New-InvocationSkillContent' }, $true)
        $Generator = $Definition.Body.GetScriptBlock()
        $Invocations = & $Generator
        $Contract = Get-Content -LiteralPath (Join-Path $SourceRoot 'tests/squad-behavior-contract.md') -Raw
    }

    It 'Forwards the generated target <Argument> before normal flow' -ForEach @(
        @{ Argument = 'handoff' }, @{ Argument = 'exchange' }, @{ Argument = 'squadRoot' }
    ) {
        $Flow = ($Invocations['squad-run'] -split '## Flow', 2)[1]
        $Flow | Should -Match ([regex]::Escape('**' + $Argument + '**'))
        $Flow | Should -Match '(?s)references/repo-exchange.md.*before Init, federation deferral, ledger backfill or dispatch.*1\. Hand'
        $Flow | Should -Match 'user-provided'
    }

    It 'Forwards the generated hub <Argument> before ordinary routing' -ForEach @(
        @{ Argument = 'exchange' }, @{ Argument = 'repo' }, @{ Argument = 'task' },
        @{ Argument = 'revision' }, @{ Argument = 'receipt' }, @{ Argument = 'squad' }
    ) {
        $Flow = ($Invocations['squad-federation'] -split '## Flow', 2)[1]
        $Flow | Should -Match ([regex]::Escape('**' + $Argument + '**'))
        $Flow | Should -Match '(?s)references/repo-exchange.md.*before any mode or member-tree branch, then return.*1\. Hand'
    }

    It 'Preserves in-repo behavior without treating reports as verified or empty dispatch as success' {
        $Invocations['squad-run'] | Should -Match 'Without handoff/exchange, the flow below is unchanged'
        $Invocations['squad-federation'] | Should -Match 'Only `in-repo` follows the flow below'
        $Invocations['squad-federation'] | Should -Match 'Import is reported; Verify requires a separate current human attestation'
        $Invocations['squad-federation'] | Should -Match 'Empty eligibility is not success'
        $Contract | Should -Match '(?m)^\| FD-04 \|.*Kind=in-repo.*Kind=repo.*unknown kinds reject'
        $Contract | Should -Not -Match 'every `Kind` is `in-repo`'
    }
}

Describe 'Exchange audit namespace regression' -Tag 'Unit', 'Wiring', 'AuditNamespace' {
    BeforeAll {
        Import-Module (Join-Path $SourceRoot 'tests/tier1/SquadState.psm1') -Force
        $NamespaceBase = Join-Path $SourceRoot ('.copilot-tracking/sandbox/2026-09-08/cross-repo-federation/audit-' + [guid]::NewGuid().ToString('D'))
        $TemplateText = Get-Content -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/references/federation-templates.md') -Raw
        $TemplateSection = $TemplateText.Substring($TemplateText.IndexOf('## Advisory Exchange Examples', [StringComparison]::Ordinal))
        $NamespaceExamples = @{}
        foreach ($Block in [regex]::Matches($TemplateSection, '(?ms)^```json\r?\n(.*?)\r?\n```')) {
            $Value = $Block.Groups[1].Value | ConvertFrom-Json -AsHashtable
            if ($Value.ContainsKey('kind')) { $NamespaceExamples[$Value.kind] = $Block.Groups[1].Value }
        }
        $DispatchBlock = @'
## Local dispatch
* Deliverable: outputs/local-result.md
#### Consumption
```json
{"model":"unknown","model_source":"unresolved","priced_as":"tier-default","model_tier":"fast","internal_turns":1,"input_tokens":100,"cached_tokens":0,"cache_write_tokens":0,"output_tokens":10,"basis":"tier-default"}
```
'@
        function Write-AuditNamespaceFile {
            param([string]$Path, [string]$Content)
            $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
            $Stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $Stream.Write([Text.Encoding]::UTF8.GetBytes($Content)); $Stream.Flush($true) }
            finally { $Stream.Dispose() }
        }
    }

    BeforeEach {
        $NamespaceRoot = Join-Path $NamespaceBase ([guid]::NewGuid().ToString('D'))
        $FlatHistory = Join-Path $NamespaceRoot 'history/repo-exchange.md'
        $NestedAudit = Join-Path $NamespaceRoot 'history/repo-exchange/audit.md'
        $MemberRoot = Join-Path $NamespaceRoot 'members/repo-exchange'
        Write-AuditNamespaceFile -Path $FlatHistory -Content "# Local member history`n"
        Write-AuditNamespaceFile -Path (Join-Path $MemberRoot 'history/Local Worker.md') -Content "# Local Worker`n$DispatchBlock`n"
        Write-AuditNamespaceFile -Path (Join-Path $MemberRoot 'team.md') -Content "# Local roster`n"
        $Registry = "# Federation`n`n| Sub-squad | Profile | Kind | Location | Owner | Description |`n| --- | --- | --- | --- | --- | --- |`n| repo-exchange | default | in-repo | members/repo-exchange/ | team | Local member |`n"
        Write-AuditNamespaceFile -Path (Join-Path $NamespaceRoot 'federation.md') -Content $Registry
    }

    It 'Preserves flat history and the member tree through Register, Issue and Import namespace writes' {
        $FlatHash = (Get-FileHash -LiteralPath $FlatHistory -Algorithm SHA256).Hash
        $MemberBefore = @(Get-ChildItem -LiteralPath $MemberRoot -File -Recurse | Sort-Object FullName | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash }) -join "`n"
        foreach ($Operation in @('Register', 'Issue', 'Import')) {
            if ($Operation -eq 'Register') {
                [IO.File]::AppendAllText((Join-Path $NamespaceRoot 'federation.md'), "| service | advisory | repo | https://github.com/contoso/service | service-team | Advisory service |`n")
            }
            elseif ($Operation -eq 'Issue') {
                Write-AuditNamespaceFile -Path (Join-Path $NamespaceRoot 'exchanges/outbox/11111111-1111-4111-8111-111111111111/packet.json') -Content $NamespaceExamples['squad-repo-task']
            }
            else {
                Write-AuditNamespaceFile -Path (Join-Path $NamespaceRoot 'exchanges/outbox/11111111-1111-4111-8111-111111111111/receipt.json') -Content $NamespaceExamples['squad-repo-receipt']
            }
            $Audit = $NamespaceExamples['squad-repo-audit'] | ConvertFrom-Json -AsHashtable
            $Audit.operation = $Operation
            $Audit.attemptId = [guid]::NewGuid().ToString('D')
            $Audit.registryAlias = 'service'
            $Audit.disposition = if ($Operation -eq 'Import') { 'reported' } else { 'pending' }
            if ($Operation -eq 'Register') {
                foreach ($Key in @('correlationId', 'taskId', 'packetSha256', 'receiptSha256', 'sourceRevision', 'targetRevision', 'resultRevision')) { $Audit[$Key] = '' }
                $Audit.artifacts = @()
            }
            $JsonLine = $Audit | ConvertTo-Json -Depth 10 -Compress
            $AuditBlock = "<!-- squad-repo-audit:$($Audit.attemptId):begin -->`n$JsonLine`n<!-- squad-repo-audit:$($Audit.attemptId):end -->`n"
            $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($NestedAudit))
            [IO.File]::AppendAllText($NestedAudit, $AuditBlock)
            [IO.File]::AppendAllText((Join-Path $NamespaceRoot 'decisions.md'), $AuditBlock)
            (Get-FileHash -LiteralPath $FlatHistory -Algorithm SHA256).Hash | Should -BeExactly $FlatHash
            $MemberAfter = @(Get-ChildItem -LiteralPath $MemberRoot -File -Recurse | Sort-Object FullName | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash }) -join "`n"
            $MemberAfter | Should -BeExactly $MemberBefore
            Test-Path -LiteralPath (Join-Path $NamespaceRoot 'members/service') | Should -BeFalse
            $Model = Get-SquadStateModel -SquadRoot $NamespaceRoot
            $Model.HistoryNames | Should -Contain 'repo-exchange'
            $Model.HistoryNames | Should -Not -Contain 'audit'
            $Model.Blocks | Should -HaveCount 0
        }
        @(Get-HistoryEntry -Path $NestedAudit) | Should -HaveCount 0
        @(Get-ConsumptionBlock -Path $NestedAudit) | Should -HaveCount 0
        $AuditHash = (Get-FileHash -LiteralPath $NestedAudit).Hash
        [IO.File]::AppendAllText($FlatHistory, "`n## Later local turn`n* Reference: members/repo-exchange/decisions.md`n")
        @(Get-HistoryEntry -Path $FlatHistory) | Should -HaveCount 1
        (Get-SquadStateModel -SquadRoot $MemberRoot).DispatchBlocks | Should -HaveCount 1
        (Get-FileHash -LiteralPath $NestedAudit).Hash | Should -BeExactly $AuditHash
        $Rows = @((Get-MarkdownTable -Content ([IO.File]::ReadAllText((Join-Path $NamespaceRoot 'federation.md')))).Rows)
        @($Rows | Where-Object { $_.Kind -eq 'in-repo' }).'Sub-squad' | Should -BeExactly 'repo-exchange'
        @($Rows | Where-Object { $_.Kind -eq 'repo' }).Location | Should -BeExactly 'https://github.com/contoso/service'
    }

    It 'Excludes nested dispatch-shaped text from the actual state model without reserving the flat name' {
        Write-AuditNamespaceFile -Path $NestedAudit -Content "# Nested audit fixture`n$DispatchBlock`n"
        @(Get-ConsumptionBlock -Path $NestedAudit) | Should -HaveCount 1
        $Model = Get-SquadStateModel -SquadRoot $NamespaceRoot
        $Model.HistoryNames | Should -BeExactly 'repo-exchange'
        $Model.Blocks | Should -HaveCount 0
        $Model.Deliverables | Should -HaveCount 0
        $MemberAudit = Join-Path $MemberRoot 'history/repo-exchange/audit.md'
        Write-AuditNamespaceFile -Path $MemberAudit -Content "# Nested member audit fixture`n$DispatchBlock`n"
        $MemberModel = Get-SquadStateModel -SquadRoot $MemberRoot
        $MemberModel.HistoryNames | Should -BeExactly 'Local Worker'
        $MemberModel.DispatchBlocks | Should -HaveCount 1
        $MemberModel.Deliverables | Should -HaveCount 1
    }

    It 'Keeps production Scribe and federation parsing instructions in the nested namespace' -ForEach @(
        @{ Relative = 'squad-src/.github/skills/squad/references/scribe-procedure.md' },
        @{ Relative = 'squad-src/.github/skills/squad/references/federation.md' },
        @{ Relative = 'squad-src/.github/instructions/squad/squad-federation.instructions.md' },
        @{ Relative = 'squad-src/.github/instructions/squad/squad-federation-autopilot.instructions.md' }
    ) {
        $Text = Get-Content -LiteralPath (Join-Path $SourceRoot $Relative) -Raw
        $Text | Should -Match 'history/repo-exchange/audit.md'
        $Text | Should -Match 'history/repo-exchange.md'
        $Text | Should -Match 'recursive enumeration|recursive history enumeration'
        $Text | Should -Match 'excluded|Exclude|not dispatch or consumption'
    }

    AfterAll {
        if (Test-Path -LiteralPath $NamespaceBase) { Remove-Item -LiteralPath $NamespaceBase -Recurse -Force }
        Remove-Module SquadState -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Exchange input boundaries' -Tag 'Unit', 'Protocol' {
    InModuleScope Test-SquadRepoExchange {
        It 'Preserves strings, numbers, booleans and arrays without timestamp coercion' {
            $Value = ConvertFrom-SquadJsonBytes ([Text.Encoding]::UTF8.GetBytes('{"time":"2026-09-08T12:00:00Z","count":1,"items":[],"enabled":false}'))
            $Value['time'] | Should -BeOfType ([string])
            $Value['count'] | Should -BeOfType ([long])
            ($Value['items'] -is [object[]]) | Should -BeTrue
            $Value['enabled'] | Should -BeFalse
        }

        It 'Rejects invalid JSON <Json>' -ForEach @(
            @{ Json = '{' }, @{ Json = '[]' }, @{ Json = 'null' },
            @{ Json = '{"id":1,"id":2}' }, @{ Json = '{"id":1,"ID":2}' },
            @{ Json = '{"child":{"id":1,"id":2}}' }, @{ Json = '{"items":[{"id":1,"ID":2}]}' },
            @{ Json = '{"items":[[[[[[[[]]]]]]]]}' }, @{ Json = '{"id":1,}' }
        ) {
            { ConvertFrom-SquadJsonBytes ([Text.Encoding]::UTF8.GetBytes($Json)) } | Should -Throw
        }

        It 'Rejects oversized bytes before parsing' {
            { ConvertFrom-SquadJsonBytes ([byte[]]::new(131073)) } | Should -Throw '*document-size*'
        }

        It 'Rejects unsafe relative path <Path>' -ForEach @(
            @{ Path = '/absolute.json' }, @{ Path = '//server/share.json' },
            @{ Path = 'C:/outside.json' }, @{ Path = 'Env:PATH' }, @{ Path = 'one\two.json' },
            @{ Path = '../other/file.json' }, @{ Path = 'one/../file.json' },
            @{ Path = 'one//file.json' }, @{ Path = './file.json' }, @{ Path = 'one/NUL.json' }
        ) {
            { Assert-SquadRelativePath $Path } | Should -Throw '*unsafe-path*'
        }

        It 'Hashes bytes rather than normalized objects' {
            $Compact = Get-SquadByteHash ([Text.Encoding]::UTF8.GetBytes('{"id":1}'))
            $Spaced = Get-SquadByteHash ([Text.Encoding]::UTF8.GetBytes('{ "id": 1 }'))
            $Compact | Should -Not -Be $Spaced
        }
    }
}

Describe 'Exchange committed lifecycle' -Tag 'Unit', 'Protocol' {
    InModuleScope Test-SquadRepoExchange {
        BeforeAll {
            $script:Scratch = [IO.Path]::GetFullPath('.copilot-tracking/sandbox/2026-09-08/cross-repo-federation/protocol-' + [guid]::NewGuid().ToString('D'), (Get-Location).ProviderPath)
            $null = [IO.Directory]::CreateDirectory($script:Scratch)

            function Write-ExchangeFixtureBytes {
                param([string]$Path, [byte[]]$Bytes, [switch]$Replace)
                $Full = [IO.Path]::Combine($script:Fixture.TopLevel, $Path)
                $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Full))
                $Mode = if ($Replace) { [IO.FileMode]::Create } else { [IO.FileMode]::CreateNew }
                $Stream = [IO.File]::Open($Full, $Mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $Stream.Write($Bytes); $Stream.Flush($true) }
                finally { $Stream.Dispose() }
                [pscustomobject]@{ Path = $Path; Hash = Get-SquadByteHash $Bytes }
            }

            function Write-ExchangeFixtureJson {
                param([string]$Path, $Value, [switch]$Replace)
                $Document = [Text.Json.JsonDocument]::Parse(($Value | ConvertTo-Json -Depth 20 -Compress))
                $Buffer = [IO.MemoryStream]::new()
                $Writer = [Text.Json.Utf8JsonWriter]::new($Buffer)
                try {
                    $Document.WriteTo($Writer)
                    $Writer.Flush()
                    $Record = Write-ExchangeFixtureBytes $Path $Buffer.ToArray() -Replace:$Replace
                    $Record | Add-Member -NotePropertyName Value -NotePropertyValue $Value
                    return $Record
                }
                finally { $Writer.Dispose(); $Buffer.Dispose(); $Document.Dispose() }
            }

            function New-ExchangeFixtureState {
                param([int]$Turn, [switch]$Federation)
                $State = [ordered]@{ schemaVersion = '1.3'; updated = '2026-09-08T12:00:00Z'; turn = $Turn; mode = 'interactive' }
                if ($Federation) {
                    $State.schemaVersion = '1.2'
                    $State.subSquads = @('api', 'sdk', 'repo-exchange')
                    $State.activeSubSquads = @()
                }
                else { $State.activeRoles = @() }
                $State.openEscalations = @()
                $State.currentRun = [ordered]@{ sessionModel = ''; modelOverrides = @{}; estCostUsd = 0; estCreditsTotal = 0 }
                if (-not $Federation -or $script:Fixture.FederationNotify) { $State.notify = [ordered]@{ approvalChannel = 'in-chat'; enabled = $false; email = ''; github = [ordered]@{ handle = ''; repo = '' } } }
                return $State
            }

            function Set-ExchangeFixtureFederation {
                $Registry = @'
| Sub-squad | Profile | Kind | Location | Owner | Description |
| --- | --- | --- | --- | --- | --- |
| api | software | in-repo | members/api/ | team | API |
| sdk | software | in-repo | members/sdk/ | team | SDK |
| repo-exchange | software | in-repo | members/repo-exchange/ | team | Local member |
'@
                $null = Write-ExchangeFixtureBytes ($script:RepositoryRoot + 'federation.md') ([Text.Encoding]::UTF8.GetBytes($Registry)) -Replace
                foreach ($Name in @('api', 'sdk', 'repo-exchange')) {
                    $null = Write-ExchangeFixtureJson ($script:RepositoryRoot + "members/$Name/state.json") (New-ExchangeFixtureState 0) -Replace
                }
            }

            function Complete-ExchangeFixtureOperation {
                param([string]$Operation, [string]$Root, [object[]]$Artifacts, $Receipt = $null, [string]$Attempt = '')
                if (-not $Attempt) { $Attempt = [guid]::NewGuid().ToString('D') }
                $StatePath = $Root + 'state.json'
                $Previous = 0
                if ([IO.File]::Exists([IO.Path]::Combine($script:Fixture.TopLevel, $StatePath))) {
                    $Previous = ([IO.File]::ReadAllText([IO.Path]::Combine($script:Fixture.TopLevel, $StatePath)) | ConvertFrom-Json).turn
                }
                $Federated = [IO.File]::Exists([IO.Path]::Combine($script:Fixture.TopLevel, $Root + 'federation.md'))
                $State = New-ExchangeFixtureState ($Previous + 1) -Federation:$Federated
                $StateRecord = Write-ExchangeFixtureJson $StatePath $State -Replace
                $Advance = [ordered]@{ fromTurn = $Previous; toTurn = $Previous + 1; updated = $State.updated; stateSha256 = $StateRecord.Hash }
                $Packet = $script:Fixture.Packet
                $Audit = [ordered]@{
                    schemaVersion = '1.0'; kind = 'squad-repo-audit'; attemptId = $Attempt; operation = $Operation
                    recordedAt = '2026-09-08T12:00:00Z'; squadRoot = $Root; correlationId = $Packet.Value.correlationId
                    taskId = $Packet.Value.taskId; registryAlias = 'service'; packetSha256 = $Packet.Hash
                    receiptSha256 = $(if ($Receipt) { $Receipt.Hash } else { '' })
                    sourceRepository = $Packet.Value.sourceRepository; targetRepository = $Packet.Value.targetRepository
                    sourceRevision = $Packet.Value.sourceRevision; targetRevision = $Packet.Value.targetRevision
                    resultRevision = $(if ($Receipt) { $Receipt.Value.resultRevision } else { '' })
                    disposition = @{ Issue = 'pending'; Claim = 'pending'; Accept = 'accepted'; Report = 'reported'; Import = 'reported' }[$Operation]
                    reason = ''; artifacts = @($Artifacts | ForEach-Object { [ordered]@{ path = $_.Path; sha256 = $_.Hash } }); stateAdvance = $Advance
                }
                $AuditRecord = Write-ExchangeFixtureJson ("fixture-audits/$Attempt.json") $Audit
                $JsonLine = [IO.File]::ReadAllText([IO.Path]::Combine($script:Fixture.TopLevel, $AuditRecord.Path))
                $Block = "<!-- squad-repo-audit:${Attempt}:begin -->`n$JsonLine`n<!-- squad-repo-audit:${Attempt}:end -->`n"
                foreach ($Path in @(($Root + 'decisions.md'), ($Root + 'history/repo-exchange/audit.md'))) {
                    $Full = [IO.Path]::Combine($script:Fixture.TopLevel, $Path)
                    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Full))
                    [IO.File]::AppendAllText($Full, $Block, [Text.UTF8Encoding]::new($false))
                }
                $Seal = [ordered]@{
                    schemaVersion = '1.0'; kind = 'squad-repo-commit'; attemptId = $Attempt; operation = $Operation; squadRoot = $Root
                    correlationId = $Packet.Value.correlationId; packetSha256 = $Packet.Hash; receiptSha256 = $Audit.receiptSha256
                    auditSha256 = $AuditRecord.Hash; stateAdvance = $Advance; committedAt = '2026-09-08T12:00:00Z'
                }
                $SealRecord = Write-ExchangeFixtureJson ($Root + "exchanges/operations/$Attempt/commit.json") $Seal
                return [pscustomobject]@{ Audit = $Audit; AuditRecord = $AuditRecord; Seal = $SealRecord; Block = $Block; State = $StateRecord }
            }

            function Initialize-ExchangeFixture {
                $script:Fixture = @{
                    TopLevel = [IO.Path]::Combine($script:Scratch, [guid]::NewGuid().ToString('D'))
                    Repository = 'https://github.com/contoso/hub'; Head = 'a' * 40
                    Now = [DateTimeOffset]::Parse('2026-09-08T12:01:00Z'); Root = $script:RepositoryRoot
                    FederationNotify = $true
                }
                $Packet = [ordered]@{
                    schemaVersion = '1.0'; kind = 'squad-repo-task'; correlationId = '11111111-1111-4111-8111-111111111111'
                    sourceRepository = 'https://github.com/contoso/hub'; sourceRevision = 'a' * 40
                    targetRepository = 'https://github.com/contoso/service'; targetRevision = 'b' * 40; taskId = 'api-contract'
                    createdAt = '2026-09-08T11:00:00Z'; expiresAt = '2026-09-15T11:00:00Z'
                    request = [ordered]@{ summary = 'Assess compatibility.'; acceptanceCriteria = @('Record the compatibility result.'); inputs = @() }
                    constraints = [ordered]@{ execution = 'advisory-only'; transport = 'user'; authority = 'target-local' }
                }
                $script:Fixture.Packet = Write-ExchangeFixtureJson ($script:RepositoryRoot + 'exchanges/staging/22222222-2222-4222-8222-222222222222/packet.json') $Packet
            }

            function Set-ExchangeFixtureTarget {
                $script:Fixture.Repository = $script:Fixture.Packet.Value.targetRepository
                $script:Fixture.Head = $script:Fixture.Packet.Value.targetRevision
            }

            function Add-ExchangeFixtureIssue {
                $Packet = $script:Fixture.Packet
                $FinalPath = $script:Fixture.Root + "exchanges/outbox/$($Packet.Value.correlationId)/packet.json"
                $Record = Write-ExchangeFixtureBytes $FinalPath ([IO.File]::ReadAllBytes([IO.Path]::Combine($script:Fixture.TopLevel, $Packet.Path)))
                $Record | Add-Member -NotePropertyName Value -NotePropertyValue $Packet.Value
                $script:Fixture.Packet = $Record
                $script:Fixture.Issue = Complete-ExchangeFixtureOperation Issue $script:Fixture.Root @($Record)
            }

            function Add-ExchangeFixtureAcceptance {
                param([string]$Root = '.copilot-tracking/squad/', [switch]$ClaimOnly, [string]$ClaimAttempt = '33333333-3333-4333-8333-333333333333')
                Set-ExchangeFixtureTarget
                $script:Fixture.Root = $Root
                $Packet = $script:Fixture.Packet
                $Claim = [ordered]@{
                    schemaVersion = '1.0'; kind = 'squad-repo-claim'; correlationId = $Packet.Value.correlationId; packetSha256 = $Packet.Hash
                    targetRepository = $Packet.Value.targetRepository; targetRevision = $Packet.Value.targetRevision; taskId = $Packet.Value.taskId
                    executionRoot = $Root; executionKind = $(if ($Root -ceq $script:RepositoryRoot) { 'single' } else { 'member' })
                    claimedAt = '2026-09-08T12:00:00Z'; claimAttemptId = $ClaimAttempt
                }
                $ClaimRecord = Write-ExchangeFixtureJson ($script:RepositoryRoot + "exchanges/claims/$($Packet.Value.correlationId)/claim.json") $Claim
                $script:Fixture.Claim = $ClaimRecord
                $script:Fixture.ClaimCommit = Complete-ExchangeFixtureOperation Claim $script:RepositoryRoot @($ClaimRecord) -Attempt $Claim.claimAttemptId
                if ($ClaimOnly) { return }
                $Inbox = $Root + "exchanges/inbox/$($Packet.Value.correlationId)/"
                $Saved = Write-ExchangeFixtureBytes ($Inbox + 'packet.json') ([IO.File]::ReadAllBytes([IO.Path]::Combine($script:Fixture.TopLevel, $Packet.Path)))
                $Saved | Add-Member -NotePropertyName Value -NotePropertyValue $Packet.Value
                $Intake = [ordered]@{
                    schemaVersion = '1.0'; kind = 'squad-repo-intake'; correlationId = $Packet.Value.correlationId; packetSha256 = $Packet.Hash
                    targetRepository = $Packet.Value.targetRepository; targetRevision = $Packet.Value.targetRevision; taskId = $Packet.Value.taskId
                    squadRoot = $Root; acceptedAt = '2026-09-08T12:00:00Z'
                }
                $script:Fixture.Packet = $Saved
                $script:Fixture.Intake = Write-ExchangeFixtureJson ($Inbox + 'intake.json') $Intake
                $script:Fixture.AcceptCommit = Complete-ExchangeFixtureOperation Accept $Root @($Saved, $script:Fixture.Intake, $ClaimRecord)
            }

            function Add-ExchangeFixtureReceipt {
                param([ValidateSet('completed', 'blocked', 'declined')][string]$Outcome = 'completed', [switch]$ForImport)
                $Packet = $script:Fixture.Packet
                $Evidence = @()
                if ($Outcome -eq 'completed') {
                    if ($ForImport) {
                        $Evidence = @([ordered]@{ path = 'src/result.txt'; sha256 = 'c' * 64 }, [ordered]@{ path = '.copilot-tracking/squad/history/Squad Scribe.md'; sha256 = 'd' * 64 })
                    }
                    else {
                        $Artifact = Write-ExchangeFixtureBytes 'src/result.txt' ([Text.Encoding]::UTF8.GetBytes('compatibility result'))
                        $History = Write-ExchangeFixtureBytes ($script:Fixture.Root + 'history/Squad Scribe.md') ([Text.Encoding]::UTF8.GetBytes("# History: Squad Scribe`n`n### Recorded local work`n"))
                        $Evidence = @([ordered]@{ path = $Artifact.Path; sha256 = $Artifact.Hash }, [ordered]@{ path = $History.Path; sha256 = $History.Hash })
                    }
                }
                $Receipt = [ordered]@{
                    schemaVersion = '1.0'; kind = 'squad-repo-receipt'; correlationId = $Packet.Value.correlationId; packetSha256 = $Packet.Hash
                    sourceRepository = $Packet.Value.sourceRepository; sourceRevision = $Packet.Value.sourceRevision
                    targetRepository = $Packet.Value.targetRepository; targetRevision = $Packet.Value.targetRevision; taskId = $Packet.Value.taskId
                    reportedAt = '2026-09-08T12:00:00Z'; status = 'reported'; outcome = $Outcome
                    resultRevision = $(if ($ForImport) { 'e' * 40 } else { $script:Fixture.Head }); summary = 'Local outcome recorded.'; evidence = $Evidence
                }
                $script:Fixture.Receipt = Write-ExchangeFixtureJson ($script:Fixture.Root + 'exchanges/staging/44444444-4444-4444-8444-444444444444/receipt.json') $Receipt
            }

            function Add-ExchangeFixtureFinalReceipt {
                param([ValidateSet('Report', 'Import')][string]$Operation)
                $Folder = if ($Operation -eq 'Report') { 'inbox' } else { 'outbox' }
                $Receipt = $script:Fixture.Receipt
                $Final = Write-ExchangeFixtureBytes ($script:Fixture.Root + "exchanges/$Folder/$($script:Fixture.Packet.Value.correlationId)/receipt.json") ([IO.File]::ReadAllBytes([IO.Path]::Combine($script:Fixture.TopLevel, $Receipt.Path)))
                $Final | Add-Member -NotePropertyName Value -NotePropertyValue $Receipt.Value
                $script:Fixture.Receipt = $Final
                $Artifacts = if ($Operation -eq 'Report') { @($script:Fixture.Packet, $script:Fixture.Intake, $Final) } else { @($script:Fixture.Packet, $Final) }
                $script:Fixture.FinalCommit = Complete-ExchangeFixtureOperation $Operation $script:Fixture.Root $Artifacts -Receipt $Final
            }

            function Invoke-ExchangeFixture {
                param([string]$Operation, [string]$Root = $script:Fixture.Root)
                $Arguments = @{ Operation = $Operation; PacketPath = $script:Fixture.Packet.Path; SquadRoot = $Root }
                if ($Operation -in @('Report', 'Import')) { $Arguments.ReceiptPath = $script:Fixture.Receipt.Path }
                Test-SquadRepoExchange @Arguments
            }

            function Update-ExchangeFixtureRecord {
                param([string]$Name)
                $Record = $script:Fixture[$Name]
                $script:Fixture[$Name] = Write-ExchangeFixtureJson $Record.Path $Record.Value -Replace
            }

            function Get-ExchangeFixtureSnapshot {
                @(Get-ChildItem -LiteralPath $script:Fixture.TopLevel -File -Recurse | Sort-Object FullName | ForEach-Object {
                        $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
                    }) -join "`n"
            }

            function Set-ExchangeFixtureAdvance {
                param($Commit, [int]$ToTurn)
                $Root = $Commit.Audit.squadRoot
                $Federated = [IO.File]::Exists([IO.Path]::Combine($script:Fixture.TopLevel, $Root + 'federation.md'))
                $State = New-ExchangeFixtureState $ToTurn -Federation:$Federated
                $StateRecord = Write-ExchangeFixtureJson ($Root + 'state.json') $State -Replace
                $Advance = [ordered]@{ fromTurn = $ToTurn - 1; toTurn = $ToTurn; updated = $State.updated; stateSha256 = $StateRecord.Hash }
                $Commit.Audit.stateAdvance = $Advance
                $AuditRecord = Write-ExchangeFixtureJson $Commit.AuditRecord.Path $Commit.Audit -Replace
                $JsonLine = [IO.File]::ReadAllText([IO.Path]::Combine($script:Fixture.TopLevel, $AuditRecord.Path))
                $Attempt = $Commit.Audit.attemptId
                $Block = "<!-- squad-repo-audit:${Attempt}:begin -->`n$JsonLine`n<!-- squad-repo-audit:${Attempt}:end -->`n"
                foreach ($Path in @(($Root + 'decisions.md'), ($Root + 'history/repo-exchange/audit.md'))) {
                    $Full = [IO.Path]::Combine($script:Fixture.TopLevel, $Path)
                    [IO.File]::WriteAllText($Full, [IO.File]::ReadAllText($Full).Replace($Commit.Block, $Block), [Text.UTF8Encoding]::new($false))
                }
                $Commit.Seal.Value.stateAdvance = $Advance
                $Commit.Seal.Value.auditSha256 = $AuditRecord.Hash
                $Commit.Seal = Write-ExchangeFixtureJson $Commit.Seal.Path $Commit.Seal.Value -Replace
                $Commit.AuditRecord = $AuditRecord
                $Commit.Block = $Block
                $Commit.State = $StateRecord
            }
        }

        BeforeEach {
            Initialize-ExchangeFixture
            Mock Get-SquadLocalContext { [pscustomobject]@{ TopLevel = $script:Fixture.TopLevel; Repository = $script:Fixture.Repository; Head = $script:Fixture.Head } }
            Mock Get-SquadClock { $script:Fixture.Now }
            Mock Invoke-SquadGitProcess { [pscustomobject]@{ ExitCode = 0; Output = '' } }
        }

        It 'Validates a staged Issue with no final files and no writes' -Tag 'Staging' {
            $Before = Get-ExchangeFixtureSnapshot
            $Result = Invoke-ExchangeFixture Issue
            $Result.Valid | Should -BeTrue -Because ($Result.Errors -join ',')
            $Result.Code | Should -Be 'valid'
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Accepts a fresh packet only in the independently observed target context' {
            Set-ExchangeFixtureTarget
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'valid'
            $script:Fixture.Repository = 'https://github.com/contoso/other'
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'wrong-context'
        }

        It 'Validates <Outcome> Report with changed HEAD and committed predecessors' -Tag 'Commit', 'Staging' -ForEach @(
            @{ Outcome = 'completed' }, @{ Outcome = 'blocked' }, @{ Outcome = 'declined' }
        ) {
            Add-ExchangeFixtureAcceptance
            $script:Fixture.Head = 'e' * 40
            Add-ExchangeFixtureReceipt -Outcome $Outcome
            $Before = Get-ExchangeFixtureSnapshot
            $Result = Invoke-ExchangeFixture Report
            $Result.Valid | Should -BeTrue -Because ($Result.Errors -join ',')
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Imports after hub HEAD advances without reading target evidence paths' -Tag 'Commit' {
            Add-ExchangeFixtureIssue
            $script:Fixture.Head = 'f' * 40
            Add-ExchangeFixtureReceipt -ForImport
            $Result = Invoke-ExchangeFixture Import
            $Result.Valid | Should -BeTrue -Because ($Result.Errors -join ',')
            Should -Invoke Invoke-SquadGitProcess -Times 1 -Exactly
        }

        It 'Identifies api acceptance from sdk without another acceptance or writes' -Tag 'Claim' {
            Set-ExchangeFixtureFederation
            Add-ExchangeFixtureAcceptance -Root ($script:RepositoryRoot + 'members/api/')
            $script:Fixture.Head = 'e' * 40
            $Before = Get-ExchangeFixtureSnapshot
            $Result = Invoke-ExchangeFixture Accept -Root ($script:RepositoryRoot + 'members/sdk/')
            $Result.Valid | Should -BeTrue -Because ($Result.Errors -join ',')
            $Result.Code | Should -Be 'already-accepted'
            $Result.ExecutionRoot | Should -Be ($script:RepositoryRoot + 'members/api/')
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Rejects a committed Claim without Accept on every public retry' -Tag 'Claim', 'Commit' {
            Add-ExchangeFixtureAcceptance -ClaimOnly
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'incomplete'
        }

        It 'Preserves a claim across promotion but rejects its old single root' -Tag 'Claim' {
            Add-ExchangeFixtureAcceptance
            Set-ExchangeFixtureFederation
            $Result = Invoke-ExchangeFixture Accept -Root ($script:RepositoryRoot + 'members/api/')
            $Result.Code | Should -Be 'wrong-context'
            $Result.Errors | Should -Contain 'root-relocated'
        }

        It 'Validates federation <Operation> with notify present=<HasNotify>' -Tag 'Commit', 'Claim' -ForEach @(
            @{ Operation = 'Import'; HasNotify = $true }, @{ Operation = 'Import'; HasNotify = $false },
            @{ Operation = 'Accept'; HasNotify = $true }, @{ Operation = 'Accept'; HasNotify = $false }
        ) {
            $script:Fixture.FederationNotify = $HasNotify
            Set-ExchangeFixtureFederation
            if ($Operation -eq 'Import') {
                (Invoke-ExchangeFixture Issue).Code | Should -Be 'valid'
                Add-ExchangeFixtureIssue
                Add-ExchangeFixtureReceipt -ForImport
                (Invoke-ExchangeFixture Import).Code | Should -Be 'valid'
                Add-ExchangeFixtureFinalReceipt Import
            }
            else { Add-ExchangeFixtureAcceptance -Root ($script:RepositoryRoot + 'members/api/') }
            $Before = Get-ExchangeFixtureSnapshot
            $Result = Invoke-ExchangeFixture $Operation
            $Result.Valid | Should -BeTrue -Because ($Result.Errors -join ',')
            $Result.Code | Should -Be $(if ($Operation -eq 'Import') { 'already-reported' } else { 'already-accepted' })
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Rejects malformed federation notify <Case>' -Tag 'Commit' -ForEach @(
            @{ Case = 'null'; Change = { $State.notify = $null } },
            @{ Case = 'array'; Change = { $State.notify = @() } },
            @{ Case = 'missing'; Change = { $State.notify.Remove('email') } },
            @{ Case = 'extra'; Change = { $State.notify.extra = $true } },
            @{ Case = 'channel-array'; Change = { $State.notify.approvalChannel = @('in-chat') } },
            @{ Case = 'channel-unknown'; Change = { $State.notify.approvalChannel = 'email' } },
            @{ Case = 'enabled-string'; Change = { $State.notify.enabled = 'false' } },
            @{ Case = 'email-array'; Change = { $State.notify.email = @('') } },
            @{ Case = 'github-null'; Change = { $State.notify.github = $null } },
            @{ Case = 'github-extra'; Change = { $State.notify.github.extra = '' } },
            @{ Case = 'handle-number'; Change = { $State.notify.github.handle = 0 } },
            @{ Case = 'repo-array'; Change = { $State.notify.github.repo = @() } }
        ) {
            Set-ExchangeFixtureFederation
            Add-ExchangeFixtureIssue
            Add-ExchangeFixtureReceipt -ForImport
            $State = New-ExchangeFixtureState 10 -Federation
            & $Change
            $null = Write-ExchangeFixtureJson ($script:RepositoryRoot + 'state.json') $State -Replace
            (Invoke-ExchangeFixture Import).Code | Should -Be 'incomplete'
        }

        It 'Rejects a single-squad state without its required notify' -Tag 'Commit' {
            Add-ExchangeFixtureAcceptance
            $State = New-ExchangeFixtureState 10
            $State.Remove('notify')
            $null = Write-ExchangeFixtureJson ($script:RepositoryRoot + 'state.json') $State -Replace
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'incomplete'
        }

        It 'Preserves root evidence through actual promotion and permits fresh <Operation>' -Tag 'Claim', 'Commit', 'AuditNamespace' -ForEach @(
            @{ Operation = 'Issue' }, @{ Operation = 'Accept' }
        ) {
            Add-ExchangeFixtureAcceptance
            $OldPacket = $script:Fixture.Packet
            $OldClaim = $script:Fixture.Claim
            $OldDecisions = [IO.File]::ReadAllBytes([IO.Path]::Combine($script:Fixture.TopLevel, $script:RepositoryRoot + 'decisions.md'))
            $Protected = @{}
            foreach ($File in Get-ChildItem -LiteralPath ([IO.Path]::Combine($script:Fixture.TopLevel, $script:RepositoryRoot + 'exchanges')) -File -Recurse) { $Protected[$File.FullName] = (Get-FileHash -LiteralPath $File.FullName).Hash }
            $AuditPath = [IO.Path]::Combine($script:Fixture.TopLevel, $script:RepositoryRoot + 'history/repo-exchange/audit.md')
            $Protected[$AuditPath] = (Get-FileHash -LiteralPath $AuditPath).Hash
            foreach ($Path in @('team.md', 'routing.md', 'notifications.md', 'consumption.md', 'consumption-rates.md', 'history/Local Worker.md')) {
                $null = Write-ExchangeFixtureBytes ($script:RepositoryRoot + $Path) ([Text.Encoding]::UTF8.GetBytes("# Existing $Path`n"))
            }
            $MemberRoot = $script:RepositoryRoot + 'members/api/'
            foreach ($Path in @('team.md', 'routing.md', 'notifications.md', 'state.json', 'consumption.md', 'consumption-rates.md', 'history/Local Worker.md')) {
                $Source = [IO.Path]::Combine($script:Fixture.TopLevel, $script:RepositoryRoot + $Path)
                $Bytes = [IO.File]::ReadAllBytes($Source)
                $Copy = Write-ExchangeFixtureBytes ($MemberRoot + $Path) $Bytes
                $Copy.Hash | Should -BeExactly (Get-SquadByteHash $Bytes)
                [IO.File]::Delete($Source)
                [IO.File]::Exists($Source) | Should -BeFalse
            }
            $MemberStateHash = Get-SquadFileDigest $script:Fixture.TopLevel ($MemberRoot + 'state.json')
            $null = Write-ExchangeFixtureBytes ($MemberRoot + 'decisions.md') ([Text.Encoding]::UTF8.GetBytes("# Decisions`nPre-promotion decisions remain at .copilot-tracking/squad/decisions.md.`n"))
            $Registry = "| Sub-squad | Profile | Kind | Location | Owner | Description |`n| --- | --- | --- | --- | --- | --- |`n| api | software | in-repo | members/api/ | team | API |`n"
            $null = Write-ExchangeFixtureBytes ($script:RepositoryRoot + 'federation.md') ([Text.Encoding]::UTF8.GetBytes($Registry))
            $null = Write-ExchangeFixtureJson ($script:RepositoryRoot + 'state.json') (New-ExchangeFixtureState 3 -Federation)
            [IO.File]::AppendAllText([IO.Path]::Combine($script:Fixture.TopLevel, $script:RepositoryRoot + 'decisions.md'), "`n## Promotion`nAdopted api; retained repository exchange evidence.`n")
            (Invoke-ExchangeFixture Accept -Root $MemberRoot).Errors | Should -Contain 'root-relocated'
            foreach ($Path in $Protected.Keys) { (Get-FileHash -LiteralPath $Path).Hash | Should -BeExactly $Protected[$Path] }
            (Get-SquadFileDigest $script:Fixture.TopLevel ($MemberRoot + 'state.json')) | Should -BeExactly $MemberStateHash
            [IO.File]::ReadAllText([IO.Path]::Combine($script:Fixture.TopLevel, $script:RepositoryRoot + 'decisions.md')).StartsWith([Text.Encoding]::UTF8.GetString($OldDecisions), [StringComparison]::Ordinal) | Should -BeTrue
            $PacketValue = [IO.File]::ReadAllText([IO.Path]::Combine($script:Fixture.TopLevel, $OldPacket.Path)) | ConvertFrom-Json -AsHashtable
            $PacketValue.correlationId = '99999999-9999-4999-8999-999999999999'
            $PacketValue.taskId = 'unrelated-contract'
            $script:Fixture.Root = if ($Operation -eq 'Issue') { $script:RepositoryRoot } else { $MemberRoot }
            if ($Operation -eq 'Issue') {
                $PacketValue.sourceRepository = $script:Fixture.Repository
                $PacketValue.sourceRevision = $script:Fixture.Head
                $PacketValue.targetRepository = 'https://github.com/contoso/other'
            }
            $script:Fixture.Packet = Write-ExchangeFixtureJson ($script:Fixture.Root + 'exchanges/staging/99999999-9999-4999-8999-999999999999/packet.json') $PacketValue
            $Result = Invoke-ExchangeFixture $Operation
            $Result.Valid | Should -BeTrue -Because ($Result.Errors -join ',')
            $Result.Code | Should -Be 'valid'
            if ($Operation -eq 'Issue') {
                Add-ExchangeFixtureIssue
                Add-ExchangeFixtureReceipt -ForImport
                (Invoke-ExchangeFixture Import).Code | Should -Be 'valid'
                Add-ExchangeFixtureFinalReceipt Import
                (Invoke-ExchangeFixture Import).Code | Should -Be 'already-reported'
            }
            else {
                Add-ExchangeFixtureAcceptance -Root $MemberRoot -ClaimAttempt '99999999-9999-4999-8999-999999999999'
                (Invoke-ExchangeFixture Accept).Code | Should -Be 'already-accepted'
            }
            (Get-SquadFileDigest $script:Fixture.TopLevel $OldClaim.Path) | Should -BeExactly $OldClaim.Hash
            $script:Fixture.Packet = $OldPacket
            (Invoke-ExchangeFixture Accept -Root $MemberRoot).Errors | Should -Contain 'root-relocated'
        }

        It 'Enforces <Case> same-StatePath predecessor turns for <Operation>' -Tag 'Commit' -ForEach @(
            foreach ($Operation in @('Accept', 'Report', 'Import')) {
                foreach ($Case in @('collapsed', 'backwards', 'distinct', 'intervening')) { @{ Operation = $Operation; Case = $Case } }
            }
        ) {
            if ($Operation -eq 'Import') { Add-ExchangeFixtureIssue } else { Add-ExchangeFixtureAcceptance }
            if ($Operation -ne 'Accept') { Add-ExchangeFixtureReceipt -ForImport:($Operation -eq 'Import'); Add-ExchangeFixtureFinalReceipt $Operation }
            $Predecessor = switch ($Operation) { 'Accept' { $script:Fixture.ClaimCommit }; 'Report' { $script:Fixture.AcceptCommit }; 'Import' { $script:Fixture.Issue } }
            $Successor = if ($Operation -eq 'Accept') { $script:Fixture.AcceptCommit } else { $script:Fixture.FinalCommit }
            $PredecessorTurn = if ($Case -eq 'backwards') { 3 } else { $Predecessor.Seal.Value.stateAdvance.toTurn }
            Set-ExchangeFixtureAdvance $Predecessor $PredecessorTurn
            $SuccessorTurn = switch ($Case) { 'collapsed' { $PredecessorTurn }; 'backwards' { $PredecessorTurn - 1 }; 'distinct' { $PredecessorTurn + 1 }; 'intervening' { $PredecessorTurn + 3 } }
            Set-ExchangeFixtureAdvance $Successor $SuccessorTurn
            if ($Case -eq 'backwards') { $null = Write-ExchangeFixtureJson ($script:Fixture.Root + 'state.json') (New-ExchangeFixtureState 10) -Replace }
            $Before = Get-ExchangeFixtureSnapshot
            $Result = Invoke-ExchangeFixture $Operation
            $Expected = if ($Case -in @('collapsed', 'backwards')) { 'incomplete' } elseif ($Operation -eq 'Accept') { 'already-accepted' } else { 'already-reported' }
            $Result.Code | Should -Be $Expected -Because ($Result.Errors -join ',')
            $Result.Valid | Should -Be ($Case -in @('distinct', 'intervening'))
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Does not compare unrelated Claim and member counters at root turn <RootTurn>' -Tag 'Claim', 'Commit' -ForEach @(
            @{ RootTurn = 1 }, @{ RootTurn = 3 }
        ) {
            Set-ExchangeFixtureFederation
            Add-ExchangeFixtureAcceptance -Root ($script:RepositoryRoot + 'members/api/')
            Set-ExchangeFixtureAdvance $script:Fixture.ClaimCommit $RootTurn
            $script:Fixture.AcceptCommit.Seal.Value.stateAdvance.toTurn | Should -Be 1
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'already-accepted'
        }

        It 'Requires a scalar string constraint <Field> for <Case>' -ForEach @(
            foreach ($Field in @('execution', 'transport', 'authority')) {
                foreach ($Case in @('empty-array', 'singleton-array', 'mixed-array', 'nested-array', 'null', 'number', 'boolean', 'object')) { @{ Field = $Field; Case = $Case } }
            }
        ) {
            $Expected = $script:Fixture.Packet.Value.constraints[$Field]
            switch ($Case) {
                'empty-array' { $Value = @() }
                'singleton-array' { $Value = @($Expected) }
                'mixed-array' { $Value = @($Expected, 0) }
                'nested-array' { $Value = ,@($Expected) }
                'null' { $Value = $null }
                'number' { $Value = 0 }
                'boolean' { $Value = $false }
                'object' { $Value = @{ value = $Expected } }
            }
            $script:Fixture.Packet.Value.constraints[$Field] = $Value
            Update-ExchangeFixtureRecord Packet
            $Result = Invoke-ExchangeFixture Issue
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Contain 'string-value'
        }

        It 'Returns historical <Operation> no-op after expiry without writes or HEAD pinning' -Tag 'Commit' -ForEach @(
            @{ Operation = 'Report' }, @{ Operation = 'Import' }
        ) {
            if ($Operation -eq 'Report') { Add-ExchangeFixtureAcceptance } else { Add-ExchangeFixtureIssue }
            Add-ExchangeFixtureReceipt -ForImport:($Operation -eq 'Import')
            Add-ExchangeFixtureFinalReceipt $Operation
            $script:Fixture.Now = [DateTimeOffset]::Parse('2026-10-08T12:00:00Z')
            $script:Fixture.Head = 'f' * 40
            $Before = Get-ExchangeFixtureSnapshot
            $Result = Invoke-ExchangeFixture $Operation
            $Result.Valid | Should -BeTrue -Because ($Result.Errors -join ',')
            $Result.Code | Should -Be 'already-reported'
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Rejects packet mutation <Case>' -ForEach @(
            @{ Case = 'unknown'; Change = { $script:Fixture.Packet.Value.extra = 'value' } },
            @{ Case = 'version'; Change = { $script:Fixture.Packet.Value.schemaVersion = '2.0' } },
            @{ Case = 'numeric-version'; Change = { $script:Fixture.Packet.Value.schemaVersion = 1 } },
            @{ Case = 'kind'; Change = { $script:Fixture.Packet.Value.kind = 'squad-repo-receipt' } },
            @{ Case = 'null-summary'; Change = { $script:Fixture.Packet.Value.request.summary = $null } },
            @{ Case = 'numeric-summary'; Change = { $script:Fixture.Packet.Value.request.summary = 42 } },
            @{ Case = 'empty-summary'; Change = { $script:Fixture.Packet.Value.request.summary = '' } },
            @{ Case = 'long-summary'; Change = { $script:Fixture.Packet.Value.request.summary = 'x' * 4001 } },
            @{ Case = 'criteria-string'; Change = { $script:Fixture.Packet.Value.request.acceptanceCriteria = 'criterion' } },
            @{ Case = 'criteria-empty'; Change = { $script:Fixture.Packet.Value.request.acceptanceCriteria = @() } },
            @{ Case = 'criteria-many'; Change = { $script:Fixture.Packet.Value.request.acceptanceCriteria = @('x') * 21 } },
            @{ Case = 'criteria-long'; Change = { $script:Fixture.Packet.Value.request.acceptanceCriteria = @('x' * 2001) } },
            @{ Case = 'criteria-null'; Change = { $script:Fixture.Packet.Value.request.acceptanceCriteria = @($null) } },
            @{ Case = 'inputs-null'; Change = { $script:Fixture.Packet.Value.request.inputs = $null } },
            @{ Case = 'input-content'; Change = { $script:Fixture.Packet.Value.request.inputs = @(@{ label = 'x'; content = 'x' * 16001 }) } },
            @{ Case = 'input-label'; Change = { $script:Fixture.Packet.Value.request.inputs = @(@{ label = 'x' * 129; content = 'x' }) } },
            @{ Case = 'input-extra'; Change = { $script:Fixture.Packet.Value.request.inputs = @(@{ label = 'x'; content = 'x'; path = 'x' }) } },
            @{ Case = 'constraints'; Change = { $script:Fixture.Packet.Value.constraints.authority = 'source' } },
            @{ Case = 'task'; Change = { $script:Fixture.Packet.Value.taskId = 'UpperCase' } },
            @{ Case = 'id'; Change = { $script:Fixture.Packet.Value.correlationId = '../elsewhere' } },
            @{ Case = 'revision'; Change = { $script:Fixture.Packet.Value.targetRevision = 'main' } },
            @{ Case = 'same-repo'; Change = { $script:Fixture.Packet.Value.targetRepository = $script:Fixture.Packet.Value.sourceRepository } },
            @{ Case = 'ttl-zero'; Change = { $script:Fixture.Packet.Value.expiresAt = $script:Fixture.Packet.Value.createdAt } },
            @{ Case = 'ttl-long'; Change = { $script:Fixture.Packet.Value.expiresAt = '2026-09-16T11:00:00Z' } },
            @{ Case = 'future'; Change = { $script:Fixture.Packet.Value.createdAt = '2026-09-08T12:07:00Z' } },
            @{ Case = 'non-utc'; Change = { $script:Fixture.Packet.Value.createdAt = '2026-09-08T11:00:00+00:00' } }
        ) {
            & $Change
            Update-ExchangeFixtureRecord Packet
            (Invoke-ExchangeFixture Issue).Valid | Should -BeFalse
        }

        It 'Rejects unsupported canonical repository <Repository>' -ForEach @(
            @{ Repository = 'https://user:secret@github.com/contoso/service' }, @{ Repository = 'https://github.com.evil.test/contoso/service' },
            @{ Repository = 'git@github.com:contoso/service.git' }, @{ Repository = 'C:/service' },
            @{ Repository = 'https://github.com/contoso/service?x=1' }, @{ Repository = 'https://github.com/contoso%2fother/service' },
            @{ Repository = 'https://github.com/contoso/service.git' }, @{ Repository = 'https://github.com/contoso/service/' },
            @{ Repository = 'https://github.com:443/contoso/service' }, @{ Repository = 'https://github.com/contoso/service#frag' },
            @{ Repository = 'https://github.com/con--toso/service' }, @{ Repository = 'https://github.com/contoso/..' },
            @{ Repository = 'https://github.com/Contoso/service' }
        ) {
            $script:Fixture.Packet.Value.targetRepository = $Repository
            Update-ExchangeFixtureRecord Packet
            $Result = Invoke-ExchangeFixture Issue
            $Result.Valid | Should -BeFalse
            ($Result.Errors -join ' ') | Should -Not -Match 'secret'
        }

        It 'Rejects receipt binding mutation <Field>' -ForEach @(
            @{ Field = 'correlationId'; Value = '99999999-9999-4999-8999-999999999999' },
            @{ Field = 'sourceRepository'; Value = 'https://github.com/contoso/other' },
            @{ Field = 'targetRepository'; Value = 'https://github.com/contoso/other' },
            @{ Field = 'sourceRevision'; Value = 'c' * 40 }, @{ Field = 'targetRevision'; Value = 'c' * 40 },
            @{ Field = 'taskId'; Value = 'other-task' }, @{ Field = 'packetSha256'; Value = 'c' * 64 }
        ) {
            Add-ExchangeFixtureIssue
            Add-ExchangeFixtureReceipt -ForImport
            $script:Fixture.Receipt.Value[$Field] = $Value
            Update-ExchangeFixtureRecord Receipt
            (Invoke-ExchangeFixture Import).Valid | Should -BeFalse
        }

        It 'Rejects incomplete Accept boundary <Boundary>' -Tag 'Commit' -ForEach @(
            @{ Boundary = 'claim'; Remove = 'Claim' }, @{ Boundary = 'intake'; Remove = 'Intake' },
            @{ Boundary = 'packet'; Remove = 'Packet' }, @{ Boundary = 'claim-seal'; Remove = 'ClaimCommit' },
            @{ Boundary = 'accept-seal'; Remove = 'AcceptCommit' }, @{ Boundary = 'state'; Remove = 'State' },
            @{ Boundary = 'decisions'; Remove = 'Decisions' }, @{ Boundary = 'audit'; Remove = 'Audit' }
        ) {
            Add-ExchangeFixtureAcceptance
            $Path = switch ($Remove) {
                'ClaimCommit' { $script:Fixture.ClaimCommit.Seal.Path }
                'AcceptCommit' { $script:Fixture.AcceptCommit.Seal.Path }
                'State' { $script:Fixture.Root + 'state.json' }
                'Decisions' { $script:Fixture.Root + 'decisions.md' }
                'Audit' { $script:Fixture.Root + 'history/repo-exchange/audit.md' }
                default { $script:Fixture[$Remove].Path }
            }
            $Transport = Write-ExchangeFixtureBytes 'transfers/packet.json' ([IO.File]::ReadAllBytes([IO.Path]::Combine($script:Fixture.TopLevel, $script:Fixture.Packet.Path)))
            [IO.File]::Delete([IO.Path]::Combine($script:Fixture.TopLevel, $Path))
            $script:Fixture.Packet.Path = $Transport.Path
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'incomplete'
        }

        It 'Rejects first <Operation> at expiry' -ForEach @(
            @{ Operation = 'Issue' }, @{ Operation = 'Accept' }, @{ Operation = 'Report' }, @{ Operation = 'Import' }
        ) {
            switch ($Operation) {
                'Accept' { Set-ExchangeFixtureTarget }
                'Report' { Add-ExchangeFixtureAcceptance; Add-ExchangeFixtureReceipt }
                'Import' { Add-ExchangeFixtureIssue; Add-ExchangeFixtureReceipt -ForImport }
            }
            $script:Fixture.Now = [DateTimeOffset]::Parse($script:Fixture.Packet.Value.expiresAt)
            (Invoke-ExchangeFixture $Operation).Code | Should -Be 'stale'
        }

        It 'Rejects an Issue collision and never overwrites saved bytes' -Tag 'Staging' {
            $Candidate = $script:Fixture.Packet
            Add-ExchangeFixtureIssue
            $script:Fixture.Packet = $Candidate
            $Before = Get-ExchangeFixtureSnapshot
            (Invoke-ExchangeFixture Issue).Code | Should -Be 'conflict'
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Preserves exact staged bytes and rejects changed candidates' -Tag 'Staging', 'Claim' {
            Add-ExchangeFixtureAcceptance
            $Original = $script:Fixture.Packet.Hash
            $Bytes = [IO.File]::ReadAllBytes([IO.Path]::Combine($script:Fixture.TopLevel, $script:Fixture.Packet.Path))
            Get-SquadByteHash $Bytes | Should -BeExactly $Original
            $Changed = Write-ExchangeFixtureBytes 'transfers/changed.json' ($Bytes + [byte[]]@(10))
            $script:Fixture.Packet.Path = $Changed.Path
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'conflict'
        }

        It 'Allows two preflights but only one create-new claim winner' -Tag 'Claim', 'Staging' {
            Set-ExchangeFixtureFederation
            Set-ExchangeFixtureTarget
            $Api = $script:RepositoryRoot + 'members/api/'
            $Sdk = $script:RepositoryRoot + 'members/sdk/'
            (Invoke-ExchangeFixture Accept -Root $Api).Code | Should -Be 'valid'
            (Invoke-ExchangeFixture Accept -Root $Sdk).Code | Should -Be 'valid'
            Add-ExchangeFixtureAcceptance -Root $Api -ClaimOnly
            $Before = Get-ExchangeFixtureSnapshot
            { Write-ExchangeFixtureJson $script:Fixture.Claim.Path $script:Fixture.Claim.Value } | Should -Throw
            (Invoke-ExchangeFixture Accept -Root $Sdk).Code | Should -Be 'incomplete'
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Rejects a removed pinned member without reading a replacement inbox' -Tag 'Claim' {
            Set-ExchangeFixtureFederation
            Add-ExchangeFixtureAcceptance -Root ($script:RepositoryRoot + 'members/api/')
            [IO.File]::Delete([IO.Path]::Combine($script:Fixture.TopLevel, $script:Fixture.Root + 'state.json'))
            (Invoke-ExchangeFixture Accept -Root ($script:RepositoryRoot + 'members/sdk/')).Code | Should -Be 'wrong-context'
        }

        It 'Refuses Report from a different registered member' -Tag 'Claim' {
            Set-ExchangeFixtureFederation
            Add-ExchangeFixtureAcceptance -Root ($script:RepositoryRoot + 'members/api/')
            Add-ExchangeFixtureReceipt
            (Invoke-ExchangeFixture Report -Root ($script:RepositoryRoot + 'members/sdk/')).Code | Should -Be 'wrong-context'
        }

        It 'Rejects an empty claim as incomplete, not absent' -Tag 'Claim' {
            Set-ExchangeFixtureTarget
            $null = Write-ExchangeFixtureBytes ($script:RepositoryRoot + "exchanges/claims/$($script:Fixture.Packet.Value.correlationId)/claim.json") ([byte[]]@())
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'incomplete'
        }

        It 'Rejects forged commit boundary <Boundary>' -Tag 'Commit' -ForEach @(
            @{ Boundary = 'wrong-audit-digest' }, @{ Boundary = 'partial-append' }, @{ Boundary = 'duplicate-block' },
            @{ Boundary = 'different-pair' }, @{ Boundary = 'failed-state' }, @{ Boundary = 'wrong-state-hash' },
            @{ Boundary = 'invalid-state-schema' }, @{ Boundary = 'tampered-intake' }, @{ Boundary = 'malformed-seal' },
            @{ Boundary = 'unknown-audit-key' }, @{ Boundary = 'unknown-seal-key' }, @{ Boundary = 'wrong-artifact-digest' },
            @{ Boundary = 'wrong-audit-binding' }, @{ Boundary = 'duplicate-operation' }
        ) {
            Add-ExchangeFixtureAcceptance
            $Commit = $script:Fixture.AcceptCommit
            $AuditPath = $script:Fixture.Root + 'history/repo-exchange/audit.md'
            switch ($Boundary) {
                'wrong-audit-digest' { $Commit.Seal.Value.auditSha256 = 'f' * 64; $null = Write-ExchangeFixtureJson $Commit.Seal.Path $Commit.Seal.Value -Replace }
                'partial-append' { [IO.File]::AppendAllText([IO.Path]::Combine($script:Fixture.TopLevel, $AuditPath), "<!-- squad-repo-audit:99999999-9999-4999-8999-999999999999:begin -->`n") }
                'duplicate-block' { [IO.File]::AppendAllText([IO.Path]::Combine($script:Fixture.TopLevel, $AuditPath), $Commit.Block) }
                'different-pair' { [IO.File]::WriteAllText([IO.Path]::Combine($script:Fixture.TopLevel, $AuditPath), $Commit.Block) }
                'failed-state' { $null = Write-ExchangeFixtureJson $Commit.State.Path (New-ExchangeFixtureState 0) -Replace }
                'wrong-state-hash' { $Commit.State.Value.mode = 'autonomous'; $null = Write-ExchangeFixtureJson $Commit.State.Path $Commit.State.Value -Replace }
                'invalid-state-schema' { $Commit.State.Value.extra = 'unsupported'; $null = Write-ExchangeFixtureJson $Commit.State.Path $Commit.State.Value -Replace }
                'tampered-intake' { $script:Fixture.Intake.Value.targetRevision = 'c' * 40; Update-ExchangeFixtureRecord Intake }
                'malformed-seal' { $null = Write-ExchangeFixtureBytes $Commit.Seal.Path ([Text.Encoding]::UTF8.GetBytes('{')) -Replace }
                'unknown-seal-key' { $Commit.Seal.Value.extra = 'unsupported'; $null = Write-ExchangeFixtureJson $Commit.Seal.Path $Commit.Seal.Value -Replace }
                'duplicate-operation' { $null = Complete-ExchangeFixtureOperation Accept $script:Fixture.Root @($script:Fixture.Packet, $script:Fixture.Intake, $script:Fixture.Claim) }
                default {
                    if ($Boundary -eq 'unknown-audit-key') { $Commit.Audit.extra = 'unsupported' }
                    elseif ($Boundary -eq 'wrong-artifact-digest') { $Commit.Audit.artifacts[0].sha256 = 'f' * 64 }
                    else { $Commit.Audit.taskId = 'wrong-task' }
                    $Changed = Write-ExchangeFixtureJson $Commit.AuditRecord.Path $Commit.Audit -Replace
                    $JsonLine = [IO.File]::ReadAllText([IO.Path]::Combine($script:Fixture.TopLevel, $Changed.Path))
                    $Attempt = $Commit.Audit.attemptId
                    $NewBlock = "<!-- squad-repo-audit:${Attempt}:begin -->`n$JsonLine`n<!-- squad-repo-audit:${Attempt}:end -->`n"
                    foreach ($Path in @(($script:Fixture.Root + 'decisions.md'), $AuditPath)) {
                        $Full = [IO.Path]::Combine($script:Fixture.TopLevel, $Path)
                        [IO.File]::WriteAllText($Full, [IO.File]::ReadAllText($Full).Replace($Commit.Block, $NewBlock))
                    }
                    $Commit.Seal.Value.auditSha256 = $Changed.Hash
                    $null = Write-ExchangeFixtureJson $Commit.Seal.Path $Commit.Seal.Value -Replace
                }
            }
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'incomplete'
        }

        It 'Rejects a final <Operation> receipt without its complete operation seal' -Tag 'Commit', 'Staging' -ForEach @(
            @{ Operation = 'Report' }, @{ Operation = 'Import' }
        ) {
            if ($Operation -eq 'Report') { Add-ExchangeFixtureAcceptance } else { Add-ExchangeFixtureIssue }
            Add-ExchangeFixtureReceipt -ForImport:($Operation -eq 'Import')
            Add-ExchangeFixtureFinalReceipt $Operation
            [IO.File]::Delete([IO.Path]::Combine($script:Fixture.TopLevel, $script:Fixture.FinalCommit.Seal.Path))
            $Before = Get-ExchangeFixtureSnapshot
            (Invoke-ExchangeFixture $Operation).Code | Should -Be 'incomplete'
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Rejects <Operation> receipt when only its predecessor audit remains' -Tag 'Commit' -ForEach @(
            @{ Operation = 'Report' }, @{ Operation = 'Import' }
        ) {
            if ($Operation -eq 'Report') { Add-ExchangeFixtureAcceptance } else { Add-ExchangeFixtureIssue }
            Add-ExchangeFixtureReceipt -ForImport:($Operation -eq 'Import')
            Add-ExchangeFixtureFinalReceipt $Operation
            foreach ($Path in @(($script:Fixture.Root + 'decisions.md'), ($script:Fixture.Root + 'history/repo-exchange/audit.md'))) {
                $Full = [IO.Path]::Combine($script:Fixture.TopLevel, $Path)
                [IO.File]::WriteAllText($Full, [IO.File]::ReadAllText($Full).Replace($script:Fixture.FinalCommit.Block, ''))
            }
            (Invoke-ExchangeFixture $Operation).Code | Should -Be 'incomplete'
        }

        It 'Rejects Import of a packet lacking issuance proof' -Tag 'Commit' {
            Add-ExchangeFixtureIssue
            Add-ExchangeFixtureReceipt -ForImport
            [IO.File]::Delete([IO.Path]::Combine($script:Fixture.TopLevel, $script:Fixture.Issue.Seal.Path))
            (Invoke-ExchangeFixture Import).Code | Should -Be 'incomplete'
        }

        It 'Retains partial final receipt bytes without repairing them' -Tag 'Staging', 'Commit' {
            Add-ExchangeFixtureAcceptance
            Add-ExchangeFixtureReceipt
            $FinalPath = $script:Fixture.Root + "exchanges/inbox/$($script:Fixture.Packet.Value.correlationId)/receipt.json"
            $null = Write-ExchangeFixtureBytes $FinalPath ([Text.Encoding]::UTF8.GetBytes('{"schemaVersion":'))
            $Before = Get-ExchangeFixtureSnapshot
            (Invoke-ExchangeFixture Report).Code | Should -Be 'incomplete'
            Get-ExchangeFixtureSnapshot | Should -BeExactly $Before
        }

        It 'Rejects different receipt bytes for an already committed <Operation>' -Tag 'Commit' -ForEach @(
            @{ Operation = 'Report' }, @{ Operation = 'Import' }
        ) {
            if ($Operation -eq 'Report') { Add-ExchangeFixtureAcceptance } else { Add-ExchangeFixtureIssue }
            Add-ExchangeFixtureReceipt -ForImport:($Operation -eq 'Import')
            Add-ExchangeFixtureFinalReceipt $Operation
            $Value = $script:Fixture.Receipt.Value
            $Value.summary = 'Changed report'
            $script:Fixture.Receipt = Write-ExchangeFixtureJson 'transfers/changed-receipt.json' $Value
            (Invoke-ExchangeFixture $Operation).Code | Should -Be 'conflict'
        }

        It 'Rejects invalid receipt <Case>' -ForEach @(
            @{ Case = 'verified'; Change = { $script:Fixture.Receipt.Value.status = 'verified' } },
            @{ Case = 'outcome'; Change = { $script:Fixture.Receipt.Value.outcome = 'partial' } },
            @{ Case = 'result-revision'; Change = { $script:Fixture.Receipt.Value.resultRevision = 'd' * 40 } },
            @{ Case = 'no-evidence'; Change = { $script:Fixture.Receipt.Value.evidence = @() } },
            @{ Case = 'history-only'; Change = { $script:Fixture.Receipt.Value.evidence = @($script:Fixture.Receipt.Value.evidence[1]) } },
            @{ Case = 'artifact-only'; Change = { $script:Fixture.Receipt.Value.evidence = @($script:Fixture.Receipt.Value.evidence[0]) } },
            @{ Case = 'wrong-hash'; Change = { $script:Fixture.Receipt.Value.evidence[0].sha256 = 'f' * 64 } },
            @{ Case = 'missing-file'; Change = { $script:Fixture.Receipt.Value.evidence[0].path = 'src/absent.txt' } },
            @{ Case = 'traversal'; Change = { $script:Fixture.Receipt.Value.evidence[0].path = '../other-repo/result.txt' } },
            @{ Case = 'evidence-extra'; Change = { $script:Fixture.Receipt.Value.evidence[0].extra = 'unknown' } },
            @{ Case = 'duplicate-evidence'; Change = { $script:Fixture.Receipt.Value.evidence += $script:Fixture.Receipt.Value.evidence[0] } },
            @{ Case = 'too-many-evidence'; Change = { $script:Fixture.Receipt.Value.evidence = @($script:Fixture.Receipt.Value.evidence[0]) * 21 } },
            @{ Case = 'report-before-created'; Change = { $script:Fixture.Receipt.Value.reportedAt = '2026-09-08T10:00:00Z' } },
            @{ Case = 'report-at-expiry'; Change = { $script:Fixture.Receipt.Value.reportedAt = $script:Fixture.Packet.Value.expiresAt } },
            @{ Case = 'report-future'; Change = { $script:Fixture.Receipt.Value.reportedAt = '2026-09-08T12:07:00Z' } },
            @{ Case = 'extra'; Change = { $script:Fixture.Receipt.Value.approved = $true } }
        ) {
            Add-ExchangeFixtureAcceptance
            Add-ExchangeFixtureReceipt
            & $Change
            Update-ExchangeFixtureRecord Receipt
            (Invoke-ExchangeFixture Report).Valid | Should -BeFalse
        }

        It 'Rejects incorrect first target HEAD' {
            Set-ExchangeFixtureTarget
            $script:Fixture.Head = 'e' * 40
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'wrong-context'
        }

        It 'Accepts a complete historical acceptance after expiry' -Tag 'Claim', 'Commit' {
            Add-ExchangeFixtureAcceptance
            $script:Fixture.Now = [DateTimeOffset]::Parse('2026-10-08T12:00:00Z')
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'already-accepted'
        }

        It 'Rejects rooted and traversing public packet paths without reading them' -ForEach @(
            @{ Path = '/packet.json' }, @{ Path = 'C:/packet.json' }, @{ Path = '../outside/packet.json' },
            @{ Path = '.copilot-tracking/squad/../../other/packet.json' }, @{ Path = 'Microsoft.PowerShell.Core/FileSystem::C:/packet.json' }
        ) {
            $script:Fixture.Packet.Path = $Path
            (Invoke-ExchangeFixture Issue).Valid | Should -BeFalse
        }

        It 'Rejects a reparse ancestor before opening packet bytes' {
            $Target = [IO.Path]::Combine($script:Fixture.TopLevel, 'real')
            $Link = [IO.Path]::Combine($script:Fixture.TopLevel, 'linked')
            $null = [IO.Directory]::CreateDirectory($Target)
            if ($IsWindows) { $null = New-Item -ItemType Junction -Path $Link -Target $Target }
            else { $null = [IO.Directory]::CreateSymbolicLink($Link, $Target) }
            try { { Resolve-SquadPath $script:Fixture.TopLevel 'linked/packet.json' } | Should -Throw '*reparse-path*' }
            finally { if ($IsWindows) { Remove-Item -LiteralPath $Link -Force } else { [IO.Directory]::Delete($Link) } }
        }

        It 'Rejects Import when the source commit is not locally available' -Tag 'OfflineGit' {
            Add-ExchangeFixtureIssue
            Add-ExchangeFixtureReceipt -ForImport
            Mock Invoke-SquadGitProcess { [pscustomobject]@{ ExitCode = 128; Output = '' } }
            (Invoke-ExchangeFixture Import).Code | Should -Be 'wrong-context'
            Should -Invoke Invoke-SquadGitProcess -Times 1 -Exactly -ParameterFilter {
                $StartInfo.ArgumentList[0] -ceq '--no-lazy-fetch' -and $StartInfo.ArgumentList[5] -ceq 'cat-file'
            }
        }

        It 'Retains committed acceptance through a later valid optional Watch state' -Tag 'Commit' {
            Add-ExchangeFixtureAcceptance
            $State = New-ExchangeFixtureState 3
            $State.trigger = [ordered]@{ source = 'workflow_dispatch'; ref = 'contoso/service'; eventId = 'manual:1'; actor = 'operator'; receivedAt = '2026-09-08T12:00:00Z'; runId = 'autopilot-run-example' }
            $null = Write-ExchangeFixtureJson ($script:Fixture.Root + 'state.json') $State -Replace
            (Invoke-ExchangeFixture Accept).Code | Should -Be 'already-accepted'
        }

        It 'Rejects arbitrary roots and unknown registry kinds' {
            Set-ExchangeFixtureFederation
            Set-ExchangeFixtureTarget
            (Invoke-ExchangeFixture Accept -Root '.copilot-tracking/squad-other/').Code | Should -Be 'wrong-context'
            $Path = [IO.Path]::Combine($script:Fixture.TopLevel, $script:RepositoryRoot + 'federation.md')
            [IO.File]::WriteAllText($Path, [IO.File]::ReadAllText($Path).Replace('| software | in-repo |', '| software | remote |'))
            (Invoke-ExchangeFixture Accept -Root ($script:RepositoryRoot + 'members/api/')).Code | Should -Be 'wrong-context'
        }

        AfterAll {
            if ($script:Scratch -and [IO.Directory]::Exists($script:Scratch)) { [IO.Directory]::Delete($script:Scratch, $true) }
        }
    }
}

Describe 'Exchange offline Git construction' -Tag 'Unit', 'Protocol', 'OfflineGit' {
    InModuleScope Test-SquadRepoExchange {
        BeforeEach {
            $script:GitCalls = [Collections.Generic.List[object]]::new()
            $script:GitRoot = (Get-Location).ProviderPath
            $script:GitOrigin = 'HTTPS://GitHub.com/Contoso/Service.git'
            $script:GitFailure = ''
            Mock Invoke-SquadGitProcess {
                param($StartInfo)
                $script:GitCalls.Add($StartInfo)
                $Suffix = @($StartInfo.ArgumentList | Select-Object -Skip 5)
                if ($script:GitFailure -and $Suffix[0] -ceq $script:GitFailure) { return [pscustomobject]@{ ExitCode = 128; Output = 'not emitted' } }
                $Output = switch ($Suffix -join ' ') {
                    '--version' { 'git version 2.55.0' }
                    'rev-parse --show-toplevel' { $script:GitRoot }
                    'config --local --get-all remote.origin.url' { $script:GitOrigin }
                    'rev-parse --verify HEAD' { 'b' * 40 }
                    default { '' }
                }
                [pscustomobject]@{ ExitCode = 0; Output = $Output }
            }
        }

        It 'Constructs every call with offline arguments and child-only environment isolation' {
            $Overrides = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0')
            $Saved = @{}
            foreach ($Key in $Overrides) { $Saved[$Key] = [Environment]::GetEnvironmentVariable($Key); [Environment]::SetEnvironmentVariable($Key, 'fixture-routing-override') }
            try {
                $Context = Get-SquadLocalContext
                $Context.Repository | Should -BeExactly 'https://github.com/contoso/service'
                $null = Invoke-SquadGit Commit -Revision ('a' * 40)
                $script:GitCalls.Count | Should -Be 5
                foreach ($StartInfo in $script:GitCalls) {
                    ($StartInfo.ArgumentList | Select-Object -First 5) -join '|' | Should -BeExactly '--no-lazy-fetch|-c|credential.helper=|-c|core.askPass='
                    $StartInfo.UseShellExecute | Should -BeFalse
                    $StartInfo.WorkingDirectory | Should -BeExactly (Get-Location).ProviderPath
                    $StartInfo.Environment['GIT_NO_LAZY_FETCH'] | Should -BeExactly '1'
                    $StartInfo.Environment['GIT_TERMINAL_PROMPT'] | Should -BeExactly '0'
                    foreach ($Key in @('GIT_ASKPASS', 'SSH_ASKPASS', 'GIT_ALLOW_PROTOCOL')) { $StartInfo.Environment[$Key] | Should -BeExactly '' }
                    foreach ($Key in $Overrides) { $StartInfo.Environment.ContainsKey($Key) | Should -BeFalse; [Environment]::GetEnvironmentVariable($Key) | Should -BeExactly 'fixture-routing-override' }
                }
                ($script:GitCalls[-1].ArgumentList | Select-Object -Last 3) -join '|' | Should -BeExactly ('cat-file|-e|' + ('a' * 40) + '^{commit}')
            }
            finally { foreach ($Key in $Overrides) { [Environment]::SetEnvironmentVariable($Key, $Saved[$Key]) } }
        }

        It 'Normalizes one local origin decoration <Origin>' -ForEach @(
            @{ Origin = 'https://github.com/CONTOSO/service/' }, @{ Origin = 'https://github.com/Contoso/SERVICE.git' }, @{ Origin = 'https://github.com/contoso/service' }
        ) {
            $script:GitOrigin = $Origin
            (Get-SquadLocalContext).Repository | Should -BeExactly 'https://github.com/contoso/service'
        }

        It 'Rejects unsupported local context <Case>' -ForEach @(
            @{ Case = 'two-origins'; Origin = "https://github.com/contoso/service`nhttps://github.com/contoso/other" },
            @{ Case = 'ssh'; Origin = 'git@github.com:contoso/service.git' },
            @{ Case = 'credentials'; Origin = 'https://user:secret@github.com/contoso/service' },
            @{ Case = 'two-decorations'; Origin = 'https://github.com/contoso/service.git/' },
            @{ Case = 'empty'; Origin = '' }, @{ Case = 'port'; Origin = 'https://github.com:443/contoso/service' }
        ) {
            $script:GitOrigin = $Origin
            { Get-SquadLocalContext } | Should -Throw '*offline-git-unavailable*'
        }

        It 'Rejects a current directory below the Git top level' {
            $script:GitRoot = [IO.Path]::GetDirectoryName((Get-Location).ProviderPath)
            { Get-SquadLocalContext } | Should -Throw '*offline-git-unavailable*'
        }

        It 'Rejects unsupported Git without a weaker fallback' {
            $script:GitFailure = '--version'
            { Get-SquadLocalContext } | Should -Throw '*offline-git-unavailable*'
            $script:GitCalls.Count | Should -Be 1
        }

        It 'Rejects missing local commit through the production isolated construction' {
            $script:GitFailure = 'cat-file'
            { Invoke-SquadGit Commit -Revision ('a' * 40) } | Should -Throw '*offline-git-unavailable*'
            $script:GitCalls.Count | Should -Be 1
            $script:GitCalls[0].ArgumentList[0] | Should -BeExactly '--no-lazy-fetch'
        }

        It 'Rejects process launch failure without exposing child output' {
            Mock Invoke-SquadGitProcess { throw 'private process failure' }
            { Get-SquadLocalContext } | Should -Throw '*offline-git-unavailable*'
        }

        It 'Rejects revision expressions before spawning any process' {
            { Invoke-SquadGit Commit -Revision 'HEAD^{commit}' } | Should -Throw '*revision*'
            Should -Invoke Invoke-SquadGitProcess -Times 0 -Exactly
        }
    }
}

Describe 'Exchange template records' -Tag 'Unit', 'Protocol' {
    InModuleScope Test-SquadRepoExchange {
        It 'Validates all concrete examples and their exact byte bindings' {
            $ModuleRoot = [IO.Path]::GetDirectoryName((Get-Module Test-SquadRepoExchange).Path)
            $Text = [IO.File]::ReadAllText([IO.Path]::GetFullPath('../references/federation-templates.md', $ModuleRoot))
            $Section = $Text.Substring($Text.IndexOf('## Advisory Exchange Examples', [StringComparison]::Ordinal))
            $Blocks = [regex]::Matches($Section, '(?ms)^```json\r?\n(.*?)\r?\n```')
            $Blocks.Count | Should -Be 7
            $Examples = @{}
            foreach ($Block in $Blocks) {
                $Bytes = [Text.Encoding]::UTF8.GetBytes($Block.Groups[1].Value)
                $Value = ConvertFrom-SquadJsonBytes $Bytes
                $Type = if ($Value.ContainsKey('kind')) { @{ 'squad-repo-task' = 'Packet'; 'squad-repo-receipt' = 'Receipt'; 'squad-repo-intake' = 'Intake'; 'squad-repo-claim' = 'Claim'; 'squad-repo-audit' = 'Audit'; 'squad-repo-commit' = 'Commit' }[$Value.kind] } else { 'State' }
                if ($Type -ne 'State') { { Assert-SquadShape $Value $Type } | Should -Not -Throw }
                $Examples[$Type] = @{ Value = $Value; Hash = Get-SquadByteHash $Bytes }
            }
            foreach ($Type in @('Receipt', 'Intake', 'Claim', 'Audit', 'Commit')) { $Examples[$Type].Value.packetSha256 | Should -BeExactly $Examples.Packet.Hash }
            foreach ($Ref in $Examples.Audit.Value.artifacts) {
                $Type = if ($Ref.path.EndsWith('/packet.json')) { 'Packet' } elseif ($Ref.path.EndsWith('/intake.json')) { 'Intake' } else { 'Claim' }
                $Ref.sha256 | Should -BeExactly $Examples[$Type].Hash
            }
            $Examples.Commit.Value.auditSha256 | Should -BeExactly $Examples.Audit.Hash
            $Examples.Commit.Value.stateAdvance.stateSha256 | Should -BeExactly $Examples.State.Hash
            $Examples.Receipt.Value.evidence[0].sha256 | Should -BeExactly (Get-SquadByteHash ([Text.Encoding]::UTF8.GetBytes('compatibility result')))
            $Examples.Receipt.Value.evidence[1].sha256 | Should -BeExactly (Get-SquadByteHash ([Text.Encoding]::UTF8.GetBytes("# History: Squad Scribe`n`n### Recorded local work`n")))
        }
    }
}

if ($PluginRoot) {
    Describe 'Offline exchange package' -Tag 'Unit', 'Package' {
        BeforeAll {
            $PackageSkill = Join-Path $PluginRoot 'skills/squad'
            $PackageModulePath = Join-Path $PackageSkill 'scripts/Test-SquadRepoExchange.psm1'
            Remove-Module Test-SquadRepoExchange -Force -ErrorAction SilentlyContinue
            $PackageModule = Import-Module $PackageModulePath -Force -PassThru
            $PackageScratch = Join-Path $SourceRoot ('.copilot-tracking/sandbox/2026-09-08/cross-repo-federation/package-' + [guid]::NewGuid().ToString('D'))
            $PackagePacketPath = '.copilot-tracking/squad/exchanges/staging/22222222-2222-4222-8222-222222222222/packet.json'
            $Templates = [IO.File]::ReadAllText((Join-Path $PackageSkill 'references/federation-templates.md'))
            $Examples = $Templates.Substring($Templates.IndexOf('## Advisory Exchange Examples', [StringComparison]::Ordinal))
            $PacketJson = [regex]::Match($Examples, '(?ms)^```json\r?\n(.*?)\r?\n```').Groups[1].Value
            $PacketValue = & $PackageModule { param($Json) ConvertFrom-SquadJsonBytes ([Text.Encoding]::UTF8.GetBytes($Json)) } $PacketJson
        }

        It 'Loads the copied module and preserves its bytes' {
            $PathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
            $PackageModule.Path.Equals([IO.Path]::GetFullPath($PackageModulePath), $PathComparison) | Should -BeTrue
            (Get-FileHash -LiteralPath $PackageModulePath).Hash | Should -BeExactly (Get-FileHash -LiteralPath (Join-Path $SourceRoot 'squad-src/.github/skills/squad/scripts/Test-SquadRepoExchange.psm1')).Hash
            $PackageModule.ExportedFunctions.Keys | Should -BeExactly 'Test-SquadRepoExchange'
        }

        It 'Executes the copied public validator on a <Case> staged packet' -ForEach @(
            @{ Case = 'valid'; Expected = $true }, @{ Case = 'invalid'; Expected = $false }
        ) {
            $Candidate = Join-Path $PackageScratch $PackagePacketPath
            $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Candidate))
            $Json = $PacketJson
            if (-not $Expected) {
                $Changed = $Json | ConvertFrom-Json -AsHashtable
                $Changed.schemaVersion = '2.0'
                $Json = $Changed | ConvertTo-Json -Depth 10 -Compress
            }
            [IO.File]::WriteAllText($Candidate, $Json, [Text.UTF8Encoding]::new($false))
            InModuleScope Test-SquadRepoExchange -Parameters @{ TopLevel = $PackageScratch; Packet = $PacketValue; PacketPath = $PackagePacketPath; Expected = $Expected } {
                param($TopLevel, $Packet, $PacketPath, $Expected)
                $script:PackageContext = [pscustomobject]@{ TopLevel = $TopLevel; Repository = $Packet.sourceRepository; Head = $Packet.sourceRevision }
                $script:PackageNow = [DateTimeOffset]::Parse($Packet.createdAt).AddHours(1)
                Mock Get-SquadLocalContext { $script:PackageContext }
                Mock Get-SquadClock { $script:PackageNow }
                $Result = Test-SquadRepoExchange -Operation Issue -PacketPath $PacketPath
                $Result.Valid | Should -Be $Expected -Because ($Result.Errors -join ',')
                $Result.Code | Should -Be $(if ($Expected) { 'valid' } else { 'invalid' })
            }
            Test-Path -LiteralPath (Join-Path $PackageScratch '.copilot-tracking/squad/exchanges/outbox') | Should -BeFalse
        }

        It 'Delivers and resolves links in <Reference>' -ForEach @(
            @{ Reference = 'repo-exchange.md' }, @{ Reference = 'federation-templates.md' },
            @{ Reference = 'federation.md' }, @{ Reference = 'scribe-procedure.md' }
        ) {
            $Path = Join-Path $PackageSkill "references/$Reference"
            Test-Path -LiteralPath $Path -PathType Leaf | Should -BeTrue
            $Content = [IO.File]::ReadAllText($Path)
            foreach ($Link in [regex]::Matches($Content, '\[[^\]]+\]\(([^)]+)\)')) {
                $Target = ($Link.Groups[1].Value -split '#', 2)[0]
                if (-not $Target -or $Target -match '^[a-z]+:') { continue }
                $Resolved = [IO.Path]::GetFullPath($Target, [IO.Path]::GetDirectoryName($Path))
                Test-Path -LiteralPath $Resolved -PathType Leaf | Should -BeTrue -Because "$Reference links $Target"
            }
        }

        It 'Delivers all seven concrete exchange example records' {
            [regex]::Matches($Examples, '(?ms)^```json\r?\n(.*?)\r?\n```').Count | Should -Be 7
        }

        It 'Delivers <Agent> within the existing 30000-character body cap and with protocol loading' -ForEach @(
            @{ Agent = 'squad-coordinator' }, @{ Agent = 'squad-federation-coordinator' }, @{ Agent = 'squad-scribe' }
        ) {
            $Raw = [IO.File]::ReadAllText((Join-Path $PluginRoot "agents/squad/$Agent.agent.md"))
            $Body = [regex]::Replace($Raw, '\A---\r?\n.*?\r?\n---\r?\n', '', [Text.RegularExpressions.RegexOptions]::Singleline)
            $Body.Length | Should -BeLessOrEqual 30000
            $Body | Should -Match 'references/repo-exchange.md'
            $Body | Should -Match 'scripts/Test-SquadRepoExchange.psm1'
        }

        It 'Forwards generated <Invocation> arguments and conditional gates' -ForEach @(
            @{ Invocation = 'squad-run'; Arguments = @('handoff', 'exchange', 'squadRoot') },
            @{ Invocation = 'squad-federation'; Arguments = @('exchange', 'repo', 'task', 'revision', 'receipt', 'squad') }
        ) {
            $Content = Get-Content -LiteralPath (Join-Path $PackageSkill "invocations/$Invocation/SKILL.md") -Raw
            foreach ($Argument in $Arguments) {
                ($Content -split '## Flow', 2)[1] | Should -Match ([regex]::Escape('**' + $Argument + '**'))
            }
            $Content | Should -Match 'references/repo-exchange.md'
            $Content | Should -Match 'before Init|before any mode or member-tree branch'
            $Content | Should -Match 'target-local gates remain authoritative|separate current human attestation'
        }

        AfterAll {
            if (Test-Path -LiteralPath $PackageScratch) { Remove-Item -LiteralPath $PackageScratch -Recurse -Force }
        }
    }
}

AfterAll {
    Remove-Module Test-SquadRepoExchange -Force -ErrorAction SilentlyContinue
}