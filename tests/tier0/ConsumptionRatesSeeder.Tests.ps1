#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Behavioral coverage for the deterministic rate seeder, squad skill
# scripts/Initialize-SquadConsumptionRates.ps1. Runs the script as a child process
# against TestDrive roots, because it calls `exit` and would otherwise end the Pester
# run. Invokes no model.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    $skillRoot = Join-Path $PackageRoot '.agents/skills/squad'
    $script:Seeder = Join-Path $skillRoot 'scripts/Initialize-SquadConsumptionRates.ps1'
    $script:TemplatePath = Join-Path $skillRoot 'references/consumption-rates-template.md'

    $templateText = (Get-Content -LiteralPath $script:TemplatePath -Raw) -replace "`r`n", "`n"
    $script:SeedBlock = ([regex]::Match($templateText, '(?ms)^````markdown\n(?<body>.*?)\n````[ \t]*$')).Groups['body'].Value.TrimEnd("`n") + "`n"
    $script:ObservedOn = ([regex]::Match($script:SeedBlock, '(?m)^\*[ \t]+Observed-on:[ \t]*(\d{4}-\d{2}-\d{2})')).Groups[1].Value
    $script:Revision = ([regex]::Match($script:SeedBlock, '(?m)^estimator_revision:\s*(\d+)')).Groups[1].Value
    $script:CurrentBasis = "$($script:ObservedOn)|$($script:Revision)"

    function Invoke-Seeder {
        <#
        .SYNOPSIS
            Runs the seeder in a child pwsh and returns its exit code and combined output.
        #>
        param([Parameter(Mandatory)][string[]]$Arguments)
        $output = & pwsh -NoProfile -File $script:Seeder @Arguments *>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    function Read-Lf {
        param([Parameter(Mandatory)][string]$Path)
        (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
    }

    function New-SeededRoot {
        $root = Join-Path $TestDrive "root-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root)
        if ($result.ExitCode -ne 0) { throw "Seeding failed: $($result.Output)" }
        $root
    }

    function Set-RatesText {
        param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Text)
        [System.IO.File]::WriteAllText((Join-Path $Root 'consumption-rates.md'), $Text, [System.Text.UTF8Encoding]::new($false))
    }
}

Describe 'Initialize-SquadConsumptionRates.ps1 seeds from the template' {
    It 'the script and the template ship in the squad skill' {
        Test-Path -LiteralPath $script:Seeder -PathType Leaf | Should -BeTrue
        $script:SeedBlock | Should -Match '(?m)^## Per-model token rates'
    }

    It 'creates the squad root and writes the template seed block verbatim' {
        $root = Join-Path $TestDrive 'fresh/squad'
        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        Read-Lf (Join-Path $root 'consumption-rates.md') | Should -BeExactly $script:SeedBlock
    }

    It '-Check passes on a freshly seeded root and writes nothing' {
        $root = New-SeededRoot
        $path = Join-Path $root 'consumption-rates.md'
        $before = (Get-FileHash -LiteralPath $path).Hash
        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
    }

    It 'leaves an existing valid file untouched unless -Reseed is given' {
        $root = New-SeededRoot
        $path = Join-Path $root 'consumption-rates.md'
        # A drifted rate on a known model only warns, so the file stays valid and must not be rewritten.
        $edited = (Read-Lf $path) -replace '(\| Claude Haiku 4\.5\s+\| `claude-haiku-4\.5`\s+\| fast\s+\| )1\.00', '${1}1.10'
        $edited | Should -Not -BeExactly (Read-Lf $path)
        Set-RatesText -Root $root -Text $edited

        $unchanged = Invoke-Seeder -Arguments @('-SquadRoot', $root)
        $unchanged.ExitCode | Should -Be 0 -Because $unchanged.Output
        Read-Lf $path | Should -BeExactly $edited

        $reseeded = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Reseed')
        $reseeded.ExitCode | Should -Be 0 -Because $reseeded.Output
        Read-Lf $path | Should -BeExactly $script:SeedBlock
    }

    It 'writes only under the intended root when -SquadRoot is relative after Set-Location' {
        $work = Join-Path $TestDrive 'rel-work'
        $null = New-Item -ItemType Directory -Path $work -Force
        $relative = "rel-root-$([guid]::NewGuid().ToString('N').Substring(0, 8))/squad"
        $processDir = [Environment]::CurrentDirectory
        Push-Location -LiteralPath $work
        try { & $script:Seeder -SquadRoot $relative *> $null; $code = $LASTEXITCODE }
        finally { Pop-Location }

        $code | Should -Be 0
        Test-Path -LiteralPath (Join-Path $work "$relative/consumption-rates.md") -PathType Leaf | Should -BeTrue
        if ($processDir -ne $work) {
            Test-Path -LiteralPath (Join-Path $processDir $relative.Split('/')[0]) | Should -BeFalse
        }
    }

    It 'refuses -Check combined with -Reseed' {
        $root = New-SeededRoot
        (Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check', '-Reseed')).ExitCode | Should -Not -Be 0
    }

    It 'exits non-zero when the template cannot be read' {
        $root = Join-Path $TestDrive 'no-template'
        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-TemplatePath', (Join-Path $TestDrive 'missing.md'))
        $result.ExitCode | Should -Not -Be 0
        Test-Path -LiteralPath (Join-Path $root 'consumption-rates.md') | Should -BeFalse
    }
}

Describe 'Initialize-SquadConsumptionRates.ps1 -Check rejects a model-authored rate table' {
    It '-Check fails when consumption-rates.md is missing' {
        $result = Invoke-Seeder -Arguments @('-SquadRoot', (Join-Path $TestDrive 'empty-root'), '-Check')
        $result.ExitCode | Should -Be 1
    }

    It 'fails the observed gpt-4o table: invented rows with no Cache write column' {
        $root = New-SeededRoot
        $inventedTable = @'
| Model (as routed) | Input | Cached | Output |
| ----------------- | ----- | ------ | ------ |
| gpt-4o            | 2.50  | 1.25   | 10.00  |
| claude-3.5-sonnet | 3.00  | 0.30   | 15.00  |
| o1                | 15.00 | 7.50   | 60.00  |
| gemini-2.0-flash  | 0.10  | 0.025  | 0.40   |
'@
        $text = Read-Lf (Join-Path $root 'consumption-rates.md')
        $perModel = [regex]::Match($text, '(?ms)^\| Model \(as routed\).*?(?=\n\n## Tier fallback)').Value
        $perModel | Should -Not -BeNullOrEmpty
        Set-RatesText -Root $root -Text $text.Replace($perModel, $inventedTable.TrimEnd())

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'No per-model rate table'
    }

    It 'fails the E2 shape: a well-formed table of invented models with no template rows' {
        $root = New-SeededRoot
        $text = Read-Lf (Join-Path $root 'consumption-rates.md')
        $e2Table = @'
| Model (as routed) | Model ID | Tier | Input | Cached | Cache write | Output |
| ----------------- | -------- | ---- | ----- | ------ | ----------- | ------ |
| GPT-4o | `gpt-4o` | default | 2.50 | 1.25 | 0 | 10.00 |
| o1 | `o1` | extended | 15.00 | 7.50 | 0 | 60.00 |
'@
        $perModel = [regex]::Match($text, '(?ms)^\| Model \(as routed\).*?(?=\n\n## Tier fallback)').Value
        Set-RatesText -Root $root -Text $text.Replace($perModel, $e2Table.TrimEnd())

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'lacks \d+ of \d+ template row'
    }

    It 'fails when any single template row is missing' {
        $root = New-SeededRoot
        $text = Read-Lf (Join-Path $root 'consumption-rates.md')
        Set-RatesText -Root $root -Text ($text -replace '(?m)^\| Claude Haiku 4\.5 .*\n', '')

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match "e\.g\. 'Claude Haiku 4\.5'"
    }

    It 'passes with a warning, and keeps across a reseed, a well-formed operator-added model row' {
        $root = New-SeededRoot
        $path = Join-Path $root 'consumption-rates.md'
        $row = '| Claude Sonnet 6 | `claude-sonnet-6` | default | 3.00 | 0.30 | 3.75 | 15.00 | none (flat rate) | n/a | n/a | n/a | n/a | operator-added |'
        Set-RatesText -Root $root -Text ((Read-Lf $path) -replace '(?m)^\| \(additional\)', ($row + "`n| (additional)"))

        $check = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $check.Output | Should -Match "WARN: .*'Claude Sonnet 6'.*operator-added"

        $reseed = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Reseed')
        $reseed.ExitCode | Should -Be 0 -Because $reseed.Output
        $reseeded = Read-Lf $path
        $reseeded | Should -Match ([regex]::Escape($row))
        $reseeded.Replace($row + "`n", '') | Should -BeExactly $script:SeedBlock
    }

    It 'refuses to rewrite a shape-failed file that holds a malformed operator row, leaving it byte-identical and naming the row' {
        $root = New-SeededRoot
        $path = Join-Path $root 'consumption-rates.md'
        $good = '| Claude Sonnet 6 | `claude-sonnet-6` | default | 3.00 | 0.30 | 3.75 | 15.00 | none (flat rate) | n/a | n/a | n/a | n/a | operator-added |'
        $bad = '| Mystery | mystery | bogus | x | 0.30 | 3.75 | 15.00 | none (flat rate) | n/a | n/a | n/a | n/a | bad |'
        $text = (Read-Lf $path) -replace '(?m)^\| \(additional\)', ($good + "`n" + $bad + "`n| (additional)")
        Set-RatesText -Root $root -Text ([regex]::Replace($text, '(?ms)^## Dispatch-size estimator.*?(?=\n## Calibration)', ''))
        $before = (Get-FileHash -LiteralPath $path).Hash

        $check = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')
        $check.ExitCode | Should -Be 1 -Because $check.Output
        $check.Output | Should -Match "'Mystery' is not in the template and is malformed"

        foreach ($extra in @(@(), @('-Reseed'))) {
            $refused = Invoke-Seeder -Arguments (@('-SquadRoot', $root) + $extra)
            $refused.ExitCode | Should -Be 1 -Because $refused.Output
            $refused.Output | Should -Match "refusing to rewrite .*delete 1 malformed operator-added row\(s\): 'Mystery'"
            $refused.Output | Should -Match 'Fix each row .* or delete it yourself and re-run, or re-run with -DropMalformedRows'
            (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
        }
    }

    It 'with -DropMalformedRows the rewrite keeps the good operator row, drops the malformed one, and says so' {
        $root = New-SeededRoot
        $path = Join-Path $root 'consumption-rates.md'
        $good = '| Claude Sonnet 6 | `claude-sonnet-6` | default | 3.00 | 0.30 | 3.75 | 15.00 | none (flat rate) | n/a | n/a | n/a | n/a | operator-added |'
        $bad = '| Mystery | mystery | bogus | x | 0.30 | 3.75 | 15.00 | none (flat rate) | n/a | n/a | n/a | n/a | bad |'
        $text = (Read-Lf $path) -replace '(?m)^\| \(additional\)', ($good + "`n" + $bad + "`n| (additional)")
        Set-RatesText -Root $root -Text ([regex]::Replace($text, '(?ms)^## Dispatch-size estimator.*?(?=\n## Calibration)', ''))

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-DropMalformedRows')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match "Dropped malformed operator row 'Mystery'"
        $reseeded = Read-Lf $path
        $reseeded | Should -Match ([regex]::Escape($good))
        $reseeded | Should -Not -Match 'Mystery'
    }

    It 'repairs an E2-shaped file of well-formed invented rows, keeping them as operator rows, without -DropMalformedRows' {
        $root = New-SeededRoot
        $path = Join-Path $root 'consumption-rates.md'
        $text = Read-Lf $path
        $e2Table = @'
| Model (as routed) | Model ID | Tier | Input | Cached | Cache write | Output |
| ----------------- | -------- | ---- | ----- | ------ | ----------- | ------ |
| GPT-4o | `gpt-4o` | default | 2.50 | 1.25 | 0 | 10.00 |
'@
        $perModel = [regex]::Match($text, '(?ms)^\| Model \(as routed\).*?(?=\n\n## Tier fallback)').Value
        Set-RatesText -Root $root -Text $text.Replace($perModel, $e2Table.TrimEnd())

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')).ExitCode | Should -Be 0
    }

    It 'fails a tier-fallback-only file with no per-model table (the E3/E4 shape)' {
        $root = New-SeededRoot
        $text = Read-Lf (Join-Path $root 'consumption-rates.md')
        $tierOnly = [regex]::Replace($text, '(?ms)^\| Model \(as routed\).*?(?=\n\n## Tier fallback)', '')
        Set-RatesText -Root $root -Text $tierOnly

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'No per-model rate table'
    }

    It 'fails a per-model row with a non-numeric rate cell' {
        $root = New-SeededRoot
        $text = Read-Lf (Join-Path $root 'consumption-rates.md')
        Set-RatesText -Root $root -Text ($text -replace '(\| GPT-5\.4 nano\s+\| `gpt-5\.4-nano`\s+\| fast\s+\| )0\.20', '${1}cheap')

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match 'non-numeric'
    }

    It 'fails when the <Name> is removed' -ForEach @(
        @{ Name = 'tier-fallback table'; Pattern = '(?ms)^## Tier fallback rates.*?(?=\n## Dispatch-size estimator)'; Expected = 'No tier-fallback table' }
        @{ Name = 'dispatch-size estimator'; Pattern = '(?ms)^## Dispatch-size estimator.*?(?=\n## Calibration)'; Expected = 'No dispatch-size estimator' }
        @{ Name = 'calibration block'; Pattern = '(?ms)^## Calibration.*\z'; Expected = 'No calibration block' }
    ) {
        $root = New-SeededRoot
        $text = Read-Lf (Join-Path $root 'consumption-rates.md')
        $stripped = [regex]::Replace($text, $Pattern, '')
        $stripped | Should -Not -BeExactly $text
        Set-RatesText -Root $root -Text $stripped

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')
        $result.ExitCode | Should -Be 1 -Because $result.Output
        $result.Output | Should -Match $Expected
    }

    It 'reseeds a shape-failed file on the default (non -Check) run' {
        $root = New-SeededRoot
        Set-RatesText -Root $root -Text "# Consumption Rates`n`n| Model | Input |`n| --- | --- |`n| gpt-4o | 2.50 |`n"
        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        Read-Lf (Join-Path $root 'consumption-rates.md') | Should -BeExactly $script:SeedBlock
    }
}

Describe 'Initialize-SquadConsumptionRates.ps1 preserves calibration across a reseed' {
    BeforeAll {
        function Set-Calibration {
            param([string]$Root, [string]$Factor, [int]$Observations, [string]$Basis)
            $path = Join-Path $Root 'consumption-rates.md'
            $text = Read-Lf $path
            $block = "calibration_factor: $Factor`nlast_reconciled: 2026-10-01`nobservations: $Observations`nestimator_revision: $script:Revision`ncalibration_basis: `"$Basis`""
            $updated = [regex]::Replace($text, '(?ms)(^```yaml\n).*?(\n```[ \t]*$)', ('${1}' + $block + '${2}'))
            Set-RatesText -Root $Root -Text $updated
            $block
        }
    }

    It 'carries a reconciled calibration block forward on -Reseed and restores everything else from the template' {
        $root = New-SeededRoot
        $block = Set-Calibration -Root $root -Factor '1.37' -Observations 4 -Basis $script:CurrentBasis

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Reseed')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $text = Read-Lf (Join-Path $root 'consumption-rates.md')
        $text | Should -Match ([regex]::Escape($block))
        $text.Replace($block, '') | Should -BeExactly ($script:SeedBlock -replace '(?ms)(^```yaml\n).*?(\n```[ \t]*$)', '${1}${2}')
    }

    It 'carries the calibration block into a file reseeded because its shape failed' {
        $root = New-SeededRoot
        $block = Set-Calibration -Root $root -Factor '2.05' -Observations 2 -Basis $script:CurrentBasis
        $text = Read-Lf (Join-Path $root 'consumption-rates.md')
        Set-RatesText -Root $root -Text ([regex]::Replace($text, '(?ms)^## Dispatch-size estimator.*?(?=\n## Calibration)', ''))

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $reseeded = Read-Lf (Join-Path $root 'consumption-rates.md')
        $reseeded | Should -Match ([regex]::Escape($block))
        $reseeded | Should -Match '(?m)^## Dispatch-size estimator'
    }

    It 'repairs a calibration block whose observations is not an integer instead of throwing' {
        $root = New-SeededRoot
        $path = Join-Path $root 'consumption-rates.md'
        Set-RatesText -Root $root -Text ((Read-Lf $path) -replace '(?m)^observations:.*$', 'observations: two')
        (Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Check')).ExitCode | Should -Be 1

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'non-numeric'
        Read-Lf $path | Should -BeExactly $script:SeedBlock
    }

    It 'resets calibration observed against a different basis, as the template requires' {
        $root = New-SeededRoot
        Set-Calibration -Root $root -Factor '3.00' -Observations 5 -Basis '2025-01-01|1' | Out-Null

        $result = Invoke-Seeder -Arguments @('-SquadRoot', $root, '-Reseed')
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'Calibration reset'
        Read-Lf (Join-Path $root 'consumption-rates.md') | Should -BeExactly $script:SeedBlock
    }
}
