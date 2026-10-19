#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# False positive: Pester evaluates BeforeDiscovery in the discovery scope and the It
# blocks that consume $model through -ForEach in the run scope. PSScriptAnalyzer
# resolves neither, so it reports the assignment as unused.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'model',
    Justification = 'Consumed by It -ForEach at discovery scope; PSScriptAnalyzer cannot resolve Pester scoping.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeDiscovery and BeforeAll, which PSScriptAnalyzer treats as unrelated scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'InstallLog',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExpectPinned',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot,

    [string]$InstallLog,

    # main deliberately ships an unpinned manifest; only a release tag pins itself.
    [bool]$ExpectPinned = $false
)

# Discovery and run are separate scopes, so each builds the model independently.
BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $model = Get-SquadPackageModel -PackageRoot $PackageRoot
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot
}

Describe 'PKG-01 Install emits no unpinned-reference warnings' {
    It 'reports zero unpinned references' -Skip:(-not ($InstallLog -and $ExpectPinned)) {
        $unpinned = @(
            Get-Content -LiteralPath $InstallLog |
                Where-Object { $_ -match 'unpinned' } |
                ForEach-Object { $_.Trim() }
        )
        $unpinned | Should -BeNullOrEmpty -Because "a tag that leaves references unpinned does not freeze the contents it ships:`n$($unpinned -join "`n")"
    }
}

Describe 'PKG-02 Every rostered agent is delivered' {
    It 'delivers at least one agent' {
        $script:Model.Agents.Count | Should -BeGreaterThan 0 -Because 'an empty agent tree means the package did not install'
    }

    It '<Owner> resolves rostered agent <Member>' -ForEach $model.RosterEntries {
        $resolvable = @($script:Model.AgentIdentifiers) + @($script:Model.OptInExternalAgents)
        $resolvable | Should -Contain $Member -Because 'a rostered agent that is neither delivered nor a registered opt-in external agent leaves the coordinator with a role it can only escalate on'
    }
}

Describe 'PKG-03 Every claimed skill reference exists' {
    It '<Agent> claims reference <Reference>' -ForEach $model.ReferenceClaims {
        $found = @($Roots | Where-Object { Test-Path -LiteralPath (Join-Path $_ $Reference) })
        $found | Should -Not -BeNullOrEmpty -Because 'a missing reference silently strips the agent of its procedure'
    }
}

Describe 'PKG-04 Agent bodies fit the host cap' {
    It '<Name> body of <BodyChars> chars is within the cap' -ForEach $model.SquadAgents {
        $BodyChars | Should -BeLessOrEqual $Limit -Because "the host truncates beyond $Limit characters, silently dropping the end of the contract"
    }

    # Third-party agents are outside this package's control, so their cap breaches are
    # reported rather than gated. Run with -IncludeAdvisory to see them.
    It '<Name> body of <BodyChars> chars is within the cap' -Tag 'Advisory' -ForEach $model.ThirdPartyAgents {
        $BodyChars | Should -BeLessOrEqual $Limit -Because "the host truncates beyond $Limit characters, silently dropping the end of the contract"
    }
}

Describe 'PKG-05 Every prompt binds to a delivered agent' {
    It '<Name> binds to a delivered agent' -ForEach $model.BoundPrompts {
        $script:Model.AgentIdentifiers | Should -Contain $Meta['agent'] -Because 'a prompt bound to an undelivered agent fails at invocation'
    }
}

Describe 'PKG-06 Frontmatter is well formed' {
    It '<Name> declares a description' -ForEach $model.Agents {
        $HasFront | Should -BeTrue
        $Meta['description'] | Should -Not -BeNullOrEmpty
    }

    # Only squad-owned agents must declare `name:`. Third-party agents may omit it
    # and let the host fall back to the file slug.
    It '<Name> declares an explicit name' -ForEach $model.SquadAgents {
        $Meta['name'] | Should -Not -BeNullOrEmpty -Because 'rosters resolve squad agents by name, so an implicit slug is not enough'
    }

    It '<Name> declares a description' -ForEach $model.Prompts {
        $HasFront | Should -BeTrue
        $Meta['description'] | Should -Not -BeNullOrEmpty
    }

    It 'agent names are unique' {
        $duplicates = @($script:Model.AgentNames | Group-Object | Where-Object Count -GT 1 | ForEach-Object Name)
        $duplicates | Should -BeNullOrEmpty -Because 'two agents sharing a name make roster resolution ambiguous'
    }
}

Describe 'PKG-07 The always-on floor is delivered' {
    It 'delivers squad-floor.instructions.md' {
        $script:Model.FloorInstructions.Count | Should -Be 1 -Because 'the floor carries the dispatch and single-writer rules that apply to every turn'
    }

    It 'declares applyTo **' -Skip:($model.FloorInstructions.Count -ne 1) {
        $script:Model.FloorInstructions[0].Meta['applyTo'] | Should -Be '**' -Because 'a narrower applyTo makes the floor conditional'
    }
}

Describe 'PKG-08 Skill reference links resolve' {
    It '<Source> links to <Link>' -ForEach $model.SkillLinks {
        Test-Path -LiteralPath (Join-Path $Base $Link) | Should -BeTrue -Because 'a dangling link sends the agent to a file that is not there'
    }
}

Describe 'PKG-09 Entrypoint prompts are delivered' {
    It 'delivers <Expected>' -ForEach $model.EntrypointPrompts {
        @($script:Model.Prompts.Name) | Should -Contain $Expected
    }
}

Describe 'PKG-10 Invocation flags match the entrypoint set' {
    It '<Name> declares an explicit user-invocable flag' -ForEach $model.SquadAgents {
        $Meta['user-invocable'] | Should -BeIn @('true', 'false') -Because 'an unset flag leaves host behavior to a default the package does not control'
    }

    It '<Name> is user-invocable because a prompt binds to it' -ForEach @(
        $model.SquadAgents | Where-Object { $model.EntrypointAgentNames -contains $_.Meta['name'] }
    ) {
        $Meta['user-invocable'] | Should -Be 'true' -Because 'an entrypoint agent hidden from the picker cannot be reached'
    }

    It '<Name> is a worker and stays out of the picker' -ForEach @(
        $model.SquadAgents | Where-Object { $model.EntrypointAgentNames -notcontains $_.Meta['name'] }
    ) {
        $Meta['user-invocable'] | Should -Be 'false' -Because 'a worker exposed as an entrypoint invites a user to bypass the coordinator'
    }
}

Describe 'PKG-12 Cost ceiling is exposed by both squad entrypoints' {
    It '<Name> declares and forwards the full cost-ceiling lifecycle' -ForEach @(
        $model.Prompts | Where-Object { $_.Name -in @('squad.prompt.md', 'squad-federation.prompt.md') }
    ) {
        $Meta['argument-hint'] | Should -Match 'cost-ceiling=<positive USD\|unset>'
        $Body | Should -Match '\$\{input:cost-ceiling\}'
        $Body | Should -Match 'cost-ceiling=unset'
        $Body | Should -Match 'same run'
    }
}

Describe 'PKG-13 Cost ceiling ownership is mode-specific' {
    It 'keeps initialization outside Cost Preflight' {
        $coordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-coordinator.agent.md')[0]
        $coordinator.Body | Should -Match 'Initialization is outside Cost Preflight'
        $coordinator.Body | Should -Match 'after initialization completes'
    }

    It 'applies an ordinary federation ceiling independently to each selected sub-squad' {
        $coordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-federation-coordinator.agent.md')[0]
        $coordinator.Body | Should -Match 'independent per-sub-squad ceiling'
        $coordinator.Body | Should -Match 'forwarding.+cost-ceiling'

        $scribeReference = Join-Path $script:Model.SquadSkillRoot 'references/scribe-procedure.md'
        Get-Content -LiteralPath $scribeReference -Raw | Should -Match 'ordinary or targeted federation routing replaces root `costPreflight` with the exact `not-requested` object'
    }

    It 'reserves aggregate admission for untargeted federation autopilot' {
        $coordinator = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-federation-coordinator.agent.md')[0]
        $coordinator.Body | Should -Match 'aggregate ceiling only when mode=autopilot has no squad= target'
        $coordinator.Body | Should -Match 'seed root.+consumption-rates\.md'

        $federationReference = Join-Path $script:Model.SquadSkillRoot 'references/federation-templates.md'
        Get-Content -LiteralPath $federationReference -Raw | Should -Match 'consumption-rates\.md \(federation root\)'
    }
}

Describe 'The Scribe hot core and charter bind writes to the file tool and fix the ledger decimal mark (CH5-07)' {
    # A static text assertion is the only offline-testable guard for this contract:
    # nothing short of an actual model turn exercises whether an agent chooses the
    # file edit/create tool over a shell string, so this proves the instruction the
    # Scribe is bound to still says so in both places it must -- the hot core it
    # follows and the charter that dispatches it -- rather than proving the
    # instruction is obeyed at runtime.
    It 'states file-edit/create-tool-only writes in the hot core and the charter, and the "." decimal mark in the hot core the charter defers to' {
        $scribeReference = Join-Path $script:Model.SquadSkillRoot 'references/scribe-procedure.md'
        $referenceBody = Get-Content -LiteralPath $scribeReference -Raw
        $referenceBody | Should -Match ([regex]::Escape("write every file with the host's file edit or create tool, never through a shell string")) `
            -Because 'the hot core is where the Scribe''s own write-mechanism rule lives'
        $referenceBody | Should -Match ([regex]::Escape('as the decimal mark whatever the host locale')) `
            -Because 'the hot core is where the ledger''s locale-independence rule lives'

        $scribeAgent = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-scribe.agent.md')[0]
        $scribeAgent.Body | Should -Match ([regex]::Escape('write the files themselves with the file edit or create tool, never through a shell string')) `
            -Because 'the charter must bind the coordinator''s own dispatched agent to the same write-mechanism rule as the hot core'
        $scribeAgent.Body | Should -Match 'scribe-procedure\.md' `
            -Because 'the charter defers the ledger''s decimal-mark rule to the hot core it cites rather than restating it, so this checks the cross-reference holds'
    }
}

Describe 'Consumption Accounting keeps its literal contract after the worked-example trim (C1)' {
    # C1 removed only the worked-example arithmetic duplicated from
    # squad-floor.instructions.md ("Example-Model X1" and the lead/orchestration
    # worked block); it must never remove the surrounding literal contract these
    # five phrases anchor. A regression here would mean the trim silently ate part
    # of the contract rather than just the redundant numbers.
    It 'still states the exact-JSON-shape, Derivation, orchestration-row, append-only-pairing, and helper-written-ledger contract phrases' {
        $scribeReference = Join-Path $script:Model.SquadSkillRoot 'references/scribe-procedure.md'
        $referenceBody = Get-Content -LiteralPath $scribeReference -Raw

        $referenceBody | Should -Match ([regex]::Escape('exactly one container shape')) `
            -Because 'the consumption block''s literal/exact JSON shape contract must survive the trim'
        $referenceBody | Should -Match ([regex]::Escape('in a `### Derivation` block under the Usage & Cost table')) `
            -Because 'the requirement that the ledger show a `### Derivation` block must survive the trim even though its worked numeric example was removed'
        $referenceBody | Should -Match ([regex]::Escape('plus the `orchestration` row')) `
            -Because 'the orchestration-row rule (every table carries an orchestration row alongside dispatched roles) must survive the trim'
        $referenceBody | Should -Match ([regex]::Escape('are inseparable')) `
            -Because 'the append-only history/consumption pairing rule must survive the trim'
        $referenceBody | Should -Match ([regex]::Escape('write these rows with the tool rather than by hand')) `
            -Because 'the instruction to have the helper write the ledger rather than hand-composing it must survive the trim'
        $referenceBody | Should -Match ([regex]::Escape('Measure-SquadLedger.ps1 -SquadRoot <squadRoot> -Write')) `
            -Because 'the helper''s -Write mode is how the Scribe writes the ledger and run totals'

        $referenceBody | Should -Not -Match ([regex]::Escape('Example-Model X1')) `
            -Because 'C1 removes the worked-example arithmetic duplicated from squad-floor.instructions.md, not just trims around it'
        $referenceBody | Should -Not -Match ([regex]::Escape('9600 × 2.00')) `
            -Because 'the lead/orchestration worked-example arithmetic block duplicated from squad-floor.instructions.md must be gone, not merely relocated'
    }
}

Describe 'PKG-15 Roster roles resolve in the catalog (C4)' {
    # C4 requires an automated gate proving every role a Squad Profiles or Squad Packs
    # row names actually resolves to a Cast Catalog row, not just a manual read. Both
    # roster tables (squad-roster.instructions.md, the hot file) and the mirrored
    # catalog copy (profiles-and-packs.md, a skill reference) are checked, because
    # either could drift from roster-catalog.md independently.
    BeforeAll {
        $rosterInstructions = @($script:Model.Instructions | Where-Object { $_.Name -eq 'squad-roster.instructions.md' })
        $rosterInstructions.Count | Should -Be 1 -Because 'exactly one roster-instructions file ships'

        $script:ProfilesAndPacksPath = Join-Path $script:Model.SquadSkillRoot 'references/profiles-and-packs.md'
        $script:CatalogPath = Join-Path $script:Model.SquadSkillRoot 'references/roster-catalog.md'
        Test-Path -LiteralPath $script:ProfilesAndPacksPath | Should -BeTrue -Because 'profiles-and-packs.md must ship for its mirrored roles to be checked'
        Test-Path -LiteralPath $script:CatalogPath | Should -BeTrue -Because 'roster-catalog.md is the canonical Cast Catalog every profile/pack role must resolve against'

        $script:RosterBody = $rosterInstructions[0].Body
        $script:ProfilesAndPacksBody = Get-Content -LiteralPath $script:ProfilesAndPacksPath -Raw
        $script:CatalogBody = Get-Content -LiteralPath $script:CatalogPath -Raw

        $script:RosterRoles = Get-SquadRosterRoles -Body @($script:RosterBody, $script:ProfilesAndPacksBody)
        $script:CatalogRoles = Get-SquadCastCatalogRoles -Body $script:CatalogBody

        $script:RosterRoles.Count | Should -BeGreaterThan 0 -Because 'a Squad Profiles/Packs table with zero parsed roles means the parser broke, not that the roster is empty'
        $script:CatalogRoles.Count | Should -BeGreaterThan 0 -Because 'a Cast Catalog with zero parsed roles means the parser broke, not that the catalog is empty'
    }

    It 'resolves every role named in a Squad Profiles or Squad Packs row to a Cast Catalog row' {
        $missing = @($script:RosterRoles | Where-Object { $script:CatalogRoles -notcontains $_ })
        $missing | Should -BeNullOrEmpty -Because "every role a Squad Profiles or Squad Packs row names in squad-roster.instructions.md or profiles-and-packs.md must resolve to a Cast Catalog row in roster-catalog.md, but these do not: $($missing -join ', ')"
    }

    It 'catches a renamed catalog row instead of passing vacuously (regression proof)' {
        # Proves the assertion above actually detects a break: mutate a copy of the
        # catalog text in memory only (the real file on disk is never touched) so the
        # `lead` row no longer exists, then confirm the same comparison reports `lead`
        # as missing.
        $mutatedCatalogBody = $script:CatalogBody -replace '(?m)^\| lead(\s*\|)', '| lead-renamed$1'
        $mutatedCatalogBody | Should -Not -Be $script:CatalogBody -Because 'the mutation must actually change the in-memory fixture for this to be a meaningful proof'

        $mutatedCatalogRoles = Get-SquadCastCatalogRoles -Body $mutatedCatalogBody
        $mutatedCatalogRoles | Should -Not -Contain 'lead' -Because 'the mutated fixture must no longer carry the lead row for this negative case to be valid'

        $missingAfterMutation = @($script:RosterRoles | Where-Object { $mutatedCatalogRoles -notcontains $_ })
        $missingAfterMutation | Should -Contain 'lead' -Because 'renaming the lead catalog row must surface lead as a missing role; a test that cannot fail this way would pass even if the real catalog lost a role'
    }
}

Describe 'GATE-45 Coordinator progress presentation contract' -Tag 'Unit' {
    BeforeAll {
        $script:ProgressCoordinator = @(
            $script:Model.SquadAgents |
                Where-Object Name -eq 'squad-coordinator.agent.md'
        )[0]
        $script:ProgressPrompt = @(
            $script:Model.Prompts |
                Where-Object Name -eq 'squad.prompt.md'
        )[0]
        $progressProcedurePath = Join-Path $script:Model.SquadSkillRoot 'references/operating-procedure.md'
        $script:ProgressProcedure = Get-Content -LiteralPath $progressProcedurePath -Raw
        $script:ProgressReferencePath = Join-Path $script:Model.SquadSkillRoot 'references/progress.md'
        $script:ProgressBody = [regex]::Match($script:ProgressProcedure, '(?ms)^### Progress Presentation\r?\n(?<Body>.*?)(?=^#{1,3} |\z)').Groups['Body'].Value
        $script:ProgressIndex = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'references/00-index.md') -Raw
        $script:ProgressSkill = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'SKILL.md') -Raw
        $script:ProgressRoutePointer = '5. Determine which gates apply and establish the actual stage shape. Apply Progress Presentation before the first work dispatch.'
        $script:ProgressAuthorization = '* `references/operating-procedure.md`'

        function Test-ProgressWiring {
            param([string]$Procedure, [string]$Coordinator)

            $route = [regex]::Match($Procedure, '(?ms)^## Route\r?\n(?<Body>.*?)(?=^## |\z)').Groups['Body'].Value
            $contract = [regex]::Match($Coordinator, '(?ms)^## Skill Reference Contract\r?\n(?<Body>.*?)(?=^## |\z)').Groups['Body'].Value
            $routePattern = (
                '(?ms)^1\. Read `team\.md` and `routing\.md`\..*?^2\. Match the request against the routing table;.*?^4\. Select cost-first:.*?^' +
                [regex]::Escape($script:ProgressRoutePointer) + '\r?\n6\. Dispatch all parallel-eligible roles'
            )
            return (
                ($route -match $routePattern) -and
                ($route -match '(?m)^### Progress Presentation\r?$') -and
                ($contract -match 'At run start, locate `squad` and read these files in one parallel block') -and
                ($contract -match ('(?m)^' + [regex]::Escape($script:ProgressAuthorization))) -and
                ($contract -match 'No other references: they belong to the Scribe or Federation Coordinator')
            )
        }

        function Test-ProgressOwnership {
            param([string]$Body)

            return (
                $Body -match 'Progress is coordinator-owned ephemeral UI, not role work or durable squad-state writes\.' -and
                $Body -match 'Dispatch no role or Squad Scribe for it; the Scribe is the sole ordinary state writer\.'
            )
        }
    }

    It 'keeps the complete common-path progress contract inline in a measured file' {
        $budget = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'baselines/hot-file-v0.18.1.json') -Raw | ConvertFrom-Json
        $budget.files.PSObject.Properties.Name | Should -Contain 'squad-src/.github/skills/squad/references/operating-procedure.md'
        $script:ProgressBody | Should -Not -BeNullOrEmpty
        [regex]::Matches($script:ProgressProcedure, '(?m)^### Progress Presentation\r?$').Count | Should -Be 1
        Test-Path -LiteralPath $script:ProgressReferencePath -PathType Leaf | Should -BeFalse
        foreach ($surface in @($script:ProgressProcedure, $script:ProgressCoordinator.Body, $script:ProgressIndex, $script:ProgressSkill)) {
            $surface | Should -Not -Match 'references/progress\.md|\[progress\.md\]' -Because 'common-path progress must not evade the budget through an unmeasured reference'
        }
    }

    It 'requires inline progress after classification and before dispatch through the loaded procedure' {
        Test-ProgressWiring -Procedure $script:ProgressProcedure -Coordinator $script:ProgressCoordinator.Body | Should -BeTrue
        $script:ProgressBody | Should -Match 'For every non-trivial request, after state, route, and gate classification'
    }

    It 'preserves cost-first tiers, per-turn override, routed modes, and off behavior' {
        $script:ProgressProcedure | Should -Match '`fast` for read-heavy `auto`, `default` for reasoning-heavy `confirm`'
        $script:ProgressProcedure | Should -Match 'user tier hints override per-role defaults for this turn'
        $script:ProgressProcedure | Should -Match 'For `team.md` `Model routing: ranked\|economy\|manual` or `routing=`, resolve ids per `references/model-routing.md`'
        $script:ProgressProcedure | Should -Match '`off` keeps cost-first selection'
    }

    It 'resolves a native tracker by capability and retains the in-chat fallback' {
        $script:ProgressBody | Should -Match 'Before first substantive dispatch, show the same concise `## Plan` in chat and a compatible native todo or task-list tracker'
        $script:ProgressBody | Should -Match 'when available by advertised host capability, not literal tool name'
        $script:ProgressBody | Should -Match 'Otherwise maintain the Markdown checklist or status ledger in later updates'
    }

    It 'pins stable three-to-seven item progress and verification before completion' {
        $script:ProgressBody | Should -Match '3 to 7 high-level outcome items, including verification and final reporting'
        $script:ProgressBody | Should -Match 'no reads, searches, Scribe mechanics, or individual edits'
        $script:ProgressBody | Should -Match 'Keep item identity and order stable unless material scope changes'
        $script:ProgressBody | Should -Match 'exactly one item in progress during active work'
        $script:ProgressBody | Should -Match 'Complete an item only after its outcome and applicable artifact, history, and consumption gates are verified'
        $script:ProgressBody | Should -Match 'After each meaningful phase, update tracker or ledger and emit exactly: `Completed: <item>\. Next: <next item>\.`'
    }

    It 'binds pre-dispatch presentation and ephemeral ownership to the coordinator' {
        $script:ProgressBody | Should -Match 'Before first substantive dispatch, show the same concise `## Plan` in chat and a compatible native'
        $script:ProgressBody | Should -Match 'without delay or degraded squad methodology'
        Test-ProgressOwnership -Body $script:ProgressBody | Should -BeTrue
    }

    It 'pins blocked work and final progress accounting' {
        $script:ProgressBody | Should -Match 'Blocked: keep the current item in progress, name the blocker, never silently skip it'
        $script:ProgressBody | Should -Match 'Before final response, complete each item or report it explicitly blocked'
        $script:ProgressBody | Should -Match 'Name changed or delivered files, actual validation, and remaining risks or decisions'
    }

    It 'forwards plan ownership from the prompt without creating duplicate state' {
        $script:ProgressPrompt.Body | Should -Match '1\. Hand `\$\{input:request\}`.*?to the Squad Coordinator and let its per-turn protocol classify, dispatch, and synthesize the response'
        $script:ProgressPrompt.Body | Should -Not -Match 'Forward progress presentation ownership|## Plan' -Because 'the existing delegation must not acquire a second progress contract'
        $script:ProgressBody | Should -Match 'The prompt delegates: no second plan or progress state writes'
    }

    It 'rejects deleted, optional, retargeted, or late inline progress wiring' {
        foreach ($mutated in @(
                $script:ProgressProcedure.Replace($script:ProgressRoutePointer, ''),
                $script:ProgressProcedure.Replace('Apply Progress Presentation', 'Optionally apply Progress Presentation'),
                $script:ProgressProcedure.Replace('Apply Progress Presentation', 'Read references/progress.md'),
                ($script:ProgressProcedure.Replace($script:ProgressRoutePointer, '') + "`n" + $script:ProgressRoutePointer),
                $script:ProgressProcedure.Replace('### Progress Presentation', '### Deferred Progress'),
                ($script:ProgressProcedure.Replace("### Progress Presentation`r`n", '').Replace("### Progress Presentation`n", '') + "`n### Progress Presentation`n")
            )) {
            Test-ProgressWiring -Procedure $mutated -Coordinator $script:ProgressCoordinator.Body | Should -BeFalse
        }
    }

    It 'rejects a missing procedure read even when the reference remains elsewhere in the coordinator' {
        $mutated = $script:ProgressCoordinator.Body.Replace($script:ProgressAuthorization, '')
        Test-ProgressWiring -Procedure $script:ProgressProcedure -Coordinator $mutated | Should -BeFalse
        Test-ProgressWiring -Procedure $script:ProgressProcedure -Coordinator ($mutated + "`n" + $script:ProgressAuthorization) | Should -BeFalse
    }

    It 'rejects role-work, durable-state, Scribe-dispatch, and shared-writer ownership mutations' {
        foreach ($mutation in @(
                @{ From = 'not role work'; To = 'role work' },
                @{ From = 'or durable squad-state writes'; To = 'and durable squad-state writes' },
                @{ From = 'Dispatch no role or Squad Scribe'; To = 'Dispatch the Squad Scribe' },
                @{ From = 'sole ordinary state writer'; To = 'shared state writer' }
            )) {
            Test-ProgressOwnership -Body $script:ProgressBody.Replace($mutation.From, $mutation.To) | Should -BeFalse
        }
    }

    It 'preserves shared-learning read order, conditional tenant loading, and single-writer promotion boundaries' {
        $decide = [regex]::Match($script:ProgressProcedure, '(?ms)^## Decide\r?\n(?<Body>.*?)(?=^## |\z)').Groups['Body'].Value
        $decide | Should -Match 'Persist durable, role-scoped learnings to `/memories/repo/squad-<agent>\.md` through the Squad Scribe and the memory tool'
        $decide | Should -Match 'Read learnings in order: local memory, shipped `learnings/shared-learnings\.md` \(skill-root-relative within the deployed `squad` skill\), then `\.agents/skills/squad-learnings-tenant/tenant-learnings\.md` only when the organization configured the tenant-internal APM dependency'
        $decide | Should -Match 'Both playbooks are read-only, authoritative context; apply entries matching the current scenario and never write either from a run'
        $decide | Should -Match 'promotion to shared playbooks uses only the human-reviewed fork-and-PR paths in `CONTRIBUTING\.md`'
        $script:ProgressProcedure | Should -Match '\| `squad_memory`.*Write durable per-agent notes with the memory tool to `/memories/repo/squad-<agent>\.md`'
    }
}

Describe 'GATE-46 Watch Mode per-case/per-ask squad selection and full RPI lifecycle contract' -Tag 'Unit' {
    BeforeAll {
        $script:WatchModeInstruction = @(
            $script:Model.Instructions |
                Where-Object Name -eq 'squad-watch-mode.instructions.md'
        )[0]
        $script:FederationRef = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'references/federation.md') -Raw
        $script:WatchWorkflowTemplate = Get-Content -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'squad-watch.workflow.yml') -Raw
    }

    It 'requires per-case and per-ask profile and pack selection across all Watch Mode triggers in squad-watch-mode.instructions.md' {
        $script:WatchModeInstruction.Body | Should -Match ([regex]::Escape('Every Watch Mode trigger (`issues`, `pull_request`, `issue_comment`, `schedule`, `workflow_dispatch`, `push`) selects its event sub-squad''s **profile** and optional **packs** per case and per ask'))
        $script:WatchModeInstruction.Body | Should -Match ([regex]::Escape('seeding from the canonical templates rather than copying a prior `members/*` roster'))
        $script:WatchModeInstruction.Body | Should -Match ([regex]::Escape('Every seeded roster carries the full `researcher`, `lead`, `developer`, `tester`, `scribe` spine, and every substantive run executes the complete Research → Plan → Council → Implement → Review pipeline even when the brief lists numbered steps.'))
    }

    It 'requires canonical sub-squad seeding, missing federation-root repair, and full RPI execution in references/federation.md' {
        $script:FederationRef | Should -Match ([regex]::Escape('Select the profile and any optional packs **per case and per ask** for every trigger kind (`issue`, `pull_request`, `issue_comment`, `schedule`, `workflow_dispatch`, `push`)'))
        $script:FederationRef | Should -Match ([regex]::Escape('do not copy a roster or history layout from an earlier `members/*` directory'))
        $script:FederationRef | Should -Match ([regex]::Escape('When `members/*` directories exist on disk without a root `federation.md`, seed the missing federation-root meta layer'))
        $script:FederationRef | Should -Match ([regex]::Escape('Numbered steps or checklists in an issue body (including **Sync and Adapt** briefs) are input requirements to research, plan, implement, and review — not a reason to skip Research or Plan.'))
    }

    It 'wires per-case/per-ask squad selection and the full RPI spine across all trigger branches in squad-watch.workflow.yml' {
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('SQUAD SELECTION PER CASE AND PER ASK (NON-NEGOTIABLE).'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('COMPLETE SQUAD LIFECYCLE (FULL RPI - NON-NEGOTIABLE).'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('IMMEDIATE SCRIBE CHECKPOINTS (NON-NEGOTIABLE).'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('Never copy a team.md, routing.md, or history/ layout from an earlier members/*'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('Stage 1 (Research): dispatch researcher'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('Stage 2 (Plan): gated on the research artifact existing on disk'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('Stage 4 (Implement): gated on the plan artifact'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('Stage 5 (Review): gated on the implementation artifacts existing on disk'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('Stage 6 (Final-Outcome & Two-Level Verification): have Squad Scribe write'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('Run /squad-federation mode=autopilot ${watchArg({ source: ''issue_comment'''))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('Run /squad-federation mode=autopilot ${watchArg({ source: ''workflow_dispatch'''))
    }

    It 'ships the handoff module and explicitly scopes the reference template prerequisites' {
        Test-Path -LiteralPath (Join-Path $script:Model.SquadSkillRoot 'scripts/SquadWatch.psm1') -PathType Leaf |
            Should -BeTrue -Because 'installed consumers need the deterministic handoff helper in the deployed squad skill'
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('New-SquadWatchBaseline'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('New-SquadWatchHandoff'))
        $script:WatchWorkflowTemplate | Should -Match ([regex]::Escape('rather than as lifecycle-enforcement parity'))
    }
}
