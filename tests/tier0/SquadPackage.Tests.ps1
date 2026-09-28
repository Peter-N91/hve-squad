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
