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
    . (Join-Path $script:ReferencesRoot '../scripts/ModelBenchmarkScoring.ps1')

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

    function New-FixtureEvidenceRow {
        param(
            [string]$Id, [string]$Evaluation, [string]$Score = '0.600',
            [string]$Version = 'fixture-v3', [string]$Date = '2026-10-19',
            [string]$ResultDate = 'unknown', [string]$Provenance = 'independent',
            [string]$SourceId = 'epoch-ai', [string]$Category = 'fixture',
            [string]$ModelVersion, [string]$Configuration = 'synthetic-evaluation-protocol-v1',
            [string]$Verification = 'verified'
        )
        if (-not $ModelVersion) {
            $ModelVersion = if ($Id -like 'claude-*') { $Id -replace '\.', '-' } else { $Id }
        }
        $hosts = (Get-SquadBenchmarkPolicy).SourceHosts
        [pscustomobject]@{
            CatalogId = $Id; Evaluation = $Evaluation; Category = $Category; NumericScore = $Score
            SourceId = $SourceId; SourceVersion = $Version; ModelVersion = $ModelVersion
            Configuration = $Configuration; ResultDate = $ResultDate; Retrieved = $Date; Verified = $Date
            Verification = $Verification
            SourceUrl = if ($hosts.ContainsKey($SourceId)) { "https://$($hosts[$SourceId])/synthetic-fixture" } else { 'unknown' }
            VerificationBasis = 'sha256:' + ('a' * 64)
            VerificationReason = 'explicit synthetic test evidence, not real model measurements or source verification'
            LegacyDate = 'unknown'; Provenance = $Provenance
        }
    }

    function ConvertTo-VerifiedFixtureSnapshot {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Attaches explicit synthetic verification only to a Pester TestDrive fixture.')]
        param([Parameter(Mandatory)][string]$Path, [string]$Date = '2026-10-18')

        $raw = Get-Content -LiteralPath $Path -Raw
        $rows = @(
            foreach ($row in (Get-SquadBenchmarkRowsFromMarkdown -Content $raw)) {
                New-FixtureEvidenceRow -Id $row.CatalogId -Evaluation $row.Evaluation -Score $row.NumericScore `
                    -Version $row.SourceVersion -Date $Date -Provenance $row.Provenance -SourceId $row.SourceId -Category $row.Category
            }
        )
        $raw = $raw -replace 'squad-capability-v2', 'squad-capability-v3'
        $raw = [regex]::Replace($raw, '(?ms)^## Benchmark Scores.*', "## Benchmark Scores`n`n$(@(Get-SquadBenchmarkScoreLine -Rows $rows) -join "`n")`n")
        Set-Content -LiteralPath $Path -Value $raw -Encoding utf8NoBOM
    }

    function New-FixtureVerificationFile {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Creates record-bound synthetic checks only in Pester TestDrive.')]
        param([Parameter(Mandatory)][string]$Snapshot, [string]$Date = '2026-10-19')

        $records = @(
            foreach ($row in (Get-SquadBenchmarkRowsFromMarkdown -Content (Get-Content -LiteralPath $Snapshot -Raw))) {
                $check = New-FixtureEvidenceRow -Id $row.CatalogId -Evaluation $row.Evaluation -Score $row.NumericScore `
                    -Version $row.SourceVersion -Date $Date -Provenance $row.Provenance -SourceId $row.SourceId -Category $row.Category
                $check | Add-Member -NotePropertyName recordDigest -NotePropertyValue (Get-SquadBenchmarkRecordDigest -Row $row)
                $check
            }
        )
        $path = Join-Path $TestDrive "$([guid]::NewGuid().ToString('N'))-verification.json"
        @{ schemaVersion = 'squad-benchmark-verification-v1'; records = $records } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        $path
    }

    function New-PolicyBenchmarkFile {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Creates synthetic evidence only inside the caller-owned Pester TestDrive.')]
        param(
            [Parameter(Mandatory)][string]$Path,
            [string]$Date = '2026-10-19',
            [System.Collections.IDictionary]$Scores = ([ordered]@{
                    'gpt-5.4' = '0.600'
                    'gpt-5.6-sol' = '0.700'
                    'gpt-5-mini' = '0.100'
                    'gpt-5.4-nano' = '0.200'
                })
        )
        $lines = @(
            '# Synthetic policy evidence, not real model measurements'
            "* **Retrieved: $Date**"
            "* **Generated: $Date**"
            '* **Scoring Policy: squad-capability-v3**'
            ''
            '## Benchmark Scores', ''
        )
        $rows = @(
            foreach ($id in $Scores.Keys) {
                foreach ($evaluation in 'SciCode', 'Terminal-Bench', 'GPQA diamond', 'GDP.pdf', 'FrontierMath-Tiers-1-3-v2', 'HLE') {
                    New-FixtureEvidenceRow -Id $id -Evaluation $evaluation -Score $Scores[$id] -Date $Date
                }
            }
        )
        $lines += @(Get-SquadBenchmarkScoreLine -Rows $rows)
        Set-Content -LiteralPath $Path -Value ($lines -join "`n") -Encoding utf8NoBOM
        $Path
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
        foreach ($entry in @($script:Ranked.roles | Where-Object { $_.suggested -and -not $_.selectionException })) {
            if ($entry.evidenceStatus -eq 'sufficient') { $entry.rationale | Should -Match '\(evidence: .+@.+ \[' }
            else { $entry.rationale | Should -Match 'declared-fit fallback' }
        }
    }

    It 'reports the assignment-specific objective without promising different winners for different classes' {
        foreach ($entry in $script:Ranked.roles) {
            if ($entry.selectionException) { continue }
            $entry.selectionObjective | Should -Be 'capability-first'
            $entry.class | Should -BeIn @('research', 'planning', 'implementation', 'review', 'council', 'intake', 'bookkeeping')
        }
    }

    It 'treats a fast floor as a minimum and reports the Scribe pin as an exception' {
        $script:CapabilityOf[$script:PickOf['tester']] | Should -BeIn @('fast-lightweight', 'balanced', 'code-specialized', 'frontier-reasoning')
        $scribe = @($script:Ranked.roles | Where-Object role -eq 'scribe')[0]
        $scribe.selectionException | Should -Be 'scribe-pin'
        $scribe.requestedDispatchModel | Should -BeNullOrEmpty
    }

    It 'reports an unavailable Scribe pin rather than suggesting a substitute dispatch will ignore' {
        $available = @($script:CliEnum | Where-Object { $_ -ne 'claude-haiku-5.5' })
        $result = Invoke-Resolver -Root $script:FullRoot -Extra @{ AvailableModels = $available; Mode = 'ranked'; Role = @('scribe') }
        $result.roles[0].suggested | Should -BeNullOrEmpty
        $result.roles[0].expectedModel | Should -Be 'claude-haiku-5.5'
        $result.roles[0].rationale | Should -Match 'pin unavailable.*never suggest a substitute'
    }

    It 'breaks an equal fit and price tie by generation, never by spelling' {
        $root = Initialize-RosterFixture -Content (@(
                '# Squad Roster', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Deliverable Root |'
                '|------|-------------|----------------------|------------|------------------|'
                '| technical-writer | | Fixture | fast | docs/ |'
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
        $result = Invoke-Resolver -Root $script:FullRoot -Extra @{ AvailableModels = $script:CliEnum; AsOf = [datetime]'2027-06-01'; Mode = 'ranked'; Role = @('lead') }
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
        $script:EconomyBenchmarks = New-PolicyBenchmarkFile -Path (Join-Path $TestDrive 'economy-policy.md') -Date '2026-10-15'
        $script:EconomyQualifiedIds = @('gpt-5.4', 'gpt-5.6-sol')

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
                BenchmarksPath = $script:EconomyBenchmarks
            }
            foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
            & $Script @parameters | ConvertFrom-Json
        }

        function Invoke-EconomyResolverRaw {
            param([Parameter(Mandatory)][string]$Root, [hashtable]$Extra = @{}, [string]$Script = $script:Resolver)
            $parameters = @{ SquadRoot = $Root; AsOf = [datetime]'2026-10-01'; AvailableModels = $script:CliEnum }
            foreach ($key in $Extra.Keys) { $parameters[$key] = $Extra[$key] }
            try {
                $output = (& $Script @parameters 2>&1 | Out-String)
                [pscustomobject]@{ ExitCode = 0; Output = $output }
            }
            catch {
                [pscustomobject]@{ ExitCode = 1; Output = ($_ | Out-String) }
            }
        }

        # Expected economy pick computed straight from the catalog, independent of the resolver.
        $catalogRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot 'model-catalog.md') -Raw
        $tables = @(Get-MarkdownTable -Content $catalogRaw)
        $script:CapabilityOf = @{}
        foreach ($row in @($tables | Where-Object { 'Capability class' -in $_.Header } | ForEach-Object { $_.Rows })) { if ($row['Catalog ID']) { $script:CapabilityOf[$row['Catalog ID']] = $row['Capability class'] } }
        $script:EconomyFit = @($tables | Where-Object { 'Blended' -in $_.Header } | Select-Object -First 1 | ForEach-Object { $_.Rows })
        $script:FloorAdmits = @{
            fast    = @('fast-lightweight', 'balanced', 'code-specialized', 'frontier-reasoning')
            default = @('balanced', 'code-specialized', 'frontier-reasoning')
        }
        function Get-ExpectedEconomyPick {
            param([string]$Floor)
            @($script:EconomyFit | Where-Object {
                    $_['Catalog ID'] -in $script:EconomyQualifiedIds -and $_['Catalog ID'] -in $script:CliEnum -and
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

    It 'picks the cheapest independently qualified id within the real floor for an implementation role: <Role>' -ForEach @(
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

    It 'escalates an economy pick once to its capability-first Ranked destination when different' {
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

    It 'keeps Economy fields opt-in and never applies a preview suggestion under Off' {
        $offRun = Invoke-EconomyResolver -Root $script:SeedRoot
        $offRun.recordedMode | Should -Be 'off'
        foreach ($run in @($offRun, $script:RankedRun)) {
            $run.roles[0].PSObject.Properties.Name | Should -Not -Contain 'escalation'
            $run.roles[0].PSObject.Properties.Name | Should -Not -Contain 'pin'
        }
        foreach ($entry in $offRun.roles) { $entry.requestedDispatchModel | Should -BeNullOrEmpty }
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

    It 'classifies additive <Role> via alignedRole=<Alignment> for assignment compatibility only' -ForEach @(
        @{ Role = 'gcp'; Alignment = 'azure-architect'; Class = 'planning' },
        @{ Role = 'dotnet-practices'; Alignment = 'tester'; Class = 'review' },
        @{ Role = 'data-quality'; Alignment = 'tester'; Class = 'review' }
    ) {
        $root = New-EconomyRoot -Content (@(
                '# Squad Roster', '', 'Model routing: ranked', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                "| $Role | Capability Assessor | Squad Connector | default | | .copilot-tracking/$Role/ |"
                ''
                '## Connector Bindings'
                ''
                '| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |'
                '| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |'
                "| capability-assessor | acme | docs/templates/connector-example/manifest.capability-assessor.1.1.json | agent | add | role | role:$Role/Capability Assessor | Capability Assessor | $Role | $Alignment | connector |"
            ) -join "`n")
        $entry = (Invoke-EconomyResolver -Root $root).roles[0]
        $entry.role | Should -Be $Role
        $entry.class | Should -Be $Class
        $entry.classSource | Should -Be "connector-aligned: $Alignment"
        $entry.rationale | Should -Not -Match '^economy pick:' -Because 'alignment grants class compatibility, not economy allowlist treatment'
    }

    It 'preserves legacy connector-backed rows when Connector Bindings are absent' {
        $root = New-EconomyRoot -Content (@(
                '# Squad Roster', '', 'Model routing: ranked', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| gcp | GCP Assessor | Squad Connector | default | | `.copilot-tracking/gcp-assessments/` |'
            ) -join "`n")
        $entry = (Invoke-EconomyResolver -Root $root).roles[0]
        $entry.role | Should -Be 'gcp'
        $entry.classSource | Should -Not -Match 'connector-aligned'
    }

    It 'fails closed on connector alignment errors: <Case>' -ForEach @(
        @{
            Case    = 'missing aligned role'
            TeamMd  = @(
                '# Squad Roster', '', 'Model routing: ranked', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| gcp | GCP Assessor | Squad Connector | default | | out/ |'
                ''
                '## Connector Bindings'
                ''
                '| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |'
                '| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |'
                '| gcp-assessor | acme | docs/templates/connector-example/manifest.1.1.json | orchestrator | add | role | role:gcp/GCP Assessor | GCP Assessor | gcp |  | connector |'
            ) -join "`n"
            Match   = 'missing Aligned Role'
        }
        @{
            Case    = 'invalid aligned role'
            TeamMd  = @(
                '# Squad Roster', '', 'Model routing: ranked', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| gcp | GCP Assessor | Squad Connector | default | | out/ |'
                ''
                '## Connector Bindings'
                ''
                '| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |'
                '| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |'
                '| gcp-assessor | acme | docs/templates/connector-example/manifest.1.1.json | orchestrator | add | role | role:gcp/GCP Assessor | GCP Assessor | gcp | imaginary-role | connector |'
            ) -join "`n"
            Match   = 'has no assignment'
        }
        @{
            Case    = 'cyclic aligned role chain'
            TeamMd  = @(
                '# Squad Roster', '', 'Model routing: ranked', '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '|------|-------------|----------------------|------------|-------|------------------|'
                '| gcp | GCP Assessor | Squad Connector | default | | out/ |'
                ''
                '## Connector Bindings'
                ''
                '| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |'
                '| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |'
                '| gcp-assessor | acme | docs/templates/connector-example/manifest.1.1.json | orchestrator | add | role | role:gcp/GCP Assessor | GCP Assessor | gcp | bridge-role | connector |'
                '| bridge-assessor | acme | docs/templates/connector-example/manifest.1.1.json | orchestrator | add | role | role:bridge-role/GCP Assessor | GCP Assessor | bridge-role | gcp | connector |'
            ) -join "`n"
            Match   = 'cyclic Aligned Role chain'
        }
    ) {
        $root = New-EconomyRoot -Content $TeamMd
        $result = Invoke-EconomyResolverRaw -Root $root -Extra @{ Mode = 'ranked' }
        $NormalizedOutput = ($result.Output -replace '\s*\|\s*', ' ') -replace '\s+', ' '
        $result.ExitCode | Should -Not -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Connector alignment error'
        $NormalizedOutput | Should -Match $Match
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
                'gpt54,terminal,0.100,Terminal Bench,2025-05-19,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt56,terminal,0.990,Terminal Bench,2025-05-19,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
            )
            @('Model version,Score,Source', 'gpt-5.4,0.100,', 'gpt-5.6-sol,0.990,') |
                Set-Content -LiteralPath (Join-Path $archive 'scicode_external.csv') -Encoding utf8NoBOM
            $output = Join-Path $TestDrive 'score-reversal.md'
            $result = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1')[-1]
            $result.ModelsCovered | Should -Be 2
            $result.VerifiedModelsCovered | Should -Be 0 -Because 'a local archive and generation date are not original-source verification'
            $result.Retrieved | Should -Be 'unknown'
            $result.Generated | Should -Be '2026-10-19'
            $checks = New-FixtureVerificationFile -Snapshot $output
            & $script:SyncScript -SnapshotPath $output -VerificationPath $checks -OutputPath $output -AsOf ([datetime]'2026-10-19') | Out-Null

            $tables = @(Get-MarkdownTable -Content (Get-Content -LiteralPath $output -Raw))
            $fit = @($tables | Where-Object { 'Composite' -in $_.Header -and 'implementation' -in $_.Header })[0]
            $byId = @{}
            foreach ($row in $fit.Rows) { $byId[$row['Catalog ID']] = $row }
            [int]$byId['gpt-5.4']['implementation'] | Should -Be 0
            [int]$byId['gpt-5.6-sol']['implementation'] | Should -Be 3

            $route = & $script:Resolver -SquadRoot (New-RoutingRootLocal) -AvailableModels @('gpt-5.4', 'gpt-5.6-sol') -Mode ranked -Role @('developer') -AsOf ([datetime]'2026-10-19') -BenchmarksPath $output | ConvertFrom-Json
            $route.roles[0].suggested | Should -Be 'gpt-5.6-sol'
            $route.roles[0].capability | Should -Be 1
            $route.roles[0].rationale | Should -Match 'SciCode, Terminal-Bench'
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

        It 'separates unknown URI authorities from the trusted source ID <TrustedId>' -ForEach @(
            @{ Source = 'https://epoch-ai/vendor-self-reported'; TrustedSource = 'https://epoch.ai/benchmarks'; TrustedId = 'epoch-ai' }
            @{ Source = 'https://artificial-analysis/vendor-self-reported'; TrustedSource = 'https://artificialanalysis.ai/data-api'; TrustedId = 'artificial-analysis' }
            @{ Source = 'https://cognition-frontiercode/vendor-self-reported'; TrustedSource = 'https://cognition.com/frontiercode'; TrustedId = 'cognition-frontiercode' }
            @{ Source = 'https://terminal-bench/vendor-self-reported'; TrustedSource = 'https://www.tbench.ai/leaderboard'; TrustedId = 'terminal-bench' }
            @{ Source = 'https://surge-gdp-pdf/vendor-self-reported'; TrustedSource = 'https://surgehq.ai/benchmarks/gdp-pdf'; TrustedId = 'surge-gdp-pdf' }
            @{ Source = 'https://deepswe-datacurve.ai/vendor-self-reported'; TrustedSource = 'https://deepswe.datacurve.ai/'; TrustedId = 'deepswe-datacurve-ai' }
            @{ Source = 'https://evals-futuresearch.ai/vendor-self-reported'; TrustedSource = 'https://evals.futuresearch.ai/'; TrustedId = 'evals-futuresearch-ai' }
            @{ Source = 'https://frontierswe-com/vendor-self-reported'; TrustedSource = 'https://www.frontierswe.com/'; TrustedId = 'frontierswe-com' }
            @{ Source = 'https://osworld-v2-xlang.ai/vendor-self-reported'; TrustedSource = 'https://osworld-v2.xlang.ai/'; TrustedId = 'osworld-v2-xlang-ai' }
            @{ Source = 'https://vals-ai/vendor-self-reported'; TrustedSource = 'https://www.vals.ai/benchmarks/proof_bench'; TrustedId = 'vals-ai' }
        ) {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                "gpt54,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,$TrustedSource"
                "gpt56,swe,0.990,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,$Source"
            )
            $output = Join-Path $TestDrive "$TrustedId-authority.md"
            $result = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -ArtificialAnalysisApiKey '' -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1')[-1]
            $result.ModelsCovered | Should -Be 1

            $tables = @(Get-MarkdownTable -Content (Get-Content -LiteralPath $output -Raw))
            $scores = @($tables | Where-Object { 'Evaluation' -in $_.Header -and 'Provenance' -in $_.Header })[0]
            $trusted = @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5.4' })[0]
            $trusted['Source ID'] | Should -Be $TrustedId
            $trusted['Provenance'] | Should -Be 'independent'

            $unknown = @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5.6-sol' })[0]
            $unknown['Source ID'] | Should -Be "unverified-$TrustedId"
            $unknown['Provenance'] | Should -Be 'self-reported'
            $sources = @($tables | Where-Object { 'Source ID' -in $_.Header -and 'License' -in $_.Header })[0]
            $unknownSource = @($sources.Rows | Where-Object { $_['Source ID'] -eq $unknown['Source ID'] })[0]
            $unknownSource['Source name'] | Should -Be ([uri]$Source).Host
            $unknownSource['URL'] | Should -Be "<$Source>"
            $unknownSource['Status'] | Should -Be 'self-reported-only'
            $unknownSource['Redistribution'] | Should -Be 'informational-only'

            $fit = @($tables | Where-Object { 'Composite' -in $_.Header -and 'implementation' -in $_.Header })[0]
            @($fit.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5.6-sol' }).Count | Should -Be 0
        }

        It 'continues recognizing the explicit publisher identity <Publisher>' -ForEach @(
            @{ Publisher = 'Epoch AI'; SourceId = 'epoch-ai' }
            @{ Publisher = 'Artificial Analysis SciCode'; SourceId = 'artificial-analysis' }
            @{ Publisher = 'Terminal-Bench'; SourceId = 'terminal-bench' }
            @{ Publisher = 'Cognition FrontierCode'; SourceId = 'cognition-frontiercode' }
            @{ Publisher = 'Surge AI GDP.pdf'; SourceId = 'surge-gdp-pdf' }
        ) {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                "gpt54,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,$Publisher"
            )
            $output = Join-Path $TestDrive "$SourceId-publisher.md"
            & $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -ArtificialAnalysisApiKey '' -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' | Out-Null
            $tables = @(Get-MarkdownTable -Content (Get-Content -LiteralPath $output -Raw))
            $scores = @($tables | Where-Object { 'Evaluation' -in $_.Header -and 'Provenance' -in $_.Header })[0]
            $row = @($scores.Rows | Where-Object { $_['Catalog ID'] -eq 'gpt-5.4' })[0]
            $row['Source ID'] | Should -Be $SourceId
            $row['Provenance'] | Should -Be 'independent'
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

        It 'treats identical duplicate <DataSet> records as a semantic no-op' -ForEach @(
            @{ DataSet = 'processed'; File = 'processed_data_for_eci.csv'; Header = ''; Rows = @() }
            @{ DataSet = 'eci'; File = 'eci_scores.csv'; Header = 'Model,eci'; Rows = @('GPT-5.4,160', 'GPT-5.6 Sol,150') }
            @{ DataSet = 'scicode'; File = 'scicode_external.csv'; Header = 'Model version,Score,Source'; Rows = @('gpt-5.4,0.700,Artificial Analysis SciCode', 'gpt-5.6-sol,0.600,Artificial Analysis SciCode') }
            @{ DataSet = 'critpt'; File = 'critpt_external.csv'; Header = 'Model version,Accuracy'; Rows = @('gpt-5.4,0.700', 'gpt-5.6-sol,0.600') }
            @{ DataSet = 'gdpPdf'; File = 'gdp_pdf_external.csv'; Header = 'Model version,GDP.pdf score,Source link,Source,Last updated'; Rows = @('gpt-5.4,0.700,https://surgehq.ai/benchmarks/gdp-pdf,Surge AI GDP.pdf,', 'gpt-5.6-sol,0.600,https://surgehq.ai/benchmarks/gdp-pdf,Surge AI GDP.pdf,') }
        ) {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.800,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt56,swe,0.600,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
            )
            $dataRoot = if ($DataSet -in @('processed', 'eci')) { Join-Path $archive 'epoch_capabilities_index' } else { $archive }
            $dataPath = Join-Path $dataRoot $File
            if ($DataSet -ne 'processed') {
                @($Header; $Rows) | Set-Content -LiteralPath $dataPath -Encoding utf8NoBOM
            }

            $output = Join-Path $TestDrive "$DataSet-duplicates.md"
            $first = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -ArtificialAnalysisApiKey '' -AsOf ([datetime]'2026-10-19'))[-1]
            $firstRaw = Get-Content -LiteralPath $output -Raw
            $before = (Get-FileHash -LiteralPath $output).Hash
            $dataLines = @(Get-Content -LiteralPath $dataPath)
            $records = @($dataLines | Select-Object -Skip 1)
            @($dataLines[0]; $records[-1]; $records; $records[0]) |
                Set-Content -LiteralPath $dataPath -Encoding utf8NoBOM

            $duplicate = @(& $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -ArtificialAnalysisApiKey '' -AsOf ([datetime]'2026-10-20'))[-1]
            $duplicate.Updated | Should -BeFalse
            $duplicate.Digest | Should -Be $first.Digest
            $duplicate.ModelsCovered | Should -Be $first.ModelsCovered
            $duplicate.ScoresCount | Should -Be $first.ScoresCount
            (Get-FileHash -LiteralPath $output).Hash | Should -Be $before

            $freshOutput = Join-Path $TestDrive "$DataSet-duplicates-fresh.md"
            & $script:SyncScript -ArchivePath $archive -OutputPath $freshOutput -CatalogPath $script:CatalogPath -ArtificialAnalysisApiKey '' -AsOf ([datetime]'2026-10-19') | Out-Null
            Get-Content -LiteralPath $freshOutput -Raw | Should -BeExactly $firstRaw
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
            { & $script:SyncScript -ArchivePath $conflicting -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') } |
                Should -Throw '*Conflicting benchmark rows*refusing row-order-dependent selection*'
            (Get-FileHash -LiteralPath $output).Hash | Should -Be $before
        }

        It 'does not collapse distinct high-precision source scores into an identical duplicate' {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.700,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
            )
            $output = Join-Path $TestDrive 'precise-source-last-good.md'
            & $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath `
                -AsOf ([datetime]'2026-10-19') -EpochVersion fixture-v1 | Out-Null
            $before = (Get-FileHash -LiteralPath $output).Hash
            $conflicting = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.60000000000000000,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt54,swe,0.60000000000000001,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
            )
            { & $script:SyncScript -ArchivePath $conflicting -OutputPath $output -CatalogPath $script:CatalogPath `
                    -AsOf ([datetime]'2026-10-19') -EpochVersion fixture-v1 } |
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
            $acceptedScores = @(Get-MarkdownTable -Content (Get-Content -LiteralPath $output -Raw) |
                    Where-Object { 'Evaluation' -in $_.Header -and 'Provenance' -in $_.Header } | ForEach-Object Rows)
            @($acceptedScores | Where-Object { $_['Catalog ID'] -eq 'gpt-6.1-sol' }).Count | Should -Be 0
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

        It 'shares primary scoring with runtime without allowing secondary scores to reverse it' {
            $archive = New-SyncArchiveLocal -ProcessedRows @(
                'gpt54,swe,0.900,SWE-Bench verified,2024-08-13,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt54,os,0.100,OSWorld 2.0,2026-06-26,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,https://osworld-v2.xlang.ai/'
                'gpt56,swe,0.600,SWE-Bench verified,2024-08-13,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
                'gpt56,os,0.900,OSWorld 2.0,2026-06-26,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,https://osworld-v2.xlang.ai/'
                'gpt54,terminal,0.700,Terminal Bench,2025-05-19,gpt-5.4,gpt-5.4,GPT-5.4,2026-10-19,'
                'gpt56,terminal,0.600,Terminal Bench,2025-05-19,gpt-5.6-sol,gpt-5.6-sol,GPT-5.6 Sol,2026-10-19,'
            )
            @('Model version,Score,Source', 'gpt-5.4,0.700,', 'gpt-5.6-sol,0.600,') |
                Set-Content -LiteralPath (Join-Path $archive 'scicode_external.csv') -Encoding utf8NoBOM
            $output = Join-Path $TestDrive 'aggregation-consistency.md'
            & $script:SyncScript -ArchivePath $archive -OutputPath $output -CatalogPath $script:CatalogPath -AsOf ([datetime]'2026-10-19') -EpochVersion 'fixture-v1' | Out-Null
            $checks = New-FixtureVerificationFile -Snapshot $output
            & $script:SyncScript -SnapshotPath $output -VerificationPath $checks -OutputPath $output -AsOf ([datetime]'2026-10-19') | Out-Null

            $tables = @(Get-MarkdownTable -Content (Get-Content -LiteralPath $output -Raw))
            $fit = @($tables | Where-Object { 'Composite' -in $_.Header -and 'implementation' -in $_.Header })[0]
            $fitById = @{}
            foreach ($row in $fit.Rows) { $fitById[$row['Catalog ID']] = [int]$row['implementation'] }
            $fitById['gpt-5.4'] | Should -Be 2
            $fitById['gpt-5.6-sol'] | Should -Be 2

            $route = & $script:Resolver -SquadRoot (New-RoutingRootLocal) -AvailableModels @('gpt-5.4', 'gpt-5.6-sol') -Mode ranked -Role @('developer') -AsOf ([datetime]'2026-10-19') -BenchmarksPath $output | ConvertFrom-Json
            foreach ($candidate in $route.roles[0].candidates) {
                if ($fitById.ContainsKey($candidate.id)) {
                    $candidate.fit | Should -Be $fitById[$candidate.id]
                }
            }
            $route.roles[0].suggested | Should -Be 'gpt-5.4'
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
        $mappedClasses = @($mappingTable.Rows | ForEach-Object { $_['Assignment class'] } | Sort-Object -Unique)
        $mappedClasses | Should -Be (@('bookkeeping', 'council', 'implementation', 'intake', 'planning', 'research', 'review') | Sort-Object)
        foreach ($row in $mappingTable.Rows) {
            $row['Primary evaluations'] | Should -Not -BeNullOrEmpty
            $row['Panel'] | Should -Not -BeNullOrEmpty
            $row['Evidence rule'] | Should -Match 'common verified panel'
        }
    }

    It 'preserves provenance and explicit known-or-unknown dates without claiming every stored row is verified' {
        $scoreTable = @($script:BenchmarkTables | Where-Object { 'Catalog ID' -in $_.Header -and 'Evaluation' -in $_.Header -and 'Provenance' -in $_.Header })[0]
        $scoreTable | Should -Not -BeNullOrEmpty
        $scoreTable.Rows.Count | Should -BeGreaterThan 100

        $invalid = @(
            foreach ($row in $scoreTable.Rows) {
                if (-not $row['Catalog ID'] -or -not $row['Evaluation'] -or $row['Score'] -notmatch '^-?\d+(\.\d+)?$' -or -not $row['Source ID'] -or -not $row['Source version'] -or $row['Retrieved'] -notmatch '^(unknown|\d{4}-\d{2}-\d{2})$' -or $row['Provenance'] -notin @('independent', 'self-reported')) {
                    "$($row['Catalog ID'])/$($row['Evaluation']): prov='$($row['Provenance'])'"
                }
                foreach ($field in 'Result date', 'Verified', 'Legacy date') {
                    $row[$field] | Should -Match '^(unknown|\d{4}-\d{2}-\d{2})$'
                }
                if ($row['Verification'] -eq 'verified') {
                    $row['Model version'] | Should -Not -Be 'unknown'
                    $row['Configuration'] | Should -Not -Be 'unknown'
                    $row['Retrieved'] | Should -Not -Be 'unknown'
                    $row['Verified'] | Should -Not -Be 'unknown'
                    $row['Verification basis'] | Should -Match '^sha256:[0-9a-f]{64}'
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
                Error = 'score LegacyDate date.*is after routing date'
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
        $run.warnings.Count | Should -BeLessOrEqual 1
        foreach ($roleEntry in $run.roles) {
            if ($roleEntry.evidenceStatus -eq 'sufficient') { $roleEntry.rationale | Should -Match '\(evidence: .+@.+ \[' }
            else {
                $roleEntry.rationale | Should -Match 'declared-fit fallback'
                $roleEntry.capability | Should -BeNullOrEmpty
            }
        }

        # Override benchmark evidence so claude-opus-4.8 has fit 3 in research while claude-opus-5.5 has fit 2
        # (reversing model-catalog.md's declared fit table) and verify routing=ranked follows the benchmark evidence.
        $customBench = Join-Path $TestDrive 'override-benchmarks.md'
        $customContent = @(
            '# Custom Benchmarks'
            '* **Retrieved: 2026-10-18**'
            '* **Scoring Policy: squad-capability-v2**'
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
            '| `claude-opus-4.8` | GPQA diamond | `scientific-reasoning` | 0.920 | `epoch-ai` | `fixture-v2` | `2026-10-18` | `independent` |'
            '| `claude-opus-5.5` | GPQA diamond | `scientific-reasoning` | 0.600 | `epoch-ai` | `fixture-v2` | `2026-10-18` | `independent` |'
        ) -join "`n"
        Set-Content -LiteralPath $customBench -Value $customContent -Encoding utf8NoBOM
        ConvertTo-VerifiedFixtureSnapshot -Path $customBench

        $overridden = & $script:Resolver -SquadRoot $root -AvailableModels @('claude-opus-4.8', 'claude-opus-5.5') -Mode ranked -Role @('researcher') -AsOf ([datetime]'2026-10-18') -BenchmarksPath $customBench | ConvertFrom-Json
        $overridden.roles[0].suggested | Should -Be 'claude-opus-4.8'
        $overridden.roles[0].rationale | Should -Match 'artificial-analysis@v4\.3\.2.*\[GDP\.pdf, GPQA diamond\]'
    }

    It 'never lets self-reported scores decide or boost a ranked pick alone' {
        $root = New-BenchmarkRosterRoot
        $selfReportBench = Join-Path $TestDrive 'self-reported-benchmarks.md'
        $selfReportContent = @(
            '# Self-Reported Test Benchmarks'
            '* **Retrieved: 2026-10-18**'
            '* **Scoring Policy: squad-capability-v2**'
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
            '| `gpt-5.6-sol` | GPQA diamond | `scientific-reasoning` | 0.891 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |'
            '| `gpt-5-mini` | FrontierMath-Tiers-1-3-v2 | `math` | 0.100 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |'
            '| `gpt-5-mini` | GPQA diamond | `scientific-reasoning` | 0.100 | `epoch-ai` | `2026-10-18` | `2026-10-18` | `independent` |'
        ) -join "`n"
        Set-Content -LiteralPath $selfReportBench -Value $selfReportContent -Encoding utf8NoBOM
        ConvertTo-VerifiedFixtureSnapshot -Path $selfReportBench

        # gpt-5.4 is cheaper (Blended 1.000 vs 1.920) and has a 0.999 self-reported score,
        # but only gpt-5.6-sol has independent benchmark evidence, so gpt-5.6-sol wins.
        $res = & $script:Resolver -SquadRoot $root -AvailableModels @('gpt-5.4', 'gpt-5.6-sol') -Mode ranked -Role @('lead') -AsOf ([datetime]'2026-10-18') -BenchmarksPath $selfReportBench | ConvertFrom-Json
        $res.roles[0].suggested | Should -Be 'gpt-5.6-sol'
        $res.roles[0].rationale | Should -Match 'epoch-ai@2026-10-18@.* \[FrontierMath-Tiers-1-3-v2, GPQA diamond\]'

        # When only a self-reported model (mai-code-1.1-flash) is available, it falls back to declared fit and logs a warning.
        $currentSnapshotDate = [regex]::Match($script:BenchmarksRaw, '\*\*Retrieved:\s*(?<date>\d{4}-\d{2}-\d{2})\*\*').Groups['date'].Value
        $onlySelfReported = & $script:Resolver -SquadRoot $root -AvailableModels @('mai-code-1.1-flash') -Mode ranked -Role @('technical-writer') -AsOf ([datetime]$currentSnapshotDate) | ConvertFrom-Json
        $onlySelfReported.roles[0].suggested | Should -Be 'mai-code-1.1-flash'
        $onlySelfReported.roles[0].rationale | Should -Match '\(declared-fit fallback\)'
        $onlySelfReported.warnings.Count | Should -Be 1
        $onlySelfReported.warnings[0] | Should -Match 'No supported implementation benchmark comparison for mai-code-1\.1-flash.*missing-evaluation'
    }

    It 'falls back when the snapshot is missing but never expires verified rows from the envelope retrieval stamp alone' {
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
        $current = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Mode ranked -Role @('developer') -AsOf ([datetime]$currentSnapshotDate) | ConvertFrom-Json
        $staleRun = & $script:Resolver -SquadRoot $root -AvailableModels $script:CliEnum -Mode ranked -Role @('developer') -AsOf ([datetime]$currentSnapshotDate) -BenchmarksPath $staleBench | ConvertFrom-Json
        $staleRun.warnings | Should -BeNullOrEmpty
        $staleRun.roles[0].suggested | Should -Be $current.roles[0].suggested
        $staleRun.roles[0].evidenceStatus | Should -Be 'sufficient'
        $staleRun.roles[0].coverage.primary[0].verified | Should -Be $current.roles[0].coverage.primary[0].verified
    }

    It 'explains unverified legacy rows and missing required evaluations rather than promoting unrelated scores' {
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
                    '* **Scoring Policy: squad-capability-v2**'
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
            $run.warnings[0] | Should -Match 'No supported planning benchmark comparison.*(unverified|missing-evaluation)'
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

    It 'contains no network cmdlets in the resolver or shared scorer so dispatch stays offline' {
        $resolverRaw = Get-Content -LiteralPath $script:Resolver -Raw
        $scoringRaw = Get-Content -LiteralPath (Join-Path $script:ReferencesRoot '../scripts/ModelBenchmarkScoring.ps1') -Raw
        $bannedPattern = 'Invoke-WebRequest|Invoke-RestMethod|System\.Net\.(WebClient|Http)|New-WebServiceProxy|Start-BitsTransfer|curl(\.exe)?\s|wget\s|gh\s+api'
        $resolverRaw | Should -Not -Match $bannedPattern
        $scoringRaw | Should -Not -Match $bannedPattern
    }
}

Describe 'Capability-first Ranked and qualified cost-first Economy (SQ-33b..d, SQ-35a)' {
    BeforeAll {
        $script:Resolver = Join-Path $script:ReferencesRoot '../scripts/Resolve-SquadModelRoute.ps1'
        $script:SyncScript = Join-Path $script:ReferencesRoot '../../../../../scripts/Sync-ModelBenchmarks.ps1'
        . (Join-Path $script:ReferencesRoot '../scripts/ModelBenchmarkScoring.ps1')

        function New-PolicyRoster {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Creates a unique Pester TestDrive fixture, never consumer state.')]
            param(
                [string]$Role = 'developer', [string]$Tier = 'default',
                [string]$Cell = '', [string]$Mode = 'ranked',
                [string]$Agent = 'Fixture Agent',
                [System.Collections.IDictionary]$Scores,
                [string[]]$Available = @('gpt-5.4', 'gpt-5.6-sol')
            )
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root | Out-Null
            @(
                '# Squad Roster', '', "Model routing: $Mode", '', '## Members', ''
                '| Role | Member Name | Agent Name (Primary) | Model Tier | Model | Deliverable Root |'
                '| --- | --- | --- | --- | --- | --- |'
                "| $Role | | $Agent | $Tier | $Cell | out/ |"
            ) | Set-Content -LiteralPath (Join-Path $root 'team.md') -Encoding utf8NoBOM
            "# Decisions`n`n## Economy Mode Accepted 2026-10-19T10:00:00Z`n" |
                Set-Content -LiteralPath (Join-Path $root 'decisions.md') -Encoding utf8NoBOM
            $path = Join-Path $root 'benchmarks.md'
            if ($Scores) { New-PolicyBenchmarkFile -Path $path -Scores $Scores | Out-Null }
            else { New-PolicyBenchmarkFile -Path $path | Out-Null }
            [pscustomobject]@{ Root = $root; Benchmarks = $path; Available = $Available; Resolver = $script:Resolver }
        }

        function Set-PolicyRow {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Mutates only the synthetic benchmark file in a Pester TestDrive fixture.')]
            param(
                $Fixture, [string]$Id, [string]$Evaluation,
                [string]$Score = '0.600', [string]$Version = 'fixture-v3',
                [string]$Date = '2026-10-19', [string]$Provenance = 'independent',
                [string]$ResultDate = 'unknown', [string]$RetrievedDate, [string]$VerifiedDate,
                [string]$ModelVersion, [string]$Configuration = 'synthetic-evaluation-protocol-v1',
                [string]$Verification = 'verified',
                [switch]$Drop
            )
            $raw = Get-Content -LiteralPath $Fixture.Benchmarks -Raw
            $prefix = [regex]::Escape("| ``$Id`` | $Evaluation |")
            $raw = [regex]::Replace($raw, "(?m)^$prefix.*(?:\r?\n|$)", '')
            if (-not $Drop) {
                $row = New-FixtureEvidenceRow -Id $Id -Evaluation $Evaluation -Score $Score -Version $Version `
                    -Date $Date -ResultDate $ResultDate -Provenance $Provenance -ModelVersion $ModelVersion `
                    -Configuration $Configuration -Verification $Verification
                if ($RetrievedDate) { $row.Retrieved = $RetrievedDate }
                if ($VerifiedDate) { $row.Verified = $VerifiedDate }
                $raw = $raw.TrimEnd("`r", "`n") + "`n" + @(Get-SquadBenchmarkScoreLine -Rows @($row))[2]
            }
            Set-Content -LiteralPath $Fixture.Benchmarks -Value $raw -Encoding utf8NoBOM
        }

        function Invoke-PolicyRoute {
            param($Fixture, [string]$Mode = 'ranked', [datetime]$AsOf = [datetime]'2026-10-19', [string[]]$Available)
            $parameters = @{
                SquadRoot = $Fixture.Root
                AvailableModels = if ($Available) { $Available } else { $Fixture.Available }
                BenchmarksPath = $Fixture.Benchmarks
                AsOf = $AsOf
                SessionModel = 'gpt-6.1-sol'
            }
            if ($Mode -ne 'off') { $parameters.Mode = $Mode }
            & $Fixture.Resolver @parameters | ConvertFrom-Json
        }

        function Copy-PolicySkill {
            param($Fixture)
            $destination = Join-Path $Fixture.Root 'plugin/skills/squad'
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            Copy-Item -LiteralPath $script:ReferencesRoot, (Join-Path $script:ReferencesRoot '../scripts') -Destination $destination -Recurse
            $Fixture.Resolver = Join-Path $destination 'scripts/Resolve-SquadModelRoute.ps1'
            Join-Path $destination 'references/model-catalog.md'
        }
    }

    It 'selects the stronger expensive model even when both native primary means have legacy fit 2' {
        $fixture = New-PolicyRoster
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $role.candidates[0].fit | Should -Be 2
        $role.candidates[1].fit | Should -Be 2
        $role.suggested | Should -Be 'gpt-5.6-sol'
        $role.capability | Should -BeGreaterThan $role.candidates[1].capability
        $role.estimatedCost | Should -BeGreaterThan $role.candidates[1].blended
        $role.rationale | Should -Match 'cost does not override capability'
    }

    It 'selects the cheaper adequate model even when the expensive one is substantially stronger' {
        $fixture = New-PolicyRoster
        $ranked = (Invoke-PolicyRoute $fixture).roles[0]
        $economy = (Invoke-PolicyRoute $fixture -Mode economy).roles[0]
        $economy.suggested | Should -Be 'gpt-5.4'
        $economy.selectionObjective | Should -Be 'cost-first'
        $economy.capability | Should -BeLessThan $ranked.capability
        $economy.estimatedCost | Should -BeLessThan $ranked.estimatedCost
        @($economy.candidates | Where-Object economyQualified).Count | Should -Be 2
        $economy.escalation | Should -Be $ranked.suggested
        $economy.escalationReason | Should -Match 'persist Model cell.*Cost Preflight'
    }

    It 'excludes a cheap model that fails even one primary minimum' {
        $fixture = New-PolicyRoster
        Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation Terminal-Bench -Score 0.010
        $role = (Invoke-PolicyRoute $fixture -Mode economy).roles[0]
        $role.suggested | Should -Be 'gpt-5.6-sol'
        @($role.candidates | Where-Object id -eq 'gpt-5.4')[0].economyQualified | Should -BeFalse
    }

    It 'uses known cost when primary capability and confidence genuinely tie' {
        $fixture = New-PolicyRoster
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation $evaluation -Score 0.700
        }
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $role.candidates[0].capability | Should -Be $role.candidates[1].capability
        $role.suggested | Should -Be 'gpt-5.4'
        $role.rationale | Should -Match 'capability tied'
    }

    It 'uses confidence only after tied capability, never before Economy price' {
        $fixture = New-PolicyRoster
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation $evaluation -Score 0.700
        }
        Set-PolicyRow $fixture -Id gpt-5.6-sol -Evaluation 'SWE-Bench verified' -Score 0.900
        Set-PolicyRow $fixture -Id gpt-5-mini -Evaluation 'SWE-Bench verified' -Score 0.100
        (Invoke-PolicyRoute $fixture).roles[0].suggested | Should -Be 'gpt-5.6-sol'
        (Invoke-PolicyRoute $fixture -Mode economy).roles[0].suggested | Should -Be 'gpt-5.4'
    }

    It 'uses higher capability when Economy prices tie' {
        $fixture = New-PolicyRoster -Scores ([ordered]@{
                'gpt-6.1-sol' = '0.700'; 'claude-sonnet-5.5' = '0.600'
                'gpt-5-mini' = '0.100'; 'gpt-5.4-nano' = '0.200'
            }) -Available @('gpt-6.1-sol', 'claude-sonnet-5.5')
        $role = (Invoke-PolicyRoute $fixture -Mode economy).roles[0]
        $role.candidates[0].blended | Should -Be $role.candidates[1].blended
        $role.suggested | Should -Be 'gpt-6.1-sol'
    }

    It 'uses one common reduced basis rather than mixing complete and incomplete full-panel scores' {
        $fixture = New-PolicyRoster
        Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation Terminal-Bench -Drop
        Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation SciCode -Score 0.999
        Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation 'SWE-Bench verified' -Score 0.999
        Set-PolicyRow $fixture -Id gpt-5-mini -Evaluation 'SWE-Bench verified' -Score 0.100
        foreach ($mode in 'ranked', 'economy') {
            $role = (Invoke-PolicyRoute $fixture -Mode $mode).roles[0]
            $role.suggested | Should -Be 'gpt-5.4'
            $role.evidenceLevel | Should -Be 'reduced'
            $role.comparisonPanel.id | Should -Be 'implementation-scicode'
            @($role.candidates.panel | Sort-Object -Unique) | Should -Be @('implementation-scicode v1')
            $role.coverage.fullProfileRequired | Should -Be 2
            $role.coverage.gaps -join '; ' | Should -Match 'Terminal-Bench: missing-evaluation'
            $role.rationale | Should -Match 'reduced evidence.*not equivalent'
        }
    }

    It 'uses an explicit conservative fallback when no primary panel can be supported' {
        $fixture = New-PolicyRoster
        foreach ($id in 'gpt-5.4', 'gpt-5.6-sol', 'gpt-5-mini', 'gpt-5.4-nano') {
            Set-PolicyRow $fixture -Id $id -Evaluation Terminal-Bench -Drop
            Set-PolicyRow $fixture -Id $id -Evaluation SciCode -Drop
        }
        $ranked = Invoke-PolicyRoute $fixture
        $economy = Invoke-PolicyRoute $fixture -Mode economy
        $ranked.roles[0].capability | Should -BeNullOrEmpty
        $ranked.roles[0].comparisonOutcome | Should -Be 'declared-fit fallback'
        $ranked.warnings.Count | Should -Be 1
        $economy.roles[0].suggested | Should -Be $ranked.roles[0].suggested
        $economy.roles[0].rationale | Should -Match 'explicit Ranked fallback'
    }

    It 'never pools incomparable source versions into a numerical ranking' {
        $fixture = New-PolicyRoster
        Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation Terminal-Bench -Version incompatible-harness
        Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation SciCode -Version incompatible-harness
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $role.evidenceStatus | Should -Be 'incomparable'
        $role.capability | Should -BeNullOrEmpty
        $role.rationale | Should -Match 'not proof of superiority'
    }

    It 'keeps intrinsic capability unchanged when host availability changes' {
        $fixture = New-PolicyRoster
        $all = Invoke-PolicyRoute $fixture
        $before = @($all.roles[0].candidates | Where-Object id -eq 'gpt-5.4')[0]
        $narrow = (Invoke-PolicyRoute $fixture -Available @('gpt-5.4')).roles[0]
        $narrow.suggested | Should -Be 'gpt-5.4'
        $narrow.capability | Should -Be $before.capability
        $narrow.coverage.primary[0].referenceCount | Should -Be 4
    }

    It 'allows a fast-floor reviewer to select a frontier candidate on stronger evidence' {
        $fixture = New-PolicyRoster -Role tester -Tier fast
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $role.suggested | Should -Be 'gpt-5.6-sol'
        $role.candidates[0].capabilityClass | Should -Be 'frontier-reasoning'
    }

    It 'never lowers the <Tier> floor under <Mode>' -ForEach @(
        @{ Tier = 'default'; Mode = 'ranked'; Available = 'gpt-5-mini' }
        @{ Tier = 'default'; Mode = 'economy'; Available = 'gpt-5-mini' }
        @{ Tier = 'extended'; Mode = 'ranked'; Available = 'gpt-5.4' }
        @{ Tier = 'extended'; Mode = 'economy'; Available = 'gpt-5.4' }
    ) {
        $fixture = New-PolicyRoster -Tier $Tier
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5-mini -Evaluation $evaluation -Score 0.990
        }
        $role = (Invoke-PolicyRoute $fixture -Mode $Mode -Available @($Available)).roles[0]
        $role.suggested | Should -BeNullOrEmpty
        $role.rationale | Should -Match 'floor exhausted'
    }

    It 'keeps a non-allowlisted deployment role on its Ranked selection' {
        $fixture = New-PolicyRoster -Role deployer
        $ranked = (Invoke-PolicyRoute $fixture).roles[0]
        $economy = (Invoke-PolicyRoute $fixture -Mode economy).roles[0]
        $economy.suggested | Should -Be $ranked.suggested
        $economy.selectionObjective | Should -Be 'capability-first'
        $economy.escalation | Should -BeNullOrEmpty
    }

    It 'does not treat a missing Blended price as zero or admit it to Economy' {
        $fixture = New-PolicyRoster
        $catalog = Copy-PolicySkill $fixture
        $raw = Get-Content -LiteralPath $catalog -Raw
        $raw | Should -Match '(?m)^\| `gpt-5\.4` \|.*\| 1\.000 \|\r?$'
        $raw = $raw -replace '(?m)^(\| `gpt-5\.4` \|.*\|) 1\.000 \|\r?$', '$1 unpriced |'
        Set-Content -LiteralPath $catalog -Value $raw -Encoding utf8NoBOM
        $role = (Invoke-PolicyRoute $fixture -Mode economy).roles[0]
        $role.suggested | Should -Be 'gpt-5.6-sol'
        $unpriced = @($role.candidates | Where-Object id -eq 'gpt-5.4')[0]
        $unpriced.blended | Should -BeNullOrEmpty
        $unpriced.economyQualified | Should -BeFalse
    }

    It 'reports that no higher-ranked escalation exists when both objectives select the same model' {
        $fixture = New-PolicyRoster -Available @('gpt-5.4')
        $role = (Invoke-PolicyRoute $fixture -Mode economy).roles[0]
        $role.escalation | Should -BeNullOrEmpty
        $role.escalationReason | Should -Be 'no higher-ranked escalation target exists'
    }

    It 'preserves a valid Manual cell while suggesting the capability-first alternative' {
        $fixture = New-PolicyRoster -Mode manual -Cell gpt-5.4
        $role = (Invoke-PolicyRoute $fixture -Mode manual).roles[0]
        $role.resolved | Should -Be 'gpt-5.4'
        $role.suggested | Should -Be 'gpt-5.6-sol'
        $role.requestedDispatchModel | Should -Be 'gpt-5.4'
        $role.selectionObjective | Should -Be 'explicit-manual-selection'
    }

    It 'applies no model policy under Off and does not mutate the roster' {
        $fixture = New-PolicyRoster -Mode off
        $before = (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'team.md')).Hash
        $role = (Invoke-PolicyRoute $fixture -Mode off).roles[0]
        $role.resolved | Should -BeNullOrEmpty
        $role.requestedDispatchModel | Should -BeNullOrEmpty
        $role.selectionObjective | Should -Be 'no-policy'
        (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'team.md')).Hash | Should -Be $before
    }

    It 'reports the Scribe pin rather than an unused automatic or manual suggestion under <Mode>' -ForEach @(
        @{ Mode = 'ranked' }, @{ Mode = 'economy' }, @{ Mode = 'manual' }
    ) {
        $fixture = New-PolicyRoster -Role scribe -Tier fast -Cell gpt-5.6-sol -Agent 'Squad Scribe' -Mode $Mode -Available @('gpt-5.4', 'gpt-5.6-sol', 'claude-haiku-5.5')
        $role = (Invoke-PolicyRoute $fixture -Mode $Mode).roles[0]
        $role.suggested | Should -Be 'claude-haiku-5.5'
        $role.expectedModel | Should -Be 'claude-haiku-5.5'
        $role.requestedDispatchModel | Should -BeNullOrEmpty
        $role.selectionObjective | Should -Be 'pin-exception'
        $role.effectiveModel | Should -Be 'unreported'
    }

    It 'keeps the selected session model for a coordinator' {
        $fixture = New-PolicyRoster -Role coordinator
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $role.expectedModel | Should -Be 'gpt-6.1-sol'
        $role.requestedDispatchModel | Should -BeNullOrEmpty
        $role.selectionException | Should -Be 'session-model'
    }

    It 'returns the same pick and explanation after reordering rows and advertised IDs' {
        $fixture = New-PolicyRoster
        $before = (Invoke-PolicyRoute $fixture).roles[0]
        $raw = Get-Content -LiteralPath $fixture.Benchmarks -Raw
        $lines = @($raw -split '\r?\n' | Where-Object { $_ -match '^\| `' })
        [array]::Reverse($lines)
        $raw = [regex]::Replace($raw, '(?m)^\| `.*(?:\r?\n|$)', '')
        Set-Content -LiteralPath $fixture.Benchmarks -Value ($raw.TrimEnd() + "`n" + ($lines -join "`n")) -Encoding utf8NoBOM
        $after = (Invoke-PolicyRoute $fixture -Available @('gpt-5.6-sol', 'gpt-5.4')).roles[0]
        $after.suggested | Should -Be $before.suggested
        $after.rationale | Should -BeExactly $before.rationale
    }

    It 'uses identical shared scoring for generated views and runtime on the same date, preserving raw evidence' {
        $fixture = New-PolicyRoster
        $output = Join-Path $fixture.Root 'regenerated.md'
        $original = Get-Content -LiteralPath $fixture.Benchmarks -Raw
        $generated = & $script:SyncScript -SnapshotPath $fixture.Benchmarks -OutputPath $output -AsOf ([datetime]'2026-10-19')
        $generated.ScoringPolicy | Should -Be 'squad-capability-v3'
        $view = Get-Content -LiteralPath $output -Raw
        @(Get-SquadBenchmarkRowsFromMarkdown -Content $view) | ConvertTo-Json -Depth 8 |
            Should -BeExactly (@(Get-SquadBenchmarkRowsFromMarkdown -Content $original) | ConvertTo-Json -Depth 8)
        $fixture.Benchmarks = $output
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $tables = @(Get-MarkdownTable -Content $view)
        $capability = @($tables | Where-Object { 'Capability' -in $_.Header -and 'Evidence status' -in $_.Header })[0]
        $generatedRow = @($capability.Rows | Where-Object { $_['Catalog ID'] -eq $role.suggested -and $_['Assignment class'] -eq 'implementation' })[0]
        $generatedRow['Capability'] | Should -Be ([decimal]$role.capability).ToString('0.000000')
        $again = & $script:SyncScript -SnapshotPath $output -OutputPath $output -AsOf ([datetime]'2026-10-19') -DryRun
        $again.Updated | Should -BeFalse
        $again.Digest | Should -Be $generated.Digest
    }

    It 're-evaluates the 90-day verification boundary without treating generation as freshness' {
        $fixture = New-PolicyRoster
        foreach ($id in 'gpt-5.4', 'gpt-5.6-sol', 'gpt-5-mini', 'gpt-5.4-nano') {
            foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
                Set-PolicyRow $fixture -Id $id -Evaluation $evaluation -Date '2026-07-21'
            }
        }
        (Invoke-PolicyRoute $fixture).roles[0].evidenceStatus | Should -Be 'sufficient'
        $later = Invoke-PolicyRoute $fixture -AsOf ([datetime]'2026-10-20')
        $later.roles[0].evidenceStatus | Should -Be 'verification-expired'
        $later.roles[0].capability | Should -BeNullOrEmpty
        $later.roles[0].rationale | Should -Match 'declared-fit fallback'
        $later.warnings.Count | Should -Be 1
    }

    It 'never counts aggregate indices in primary capability or secondary confidence' {
        $fixture = New-PolicyRoster
        $before = (Invoke-PolicyRoute $fixture).roles[0]
        foreach ($evaluation in 'Artificial Analysis Coding Index', 'Epoch Capabilities Index') {
            Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation $evaluation -Score 0.999
            Set-PolicyRow $fixture -Id gpt-5.6-sol -Evaluation $evaluation -Score 0.100
        }
        $after = (Invoke-PolicyRoute $fixture).roles[0]
        $after.suggested | Should -Be $before.suggested
        $after.capability | Should -Be $before.capability
        $after.coverage.secondary.Count | Should -Be $before.coverage.secondary.Count
    }

    It 'does not round away native differences before comparison' {
        $less = New-FixtureEvidenceRow -Id gpt-5.4 -Evaluation SciCode -Score '0.60000000000000000'
        $more = New-FixtureEvidenceRow -Id gpt-5.4 -Evaluation SciCode -Score '0.60000000000000001'
        (Get-SquadBenchmarkRecordDigest -Row $less) | Should -Not -Be (Get-SquadBenchmarkRecordDigest -Row $more)
        { Get-SquadBenchmarkScore -Rows @($less, $more) -AsOf ([datetime]'2026-10-19') } |
            Should -Throw '*Conflicting duplicate benchmark score rows*'
        $fixture = New-PolicyRoster
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation $evaluation -Score '0.60000000000000000'
            Set-PolicyRow $fixture -Id gpt-5.6-sol -Evaluation $evaluation -Score '0.60000000000000001'
        }
        (Invoke-PolicyRoute $fixture).roles[0].suggested | Should -Be 'gpt-5.6-sol'
    }

    It 'discloses an unsupported policy without changing Manual selections or Off behavior' {
        $fixture = New-PolicyRoster -Mode manual -Cell gpt-5.4
        $raw = (Get-Content -LiteralPath $fixture.Benchmarks -Raw) -replace 'squad-capability-v3', 'unsupported-v999'
        Set-Content -LiteralPath $fixture.Benchmarks -Value $raw -Encoding utf8NoBOM
        $ranked = Invoke-PolicyRoute $fixture
        $ranked.warnings.Count | Should -Be 1
        $ranked.warnings[0] | Should -Match 'unsupported scoring policy'
        $ranked.roles[0].capability | Should -BeNullOrEmpty
        $ranked.roles[0].comparisonOutcome | Should -Be 'declared-fit fallback'
        $manual = Invoke-PolicyRoute $fixture -Mode manual
        $manual.warnings | Should -BeNullOrEmpty
        $manual.roles[0].resolved | Should -Be 'gpt-5.4'
        $offFixture = New-PolicyRoster -Mode off
        Copy-Item -LiteralPath $fixture.Benchmarks -Destination $offFixture.Benchmarks -Force
        $off = Invoke-PolicyRoute $offFixture -Mode off
        $off.warnings | Should -BeNullOrEmpty
        $off.roles[0].requestedDispatchModel | Should -BeNullOrEmpty
    }

    It 'treats equivalent decimal spellings as one measurement without changing calibration or explanations' {
        $fixture = New-PolicyRoster
        $before = (Invoke-PolicyRoute $fixture).roles[0]
        $raw = Get-Content -LiteralPath $fixture.Benchmarks -Raw
        $duplicate = [regex]::Match($raw, '(?m)^\| `gpt-5\.4` \| SciCode \|.*$').Value -replace '\| 0\.600 \|', '| 0.6000 |'
        $duplicate | Should -Not -BeNullOrEmpty
        $raw += "`n$duplicate"
        Set-Content -LiteralPath $fixture.Benchmarks -Value $raw -Encoding utf8NoBOM
        $after = (Invoke-PolicyRoute $fixture).roles[0]
        $after.suggested | Should -Be $before.suggested
        $after.rationale | Should -BeExactly $before.rationale
        $after.coverage.primary[0].referenceCount | Should -Be $before.coverage.primary[0].referenceCount
    }

    It 'keeps an older published exact-model result usable after genuine recent verification (SQ-33e)' {
        $fixture = New-PolicyRoster
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5.6-sol -Evaluation $evaluation -Score 0.700 -ResultDate '2026-02-05'
        }
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $role.suggested | Should -Be 'gpt-5.6-sol'
        $role.evidenceStatus | Should -Be 'sufficient'
        @($role.coverage.primary.status | Sort-Object -Unique) | Should -Be @('older-valid-result')
        $role.coverage.primary[0].resultDate | Should -Be '2026-02-05'
        $role.coverage.primary[0].verified | Should -Be '2026-10-19'
        $role.rationale | Should -Match 'older-valid-result'
    }

    It 'does not turn copied legacy rows into verified evidence by generating a new snapshot (SQ-33e,g)' {
        $fixture = New-PolicyRoster
        $rows = @(Get-SquadBenchmarkRowsFromMarkdown -Content (Get-Content -LiteralPath $fixture.Benchmarks -Raw))
        $legacy = @(
            '# Synthetic legacy evidence'
            '* **Retrieved: 2026-01-01**'
            '* **Scoring Policy: squad-capability-v2**'
            '', '## Benchmark Scores', ''
            '| Catalog ID | Evaluation | Category | Score | Source ID | Source version | Retrieved | Provenance |'
            '| --- | --- | --- | ---: | --- | --- | --- | --- |'
            foreach ($row in $rows) {
                "| ``$($row.CatalogId)`` | $($row.Evaluation) | fixture | $($row.NumericScore) | epoch-ai | fixture-v3 | 2026-01-01 | independent |"
            }
        ) -join "`n"
        Set-Content -LiteralPath $fixture.Benchmarks -Value $legacy -Encoding utf8NoBOM
        $legacyRoute = Invoke-PolicyRoute $fixture
        $legacyRoute.legacyEvidence | Should -BeTrue
        $legacyRoute.roles[0].rationale | Should -Match 'legacy v2 metadata is unverified'
        $output = Join-Path $fixture.Root 'copied-today.md'
        $generated = & $script:SyncScript -SnapshotPath $fixture.Benchmarks -OutputPath $output -AsOf ([datetime]'2026-10-19')
        $generated.VerifiedModelsCovered | Should -Be 0
        $fixture.Benchmarks = $output
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $role.comparisonOutcome | Should -Be 'declared-fit fallback'
        $role.capability | Should -BeNullOrEmpty
        $role.coverage.evaluations[0].verified | Should -Be 'unknown'
        $role.coverage.evaluations[0].retrieved | Should -Be 'unknown'
        $role.coverage.evaluations[0].legacyDate | Should -Be '2026-01-01'
    }

    It 'refuses attribution to another exact model version despite fresh acquisition and verification (SQ-33g)' {
        $fixture = New-PolicyRoster
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation $evaluation -Score 0.999 -ModelVersion 'gpt-5.5'
        }
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $rejected = @($role.evidenceCandidates | Where-Object id -eq 'gpt-5.4')[0]
        $rejected.evidenceStatus | Should -Be 'incomparable'
        $rejected.capability | Should -BeNullOrEmpty
        $rejected.gaps -join '; ' | Should -Match 'identity mismatch'
        $role.suggested | Should -Be 'gpt-5.6-sol'
        $rejected.availability | Should -Be 'host-advertised'
    }

    It 'does not let recent retrieval legitimize an unknown evaluation configuration' {
        $fixture = New-PolicyRoster
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation $evaluation -Score 0.999 -Configuration unknown
        }
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $bad = @($role.evidenceCandidates | Where-Object id -eq 'gpt-5.4')[0]
        $bad.evidenceStatus | Should -Be 'unverified'
        $bad.capability | Should -BeNullOrEmpty
        $bad.gaps -join '; ' | Should -Match 'known configuration'
    }

    It 'keeps a source-marked <State> result out of capability and Economy' -ForEach @(
        @{ State = 'invalidated' }, @{ State = 'superseded' }
    ) {
        $fixture = New-PolicyRoster
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation $evaluation -Score 0.999 -Verification $State
        }
        $role = (Invoke-PolicyRoute $fixture -Mode economy).roles[0]
        $bad = @($role.evidenceCandidates | Where-Object id -eq 'gpt-5.4')[0]
        @($bad.evaluations.status | Sort-Object -Unique) | Should -Be @($State)
        $bad.capability | Should -BeNullOrEmpty
        $bad.economyQualified | Should -BeFalse
    }

    It 'selects full on equal coverage and exposes why broader coverage selects reduced (SQ-33f)' {
        $fixture = New-PolicyRoster
        $full = (Invoke-PolicyRoute $fixture).roles[0]
        $full.comparisonPanel.id | Should -Be 'implementation-full'
        $full.comparisonPanel.weight | Should -Be 0.5
        Set-PolicyRow $fixture -Id gpt-5-mini -Evaluation Terminal-Bench -Drop
        $reduced = (Invoke-PolicyRoute $fixture).roles[0]
        $reduced.comparisonPanel.id | Should -Be 'implementation-scicode'
        $reduced.comparisonPanel.weight | Should -Be 1
        @($reduced.comparisonPanel.options | Where-Object id -eq 'implementation-full')[0].populationCount | Should -Be 3
        $reduced.comparisonPanel.populationCount | Should -Be 4
        $narrow = (Invoke-PolicyRoute $fixture -Available @('gpt-5.4')).roles[0]
        $narrow.comparisonPanel | ConvertTo-Json -Depth 6 |
            Should -BeExactly ($reduced.comparisonPanel | ConvertTo-Json -Depth 6)
        $narrow.capability | Should -Be @($reduced.candidates | Where-Object id -eq 'gpt-5.4')[0].capability
    }

    It 'versions the reduced minimum rather than silently reusing both midpoint requirements (SQ-35b)' {
        $fixture = New-PolicyRoster
        foreach ($id in 'gpt-5.4', 'gpt-5.6-sol', 'gpt-5-mini', 'gpt-5.4-nano') {
            Set-PolicyRow $fixture -Id $id -Evaluation Terminal-Bench -Drop
        }
        $role = (Invoke-PolicyRoute $fixture -Mode economy).roles[0]
        $role.qualificationRule | Should -Be 'implementation-scicode-upper-quartile-v1'
        $role.comparisonPanel.minimumPercentile | Should -Be 0.75
        $cheap = @($role.candidates | Where-Object id -eq 'gpt-5.4')[0]
        $cheap.capability | Should -BeGreaterThan 0.50
        $cheap.capability | Should -BeLessThan 0.75
        $cheap.economyQualified | Should -BeFalse
        $role.suggested | Should -Be 'gpt-5.6-sol'
    }

    It 'keeps Ranked capability-first and Economy price-first on a qualified common reduced panel (SQ-35b)' {
        $scores = [ordered]@{
            'gpt-5.4' = '0.600'; 'gpt-5.6-sol' = '0.990'
            'gpt-5-mini' = '0.100'; 'gpt-5.4-nano' = '0.200'; 'gpt-5.4-mini' = '0.300'
        }
        $fixture = New-PolicyRoster -Scores $scores
        foreach ($id in $scores.Keys) { Set-PolicyRow $fixture -Id $id -Evaluation Terminal-Bench -Drop }
        $ranked = (Invoke-PolicyRoute $fixture).roles[0]
        $economy = (Invoke-PolicyRoute $fixture -Mode economy).roles[0]
        $ranked.suggested | Should -Be 'gpt-5.6-sol'
        $economy.suggested | Should -Be 'gpt-5.4'
        $economy.capability | Should -Be 0.75
        $ranked.comparisonPanel.id | Should -Be $economy.comparisonPanel.id
        $economy.escalation | Should -Be $ranked.suggested
    }

    It 'requires at least two same-panel models, not unrelated single-model primary populations' {
        $fixture = New-PolicyRoster -Scores ([ordered]@{ 'gpt-5.4' = '0.600'; 'gpt-5.6-sol' = '0.700' })
        Set-PolicyRow $fixture -Id gpt-5.6-sol -Evaluation SciCode -Drop
        Set-PolicyRow $fixture -Id gpt-5.6-sol -Evaluation Terminal-Bench -Drop
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $role.comparisonPanel.defensible | Should -BeFalse
        $role.evidenceStatus | Should -Be 'insufficient-coverage'
        $role.comparisonOutcome | Should -Be 'declared-fit fallback'
        $role.coverage.gaps -join '; ' | Should -Match 'insufficient coverage'
    }

    It 'includes genuine verification renewal in the digest even when every numerical score is unchanged (SQ-33h)' {
        $fixture = New-PolicyRoster
        $beforeRaw = Get-Content -LiteralPath $fixture.Benchmarks -Raw
        $before = Get-SquadBenchmarkDigest -Content $beforeRaw
        Set-PolicyRow $fixture -Id gpt-5.6-sol -Evaluation SciCode -Score 0.700 -VerifiedDate '2026-10-20'
        $afterRaw = Get-Content -LiteralPath $fixture.Benchmarks -Raw
        (Get-SquadBenchmarkDigest -Content $afterRaw) | Should -Not -Be $before
        @((Get-SquadBenchmarkRowsFromMarkdown -Content $afterRaw).NumericScore) | Sort-Object |
            Should -Be (@((Get-SquadBenchmarkRowsFromMarkdown -Content $beforeRaw).NumericScore) | Sort-Object)
        (Invoke-PolicyRoute $fixture -AsOf ([datetime]'2026-10-20')).roles[0].evidenceStatus | Should -Be 'sufficient'
    }

    It 'does not renew evidence or change its semantic digest when only snapshot generation changes (SQ-33h)' {
        $fixture = New-PolicyRoster
        $before = Get-Content -LiteralPath $fixture.Benchmarks -Raw
        $after = $before.Replace('**Generated: 2026-10-19**', '**Generated: 2026-10-20**')
        (Get-SquadBenchmarkDigest -Content $after) | Should -Be (Get-SquadBenchmarkDigest -Content $before)
        Set-Content -LiteralPath $fixture.Benchmarks -Value $after -Encoding utf8NoBOM
        $role = (Invoke-PolicyRoute $fixture -AsOf ([datetime]'2026-10-20')).roles[0]
        $role.coverage.primary[0].verified | Should -Be '2026-10-19'
    }

    It 'hashes acquisition presence because filling an unknown acquisition can change eligibility' {
        $fixture = New-PolicyRoster
        $raw = Get-Content -LiteralPath $fixture.Benchmarks -Raw
        $rows = @(Get-SquadBenchmarkRowsFromMarkdown -Content $raw)
        foreach ($row in @($rows | Where-Object CatalogId -eq 'gpt-5.4')) { $row.Retrieved = 'unknown' }
        $missing = "## Benchmark Scores`n`n" + (@(Get-SquadBenchmarkScoreLine -Rows $rows) -join "`n")
        (Get-SquadBenchmarkScore -Rows $rows -AsOf ([datetime]'2026-10-19')).Models['gpt-5.4'].implementation.status | Should -Be 'unverified'
        foreach ($row in @($rows | Where-Object CatalogId -eq 'gpt-5.4')) { $row.Retrieved = '2026-10-19' }
        $known = "## Benchmark Scores`n`n" + (@(Get-SquadBenchmarkScoreLine -Rows $rows) -join "`n")
        (Get-SquadBenchmarkScore -Rows $rows -AsOf ([datetime]'2026-10-19')).Models['gpt-5.4'].implementation.status | Should -Be 'sufficient'
        (Get-SquadBenchmarkDigest -Content $known) | Should -Not -Be (Get-SquadBenchmarkDigest -Content $missing)
    }

    It 'allows a later acquisition without renewing an expired genuine verification' {
        $fixture = New-PolicyRoster
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation $evaluation -Date '2026-07-20' -RetrievedDate '2026-10-19'
        }
        $report = Invoke-PolicyRoute $fixture
        $bad = @($report.roles[0].evidenceCandidates | Where-Object id -eq 'gpt-5.4')[0]
        $report.warnings | Should -BeNullOrEmpty -Because 'valid expired evidence must not invalidate other candidates'
        $bad.evidenceStatus | Should -Be 'verification-expired'
        $bad.evaluations[0].retrieved | Should -Be '2026-10-19'
        $bad.evaluations[0].verified | Should -Be '2026-07-20'
        $bad.economyQualified | Should -BeFalse
    }

    It 'refuses a verification manifest bound to different scores without replacing the output' {
        $fixture = New-PolicyRoster
        $checks = New-FixtureVerificationFile -Snapshot $fixture.Benchmarks
        Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation SciCode -Score 0.601
        $output = Join-Path $fixture.Root 'last-good.md'
        Set-Content -LiteralPath $output -Value 'last good' -Encoding utf8NoBOM
        $before = (Get-FileHash -LiteralPath $output).Hash
        { & $script:SyncScript -SnapshotPath $fixture.Benchmarks -VerificationPath $checks -OutputPath $output -AsOf ([datetime]'2026-10-19') } |
            Should -Throw '*unmatched record digest*'
        (Get-FileHash -LiteralPath $output).Hash | Should -Be $before
    }

    It 'does not count case-variant evaluation labels as two independent models' {
        $rows = @(
            New-FixtureEvidenceRow -Id gpt-5.4 -Evaluation SciCode -Score 0.600
            New-FixtureEvidenceRow -Id gpt-5.4 -Evaluation scicode -Score 0.900
        )
        $score = Get-SquadBenchmarkScore -Rows $rows -AsOf ([datetime]'2026-10-19')
        $result = $score.Models['gpt-5.4'].implementation
        $result.capability | Should -BeNullOrEmpty
        @($result.evaluations | Where-Object evaluation -CEQ SciCode)[0].referenceCount | Should -Be 1
        $result.status | Should -Be 'insufficient-coverage'
    }

    It 'never pools different harness configurations even when their source versions match' {
        $fixture = New-PolicyRoster
        foreach ($evaluation in 'SciCode', 'Terminal-Bench') {
            Set-PolicyRow $fixture -Id gpt-5.4 -Evaluation $evaluation -Configuration 'different-agent-harness-v2'
        }
        $role = (Invoke-PolicyRoute $fixture).roles[0]
        $role.capability | Should -BeNullOrEmpty
        $role.evidenceStatus | Should -Be 'incomparable'
        $role.coverage.gaps -join '; ' | Should -Match 'incomparable source/version/evaluation configuration'
    }
}

Describe 'Sync original-source verification is a real check, not a new timestamp (SQ-33e,h)' {
    BeforeAll {
        $sync = Join-Path $script:ReferencesRoot '../../../../../scripts/Sync-ModelBenchmarks.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($sync, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw 'Sync source did not parse.' }
        foreach ($name in 'Get-ArtificialAnalysisModelRecordsLocal', 'Get-OnlineSciCodeVerificationLocal') {
            $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($function.Extent.Text))
        }
        $script:SupportedMethod = '<table><tr><td>SciCode</td><td>288 subproblems (test set)</td><td>3</td></tr></table><h4 id="scicode">SciCode</h4><p>scientist-annotated background information; sub-problem level scoring; Pass@1; 300-second execution timeout (dataset v1.0.1)</p><h3 id="next">Next</h3>'

        function Get-SyntheticPublisherHtml {
            param([decimal]$FirstScore = 0.600, [string]$FirstName = 'GPT-5.4 (High)')
            $data = @{ models = @(
                    @{ slug = 'gpt-5-4'; name = $FirstName; scicode = $FirstScore }
                    @{ slug = 'gpt-5-6-sol'; name = 'GPT-5.6 Sol (High)'; scicode = [decimal]0.700 }
                ) } | ConvertTo-Json -Depth 6 -Compress
            $payload = ConvertTo-Json -InputObject @(1, "a:$data`n") -Compress
            "<script>self.__next_f.push($payload)</script>"
        }
    }

    BeforeEach {
        $script:MethodFixture = $script:SupportedMethod
        $script:PublisherFixture = Get-SyntheticPublisherHtml
        $script:VerificationRows = @(
            New-FixtureEvidenceRow -Id gpt-5.4 -Evaluation SciCode -Score 0.600 -SourceId artificial-analysis -ModelVersion gpt-5.4_high -Verification unverified
            New-FixtureEvidenceRow -Id gpt-5.6-sol -Evaluation SciCode -Score 0.700 -SourceId artificial-analysis -ModelVersion gpt-5.6-sol_high -Verification unverified
        )
        foreach ($row in $script:VerificationRows) {
            $row.Retrieved = 'unknown'; $row.Verified = 'unknown'; $row.Configuration = 'unknown'; $row.VerificationBasis = 'unknown'
        }
        $script:RawSciCodeRows = @(
            [pscustomobject]@{ 'Model version' = 'gpt-5.4_high'; Score = '0.600'; 'AA model slug' = 'gpt-5-4' }
            [pscustomobject]@{ 'Model version' = 'gpt-5.6-sol_high'; Score = '0.700'; 'AA model slug' = 'gpt-5-6-sol' }
        )
        Mock Invoke-WebRequest {
            param($Uri)
            [pscustomobject]@{
                Content = if ([string]$Uri -like '*methodology*') { $script:MethodFixture } else { $script:PublisherFixture }
                BaseResponse = [pscustomobject]@{ RequestMessage = [pscustomobject]@{ RequestUri = [uri]$Uri } }
            }
        }
    }

    It 'checks exact publisher variants, values and the scoped protocol before recording verification' {
        $rows = @(Get-OnlineSciCodeVerificationLocal -Rows $script:VerificationRows -SciCodeRows $script:RawSciCodeRows)
        @($rows | Where-Object Verification -eq 'verified').Count | Should -Be 2
        $rows[0].Verified | Should -Be ([datetime]::UtcNow.ToString('yyyy-MM-dd'))
        $rows[0].ResultDate | Should -Be 'unknown'
        $rows[0].Configuration | Should -Be 'aa-scicode-v1.0.1-background-subproblem-pass1-r3-t300-v1'
        $rows[0].VerificationBasis | Should -Match '^sha256:[0-9a-f]{64}\+sha256:[0-9a-f]{64}$'
    }

    It 'does not borrow another evaluation section to verify an unknown SciCode harness' {
        $script:MethodFixture = $script:SupportedMethod.Replace('dataset v1.0.1', 'dataset v9.9') +
        '<h4 id="unrelated">Other evaluation</h4><p>dataset v1.0.1, 300-second, pass@1</p>'
        $rows = @(Get-OnlineSciCodeVerificationLocal -Rows $script:VerificationRows -SciCodeRows $script:RawSciCodeRows)
        @($rows | Where-Object Verification -eq 'verified').Count | Should -Be 0
        $rows[0].Retrieved | Should -Be ([datetime]::UtcNow.ToString('yyyy-MM-dd'))
        $rows[0].Verified | Should -Be 'unknown'
        $rows[0].Configuration | Should -Be 'unknown'
        Should -Invoke Invoke-WebRequest -Times 0 -ParameterFilter { [string]$Uri -like '*models/*' }
    }

    It 'does not verify a recently downloaded original record whose numerical result differs' {
        $script:PublisherFixture = Get-SyntheticPublisherHtml -FirstScore 0.999
        $rows = @(Get-OnlineSciCodeVerificationLocal -Rows $script:VerificationRows -SciCodeRows $script:RawSciCodeRows)
        $rows[0].Verification | Should -Be 'unverified'
        $rows[0].Verified | Should -Be 'unknown'
        $rows[0].VerificationReason | Should -Match 'does not reproduce this exact model variant and score'
        $rows[1].Verification | Should -Be 'verified'
    }

    It 'preserves original JSON numeric precision when checking a near-equal source value' {
        $score = [decimal]::Parse('0.60000000000000001', [System.Globalization.CultureInfo]::InvariantCulture)
        $script:PublisherFixture = Get-SyntheticPublisherHtml -FirstScore $score
        $rows = @(Get-OnlineSciCodeVerificationLocal -Rows $script:VerificationRows -SciCodeRows $script:RawSciCodeRows)
        $rows[0].Verification | Should -Be 'unverified'
        $rows[0].Verified | Should -Be 'unknown'
        $rows[1].Verification | Should -Be 'verified'
    }

    It 'refuses a publisher fallback configuration rather than attributing another model to this one' {
        $script:PublisherFixture = Get-SyntheticPublisherHtml -FirstName 'GPT-5.4 (High, GPT-5.5 Fallback)'
        $rows = @(Get-OnlineSciCodeVerificationLocal -Rows $script:VerificationRows -SciCodeRows $script:RawSciCodeRows)
        $rows[0].Verification | Should -Be 'incomparable'
        $rows[0].Verified | Should -Be 'unknown'
        $rows[0].VerificationReason | Should -Match 'single-model/configuration attribution unproven'
        $rows[1].Verification | Should -Be 'verified'
    }
}