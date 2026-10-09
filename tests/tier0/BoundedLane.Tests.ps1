#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Static wording pins for the bounded lane, plan-driven parallelism, and the dispatch brief.
# All three are economy-only (interactive mode, `Model routing: economy`), so their text lives
# only in the cold references/economy-mode.md and never in a file a default run reads. Each
# assertion quotes text shipped in squad-src; this proves the contract still reads the way it
# must, never that a model turn
# obeys it.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeDiscovery {
    # Rows with Flagged=$false must pass: a negated clause is exempt, but never a permission clause that follows it.
    $script:GuardCases = @(
        @{ Name = 'may edit directly'; Flagged = $true; Sentence = 'In the bounded lane the coordinator may edit the target file directly.' }
        @{ Name = 'yourself instead of dispatching'; Flagged = $true; Sentence = 'In the bounded lane, apply a one-line change yourself instead of dispatching.' }
        @{ Name = 'passive by the coordinator'; Flagged = $true; Sentence = 'For a bounded request the owning role''s work may be done by the coordinator.' }
        @{ Name = 'can author and skip review'; Flagged = $true; Sentence = 'In the bounded lane the coordinator can author the change and skip review.' }
        @{ Name = 'unqualified inline permission'; Flagged = $true; Sentence = 'For a fully specified one-line change you may apply it yourself.' }
        @{ Name = 'permitted to write'; Flagged = $true; Sentence = 'Within the lane, the coordinator is permitted to write the fix itself.' }
        @{ Name = 'permission after a negated clause'; Flagged = $true; Sentence = 'The bounded lane does not waive dispatch, but the coordinator may edit the file directly.' }
        @{ Name = 'subject-omitted modal after a negated clause'; Flagged = $true; Sentence = 'The lane does not waive dispatch, but may edit the file directly.' }
        @{ Name = 'safe negation then non-work verb (negative)'; Flagged = $false; Sentence = 'The coordinator does not waive dispatch, but may report the result.' }
        @{ Name = 'never edits (negative)'; Flagged = $false; Sentence = 'In the bounded lane the coordinator never edits the target file.' }
        @{ Name = 'owner dispatched (negative)'; Flagged = $false; Sentence = 'The owning role is always dispatched, never inline, and tester still closes.' }
    )
}

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
    $script:Floor = @($script:Model.Instructions | Where-Object Name -eq 'squad-floor.instructions.md')[0]
    $script:Routing = @($script:Model.Instructions | Where-Object Name -eq 'squad-routing.instructions.md')[0]
    $script:Gates = Get-SquadReferenceBody -Name 'gates-and-modes.md'
    $script:OperatingProcedure = Get-SquadReferenceBody -Name 'operating-procedure.md'
    $script:Economy = Get-SquadReferenceBody -Name 'economy-mode.md'
    $script:BoundedLane = Get-Section -Body $script:Economy -Heading '## Bounded Lane'
    $script:HotTexts = [ordered]@{
        'squad-coordinator.agent.md'      = $script:Coordinator.Body
        'squad-implementor.agent.md'      = (Get-Agent 'squad-implementor.agent.md').Body
        'squad-technical-writer.agent.md' = (Get-Agent 'squad-technical-writer.agent.md').Body
        'squad-floor.instructions.md'     = $script:Floor.Body
        'squad-routing.instructions.md'   = $script:Routing.Body
        'squad-autopilot.instructions.md' = @($script:Model.Instructions | Where-Object Name -eq 'squad-autopilot.instructions.md')[0].Body
        'gates-and-modes.md'              = $script:Gates
        'operating-procedure.md'          = $script:OperatingProcedure
    }
}

Describe 'Bounded lane wording pins (RTE-38 to RTE-41)' {
    It 'requires every criterion to hold at once and states each one' {
        $script:BoundedLane | Should -Match ([regex]::Escape('only when **all** of these hold'))
        $script:BoundedLane | Should -Match ([regex]::Escape('names the exact target files or artifacts and the exact change'))
        $script:BoundedLane | Should -Match ([regex]::Escape('no open questions or unknowns'))
        $script:BoundedLane | Should -Match ([regex]::Escape('single owning role'))
        $script:BoundedLane | Should -Match ([regex]::Escape('disjoint write sets'))
        $script:BoundedLane | Should -Match ([regex]::Escape('No Impactful-Action Gate or Risk Gate trigger applies'))
        $script:BoundedLane | Should -Match ([regex]::Escape('no intake or discovery gate trigger applies'))
    }

    It 'uses the #144 task-fit council lenses for the council criterion' {
        $script:BoundedLane | Should -Match ([regex]::Escape('It engages no council lens: it touches none of architecture, security, cost, product-fit, or RAI (the task-fit lenses in `gates-and-modes.md` *Council Procedure*)'))
        $script:BoundedLane | Should -Match ([regex]::Escape('A request that would need a council, an extension, or a waiver is never bounded.'))
        $script:Gates | Should -Match ([regex]::Escape('The coordinator dispatches a **task-fit** council in a single parallel batch'))
        $script:BoundedLane | Should -Not -Match '(?i)council domain is crossed'
    }

    It 'waives only Research and Plan: any doubt, pipeline=full, unattended modes, and Watch keep the full pipeline' {
        $script:BoundedLane | Should -Match ([regex]::Escape('Interactive mode only (no `mode=`).'))
        $script:BoundedLane | Should -Match ([regex]::Escape('Under economy the lane waives **only** those two stages'))
        $script:BoundedLane | Should -Match ([regex]::Escape('**Any doubt means the full pipeline.**'))
        $script:BoundedLane | Should -Match ([regex]::Escape('`pipeline=full` forces it, and `mode=autonomous`, `mode=autopilot`, and Watch Mode never use the lane'))
    }

    It 'never lets the coordinator work inline and keeps review and Scribe recording' {
        $script:BoundedLane | Should -Match ([regex]::Escape('still dispatches the owning role through `runSubagent` or `task`, never inline'))
        $script:BoundedLane | Should -Match ([regex]::Escape('still dispatches `tester` as the closing stage'))
        $script:BoundedLane | Should -Match ([regex]::Escape('The decision entry records `Route: bounded` and each criterion'))
    }

    It 'never picks a model and names no model id' {
        $script:BoundedLane | Should -Match ([regex]::Escape('The lane never changes which model a dispatch runs on.'))
        $script:BoundedLane | Should -Not -Match '(?i)\b(gpt|claude|gemini|kimi)-[0-9a-z.-]+'
    }

    It 'leaves every hot file at its v0.18.0 methodology text: <_>' -ForEach @(
        'squad-coordinator.agent.md', 'squad-implementor.agent.md', 'squad-technical-writer.agent.md', 'squad-floor.instructions.md',
        'squad-routing.instructions.md', 'squad-autopilot.instructions.md', 'gates-and-modes.md', 'operating-procedure.md'
    ) {
        $text = $script:HotTexts[$_]
        $text | Should -Not -BeNullOrEmpty
        $text | Should -Not -Match '(?i)bounded lane|Route: bounded|pipeline=full|Plan-Driven Parallelism|deliverable-fan-out plan|Get-SquadDispatchBrief|blocked: not bounded' -Because "$_ is read on every default run"
    }

    It 'no always-on text or the cold file permits the coordinator to author, edit, or work inline (lexical guard)' {
        $texts = @($script:HotTexts.Values) + $script:Economy
        $offending = foreach ($text in $texts) { Find-InlineWorkPermission -Text $text }
        @($offending).Count | Should -Be 0 -Because "text must never let the coordinator work inline: $(@($offending) -join ' | ')"
    }

    It 'the guard flags <Name> and passes the negatives (lexical only)' -ForEach $script:GuardCases {
        $caught = @(Find-InlineWorkPermission -Text "The owning role is dispatched. $Sentence")
        ($caught.Count -gt 0) | Should -Be $Flagged -Because "'$Sentence' should $(if ($Flagged) { '' } else { 'not ' })be flagged; got: $($caught -join ' | ')"
    }
}

Describe 'Bounded owner brief (RTE-38)' {
    It 'names the write set, change, validation, and change record, allows a reference search, and returns blocked: not bounded' {
        $script:BoundedLane | Should -Match ([regex]::Escape('carries its full write set (every file and directory it may touch)'))
        $script:BoundedLane | Should -Match ([regex]::Escape('the exact change, the validation command, the change-record path'))
        $script:BoundedLane | Should -Match ([regex]::Escape('you may search for references to any symbol, heading, or link you change'))
        $script:BoundedLane | Should -Match ([regex]::Escape('return "blocked: not bounded" without editing it'))
        $script:BoundedLane | Should -Match ([regex]::Escape('The owner still follows the repository coding-standards instructions, runs the validation, and writes the change record last'))
        $script:BoundedLane | Should -Match ([regex]::Escape('The closing review runs only after every owner''s final message'))
    }
}

Describe 'Dispatch brief contract (RTE-43)' {
    It 'economy-mode.md describes the brief and its coverage line' {
        $brief = Get-Section -Body $script:Economy -Heading '## Dispatch Brief'
        $brief | Should -Match ([regex]::Escape('`scripts/Get-SquadDispatchBrief.ps1 -SquadRoot <root> -SessionModel <id>`'))
        $brief | Should -Match ([regex]::Escape('When its `coverage:` line covers the request, the coordinator reads no further reference, agent file, or rate table that turn'))
    }

    It 'the coordinator body stays within the 30,000-character cap' {
        ($script:Coordinator.Body -replace "`r`n", "`n").Length | Should -BeLessOrEqual 30000
    }
}

Describe 'Plan-driven parallelism wording pins (RTE-42)' {
    BeforeAll {
        $script:Parallelism = Get-Section -Body $script:Economy -Heading '## Plan-Driven Parallelism'
    }

    It 'applies to a deliverable-fan-out plan or a bounded request with disjoint write sets shown by it, never by budget' {
        $script:Parallelism | Should -Match ([regex]::Escape('Interactive mode only (no `mode=`).'))
        $script:Parallelism | Should -Match ([regex]::Escape('`Implement Shape` is `deliverable-fan-out`'))
        $script:Parallelism | Should -Match ([regex]::Escape('a bounded request lists independent items'))
        $script:Parallelism | Should -Match ([regex]::Escape('their write sets are disjoint'))
        $script:Parallelism | Should -Match ([regex]::Escape('budget is never a reason'))
        $script:Parallelism | Should -Match ([regex]::Escape('When disjointness is unproven, dispatch sequentially'))
    }

    It 'confirms once per batch, never batches an escalate-tier owner, and leaves the Scribe rules unchanged' {
        $script:Parallelism | Should -Match ([regex]::Escape('confirmation once for the batch'))
        $script:Parallelism | Should -Match ([regex]::Escape('listing every owner, its tier, and its write set; an `escalate`-tier owner is never batched'))
        $script:Parallelism | Should -Match ([regex]::Escape('Scribe single-writer, one hand-off per stage, and per-stage `history/<agent>.md` entries are unchanged'))
    }

    It 'RTE-21 keeps its v0.18.0 text and RTE-42 is economy-only' {
        $contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../squad-behavior-contract.md') -Raw
        [regex]::Match($contract, '(?m)^\| RTE-21 \|.*$').Value | Should -Not -Match '(?i)fan-out|bounded'
        [regex]::Match($contract, '(?m)^\| RTE-42 \|.*$').Value | Should -Match ([regex]::Escape('**Plan-driven parallelism (economy only).**'))
    }
}
