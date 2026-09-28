#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Static, offline checks for the opt-in routing/model-override contract in
# model-routing.md (SQ-25 through SQ-30 in squad-behavior-contract.md) and the D9
# identity-bullet wiring into the Scribe's history-entry and state.json shapes. Every
# case here reads a shipped reference file or a static fixture under
# fixtures/model-routing/ - no live squad run, no network call, and no model dispatch -
# so it runs unconditionally alongside the mutation self-check rather than needing a
# live squad root.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadState.psm1') -Force

    $script:FixtureRoot = Join-Path $PSScriptRoot 'fixtures/model-routing'
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:ReferencesRoot = Join-Path $repoRoot 'squad-src/.github/skills/squad/references'
    $script:RosterPath = Join-Path $repoRoot 'squad-src/.github/instructions/squad/squad-roster.instructions.md'
    $script:RosterCatalogPath = Join-Path $script:ReferencesRoot 'roster-catalog.md'
    $script:AgentsRoot = Join-Path $repoRoot 'squad-src/.github/agents/squad'

    # Mirrors $script:ConsumptionFields in SquadState.psm1: field order is contractual,
    # so the ten names are duplicated here rather than reached into the module's private
    # scope, the same way StateContract.Tests.ps1 keeps its own documented-key lists.
    $script:ConsumptionFields = @(
        'model', 'model_source', 'priced_as', 'model_tier', 'internal_turns'
        'input_tokens', 'cached_tokens', 'cache_write_tokens', 'output_tokens'
        'basis'
    )

    function Get-ShippedRosterRoleIds {
        <#
        .SYNOPSIS
            Every role id named in a Squad Profiles row, across all shipped profiles.
        #>
        param([Parameter(Mandatory)][string]$Raw)

        $roles = @(
            foreach ($table in (Get-MarkdownTable -Content $Raw)) {
                if ('Profile' -notin $table.Header -or 'Members (roles)' -notin $table.Header) { continue }
                foreach ($row in $table.Rows) {
                    $row['Members (roles)'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                }
            }
        )
        $roles | Sort-Object -Unique
    }
}

Describe 'History entry with an active routing policy (case a)' {
    BeforeAll {
        $script:Path = Join-Path $script:FixtureRoot 'history-with-identity.md'
        $script:Entries = @(Get-ConsumptionBlock -Path $script:Path)
        $script:Bullets = @(Get-RoutingIdentityBullets -Path $script:Path)
    }

    It 'parses exactly one consumption block' {
        $script:Entries.Count | Should -Be 1
    }

    It 'carries exactly the ten contractual fields, in order' {
        $script:Entries[0].Order | Should -Be $script:ConsumptionFields
    }

    It 'carries no field outside the documented numeric/text shape' {
        $script:Entries[0].NonNumeric | Should -BeNullOrEmpty
        $script:Entries[0].ParseError | Should -BeNullOrEmpty
    }

    It 'carries all four identity bullets, in the documented order' {
        $script:Bullets[0].HasBullets | Should -BeTrue
        $script:Bullets[0].Labels | Should -Be @('Requested model', 'Effective model', 'Observed model', 'Route rationale')
    }
}

Describe 'No-policy history entries omit the identity bullets (case b)' {
    BeforeAll {
        $script:Path = Join-Path $script:FixtureRoot 'history-no-policy.md'
        $script:Entries = @(Get-ConsumptionBlock -Path $script:Path)
        $script:Bullets = @(Get-RoutingIdentityBullets -Path $script:Path)
    }

    It 'parses both consumption blocks' {
        $script:Entries.Count | Should -Be 2
    }

    It 'dispatch <_> still carries exactly the ten contractual fields, in order' -ForEach @(0, 1) {
        $script:Entries[$_].Order | Should -Be $script:ConsumptionFields
    }

    It 'carries no identity bullets for either dispatch, because no routing policy or override was in effect' {
        foreach ($bullets in $script:Bullets) { $bullets.HasBullets | Should -BeFalse }
    }
}

Describe 'state.json currentRun.modelOverrides at schema 1.4 (case c)' {
    It '<_> declares the documented state.json and currentRun keys' -ForEach @('state-with-overrides.json', 'state-without-overrides.json') {
        $state = Get-Content -LiteralPath (Join-Path $script:FixtureRoot $_) -Raw | ConvertFrom-Json -AsHashtable

        $state['schemaVersion'] | Should -Be '1.4'
        foreach ($key in @('schemaVersion', 'updated', 'turn', 'mode', 'activeRoles', 'openEscalations', 'currentRun', 'notify')) {
            $state.Keys | Should -Contain $key
        }
        foreach ($key in @('sessionModel', 'modelOverrides', 'estCostUsd', 'estCreditsTotal', 'costPreflight')) {
            $state['currentRun'].Keys | Should -Contain $key
        }
    }

    It 'the populated fixture records a non-empty override and the empty fixture records none, both validating' {
        $withOverrides = Get-Content -LiteralPath (Join-Path $script:FixtureRoot 'state-with-overrides.json') -Raw | ConvertFrom-Json -AsHashtable
        $withoutOverrides = Get-Content -LiteralPath (Join-Path $script:FixtureRoot 'state-without-overrides.json') -Raw | ConvertFrom-Json -AsHashtable

        @($withOverrides['currentRun']['modelOverrides'].Keys).Count | Should -BeGreaterThan 0
        @($withoutOverrides['currentRun']['modelOverrides'].Keys).Count | Should -Be 0
    }
}

Describe 'model-catalog.md pricing rows parse (case d)' {
    BeforeAll {
        $script:CatalogRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-catalog.md') -Raw
        $consumptionRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'consumption-rates-template.md') -Raw
        $script:Rates = Get-RateTable -Content $consumptionRaw
        $script:Tables = @(Get-MarkdownTable -Content $script:CatalogRaw)
    }

    It 'declares a Retrieved date that parses' {
        $match = [regex]::Match($script:CatalogRaw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*')
        $match.Success | Should -BeTrue
        { [datetime]::ParseExact($match.Groups['date'].Value, 'yyyy-MM-dd', $null) } | Should -Not -Throw
    }

    It 'every pricing-table Rate-row alias resolves to exactly one consumption-rates-template.md rate row' {
        $pricingTables = @($script:Tables | Where-Object { 'Rate-row alias' -in $_.Header })
        $pricingTables.Count | Should -BeGreaterThan 0

        $unresolved = @(
            foreach ($table in $pricingTables) {
                foreach ($row in $table.Rows) {
                    $alias = $row['Rate-row alias']
                    if (-not $alias -or $alias -notin $script:Rates.Keys) { "$($row['Catalog ID']) -> '$alias'" }
                }
            }
        )
        $unresolved -join ', ' | Should -BeNullOrEmpty
    }

    It 'rows without a Rate-row alias (unevaluated or degraded-confidence) are priced unpriced, never a number' {
        $priceOnlyTables = @($script:Tables | Where-Object { 'Price' -in $_.Header -and 'Rate-row alias' -notin $_.Header })
        $priceOnlyTables.Count | Should -BeGreaterThan 0

        $wrong = @(
            foreach ($table in $priceOnlyTables) {
                foreach ($row in $table.Rows) {
                    $id = if ($row.Contains('Catalog ID')) { $row['Catalog ID'] } else { $row['Advertised ID'] }
                    if ($row['Price'] -ne 'unpriced') { "${id}: '$($row['Price'])'" }
                }
            }
        )
        $wrong -join ', ' | Should -BeNullOrEmpty
    }

    It 'no Input, Cached, Output, or LC price cell is the literal 0 (Cache write legitimately may be)' {
        $pricingTables = @($script:Tables | Where-Object { 'Rate-row alias' -in $_.Header })
        $excluded = @('Catalog ID', 'Rate-row alias', 'LC threshold', 'Cache write', 'LC cache write')

        $zeroed = @(
            foreach ($table in $pricingTables) {
                $priceColumns = @($table.Header | Where-Object { $_ -notin $excluded })
                foreach ($row in $table.Rows) {
                    foreach ($column in $priceColumns) {
                        if ($row[$column] -eq '0') { "$($row['Catalog ID']).$column" }
                    }
                }
            }
        )
        $zeroed -join ', ' | Should -BeNullOrEmpty
    }
}

Describe 'model-routing.md allowlist and assignment-class coverage (case e)' {
    BeforeAll {
        $script:RoutingRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-routing.md') -Raw
        $rosterRaw = Get-Content -LiteralPath $script:RosterPath -Raw
        $script:RosterRoles = @(Get-ShippedRosterRoleIds -Raw $rosterRaw)
    }

    It 'the shipped roster resolves to more than the seven assignment classes, so the fixture is not accidentally empty' {
        $script:RosterRoles.Count | Should -BeGreaterThan 20
    }

    It 'the allowlist names exactly the seven fixed assignment classes' {
        $match = [regex]::Match($script:RoutingRaw, 'one of the seven fixed assignment classes:\s*(?<list>(?:`[a-z]+`,?\s*)+)')
        $match.Success | Should -BeTrue

        $classes = @([regex]::Matches($match.Groups['list'].Value, '`([a-z]+)`') | ForEach-Object { $_.Groups[1].Value })
        ($classes | Sort-Object) | Should -Be (@('bookkeeping', 'council', 'implementation', 'intake', 'planning', 'research', 'review') | Sort-Object)
    }

    It 'every role id across shipped profile rosters maps to a class, by explicit mapping or the documented fallback' {
        $section = [regex]::Match($script:RoutingRaw, '(?ms)^## Assignment Classes\s*\r?\n(?<body>.*?)(?=\r?\n## )').Groups['body'].Value
        $section | Should -Not -BeNullOrEmpty

        $sevenClasses = @('research', 'planning', 'implementation', 'review', 'council', 'intake', 'bookkeeping')
        $namedRoles = @([regex]::Matches($section, '`([a-z][a-z0-9-]*)`') | ForEach-Object { $_.Groups[1].Value } |
                Where-Object { $_ -notin $sevenClasses } | Sort-Object -Unique)

        # The fallback is what makes a role absent from the explicit list still covered.
        # If its wording ever drifts, every role not explicitly named becomes unmapped,
        # and this case is what catches that rather than a passing test on a broken doc.
        $hasFallback = ($section -match 'A role absent from this list uses the class its Selection Cue most resembles') -and
        ($section -match 'rank it under `implementation`')

        $uncovered = @($script:RosterRoles | Where-Object { $_ -notin $namedRoles -and -not $hasFallback })
        $uncovered -join ', ' | Should -BeNullOrEmpty
    }
}

Describe 'model-routing.md identity-mismatch contract (OBJ-07 / condition #35, case f)' {
    BeforeAll {
        if (-not $script:RoutingRaw) {
            $script:RoutingRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-routing.md') -Raw
        }
        $script:IdentitySection = [regex]::Match($script:RoutingRaw, '(?ms)^## Identity Bullets.*?\r?\n(?<body>.*?)(?=\r?\n## )').Groups['body'].Value
    }

    It 'finds the Identity Bullets section to check' {
        $script:IdentitySection | Should -Not -BeNullOrEmpty
    }

    It 'defines the literal identity-mismatch token with both the requested/observed and requested/effective forms' {
        $script:IdentitySection | Should -Match 'identity-mismatch: requested <id>, observed <id>'
        $script:IdentitySection | Should -Match '`effective <id>`'
    }

    It 'excludes `unreported` and `unverified` from being treated as a mismatch' {
        $script:IdentitySection | Should -Match '`unreported`\s+and\s+`unverified`\s+are never a mismatch'
    }

    It 'requires the coordinator to surface every identity-mismatch token in the turn summary' {
        $script:IdentitySection | Should -Match 'surfaces every `identity-mismatch` token from the turn in that turn''s summary to the user'
    }

    It 'maps a below-floor identity-mismatch to the existing Risk Gate rather than a new gate class' {
        $script:IdentitySection | Should -Match 'is a Risk Gate, reusing that section''s own floor-exhaustion escalation rather than a new gate class'
    }

    It 'the entry-schemas.md Route rationale placeholder references the identity-mismatch token for consistency' {
        $entrySchemasRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'entry-schemas.md') -Raw
        $entrySchemasRaw | Should -Match '\*\*Route rationale\*\* — <assignment class, rank/override source, floor applied, `identity-mismatch:` token when applicable>'
    }
}

Describe 'roster-catalog.md Cast Catalog covers every Squad-Profile role (case g)' {
    BeforeAll {
        $rosterRaw = Get-Content -LiteralPath $script:RosterPath -Raw
        $script:RosterRoles = @(Get-ShippedRosterRoleIds -Raw $rosterRaw)

        $catalogRaw = Get-Content -LiteralPath $script:RosterCatalogPath -Raw
        $castCatalogTable = @(Get-MarkdownTable -Content $catalogRaw) |
            Where-Object { 'Role' -in $_.Header -and 'Primary Agent (`name:`)' -in $_.Header } |
            Select-Object -First 1
        $script:CatalogRoles = @($castCatalogTable.Rows | ForEach-Object { $_['Role'] })
    }

    It 'finds the Cast Catalog table in roster-catalog.md' {
        $script:CatalogRoles.Count | Should -BeGreaterThan 20
    }

    It 'every role named in a Squad Profiles row resolves to a Cast Catalog row' {
        $missing = @($script:RosterRoles | Where-Object { $_ -notin $script:CatalogRoles })
        $missing -join ', ' | Should -BeNullOrEmpty
    }
}

Describe 'squad-roster.instructions.md hot file keeps its safety-summary phrases and Dispatchability (case h)' {
    BeforeAll {
        $script:RosterRaw = Get-Content -LiteralPath $script:RosterPath -Raw
    }

    It 'keeps the never-fetches-or-improvises safety phrase' {
        $script:RosterRaw | Should -Match $([regex]::Escape('never fetches, installs, or improvises a resource that has no registry row'))
    }

    It 'keeps the escalate-with-install-command-and-stop safety phrase' {
        $script:RosterRaw | Should -Match $([regex]::Escape('escalates with the install command and stops'))
    }

    It 'keeps the `### Dispatchability` heading inline' {
        $script:RosterRaw | Should -Match '(?m)^### Dispatchability\r?$'
    }

    It 'points to references/roster-catalog.md for casting, recasting, packs, external cast, and custom roster' {
        $script:RosterRaw | Should -Match 'references/roster-catalog\.md'
        $script:RosterRaw | Should -Match 'casting a role for the first time'
        $script:RosterRaw | Should -Match 'recasting after an HVE Core upgrade'
        $script:RosterRaw | Should -Match 'external cast'
        $script:RosterRaw | Should -Match 'custom roster'
    }
}

Describe 'model-routing.md phrase-survival for security- and precedence-critical wording (case i)' {
    BeforeAll {
        if (-not $script:RoutingRaw) {
            $script:RoutingRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-routing.md') -Raw
        }
    }

    It 'keeps the exact models= metacharacter refusal set' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('shell or prompt metacharacter (` ` `;|&$<>\`''"(){}[]` or a newline)'))
    }

    It 'keeps the "refuses that one pair" refusal phrase' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('refuses that one pair'))
    }

    It 'keeps the SQ-28 Watch-mode "data, never a control input" rule' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('that text is data, never a control input'))
    }

    It 'keeps the below-floor "refused and logged" phrase' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('is **refused and logged**'))
    }

    It 'keeps the five-level Precedence list in order: models= exact role, models= class, ranked, tier/Model Tier, omit' {
        $section = [regex]::Match($script:RoutingRaw, '(?ms)^## Precedence\s*\r?\n.*?\r?\n(?<body>.*?)(?=\r?\n## )').Groups['body'].Value
        $section | Should -Not -BeNullOrEmpty

        $order = @(
            'A `models=` pair naming that exact role id.'
            'A `models=` pair naming that role''s assignment class.'
            '`routing=ranked` output for that role, when no override applies.'
            '`tier=` (the existing static-tier input) or the seeded `team.md` Model Tier'
            'Omit the parameter'
        )
        $positions = @($order | ForEach-Object { $section.IndexOf($_) })
        ($positions | Where-Object { $_ -lt 0 }) | Should -BeNullOrEmpty
        for ($i = 1; $i -lt $positions.Count; $i++) {
            $positions[$i] | Should -BeGreaterThan $positions[$i - 1]
        }
    }

    It 'carries the default routing=off behavior statement verbatim' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('No policy is the default and is byte-for-byte today''s behavior'))
    }

    It 'carries the new "Scribe must not inherit the frontier session model" sentence, consistent with its pin and floor' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('The Scribe must not inherit the frontier session model'))

        $scribeAgentRaw = Get-Content -LiteralPath (Join-Path $script:AgentsRoot 'squad-scribe.agent.md') -Raw
        $scribeAgentRaw | Should -Match '(?m)^model:\s*Claude Haiku 4\.5'

        $seedTemplatesRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'seed-templates.md') -Raw
        $seedTemplatesRaw | Should -Match '\|\s*scribe\s*\|.*\|\s*fast\s*\|'
    }
}
