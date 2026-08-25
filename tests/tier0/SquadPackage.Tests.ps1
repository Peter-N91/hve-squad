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
