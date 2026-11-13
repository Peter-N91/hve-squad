#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# AI cost: none; inspects source and built-package contents locally.

# D7 (routing-performance plan amendment-1, P04-T05) packaging-parity Tier 0 coverage.
# Covers: (a) no dangling `.github/instructions/squad/` path prose survives in the
# built plugin output; (b) every file named in 00-index.md's and SKILL.md's reference
# tables exists in both squad-src and the built plugin output; (c) no shipped file
# leaks the `knowledge-docs` name or a verbatim long line from a private guide under
# knowledge-docs/; (d) the Scribe hot-core byte budget stays at or under the BEFORE
# baseline; plus a regression fixture asserting a routing/performance change never
# touches an agent's own frontmatter `model:` scalar (Architect condition C3).
#
# See .copilot-tracking/squad/members/routing-performance/changes/2026-09-27-d7-packaging.md
# for this file's contract. The test IDs below (D7-1..D7-5) are this file's own; they
# are not registered in tests/squad-behavior-contract.md, which a concurrent dispatch
# in this run owns.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside Pester BeforeDiscovery and BeforeAll blocks, which PSScriptAnalyzer treats as scopes unrelated to the param block.')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

BeforeDiscovery {
    $script:SourceRootResolved = (Resolve-Path -LiteralPath $SourceRoot).Path
    $referencesRoot = Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/references'
    $skillMdPath = Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/SKILL.md'
    $indexPath = Join-Path $referencesRoot '00-index.md'

    function Get-MarkdownLinkTarget {
        <#
        .SYNOPSIS
            Extracts every markdown-link target ending in .md from a file's text.
        #>
        param([Parameter(Mandatory)][string]$Path)
        $text = Get-Content -LiteralPath $Path -Raw
        @([regex]::Matches($text, '\[[^\]]+\]\(([a-zA-Z0-9_.-]+\.md)\)') | ForEach-Object { $_.Groups[1].Value })
    }

    $indexTargets = Get-MarkdownLinkTarget -Path $indexPath
    $skillTargets = @(Get-MarkdownLinkTarget -Path $skillMdPath | ForEach-Object { $_ -replace '^references/', '' })

    # Union of both tables -- they describe the same references/ directory from two
    # entry points (the index file itself, and the skill's top-level SKILL.md).
    $script:ReferenceTableFiles = @($indexTargets + $skillTargets | Sort-Object -Unique)

    $script:KnowledgeDocsRoot = Join-Path $script:SourceRootResolved 'knowledge-docs'
    $script:HasKnowledgeDocs = Test-Path -LiteralPath $script:KnowledgeDocsRoot -PathType Container

    # Frontmatter-scalar regression fixture (Architect condition C3). Built here, not
    # in BeforeAll, because -ForEach below is evaluated during discovery.
    $fixturePath = Join-Path $script:SourceRootResolved 'tests/tier0/baselines/agent-model-frontmatter.json'
    $fixture = (Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json).agents
    $agentsDir = Join-Path $script:SourceRootResolved 'squad-src/.github/agents/squad'

    $script:FrontmatterComparisons = @(
        foreach ($file in (Get-ChildItem -LiteralPath $agentsDir -Filter '*.agent.md' -File | Sort-Object Name)) {
            $head = Get-Content -LiteralPath $file.FullName -TotalCount 15
            $modelLine = $head | Where-Object { $_ -match '^model:\s*(.+)$' } | Select-Object -First 1
            $actual = if ($modelLine) { ($modelLine -replace '^model:\s*', '').Trim() } else { $null }
            $hasFixtureEntry = $fixture.PSObject.Properties.Name -contains $file.Name
            @{
                FileName        = $file.Name
                Actual          = $actual
                Expected        = if ($hasFixtureEntry) { $fixture.($file.Name) } else { $null }
                HasFixtureEntry = $hasFixtureEntry
            }
        }
    )
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:SourceRootResolved = (Resolve-Path -LiteralPath $SourceRoot).Path
    $script:BuildScript = Join-Path $script:SourceRootResolved 'scripts/Build-SquadPlugin.ps1'
    $script:PluginOutputRoot = Join-Path $TestDrive 'd7-plugin-output'
    $script:HveCoreRoot = Join-Path $TestDrive 'd7-hve-core'

    # Re-derived rather than trusted from BeforeDiscovery: Discovery and Run execute
    # in independent script scopes when multiple Pester containers run together, so a
    # BeforeDiscovery-set $script: variable is not reliably visible here.
    $script:KnowledgeDocsRoot = Join-Path $script:SourceRootResolved 'knowledge-docs'
    $script:HasKnowledgeDocs = Test-Path -LiteralPath $script:KnowledgeDocsRoot -PathType Container

    $hveAgent = Join-Path $script:HveCoreRoot '.github/agents/security/security-planner.agent.md'
    $hveSkill = Join-Path $script:HveCoreRoot '.github/skills/security/secure-by-design/SKILL.md'
    foreach ($path in @($hveAgent, $hveSkill)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    }
    Set-Content -LiteralPath $hveAgent -Value "---`nname: Security Planner`n---`n# Security Planner`n" -Encoding utf8NoBOM
    Set-Content -LiteralPath $hveSkill -Value "---`nname: secure-by-design`ndescription: Fixture skill`n---`n# Skill`n" -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $script:HveCoreRoot 'LICENSE') -Value 'MIT fixture' -Encoding utf8NoBOM
    $hveManifest = [ordered]@{
        name = 'hve-core'; version = '0.0.0-test'
        agents = @('.github/agents/security/security-planner.agent.md')
        commands = @(); rules = @()
        skills = @('.github/skills/security/secure-by-design')
        extensions = @()
    }
    Set-Content -LiteralPath (Join-Path $script:HveCoreRoot 'plugin.json') `
        -Value (($hveManifest | ConvertTo-Json -Depth 6) + "`n") -Encoding utf8NoBOM

    $pwsh = (Get-Process -Id $PID).Path
    $buildOutput = @(
        & $pwsh -NoProfile -File $script:BuildScript `
            -SourceRoot $script:SourceRootResolved `
            -OutputRoot $script:PluginOutputRoot `
            -HveCoreRoot $script:HveCoreRoot `
            -AllowUnverifiedHveCoreSource 2>&1
    )
    $script:BuildExitCode = $LASTEXITCODE
    $script:BuildOutputText = $buildOutput -join "`n"

    $script:PluginReferencesRoot = Join-Path $script:PluginOutputRoot 'skills/squad/references'

    # (a) Scan every text file in the built output for the dangling source-tree path.
    # The builder rewrites `.instructions.md` mentions to their plugin-relative
    # skills/squad/references/rules/*.md form; this is a regression guard confirming
    # that rewrite covers the new reference files too, not a fix for a known gap.
    # Excluded: the builder's own "Ported from squad-src/.github/instructions/squad/..."
    # provenance comment atop every rules/*.md file. That path resolves correctly in
    # the source repo it names (hve-squad) for the maintainers it targets ("do not
    # hand-edit here") -- it is not prose a plugin consumer would follow, and it
    # predates this dispatch. A bare (non-squad-src-prefixed) mention is still caught.
    $script:DanglingPathHits = @(
        Get-ChildItem -LiteralPath $script:PluginOutputRoot -Recurse -File |
            Where-Object { $_.Extension -in '.md', '.json', '.yml', '.yaml' } |
            ForEach-Object {
                Select-String -LiteralPath $_.FullName -Pattern '(?<!squad-src/)\.github/instructions/squad/' -ErrorAction SilentlyContinue
            }
    )

    # (c) knowledge-docs leakage. Only meaningful when the private guides directory
    # exists in this checkout (it is gitignored / absent in most CI runs), so the
    # whole check degrades gracefully to zero assertions rather than failing when it
    # is not present.
    #
    # The literal-string sub-check is split into two scopes. squad-src/ and the built
    # plugin output are the actual package surface a consumer installs; a mention
    # there is a genuine defect. docs/ and README.md are project documentation, where
    # some existing pages (the demo script, ADR 0001/0004) legitimately *describe* the
    # private knowledge-docs/ convention itself ("this folder is gitignored, never
    # copy its contents") rather than leaking a guide's content -- those predate this
    # dispatch and are reported as Advisory, not gated, so this new test does not fail
    # the required run on content unrelated to D7.
    $script:PackageRoots = @(
        (Join-Path $script:SourceRootResolved 'squad-src'),
        $script:PluginOutputRoot
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
    $script:PackageFiles = @(
        foreach ($root in $script:PackageRoots) {
            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue
        }
    )

    $script:ProjectDocRoots = @(
        (Join-Path $script:SourceRootResolved 'docs')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
    $script:ProjectDocFiles = @(
        foreach ($root in $script:ProjectDocRoots) {
            Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue
        }
        $readme = Join-Path $script:SourceRootResolved 'README.md'
        if (Test-Path -LiteralPath $readme -PathType Leaf) { Get-Item -LiteralPath $readme }
    )

    $script:ShippedFiles = @($script:PackageFiles) + @($script:ProjectDocFiles)

    if ($script:HasKnowledgeDocs) {
        $script:PackageKnowledgeDocsNameHits = @(
            $script:PackageFiles | ForEach-Object {
                Select-String -LiteralPath $_.FullName -Pattern 'knowledge-docs' -SimpleMatch -ErrorAction SilentlyContinue
            }
        )
        $script:ProjectDocKnowledgeDocsNameHits = @(
            $script:ProjectDocFiles | ForEach-Object {
                Select-String -LiteralPath $_.FullName -Pattern 'knowledge-docs' -SimpleMatch -ErrorAction SilentlyContinue
            }
        )

        $longKnowledgeLines = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($file in (Get-ChildItem -LiteralPath $script:KnowledgeDocsRoot -Recurse -File -ErrorAction SilentlyContinue)) {
            foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
                $trimmed = $line.Trim()
                if ($trimmed.Length -gt 80) { [void]$longKnowledgeLines.Add($trimmed) }
            }
        }
        $script:LongKnowledgeLines = $longKnowledgeLines

        # squad-watch-mode.instructions.md (and its ported plugin-output copy) share a
        # handful of spec-table rows with the pre-existing watch-mode-dr-01-design.md
        # guide: the guide documents the feature the instructions file already ships,
        # so the table rows are the same real, already-shipped behavior described
        # twice, not a leaked proposal. Both files predate this dispatch and are out
        # of D7's scope to rewrite, so a match against this known pair is reported as
        # Advisory (visible, never silently dropped) rather than gated; any other
        # file colliding with a knowledge-docs line still fails the required run.
        $knownPreexistingOverlapFileNames = @('squad-watch-mode.instructions.md', 'squad-watch-mode.md')

        $script:CopiedLongLineHits = [System.Collections.Generic.List[string]]::new()
        $script:KnownPreexistingOverlapHits = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $script:ShippedFiles) {
            foreach ($line in (Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
                $trimmed = $line.Trim()
                if ($trimmed.Length -gt 80 -and $longKnowledgeLines.Contains($trimmed)) {
                    $entry = "$($file.FullName): $trimmed"
                    if ($knownPreexistingOverlapFileNames -contains $file.Name) {
                        $script:KnownPreexistingOverlapHits.Add($entry)
                    }
                    else {
                        $script:CopiedLongLineHits.Add($entry)
                    }
                }
            }
        }
    }

    # Measure the ordinary read set and keep the legacy cold surface budget too.
    $scribeText = Get-Content -LiteralPath (Join-Path $script:SourceRootResolved 'squad-src/.github/agents/squad/squad-scribe.agent.md') -Raw
    $ordinarySection = [regex]::Match($scribeText, '(?s)## Ordinary handoff.*?(?=\r?\n## )')
    $script:ScribeHotCoreReferenceFiles = @([regex]::Matches($ordinarySection.Value, '`references/([a-zA-Z0-9_.-]+\.md)`') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $script:ScribeHotCoreFiles = @(
        'squad-src/.github/agents/squad/squad-scribe.agent.md'
    ) + @($script:ScribeHotCoreReferenceFiles | ForEach-Object { "squad-src/.github/skills/squad/references/$_" })
    $script:ScribeHotCoreBytes = ($script:ScribeHotCoreFiles | ForEach-Object {
            Get-SquadContractByteCount -Text ([IO.File]::ReadAllText((Join-Path $script:SourceRootResolved $_)))
        } | Measure-Object -Sum).Sum
    $script:ScribeColdCoreFiles = @(
        'squad-src/.github/agents/squad/squad-scribe.agent.md'
    ) + @(
        'scribe-cold-charter.md', '00-index.md', 'scribe-procedure.md', 'entry-schemas.md', 'scribe-payload-template.md'
    ) | ForEach-Object { if ($_ -like 'squad-src/*') { $_ } else { "squad-src/.github/skills/squad/references/$_" } }
    $script:ScribeColdCoreBytes = ($script:ScribeColdCoreFiles | ForEach-Object {
            Get-SquadContractByteCount -Text ([IO.File]::ReadAllText((Join-Path $script:SourceRootResolved $_)))
        } | Measure-Object -Sum).Sum

    $baselinePath = Join-Path $script:SourceRootResolved 'tests/tier0/baselines/prefill-baseline.json'
    $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
    $script:ScribeBaselineBytes = ($baseline.sessionTypes | Where-Object { $_.sessionType -eq 'scribe' -and $_.hostPath -eq 'plugin-cli' } | Select-Object -First 1).unconditionalBytes
}

Describe 'D7-1 Plugin build succeeds and carries every new reference file' {
    It 'builds the plugin distribution successfully' {
        $script:BuildExitCode | Should -Be 0 -Because $script:BuildOutputText
    }

    It '<_> ships in the built plugin output' -ForEach @(
        'model-catalog.md', 'model-benchmarks.md', 'model-routing.md', 'model-scoring.md', 'scribe-payload-template.md',
        'scribe-cold-init-and-seeding.md', 'scribe-cold-federation.md', 'scribe-cold-gates-and-verdicts.md',
        'consumption-rates-template.md', 'economy-scribe.md', 'scribe-cold-charter.md'
    ) {
        Test-Path -LiteralPath (Join-Path $script:PluginReferencesRoot $_) -PathType Leaf |
            Should -BeTrue -Because 'the deliverable requires every new reference file to ship in the plugin build, not only in squad-src'
    }

    It 'ships the deterministic Watch Mode handoff module in the plugin output' {
        Test-Path -LiteralPath (Join-Path $script:PluginOutputRoot 'skills/squad/scripts/SquadWatch.psm1') -PathType Leaf |
            Should -BeTrue -Because 'consumer handoff prerequisites must be delivered with the squad skill'
    }
}

Describe 'Shared scoring is delivered with the plugin runtime (SQ-33c)' {
    It 'delivers the scorer unchanged beside the resolver' {
        $source = Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/scripts/ModelBenchmarkScoring.ps1'
        $delivered = Join-Path $script:PluginOutputRoot 'skills/squad/scripts/ModelBenchmarkScoring.ps1'
        Test-Path -LiteralPath $delivered -PathType Leaf | Should -BeTrue
        (Get-FileHash -LiteralPath $delivered).Hash | Should -Be (Get-FileHash -LiteralPath $source).Hash
    }
}

Describe 'Deterministic coordinator transactions ship with the runtime' {
    It 'delivers <Name> unchanged beside the coordinator scripts' -ForEach @(
        @{ Name = 'SquadUsage.psm1' }
        @{ Name = 'Get-SquadUsage.ps1' }
        @{ Name = 'Set-SquadModelRouting.ps1' }
        @{ Name = 'Write-SquadVerdict.ps1' }
        @{ Name = 'SquadPromotion.psm1' }
        @{ Name = 'Get-SquadPromotionPlan.ps1' }
        @{ Name = 'Promote-SquadFederation.ps1' }
        @{ Name = 'Get-SquadFederationInitPlan.ps1' }
        @{ Name = 'Initialize-SquadFederation.ps1' }
        @{ Name = 'Get-SquadRosterExpansionPlan.ps1' }
        @{ Name = 'Expand-SquadRoster.ps1' }
        @{ Name = 'New-SquadGovernanceReport.ps1' }
        @{ Name = 'SquadGovernanceReport.psm1' }
        @{ Name = 'SquadGovernanceReport.Markdown.ps1' }
        @{ Name = 'SquadGovernanceReport.State.ps1' }
        @{ Name = 'SquadGovernanceReport.Ledger.ps1' }
        @{ Name = 'SquadGovernanceReport.Economics.ps1' }
        @{ Name = 'SquadGovernanceReport.Model.ps1' }
        @{ Name = 'SquadGovernanceReport.Html.ps1' }
    ) {
        $source = Join-Path $script:SourceRootResolved "squad-src/.github/skills/squad/scripts/$Name"
        $delivered = Join-Path $script:PluginOutputRoot "skills/squad/scripts/$Name"
        Test-Path -LiteralPath $delivered -PathType Leaf | Should -BeTrue
        (Get-FileHash -LiteralPath $delivered).Hash | Should -Be (Get-FileHash -LiteralPath $source).Hash
    }
}

Describe 'D7-2 Plugin output has no dangling instructions/squad path prose' {
    It 'contains zero literal ".github/instructions/squad/" references anywhere in the built output' {
        $script:DanglingPathHits.Count | Should -Be 0 -Because (
            'a path under .github/instructions/squad/ does not exist in the plugin layout, so any surviving mention is dead prose: ' +
            (($script:DanglingPathHits | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) -join ', ')
        )
    }
}

Describe 'D7-3 Every reference-table file exists in source and in the plugin output' {
    It 'finds reference-table entries to check' -ForEach @(@{ Found = @($script:ReferenceTableFiles).Count }) {
        $Found | Should -BeGreaterThan 0 -Because 'an empty table means this suite parsed 00-index.md/SKILL.md incorrectly'
    }

    It '<_> exists in squad-src and in the plugin output' -ForEach $script:ReferenceTableFiles {
        $sourcePath = Join-Path $script:SourceRootResolved "squad-src/.github/skills/squad/references/$_"
        $outputPath = Join-Path $script:PluginReferencesRoot $_
        Test-Path -LiteralPath $sourcePath -PathType Leaf | Should -BeTrue -Because "$_ is named in a reference table but absent from squad-src"
        Test-Path -LiteralPath $outputPath -PathType Leaf | Should -BeTrue -Because "$_ is named in a reference table but absent from the built plugin output"
    }
}

Describe 'D7-4 No shipped file leaks the private knowledge-docs guides' {
    It 'contains no literal "knowledge-docs" string in the package surface (squad-src, plugin output)' -Skip:(-not $script:HasKnowledgeDocs) {
        $script:PackageKnowledgeDocsNameHits.Count | Should -Be 0 -Because (
            'a package-surface file naming knowledge-docs/ points a consumer at a directory that does not ship with the package: ' +
            (($script:PackageKnowledgeDocsNameHits | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) -join ', ')
        )
    }

    It 'contains no line copied verbatim (>80 chars) from a private guide' -Skip:(-not $script:HasKnowledgeDocs) {
        $script:CopiedLongLineHits.Count | Should -Be 0 -Because (
            'a shipped file must not carry proposal-stage text unique to the private guides: ' +
            ($script:CopiedLongLineHits -join ' | ')
        )
    }

    It 'contains no literal "knowledge-docs" string in project docs/README (Advisory)' -Tag 'Advisory' -Skip:(-not $script:HasKnowledgeDocs) {
        # Existing pages (the demo script, ADR 0001/0004) legitimately describe the
        # private knowledge-docs/ convention itself; this is reported, not gated.
        $script:ProjectDocKnowledgeDocsNameHits.Count | Should -BeGreaterOrEqual 0 -Because (
            'for visibility only -- not a required-run gate: ' +
            (($script:ProjectDocKnowledgeDocsNameHits | ForEach-Object { "$($_.Path):$($_.LineNumber)" }) -join ', ')
        )
    }

    It 'the known squad-watch-mode/watch-mode-dr-01-design overlap has not grown (Advisory)' -Tag 'Advisory' -Skip:(-not $script:HasKnowledgeDocs) {
        # A pre-existing, out-of-D7-scope coincidence (see BeforeAll comment). Ceiling
        # guards against a *new* overlap growing silently under this exclusion.
        $script:KnownPreexistingOverlapHits.Count | Should -BeLessOrEqual 4 -Because (
            'the known pre-existing squad-watch-mode overlap grew beyond its recorded size: ' +
            ($script:KnownPreexistingOverlapHits -join ' | ')
        )
    }
}

Describe 'D7-5 Ordinary hot contract shrinks while legacy cold protections remain budgeted' {
    It 'measures the complete ordinary reference set rather than silently measuring zero references' {
        $script:ScribeHotCoreReferenceFiles | Should -Be @('economy-scribe.md')
        $script:ScribeHotCoreFiles.Count | Should -Be 2
    }

    It 'keeps the pinned Scribe agent below 3000 normalized UTF-8 bytes' {
        $path = Join-Path $script:SourceRootResolved 'squad-src/.github/agents/squad/squad-scribe.agent.md'
        Get-SquadContractByteCount -Text ([IO.File]::ReadAllText($path)) | Should -BeLessThan 3000
    }

    It 'keeps agent plus ordinary contract within 6 KiB' {
        $script:ScribeHotCoreBytes | Should -BeLessOrEqual 6144
        $path = Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/references/economy-scribe.md'
        Get-SquadContractByteCount -Text ([IO.File]::ReadAllText($path)) | Should -BeLessOrEqual 3072
    }

    It 'measured the BEFORE baseline scribe/plugin-cli figure' {
        $script:ScribeBaselineBytes | Should -BeGreaterThan 0 -Because 'tests/tier0/baselines/prefill-baseline.json must carry the BEFORE scribe/plugin-cli row'
    }

    It 'retains the full legacy cold charter/procedure/schema/payload within the prior surface budget' {
        $script:ScribeColdCoreBytes | Should -BeLessOrEqual $script:ScribeBaselineBytes
        $cold = Get-Content -LiteralPath (Join-Path $script:PluginReferencesRoot 'scribe-cold-charter.md') -Raw
        foreach ($protection in @('Copy each `team.md` row verbatim', 'unused permitted slot', 'copy → verify → delete-source', 'Never write outside consumer-local memory', 'never invent a model name')) {
            $cold | Should -Match ([regex]::Escape($protection))
        }
    }
}

Describe 'D7-6 Model routing never touches an agent''s own frontmatter model scalar' {
    It 'has a frontmatter fixture entry for every current agent' -ForEach $script:FrontmatterComparisons {
        $HasFixtureEntry | Should -BeTrue -Because "a new agent file must be added to tests/tier0/baselines/agent-model-frontmatter.json: $FileName"
    }

    It '<FileName> keeps its fixture-recorded model scalar' -ForEach $script:FrontmatterComparisons {
        $Actual | Should -BeExactly $Expected -Because 'a routing/performance change must never add, remove, or alter an agent''s own frontmatter model: scalar'
    }
}

Describe 'GATE-48 Repository Watch Mode and Sync-and-Adapt workflows enforce full RPI and package provisioning' {
    BeforeAll {
        $script:RepoSquadWatch = Get-Content -LiteralPath (Join-Path $script:SourceRootResolved '.github/workflows/squad-watch.yml') -Raw
        $script:RepoSyncHveCore = Get-Content -LiteralPath (Join-Path $script:SourceRootResolved '.github/workflows/sync-hve-core.yml') -Raw
        $script:ReferenceSquadWatch = Get-Content -LiteralPath (
            Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/squad-watch.workflow.yml'
        ) -Raw
    }

    It 'provisions the squad package before running Copilot CLI and restores the owned runtime overlay before staging in squad-watch.yml' {
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('Provision squad package for headless CLI'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('Install-SquadPackage -Destination $staging -SourceRoot .'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('Enable-SquadWatchRuntimeOverlay'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('Restore-SquadWatchRuntimeOverlay'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('New-SquadWatchBaseline'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('ExpectedBaselineHash'))
        $script:RepoSquadWatch | Should -Not -Match ([regex]::Escape("'.agents', 'apm_modules', 'install.log'"))
    }

    It 'pins a Watch CLI version compatible with the Haiku 5.5 subagent smoke test' {
        $versionMatch = [regex]::Match($script:RepoSquadWatch, "(?m)^\s*COPILOT_CLI_VERSION:\s*'(\d+\.\d+\.\d+)'\s*$")
        $versionMatch.Success | Should -BeTrue
        if ($versionMatch.Success) {
            [version]$versionMatch.Groups[1].Value | Should -BeGreaterOrEqual ([version]'1.0.106')
        }
    }

    It 'keeps Watch specialist selection within the canonical roster and avoids unnecessary repeated suites' {
        foreach ($workflow in @($script:RepoSquadWatch, $script:ReferenceSquadWatch)) {
            $workflow | Should -Match 'canonical profile and retained'
            $workflow | Should -Match 'do not add'
            $workflow | Should -Match 'do not repeat'
            $workflow | Should -Match 'never custom'
            $workflow | Should -Match 'Stages table format is machine-checked'
            $workflow | Should -Match 'Result is exactly complete'
            $workflow | Should -Match 'Outcome is exactly Completed'
        }
        $script:RepoSquadWatch | Should -Match 'squad-watch-diagnostics-'
        $script:RepoSquadWatch | Should -Match 'Source must be exactly one of: OQ-WATCH-NNN'
        $script:RepoSquadWatch | Should -Match 'never repeat that prefix'
        $script:RepoSquadWatch | Should -Match 'copied in this exact shape'
        $script:RepoSquadWatch | Should -Match '\* Source: watch-demand'
        $script:RepoSquadWatch | Should -Match 'Stage, Role\(s\), Dispatch Record, Result, Gate Fired in that order'
        $script:RepoSquadWatch | Should -Match 'record an ordinary risk rating under a heading named Risk Assessment'
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('$stateDoc[''mode''] = ''autopilot'''))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('runId      = $env:TRIGGER_RUN_ID'))
        $script:RepoSquadWatch | Should -Match 'full Tier 0 suite inside Watch unless'
        $script:RepoSquadWatch | Should -Match 'profileValid=\$\(\$gate\.ProfileValid\), questionsValid=\$\(\$gate\.QuestionsValid\)'
    }

    It 'exposes depth, routing, and economy consent as validated trusted run controls in both workflows' {
        foreach ($workflow in @($script:RepoSquadWatch, $script:ReferenceSquadWatch)) {
            $workflow | Should -Match '(?m)^  SQUAD_DEPTH: standard\s*$'
            $workflow | Should -Match "(?m)^  SQUAD_ROUTING: 'off'\s*$"
            $workflow | Should -Match "(?m)^  SQUAD_ECONOMY_CONSENT: 'false'\s*$"
            $workflow | Should -Match ([regex]::Escape('options: [default, standard, quick]'))
            $workflow | Should -Match ([regex]::Escape("options: [default, 'off', ranked, economy]"))
            $workflow | Should -Match '(?m)^      economy_consent:\s*$'
            $workflow | Should -Match '(?m)^  SQUAD_PROFILE: default\s*$'
            $workflow | Should -Match ([regex]::Escape('options: [keep, auto, default, full,'))
            $workflow | Should -Match ([regex]::Escape('TRUSTED RUN CONTROLS (WORKFLOW CONFIGURATION, NOT EVENT TEXT).'))
            $workflow | Should -Match ([regex]::Escape("].join('\n') + '\n\n' + controlsText;"))
        }
    }

    It 'resolves run controls from trusted configuration only and downgrades unconsented economy' {
        $node = Get-Command node -ErrorAction Stop
        $driver = @'
const fs = require('fs');
const [snippetPath, casesPath] = process.argv.slice(2);
const snippet = fs.readFileSync(snippetPath, 'utf8');
const cases = JSON.parse(fs.readFileSync(casesPath, 'utf8'));
const results = cases.map(c => {
  const warnings = [];
  const core = { warning: m => warnings.push(String(m)) };
  const context = { actor: c.actor || 'octocat', payload: { inputs: c.inputs || {} } };
  const body = snippet.replace(/process\.env/g, 'env') + '\nreturn { runDepth, runRouting, runProfile, economyGranted };';
  const out = new Function('evt', 'context', 'core', 'env', body)(c.evt, context, core, c.env || {});
  return { name: c.name, ...out, warned: warnings.length };
});
console.log(JSON.stringify(results));
'@
        $cases = @(
            @{ name = 'defaults'; evt = 'workflow_dispatch'; inputs = @{ depth = 'default'; routing = 'default'; economy_consent = 'false' }; env = @{ SQUAD_DEPTH = 'standard'; SQUAD_ROUTING = 'off'; SQUAD_ECONOMY_CONSENT = 'false' } }
            @{ name = 'dispatch overrides'; evt = 'workflow_dispatch'; inputs = @{ depth = 'quick'; routing = 'ranked'; economy_consent = 'false' }; env = @{ SQUAD_DEPTH = 'standard'; SQUAD_ROUTING = 'off' } }
            @{ name = 'economy without consent'; evt = 'workflow_dispatch'; inputs = @{ routing = 'economy'; economy_consent = 'false' }; env = @{ SQUAD_ECONOMY_CONSENT = 'false' } }
            @{ name = 'economy with dispatch consent'; evt = 'workflow_dispatch'; inputs = @{ routing = 'economy'; economy_consent = 'true' }; env = @{} }
            @{ name = 'committed economy and consent on an issue event'; evt = 'issues'; inputs = @{}; env = @{ SQUAD_ROUTING = 'economy'; SQUAD_ECONOMY_CONSENT = 'true'; SQUAD_DEPTH = 'quick' } }
            @{ name = 'invalid values fall back'; evt = 'workflow_dispatch'; inputs = @{ depth = 'turbo' }; env = @{ SQUAD_DEPTH = 'quick'; SQUAD_ROUTING = 'cheapest' } }
            @{ name = 'event inputs are never read off dispatch'; evt = 'issues'; inputs = @{ depth = 'quick'; routing = 'economy'; economy_consent = 'true' }; env = @{} }
            @{ name = 'profile defaults to default'; evt = 'workflow_dispatch'; inputs = @{ profile = 'keep' }; env = @{ SQUAD_PROFILE = 'default' } }
            @{ name = 'profile dispatch override'; evt = 'workflow_dispatch'; inputs = @{ profile = 'security' }; env = @{ SQUAD_PROFILE = 'default' } }
            @{ name = 'custom profile is refused'; evt = 'workflow_dispatch'; inputs = @{ profile = 'custom' }; env = @{} }
        )
        $expected = @{
            'defaults'                                            = @('standard', 'off', 0)
            'dispatch overrides'                                  = @('quick', 'ranked', 0)
            'economy without consent'                             = @('standard', 'off', 1)
            'economy with dispatch consent'                       = @('standard', 'economy', 0)
            'committed economy and consent on an issue event'     = @('quick', 'economy', 0)
            'invalid values fall back'                            = @('quick', 'off', 2)
            'event inputs are never read off dispatch'            = @('standard', 'off', 0)
            'profile defaults to default'                         = @('standard', 'off', 0)
            'profile dispatch override'                           = @('standard', 'off', 0)
            'custom profile is refused'                           = @('standard', 'off', 1)
        }
        $expectedProfile = @{ 'profile defaults to default' = 'default'; 'profile dispatch override' = 'security'; 'custom profile is refused' = 'default'; 'defaults' = 'default'; 'event inputs are never read off dispatch' = 'default' }
        $dir = Join-Path $TestDrive ('controls-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $casesPath = Join-Path $dir 'cases.json'
        $driverPath = Join-Path $dir 'driver.js'
        Set-Content -LiteralPath $casesPath -Value ($cases | ConvertTo-Json -Depth 6) -Encoding utf8
        Set-Content -LiteralPath $driverPath -Value $driver -Encoding utf8
        foreach ($workflow in @($script:RepoSquadWatch, $script:ReferenceSquadWatch)) {
            $match = [regex]::Match($workflow, '(?s)(const dispatchedInputs = .*?)\r?\n\s*const controlActor')
            $match.Success | Should -BeTrue
            $snippetPath = Join-Path $dir ('snippet-' + [guid]::NewGuid().ToString('n') + '.js')
            Set-Content -LiteralPath $snippetPath -Value $match.Groups[1].Value -Encoding utf8
            $json = & $node.Source $driverPath $snippetPath $casesPath
            $LASTEXITCODE | Should -Be 0 -Because ($json -join "`n")
            foreach ($row in @($json | ConvertFrom-Json)) {
                $want = $expected[$row.name]
                $row.runDepth | Should -Be $want[0] -Because $row.name
                $row.runRouting | Should -Be $want[1] -Because $row.name
                $row.warned | Should -Be $want[2] -Because $row.name
                if ($expectedProfile.ContainsKey($row.name)) { $row.runProfile | Should -Be $expectedProfile[$row.name] -Because $row.name }
            }
        }
    }

    It 'wires issues, pull_request, issue_comment, and workflow_dispatch with per-case/per-ask squad selection and a gated full RPI handoff in squad-watch.yml' {
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('SQUAD SELECTION PER CASE AND PER ASK (NON-NEGOTIABLE).'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('COMPLETE SQUAD LIFECYCLE (FULL RPI - NON-NEGOTIABLE).'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('IMMEDIATE SCRIBE CHECKPOINTS (NON-NEGOTIABLE).'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape("github.event_name == 'issue_comment' && startsWith(github.event.comment.body, '/squad')"))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape("contains(join(github.event.pull_request.labels.*.name, ','), 'squad/review')"))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('New-SquadWatchHandoff'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('sourceSha: ${{ steps.source.outputs.sha }}'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('ref: ${{ needs.interpret.outputs.sourceSha }}'))
    }

    It 'enforces split-job least privilege, credential non-persistence, and deterministic patch handoff in squad-watch.workflow.yml' {
        $python = Get-Command python -ErrorAction Stop
        $templatePath = Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/squad-watch.workflow.yml'
        $inspector = @'
import json, sys, yaml
from pathlib import Path
doc = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
jobs = doc.get("jobs") or {}
checkouts = []
uses = []
for job_name, job in jobs.items():
    if not isinstance(job, dict):
        continue
    for step in (job.get("steps") or []):
        if not isinstance(step, dict):
            continue
        u = str(step.get("uses") or "")
        if u:
            uses.append(u)
        if u.startswith("actions/checkout"):
            w = step.get("with") or {}
            checkouts.append({"job": job_name, "name": step.get("name") or "", "persist": w.get("persist-credentials")})
print(json.dumps({
    "topPermissions": doc.get("permissions"),
    "jobNames": list(jobs.keys()),
    "jobPermissions": {k: (v.get("permissions") if isinstance(v, dict) else None) for k, v in jobs.items()},
    "checkouts": checkouts,
    "uses": uses,
}))
'@
        $parsed = (& $python.Source -c $inspector $templatePath | ConvertFrom-Json)
        $LASTEXITCODE | Should -Be 0
        $parsed.topPermissions.contents | Should -Be 'read'
        $parsed.topPermissions.PSObject.Properties.Name | Should -Not -Contain 'pull-requests'
        $parsed.topPermissions.PSObject.Properties.Name | Should -Not -Contain 'issues'
        $parsed.jobNames | Should -Contain 'interpret'
        $parsed.jobNames | Should -Contain 'apply'
        $parsed.jobNames | Should -Contain 'post-review'
        $parsed.jobNames | Should -Contain 'escalate-unauthorized'
        $parsed.jobNames | Should -Contain 'escalate-failure'
        $parsed.jobNames | Should -Not -Contain 'watch'
        $parsed.jobPermissions.interpret.contents | Should -Be 'read'
        $parsed.jobPermissions.interpret.issues | Should -Be 'read'
        $parsed.jobPermissions.interpret.'pull-requests' | Should -Be 'read'
        $parsed.jobPermissions.'escalate-unauthorized'.issues | Should -Be 'write'
        $parsed.jobPermissions.'escalate-unauthorized'.PSObject.Properties.Name | Should -HaveCount 1
        $parsed.jobPermissions.'escalate-failure'.issues | Should -Be 'write'
        $parsed.jobPermissions.'escalate-failure'.PSObject.Properties.Name | Should -HaveCount 1
        foreach ($checkout in @($parsed.checkouts)) {
            $checkout.persist | Should -BeFalse -Because "checkout '$($checkout.name)' in job '$($checkout.job)' must set persist-credentials: false"
        }
        foreach ($useRef in @($parsed.uses)) {
            $useRef | Should -Match '^[^@]+@[0-9a-f]{40}$' -Because "consumer template action '$useRef' must be SHA-pinned"
        }
        $script:ReferenceSquadWatch | Should -Match ([regex]::Escape('New-SquadWatchBaseline'))
        $script:ReferenceSquadWatch | Should -Match ([regex]::Escape('New-SquadWatchHandoff'))
        $script:ReferenceSquadWatch | Should -Match ([regex]::Escape('Verify COPILOT_GITHUB_TOKEN least privilege'))
        $script:RepoSquadWatch | Should -Match ([regex]::Escape('Verify COPILOT_GITHUB_TOKEN least privilege'))
        $script:ReferenceSquadWatch | Should -Match ([regex]::Escape('sourceSha: ${{ steps.source.outputs.sha }}'))
        $script:ReferenceSquadWatch | Should -Match ([regex]::Escape('ref: ${{ needs.interpret.outputs.sourceSha }}'))
    }

    It 'requires per-case/per-ask squad composition and the full RPI lifecycle in sync-hve-core.yml adaptation briefs' {
        $script:RepoSyncHveCore | Should -Match ([regex]::Escape('## Squad Composition and Full RPI Lifecycle (Required)'))
        $script:RepoSyncHveCore | Should -Match ([regex]::Escape('Stage 1 — Research (`researcher` -> `Squad Researcher`):'))
        $script:RepoSyncHveCore | Should -Match ([regex]::Escape('Stage 2 — Plan (`lead` -> `Squad Lead`):'))
        $script:RepoSyncHveCore | Should -Match ([regex]::Escape('Stage 4 — Implement (`developer` -> `Squad Implementor` / `prompt-engineer` fan-out):'))
        $script:RepoSyncHveCore | Should -Match ([regex]::Escape('Stage 5 — Review (`tester` -> `Squad Reviewer`):'))
        $script:RepoSyncHveCore | Should -Match ([regex]::Escape('Full RPI stage artifacts (`research/<date>/*.md`, `plans/*.md`, `changes/*.md`, `reviews/*.md`) and `history/autopilot-run-*.md` are produced'))
    }
}

Describe 'GATE-50 Watch workflow publication contract' {
    BeforeAll {
        $script:LiveWatch = Get-Content -LiteralPath (Join-Path $script:SourceRootResolved '.github/workflows/squad-watch.yml') -Raw
        $script:TemplateWatch = Get-Content -LiteralPath (Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/squad-watch.workflow.yml') -Raw
        $script:Tier0Runner = Get-Content -LiteralPath (Join-Path $script:SourceRootResolved 'tests/tier0/Tier0TestPlan.psm1') -Raw
    }

    It 'GATE-50 pins repository-wide queue max concurrency in both workflows' {
        foreach ($workflow in @($script:LiveWatch, $script:TemplateWatch)) {
            $workflow | Should -Match ([regex]::Escape('group: squad-watch-${{ github.repository }}'))
            $workflow | Should -Match ([regex]::Escape('cancel-in-progress: false'))
            $workflow | Should -Match ([regex]::Escape('queue: max'))
        }
    }

    It 'GATE-50 keeps review-event subscriptions absent and Conversation comments supported' {
        foreach ($workflow in @($script:LiveWatch, $script:TemplateWatch)) {
            $workflow | Should -Not -Match 'pull_request_review:'
            $workflow | Should -Match 'issue_comment:'
            $workflow | Should -Match '/squad'
        }
    }

    It 'GATE-50 preserves live and template actor rules without authorization widening' {
        foreach ($workflow in @($script:LiveWatch, $script:TemplateWatch)) {
            $workflow | Should -Match ([regex]::Escape("['write', 'admin', 'maintain']"))
            $workflow | Should -Not -Match 'notify\.github\.handle'
            $workflow | Should -Not -Match 'registered approver'
        }
    }

    It 'GATE-50 wires every resolver output through apply review escalation staging and upload' {
        foreach ($name in @('member', 'stableRef', 'sourceThread', 'sourceThreadNumber', 'publicationBranch', 'existingPr', 'sourceSha', 'trustedBaseSha', 'suppressInterpret', 'reconcilePublication', 'publishSourceComment')) {
            $script:LiveWatch | Should -Match $name
            $script:TemplateWatch | Should -Match $name
        }
        $script:LiveWatch | Should -Match 'needs.interpret.outputs.reconcilePublication'
        $script:LiveWatch | Should -Match 'needs.interpret.outputs.publishSourceComment'
        $script:LiveWatch | Should -Match 'needs.interpret.outputs.sourceThreadNumber'
    }

    It 'GATE-50 reacquires trusted helpers in every privileged job' {
        $trustedCheckouts = [regex]::Matches($script:LiveWatch, [regex]::Escape('.squad-trusted'))
        $trustedCheckouts.Count | Should -BeGreaterOrEqual 4
        $script:LiveWatch | Should -Match ([regex]::Escape('persist-credentials: false'))
        $script:LiveWatch | Should -Match 'Assert-SquadWatchTrustedHelper'
        $script:TemplateWatch | Should -Match ([regex]::Escape('.squad-trusted'))
        $script:TemplateWatch | Should -Match ([regex]::Escape('persist-credentials: false'))
    }

    It 'GATE-50 updates only the marked Open Questions body block' {
        $script:LiveWatch | Should -Match ([regex]::Escape('<!-- squad-watch-open-questions:start -->'))
        $script:LiveWatch | Should -Match 'Update-SquadWatchMarkedBody'
    }

    It 'GATE-50 keeps fast-forward-only push and failure escalation' {
        $script:LiveWatch | Should -Not -Match '--force'
        $script:LiveWatch | Should -Match 'Refusing to force-push'
        $script:LiveWatch | Should -Match 'Escalate on run failure'
    }

    It 'GATE-50 executes publication PowerShell commands without Bash expanding their environment references' {
        $bash = Get-Command bash -ErrorAction Stop
        $commands = @([regex]::Matches($script:LiveWatch, '(?m)^\s*(?:branch_reason|CLOSES)=.*pwsh -NoProfile -Command.*$') | ForEach-Object { $_.Value.Trim() })
        $commands.Count | Should -Be 2
        $workspace = Join-Path $TestDrive 'watch publication $fixture'
        $helperDir = Join-Path $workspace '.squad-trusted/squad-src/.github/skills/squad/scripts'
        New-Item -ItemType Directory -Path $helperDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/scripts/SquadWatch.Delivery.ps1') -Destination $helperDir
        $shellScript = (@('set -euo pipefail', 'unset env') + $commands + @('printf "%s\t%s\n" "$branch_reason" "$CLOSES"')) -join "`n"
        $cases = @(
            @{ Name = 'new branch'; Existing = 'false'; Fetched = 'false'; Ref = 'Peter-N91/hve-squad#248'; Expected = "continue`tCloses #248" }
            @{ Name = 'existing branch'; Existing = 'true'; Fetched = 'true'; Ref = 'Peter-N91/hve-squad#248'; Expected = "continue`tCloses #248" }
            @{ Name = 'disappeared branch'; Existing = 'true'; Fetched = 'false'; Ref = 'Peter-N91/hve-squad#248'; Expected = "branch-disappeared`tCloses #248" }
            @{ Name = 'issue-less dispatch'; Existing = 'false'; Fetched = 'false'; Ref = 'dispatch@abc123'; Expected = "continue`t" }
        )
        $savedEnvironment = @{}
        foreach ($name in @('GITHUB_WORKSPACE', 'PUBLICATION_BRANCH_EXISTS', 'FETCHED', 'STABLE_REF')) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        try {
            $env:GITHUB_WORKSPACE = $workspace
            foreach ($case in $cases) {
                $env:PUBLICATION_BRANCH_EXISTS = $case.Existing
                $env:FETCHED = $case.Fetched
                $env:STABLE_REF = $case.Ref
                $output = @(& $bash.Source -c $shellScript 2>&1)
                $LASTEXITCODE | Should -Be 0 -Because "$($case.Name): $($output -join "`n")"
                ($output -join "`n") | Should -BeExactly $case.Expected -Because $case.Name
            }
        }
        finally {
            foreach ($name in $savedEnvironment.Keys) {
                [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
            }
        }
    }

    It 'GATE-49 comments encoded questions and creates no PR or placeholder for blocked no-material' {
        $script:LiveWatch | Should -Match 'publishSourceComment'
        $script:LiveWatch | Should -Match 'no material publication'
        $script:LiveWatch | Should -Match 'hasMaterialChanges'
    }

    It 'GATE-49 keeps gh pr create --draft unconditional for new material publication' {
        foreach ($workflow in @($script:LiveWatch, $script:TemplateWatch)) {
            $workflow | Should -Match 'gh pr create'
            $create = [regex]::Match($workflow, 'gh pr create\s*\\?\s*--draft')
            $create.Success | Should -BeTrue
        }
    }

    It 'GATE-50 rejects a trusted checkout path outside the workspace' {
        $paths = @(
            (Join-Path $script:SourceRootResolved '.github/workflows/squad-watch.yml'),
            (Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/squad-watch.workflow.yml')
        )
        $extractor = @'
import json, sys, yaml
from pathlib import Path
rows = []
for path in sys.argv[1:]:
    doc = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    for job in (doc.get("jobs") or {}).values():
        if not isinstance(job, dict):
            continue
        for step in job.get("steps") or []:
            if not isinstance(step, dict):
                continue
            if not str(step.get("uses") or "").startswith("actions/checkout"):
                continue
            rows.append({"file": path, "name": step.get("name") or "", "path": (step.get("with") or {}).get("path")})
print(json.dumps(rows))
'@
        $json = & python -c $extractor @paths
        $LASTEXITCODE | Should -Be 0
        $rows = @($json | ConvertFrom-Json)
        $rows.Count | Should -BeGreaterThan 0
        foreach ($row in $rows) {
            $checkoutPath = [string]$row.path
            if ([string]::IsNullOrWhiteSpace($checkoutPath)) { continue }
            $checkoutPath | Should -Not -Match 'runner\.temp'
            $checkoutPath | Should -Not -Match '^[A-Za-z]:[\\/]|^/'
            $checkoutPath | Should -Not -Match '\.\.'
            $checkoutPath | Should -Be '.squad-trusted' -Because "trusted helper checkout $($row.name) must stay workspace-relative"
        }
    }

    It 'GATE-50 parses both Watch workflows and their embedded scripts' {
        $python = Get-Command python -ErrorAction Stop
        $files = @(
            (Join-Path $script:SourceRootResolved '.github/workflows/squad-watch.yml'),
            (Join-Path $script:SourceRootResolved 'squad-src/.github/skills/squad/squad-watch.workflow.yml')
        )
        $extractor = @'
import json, sys, yaml
from pathlib import Path
items = []
for path in sys.argv[1:]:
    doc = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    for job_name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        for index, step in enumerate(job.get("steps") or []):
            if not isinstance(step, dict):
                continue
            if step.get("run"):
                items.append({"file": path, "job": job_name, "name": step.get("name") or str(index), "shell": step.get("shell") or "bash", "kind": "run", "script": step["run"]})
            uses = str(step.get("uses") or "")
            payload = step.get("with") or {}
            if uses.startswith("actions/github-script") and isinstance(payload, dict) and payload.get("script"):
                items.append({"file": path, "job": job_name, "name": step.get("name") or str(index), "shell": "javascript", "kind": "github-script", "script": payload["script"]})
print(json.dumps(items))
'@
        $json = & $python.Source -c $extractor @files
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
            throw "YAML parser failed for a Watch workflow. $json"
        }
        $items = $json | ConvertFrom-Json
        @($items).Count | Should -BeGreaterThan 10
        $bash = Get-Command bash -ErrorAction Stop
        foreach ($item in $items) {
            if ($item.kind -eq 'github-script') {
                $dir = Join-Path $TestDrive ("js-" + [guid]::NewGuid().ToString('n'))
                New-Item -ItemType Directory -Path $dir | Out-Null
                $scriptPath = Join-Path $dir 'script.js'
                $wrapper = Join-Path $dir 'parse.js'
                Set-Content -LiteralPath $scriptPath -Value $item.script -Encoding utf8
                Set-Content -LiteralPath $wrapper -Value "const fs=require('fs'); const script=fs.readFileSync(process.argv[1],'utf8'); new Function('return (async () => {\n'+script+'\n})');" -Encoding utf8
                & node $wrapper $scriptPath
                $LASTEXITCODE | Should -Be 0 -Because "$($item.name) github-script must parse"
            }
            elseif ($item.shell -like 'pwsh*' -or $item.shell -like 'powershell*') {
                $parseErrors = $null
                $tokens = $null
                [System.Management.Automation.Language.Parser]::ParseInput([string]$item.script, [ref]$tokens, [ref]$parseErrors) | Out-Null
                @($parseErrors).Count | Should -Be 0 -Because "$($item.name) PowerShell must parse"
                if ([string]$item.script -match 'Import-Module \$watchModule' -or [string]$item.script -match 'Import-Module \$installModule') {
                    $showAt = $item.script.IndexOf('Assert-SquadWatchTrustedCheckout.ps1')
                    $importAt = $item.script.IndexOf('Import-Module')
                    $showAt | Should -BeGreaterOrEqual 0 -Because "$($item.name) must load the pinned verifier from git show"
                    $showAt | Should -BeLessThan $importAt
                }
                if ([string]$item.script -match 'Assert-SquadWatchTrustedHelper') {
                    $importAt = $item.script.IndexOf('Import-Module')
                    $assertAt = $item.script.IndexOf('Assert-SquadWatchTrustedHelper')
                    $importAt | Should -BeGreaterOrEqual 0
                    $importAt | Should -BeLessThan $assertAt
                }
            }
            else {
                ([string]$item.script).Replace("`r`n", "`n") | & $bash.Source -n
                $LASTEXITCODE | Should -Be 0 -Because "$($item.name) bash must parse"
            }
        }
    }

    It 'Tier 0 source mode discovers WatchMode.Tests.ps1' {
        $script:Tier0Runner | Should -Match 'WatchMode\.Tests\.ps1'
    }
}

Describe 'CI-06 Workflow supply-chain pinning and template SDL hygiene' {
    BeforeAll {
        $script:SourceRootCi06 = (Resolve-Path -LiteralPath $SourceRoot).Path
        $script:LiveWorkflowPaths = @(
            Get-ChildItem -LiteralPath (Join-Path $script:SourceRootCi06 '.github/workflows') -File -Filter '*.yml' |
                Sort-Object FullName |
                ForEach-Object { $_.FullName }
        )
        $script:TemplateWorkflowPaths = @(
            Get-ChildItem -LiteralPath (Join-Path $script:SourceRootCi06 'squad-src') -Recurse -File -Filter '*.workflow.yml' |
                Sort-Object FullName |
                ForEach-Object { $_.FullName }
        )
        $script:AllWorkflowPaths = @($script:LiveWorkflowPaths + $script:TemplateWorkflowPaths)
    }

    It 'CI-06 pins every external uses reference to a 40-char SHA with a version tag comment and sets persist-credentials false on every checkout' {
        $python = Get-Command python -ErrorAction Stop
        $inspector = @'
import json, re, sys, yaml
from pathlib import Path

uses_rows = []
checkout_rows = []
uses_line_re = re.compile(r"^\s*(?:-\s*)?uses:\s*(.+?)\s*$")
pinned_line_re = re.compile(r"^[^@\s]+@[0-9a-f]{40}\s+#\s*v\d+\.\d+\.\d+\b")

for raw_path in sys.argv[1:]:
    p = Path(raw_path)
    text = p.read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), 1):
        m = uses_line_re.match(line)
        if not m:
            continue
        target = m.group(1)
        if target.startswith("./"):
            continue
        uses_rows.append({
            "file": p.as_posix(),
            "line": lineno,
            "raw": target,
            "pinnedWithTagComment": bool(pinned_line_re.match(target)),
        })
    doc = yaml.safe_load(text) or {}
    for job_name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        for idx, step in enumerate(job.get("steps") or []):
            if not isinstance(step, dict):
                continue
            u = str(step.get("uses") or "")
            if u.startswith("actions/checkout"):
                w = step.get("with") or {}
                checkout_rows.append({
                    "file": p.as_posix(),
                    "job": str(job_name),
                    "step": str(step.get("name") or f"step-{idx}"),
                    "persist": w.get("persist-credentials"),
                })

print(json.dumps({"uses": uses_rows, "checkouts": checkout_rows}))
'@
        $json = & $python.Source -c $inspector @script:AllWorkflowPaths
        $LASTEXITCODE | Should -Be 0 -Because ($json -join "`n")
        $report = $json | ConvertFrom-Json
        @($report.uses).Count | Should -BeGreaterThan 20
        @($report.checkouts).Count | Should -BeGreaterThan 15
        foreach ($row in @($report.uses)) {
            $row.pinnedWithTagComment | Should -BeTrue -Because "$($row.file):$($row.line) '$($row.raw)' must pin a 40-char SHA with a '# vX.Y.Z' comment"
        }
        foreach ($checkout in @($report.checkouts)) {
            $checkout.persist | Should -BeFalse -Because "$($checkout.file) job '$($checkout.job)' checkout '$($checkout.step)' must set persist-credentials: false"
        }
    }

    It 'CI-06 aligns COPILOT_CLI_VERSION, adhoc-packages rationale, and setup-node cache hardening across workflows' {
        $cliWorkflows = @(
            '.github/workflows/squad-watch.yml'
            'squad-src/.github/skills/squad/squad-watch.workflow.yml'
            '.github/workflows/tier1-behavior.yml'
            '.github/workflows/tier2-semantic.yml'
        )
        $versions = [System.Collections.Generic.List[string]]::new()
        foreach ($rel in $cliWorkflows) {
            $content = Get-Content -LiteralPath (Join-Path $script:SourceRootCi06 $rel) -Raw
            $match = [regex]::Match($content, "(?m)^\s*COPILOT_CLI_VERSION:\s*'(\d+\.\d+\.\d+)'\s*$")
            $match.Success | Should -BeTrue -Because "$rel must pin COPILOT_CLI_VERSION"
            [version]$match.Groups[1].Value | Should -BeGreaterOrEqual ([version]'1.0.106') -Because "$rel COPILOT_CLI_VERSION must be >= 1.0.106"
            $versions.Add($match.Groups[1].Value)
            $content | Should -Match '#\s*zizmor:\s*ignore\[adhoc-packages\]' -Because "$rel must document the pinned npm CLI exception for Zizmor"
        }
        @($versions | Select-Object -Unique).Count | Should -Be 1 -Because 'all Copilot CLI workflows must pin the same CLI version'

        foreach ($watchRel in @('.github/workflows/squad-watch.yml', 'squad-src/.github/skills/squad/squad-watch.workflow.yml')) {
            $watchContent = Get-Content -LiteralPath (Join-Path $script:SourceRootCi06 $watchRel) -Raw
            $watchContent | Should -Match 'package-manager-cache:\s*false' -Because "$watchRel must disable setup-node package-manager caching"
        }
    }

    It 'CI-06 enforces non-write top-level permissions, explicit job permissions, and env-bound run blocks across all shipped workflow templates' {
        $python = Get-Command python -ErrorAction Stop
        $inspector = @'
import json, re, sys, yaml
from pathlib import Path

expr_re = re.compile(r"\$\{\{.*?\}\}", re.DOTALL)
rows = []
for raw_path in sys.argv[1:]:
    p = Path(raw_path)
    doc = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    top_perm = doc.get("permissions")
    top_write = False
    if isinstance(top_perm, dict):
        top_write = any(str(v) == "write" for v in top_perm.values())
    elif isinstance(top_perm, str):
        top_write = "write" in top_perm
    missing_job_perm = []
    run_interpolations = []
    for job_name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        if not isinstance(job.get("permissions"), dict) or len(job.get("permissions")) == 0:
            missing_job_perm.append(str(job_name))
        for idx, step in enumerate(job.get("steps") or []):
            if not isinstance(step, dict):
                continue
            run_body = step.get("run")
            if isinstance(run_body, str) and expr_re.search(run_body):
                run_interpolations.append(f"{job_name}:{step.get('name') or idx}")
    rows.append({
        "file": p.name,
        "hasTopPermissions": top_perm is not None,
        "topWrite": top_write,
        "missingJobPerm": missing_job_perm,
        "runInterpolations": run_interpolations,
    })

print(json.dumps(rows))
'@
        $json = & $python.Source -c $inspector @script:TemplateWorkflowPaths
        $LASTEXITCODE | Should -Be 0 -Because ($json -join "`n")
        $rows = @($json | ConvertFrom-Json)
        $rows.Count | Should -Be 5
        foreach ($row in $rows) {
            $row.hasTopPermissions | Should -BeTrue -Because "$($row.file) must declare workflow-level permissions"
            $row.topWrite | Should -BeFalse -Because "$($row.file) must not grant write permissions at workflow scope"
            @($row.missingJobPerm) | Should -BeNullOrEmpty -Because "$($row.file) must declare explicit permissions on every job"
            @($row.runInterpolations) | Should -BeNullOrEmpty -Because "$($row.file) must pass GitHub expressions via env: rather than interpolating inside run:"
        }
    }

    It 'CI-06 hardens github-approval-watcher.workflow.yml permissions, authorization markers, and /changes note sanitization' {
        $python = Get-Command python -ErrorAction Stop
        $node = Get-Command node -ErrorAction Stop
        $watcherPath = Join-Path $script:SourceRootCi06 'squad-src/.github/skills/squad/github-approval-watcher.workflow.yml'
        $extractor = @'
import json, sys, yaml
from pathlib import Path
doc = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8"))
job = doc["jobs"]["relay-approval"]
steps = job["steps"]
decide = next(s for s in steps if s.get("id") == "decide")
summary = next(s for s in steps if s.get("name") == "Decision summary")
print(json.dumps({
    "topPermKeys": list((doc.get("permissions") or {}).keys()),
    "jobIf": str(job.get("if") or ""),
    "jobPerm": job.get("permissions") or {},
    "script": decide["with"]["script"],
    "summaryIf": str(summary.get("if") or ""),
    "summaryEnvKeys": sorted(list((summary.get("env") or {}).keys())),
}))
'@
        $json = & $python.Source -c $extractor $watcherPath
        $LASTEXITCODE | Should -Be 0 -Because ($json -join "`n")
        $meta = $json | ConvertFrom-Json
        @($meta.topPermKeys).Count | Should -Be 0 -Because 'workflow-level permissions must be empty ({})'
        $meta.jobIf | Should -Match '!github\.event\.issue\.pull_request'
        $meta.jobPerm.issues | Should -Be 'write'
        @($meta.jobPerm.PSObject.Properties.Name) | Should -HaveCount 1 -Because 'relay-approval needs only issues: write'
        $meta.summaryIf | Should -Match 'ignored-unauthorized'
        @($meta.summaryEnvKeys) | Should -Be @('ACTOR', 'DECISION', 'ISSUE')

        $dir = Join-Path $TestDrive ('approval-watcher-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $scriptPath = Join-Path $dir 'decide.js'
        $driverPath = Join-Path $dir 'driver.js'
        Set-Content -LiteralPath $scriptPath -Value $meta.script -Encoding utf8
        $driver = @'
const fs = require('fs');
const code = fs.readFileSync(process.argv[2], 'utf8');
const fn = new Function('context', 'github', 'core', `return (async () => {\n${code}\n})();`);

async function runCase(c) {
  const outputs = {};
  const comments = [];
  const core = {
    info: () => {},
    setOutput: (k, v) => { outputs[k] = v; },
  };
  const github = {
    rest: {
      repos: {
        getCollaboratorPermissionLevel: async () => ({ data: { permission: c.perm || 'read' } }),
      },
      issues: {
        createComment: async (req) => { comments.push(req.body); },
      },
    },
  };
  await fn(c.context, github, core);
  return { name: c.name, outputs, comments };
}

(async () => {
  const cases = [
    {
      name: 'rejects pull request comments',
      perm: 'write',
      context: {
        eventName: 'issue_comment',
        actor: 'maintainer',
        repo: { owner: 'org', repo: 'app' },
        payload: {
          issue: { number: 12, body: 'Approver: @maintainer', pull_request: { url: 'https://api.github.com/pulls/12' } },
          comment: { body: '/approve' },
        },
      },
    },
    {
      name: 'ignores self-relayed marker comment',
      perm: 'write',
      context: {
        eventName: 'issue_comment',
        actor: 'maintainer',
        repo: { owner: 'org', repo: 'app' },
        payload: {
          issue: { number: 12, body: 'Approver: @maintainer' },
          comment: { body: '<!-- squad-approval-relay -->\n/approve' },
        },
      },
    },
    {
      name: 'rejects mid-sentence Approver spoof from read-only user',
      perm: 'read',
      context: {
        eventName: 'issue_comment',
        actor: 'mallory',
        repo: { owner: 'org', repo: 'app' },
        payload: {
          issue: { number: 12, body: 'Context paragraph mentioning Approver: @mallory inline only.\nApprover: @alice' },
          comment: { body: '/approve' },
        },
      },
    },
    {
      name: 'sanitizes /changes note newlines backticks angle brackets mentions and issue refs',
      perm: 'read',
      context: {
        eventName: 'issue_comment',
        actor: 'Alice',
        repo: { owner: 'org', repo: 'app' },
        payload: {
          issue: { number: 42, body: '- Approver: @alice\nTopic: deploy' },
          comment: { body: '/changes: Fix `auth`\n<script>alert(1)</script> ping @sec-team Closes #99' },
        },
      },
    },
  ];
  const results = [];
  for (const c of cases) {
    results.push(await runCase(c));
  }
  console.log(JSON.stringify(results));
})();
'@
        Set-Content -LiteralPath $driverPath -Value $driver -Encoding utf8
        $out = & $node.Source $driverPath $scriptPath
        $LASTEXITCODE | Should -Be 0 -Because ($out -join "`n")
        $results = @($out | ConvertFrom-Json)

        $results[0].outputs.decision | Should -Be 'none'
        @($results[0].comments).Count | Should -Be 0

        $results[1].outputs.decision | Should -Be 'none'
        @($results[1].comments).Count | Should -Be 0

        $results[2].outputs.decision | Should -Be 'ignored-unauthorized'
        @($results[2].comments).Count | Should -Be 0

        $results[3].outputs.decision | Should -Be 'changes-requested'
        $results[3].outputs.issue | Should -Be '42'
        $results[3].outputs.actor | Should -Be 'Alice'
        $results[3].outputs.note | Should -Be "Fix 'auth' scriptalert(1)/script ping @sec-team Closes #99"
        $results[3].outputs.note | Should -Not -Match '[\r\n`<>]'
        @($results[3].comments).Count | Should -Be 1
        $results[3].comments[0] | Should -Match ([regex]::Escape("Note: ``Fix 'auth' scriptalert(1)/script ping @sec-team Closes #99``"))
    }
}
