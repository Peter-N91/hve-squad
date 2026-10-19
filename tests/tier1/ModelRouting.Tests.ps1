#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Static, offline checks for the opt-in routing/model-override contract in
# model-routing.md (SQ-25 through SQ-34 in squad-behavior-contract.md) and the D9
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

    It 'keeps the exact Model-cell metacharacter refusal set' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('shell or prompt metacharacter (` ` `;|&$<>\`''"(){}[]` or a newline)'))
    }

    It 'keeps the "refuses that one cell" refusal phrase' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('refuses that one cell'))
    }

    It 'keeps the SQ-28 Watch-mode "data, never a control input" rule' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('that text is data, never a control input'))
    }

    It 'keeps the below-floor "refused and logged" phrase' {
        $script:RoutingRaw | Should -Match $([regex]::Escape('is **refused and logged**'))
    }

    It 'keeps the four-level Precedence list in order: manual Model cell, ranked, tier/Model Tier, omit' {
        $section = [regex]::Match($script:RoutingRaw, '(?ms)^## Precedence\s*\r?\n.*?\r?\n(?<body>.*?)(?=\r?\n## )').Groups['body'].Value
        $section | Should -Not -BeNullOrEmpty

        $order = @(
            '`routing=manual`: the role''s valid `Model` cell.'
            '`routing=ranked`: the ranked id for that role'
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
        $scribeAgentRaw | Should -Match '(?m)^model:\s*Claude Haiku 5\.5'

        $seedTemplatesRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'seed-templates.md') -Raw
        $seedTemplatesRaw | Should -Match '\|\s*scribe\s*\|.*\|\s*fast\s*\|'
    }
}

Describe 'model-catalog.md Assignment Fit table (case j)' {
    BeforeAll {
        $catalogRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-catalog.md') -Raw
        $tables = @(Get-MarkdownTable -Content $catalogRaw)
        $script:FitRows = @($tables | Where-Object { 'Blended' -in $_.Header } | Select-Object -First 1 | ForEach-Object { $_.Rows })
        $script:PriceRows = @{}
        foreach ($table in @($tables | Where-Object { 'Rate-row alias' -in $_.Header })) {
            foreach ($row in $table.Rows) { $script:PriceRows[$row['Catalog ID']] = $row }
        }
        $script:CapabilityRows = @{}
        foreach ($row in @($tables | Where-Object { 'Capability class' -in $_.Header } | ForEach-Object { $_.Rows })) {
            if ($row.Contains('Catalog ID') -and $row['Catalog ID']) { $script:CapabilityRows[$row['Catalog ID']] = $row }
        }
        $script:CapabilityIds = @($script:CapabilityRows.Keys)
        $script:SevenClasses = @('research', 'planning', 'implementation', 'review', 'council', 'intake', 'bookkeeping')
    }

    It 'finds the fit table' {
        $script:FitRows.Count | Should -BeGreaterThan 20
    }

    It 'scores every priced Catalog ID exactly once, and nothing else' {
        $fitIds = @($script:FitRows | ForEach-Object { $_['Catalog ID'] })
        ($fitIds | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name) -join ', ' | Should -BeNullOrEmpty
        (@($script:PriceRows.Keys | Where-Object { $_ -notin $fitIds }) -join ', ') | Should -BeNullOrEmpty
        (@($fitIds | Where-Object { $_ -notin $script:PriceRows.Keys -or $_ -notin $script:CapabilityIds }) -join ', ') | Should -BeNullOrEmpty
    }

    It 'holds an integer fit score from 0 to 3 in every class column' {
        $bad = @(
            foreach ($row in $script:FitRows) {
                foreach ($class in $script:SevenClasses) {
                    if ($row[$class] -notmatch '^[0-3]$') { "$($row['Catalog ID']).$class='$($row[$class])'" }
                }
            }
        )
        $bad -join ', ' | Should -BeNullOrEmpty
    }

    It 'derives every Blended rate from the pricing tables with the documented formula' {
        $number = { param($v) if ($v -match '^\d+(\.\d+)?$') { [double]$v } else { 0.0 } }
        $wrong = @(
            foreach ($row in $script:FitRows) {
                $price = $script:PriceRows[$row['Catalog ID']]
                $expected = 0.20 * (& $number $price['Input']) + 0.80 * (& $number $price['Cached']) + 0.08 * (& $number $price['Cache write']) + 0.02 * (& $number $price['Output'])
                if ([math]::Abs($expected - [double]$row['Blended']) -gt 0.0005) { "$($row['Catalog ID']): $($row['Blended']) vs $([math]::Round($expected, 3))" }
            }
        )
        $wrong -join ', ' | Should -BeNullOrEmpty
    }

    It 'catalogs Haiku 5.5 with its documented standard and long-context rates and sourced lightweight fit' {
        $price = $script:PriceRows['claude-haiku-5.5']
        $price['LC threshold'] | Should -Be '≤100K / >100K'
        @($price['Input'], $price['Cached'], $price['Cache write'], $price['Output']) | Should -Be @('0.10', '0.01', '0.125', '0.50')
        @($price['LC input'], $price['LC cached'], $price['LC cache write'], $price['LC output']) | Should -Be @('0.50', '0.05', '0.625', '2.50')
        $script:CapabilityRows['claude-haiku-5.5']['Capability class'] | Should -Be 'fast-lightweight'
        $fit = @($script:FitRows | Where-Object { $_['Catalog ID'] -eq 'claude-haiku-5.5' })[0]
        @($fit['intake'], $fit['bookkeeping'], $fit['Blended']) | Should -Be @('2', '3', '0.048')
    }

    It 'keeps at least one model scoring 3 in every class, so no class ranks on cost alone' {
        foreach ($class in $script:SevenClasses) {
            @($script:FitRows | Where-Object { $_[$class] -eq '3' }).Count | Should -BeGreaterThan 0 -Because "$class needs a best-in-class row"
        }
    }
}

Describe 'consumption-rates-template.md Model ID column (case k)' {
    BeforeAll {
        $templateRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'consumption-rates-template.md') -Raw
        $script:RateRows = @(Get-MarkdownTable -Content $templateRaw | Where-Object { 'Model ID' -in $_.Header } | Select-Object -First 1 | ForEach-Object { $_.Rows })
        $catalogRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-catalog.md') -Raw
        $script:AliasById = @{}
        foreach ($table in @(Get-MarkdownTable -Content $catalogRaw | Where-Object { 'Rate-row alias' -in $_.Header })) {
            foreach ($row in $table.Rows) { $script:AliasById[$row['Catalog ID']] = $row['Rate-row alias'] }
        }
    }

    It 'keeps Model (as routed) as the first column so the ledger parsers still key on it' {
        $header = @(Get-MarkdownTable -Content (Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'consumption-rates-template.md') -Raw) | Where-Object { 'Model ID' -in $_.Header } | Select-Object -First 1).Header
        $header[0] | Should -Be 'Model (as routed)'
        $header[1] | Should -Be 'Model ID'
    }

    It 'names every priced catalog id exactly once' {
        $ids = @($script:RateRows | ForEach-Object { $_['Model ID'] } | Where-Object { $_ -and $_ -ne '—' })
        ($ids | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name) -join ', ' | Should -BeNullOrEmpty
        (@($script:AliasById.Keys | Where-Object { $_ -notin $ids }) -join ', ') | Should -BeNullOrEmpty
    }

    It 'pairs each Model ID with the display name the catalog aliases it to' {
        $wrong = @(
            foreach ($row in $script:RateRows) {
                $id = $row['Model ID']
                if (-not $id -or $id -eq '—' -or $row['Model (as routed)'] -eq '(additional)') { continue }
                if ($script:AliasById[$id] -ne $row['Model (as routed)']) { "$id -> '$($row['Model (as routed)'])'" }
            }
        )
        $wrong -join ', ' | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-SquadModelRoute.ps1 ranks by fit, not by name (case l)' {
    BeforeAll {
        $script:Resolver = Join-Path $script:ReferencesRoot '../scripts/Resolve-SquadModelRoute.ps1'
        $seedRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'seed-templates.md') -Raw
        $script:SeedTeam = [regex]::Match($seedRaw, '(?s)## team\.md.*?```markdown\r?\n(?<b>.*?)```').Groups['b'].Value
        $script:CliEnum = @(
            'claude-sonnet-5', 'claude-opus-5', 'claude-opus-4.8', 'claude-opus-4.7', 'claude-haiku-5.5', 'claude-haiku-4.5', 'gpt-6-sol', 'gpt-6-luna'
            'gpt-6-astra', 'gpt-5.6-sol', 'gpt-5.6-sol-fast', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.5', 'gpt-5.4', 'gpt-5.4-mini'
            'gpt-5.3-codex', 'gpt-5-mini', 'mai-code-1.1-flash', 'gemini-3.8-flash', 'gemini-3.7-flash', 'gemini-3.6-flash'
            'gemini-3.5-flash', 'grok-4.5', 'claude-sonnet-5.5', 'gpt-6.1-sol', 'grok-4.6', 'grok-4.7', 'claude-opus-5.5'
        )

        function Initialize-RosterFixture {
            param([Parameter(Mandatory)][string]$Content)
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'team.md') -Value $Content -Encoding utf8NoBOM
            $root
        }

        function Invoke-Resolver {
            param([Parameter(Mandatory)][string]$Root, [hashtable]$Extra = @{})
            $benchmarkRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-benchmarks.md') -Raw
            $benchmarkDate = [regex]::Match($benchmarkRaw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*').Groups['date'].Value
            $parameters = @{ SquadRoot = $Root; AsOf = [datetime]$benchmarkDate }
            foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
            & $script:Resolver @parameters | ConvertFrom-Json
        }

        $catalogRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-catalog.md') -Raw
        $script:CapabilityOf = @{}
        foreach ($row in @(Get-MarkdownTable -Content $catalogRaw | Where-Object { 'Capability class' -in $_.Header } | ForEach-Object { $_.Rows })) {
            if ($row['Catalog ID']) { $script:CapabilityOf[$row['Catalog ID']] = $row['Capability class'] }
        }

        $script:FullRoot = Initialize-RosterFixture -Content $script:SeedTeam
        $script:Ranked = Invoke-Resolver -Root $script:FullRoot -Extra @{ AvailableModels = $script:CliEnum; Mode = 'ranked' }
        $script:PickOf = @{}
        foreach ($entry in $script:Ranked.roles) { $script:PickOf[$entry.role] = $entry.suggested }
    }

    It 'reads a roster with no mode line as off' {
        $script:Ranked.recordedMode | Should -Be 'off'
    }

    It 'documents snapshot-relative picks and records evidence in each ranked rationale' {
        $routingRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-routing.md') -Raw
        $example = [regex]::Match($routingRaw, '(?m)^\* \*\*Ranked on the Copilot CLI\*\*:.*$').Value
        $example | Should -Not -BeNullOrEmpty
        $example | Should -Match 'snapshot-relative'
        foreach ($entry in @($script:Ranked.roles | Where-Object suggested)) {
            $entry.rationale | Should -Match '\(evidence: .+@.+ \['
        }
    }

    It 'gives different classes different picks instead of one cheapest or first-alphabetical model' {
        @($script:Ranked.roles | Where-Object suggested | ForEach-Object suggested | Sort-Object -Unique).Count | Should -BeGreaterOrEqual 3
        $script:PickOf['researcher'] | Should -Not -Be $script:PickOf['lead']
    }

    It 'keeps a fast-floor role off frontier-reasoning rows under ranked selection' {
        $script:CapabilityOf[$script:PickOf['tester']] | Should -BeIn @('fast-lightweight', 'balanced', 'code-specialized')
        $script:CapabilityOf[$script:PickOf['scribe']] | Should -BeIn @('fast-lightweight', 'balanced', 'code-specialized')
    }

    It 'does not rank Haiku 5.5 when the host does not advertise it' {
        $available = @($script:CliEnum | Where-Object { $_ -ne 'claude-haiku-5.5' })
        $result = Invoke-Resolver -Root $script:FullRoot -Extra @{ AvailableModels = $available; Mode = 'ranked'; Role = @('scribe') }
        $result.roles[0].suggested | Should -BeIn $available
        $result.roles[0].suggested | Should -Not -Be 'claude-haiku-5.5'
        $script:CapabilityOf[$result.roles[0].suggested] | Should -BeIn @('fast-lightweight', 'balanced', 'code-specialized')
        @($result.roles[0].candidates | ForEach-Object id) | Should -Not -Contain 'claude-haiku-5.5'
    }

    It 'breaks an equal fit and price tie by generation, never by spelling' {
        $root = Initialize-RosterFixture -Content (@(
                '# Squad Roster', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Deliverable Root |'
                '|------|-------------|----------------------|------------|------------------|'
                '| scribe | | Squad Scribe | fast | (squad state) |'
            ) -join "`n")
        $result = Invoke-Resolver -Root $root -Extra @{ AvailableModels = @('gemini-3.6-flash', 'gemini-3.7-flash', 'gemini-3.8-flash') }
        $result.roles[0].suggested | Should -Be 'gemini-3.8-flash'
    }

    It 'never offers or ranks an unevaluated id, but reports it' {
        $script:Ranked.unevaluated | Should -Contain 'gpt-5.6-sol-fast'
        @($script:Ranked.roles | ForEach-Object { $_.candidates } | ForEach-Object { $_.id }) | Should -Not -Contain 'gpt-5.6-sol-fast'
    }

    It 'narrows a VS Code session to models priced at or below the session model' {
        $result = Invoke-Resolver -Root $script:FullRoot -Extra @{ SessionModel = 'claude-sonnet-5.5'; Mode = 'ranked'; Role = @('researcher', 'architect') }
        $result.availability | Should -Match 'unverified'
        foreach ($entry in $result.roles) { $entry.suggested | Should -Not -BeIn @('claude-opus-5.5', 'gpt-5.5', 'gpt-5.6-sol') }
    }

    It 'falls back to static tiers on a stale catalog' {
        $result = Invoke-Resolver -Root $script:FullRoot -Extra @{ AvailableModels = $script:CliEnum; AsOf = [datetime]'2027-06-01'; Role = @('lead') }
        $result.warnings.Count | Should -BeGreaterThan 0
        $result.roles[0].suggested | Should -BeNullOrEmpty
        $result.roles[0].rationale | Should -Be 'stale-catalog fallback'
    }

    It 'validates manual Model cells: <Cell> is <Status>' -ForEach @(
        @{ Tier = 'default'; Cell = 'claude-opus-4.8'; Status = 'valid' }
        @{ Tier = 'default'; Cell = 'claude-haiku-5.5'; Status = 'refused: below the default floor' }
        @{ Tier = 'default'; Cell = 'gpt-5.6-sol-fast'; Status = 'valid: unevaluated' }
        @{ Tier = 'default'; Cell = 'not-a-model'; Status = 'refused: unknown id' }
        @{ Tier = 'default'; Cell = 'gpt-5.5;rm'; Status = 'refused: metacharacter' }
        @{ Tier = 'default'; Cell = 'claude-fable-5'; Status = 'refused: not available on this host' }
        @{ Tier = 'fast'; Cell = 'claude-opus-5'; Status = 'valid' }
    ) {
        $root = Initialize-RosterFixture -Content (@(
                '# Squad Roster', '', 'Model routing: manual', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                "| architect | | System Architecture Reviewer | $Tier | $Cell | docs/architecture/ |"
            ) -join "`n")
        $result = Invoke-Resolver -Root $root -Extra @{ AvailableModels = $script:CliEnum }
        $result.recordedMode | Should -Be 'manual'
        $result.roles[0].cellStatus | Should -Be $Status
        if ($Status -like 'valid*') { $result.roles[0].resolved | Should -Be $Cell } else { $result.roles[0].resolved | Should -BeNullOrEmpty }
    }
}

Describe 'Seeded roster defaults for routing (case m)' {
    BeforeAll {
        $script:SeedRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'seed-templates.md') -Raw
    }

    It 'seeds intake-validator at the default floor, never fast' {
        $script:SeedRaw | Should -Match '\|\s*intake-validator\s*\|.*\|\s*default\s*\|'
    }

    It 'keeps the default (routing=off) roster free of a mode line and a Model column' {
        $team = [regex]::Match($script:SeedRaw, '(?s)## team\.md.*?```markdown\r?\n(?<b>.*?)```').Groups['b'].Value
        $team | Should -Not -Match '(?m)^Model routing:'
        $team | Should -Not -Match '\|\s*Model\s*\|'
    }
}

Describe 'Resolve-SquadModelRoute.ps1 economy mode (case n)' {
    BeforeAll {
        $script:Resolver = Join-Path $script:ReferencesRoot '../scripts/Resolve-SquadModelRoute.ps1'
        $seedRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'seed-templates.md') -Raw
        $script:SeedTeam = [regex]::Match($seedRaw, '(?s)## team\.md.*?```markdown\r?\n(?<b>.*?)```').Groups['b'].Value
        $script:CliEnum = @(
            'claude-sonnet-5', 'claude-opus-5', 'claude-opus-4.8', 'claude-opus-4.7', 'claude-haiku-5.5', 'claude-haiku-4.5', 'gpt-6-sol', 'gpt-6-luna'
            'gpt-6-astra', 'gpt-5.6-sol', 'gpt-5.6-sol-fast', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.5', 'gpt-5.4', 'gpt-5.4-mini'
            'gpt-5.3-codex', 'gpt-5-mini', 'mai-code-1.1-flash', 'gemini-3.8-flash', 'gemini-3.7-flash', 'gemini-3.6-flash'
            'gemini-3.5-flash', 'grok-4.5', 'claude-sonnet-5.5', 'gpt-6.1-sol', 'grok-4.6', 'grok-4.7', 'claude-opus-5.5'
        )

        function New-EconomyRoot {
            param([Parameter(Mandatory)][string]$Content, [string]$Under = $TestDrive)
            $root = Join-Path $Under ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'team.md') -Value $Content -Encoding utf8NoBOM
            $root
        }

        function Invoke-EconomyResolver {
            param([Parameter(Mandatory)][string]$Root, [hashtable]$Extra = @{}, [string]$Script = $script:Resolver)
            $parameters = @{
                SquadRoot      = $Root
                AsOf           = [datetime]'2026-10-15'
                AvailableModels = $script:CliEnum
                BenchmarksPath = Join-Path $TestDrive 'missing-economy-benchmarks.md'
            }
            foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
            & $Script @parameters | ConvertFrom-Json
        }

        # Expected economy pick computed straight from the catalog, independent of the resolver.
        $catalogRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-catalog.md') -Raw
        $tables = @(Get-MarkdownTable -Content $catalogRaw)
        $script:CapabilityOf = @{}
        foreach ($row in @($tables | Where-Object { 'Capability class' -in $_.Header } | ForEach-Object { $_.Rows })) { if ($row['Catalog ID']) { $script:CapabilityOf[$row['Catalog ID']] = $row['Capability class'] } }
        $script:EconomyFit = @($tables | Where-Object { 'Blended' -in $_.Header } | Select-Object -First 1 | ForEach-Object { $_.Rows })
        $script:FloorAdmits = @{
            fast    = @('fast-lightweight', 'balanced', 'code-specialized')
            default = @('balanced', 'code-specialized', 'frontier-reasoning')
        }
        function Get-ExpectedEconomyPick {
            param([string]$Floor)
            @($script:EconomyFit | Where-Object {
                    [int]$_['implementation'] -ge 2 -and $_['Catalog ID'] -in $script:CliEnum -and
                    $script:CapabilityOf[$_['Catalog ID']] -in $script:FloorAdmits[$Floor]
                } | Sort-Object { [double]$_['Blended'] }, { - [int]$_['implementation'] } | Select-Object -First 1)[0]['Catalog ID']
        }

        $script:SeedRoot = New-EconomyRoot -Content $script:SeedTeam
        $script:RankedRun = Invoke-EconomyResolver -Root $script:SeedRoot -Extra @{ Mode = 'ranked' }
        $script:EconomyRun = Invoke-EconomyResolver -Root $script:SeedRoot -Extra @{ Mode = 'economy' }
        $script:RankedOf = @{}
        foreach ($entry in $script:RankedRun.roles) { $script:RankedOf[$entry.role] = $entry.suggested }
        $script:EconomyOf = @{}
        foreach ($entry in $script:EconomyRun.roles) { $script:EconomyOf[$entry.role] = $entry }
    }

    It 'picks the cheapest fit >= 2 id within the real floor for an implementation role: <Role>' -ForEach @(
        @{ Role = 'technical-writer' }
        @{ Role = 'developer' }
    ) {
        $entry = $script:EconomyOf[$Role]
        $entry.class | Should -Be 'implementation'
        $entry.suggested | Should -Be (Get-ExpectedEconomyPick -Floor $entry.floor)
        $entry.resolved | Should -Be $entry.suggested
        $script:CapabilityOf[$entry.suggested] | Should -BeIn $script:FloorAdmits[$entry.floor] -Because 'economy never leaves the role''s own floor'
        $entry.rationale | Should -Match '^economy pick: '
    }

    It 'goes cheaper than ranked where the floor allows it (fast-floor technical-writer)' {
        $script:EconomyOf['technical-writer'].floor | Should -Be 'fast'
        $script:EconomyOf['technical-writer'].suggested | Should -Not -Be $script:RankedOf['technical-writer']
    }

    It 'never lowers a default-floor implementation role to a fast-lightweight model' {
        $defaults = @($script:EconomyRun.roles | Where-Object { $_.class -eq 'implementation' -and $_.floor -eq 'default' -and $_.suggested })
        $defaults.Count | Should -BeGreaterThan 0
        foreach ($entry in $defaults) { $script:CapabilityOf[$entry.suggested] | Should -Not -Be 'fast-lightweight' -Because "$($entry.role) floors at default" }
    }

    It 'keeps every review-class and other non-implementation role on its ranked pick' {
        $others = @($script:EconomyRun.roles | Where-Object { $_.class -ne 'implementation' })
        @($others | Where-Object class -eq 'review').Count | Should -BeGreaterThan 0
        foreach ($entry in $others) {
            $entry.suggested | Should -Be $script:RankedOf[$entry.role] -Because "$($entry.role) is $($entry.class)-class"
            $entry.escalation | Should -BeNullOrEmpty
        }
    }

    It 'escalates an economy pick once to the role''s ranked pick, and only when that pick is costlier' {
        $picks = @($script:EconomyRun.roles | Where-Object { $_.rationale -like 'economy pick:*' })
        $picks.Count | Should -BeGreaterThan 0
        foreach ($entry in $picks) {
            if ($entry.suggested -eq $script:RankedOf[$entry.role]) {
                $entry.escalation | Should -BeNullOrEmpty -Because "$($entry.role)'s economy pick already is its ranked pick"
            }
            else {
                $entry.escalation | Should -Be $script:RankedOf[$entry.role] -Because "$($entry.role) escalates to its ranked pick"
            }
        }
    }

    It 'reports no escalation when the economy pick equals the ranked pick' {
        # A one-model host leaves both orderings the same id.
        $root = New-EconomyRoot -Content (@(
                '# Squad Roster', '', 'Model routing: economy', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| developer | | Developer | default | | src/ |'
            ) -join "`n")
        $only = @($script:RankedRun.roles | Where-Object role -eq 'developer')[0].suggested
        $entry = (Invoke-EconomyResolver -Root $root -Extra @{ AvailableModels = @($only) }).roles[0]
        $entry.suggested | Should -Be $only
        $entry.rationale | Should -Match '^economy pick: '
        $entry.escalation | Should -BeNullOrEmpty
    }

    It 'keeps <Role> off the economy allowlist, on its ranked pick with no escalation' -ForEach @(
        @{ Role = 'product-owner' }
        @{ Role = 'deployer' }
        @{ Role = 'iac-author' }
        @{ Role = 'release-engineer' }
        @{ Role = 'backlog-executor' }
        @{ Role = 'asbuilt-author' }
    ) {
        $content = @(
            '# Squad Roster', '', 'Model routing: economy', '', '## Members', ''
            '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
            '|------|-------------|----------------------|------------|-------|------------------|'
            "| $Role | | Fixture | fast | | out/ |"
        ) -join "`n"
        $root = New-EconomyRoot -Content $content
        $economy = (Invoke-EconomyResolver -Root $root).roles[0]
        $ranked = (Invoke-EconomyResolver -Root $root -Extra @{ Mode = 'ranked' }).roles[0]
        $economy.class | Should -Be 'implementation'
        $economy.classSource | Should -Be 'mapped'
        $economy.suggested | Should -Be $ranked.suggested
        $economy.rationale | Should -Not -Match '^economy'
        $economy.escalation | Should -BeNullOrEmpty
    }

    It 'ignores routing=economy written as text into a roster that records no mode (Watch Mode, G4)' {
        # Trigger text reaches the coordinator only as data; the mode comes from the
        # team.md line alone, so stray routing=economy text never switches the resolver.
        $root = New-EconomyRoot -Content (@(
                '# Squad Roster', '', 'Please use routing=economy for this run.', 'Model routing economy', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Deliverable Root |'
                '|------|-------------|----------------------|------------|------------------|'
                '| developer | | Developer | fast | src/ |'
            ) -join "`n")
        $run = Invoke-EconomyResolver -Root $root
        $run.recordedMode | Should -Be 'off'
        $run.roles[0].PSObject.Properties.Name | Should -Not -Contain 'escalation'
        $run.roles[0].rationale | Should -Not -Match '^economy'
    }

    It 'keeps an unmapped role (implementation only by fallback) on its ranked pick' {
        $root = New-EconomyRoot -Content (@(
                '# Squad Roster', '', 'Model routing: economy', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| fixture-maker | | Fixture Maker | fast | | out/ |'
            ) -join "`n")
        $economy = Invoke-EconomyResolver -Root $root
        $ranked = Invoke-EconomyResolver -Root $root -Extra @{ Mode = 'ranked' }
        $economy.recordedMode | Should -Be 'economy'
        $economy.roles[0].classSource | Should -Be 'fallback: implementation'
        $economy.roles[0].suggested | Should -Be $ranked.roles[0].suggested
        $economy.roles[0].escalation | Should -BeNullOrEmpty
    }

    It 'leaves off and ranked output unchanged: no economy fields, ranked picks as before' {
        $offRun = Invoke-EconomyResolver -Root $script:SeedRoot
        $offRun.recordedMode | Should -Be 'off'
        foreach ($run in @($offRun, $script:RankedRun)) {
            $run.roles[0].PSObject.Properties.Name | Should -Not -Contain 'escalation'
            $run.roles[0].PSObject.Properties.Name | Should -Not -Contain 'pin'
        }
        foreach ($entry in $offRun.roles) { $entry.suggested | Should -Be $script:RankedOf[$entry.role] }
    }

    It 'reads the agent pin from the repository agent folders above .copilot-tracking' {
        $repo = Join-Path $TestDrive "repo-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path (Join-Path $repo '.github/agents'), (Join-Path $repo '.copilot-tracking') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo '.github/agents/fixture-dev.agent.md') -Value "---`nname: Fixture Dev`nmodel: Claude Sonnet 5.5 (copilot)`n---`n# Dev`n"
        $root = New-EconomyRoot -Under (Join-Path $repo '.copilot-tracking') -Content (@(
                '# Squad Roster', '', 'Model routing: economy', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| developer | | Fixture Dev | default | | src/ |'
            ) -join "`n")
        (Invoke-EconomyResolver -Root $root).roles[0].pin | Should -Be 'Claude Sonnet 5.5'
    }

    It 'finds the agent pin in an installed plugin agents/ folder when the repository has none' {
        $plugin = Join-Path $TestDrive "plugin-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path (Join-Path $plugin 'skills/squad'), (Join-Path $plugin 'agents') -Force | Out-Null
        $skill = Split-Path -Parent $script:ReferencesRoot
        Copy-Item -LiteralPath (Join-Path $skill 'scripts'), $script:ReferencesRoot -Destination (Join-Path $plugin 'skills/squad') -Recurse
        Set-Content -LiteralPath (Join-Path $plugin 'agents/fixture-writer.agent.md') -Value "---`nname: Fixture Writer`nmodel: Claude Haiku 5.5 (copilot)`n---`n# Writer`n"
        $root = New-EconomyRoot -Content (@(
                '# Squad Roster', '', 'Model routing: economy', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| technical-writer | | Fixture Writer | fast | | docs/ |'
            ) -join "`n")
        $result = Invoke-EconomyResolver -Root $root -Script (Join-Path $plugin 'skills/squad/scripts/Resolve-SquadModelRoute.ps1')
        $result.roles[0].pin | Should -Be 'Claude Haiku 5.5'
        $result.roles[0].suggested | Should -Be (Get-ExpectedEconomyPick -Floor 'fast')
    }

    Context 'economy consent is reported, never enforced (E2)' {
        BeforeAll {
            $script:ConsentTeam = @(
                '# Squad Roster', '', 'Model routing: economy', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| developer | | Developer | default | | src/ |'
            ) -join "`n"
            $script:Accepted = @(
                '# Squad Decisions', '', '## Economy Mode Accepted 2026-10-08T10:00:00Z', ''
                '* User: Fixture User', '* Previous mode: ranked', '* Trade accepted: cheaper allowlisted picks', '* Never weakened: every gate'
            ) -join "`n"
        }

        It 'reports consent: missing with a warning when decisions.md is absent' {
            $root = New-EconomyRoot -Content $script:ConsentTeam
            $run = Invoke-EconomyResolver -Root $root
            $run.consent | Should -Be 'missing'
            @($run.warnings | Where-Object { $_ -like 'economy consent not recorded*' }).Count | Should -Be 1
            $run.roles[0].resolved | Should -Not -BeNullOrEmpty -Because 'missing consent is a warning, never a refusal'
        }

        It 'reports consent: missing when decisions.md has no Economy Mode Accepted entry' {
            $root = New-EconomyRoot -Content $script:ConsentTeam
            Set-Content -LiteralPath (Join-Path $root 'decisions.md') -Value "# Squad Decisions`n`n## 2026-10-08T09:00:00Z Init`n`n* Roster seeded.`n" -Encoding utf8NoBOM
            (Invoke-EconomyResolver -Root $root).consent | Should -Be 'missing'
        }

        It 'reports consent: recorded, without the warning, when the entry exists' {
            $root = New-EconomyRoot -Content $script:ConsentTeam
            Set-Content -LiteralPath (Join-Path $root 'decisions.md') -Value $script:Accepted -Encoding utf8NoBOM
            $run = Invoke-EconomyResolver -Root $root
            $run.consent | Should -Be 'recorded'
            @($run.warnings | Where-Object { $_ -like 'economy consent*' }).Count | Should -Be 0
        }

        It 'prints the consent line in the table output' {
            $root = New-EconomyRoot -Content $script:ConsentTeam
            $missing = @(& $script:Resolver -SquadRoot $root -AsOf ([datetime]'2026-10-15') -AvailableModels $script:CliEnum -Format markdown)
            $missing | Should -Contain 'consent: missing'
            Set-Content -LiteralPath (Join-Path $root 'decisions.md') -Value $script:Accepted -Encoding utf8NoBOM
            $recorded = @(& $script:Resolver -SquadRoot $root -AsOf ([datetime]'2026-10-15') -AvailableModels $script:CliEnum -Format markdown)
            $recorded | Should -Contain 'consent: recorded'
        }

        It 'adds no consent field or line under off, ranked, or manual' {
            foreach ($mode in 'ranked', 'manual') {
                $run = Invoke-EconomyResolver -Root $script:SeedRoot -Extra @{ Mode = $mode }
                $run.PSObject.Properties.Name | Should -Not -Contain 'consent'
                @(& $script:Resolver -SquadRoot $script:SeedRoot -AsOf ([datetime]'2026-10-15') -AvailableModels $script:CliEnum -Mode $mode -Format markdown) -join "`n" | Should -Not -Match 'consent'
            }
            (Invoke-EconomyResolver -Root $script:SeedRoot).PSObject.Properties.Name | Should -Not -Contain 'consent'
        }
    }
}

Describe 'model-benchmarks.md knowledge base and provenance contract (#166, case o)' {
    BeforeAll {
        $script:Resolver = Join-Path $script:ReferencesRoot '../scripts/Resolve-SquadModelRoute.ps1'
        $script:BenchmarksPath = Join-Path $script:ReferencesRoot 'model-benchmarks.md'
        $script:BenchmarksRaw = Get-Content -LiteralPath $script:BenchmarksPath -Raw
        $script:BenchmarkTables = @(Get-MarkdownTable -Content $script:BenchmarksRaw)
        $seedRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'seed-templates.md') -Raw
        $script:SeedTeam = [regex]::Match($seedRaw, '(?s)## team\.md.*?```markdown\r?\n(?<b>.*?)```').Groups['b'].Value
        $script:CliEnum = @(
            'claude-sonnet-5', 'claude-opus-5', 'claude-opus-4.8', 'claude-opus-4.7', 'claude-haiku-5.5', 'claude-haiku-4.5', 'gpt-6-sol', 'gpt-6-luna'
            'gpt-6-astra', 'gpt-5.6-sol', 'gpt-5.6-sol-fast', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.5', 'gpt-5.4', 'gpt-5.4-mini'
            'gpt-5.3-codex', 'gpt-5.4-nano', 'gpt-5-mini', 'mai-code-1.1-flash', 'gemini-3.8-flash', 'gemini-3.7-flash', 'gemini-3.6-flash'
            'gemini-3.5-flash', 'grok-4.5', 'claude-sonnet-5.5', 'gpt-6.1-sol', 'grok-4.6', 'grok-4.7', 'claude-opus-5.5'
        )

        function New-BenchmarkRosterRoot {
            param([string]$Content = $script:SeedTeam)
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'team.md') -Value $Content -Encoding utf8NoBOM
            return $root
        }
    }

    Describe 'Sync-ModelBenchmarks produces evidence-derived, source-faithful snapshots (#166)' {
        BeforeAll {
            $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
            $script:SyncScript = Join-Path $repoRoot 'scripts/Sync-ModelBenchmarks.ps1'
            $script:Resolver = Join-Path $repoRoot 'squad-src/.github/skills/squad/scripts/Resolve-SquadModelRoute.ps1'
            $script:CatalogPath = Join-Path $repoRoot 'squad-src/.github/skills/squad/references/model-catalog.md'
            $script:WorkflowPath = Join-Path $repoRoot '.github/workflows/sync-model-benchmarks.yml'

            function New-SyncArchiveLocal {
                param([AllowEmptyCollection()][string[]]$ProcessedRows = @())

                $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                $eciRoot = Join-Path $root 'epoch_capabilities_index'
                New-Item -ItemType Directory -Path $eciRoot -Force | Out-Null
                @(
                    'model_id,benchmark_id,performance,benchmark,benchmark_release_date,model_lower,model_version,model_display,date,source'
                    $ProcessedRows
                ) | Set-Content -LiteralPath (Join-Path $eciRoot 'processed_data_for_eci.csv') -Encoding utf8NoBOM
                $root
            }

            function New-RoutingRootLocal {
                $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $root | Out-Null
                @(
                    '# Squad Roster'
                    ''
                    'Model routing: ranked'
                    ''
                    '## Members'
                    ''
                    '| Role | Member Name | Agent Name (Primary) | Model Tier | Deliverable Root |'
                    '|------|-------------|----------------------|------------|------------------|'
                    '| developer | | Squad Implementor | default | src/ |'
                ) | Set-Content -LiteralPath (Join-Path $root 'team.md') -Encoding utf8NoBOM
                $root
            }
        }

        It 'derives implementation fit from measured scores and routes the higher score even when it costs more' {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.100,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt56,swe,0.990,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
            )
            $output = Join-Path $TestDrive 'score-reversal.md'
            $result = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1')[-1]
            $result.ModelsCovered | Should -Be 2

            $tables = @(Get-MarkdownTable -Content (Get-Content -LiteralPath $output -Raw))
            $fit = @($tables | Where-Object { 'Composite' -in $_.Header -and 'implementation' -in $_.Header })[0]
            $byId = @{}
            foreach ($row in $fit.Rows) { $byId[$row['Catalog ID']] = $row }
            [int]$byId['gpt-5.4']['implementation'] | Should -Be 0
            [int]$byId['gpt-5.6-sol']['implementation'] | Should -Be 3

            $route = & $script:Resolver -SquadRoot (New-RoutingRootLocal) -AvailableModels @('gpt-5.4', 'gpt-5.6-sol') -Mode ranked -Role @('developer') -AsOf ([datetime]'2026-10-19') -BenchmarksPath $output | ConvertFrom-Json
            $route.roles[0].suggested | Should -Be 'gpt-5.6-sol'
            $route.roles[0].rationale | Should -Match 'fit 3 .*SWE-Bench verified'
        }

        It 'preserves source provenance, consumes Artificial Analysis indices, and excludes synthetic Hydra solver proxies' {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,frontier,0.400,FrontierCode,2026-06-08,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-18,https://cognition.com/frontiercode'
                'gptmini,swe,0.900,SWE-Bench verified,2024-08-13,gpt-5-mini,gpt-5-mini,GPT-5 mini,2026-10-18,OpenAI'
                'gpt56,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-18,vendor self-reported'
                'gpt61,swe,0.850,SWE-Bench verified,2024-08-13,gpt-6.1-sol,gpt-6.1-sol,GPT-6.1 Sol,2026-10-18,unverified user submission'
                'gpt6,swe,0.820,SWE-Bench verified,2024-08-13,gpt-6-sol,gpt-6-sol,GPT-6 Sol,2026-10-18,unverified Cognition user submission'
            )
            $aaPath = Join-Path $TestDrive 'aa.json'
            @{
                intelligence_index_version = '4.3.2'
                data = @(
                    @{
                        slug = 'gpt-5.4'
                        evaluations = @{
                            artificial_analysis_intelligence_index = 98
                            artificial_analysis_coding_index = 99
                        }
                    }
                )
            } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $aaPath -Encoding utf8NoBOM

            $output = Join-Path $TestDrive 'provenance.md'
            & $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -ArtificialAnalysisJsonPath $aaPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' | Out-Null
            $tables = @(Get-MarkdownTable -Content (Get-Content -LiteralPath $output -Raw))
            $scores = @($tables | Where-Object { 'Evaluation' -in $_.Header -and 'Provenance' -in $_.Header })[0]

            $frontier = @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5.4' -and $_['Evaluation'] -eq 'FrontierCode' })[0]
            $frontier['Source ID'] | Should -Be 'cognition-frontiercode'
            $frontier['Source version'] | Should -Be '2026-06-08'
            $frontier['Provenance'] | Should -Be 'independent'

            $vendor = @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5-mini' -and $_['Evaluation'] -eq 'SWE-Bench verified' })[0]
            $vendor['Source ID'] | Should -Be 'openai'
            $vendor['Provenance'] | Should -Be 'self-reported'

            $explicitSelfReport = @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5.6-sol' -and $_['Evaluation'] -eq 'SWE-Bench verified' })[0]
            $explicitSelfReport['Source ID'] | Should -Be 'vendor-self-reported'
            $explicitSelfReport['Provenance'] | Should -Be 'self-reported'

            $unverified = @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-6.1-sol' -and $_['Evaluation'] -eq 'SWE-Bench verified' })[0]
            $unverified['Source ID'] | Should -Be 'unverified-user-submission'
            $unverified['Provenance'] | Should -Be 'self-reported'

            $spoofedPublisher = @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-6-sol' -and $_['Evaluation'] -eq 'SWE-Bench verified' })[0]
            $spoofedPublisher['Source ID'] | Should -Be 'unverified-cognition-user-submission'
            $spoofedPublisher['Provenance'] | Should -Be 'self-reported'

            $aaCoding = @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5.4' -and $_['Evaluation'] -eq 'Artificial Analysis Coding Index' })[0]
            $aaCoding['Score'] | Should -Be '0.990'
            $aaCoding['Source version'] | Should -Be 'v4.3.2'

            @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'hydrafusion-max' }).Count | Should -Be 0
            $fit = @($tables | Where-Object { 'Composite' -in $_.Header -and 'implementation' -in $_.Header })[0]
            @($fit.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5-mini' }).Count | Should -Be 0
            @($fit.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5.6-sol' }).Count | Should -Be 0
            @($fit.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-6.1-sol' }).Count | Should -Be 0
            @($fit.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-6-sol' }).Count | Should -Be 0
            @($fit.Rows | Where-Object { $_['Catalog ID'] -eq 'hydrafusion-max' }).Count | Should -Be 0
        }

        It 'refuses empty independent coverage and preserves the last good snapshot' {
            $archive = New-SyncArchiveLocal
            $output = Join-Path $TestDrive 'last-good.md'
            Set-Content -LiteralPath $output -Value '# Last good snapshot' -Encoding utf8NoBOM -NoNewline
            $before = (Get-FileHash -LiteralPath $output).Hash

            { & $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') } |
                Should -Throw '*no usable independent model coverage*'
            (Get-FileHash -LiteralPath $output).Hash | Should -Be $before
        }

        It 'includes source versions in change detection' {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
            )
            $output = Join-Path $TestDrive 'version-digest.md'
            $first = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1')[-1]
            $second = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v2' -DryRun)[-1]

            $second.Updated | Should -BeTrue
            $second.Digest | Should -Not -Be $first.Digest
        }

        It 'uses a stable semantic archive version across retrieval-only dates and persists source URL changes' {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,frontier,0.800,FrontierCode,2026-06-08,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,https://cognition.com/frontiercode'
            )
            $output = Join-Path $TestDrive 'stable-version.md'
            $first = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19'))[-1]
            $second = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-20') -DryRun)[-1]
            $day59 = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-12-17') -DryRun)[-1]
            $day60 = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-12-18') -DryRun)[-1]

            $second.Updated | Should -BeFalse
            $second.Digest | Should -Be $first.Digest
            $day59.Updated | Should -BeFalse
            $day59.Digest | Should -Be $first.Digest
            $day60.Updated | Should -BeTrue
            $day60.Digest | Should -Be $first.Digest

            $changedArchive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,frontier,0.800,FrontierCode,2026-06-08,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,https://cognition.com/frontiercode-v2'
            )
            $changed = @(& $script:SyncScript -ArchivePath $changedArchive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-20'))[-1]
            $changed.Updated | Should -BeTrue
            $changed.Digest | Should -Not -Be $first.Digest
            Get-Content -LiteralPath $output -Raw | Should -Match '<https://cognition\.com/frontiercode-v2>'
        }

        It 'does not rewrite when only the derived fit view crosses the 90-day row boundary' {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.900,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-07-21,'
                'gpt56,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
            )
            $output = Join-Path $TestDrive 'age-only-fit-change.md'
            $first = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1')[-1]
            $second = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-20') -EpochVersion 'fixture-v1' -DryRun)[-1]

            $second.Updated | Should -BeFalse
            $second.Digest | Should -Be $first.Digest
        }

        It 'normalizes padded model display names and rejects conflicting duplicate evaluations before mutation' {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4," GPT-5.4 ",2026-10-19,'
            )
            $output = Join-Path $TestDrive 'normalized-display.md'
            $result = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1')[-1]
            $result.ModelsCovered | Should -Be 1
            Get-Content -LiteralPath $output -Raw | Should -Match '\| `gpt-5\.4` \| SWE-Bench verified \|'

            $before = (Get-FileHash -LiteralPath $output).Hash
            $conflicting = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.200,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt54,swe,0.900,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
            )
            { & $script:SyncScript -ArchivePath $conflicting -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' } |
                Should -Throw '*Conflicting benchmark rows*refusing row-order-dependent selection*'
            (Get-FileHash -LiteralPath $output).Hash | Should -Be $before
        }

        It 'preserves prior independent model coverage unless a reviewed reduction is explicit' {
            $broadArchive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.700,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt56,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
                'gpt61,swe,0.900,SWE-Bench verified,2024-08-13,gpt-6.1-sol,gpt-6.1-sol,GPT-6.1 Sol,2026-10-19,'
            )
            $output = Join-Path $TestDrive 'coverage-continuity.md'
            & $script:SyncScript -ArchivePath $broadArchive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' | Out-Null
            $before = (Get-FileHash -LiteralPath $output).Hash

            $narrowArchive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.700,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt56,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
            )
            { & $script:SyncScript -ArchivePath $narrowArchive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' } |
                Should -Throw '*would remove existing independent evidence coverage*gpt-6.1-sol/SWE-Bench verified*AllowCoverageReduction*'
            (Get-FileHash -LiteralPath $output).Hash | Should -Be $before

            $accepted = @(& $script:SyncScript -ArchivePath $narrowArchive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' -AllowCoverageReduction)[-1]
            $accepted.ModelsCovered | Should -Be 2
            Get-Content -LiteralPath $output -Raw | Should -Not -Match '\| `gpt-6\.1-sol` \|'
        }

        It 'requires the same explicit override when an evaluation disappears but model coverage remains' {
            $broadArchive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.700,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt54,os,0.600,OSWorld 2.0,2026-06-26,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,https://osworld-v2.xlang.ai/'
                'gpt56,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
            )
            $output = Join-Path $TestDrive 'score-coverage-continuity.md'
            & $script:SyncScript -ArchivePath $broadArchive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' | Out-Null
            $before = (Get-FileHash -LiteralPath $output).Hash

            $narrowArchive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.700,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt56,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
            )
            { & $script:SyncScript -ArchivePath $narrowArchive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' } |
                Should -Throw '*would remove existing independent evidence coverage*gpt-5.4/OSWorld 2.0*AllowCoverageReduction*'
            (Get-FileHash -LiteralPath $output).Hash | Should -Be $before
        }

        It 'materializes the same primary-plus-secondary class aggregation the router consumes' {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.900,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt54,os,0.100,OSWorld 2.0,2026-06-26,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,https://osworld-v2.xlang.ai/'
                'gpt56,swe,0.600,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
                'gpt56,os,0.900,OSWorld 2.0,2026-06-26,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,https://osworld-v2.xlang.ai/'
            )
            $output = Join-Path $TestDrive 'aggregation-consistency.md'
            & $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' | Out-Null

            $tables = @(Get-MarkdownTable -Content (Get-Content -LiteralPath $output -Raw))
            $fit = @($tables | Where-Object { 'Composite' -in $_.Header -and 'implementation' -in $_.Header })[0]
            $fitById = @{}
            foreach ($row in $fit.Rows) { $fitById[$row['Catalog ID']] = [int]$row['implementation'] }
            $fitById['gpt-5.4'] | Should -Be 2
            $fitById['gpt-5.6-sol'] | Should -Be 3

            $route = & $script:Resolver -SquadRoot (New-RoutingRootLocal) -AvailableModels @('gpt-5.4', 'gpt-5.6-sol') -Mode ranked -Role @('developer') -AsOf ([datetime]'2026-10-19') -BenchmarksPath $output | ConvertFrom-Json
            foreach ($candidate in $route.roles[0].candidates) {
                if ($fitById.ContainsKey($candidate.id)) {
                    $candidate.fit | Should -Be $fitById[$candidate.id]
                }
            }
            $route.roles[0].suggested | Should -Be 'gpt-5.6-sol'
        }

        It 'writes a transient snapshot for dry-run validation but gates publication on the typed boolean' {
            $workflow = Get-Content -LiteralPath $script:WorkflowPath -Raw
            $workflow | Should -Match "if:\s*steps\.sync\.outputs\.updated == 'true' && !inputs\.dry_run"
            $workflow | Should -Not -Match "inputs\.dry_run != 'true'"
            $workflow | Should -Not -Match '\$params\[''DryRun''\]'
            $workflow | Should -Match 'allow_coverage_reduction:'
            $workflow | Should -Match '\$params\[''AllowCoverageReduction''\]\s*=\s*\$true'
        }
    }

    It 'declares a parsable Retrieved date, a SHA-256 Content Digest, and verified source licensing' {
        $dateMatch = [regex]::Match($script:BenchmarksRaw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*')
        $dateMatch.Success | Should -BeTrue
        { [datetime]::ParseExact($dateMatch.Groups['date'].Value, 'yyyy-MM-dd', $null) } | Should -Not -Throw

        $digestMatch = [regex]::Match($script:BenchmarksRaw, '\*\*Content Digest:\s*sha256:[0-9a-f]{64}\*\*')
        $digestMatch.Success | Should -BeTrue

        $sourceTable = @($script:BenchmarkTables | Where-Object { 'Source ID' -in $_.Header -and 'License' -in $_.Header })[0]
        $sourceTable | Should -Not -BeNullOrEmpty
        $bySource = @{}
        foreach ($r in $sourceTable.Rows) {
            $bySource[$r['Source ID']] = $r
        }
        $bySource['epoch-ai']['License'] | Should -Be 'CC-BY-4.0'
        $bySource['epoch-ai']['Status'] | Should -Be 'active'
        $bySource['artificial-analysis']['Status'] | Should -Be 'active'
        $bySource['llm-stats']['Status'] | Should -Be 'excluded'
        $bySource['lmarena']['Status'] | Should -Be 'excluded'
    }

    It 'documents an evidence mapping for every one of the seven assignment classes' {
        $mappingTable = @($script:BenchmarkTables | Where-Object { 'Assignment class' -in $_.Header -and 'Primary evaluations' -in $_.Header })[0]
        $mappingTable | Should -Not -BeNullOrEmpty
        $mappedClasses = @($mappingTable.Rows | ForEach-Object { $_['Assignment class'] } | Sort-Object)
        $mappedClasses | Should -Be (@('bookkeeping', 'council', 'implementation', 'intake', 'planning', 'research', 'review') | Sort-Object)
        foreach ($row in $mappingTable.Rows) {
            $row['Primary evaluations'] | Should -Not -BeNullOrEmpty
            $row['Primary sources'] | Should -Not -BeNullOrEmpty
        }
    }

    It 'tags every score row with source, version, date, and provenance (independent or self-reported)' {
        $scoreTable = @($script:BenchmarkTables | Where-Object { 'Catalog ID' -in $_.Header -and 'Evaluation' -in $_.Header -and 'Provenance' -in $_.Header })[0]
        $scoreTable | Should -Not -BeNullOrEmpty
        $scoreTable.Rows.Count | Should -BeGreaterThan 100

        $invalid = @(
            foreach ($row in $scoreTable.Rows) {
                if (-not $row['Catalog ID'] -or -not $row['Evaluation'] -or $row['Score'] -notmatch '^-?\d+(\.\d+)?$' -or -not $row['Source ID'] -or -not $row['Source version'] -or $row['Retrieved'] -notmatch '^\d{4}-\d{2}-\d{2}$' -or $row['Provenance'] -notin @('independent', 'self-reported')) {
                    "$($row['Catalog ID'])/$($row['Evaluation']): prov='$($row['Provenance'])'"
                }
            }
        )
        $invalid -join ', ' | Should -BeNullOrEmpty
    }

    It 'falls back for malformed benchmark evidence under ranked and leaves manual/off behavior unchanged' {
        $root = New-BenchmarkRosterRoot
        $badBenchmarks = Join-Path $TestDrive 'bad-provenance-benchmarks.md'
        $badContent = @(
            '# Bad Benchmarks'
            '* **Retrieved: 2026-10-18**'
            ''
            '## Benchmark Scores'
            ''
            '| Catalog ID | Evaluation | Category | Score | Source ID | Source version | Retrieved | Provenance |'
            '| --- | --- | --- | ---: | --- | --- | --- | --- |'
            '| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 0.913 | `epoch-ai` | `2026-10-18` | `2026-10-18` |  |'
        ) -join "`n"
        Set-Content -LiteralPath $badBenchmarks -Value $badContent -Encoding utf8NoBOM

        $ranked = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Mode ranked -Role @('lead') -AsOf ([datetime]'2026-10-18') -BenchmarksPath $badBenchmarks | ConvertFrom-Json
        $ranked.warnings.Count | Should -Be 1
        $ranked.warnings[0] | Should -Match 'could not be parsed.*Provenance.*ranking falls back'
        $ranked.roles[0].rationale | Should -Match '\(declared-fit fallback\)'

        $manual = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Mode manual -Role @('lead') -AsOf ([datetime]'2026-10-18') -BenchmarksPath $badBenchmarks | ConvertFrom-Json
        $manual.warnings | Should -BeNullOrEmpty

        $off = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Role @('lead') -AsOf ([datetime]'2026-10-18') -BenchmarksPath $badBenchmarks | ConvertFrom-Json
        $off.recordedMode | Should -Be 'off'
        $off.warnings | Should -BeNullOrEmpty
    }

    It 'treats invalid headers, out-of-range or conflicting scores, and future dates as ranked-only fallback evidence' {
        $root = New-BenchmarkRosterRoot
        $cases = @(
            @{
                Name = 'invalid-header'
                HeaderDate = '2026-02-30'
                Rows = @('| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 0.900 | `epoch-ai` | `fixture-v1` | `2026-10-19` | `independent` |')
                Error = 'Invalid benchmark snapshot Retrieved date'
            }
            @{
                Name = 'high-score'
                HeaderDate = '2026-10-19'
                Rows = @('| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 9.99 | `epoch-ai` | `fixture-v1` | `2026-10-19` | `independent` |')
                Error = 'normalized scores must be between'
            }
            @{
                Name = 'negative-score'
                HeaderDate = '2026-10-19'
                Rows = @('| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | -0.99 | `epoch-ai` | `fixture-v1` | `2026-10-19` | `independent` |')
                Error = 'normalized scores must be between'
            }
            @{
                Name = 'conflicting-duplicate'
                HeaderDate = '2026-10-19'
                Rows = @(
                    '| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 0.900 | `epoch-ai` | `fixture-v1` | `2026-10-19` | `independent` |'
                    '| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 0.800 | `epoch-ai` | `fixture-v1` | `2026-10-19` | `independent` |'
                )
                Error = 'Conflicting duplicate benchmark score rows'
            }
            @{
                Name = 'future-header'
                HeaderDate = '2026-10-20'
                Rows = @('| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 0.900 | `epoch-ai` | `fixture-v1` | `2026-10-19` | `independent` |')
                Error = 'snapshot Retrieved date.*is after routing date'
            }
            @{
                Name = 'future-row'
                HeaderDate = '2026-10-19'
                Rows = @('| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 0.900 | `epoch-ai` | `fixture-v1` | `2026-10-20` | `independent` |')
                Error = 'score date.*is after routing date'
            }
        )

        foreach ($case in $cases) {
            $path = Join-Path $TestDrive "$($case.Name)-invalid-benchmarks.md"
            Set-Content -LiteralPath $path -Value (@(
                    '# Invalid Benchmarks'
                    "* **Retrieved: $($case.HeaderDate)**"
                    ''
                    '## Assignment Class Evidence Mapping'
                    ''
                    '| Assignment class | Primary evaluations | Secondary evaluations | Primary sources | Evidence rule |'
                    '| --- | --- | --- | --- | --- |'
                    '| `planning` | `GPQA diamond` |  | `epoch-ai` | test |'
                    ''
                    '## Benchmark Scores'
                    ''
                    '| Catalog ID | Evaluation | Category | Score | Source ID | Source version | Retrieved | Provenance |'
                    '| --- | --- | --- | ---: | --- | --- | --- | --- |'
                    $case.Rows
                ) -join "`n") -Encoding utf8NoBOM

            $ranked = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Mode ranked -Role @('lead') -AsOf ([datetime]'2026-10-19') -BenchmarksPath $path | ConvertFrom-Json
            $ranked.warnings.Count | Should -Be 1 -Because $case.Name
            $ranked.warnings[0] | Should -Match "could not be parsed.*$($case.Error).*ranking falls back" -Because $case.Name
            $ranked.roles[0].rationale | Should -Match '\(declared-fit fallback\)' -Because $case.Name

            $manual = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Mode manual -Role @('lead') -AsOf ([datetime]'2026-10-19') -BenchmarksPath $path | ConvertFrom-Json
            $manual.warnings | Should -BeNullOrEmpty -Because $case.Name

            $off = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Role @('lead') -AsOf ([datetime]'2026-10-19') -BenchmarksPath $path | ConvertFrom-Json
            $off.recordedMode | Should -Be 'off' -Because $case.Name
            $off.warnings | Should -BeNullOrEmpty -Because $case.Name
        }
    }

    It 'uses independent benchmark evidence before model-catalog.md and records source, version, and evaluations in Route rationale' {
        $root = New-BenchmarkRosterRoot
        $snapshotDate = [regex]::Match($script:BenchmarksRaw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*').Groups['date'].Value
        $run = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Mode ranked -Role @('researcher', 'lead', 'developer') -AsOf ([datetime]$snapshotDate) | ConvertFrom-Json
        $run.benchmarksRetrieved | Should -Be $snapshotDate
        $run.warnings | Should -BeNullOrEmpty
        foreach ($roleEntry in $run.roles) {
            $roleEntry.rationale | Should -Match '\(evidence: .+@.+ \['
        }

        # Override benchmark evidence so claude-opus-4.8 has fit 3 in research while claude-opus-5.5 has fit 2
        # (reversing model-catalog.md's declared fit table) and verify routing=ranked follows the benchmark evidence.
        $customBench = Join-Path $TestDrive 'override-benchmarks.md'
        $customContent = @(
            '# Custom Benchmarks'
            '* **Retrieved: 2026-10-18**'
            ''
            '## Assignment Class Evidence Mapping'
            ''
            '| Assignment class | Primary evaluations | Secondary evaluations | Primary sources | Evidence rule |'
            '| --- | --- | --- | --- | --- |'
            '| `research` | `GDP.pdf`, `GPQA diamond` | `CritPt` | `artificial-analysis`, `epoch-ai` | test |'
            ''
            '## Benchmark Scores'
            ''
            '| Catalog ID | Evaluation | Category | Score | Source ID | Source version | Retrieved | Provenance |'
            '| --- | --- | --- | ---: | --- | --- | --- | --- |'
            '| `claude-opus-4.8` | GDP.pdf | `general-long-doc` | 0.920 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |'
            '| `claude-opus-5.5` | GDP.pdf | `general-long-doc` | 0.600 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |'
        ) -join "`n"
        Set-Content -LiteralPath $customBench -Value $customContent -Encoding utf8NoBOM

        $overridden = & $script:Resolver -SquadRoot $root -AvailableModels @('claude-opus-4.8', 'claude-opus-5.5') -Mode ranked -Role @('researcher') -AsOf ([datetime]'2026-10-18') -BenchmarksPath $customBench | ConvertFrom-Json
        $overridden.roles[0].suggested | Should -Be 'claude-opus-4.8'
        $overridden.roles[0].rationale | Should -Match 'artificial-analysis@v4\.3\.2 \[GDP\.pdf\]'
    }

    It 'never lets self-reported scores decide or boost a ranked pick alone' {
        $root = New-BenchmarkRosterRoot
        $selfReportBench = Join-Path $TestDrive 'self-reported-benchmarks.md'
        $selfReportContent = @(
            '# Self-Reported Test Benchmarks'
            '* **Retrieved: 2026-10-18**'
            ''
            '## Assignment Class Evidence Mapping'
            ''
            '| Assignment class | Primary evaluations | Secondary evaluations | Primary sources | Evidence rule |'
            '| --- | --- | --- | --- | --- |'
            '| `planning` | `FrontierMath-Tiers-1-3-v2` |  | `epoch-ai` | test |'
            ''
            '## Benchmark Scores'
            ''
            '| Catalog ID | Evaluation | Category | Score | Source ID | Source version | Retrieved | Provenance |'
            '| --- | --- | --- | ---: | --- | --- | --- | --- |'
            '| `gpt-5.4` | FrontierMath-Tiers-1-3-v2 | `math` | 0.999 | `vendor-model-card` | `2026-10` | `2026-10-18` | `self-reported` |'
            '| `gpt-5.6-sol` | FrontierMath-Tiers-1-3-v2 | `math` | 0.891 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |'
        ) -join "`n"
        Set-Content -LiteralPath $selfReportBench -Value $selfReportContent -Encoding utf8NoBOM

        # gpt-5.4 is cheaper (Blended 1.000 vs 1.920) and has a 0.999 self-reported score,
        # but only gpt-5.6-sol has independent benchmark evidence, so gpt-5.6-sol wins.
        $res = & $script:Resolver -SquadRoot $root -AvailableModels @('gpt-5.4', 'gpt-5.6-sol') -Mode ranked -Role @('lead') -AsOf ([datetime]'2026-10-18') -BenchmarksPath $selfReportBench | ConvertFrom-Json
        $res.roles[0].suggested | Should -Be 'gpt-5.6-sol'
        $res.roles[0].rationale | Should -Match 'epoch-ai@2026-10-18 \[FrontierMath-Tiers-1-3-v2\]'

        # When only a self-reported model (mai-code-1.1-flash) is available, it falls back to declared fit and logs a warning.
        $currentSnapshotDate = [regex]::Match($script:BenchmarksRaw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*').Groups['date'].Value
        $onlySelfReported = & $script:Resolver -SquadRoot $root -AvailableModels @('mai-code-1.1-flash') -Mode ranked -Role @('scribe') -AsOf ([datetime]$currentSnapshotDate) | ConvertFrom-Json
        $onlySelfReported.roles[0].suggested | Should -Be 'mai-code-1.1-flash'
        $onlySelfReported.roles[0].rationale | Should -Match '\(declared-fit fallback\)'
        $onlySelfReported.warnings.Count | Should -Be 1
        $onlySelfReported.warnings[0] | Should -Match 'missing independent benchmark evidence for mai-code-1\.1-flash'
    }

    It 'falls back to the declared fit table in model-catalog.md and logs one warning when model-benchmarks.md is missing or stale' {
        $root = New-BenchmarkRosterRoot
        $currentSnapshotDate = [regex]::Match($script:BenchmarksRaw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*').Groups['date'].Value
        $missingPath = Join-Path $TestDrive 'does-not-exist-benchmarks.md'
        $missingRun = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Mode ranked -Role @('lead') -AsOf ([datetime]$currentSnapshotDate) -BenchmarksPath $missingPath | ConvertFrom-Json
        $missingRun.warnings.Count | Should -Be 1
        $missingRun.warnings[0] | Should -Match 'model-benchmarks\.md was not found; ranking falls back to the declared fit table'
        $missingRun.roles[0].suggested | Should -Be 'gpt-5.6-sol'
        $missingRun.roles[0].rationale | Should -Match '\(declared-fit fallback\)'

        $staleBench = Join-Path $TestDrive 'stale-benchmarks.md'
        Set-Content -LiteralPath $staleBench -Value ($script:BenchmarksRaw -replace '\*\*Retrieved:\s*\d{4}-\d{2}-\d{2}\*\*', '**Retrieved: 2026-01-01**') -Encoding utf8NoBOM
        $staleRun = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Mode ranked -Role @('lead') -AsOf ([datetime]$currentSnapshotDate) -BenchmarksPath $staleBench | ConvertFrom-Json
        $staleRun.warnings.Count | Should -Be 1
        $staleRun.warnings[0] | Should -Match "model-benchmarks\.md was retrieved 2026-01-01, more than 90 days before $currentSnapshotDate; ranking falls back to the declared fit table"
        $staleRun.roles[0].suggested | Should -Be 'gpt-5.6-sol'
        $staleRun.roles[0].rationale | Should -Match '\(declared-fit fallback\)'
    }

    It 'treats stale score rows and missing class mappings as missing evidence instead of promoting unrelated scores' {
        $root = New-BenchmarkRosterRoot
        $cases = @(
            @{
                Name = 'stale-row'
                Mapping = '| `planning` | `GPQA diamond` |  | `epoch-ai` | test |'
                Score = '| `gpt-5.4` | GPQA diamond | `scientific-reasoning` | 0.990 | `epoch-ai` | `2026-10-18` | `2020-01-01` | `independent` |'
            }
            @{
                Name = 'missing-class-map'
                Mapping = '| `research` | `SciCode` |  | `artificial-analysis` | test |'
                Score = '| `gpt-5.4` | SciCode | `coding` | 0.990 | `artificial-analysis` | `v4.3.2` | `2026-10-18` | `independent` |'
            }
        )

        foreach ($case in $cases) {
            $path = Join-Path $TestDrive "$($case.Name)-benchmarks.md"
            Set-Content -LiteralPath $path -Value (@(
                    '# Test Benchmarks'
                    '* **Retrieved: 2026-10-18**'
                    ''
                    '## Assignment Class Evidence Mapping'
                    ''
                    '| Assignment class | Primary evaluations | Secondary evaluations | Primary sources | Evidence rule |'
                    '| --- | --- | --- | --- | --- |'
                    $case.Mapping
                    ''
                    '## Benchmark Scores'
                    ''
                    '| Catalog ID | Evaluation | Category | Score | Source ID | Source version | Retrieved | Provenance |'
                    '| --- | --- | --- | ---: | --- | --- | --- | --- |'
                    $case.Score
                ) -join "`n") -Encoding utf8NoBOM

            $run = & $script:Resolver -SquadRoot $root -AvailableModels @('gpt-5.4') -Mode ranked -Role @('lead') -AsOf ([datetime]'2026-10-18') -BenchmarksPath $path | ConvertFrom-Json
            $run.roles[0].suggested | Should -Be 'gpt-5.4'
            $run.roles[0].rationale | Should -Match '\(declared-fit fallback\)'
            $run.warnings.Count | Should -Be 1
            $run.warnings[0] | Should -Match 'missing independent benchmark evidence'
        }
    }

    It 'canonicalizes the short HydraFusion alias for ranked availability and manual cells' {
        $root = New-BenchmarkRosterRoot
        $ranked = & $script:Resolver -SquadRoot $root -AvailableModels @('hydrafusion') -Mode ranked -Role @('developer') -AsOf ([datetime]'2026-10-18') | ConvertFrom-Json
        $ranked.unevaluated | Should -BeNullOrEmpty
        $ranked.roles[0].suggested | Should -Be 'hydrafusion'

        $manualRoot = New-BenchmarkRosterRoot -Content (@(
                '# Squad Roster', '', 'Model routing: manual', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| developer | | Squad Implementor | default | hydrafusion | src/ |'
            ) -join "`n")
        $manual = & $script:Resolver -SquadRoot $manualRoot -AvailableModels @('hydrafusion') -Mode manual -Role @('developer') -AsOf ([datetime]'2026-10-18') | ConvertFrom-Json
        $manual.roles[0].cellStatus | Should -Be 'valid'
        $manual.roles[0].resolved | Should -Be 'hydrafusion'
        $manual.warnings | Should -BeNullOrEmpty

        $canonicalOnlyRoot = New-BenchmarkRosterRoot -Content (@(
                '# Squad Roster', '', 'Model routing: manual', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| developer | | Squad Implementor | default | hydrafusion-max | src/ |'
            ) -join "`n")
        $canonicalOnly = & $script:Resolver -SquadRoot $canonicalOnlyRoot -AvailableModels @('hydrafusion') -Mode manual -Role @('developer') -AsOf ([datetime]'2026-10-18') | ConvertFrom-Json
        $canonicalOnly.roles[0].cellStatus | Should -Be 'refused: not available on this host'
        $canonicalOnly.roles[0].resolved | Should -BeNullOrEmpty
    }

    It 'contains no network cmdlets in Resolve-SquadModelRoute.ps1 so runtime dispatches never fetch live web pages' {
        $resolverRaw = Get-Content -LiteralPath $script:Resolver -Raw
        $bannedPattern = 'Invoke-WebRequest|Invoke-RestMethod|System\.Net\.(WebClient|Http)|New-WebServiceProxy|Start-BitsTransfer|curl(\.exe)?\s|wget\s|gh\s+api'
        $resolverRaw | Should -Not -Match $bannedPattern
    }
}