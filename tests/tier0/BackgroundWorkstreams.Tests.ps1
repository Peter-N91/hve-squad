#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Static wording pins for background workstreams (`delivery=background`, economy-only and
# interactive-only) and the Squad Workstream Lead. The procedure lives only in the cold
# references/economy-mode.md. Each assertion quotes text shipped in squad-src; this proves
# the contract still reads the way it must, never that a model turn obeys it. The hand-off
# script's workstream fields are exercised in WriteSquadHandoff.Tests.ps1.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot

    function Find-InlineWorkPermission {
        <#
        .SYNOPSIS
            Lexical guard, not a proof of model behavior: returns clauses that grant the coordinator
            permission to do the owning role's work or to skip its dispatch.
        #>
        param([Parameter(Mandatory)][string]$Text)
        $verbs = 'author|edit|write|implement|apply|produce|perform|fix|patch|modify|do'
        $negation = "(?i)\b(never|not|no|nor|cannot|can't|don't|doesn't|won't|neither)\b"
        $patterns = @(
            "(?i)\b(coordinator|you)\s+(may|can|could|might|is permitted to|are permitted to|is allowed to|are allowed to|is free to|are free to)\s+(also\s+|still\s+|then\s+)?($verbs)\b"
            "(?i)\b(permitted|allowed|authori[sz]ed|free)\s+to\s+($verbs)\b"
            "(?i)\b($verbs)\b[^;:]{0,80}\byourself\b"
            "(?i)\b(done|authored|implemented|applied|performed|written|handled|made|fixed|edited)\s+(inline\s+)?by\s+the\s+coordinator\b"
            "(?i)\b(skip|skips|waive|waives|bypass|bypasses)\s+(the\s+)?(dispatch|dispatching|tester|review|owning role)"
            "(?i)\b(may|can)\s+(be\s+)?(done\s+|authored\s+|implemented\s+|applied\s+)?inline\b"
            "(?i)^\s*(?:(?:but|and|so|then)\s+)?(may|can|could|might|is permitted to|is allowed to)\s+(also\s+|still\s+|then\s+)?($verbs)\b"
        )
        foreach ($sentence in ($Text -split '(?<=[.!?])\s+|\r?\n')) {
            foreach ($clause in ($sentence -split '[;,:]\s+|\s+(?:and|but|or)\s+')) {
                foreach ($pattern in $patterns) {
                    $m = [regex]::Match($clause, $pattern)
                    if (-not $m.Success) { continue }
                    if ([regex]::IsMatch($clause.Substring(0, $m.Index + $m.Length), $negation)) { continue }
                    $clause.Trim()
                    break
                }
            }
        }
    }

    function Get-SquadReferenceBody {
        param([Parameter(Mandatory)][string]$Name)
        Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot "references/$Name") -Raw
    }

    function Get-Section {
        param([Parameter(Mandatory)][string]$Body, [Parameter(Mandatory)][string]$Heading)
        $level = ($Heading -split ' ')[0].Length
        $pattern = '(?ms)^' + [regex]::Escape($Heading) + '\s*$.*?(?=^#{1,' + $level + '} |\z)'
        [regex]::Match($Body, $pattern).Value
    }

    function Get-Agent {
        param([Parameter(Mandatory)][string]$Name)
        @($script:Model.SquadAgents | Where-Object Name -eq $Name)[0]
    }

    $script:Coordinator = Get-Agent 'squad-coordinator.agent.md'
    $script:Lead = Get-Agent 'squad-workstream-lead.agent.md'
    $script:Gates = Get-SquadReferenceBody -Name 'gates-and-modes.md'
    $script:Economy = Get-SquadReferenceBody -Name 'economy-mode.md'
    $script:BgText = Get-Section -Body $script:Economy -Heading '## Background Workstreams'
}

Describe 'Squad Workstream Lead charter (RTE-51)' {
    It 'exists, is not user-invocable, carries the Squad Lead''s pin, and declares no tools so its children keep their own' {
        $script:Lead | Should -Not -BeNullOrEmpty
        $script:Lead.Meta['name'] | Should -Be 'Squad Workstream Lead'
        $script:Lead.Meta['user-invocable'] | Should -Be 'false'
        $script:Lead.Meta.ContainsKey('tools') | Should -BeFalse
        $script:Lead.Meta['model'] | Should -Be (Get-Agent 'squad-lead.agent.md').Meta['model']
        @($script:Lead.Meta['agents']) | Should -Not -Contain 'Squad Scribe'
        @($script:Lead.Meta['agents']) | Should -Not -Contain 'Squad Deployer'
        $script:Lead.Body.Length | Should -BeLessOrEqual 30000
    }

    It 'can dispatch every tester alternate, QA, and the producing roles, each also known to the coordinator' {
        $catalog = Get-SquadReferenceBody -Name 'roster-catalog.md'
        $testerRow = @($catalog -split "`n" | Where-Object { $_ -match '^\| tester ' -and $_ -match 'Code Review Walkback' })[0]
        $alternates = @((($testerRow -split '\|') | Where-Object { $_ -match 'Code Review Functional' })[0].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $alternates.Count | Should -BeGreaterOrEqual 7
        $leadAgents = @($script:Lead.Meta['agents'])
        foreach ($name in $alternates + @('QA', 'Squad Implementor', 'Squad Reviewer', 'Squad Technical Writer', 'Squad Data Scientist')) { $leadAgents | Should -Contain $name }
        foreach ($name in $leadAgents) { @($script:Coordinator.Meta['agents']) | Should -Contain $name }
    }

    It 'forwards briefs verbatim, sends one final message, writes no squad state, and never works inline' {
        $script:Lead.Body | Should -Match ([regex]::Escape('Forward each owner''s brief to that owner VERBATIM.'))
        $script:Lead.Body | Should -Match ([regex]::Escape('your single final message is the report'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Never write squad state: no `history/`, `decisions.md`, `state.json`, `consumption.md`, `team.md`, or Scribe file, and never run `Write-SquadHandoff.ps1` or dispatch the Squad Scribe.'))
        $script:Lead.Body | Should -Match ([regex]::Escape('the coordinator hands your workstream''s payload to the Squad Scribe, the only writer, which runs the script'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Never do role work inline.'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Never perform an impactful action'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Dispatch the closing review only when every owner reply names its files changed, its validation result, and a change record ending `Status: complete`'))
        $script:Lead.Meta['description'] | Should -Match ([regex]::Escape('under routing=economy (references/economy-mode.md)'))
        $script:Lead.Body | Should -Match ([regex]::Escape('by the reviewer agent the coordinator named in your brief'))
        @(Find-InlineWorkPermission -Text $script:Lead.Body) | Should -BeNullOrEmpty
    }

    It 'copies each owner''s Model cell as written under any routing mode that writes it, and never picks a model' {
        $script:Lead.Body | Should -Match ([regex]::Escape('Under `ranked`, `manual`, or any routing mode that writes the `Model` cell, pass that cell as the dispatch `model` for that owner and for the closing reviewer, as the coordinator does'))
        $script:Lead.Body | Should -Match ([regex]::Escape('with no cell value, pass no `model`, so the agent runs on its own pin'))
        $script:Lead.Body | Should -Match ([regex]::Escape('Never pick, rank, or lower a model yourself'))
        $script:Lead.Body | Should -Not -Match '(?i)bounded pick|boundedPick|(?<![a-z])-Bounded\b'
        $script:Lead.Body | Should -Not -Match '(?i)\b(claude|gpt-|gemini|grok)'
    }
}

Describe 'Coordinator entry points for background workstreams (RTE-51)' {
    It 'lists the lead in the coordinator''s agents but carries no background procedure in any hot file' {
        @($script:Coordinator.Meta['agents']) | Should -Contain 'Squad Workstream Lead'
        $hot = @($script:Coordinator.Body, $script:Gates, (Get-SquadReferenceBody -Name 'operating-procedure.md'), (Get-SquadReferenceBody -Name 'scribe-payload-template.md'))
        foreach ($text in $hot) { $text | Should -Not -Match '(?i)delivery=background|Background Workstreams|leadConsumption|launchedAt' }
        $script:Coordinator.Body.Length | Should -BeLessOrEqual 30000
    }

    It 'tells a non-economy coordinator, in the /squad prompt, that delivery=background is economy-only and ignored otherwise (W2)' {
        $prompt = @($script:Model.Prompts | Where-Object Name -eq 'squad.prompt.md')[0]
        $prompt.Meta['argument-hint'] | Should -Match ([regex]::Escape('[delivery=background]'))
        $prompt.Body | Should -Match ([regex]::Escape('* ${input:delivery}: (Optional) `background`: economy only (`references/economy-mode.md`); any other mode ignores it and says so once.'))
        $prompt.Body | Should -Not -Match '(?i)Background Workstreams Launched|leadConsumption|launchedAt'
    }

    It 'mentions the Workstream Lead only in economy-mode.md, its own charter, and the coordinator agents list (W3)' {
        $allowed = @('economy-mode.md', 'squad-workstream-lead.agent.md', 'squad-coordinator.agent.md')
        $roots = @(
            (Join-Path $PackageRoot '.github/agents'), (Join-Path $PackageRoot '.github/prompts'), (Join-Path $PackageRoot '.github/instructions'),
            (Join-Path $script:Model.SquadSkillRoot 'references')
        )
        $files = @($roots | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File -Filter '*.md' }) + @(Get-Item -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'SKILL.md'))
        $files.Count | Should -BeGreaterThan 20
        $mentions = @($files | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?i)Workstream Lead' } | ForEach-Object Name | Sort-Object -Unique)
        foreach ($name in $mentions) { $name | Should -BeIn $allowed -Because "$name is read outside economy and must not carry Workstream Lead text" }
        $script:Coordinator.Body | Should -Not -Match '(?i)Workstream Lead' -Because 'the coordinator names it only in its agents: frontmatter'
        $repo = Join-Path $PSScriptRoot '../..'
        (Get-Content -LiteralPath (Join-Path $repo 'apm.yml') -Raw) | Should -Match ([regex]::Escape('squad-workstream-lead.agent.md'))
    }

    It 'holds read_agent whenever it declares a tools list' {
        if ($script:Coordinator.Meta.ContainsKey('tools')) { @($script:Coordinator.Meta['tools']) | Should -Contain 'read_agent' }
    }
}

Describe 'Background Workstreams in economy-mode.md (RTE-51 to RTE-53)' {
    It 'is economy-only and interactive-only, and keeps the Scribe the only writer' {
        $script:BgText | Should -Match ([regex]::Escape('`delivery=background` is honored only under economy and only in interactive mode (no `mode=`; never autonomous, autopilot, or Watch Mode). Under any other routing mode the input is ignored and the coordinator says so once.'))
        $script:BgText | Should -Match ([regex]::Escape('the Squad Scribe stays the only writer'))
    }

    It 'runs sequentially in the foreground on VS Code' {
        $script:BgText | Should -Match ([regex]::Escape('VS Code has neither: there, run the same workstreams one at a time in the foreground'))
    }

    It 'runs coordinator-only gates in the foreground and backgrounds only bounded or planned workstreams' {
        $script:BgText | Should -Match ([regex]::Escape('Run every coordinator-only gate in the foreground before any launch: discovery, intake, council, Cost Preflight, the Risk Gate, and routing tiers'))
        $script:BgText | Should -Match ([regex]::Escape('only when it qualifies for the *Bounded Lane* or already has a confirmed plan artifact on disk'))
        $script:BgText | Should -Match ([regex]::Escape('returns for a second approval before any implementation'))
        $script:BgText | Should -Match ([regex]::Escape('An `escalate`-tier owner, or a Risk Gate or Impactful-Action Gate trigger, keeps that workstream in the foreground'))
        $script:BgText | Should -Match ([regex]::Escape('With an effective Cost Preflight ceiling, run the workstreams sequentially and say so.'))
    }

    It 'requires an independent named reviewer and the lead''s agents list, else the foreground' {
        $script:BgText | Should -Match ([regex]::Escape('the reviewer must differ from every owner'))
        $script:BgText | Should -Match ([regex]::Escape('every owner and the reviewer must be in its `agents:` list. Otherwise the workstream runs in the foreground.'))
        $script:BgText | Should -Match ([regex]::Escape('A bounded workstream needs no lead: the coordinator dispatches its owner and reviewer directly.'))
        $script:BgText | Should -Match ([regex]::Escape('copies each owner''s `Model` cell, picks no model'))
    }

    It 'takes one approval, records the launch, and launches in one block under the concurrency cap' {
        $script:BgText | Should -Match ([regex]::Escape('Present one confirmation listing every workstream'))
        $script:BgText | Should -Match ([regex]::Escape('hand the Scribe a decision headed `## Background Workstreams Launched`'))
        $script:BgText | Should -Match ([regex]::Escape('a workstream is never in flight without it'))
        $script:BgText | Should -Match ([regex]::Escape('`COPILOT_SUBAGENT_MAX_CONCURRENT`, else 4'))
        $script:BgText | Should -Match ([regex]::Escape('its `Model` cell as `model` exactly as written (none without one)'))
        @(Find-InlineWorkPermission -Text $script:BgText) | Should -BeNullOrEmpty
    }

    It 'verifies artifacts on disk, records each result through the script, and recovers after an interruption' {
        $script:BgText | Should -Match ([regex]::Escape('read the verdict from that artifact, never from a message'))
        $script:BgText | Should -Match ([regex]::Escape('leaves the workstream not delivered'))
        $script:BgText | Should -Match ([regex]::Escape('The script holds the squad root''s lock, so concurrent hand-offs are written one after the other'))
        $script:BgText | Should -Match ([regex]::Escape('`orchestration.leadConsumption` (`agent-pinned`)'))
        $script:BgText | Should -Match ([regex]::Escape('reads the latest `## Background Workstreams Launched` decision, finds each listed workstream id with no `* Workstream: <id>` history entry'))
        $script:BgText | Should -Match ([regex]::Escape('never re-launched silently'))
    }

    It 'records the agent ids after launch and recovers from disk first, never relaunching silently (W1)' {
        $script:BgText | Should -Match ([regex]::Escape('hand the Scribe a decision headed `## Background Workstreams Launched`'))
        $script:BgText | Should -Match ([regex]::Escape('Right after the launch block, hand the Scribe a second short decision headed `## Background Workstreams Agents` that maps each workstream id to the agent id the `task` tool returned'))
        $script:BgText | Should -Match ([regex]::Escape('9. **Recover, disk first.**'))
        $script:BgText | Should -Match ([regex]::Escape('runs step 7''s on-disk verification for each: every deliverable newer than `launchedAt`, each owner''s change record ending with `Status: complete`, and a review artifact holding a verdict'))
        $script:BgText | Should -Match ([regex]::Escape('`read_agent` is used only for agent ids recorded in `## Background Workstreams Agents` during the current session'))
        $script:BgText | Should -Match ([regex]::Escape('reported to the user as not delivered, with its partial files listed, and is never re-launched silently'))
        $script:BgText | Should -Not -Match ([regex]::Escape('checks the background agents still listed by `read_agent`'))
    }

    It 'names no model id and no bounded pick' {
        $script:BgText | Should -Not -Match '(?i)bounded pick|boundedPick|(?<![a-z])-Bounded\b'
        $script:BgText | Should -Not -Match '(?i)\b(claude|gpt-|gemini|grok)'
    }

    It 'the behavior contract carries RTE-51 to RTE-53 as economy-only' {
        $contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../squad-behavior-contract.md') -Raw
        $contract | Should -Match '(?m)^\| RTE-51 \| \*\*Background workstreams \(economy only\)\.\*\*'
        $contract | Should -Match '(?m)^\| RTE-52 \| \*\*Workstream hand-offs are serialized and proven\.\*\*'
        $contract | Should -Match '(?m)^\| RTE-53 \| \*\*Recovery after an interrupted session\.\*\* A `## Background Workstreams Agents` decision maps each workstream to its agent id'
        (Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'scripts/Write-SquadHandoff.ps1') -Raw) | Should -Match ([regex]::Escape("'leadConsumption'"))
    }
}
