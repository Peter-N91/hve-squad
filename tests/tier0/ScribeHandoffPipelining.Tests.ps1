#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# P03-T02/P03-T03 (routing-performance plan, Scribe Hand-off Pipelining, Amendment 3
# Unit U4): pins the pipelining contract text the prompt-engineer landed in Unit U3
# against the built plugin output, and pins that the pre-pipelining sequential-only
# wording it replaced does not resurface. GATE-22..GATE-28 in
# tests/squad-behavior-contract.md are this file's contract IDs.
#
# Every positive assertion below quotes text confirmed present in squad-src this
# session (git diff); every negative assertion quotes text confirmed removed by that
# same diff. This is a static text pin only -- it proves the contract still reads the
# way it must, never that a model turn obeys it.

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
        <#
        .SYNOPSIS
            Reads a squad skill reference file's raw text from the built package.
        .PARAMETER Name
            File name under references/, for example 'gates-and-modes.md'.
        #>
        param([Parameter(Mandatory)][string]$Name)
        $path = Join-Path $script:Model.SquadSkillRoot "references/$Name"
        return Get-Content -LiteralPath $path -Raw
    }

    $script:Coordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-coordinator.agent.md')[0]
    $script:AutopilotInstructions = @($script:Model.Instructions | Where-Object Name -eq 'squad-autopilot.instructions.md')[0]
    $script:FloorInstructions = @($script:Model.Instructions | Where-Object Name -eq 'squad-floor.instructions.md')[0]
    $script:StateInstructions = @($script:Model.Instructions | Where-Object Name -eq 'squad-state.instructions.md')[0]
    $script:FederationInstructions = @($script:Model.Instructions | Where-Object Name -eq 'squad-federation.instructions.md')[0]
    $script:FederationAutopilotInstructions = @($script:Model.Instructions | Where-Object Name -eq 'squad-federation-autopilot.instructions.md')[0]
    $script:WatchModeInstructions = @($script:Model.Instructions | Where-Object Name -eq 'squad-watch-mode.instructions.md')[0]
    $script:GatesAndModesBody = Get-SquadReferenceBody -Name 'gates-and-modes.md'
    $script:OperatingProcedureBody = Get-SquadReferenceBody -Name 'operating-procedure.md'
    $script:FederationReferenceBody = Get-SquadReferenceBody -Name 'federation.md'
}

Describe 'Scribe Hand-off Pipelining wording pins (GATE-22..GATE-28)' {

    Context 'Positive pins: the pipelining contract is present' {
        It 'coordinator carries a one-line pointer to the pipelining contract, at or under 200 chars' {
            $pointerLine = @($script:Coordinator.Body -split '\r?\n' | Where-Object { $_ -match 'Hand off to the Scribe once per stage' })
            $pointerLine.Count | Should -Be 1 -Because 'exactly one line in the coordinator body should carry this pointer'

            $pointerSentence = ($pointerLine[0] -split '`state\.json`')[0].TrimEnd()
            $pointerSentence.Length | Should -BeLessOrEqual 200 -Because 'R-8/Condition 2 caps the coordinator pointer at 200 chars so PKG-04 headroom is not spent restating the contract inline'
            $pointerLine[0] | Should -Match ([regex]::Escape('pipelining rules, barriers, and verification live in references/operating-procedure.md and references/gates-and-modes.md'))
        }

        It 'the pointer''s targets exist: both named sections are present in their reference files' {
            $script:OperatingProcedureBody | Should -Match '(?m)^### Scribe Hand-off Pipelining \(Autopilot\)\s*$'
            $script:GatesAndModesBody | Should -Match '(?m)^### Scribe Hand-off Pipelining: Enablement Predicate and Barriers\s*$'
        }

        It 'the Enablement Predicate defaults off and names the tool-schema host signal' {
            $script:GatesAndModesBody | Should -Match ([regex]::Escape('**Enablement Predicate (`PipeliningEnabled`, default OFF).**'))
            $script:GatesAndModesBody | Should -Match ([regex]::Escape("the coordinator's own dispatch tool advertises a background or asynchronous execution mode in its tool schema"))
            $script:GatesAndModesBody | Should -Match ([regex]::Escape('Copilot CLI'))
            $script:GatesAndModesBody | Should -Match ([regex]::Escape('mode: background'))
        }

        It 'a configured cost ceiling latches pipelining off for the rest of the run id' {
            $script:GatesAndModesBody | Should -Match ([regex]::Escape('no cost ceiling has been configured at any point in this run id (latched'))
            $script:AutopilotInstructions.Body | Should -Match ([regex]::Escape('Configuring any cost ceiling at any point in a run disables Scribe hand-off pipelining for the rest of that run id (latched)'))
        }

        It 'excludes Watch Mode, the federation root, and an untargeted aggregate-ceiling inner run' {
            $script:GatesAndModesBody | Should -Match ([regex]::Escape('not Watch Mode'))
            $script:GatesAndModesBody | Should -Match ([regex]::Escape('not the federation root; not an inner run under untargeted federation autopilot with an aggregate ceiling'))
            $script:WatchModeInstructions.Body | Should -Match ([regex]::Escape('Scribe hand-off pipelining stays off.'))
            $script:FederationAutopilotInstructions.Body | Should -Match ([regex]::Escape('keeps every selected inner run''s Scribe hand-off pipelining disabled for its duration'))
            $script:FederationReferenceBody | Should -Match ([regex]::Escape('an inner run under an untargeted aggregate ceiling stays sequential'))
        }

        It 'single-writer invariant: at most one Scribe hand-off in flight per squad root, queued in stage order' {
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape('At most one Scribe call is ever included in a parallel block.'))
            $script:FloorInstructions.Body | Should -Match ([regex]::Escape('never two Scribe subagents in flight for one root at once; queue hand-offs strictly in stage order'))
            $script:StateInstructions.Body | Should -Match ([regex]::Escape('at most one Scribe hand-off is ever in flight for a given root, later stages'' hand-offs queue behind it in stage order'))
        }

        It 'depth-1 rule: stage N+2 is never dispatched before stage N''s Scribe hand-off is verified' {
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape('stage N+2 is never dispatched before stage N''s Scribe hand-off has returned and passed verification'))
        }

        It 'the barrier list names at least 11 items, including council verdict->implement, intake/discovery, Cost Preflight, Risk and Impactful-Action gates, and the final-outcome gate' {
            $barrierBlock = [regex]::Match($script:GatesAndModesBody, '(?s)Barrier invariant\..*?(?=\n## )').Value
            $numberedItems = @([regex]::Matches($barrierBlock, '(?m)^\d+\.\s'))
            $numberedItems.Count | Should -BeGreaterOrEqual 11 -Because 'the barrier list is a documented minimum of 11 items'

            $barrierBlock | Should -Match 'A council verdict consumed by Implement\.'
            $barrierBlock | Should -Match 'An intake gate verdict\.'
            $barrierBlock | Should -Match 'A discovery gate verdict\.'
            $barrierBlock | Should -Match ([regex]::Escape('Every Cost Preflight write, CAS or check, with or without a ceiling.'))
            $barrierBlock | Should -Match ([regex]::Escape('The Risk Gate, before the approved action.'))
            $barrierBlock | Should -Match ([regex]::Escape('The Impactful-Action Gate, before the approved action.'))
            $barrierBlock | Should -Match ([regex]::Escape('The final-outcome gate, including the notification record and the autopilot-run summary.'))
            $barrierBlock | Should -Match ([regex]::Escape("All fan-out deliverables' Scribe writes verified before Review begins."))
        }

        It 'per-write verification requires -ExpectedHistoryCounts paired with -BaselinePath, and a bare/count-only -Check is not verification' {
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape('A bare `-Check` or a count-only `-Check -ExpectedHistoryCounts` is not a write verification by itself'))
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape('Pair it with `-BaselinePath`'))
            $script:GatesAndModesBody | Should -Match ([regex]::Escape('verified (`-Check -ExpectedHistoryCounts` plus `-BaselinePath`)'))
        }

        It 'a failed verification is corrected append-only, never by re-running the originating stage' {
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape('The coordinator never re-runs the originating stage and never rewrites history to correct a bad write'))
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape('it dispatches a new, append-only Scribe correction entry'))
        }

        It 'resume re-sends the Scribe hand-off for the affected stage rather than re-running it' {
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape('re-send the hand-off for that stage only; never re-run the stage that produced the artifact'))
            $script:AutopilotInstructions.Body | Should -Match ([regex]::Escape('re-send the Scribe hand-off for that stage — never re-run the stage that produced the artifact'))
        }

        It 'a host whose dispatch tool advertises no background/async mode stays fully sequential' {
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape('Hosts whose dispatch tool does not advertise a background or asynchronous execution mode'))
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape('keep dispatching stage N''s Scribe hand-off, waiting for it, and only then dispatching stage N+1 — exactly as today'))
        }

        It 'the negative-space "never merge two stages'' Scribe payloads" sentence is single-homed in operating-procedure.md' {
            $script:OperatingProcedureBody | Should -Match ([regex]::Escape("never merge two stages' Scribe payloads into one hand-off"))

            $needle = "never merge two stages' Scribe payloads into one hand-off"
            $hits = New-Object System.Collections.Generic.List[string]
            foreach ($file in @($script:Model.Instructions + $script:Model.SquadAgents)) {
                if ($file.Body -match [regex]::Escape($needle)) { $hits.Add($file.Name) }
            }
            if ($script:GatesAndModesBody -match [regex]::Escape($needle)) { $hits.Add('gates-and-modes.md') }
            if ($script:OperatingProcedureBody -match [regex]::Escape($needle)) { $hits.Add('operating-procedure.md') }
            if ($script:FederationReferenceBody -match [regex]::Escape($needle)) { $hits.Add('federation.md') }
            @($hits) | Should -Be @('operating-procedure.md') -Because 'the plan requires this sentence single-homed in operating-procedure.md, not duplicated'
        }

        It 'keeps "state.json advances per stage" verbatim' {
            $script:Coordinator.Body | Should -Match ([regex]::Escape('`state.json` advances per stage'))
            $script:AutopilotInstructions.Body | Should -Match ([regex]::Escape('`state.json` advances per stage'))
            $script:GatesAndModesBody | Should -Match ([regex]::Escape('`state.json` advances per stage'))
        }
    }

    Context 'Negative pins: the pre-pipelining sequential-only wording does not resurface' {
        It 'coordinator no longer states the pipeline cannot advance past a missing history entry (old L92)' {
            $script:Coordinator.Body | Should -Not -Match ([regex]::Escape('and the pipeline cannot advance past it'))
        }

        It 'coordinator no longer states each stage is gated on the prior stage''s artifact plus its history entry as one inseparable gate (old L263)' {
            $script:Coordinator.Body | Should -Not -Match ([regex]::Escape("each stage is gated on the prior stage's artifact existing on disk plus its"))
        }

        It 'coordinator no longer states collapsing stages removes every checklist failure point (old L265)' {
            $script:Coordinator.Body | Should -Not -Match ([regex]::Escape('Collapsing several stages into one hand-off removes every point at which the checklist above could fail'))
        }

        It 'autopilot no longer states hand-off then only-then-read-and-advance with no pipelining allowance (old L53)' {
            $script:AutopilotInstructions.Body | Should -Not -Match ([regex]::Escape('and only then read the stage''s history entry and advance'))
        }

        It 'autopilot Artifact Gates no longer states the coordinator confirms evidence before advancing as a single undifferentiated gate (old L75)' {
            $script:AutopilotInstructions.Body | Should -Not -Match ([regex]::Escape('The coordinator confirms the evidence before advancing; a stage with no artifact and no'))
        }

        It 'autopilot Per-Stage Advance Checklist no longer states the old "do not advance...until...both" sentence (old L95)' {
            $script:AutopilotInstructions.Body | Should -Not -Match ([regex]::Escape('Do not advance from stage N to stage N+1 until, for stage N, both are confirmed on disk'))
        }

        It 'gates-and-modes Per-Stage Advance Checklist no longer states the old "do not advance...until both" sentence (old L122)' {
            $script:GatesAndModesBody | Should -Not -Match ([regex]::Escape('Do not advance from stage N to stage N+1 until both are confirmed on disk for stage N'))
        }

        It 'floor Proof of Dispatch no longer states a stage counts as run only when both exist, as one inseparable gate (old L67)' {
            $script:FloorInstructions.Body | Should -Not -Match ([regex]::Escape("A stage counts as run only when both exist: its domain artifact on disk at the role's ``Deliverable Root``"))
        }

        It 'the Enablement Predicate''s host term is never described as hardcoding false' {
            $script:GatesAndModesBody | Should -Not -Match ([regex]::Escape('hardcodes `false`'))
        }
    }
}
