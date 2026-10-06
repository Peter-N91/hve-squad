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
        $scribeAgentRaw | Should -Match '(?m)^model:\s*Claude Haiku 4\.5'

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
        $script:CapabilityIds = @($tables | Where-Object { 'Capability class' -in $_.Header } | ForEach-Object { $_.Rows } | ForEach-Object { $_['Catalog ID'] })
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
            'claude-sonnet-5', 'claude-opus-5', 'claude-opus-4.8', 'claude-opus-4.7', 'claude-haiku-4.5', 'gpt-6-sol', 'gpt-6-luna'
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
            $parameters = @{ SquadRoot = $Root; AsOf = [datetime]'2026-10-01' }
            foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
            & $script:Resolver @parameters | ConvertFrom-Json
        }

        $script:FullRoot = Initialize-RosterFixture -Content $script:SeedTeam
        $script:Ranked = Invoke-Resolver -Root $script:FullRoot -Extra @{ AvailableModels = $script:CliEnum; Mode = 'ranked' }
        $script:PickOf = @{}
        foreach ($entry in $script:Ranked.roles) { $script:PickOf[$entry.role] = $entry.suggested }
    }

    It 'reads a roster with no mode line as off' {
        $script:Ranked.recordedMode | Should -Be 'off'
    }

    It 'matches every pick the model-routing.md ranked worked example documents' {
        $routingRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-routing.md') -Raw
        $example = [regex]::Match($routingRaw, '(?m)^\* \*\*Ranked on the Copilot CLI\*\*:.*$').Value
        $example | Should -Not -BeNullOrEmpty
        $pairs = @([regex]::Matches($example, '`(?<role>[a-z-]+)`(?: \([^)]*\))? → `(?<id>[a-z0-9.-]+)`'))
        $pairs.Count | Should -BeGreaterThan 5
        foreach ($pair in $pairs) {
            $script:PickOf[$pair.Groups['role'].Value] | Should -Be $pair.Groups['id'].Value -Because "the worked example names $($pair.Value)"
        }
    }

    It 'gives different classes different picks instead of one cheapest or first-alphabetical model' {
        @($script:Ranked.roles | Where-Object suggested | ForEach-Object suggested | Sort-Object -Unique).Count | Should -BeGreaterOrEqual 5
        $script:PickOf['intake-validator'] | Should -Not -BeLike 'gemini-*'
        $script:PickOf['researcher'] | Should -Not -Be $script:PickOf['lead']
    }

    It 'keeps a fast-floor role off frontier-reasoning rows under ranked selection' {
        $script:PickOf['tester'] | Should -Be 'gpt-6-sol'
        $script:PickOf['scribe'] | Should -Be 'claude-haiku-4.5'
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
        $result = Invoke-Resolver -Root $script:FullRoot -Extra @{ SessionModel = 'claude-sonnet-5'; Mode = 'ranked'; Role = @('researcher', 'architect') }
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
        @{ Tier = 'default'; Cell = 'claude-haiku-4.5'; Status = 'refused: below the default floor' }
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
            'claude-sonnet-5', 'claude-opus-5', 'claude-opus-4.8', 'claude-opus-4.7', 'claude-haiku-4.5', 'gpt-6-sol', 'gpt-6-luna'
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
            $parameters = @{ SquadRoot = $Root; AsOf = [datetime]'2026-10-01'; AvailableModels = $script:CliEnum }
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
        Set-Content -LiteralPath (Join-Path $repo '.github/agents/fixture-dev.agent.md') -Value "---`nname: Fixture Dev`nmodel: Claude Sonnet 5 (copilot)`n---`n# Dev`n"
        $root = New-EconomyRoot -Under (Join-Path $repo '.copilot-tracking') -Content (@(
                '# Squad Roster', '', 'Model routing: economy', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| developer | | Fixture Dev | default | | src/ |'
            ) -join "`n")
        (Invoke-EconomyResolver -Root $root).roles[0].pin | Should -Be 'Claude Sonnet 5'
    }

    It 'finds the agent pin in an installed plugin agents/ folder when the repository has none' {
        $plugin = Join-Path $TestDrive "plugin-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path (Join-Path $plugin 'skills/squad'), (Join-Path $plugin 'agents') -Force | Out-Null
        $skill = Split-Path -Parent $script:ReferencesRoot
        Copy-Item -LiteralPath (Join-Path $skill 'scripts'), $script:ReferencesRoot -Destination (Join-Path $plugin 'skills/squad') -Recurse
        Set-Content -LiteralPath (Join-Path $plugin 'agents/fixture-writer.agent.md') -Value "---`nname: Fixture Writer`nmodel: Claude Haiku 4.5 (copilot)`n---`n# Writer`n"
        $root = New-EconomyRoot -Content (@(
                '# Squad Roster', '', 'Model routing: economy', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| technical-writer | | Fixture Writer | fast | | docs/ |'
            ) -join "`n")
        $result = Invoke-EconomyResolver -Root $root -Script (Join-Path $plugin 'skills/squad/scripts/Resolve-SquadModelRoute.ps1')
        $result.roles[0].pin | Should -Be 'Claude Haiku 4.5'
        $result.roles[0].suggested | Should -Be (Get-ExpectedEconomyPick -Floor 'fast')
    }
}