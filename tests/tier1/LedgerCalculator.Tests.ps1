#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# AI cost: none; local calculator checks only, despite the Tier 1 directory.

# Offline, self-contained Pester coverage for the D6b routing-performance remedy's
# deterministic ledger calculator (squad-src/.github/skills/squad/scripts/Measure-SquadLedger.ps1).
# Like ModelRouting.Tests.ps1, this reads only shipped references/scripts and static
# fixtures under tests/fixtures/scribe-benchmark/ -- no live squad root, no network call,
# no model dispatch -- so it runs unconditionally in the -SelfCheck container alongside
# Assertions.Tests.ps1 and ModelRouting.Tests.ps1.
#
# See .copilot-tracking/squad/members/routing-performance/changes/2026-09-28-d6b-ledger-tool.md
# for this file's contract.

BeforeDiscovery {
    $script:LedgerScript = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'squad-src', '.github', 'skills', 'squad', 'scripts', 'Measure-SquadLedger.ps1'
    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'fixtures', 'scribe-benchmark'
}

BeforeAll {
    $script:LedgerScript = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'squad-src', '.github', 'skills', 'squad', 'scripts', 'Measure-SquadLedger.ps1'
    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'fixtures', 'scribe-benchmark'

    function Invoke-Ledger {
        <#
        .SYNOPSIS
            Runs Measure-SquadLedger.ps1 as a genuine child process (it calls `exit` at
            top level, both with and without -Check, and would otherwise terminate this
            Pester run's own process) and returns its stdout and exit code.
        .DESCRIPTION
            When -ExpectedHistoryCounts is supplied, the call is built as a `-Command`
            string (rather than `-File` plus a positional args array) so the child
            pwsh process's own parser evaluates the `@{ ... }` hashtable literal --
            `-File` passes every trailing token as a literal string, which a hashtable
            parameter cannot bind. This is the F3 review-fix's post-write self-check
            shape: `-Check` combined with `-ExpectedHistoryCounts`.
        #>
        param(
            [Parameter(Mandatory)][string]$SquadRoot,
            [switch]$Check,
            [switch]$Write,
            [string]$Format,
            [hashtable]$ExpectedHistoryCounts,
            # U1 (Amendment 3 §2): -EmitBaseline / -BaselinePath / -ProtectedPath /
            # -AllowedWritePath and the four -Lookup* key-lookup parameters. All
            # optional and orthogonal to the params above and to each other.
            [string]$EmitBaseline,
            [string]$BaselinePath,
            [string[]]$ProtectedPath,
            [string[]]$AllowedWritePath,
            [string]$LookupRunId,
            [string]$LookupTopic,
            [string]$LookupStage,
            [string]$LookupSlot
        )
        if ($ExpectedHistoryCounts) {
            $countsLiteral = '@{' + (($ExpectedHistoryCounts.GetEnumerator() | ForEach-Object { "'$($_.Key)' = $($_.Value)" }) -join '; ') + '}'
            $cmdParts = [System.Collections.Generic.List[string]]::new()
            $cmdParts.Add("& '$script:LedgerScript'")
            $cmdParts.Add("-SquadRoot '$SquadRoot'")
            if ($Check) { $cmdParts.Add('-Check') }
            if ($Format) { $cmdParts.Add("-Format '$Format'") }
            $cmdParts.Add("-ExpectedHistoryCounts $countsLiteral")
            $command = $cmdParts -join ' '
            $output = & pwsh -NoProfile -Command $command 2>&1 | Out-String
        }
        else {
            $scriptArgs = @('-NoProfile', '-File', $script:LedgerScript, '-SquadRoot', $SquadRoot)
            if ($Check) { $scriptArgs += '-Check' }
            if ($Write) { $scriptArgs += '-Write' }
            if ($Format) { $scriptArgs += @('-Format', $Format) }
            if ($EmitBaseline) { $scriptArgs += @('-EmitBaseline', $EmitBaseline) }
            if ($BaselinePath) { $scriptArgs += @('-BaselinePath', $BaselinePath) }
            if ($ProtectedPath) { $scriptArgs += @('-ProtectedPath') + $ProtectedPath }
            if ($AllowedWritePath) { $scriptArgs += @('-AllowedWritePath') + $AllowedWritePath }
            if ($PSBoundParameters.ContainsKey('LookupRunId')) { $scriptArgs += @('-LookupRunId', $LookupRunId) }
            if ($PSBoundParameters.ContainsKey('LookupTopic')) { $scriptArgs += @('-LookupTopic', $LookupTopic) }
            if ($PSBoundParameters.ContainsKey('LookupStage')) { $scriptArgs += @('-LookupStage', $LookupStage) }
            if ($PSBoundParameters.ContainsKey('LookupSlot')) { $scriptArgs += @('-LookupSlot', $LookupSlot) }
            $output = & pwsh @scriptArgs 2>&1 | Out-String
        }
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    function Sync-LedgerStateLocal {
        <#
        .SYNOPSIS
            Re-derives a root's ledger totals via -Format json and rewrites that root's
            state.json currentRun.estCostUsd/estCreditsTotal to match, so a test that
            splices extra history blocks onto a copy of a fixture doesn't trip the C3
            ledger<->state.json divergence check for reasons unrelated to what the test
            itself is asserting.
        #>
        param(
            [Parameter(Mandatory)][string]$SquadRoot
        )
        $derived = (Invoke-Ledger -SquadRoot $SquadRoot -Format json).Output | ConvertFrom-Json
        $statePath = Join-Path $SquadRoot 'state.json'
        $raw = Get-Content -LiteralPath $statePath -Raw
        $invariant = [System.Globalization.CultureInfo]::InvariantCulture
        $costText = ([double]$derived.total.estCostUsd).ToString('F4', $invariant)
        $creditsText = ([double]$derived.total.estCredits).ToString('F2', $invariant)
        $raw = $raw -replace '"estCostUsd"\s*:\s*[0-9.]+', "`"estCostUsd`": $costText"
        $raw = $raw -replace '"estCreditsTotal"\s*:\s*[0-9.]+', "`"estCreditsTotal`": $creditsText"
        Set-Content -LiteralPath $statePath -Value $raw -NoNewline
    }

    function New-BaselineTestRootLocal {
        <#
        .SYNOPSIS
            U1 (Amendment 3 §2 item 1) baseline/protected-artifact tests: a fresh copy
            of the known-good scribe-benchmark 'applied' fixture under $TestDrive, so
            each test mutates its own private copy and the checked-in fixture is never
            touched -- and every baseline JSON these tests emit is written elsewhere
            under $TestDrive, never into the repo or a squad root.
        #>
        $dest = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $dest -Recurse
        $dest
    }
}

Describe 'Measure-SquadLedger reproduces the correct ledger on a fully-applied fixture' {
    BeforeAll {
        $script:AppliedRoot = Join-Path $script:FixtureRoot 'applied'
    }

    It 'the fixture exists (built from payload.md over the checked-in seed)' {
        Test-Path -LiteralPath $script:AppliedRoot -PathType Container | Should -BeTrue
    }

    It 'prints a Total Est. Cost (USD) of 0.3171 in markdown format' {
        $result = Invoke-Ledger -SquadRoot $script:AppliedRoot -Format markdown
        $result.Output | Should -Match '\*\*0\.3171\*\*'
    }

    It 'prints the derivation lines in the scribe-procedure.md Step 7 shape, including the per-file block enumeration' {
        $result = Invoke-Ledger -SquadRoot $script:AppliedRoot -Format markdown
        $result.Output | Should -Match 'Squad Researcher\.md — 1 block\(s\)'
        $result.Output | Should -Match 'Squad Scribe\.md — 1 block\(s\)'
        $result.Output | Should -Match 'total = 0\.3171'
    }

    It '-Check exits 0 against the fixture''s own checked-in consumption.md' {
        $result = Invoke-Ledger -SquadRoot $script:AppliedRoot -Check
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'PASS'
    }

    It 'emits well-formed json with -Format json' {
        $result = Invoke-Ledger -SquadRoot $script:AppliedRoot -Format json
        { $result.Output | ConvertFrom-Json } | Should -Not -Throw
        ($result.Output | ConvertFrom-Json).total.estCostUsd | Should -Be 0.3171
    }
}

Describe 'Measure-SquadLedger preserves legacy orchestration attribution identity' -Tag 'NF002' {
    It '-Check passes when consumption.md uses historical Agent `Coordinator+Scribe` for `orchestration`' {
        $root = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $ledgerPath = Join-Path $root 'consumption.md'
        $ledger = Get-Content -LiteralPath $ledgerPath -Raw
        $ledger = $ledger.Replace('| orchestration |        | Squad Scribe      |', '| orchestration |        | Coordinator+Scribe |')
        Set-Content -LiteralPath $ledgerPath -Value $ledger -NoNewline

        $check = Invoke-Ledger -SquadRoot $root -Check
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $check.Output | Should -Match 'PASS'

        $derived = Invoke-Ledger -SquadRoot $root -Format markdown
        $derived.Output | Should -Match '\|\s*orchestration\s*\|\s*\|\s*Coordinator\+Scribe\s*\|'
    }
}

Describe 'Measure-SquadLedger catches a mutated (wrong-arithmetic) ledger' {
    BeforeAll {
        $script:MutatedRoot = Join-Path $script:FixtureRoot 'mutated'
    }

    It '-Check exits 1 and reports the exact mismatch against the mutated consumption.md' {
        $result = Invoke-Ledger -SquadRoot $script:MutatedRoot -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'FAIL'
        $result.Output | Should -Match '0\.8854'
        $result.Output | Should -Match '0\.3171'
    }
}

Describe 'Measure-SquadLedger parses an old-shape (no LC-column) consumption-rates.md' {
    BeforeAll {
        $script:OldShapeRoot = Join-Path $script:FixtureRoot 'applied-old-shape-rates'
    }

    It 'the fixture carries the pre-LC-column 7-column rate table verbatim' {
        $ratesRaw = Get-Content -LiteralPath (Join-Path $script:OldShapeRoot 'consumption-rates.md') -Raw
        $ratesRaw | Should -Not -Match 'LC\b'
    }

    It 'still reproduces the same correct Total (0.3171) from the old-shape table' {
        $result = Invoke-Ledger -SquadRoot $script:OldShapeRoot -Format markdown
        $result.Output | Should -Match '\*\*0\.3171\*\*'
    }

    It '-Check exits 0 against the old-shape fixture too' {
        $result = Invoke-Ledger -SquadRoot $script:OldShapeRoot -Check
        $result.ExitCode | Should -Be 0
    }
}

Describe 'Measure-SquadLedger applies documented long-context rates' {
    BeforeAll {
        $script:LongContextRoot = Join-Path $TestDrive 'long-context'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $script:LongContextRoot -Recurse

        $templatePath = Join-Path (Split-Path -Parent $script:LedgerScript) '../references/consumption-rates-template.md'
        $template = (Get-Content -LiteralPath $templatePath -Raw) -replace "`r`n", "`n"
        $seed = [regex]::Match($template, '(?ms)^````markdown\n(?<body>.*?)\n````[ \t]*$').Groups['body'].Value
        Set-Content -LiteralPath (Join-Path $script:LongContextRoot 'consumption-rates.md') -Value $seed -NoNewline

        Remove-Item -Path (Join-Path $script:LongContextRoot 'history/*') -Force
        @'
# History: Squad Researcher

### Long-context fixture

#### Consumption

```json
{
  "model": "Claude Haiku 5.5",
  "model_source": "agent-pinned",
  "priced_as": "Claude Haiku 5.5",
  "model_tier": "fast",
  "internal_turns": 1,
  "input_tokens": 30000,
  "cached_tokens": 80000,
  "cache_write_tokens": 0,
  "output_tokens": 0,
  "basis": "estimated"
}
```
'@ | Set-Content -LiteralPath (Join-Path $script:LongContextRoot 'history/Squad Researcher.md') -NoNewline
    }

    It 'uses the >100K Haiku 5.5 tier when input plus cached tokens exceed the threshold' {
        $result = Invoke-Ledger -SquadRoot $script:LongContextRoot -Format json
        $result.ExitCode | Should -Be 0
        ($result.Output | ConvertFrom-Json).total.estCostUsd | Should -Be 0.019
    }
}

Describe 'Measure-SquadLedger is locale-independent' {
    It 'prints a "." decimal mark even when the calling session culture is fr-FR' {
        $root = Join-Path $script:FixtureRoot 'applied'
        $command = "[System.Globalization.CultureInfo]::CurrentCulture = 'fr-FR'; & '$($script:LedgerScript)' -SquadRoot '$root' -Format markdown"
        $output = & pwsh -NoProfile -Command $command 2>&1 | Out-String
        $output | Should -Match '\*\*0\.3171\*\*'
        $output | Should -Not -Match '0,3171'
    }

    It '-Check fails a ledger whose cost was written with a locale decimal comma (0,3171)' {
        $root = Join-Path $TestDrive 'locale-comma'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $ledgerPath = Join-Path $root 'consumption.md'
        (Get-Content -LiteralPath $ledgerPath -Raw).Replace('0.3171', '0,3171') | Set-Content -LiteralPath $ledgerPath -NoNewline
        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'Est\. Cost'
    }
}

Describe 'Measure-SquadLedger is read-only' {
    It 'writes nothing under the applied fixture root across a -Check run' {
        $root = Join-Path $script:FixtureRoot 'applied'
        $before = Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" } | Sort-Object
        Invoke-Ledger -SquadRoot $root -Check | Out-Null
        $after = Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" } | Sort-Object
        (Compare-Object $before $after) | Should -BeNullOrEmpty
    }
}

Describe 'Measure-SquadLedger -Write splices the derived fragment and run totals' {
    BeforeAll {
        function Initialize-WriteTestRootLocal {
            param([string]$Fixture = 'mutated')
            $dest = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath (Join-Path $script:FixtureRoot $Fixture) -Destination $dest -Recurse
            $dest
        }

        function Edit-StateTotalLocal {
            param([string]$Root, [string]$Cost, [string]$Cents)
            $statePath = Join-Path $Root 'state.json'
            $raw = Get-Content -LiteralPath $statePath -Raw
            $raw = $raw -replace '"estCostUsd"\s*:\s*[0-9.]+', "`"estCostUsd`": $Cost"
            $raw = $raw -replace '"estCreditsTotal"\s*:\s*[0-9.]+', "`"estCreditsTotal`": $Cents"
            Set-Content -LiteralPath $statePath -Value $raw -NoNewline
        }
    }

    It 'repairs a wrong-arithmetic ledger and stale state totals so a post-write -Check passes' {
        $root = Initialize-WriteTestRootLocal
        Edit-StateTotalLocal -Root $root -Cost '9.9999' -Cents '999.99'
        (Invoke-Ledger -SquadRoot $root -Check).ExitCode | Should -Be 1

        $result = Invoke-Ledger -SquadRoot $root -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $check = Invoke-Ledger -SquadRoot $root -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Scribe' = 1 }
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json
        $state.currentRun.estCostUsd | Should -Be 0.3171
        $state.currentRun.estCreditsTotal | Should -Be 31.71
    }

    It 'preserves frontmatter, H1, Basis note, comparison context and surrounding notes' {
        $root = Initialize-WriteTestRootLocal
        $ledgerPath = Join-Path $root 'consumption.md'
        $before = Get-Content -LiteralPath $ledgerPath -Raw
        (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0
        $after = Get-Content -LiteralPath $ledgerPath -Raw

        $headOf = { param($text) $text.Substring(0, $text.IndexOf('## Attribution')) }
        $tailOf = { param($text) $text.Substring($text.IndexOf('## Cost Comparison')) }
        (& $headOf $after) | Should -Be (& $headOf $before)
        (& $tailOf $after) | Should -Be ((& $tailOf $before).Replace('$0.8854 (~88.54 AI credits)', '$0.3171 (~31.71 AI credits)'))
        $after | Should -Match '(?m)^Squad Researcher\.md — 1 block\(s\) — identities: '
        $after | Should -Match '\*\*0\.3171\*\*'
    }

    It 'finalizes stale comparison figures and savings without losing baseline assumptions or notes' {
        $root = Initialize-WriteTestRootLocal -Fixture applied
        $path = Join-Path $root 'consumption.md'
        $line = 'This run consumed an estimated **$9.9999 (~999.99 AI credits)** across 1 role. Manually prompting Example Model across roughly 12 turns is estimated at **$20.00 (~2000 AI credits)**, a saving of about **50%**.'
        $text = [regex]::Replace((Get-Content -LiteralPath $path -Raw), '(?m)^This run consumed[^\r\n]*', { $line })
        $text += "`nOperator comparison note.`n`n## Operator Notes`n`nThis run consumed an estimated **`$7.0000 (~700.00 AI credits)** elsewhere.`n"
        Set-Content -LiteralPath $path -Value $text -NoNewline
        $before = (Get-FileHash -LiteralPath $path).Hash
        $check = Invoke-Ledger -SquadRoot $root -Check
        $check.ExitCode | Should -Be 1 -Because 'table/state reconciliation alone must not certify stale prose'
        $check.Output | Should -Match 'failure class: ledger-only'
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $before
        $write = Invoke-Ledger -SquadRoot $root -Write
        $write.ExitCode | Should -Be 0 -Because $write.Output
        $after = Get-Content -LiteralPath $path -Raw
        $after | Should -Match ([regex]::Escape('$0.3171 (~31.71 AI credits)'))
        $after | Should -Match ([regex]::Escape('Example Model across roughly 12 turns is estimated at **$20.00 (~2000 AI credits)**, a saving of about **98%**.'))
        $after | Should -Match 'Operator comparison note\.'
        $after | Should -Match ([regex]::Escape('**$7.0000 (~700.00 AI credits)** elsewhere.'))
        (Invoke-Ledger -SquadRoot $root -Check).ExitCode | Should -Be 0
    }

    It 'reports negative savings and zero baseline honestly while preserving the manual assumptions' {
        foreach ($baseline in @('0.10', '0.00')) {
            $root = Initialize-WriteTestRootLocal -Fixture applied
            $path = Join-Path $root 'consumption.md'
            $line = 'This run consumed an estimated **$0.3171 (~31.71 AI credits)**. A manual model across 12 turns is estimated at **$' + $baseline + ' (~10 AI credits)**, a saving of about **50.00%**.'
            Set-Content -LiteralPath $path -Value ([regex]::Replace((Get-Content -LiteralPath $path -Raw), '(?m)^This run consumed[^\r\n]*', { $line })) -NoNewline
            $write = Invoke-Ledger -SquadRoot $root -Write
            $write.ExitCode | Should -Be 0 -Because $write.Output
            $after = Get-Content -LiteralPath $path -Raw
            $after | Should -Match ([regex]::Escape("manual model across 12 turns is estimated at **`$$baseline"))
            if ($baseline -eq '0.10') { $after | Should -Match '\*\*-217\.08%\*\*' }
            else { $after | Should -Match 'saving unavailable \(non-positive manual baseline\)' }
            $after | Should -Not -Match 'stale — refreshed|NaN|Infinity'
            (Invoke-Ledger -SquadRoot $root -Check).ExitCode | Should -Be 0
        }
    }

    It 'replaces seed or missing comparisons with an explicit unavailable baseline and remains idempotent' {
        foreach ($kind in @('seed', 'missing')) {
            $root = Initialize-WriteTestRootLocal -Fixture applied
            $path = Join-Path $root 'consumption.md'
            $text = Get-Content -LiteralPath $path -Raw
            if ($kind -eq 'seed') { $text = [regex]::Replace($text, '(?m)^This run consumed[^\r\n]*', 'This run consumed an estimated **$<squad-cost> (~<squad-credits> AI credits)** across <n> agents.') }
            else { $text = [regex]::Replace($text, '(?s)## Cost Comparison.*$', '## Operator Notes' + "`n`nKeep this note.`n") }
            Set-Content -LiteralPath $path -Value $text -NoNewline
            (Invoke-Ledger -SquadRoot $root -Check).ExitCode | Should -Be 1
            $write = Invoke-Ledger -SquadRoot $root -Write
            $write.ExitCode | Should -Be 0 -Because $write.Output
            $after = Get-Content -LiteralPath $path -Raw
            $after | Should -Match ([regex]::Escape('**$0.3171 (~31.71 AI credits)**'))
            $after | Should -Match 'manual baseline and saving unavailable'
            $after | Should -Not -Match '<squad-cost>|<squad-credits>|<n>'
            if ($kind -eq 'missing') { $after | Should -Match 'Keep this note\.' }
            $hash = (Get-FileHash -LiteralPath $path).Hash
            (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0
            (Get-FileHash -LiteralPath $path).Hash | Should -Be $hash
            (Invoke-Ledger -SquadRoot $root -Check).ExitCode | Should -Be 0
        }
    }

    It 'validates comparison numbers semantically even with observed usage and never changes checked files' {
        $root = Initialize-WriteTestRootLocal -Fixture applied
        $path = Join-Path $root 'consumption.md'
        $line = 'This run consumed an estimated **$0.317100 (~31.710 AI credits)**. A manual baseline is estimated at **$20.00 (~2000 AI credits)**, a saving of about **98.41%**.'
        $text = [regex]::Replace((Get-Content -LiteralPath $path -Raw), '(?m)^This run consumed[^\r\n]*', { $line })
        $text = $text.Replace('## Cost Comparison', "## Observed Usage (host-reported)`n`nIndependent host telemetry retained.`n`n## Cost Comparison")
        Set-Content -LiteralPath $path -Value $text -NoNewline
        (Invoke-Ledger -SquadRoot $root -Check).ExitCode | Should -Be 0
        foreach ($mutation in @(@('$0.317100', '$0.400000'), @('31.710 AI', '39.000 AI'), @('98.41%', '90.00%'))) {
            Set-Content -LiteralPath $path -Value $text.Replace($mutation[0], $mutation[1]) -NoNewline
            $hashes = @(Get-FileHash -LiteralPath $path, (Join-Path $root 'state.json') | ForEach-Object Hash)
            $check = Invoke-Ledger -SquadRoot $root -Check
            $check.ExitCode | Should -Be 1 -Because $check.Output
            $check.Output | Should -Match 'Cost Comparison'
            $check.Output | Should -Match 'failure class: ledger-only'
            @(Get-FileHash -LiteralPath $path, (Join-Path $root 'state.json') | ForEach-Object Hash) | Should -Be $hashes
        }
    }

    It 'preserves a supplied baseline when squad figures are still template placeholders' {
        $root = Initialize-WriteTestRootLocal -Fixture applied
        $path = Join-Path $root 'consumption.md'
        $line = 'This run consumed an estimated **$<squad-cost> (~<squad-credits> AI credits)** across <n> agents. Manually prompting Example Model across 12 turns is estimated at **$20.00 (~2000 AI credits)**, a saving of about **<savings-pct>%**.'
        Set-Content -LiteralPath $path -Value ([regex]::Replace((Get-Content -LiteralPath $path -Raw), '(?m)^This run consumed[^\r\n]*', { $line })) -NoNewline
        $write = Invoke-Ledger -SquadRoot $root -Write
        $write.ExitCode | Should -Be 0 -Because $write.Output
        $after = Get-Content -LiteralPath $path -Raw
        $after | Should -Match ([regex]::Escape('**$0.3171 (~31.71 AI credits)** across 1 agents.'))
        $after | Should -Match ([regex]::Escape('Example Model across 12 turns is estimated at **$20.00 (~2000 AI credits)**, a saving of about **98%**.'))
        (Invoke-Ledger -SquadRoot $root -Check).ExitCode | Should -Be 0
    }

    It 'changes only the two currentRun values in state.json, preserving every other byte' {
        $root = Initialize-WriteTestRootLocal
        Edit-StateTotalLocal -Root $root -Cost '1.5' -Cents '150'
        $statePath = Join-Path $root 'state.json'
        $before = Get-Content -LiteralPath $statePath -Raw
        (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0
        $after = Get-Content -LiteralPath $statePath -Raw

        $normalize = { param($text) ($text -replace '"estCostUsd"\s*:\s*[0-9.]+', '"estCostUsd": X') -replace '"estCreditsTotal"\s*:\s*[0-9.]+', '"estCreditsTotal": X' }
        (& $normalize $after) | Should -Be (& $normalize $before)
        $after | Should -Match '"estCostUsd": 0\.3171'
        $after | Should -Match '"estCreditsTotal": 31\.71'
    }

    It 'is idempotent: a second -Write produces identical bytes' {
        $root = Initialize-WriteTestRootLocal
        (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0
        $first = (Get-FileHash -LiteralPath (Join-Path $root 'consumption.md')).Hash
        (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0
        (Get-FileHash -LiteralPath (Join-Path $root 'consumption.md')).Hash | Should -Be $first
    }

    It 'refuses -Write combined with -Check, writing nothing' {
        $root = Initialize-WriteTestRootLocal
        $before = (Get-FileHash -LiteralPath (Join-Path $root 'consumption.md')).Hash
        $output = & pwsh -NoProfile -File $script:LedgerScript -SquadRoot $root -Write -Check 2>&1 | Out-String
        $LASTEXITCODE | Should -Not -Be 0
        $output | Should -Match 'cannot be combined with -Check'
        (Get-FileHash -LiteralPath (Join-Path $root 'consumption.md')).Hash | Should -Be $before
    }

    It 'refuses a federation root' {
        $root = Initialize-WriteTestRootLocal
        Set-Content -LiteralPath (Join-Path $root 'federation.md') -Value '# Federation'
        $result = Invoke-Ledger -SquadRoot $root -Write
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'does not apply to a federation root'
    }

    It 'refuses a consumption.md missing its Derivation block, writing neither file' {
        $root = Initialize-WriteTestRootLocal
        $ledgerPath = Join-Path $root 'consumption.md'
        $statePath = Join-Path $root 'state.json'
        $stripped = (Get-Content -LiteralPath $ledgerPath -Raw) -replace '(?s)### Derivation.*?```text.*?```', ''
        Set-Content -LiteralPath $ledgerPath -Value $stripped -NoNewline
        Edit-StateTotalLocal -Root $root -Cost '1.5' -Cents '150'
        $stateBefore = (Get-FileHash -LiteralPath $statePath).Hash

        $result = Invoke-Ledger -SquadRoot $root -Write
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'nothing was written'
        (Get-Content -LiteralPath $ledgerPath -Raw) | Should -Be $stripped
        (Get-FileHash -LiteralPath $statePath).Hash | Should -Be $stateBefore
    }

    It 'refuses a state.json missing a currentRun total, leaving consumption.md untouched too' {
        $root = Initialize-WriteTestRootLocal
        $ledgerPath = Join-Path $root 'consumption.md'
        $statePath = Join-Path $root 'state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
        $state['currentRun'].Remove('estCreditsTotal')
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -NoNewline
        $ledgerBefore = (Get-FileHash -LiteralPath $ledgerPath).Hash

        $result = Invoke-Ledger -SquadRoot $root -Write
        $result.ExitCode | Should -Not -Be 0
        # The child's error view wraps to the console width (narrow on CI) and prefixes each
        # continuation line with '|', so compare against the message with that layout removed.
        ($result.Output -replace '[\s|]+', ' ') | Should -Match "no 'estCreditsTotal' key"
        (Get-FileHash -LiteralPath $ledgerPath).Hash | Should -Be $ledgerBefore
    }

    It 'repairs a hand-written ledger whose Derivation carries placeholder identities instead of hashes' {
        # A live run's Scribe hand-wrote 'identities: unreported' and 'identities:
        # dispatch-reported'; the guard read those labels as hashes, failed them as
        # overwrites, and refused every later -Write.
        $root = Initialize-WriteTestRootLocal -Fixture 'applied'
        $ledgerPath = Join-Path $root 'consumption.md'
        $raw = Get-Content -LiteralPath $ledgerPath -Raw
        $raw = $raw.Replace('```text', "``````text`nSquad Researcher.md — 1 block(s) — identities: unreported`nSquad Scribe.md — 1 block(s) — identities: dispatch-reported")
        Set-Content -LiteralPath $ledgerPath -Value $raw -NoNewline

        $result = Invoke-Ledger -SquadRoot $root -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $check = Invoke-Ledger -SquadRoot $root -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Scribe' = 1 }
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }
}

Describe 'Measure-SquadLedger -Check reports a role missing from the ledger instead of crashing' {
    It 'names the missing Attribution row (a live hand-written ledger dropped the intake-validator row and -Check threw on $null.Count)' {
        $root = Join-Path $TestDrive 'missing-role-row'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $ledgerPath = Join-Path $root 'consumption.md'
        $lines = Get-Content -LiteralPath $ledgerPath | Where-Object { $_ -notmatch '^\| researcher\s+\| Alpha' }
        Set-Content -LiteralPath $ledgerPath -Value $lines

        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "missing a row for role 'researcher'"
        $result.Output | Should -Not -Match 'Count'
    }
}

# R-LEDGER-SHAPE: the Scribe pasted this helper's whole console output -- heading
# decoration, table, and diagnostic tail -- as the *entire* consumption.md, and
# -Check still exited 0 because it only ever compared the Total row's numbers. The
# three Describe blocks below cover the two-part remedy: the default markdown output
# is now a bare, paste-safe `## Usage & Cost` / `### Derivation` fragment with no
# path decoration and no diagnostics on the success stream, and -Check now fails a
# ledger that lost its own shape even when its numbers still reconcile.
Describe 'Measure-SquadLedger prints a paste-safe fragment, never a whole ledger file' {
    BeforeAll {
        $script:AppliedRoot = Join-Path $script:FixtureRoot 'applied'
    }

    It 'the default markdown stdout begins with the bare "## Attribution" heading, followed by "## Usage & Cost"' {
        # R-LEDGER-ATTRIBUTION: the default fragment now leads with Attribution
        # (never fabricated Model/Model Source/Priced As values) so the Scribe
        # pastes both roster-honest tables from one helper run, never hand-writing
        # Attribution separately.
        $result = Invoke-Ledger -SquadRoot $script:AppliedRoot -Format markdown
        ($result.Output -split '\r?\n')[0] | Should -Be '## Attribution'
        $result.Output | Should -Match '(?m)^## Usage & Cost\s*$'
    }

    It 'the default markdown stdout carries no absolute squad-root path, no state.json leakage, and no "> Basis:" line' {
        $result = Invoke-Ledger -SquadRoot $script:AppliedRoot -Format markdown
        $result.Output | Should -Not -Match ([regex]::Escape($script:AppliedRoot))
        $result.Output | Should -Not -Match 'state\.json currentRun'
        $result.Output | Should -Not -Match '> Basis:'
    }
}

Describe 'Measure-SquadLedger -Check catches a structurally destroyed ledger (H1 and Attribution stripped)' {
    It 'exits 1 and names both the missing H1 and the missing Attribution heading' {
        $root = Join-Path $TestDrive 'structurally-destroyed'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $ledgerPath = Join-Path $root 'consumption.md'
        $stripped = ((Get-Content -LiteralPath $ledgerPath) | Where-Object {
                $_ -notmatch '^# Squad Consumption Ledger' -and $_ -notmatch '^## Attribution\s*$'
            }) -join "`n"
        Set-Content -LiteralPath $ledgerPath -Value $stripped -NoNewline
        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'missing its H1 heading'
        $result.Output | Should -Match "missing its '## Attribution' heading"
    }
}

Describe 'Measure-SquadLedger -Check catches leaked helper diagnostics pasted into the ledger' {
    It 'exits 1 and names the leaked "state.json currentRun." line' {
        $root = Join-Path $TestDrive 'leaked-diagnostics'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $ledgerPath = Join-Path $root 'consumption.md'
        $leaked = (Get-Content -LiteralPath $ledgerPath -Raw) + "`nstate.json currentRun.estCostUsd: 29.651`n"
        Set-Content -LiteralPath $ledgerPath -Value $leaked -NoNewline
        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'leaks a helper diagnostic line'
    }
}

# R-LEDGER-ATTRIBUTION: the Scribe hand-rebuilt the live '## Attribution' table and
# invented identities for four roles -- most tellingly, writing a resolved model
# name (the rate row's own `priced_as`) into the Model cell for a role whose block
# was `model: unknown` / `model_source: unresolved`, and once writing `tier-default`
# (a Basis value, not a legal Model Source) into the Model Source cell. Neither
# -Check nor any other test ever compared Attribution against the blocks it
# describes, so this passed every gate. The three Describe blocks below cover the
# remedy: the default output's Attribution table never substitutes a priced-as
# model for an unresolved one, and -Check now fails both classes of the live defect.
Describe 'Measure-SquadLedger default Attribution table never substitutes the priced-as model for an unresolved one' {
    BeforeAll {
        $script:UnresolvedRoot = Join-Path $TestDrive 'attribution-unresolved-block'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $script:UnresolvedRoot -Recurse

        # Add a roster row (so the block prints under role 'challenger', matching
        # the live run's own naming) and a history file whose block is exactly the
        # live defect's shape: an honestly unresolved model priced only through its
        # model_tier fallback (there is no rate row literally named "unknown").
        Add-Content -LiteralPath (Join-Path $script:UnresolvedRoot 'team.md') -Value "| challenger | Epsilon | Squad Challenger | — | — | runSubagent / task | default | reviews/ |"

        $unknownHistory = @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Challenger

### 2026-09-27T11:00:00Z Challenging the fixture-topic recommendation

* Turn: 3
* Request: Challenge the recommended fixture shape.
* Deliverable: `reviews/2026-09-27-challenge.md`
* Outcome: Confirmed the minimal shape with one caveat.

#### Consumption

```json
{
  "model": "unknown",
  "model_source": "unresolved",
  "priced_as": "unknown",
  "model_tier": "default",
  "internal_turns": 6,
  "input_tokens": 4000,
  "cached_tokens": 16000,
  "cache_write_tokens": 3000,
  "output_tokens": 5000,
  "basis": "estimated"
}
```
'@
        Set-Content -LiteralPath (Join-Path $script:UnresolvedRoot 'history/Squad Challenger.md') -Value $unknownHistory -NoNewline
    }

    It 'prints Model "unknown" and Model Source "unresolved" for the challenger role, never the tier-fallback priced-as model' {
        $result = Invoke-Ledger -SquadRoot $script:UnresolvedRoot -Format markdown
        $result.Output | Should -Match '(?m)^\|\s*challenger\s*\|\s*Epsilon\s*\|\s*Squad Challenger\s*\|\s*unknown\s*\|\s*unresolved\s*\|\s*Claude Sonnet 4\.6\s*\|\s*default\s*\|\s*$'
        $result.Output | Should -Not -Match '(?m)^\|\s*challenger\s*\|.*\|\s*Claude Sonnet 4\.6\s*\|\s*unresolved\s*\|'
    }
}

Describe 'Measure-SquadLedger -Check catches the live defect: a priced-as model written into an unresolved role''s Attribution Model cell' {
    It 'exits 1 and names the role and the Model column' {
        $root = Join-Path $TestDrive 'attribution-model-leak'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        Add-Content -LiteralPath (Join-Path $root 'team.md') -Value "| challenger | Epsilon | Squad Challenger | — | — | runSubagent / task | default | reviews/ |"

        $unknownHistory = @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Challenger

### 2026-09-27T11:00:00Z Challenging the fixture-topic recommendation

* Turn: 3
* Request: Challenge the recommended fixture shape.
* Deliverable: `reviews/2026-09-27-challenge.md`
* Outcome: Confirmed the minimal shape with one caveat.

#### Consumption

```json
{
  "model": "unknown",
  "model_source": "unresolved",
  "priced_as": "unknown",
  "model_tier": "default",
  "internal_turns": 6,
  "input_tokens": 4000,
  "cached_tokens": 16000,
  "cache_write_tokens": 3000,
  "output_tokens": 5000,
  "basis": "estimated"
}
```
'@
        Set-Content -LiteralPath (Join-Path $root 'history/Squad Challenger.md') -Value $unknownHistory -NoNewline

        # Regenerate a self-consistent ledger from the now three-block history set --
        # front matter and H1 stay from the fixture's own template, the helper
        # supplies a fresh Attribution/Usage & Cost/Derivation fragment for it.
        $fragment = (Invoke-Ledger -SquadRoot $root -Format markdown).Output
        $ledgerPath = Join-Path $root 'consumption.md'
        $rebuilt = @"
---
description: "Squad consumption ledger: members, models, estimated tokens, cost, and AI credits"
---

# Squad Consumption Ledger (Run: rp-fixture-01)

$fragment
"@
        Set-Content -LiteralPath $ledgerPath -Value $rebuilt -NoNewline
        Sync-LedgerStateLocal -SquadRoot $root
        (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0

        $selfCheck = Invoke-Ledger -SquadRoot $root -Check
        $selfCheck.ExitCode | Should -Be 0 -Because "the freshly regenerated ledger must itself pass -Check before corruption: $($selfCheck.Output)"

        # Reproduce the live defect: overwrite only the challenger row's Model cell
        # (still literally "unknown") with the rate row that priced it.
        (Get-Content -LiteralPath $ledgerPath -Raw).Replace('| unknown | unresolved |', '| Claude Sonnet 4.6 | unresolved |') |
            Set-Content -LiteralPath $ledgerPath -NoNewline

        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "role 'challenger' agent 'Squad Challenger' column 'Model'"
    }
}

Describe 'Measure-SquadLedger -Check catches an illegal Model Source value' {
    It 'exits 1 and names the role, the column, and the illegal "tier-default" value' {
        $root = Join-Path $TestDrive 'attribution-illegal-source'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $ledgerPath = Join-Path $root 'consumption.md'
        (Get-Content -LiteralPath $ledgerPath -Raw).Replace('session-inherited', 'tier-default') |
            Set-Content -LiteralPath $ledgerPath -NoNewline

        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "role 'researcher' agent 'Squad Researcher' column 'Model Source' has illegal value 'tier-default'"
    }
}

# R-LEDGER-ATTRIBUTION follow-up: the live root printed two `architect` rows
# (team.md's Primary `System Architecture Reviewer` and Fallback `ADR Creator`,
# both actually dispatched in the same run) with identical Agent cells --
# `System Architecture Reviewer` twice -- because Agent was set from the role's
# roster-declared Primary rather than from the history file each row actually
# came from. The remedy: Agent always names the history file's own agent name,
# so a Fallback dispatch is never misattributed to that role's Primary.
Describe 'Measure-SquadLedger Attribution names the actually-dispatched agent, not merely the role''s roster Primary' {
    BeforeAll {
        $script:PrimaryFallbackRoot = Join-Path $TestDrive 'attribution-primary-and-fallback'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $script:PrimaryFallbackRoot -Recurse

        # A role with both a Primary and a Fallback agent, matching team.md's own
        # live `architect` row shape (Primary `System Architecture Reviewer`,
        # Fallback `ADR Creator`).
        Add-Content -LiteralPath (Join-Path $script:PrimaryFallbackRoot 'team.md') -Value "| architect | Zeta | System Architecture Reviewer | ADR Creator | — | runSubagent / task | default | docs/architecture/ |"

        $primaryHistory = @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: System Architecture Reviewer

### 2026-09-27T12:00:00Z Reviewing the fixture-topic design tradeoffs

* Turn: 4
* Request: Review the recommended fixture shape's design tradeoffs.
* Deliverable: `docs/architecture/2026-09-27-design-review.md`
* Outcome: Confirmed the minimal shape.

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "agent-pinned",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 4,
  "input_tokens": 2000,
  "cached_tokens": 8000,
  "cache_write_tokens": 1000,
  "output_tokens": 2500,
  "basis": "estimated"
}
```
'@
        Set-Content -LiteralPath (Join-Path $script:PrimaryFallbackRoot 'history/System Architecture Reviewer.md') -Value $primaryHistory -NoNewline

        $fallbackHistory = @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: ADR Creator

### 2026-09-27T13:00:00Z Capturing the fixture-topic decision record

* Turn: 2
* Request: Capture the fixture-topic decision as an ADR.
* Deliverable: `docs/architecture/2026-09-27-decision-record.md`
* Outcome: ADR captured.

#### Consumption

```json
{
  "model": "Claude Opus 5",
  "model_source": "agent-pinned",
  "priced_as": "Claude Opus 5",
  "model_tier": "extended",
  "internal_turns": 2,
  "input_tokens": 1000,
  "cached_tokens": 4000,
  "cache_write_tokens": 500,
  "output_tokens": 1200,
  "basis": "estimated"
}
```
'@
        Set-Content -LiteralPath (Join-Path $script:PrimaryFallbackRoot 'history/ADR Creator.md') -Value $fallbackHistory -NoNewline
    }

    It 'prints two architect rows, one per history file, whose Agent cells are the two distinct dispatched agent names' {
        $result = Invoke-Ledger -SquadRoot $script:PrimaryFallbackRoot -Format markdown
        $lines = $result.Output -split '\r?\n'
        $attributionStart = ($lines | Select-String -Pattern '^## Attribution\s*$').LineNumber[0]
        $usageStart = ($lines | Select-String -Pattern '^## Usage & Cost\s*$').LineNumber[0]
        # LineNumber is 1-based; the slice below is the Attribution table's own
        # body, exclusive of the Usage & Cost heading that follows it -- excluding
        # this scope would also match that table's own "| architect | ..." rows.
        $attributionLines = @($lines[$attributionStart..($usageStart - 2)])
        $architectLines = @($attributionLines | Where-Object { $_ -match '^\|\s*architect\s*\|' })
        $architectLines.Count | Should -Be 2
        ($architectLines -join "`n") | Should -Match '\|\s*architect\s*\|\s*Zeta\s*\|\s*ADR Creator\s*\|'
        ($architectLines -join "`n") | Should -Match '\|\s*architect\s*\|\s*Zeta\s*\|\s*System Architecture Reviewer\s*\|'
    }
}

# R-LEDGER-ATTRIBUTION follow-up: before this fix, `-Check`'s Attribution
# comparison indexed ledger rows by Role alone, so a role dispatched through both
# a Primary and a Fallback agent (e.g. the `architect` Primary/Fallback pair
# above) collapsed both ledger rows onto whichever one was parsed last -- both
# aggregates were then compared against that single survivor, producing a false
# mismatch (each aggregate's own Priced As legitimately differs from the other
# role-mate's) even when every row was individually correct. The two Describe
# blocks below are the regression coverage for the fix: a composite-keyed
# (Role, Agent) lookup so each history file's own row is compared only to its
# own aggregate.
Describe 'Measure-SquadLedger -Check compares each Primary/Fallback row to its own aggregate, not the other role-mate''s' {
    BeforeAll {
        $script:CompositeKeyRoot = Join-Path $TestDrive 'attribution-composite-key'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $script:CompositeKeyRoot -Recurse

        # Same Primary+Fallback `architect` shape as the Describe block above:
        # team.md's own live convention (Primary `System Architecture Reviewer`,
        # Fallback `ADR Creator`), each priced at a distinct, directly-hit rate
        # row (Claude Sonnet 4.6 / Claude Opus 5) so Model and Priced As are
        # identical within each row -- the swap in the second It below is only
        # detectable by comparing each row to its own aggregate, never by
        # comparing either row to itself.
        Add-Content -LiteralPath (Join-Path $script:CompositeKeyRoot 'team.md') -Value "| architect | Zeta | System Architecture Reviewer | ADR Creator | — | runSubagent / task | default | docs/architecture/ |"

        $primaryHistory = @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: System Architecture Reviewer

### 2026-09-27T12:00:00Z Reviewing the fixture-topic design tradeoffs

* Turn: 4
* Request: Review the recommended fixture shape's design tradeoffs.
* Deliverable: `docs/architecture/2026-09-27-design-review.md`
* Outcome: Confirmed the minimal shape.

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "agent-pinned",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 4,
  "input_tokens": 2000,
  "cached_tokens": 8000,
  "cache_write_tokens": 1000,
  "output_tokens": 2500,
  "basis": "estimated"
}
```
'@
        Set-Content -LiteralPath (Join-Path $script:CompositeKeyRoot 'history/System Architecture Reviewer.md') -Value $primaryHistory -NoNewline

        $fallbackHistory = @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: ADR Creator

### 2026-09-27T13:00:00Z Capturing the fixture-topic decision record

* Turn: 2
* Request: Capture the fixture-topic decision as an ADR.
* Deliverable: `docs/architecture/2026-09-27-decision-record.md`
* Outcome: ADR captured.

#### Consumption

```json
{
  "model": "Claude Opus 5",
  "model_source": "agent-pinned",
  "priced_as": "Claude Opus 5",
  "model_tier": "extended",
  "internal_turns": 2,
  "input_tokens": 1000,
  "cached_tokens": 4000,
  "cache_write_tokens": 500,
  "output_tokens": 1200,
  "basis": "estimated"
}
```
'@
        Set-Content -LiteralPath (Join-Path $script:CompositeKeyRoot 'history/ADR Creator.md') -Value $fallbackHistory -NoNewline

        # Build a self-consistent ledger the same way scribe-procedure.md's Step 7
        # prescribes: the helper's own printed Attribution/Usage & Cost/Derivation
        # fragment replaces those sections in a copy of the fixture's own ledger,
        # keeping that ledger's own H1, Basis note, and Cost Comparison section
        # exactly as already written (never hand-composed).
        $fragment = (Invoke-Ledger -SquadRoot $script:CompositeKeyRoot -Format markdown).Output.Trim()
        $originalLedger = Get-Content -LiteralPath (Join-Path $script:FixtureRoot 'applied/consumption.md') -Raw
        $h1Line = [regex]::Match($originalLedger, '(?m)^#\s+Squad Consumption Ledger.*$')
        $basisIndex = $originalLedger.IndexOf('> Basis:')
        $head = $originalLedger.Substring(0, $h1Line.Index + $h1Line.Length)
        $tail = $originalLedger.Substring($basisIndex)
        $script:CompositeKeyLedgerContent = "$head`n`n$fragment`n`n$tail"
        $script:CompositeKeyLedgerPath = Join-Path $script:CompositeKeyRoot 'consumption.md'
        Set-Content -LiteralPath $script:CompositeKeyLedgerPath -Value $script:CompositeKeyLedgerContent -NoNewline
        Sync-LedgerStateLocal -SquadRoot $script:CompositeKeyRoot
        (Invoke-Ledger -SquadRoot $script:CompositeKeyRoot -Write).ExitCode | Should -Be 0

        # Guard: the spliced-together ledger must itself pass -Check before either
        # It below relies on it, so a failure here points at the splice, not the
        # composite-key fix under test.
        $script:CompositeKeyGuard = Invoke-Ledger -SquadRoot $script:CompositeKeyRoot -Check
    }

    It 'a root with a Primary+Fallback role whose ledger Attribution is correct: -Check exits 0' {
        $script:CompositeKeyGuard.ExitCode | Should -Be 0 -Because "the spliced ledger must self-pass before any corruption is applied: $($script:CompositeKeyGuard.Output)"
    }

    It 'the same root with the two rows'' Priced As cells swapped: -Check exits 1 naming both rows'' role and agent' {
        $swappedRoot = Join-Path $TestDrive 'attribution-composite-key-swapped'
        Copy-Item -LiteralPath $script:CompositeKeyRoot -Destination $swappedRoot -Recurse

        $ledgerPath = Join-Path $swappedRoot 'consumption.md'
        $content = Get-Content -LiteralPath $ledgerPath -Raw

        # Swap only the Priced As cell of each architect row (the sixth data
        # column), anchored on each row's own Agent/Model Source cells so the
        # identical-looking "Claude Sonnet 4.6" / "Claude Opus 5" text that also
        # appears in the Model column of the very same row is never touched --
        # only the Priced As cell moves between the two rows. Both rows print
        # Tier "default" (Tier is roster-sourced from team.md's single per-role
        # column, not block-derived, so it is identical for both the Primary and
        # the Fallback), so the lookahead anchor is " | default" for both.
        $primaryPricedAsPattern = '(?<=System Architecture Reviewer \| Claude Sonnet 4\.6 \| agent-pinned \| )Claude Sonnet 4\.6(?= \| default)'
        $fallbackPricedAsPattern = '(?<=ADR Creator \| Claude Opus 5 \| agent-pinned \| )Claude Opus 5(?= \| default)'
        $content = $content -replace $primaryPricedAsPattern, 'Claude Opus 5'
        $content = $content -replace $fallbackPricedAsPattern, 'Claude Sonnet 4.6'
        Set-Content -LiteralPath $ledgerPath -Value $content -NoNewline

        $result = Invoke-Ledger -SquadRoot $swappedRoot -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "role 'architect' agent 'System Architecture Reviewer' column 'Priced As'"
        $result.Output | Should -Match "role 'architect' agent 'ADR Creator' column 'Priced As'"
    }
}

Describe 'Connector member-aware attribution and legacy missing-member behavior' {
    BeforeAll {
        function Initialize-ConnectorAttributionManifest {
            param([string]$Root, [string[]]$Roles)
            $example = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'docs', 'templates', 'connector-example', 'manifest.1.1.json'
            $manifest = Get-Content -LiteralPath $example -Raw | ConvertFrom-Json -AsHashtable
            $manifest.roles = $Roles
            $path = Join-Path $Root 'docs/templates/connector-example/manifest.1.1.json'
            [void][System.IO.Directory]::CreateDirectory((Split-Path $path -Parent))
            $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path
        }
    }

    It 'keeps two Squad Connector members distinct in Attribution by (agent, Member Name)' {
        $root = Join-Path $TestDrive 'connector-distinct-members'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        Initialize-ConnectorAttributionManifest -Root $root -Roles @('gcp')
        Add-Content -LiteralPath (Join-Path $root 'team.md') -Value @'
| gcp | GCP Assessor | Squad Connector | — | — | runSubagent / task | default | gcp/assessments/ |
| gcp | GCP Reviewer | Squad Connector | — | — | runSubagent / task | default | gcp/reviews/ |

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |
| gcp-assessor | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | add | role | role:gcp/GCP Assessor | GCP Assessor | gcp | azure-architect | connector |
| gcp-reviewer | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | add | role | role:gcp/GCP Reviewer | GCP Reviewer | gcp | azure-architect | connector |
'@
        Set-Content -LiteralPath (Join-Path $root 'history/Squad Connector.md') -Value @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Connector

### 2026-10-12T10:00:00Z Assess gcp architecture

* Turn: 3
* Request: Assess bounded gcp architecture.
* Deliverable: `research/2026-09-27-fixture-topic.md`
* Outcome: Assessed architecture.
* Member Name: GCP Assessor
* External provenance: connector=acme-delivery-orchestrator-v3; binding=gcp-assessor; endpoint=orchestrator; mode=add; target=role:gcp/GCP Assessor
* Verification: external, unverified
* External-unmetered: connector=acme-delivery-orchestrator-v3

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "dispatch-reported",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 2,
  "input_tokens": 800,
  "cached_tokens": 3200,
  "cache_write_tokens": 400,
  "output_tokens": 900,
  "basis": "estimated"
}
```

### 2026-10-12T10:05:00Z Review gcp architecture

* Turn: 3
* Request: Review bounded gcp architecture.
* Deliverable: `research/2026-09-27-fixture-topic.md`
* Outcome: Reviewed architecture.
* Member Name: GCP Reviewer
* External provenance: connector=acme-delivery-orchestrator-v3; binding=gcp-reviewer; endpoint=orchestrator; mode=add; target=role:gcp/GCP Reviewer
* Verification: external, unverified
* External-unmetered: connector=acme-delivery-orchestrator-v3

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "dispatch-reported",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 2,
  "input_tokens": 900,
  "cached_tokens": 3600,
  "cache_write_tokens": 450,
  "output_tokens": 950,
  "basis": "estimated"
}
```
'@ -NoNewline

        (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0
        $check = Invoke-Ledger -SquadRoot $root -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Scribe' = 1; 'Squad Connector' = 2 }
        $check.ExitCode | Should -Be 0 -Because $check.Output

        $markdown = (Invoke-Ledger -SquadRoot $root -Format markdown).Output
        $markdown | Should -Match '\| gcp \| GCP Assessor \| Squad Connector \|'
        $markdown | Should -Match '\| gcp \| GCP Reviewer \| Squad Connector \|'
    }

    It 'keeps legacy unique-agent history without Member Name valid' {
        $result = Invoke-Ledger -SquadRoot (Join-Path $script:FixtureRoot 'applied') -Check
        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'fails closed for ambiguous shared-agent connector history missing Member Name' {
        $root = Join-Path $TestDrive 'connector-ambiguous-memberless'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        Add-Content -LiteralPath (Join-Path $root 'team.md') -Value @'
| gcp | GCP Assessor | Squad Connector | — | — | runSubagent / task | default | gcp/assessments/ |
| gcp | GCP Reviewer | Squad Connector | — | — | runSubagent / task | default | gcp/reviews/ |
'@
        Set-Content -LiteralPath (Join-Path $root 'history/Squad Connector.md') -Value @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Connector

### 2026-10-12T10:00:00Z Ambiguous connector history

* Turn: 3
* Request: Produce a connector note.
* Deliverable: `research/2026-09-27-fixture-topic.md`
* Outcome: Produced a connector note.
* External provenance: connector=legacy-agent; binding=legacy-1.0; endpoint=agent; mode=replace; target=role:gcp
* Verification: external, unverified
* External-unmetered: connector=legacy-agent

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "dispatch-reported",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 2,
  "input_tokens": 700,
  "cached_tokens": 2800,
  "cache_write_tokens": 350,
  "output_tokens": 800,
  "basis": "estimated"
}
```
'@ -NoNewline
        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'Attribution identity:'
        $result.Output | Should -Match 'ambiguous-missing-member'
    }

    It 'fails closed when connector Member Name is reused across add/replace/coordinator bindings' {
        $root = Join-Path $TestDrive 'connector-duplicate-member-collision'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        Add-Content -LiteralPath (Join-Path $root 'team.md') -Value @'
## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |
| gcp-assessor | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | add | role | role:gcp/GCP Assessor | GCP Assessor | gcp | azure-architect | connector |
| developer-replace | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | GCP Assessor | — | developer | connector |
'@
        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'globally unique across connector bindings'
    }

    It 'fails closed when two replacement bindings reuse one connector Member Name' {
        $root = Join-Path $TestDrive 'connector-duplicate-replace-coordinator-member'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        Add-Content -LiteralPath (Join-Path $root 'team.md') -Value @'
## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |
| developer-replace | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer | — | developer | connector |
| second-developer | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Gamma | Partner Developer | — | developer | ask |
'@
        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'globally unique across connector bindings'
    }

    It 'rejects a retired coordinator binding regardless of its member identity' {
        $root = Join-Path $TestDrive 'connector-coordinator-target-collision'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $teamPath = Join-Path $root 'team.md'
        $team = Get-Content -LiteralPath $teamPath -Raw
        $team = $team.Replace('| scribe     |             | Squad Scribe          | —                  | —              | runSubagent / task | fast       | (squad state)      |', "| scribe     |             | Squad Scribe          | —                  | —              | runSubagent / task | fast       | (squad state)      |`n| coordinator | Lead      | Squad Coordinator     | —                  | —              | runSubagent / task | default    | plans/             |")
        [System.IO.File]::WriteAllText($teamPath, $team, [System.Text.UTF8Encoding]::new($false))
        Add-Content -LiteralPath (Join-Path $root 'team.md') -Value @'
## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |
| coordinator-replace | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | coordinator | coordinator:Squad Coordinator | Lead | — | coordinator | connector |
'@
        $result = Invoke-Ledger -SquadRoot $root -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'governance are protected'
    }

    It 'uses the explicit trusted target member tier for replace bindings regardless roster row order' {
        foreach ($variant in @('gamma-first', 'delta-first')) {
            $root = Join-Path $TestDrive "connector-deterministic-tier-$variant"
            Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
            Initialize-ConnectorAttributionManifest -Root $root -Roles @('developer')
            $teamPath = Join-Path $root 'team.md'
            $team = Get-Content -LiteralPath $teamPath -Raw
            $developerRows = if ($variant -eq 'gamma-first') {
                @(
                    '| developer | Gamma | Squad Implementor | — | — | runSubagent / task | default | changes/gamma/ |',
                    '| developer | Delta | Squad Implementor | — | — | runSubagent / task | extended | changes/delta/ |'
                )
            }
            else {
                @(
                    '| developer | Delta | Squad Implementor | — | — | runSubagent / task | extended | changes/delta/ |',
                    '| developer | Gamma | Squad Implementor | — | — | runSubagent / task | default | changes/gamma/ |'
                )
            }
            $team = $team.Replace('| scribe     |             | Squad Scribe          | —                  | —              | runSubagent / task | fast       | (squad state)      |', "| scribe     |             | Squad Scribe          | —                  | —              | runSubagent / task | fast       | (squad state)      |`n$($developerRows[0])`n$($developerRows[1])")
            [System.IO.File]::WriteAllText($teamPath, $team, [System.Text.UTF8Encoding]::new($false))
            Add-Content -LiteralPath $teamPath -Value @'
## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |
| developer-replace-delta | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer/Delta | Partner Developer | — | developer | connector |
'@
            Set-Content -LiteralPath (Join-Path $root 'history/Squad Connector.md') -Value @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: Squad Connector

### 2026-10-12T10:00:00Z Replace developer execution

* Turn: 3
* Request: Produce a bounded developer note.
* Deliverable: `changes/delta-note.md`
* Outcome: Delivered a bounded developer note.
* Member Name: Partner Developer
* External provenance: connector=acme-delivery-orchestrator-v3; binding=developer-replace-delta; endpoint=orchestrator; mode=replace; target=role:developer/Delta
* Verification: external, unverified
* External-unmetered: connector=acme-delivery-orchestrator-v3

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "dispatch-reported",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 1,
  "input_tokens": 120,
  "cached_tokens": 240,
  "cache_write_tokens": 0,
  "output_tokens": 220,
  "basis": "estimated"
}
```
'@ -NoNewline

            $markdown = (Invoke-Ledger -SquadRoot $root -Format markdown).Output
            $markdown | Should -Match '\|\s*developer\s*\|\s*Partner Developer\s*\|\s*Squad Connector\s*\|'
            $markdown | Should -Match '\|\s*developer\s*\|\s*Partner Developer\s*\|\s*Squad Connector\s*\|.*\|\s*extended\s*\|'
        }
    }

    It 'fails closed for generic replace targets with mixed internal tiers so roster order cannot change connector tier attribution' {
        foreach ($variant in @('gamma-first', 'delta-first')) {
            $root = Join-Path $TestDrive "connector-ambiguous-generic-tier-$variant"
            Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
            $teamPath = Join-Path $root 'team.md'
            $team = Get-Content -LiteralPath $teamPath -Raw
            $developerRows = if ($variant -eq 'gamma-first') {
                @(
                    '| developer | Gamma | Squad Implementor | — | — | runSubagent / task | default | changes/gamma/ |',
                    '| developer | Delta | Squad Implementor | — | — | runSubagent / task | extended | changes/delta/ |'
                )
            }
            else {
                @(
                    '| developer | Delta | Squad Implementor | — | — | runSubagent / task | extended | changes/delta/ |',
                    '| developer | Gamma | Squad Implementor | — | — | runSubagent / task | default | changes/gamma/ |'
                )
            }
            $team = $team.Replace('| scribe     |             | Squad Scribe          | —                  | —              | runSubagent / task | fast       | (squad state)      |', "| scribe     |             | Squad Scribe          | —                  | —              | runSubagent / task | fast       | (squad state)      |`n$($developerRows[0])`n$($developerRows[1])")
            [System.IO.File]::WriteAllText($teamPath, $team, [System.Text.UTF8Encoding]::new($false))
            Add-Content -LiteralPath $teamPath -Value @'
## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| ---------- | ------------ | -------- | ------------- | --------- | ----------- | ------ | ----------- | ---------- | ------------ | ----------------- |
| developer-replace-generic | acme-delivery-orchestrator-v3 | docs/templates/connector-example/manifest.1.1.json | orchestrator | replace | role | role:developer | Partner Developer | — | developer | connector |
'@

            $result = Invoke-Ledger -SquadRoot $root -Check
            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match "developer-replace-generic"
            $result.Output | Should -Match 'ambiguous'
        }
    }
}

Describe 'CONN-32 production connector ledger regeneration after confirmed binding changes' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot 'SquadState.psm1') -Force

        function New-ConnectorLedgerRoot {
            param([string]$RoleMode = 'replace')
            $workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $root = Join-Path $workspace '.copilot-tracking/squad'
            [void][System.IO.Directory]::CreateDirectory((Split-Path $root -Parent))
            Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
            $teamPath = Join-Path $root 'team.md'
            $team = [System.IO.File]::ReadAllText($teamPath).Replace('| default    | research/', '| extended   | research/')
            $role = if ($RoleMode -eq 'add') { 'gcp' } else { 'researcher' }
            $target = if ($RoleMode -eq 'add') { 'role:gcp/External Researcher' } else { 'role:researcher/Alpha' }
            if ($RoleMode -eq 'add') {
                $team = $team.TrimEnd() + "`n| gcp | External Researcher | Squad Connector | | - | task | extended | research/ |`n"
            }
            $addedRole = if ($RoleMode -eq 'add') { 'gcp' } else { '' }
            $team += @"

## Connector Bindings

| Binding ID | Connector ID | Manifest | Endpoint Kind | Role Mode | Target Kind | Target | Member Name | Added Role | Aligned Role | Default Execution |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| external-research | external-agent | connectors/manifest.json | agent | $RoleMode | role | $target | External Researcher | $addedRole | researcher | connector |
"@
            Set-Content -LiteralPath $teamPath -Value $team -Encoding utf8NoBOM
            $manifest = [ordered]@{
                connectorId = 'external-agent'; schemaVersion = '1.1'; transport = 'file'; endpointKind = 'agent'
                capabilities = @('Bounded research'); roles = @($role); dropPath = '.connector-drops/research/'
                deadlineMinutesDefault = 60; retryCapDefault = 2; contact = 'Consumer operator'; version = '1.0'
            }
            $manifestPath = Join-Path $workspace 'connectors/manifest.json'
            [void][System.IO.Directory]::CreateDirectory((Split-Path $manifestPath -Parent))
            $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8NoBOM
            $oldHistory = Join-Path $root 'history/Squad Researcher.md'
            $historyPath = Join-Path $root 'history/Squad Connector.md'
            $history = [System.IO.File]::ReadAllText($oldHistory).Replace('# History: Squad Researcher', '# History: Squad Connector')
            $history = $history -replace '(?m)^(\* Outcome:[^\r\n]*)', ('$1' + "`n* Member Name: External Researcher" +
                "`n* External provenance: connector=external-agent; binding=external-research; endpoint=agent; mode=$RoleMode; target=$target" +
                "`n* Verification: external, unverified`n* External-unmetered: connector=external-agent")
            Set-Content -LiteralPath $historyPath -Value $history -Encoding utf8NoBOM -NoNewline
            Remove-Item -LiteralPath $oldHistory
            [pscustomobject]@{ Root = $root; Workspace = $workspace; Manifest = $manifest; ManifestPath = $manifestPath; Role = $role; RoleMode = $RoleMode; HistoryPath = $historyPath }
        }

        function Save-LedgerRetirement {
            param(
                $Fixture, [string]$Mutation,
                [string[]]$HistoryEntries,
                [string]$RetiredAt = '2026-10-21T12:00:00Z'
            )
            $record = [ordered]@{
                team = [System.IO.File]::ReadAllText((Join-Path $Fixture.Root 'team.md'))
                manifests = @{ 'connectors/manifest.json' = $Fixture.Manifest }
                confirmed = $true; confirmationRef = 'in-chat:confirmed-ledger-refresh'
                historyEntries = @([regex]::Matches([System.IO.File]::ReadAllText($Fixture.HistoryPath), '(?m)^###[ \t]+([^\r\n]+)') |
                    ForEach-Object { $_.Groups[1].Value.Trim() })
            }
            if ($PSBoundParameters.ContainsKey('HistoryEntries')) { $record.historyEntries = $HistoryEntries }
            switch ($Mutation) {
                'unconfirmed' { $record.confirmed = $false }
                'missing confirmation' { $record.confirmationRef = '' }
                'missing snapshot' { $record.manifests = @{} }
                'wrong manifest' { $record.manifests['connectors/manifest.json'] = @{ connectorId = 'wrong-id' } }
                'unknown field' { $record.authority = 'external' }
                'invalid prior target' { $record.team = $record.team.Replace('role:researcher/Alpha', 'role:researcher/Missing') }
                'postdated entry' { $record.historyEntries = @('2027-01-01T00:00:00Z Future work') }
                'retry string' { $record.manifests['connectors/manifest.json'].retryCapDefault = 'invalid' }
                'retry numeric string' { $record.manifests['connectors/manifest.json'].retryCapDefault = '2' }
                'retry negative' { $record.manifests['connectors/manifest.json'].retryCapDefault = -1 }
                'retry boolean' { $record.manifests['connectors/manifest.json'].retryCapDefault = $true }
                'retry overflow' { $record.manifests['connectors/manifest.json'].retryCapDefault = [long][int]::MaxValue + 1 }
                'deadline string' { $record.manifests['connectors/manifest.json'].deadlineMinutesDefault = 'invalid' }
                'deadline zero' { $record.manifests['connectors/manifest.json'].deadlineMinutesDefault = 0 }
                'deadline fraction' { $record.manifests['connectors/manifest.json'].deadlineMinutesDefault = 1.5 }
            }
            $decision = "`n## Connector Binding Retirement $RetiredAt external-research`n`n" +
                '```json' + "`n" + ($record | ConvertTo-Json -Depth 16) + "`n" + '```'
            Add-Content -LiteralPath (Join-Path $Fixture.Root 'decisions.md') -Value $decision -Encoding utf8NoBOM
        }

        function Change-LedgerBinding {
            param($Fixture, [string]$Change = 'unbind')
            $path = Join-Path $Fixture.Root 'team.md'
            $team = [System.IO.File]::ReadAllText($path)
            if ($Change -eq 'unbind') {
                $team = $team -replace '(?ms)^## Connector Bindings\b.*', ''
                $team = $team -replace '(?m)^\| gcp \| External Researcher[^\r\n]*\r?\n', ''
                Remove-Item -LiteralPath $Fixture.ManifestPath
            }
            else {
                $team = $team.Replace('External Researcher', 'New Researcher').Replace('external-agent', 'new-agent')
                $manifest = $Fixture.Manifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
                $manifest.connectorId = 'new-agent'
                $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Fixture.ManifestPath -Encoding utf8NoBOM
            }
            Set-Content -LiteralPath $path -Value $team.Replace('extended', 'fast') -Encoding utf8NoBOM
        }
    }

    It 'keeps ordinary ledger execution independent of the connector-only helper and its runtime requirement' {
        $directory = Join-Path $TestDrive 'standalone-ledger'
        [void][System.IO.Directory]::CreateDirectory($directory)
        $standalone = Join-Path $directory 'Measure-SquadLedger.ps1'
        Copy-Item -LiteralPath $script:LedgerScript -Destination $standalone
        $output = & pwsh -NoProfile -File $standalone -SquadRoot (Join-Path $script:FixtureRoot 'applied') -Check 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $output | Should -Match 'PASS'
    }

    It 'derives binding-free legacy provenance from the actual history entry rather than an array property' {
        $fixture = New-ConnectorLedgerRoot
        Change-LedgerBinding $fixture
        $history = [System.IO.File]::ReadAllText($fixture.HistoryPath).Replace('binding=external-research', 'binding=legacy-1.0')
        Set-Content -LiteralPath $fixture.HistoryPath -Value $history -NoNewline
        $rewrite = Invoke-Ledger -SquadRoot $fixture.Root -Write
        $rewrite.ExitCode | Should -Be 0 -Because $rewrite.Output
        $ledger = [System.IO.File]::ReadAllText((Join-Path $fixture.Root 'consumption.md'))
        $ledger | Should -Match '\|\s*researcher\s*\|\s*External Researcher\s*\|\s*Squad Connector\s*\|'
        (Invoke-Ledger -SquadRoot $fixture.Root -Check).ExitCode | Should -Be 0
    }

    It 'preserves the actual <RoleMode> ledger after <Change>, without changing cost or history' -ForEach @(
        @{ RoleMode = 'replace'; Change = 'unbind' }, @{ RoleMode = 'replace'; Change = 'rebind' },
        @{ RoleMode = 'add'; Change = 'unbind' }, @{ RoleMode = 'add'; Change = 'rebind' }
    ) {
        $fixture = New-ConnectorLedgerRoot -RoleMode $RoleMode
        $before = Invoke-Ledger -SquadRoot $fixture.Root -Write
        $before.ExitCode | Should -Be 0 -Because $before.Output
        $beforeCost = ((Invoke-Ledger -SquadRoot $fixture.Root -Format json).Output | ConvertFrom-Json).total.estCostUsd
        $historyHash = (Get-FileHash -LiteralPath $fixture.HistoryPath).Hash
        Save-LedgerRetirement $fixture
        Change-LedgerBinding $fixture $Change
        $rewrite = Invoke-Ledger -SquadRoot $fixture.Root -Write
        $rewrite.ExitCode | Should -Be 0 -Because $rewrite.Output
        $ledger = [System.IO.File]::ReadAllText((Join-Path $fixture.Root 'consumption.md'))
        $ledger | Should -Match "\|\s*$($fixture.Role)\s*\|\s*External Researcher\s*\|\s*Squad Connector\s*\|[^\r\n]*\|\s*extended\s*\|"
        $ledger | Should -Not -Match '\|\s*Squad Connector\s*\|\s*\|\s*Squad Connector'
        ((Invoke-Ledger -SquadRoot $fixture.Root -Format json).Output | ConvertFrom-Json).total.estCostUsd | Should -Be $beforeCost
        (Get-FileHash -LiteralPath $fixture.HistoryPath).Hash | Should -Be $historyHash
        $check = Invoke-Ledger -SquadRoot $fixture.Root -Check
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'keeps old and new completed entries distinct after reuse of the binding id' {
        $fixture = New-ConnectorLedgerRoot
        Save-LedgerRetirement $fixture
        Change-LedgerBinding $fixture 'rebind'
        $old = [System.IO.File]::ReadAllText($fixture.HistoryPath)
        $newEntry = ($old -split '(?m)(?=^### )', 2)[1].
            Replace('2026-09-27T10:00:00Z', '2026-10-21T12:30:00Z').
            Replace('External Researcher', 'New Researcher').Replace('external-agent', 'new-agent')
        Add-Content -LiteralPath $fixture.HistoryPath -Value $newEntry -Encoding utf8NoBOM
        $rewrite = Invoke-Ledger -SquadRoot $fixture.Root -Write
        $rewrite.ExitCode | Should -Be 0 -Because $rewrite.Output
        $ledger = [System.IO.File]::ReadAllText((Join-Path $fixture.Root 'consumption.md'))
        $ledger | Should -Match '\|\s*researcher\s*\|\s*External Researcher\s*\|\s*Squad Connector\s*\|[^\r\n]*\|\s*extended\s*\|'
        $ledger | Should -Match '\|\s*researcher\s*\|\s*New Researcher\s*\|\s*Squad Connector\s*\|[^\r\n]*\|\s*fast\s*\|'
        (Invoke-Ledger -SquadRoot $fixture.Root -Check).ExitCode | Should -Be 0
    }

    It 'CONN-34 rejects an archived <Mutation> in state assurance and every calculator mode' -ForEach @(
        @{ Mutation = 'retry string' }, @{ Mutation = 'retry numeric string' }, @{ Mutation = 'retry negative' },
        @{ Mutation = 'retry boolean' }, @{ Mutation = 'retry overflow' }, @{ Mutation = 'deadline string' },
        @{ Mutation = 'deadline zero' }, @{ Mutation = 'deadline fraction' }
    ) {
        $fixture = New-ConnectorLedgerRoot
        (Invoke-Ledger -SquadRoot $fixture.Root -Write).ExitCode | Should -Be 0
        Save-LedgerRetirement $fixture $Mutation
        Change-LedgerBinding $fixture
        (Get-SquadStateModel -SquadRoot $fixture.Root).ConnectorRetirementIssues.Count | Should -BeGreaterThan 0
        $protected = @('consumption.md', 'state.json', 'history/Squad Connector.md')
        $before = @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash })
        foreach ($options in @(@{}, @{ Format = 'json' }, @{ Write = $true }, @{ Check = $true })) {
            $result = Invoke-Ledger -SquadRoot $fixture.Root @options
            $result.ExitCode | Should -Be 1 -Because $result.Output
        }
        @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash }) | Should -Be $before
    }

    It 'CONN-34 rejects duplicate retirement authority when Active=<Active>' -ForEach @(
        @{ Active = $true }, @{ Active = $false }
    ) {
        $fixture = New-ConnectorLedgerRoot
        (Invoke-Ledger -SquadRoot $fixture.Root -Write).ExitCode | Should -Be 0
        Save-LedgerRetirement $fixture
        Save-LedgerRetirement $fixture -RetiredAt '2026-10-21T13:00:00Z'
        if (-not $Active) { Change-LedgerBinding $fixture }
        $model = Get-SquadStateModel -SquadRoot $fixture.Root
        $model.ConnectorRetirementIssues | Should -Not -BeNullOrEmpty
        $model.ConnectorRetirementIssues -join ',' | Should -Match 'duplicate:history-authority'
        $protected = @('consumption.md', 'state.json', 'history/Squad Connector.md')
        $before = @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash })
        foreach ($options in @(@{}, @{ Format = 'json' }, @{ Write = $true }, @{ Check = $true })) {
            (Invoke-Ledger -SquadRoot $fixture.Root @options).ExitCode | Should -Be 1
        }
        @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash }) | Should -Be $before
    }

    It 'CONN-34 rejects a malformed <Field> in the active manifest too' -ForEach @(
        @{ Field = 'retryCapDefault' }, @{ Field = 'deadlineMinutesDefault' }
    ) {
        $fixture = New-ConnectorLedgerRoot
        (Invoke-Ledger -SquadRoot $fixture.Root -Write).ExitCode | Should -Be 0
        $fixture.Manifest[$Field] = 'invalid'
        $fixture.Manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fixture.ManifestPath
        (Get-SquadStateModel -SquadRoot $fixture.Root).ConnectorBindingIssues.Count | Should -BeGreaterThan 0
        $result = Invoke-Ledger -SquadRoot $fixture.Root -Write
        $result.ExitCode | Should -Be 1 -Because $result.Output
    }

    It 'CONN-34 permits disjoint retirement records after reuse of a binding id' {
        $fixture = New-ConnectorLedgerRoot
        Save-LedgerRetirement $fixture
        Change-LedgerBinding $fixture 'rebind'
        $old = [System.IO.File]::ReadAllText($fixture.HistoryPath)
        $newEntry = ($old -split '(?m)(?=^### )', 2)[1].
            Replace('2026-09-27T10:00:00Z', '2026-10-21T12:30:00Z').
            Replace('External Researcher', 'New Researcher').Replace('external-agent', 'new-agent')
        $newTitle = [regex]::Match($newEntry, '^###[ \t]+([^\r\n]+)').Groups[1].Value.Trim()
        Add-Content -LiteralPath $fixture.HistoryPath -Value $newEntry -Encoding utf8NoBOM
        $fixture.Manifest = Get-Content -LiteralPath $fixture.ManifestPath -Raw | ConvertFrom-Json -AsHashtable
        Save-LedgerRetirement $fixture -HistoryEntries @($newTitle) -RetiredAt '2026-10-21T13:00:00Z'
        Change-LedgerBinding $fixture

        $model = Get-SquadStateModel -SquadRoot $fixture.Root
        $model.ConnectorRetirementIssues | Should -BeNullOrEmpty
        $model.ConnectorRetirements.Count | Should -Be 2
        $model.ConnectorHistoryIssues | Should -BeNullOrEmpty
        $model.ConnectorHistoryIdentities.Count | Should -Be 2
        $rewrite = Invoke-Ledger -SquadRoot $fixture.Root -Write
        $rewrite.ExitCode | Should -Be 0 -Because $rewrite.Output
        $ledger = [System.IO.File]::ReadAllText((Join-Path $fixture.Root 'consumption.md'))
        $ledger | Should -Match '\|\s*researcher\s*\|\s*External Researcher\s*\|\s*Squad Connector\s*\|[^\r\n]*\|\s*extended\s*\|'
        $ledger | Should -Match '\|\s*researcher\s*\|\s*New Researcher\s*\|\s*Squad Connector\s*\|[^\r\n]*\|\s*fast\s*\|'
        (Invoke-Ledger -SquadRoot $fixture.Root -Check).ExitCode | Should -Be 0
    }

    It 'CONN-35 rejects <Marker> metadata without the fixed bullet prefix, even with a matching active binding' -ForEach @(
        @{ Marker = 'External provenance' }, @{ Marker = 'Verification' }, @{ Marker = 'External-unmetered' }
    ) {
        $fixture = New-ConnectorLedgerRoot
        (Invoke-Ledger -SquadRoot $fixture.Root -Write).ExitCode | Should -Be 0
        $history = [System.IO.File]::ReadAllText($fixture.HistoryPath).Replace("* ${Marker}:", "${Marker}:")
        Set-Content -LiteralPath $fixture.HistoryPath -Value $history -NoNewline
        (Get-SquadStateModel -SquadRoot $fixture.Root).ConnectorHistoryIssues.Count | Should -BeGreaterThan 0
        $protected = @('consumption.md', 'state.json', 'history/Squad Connector.md')
        $before = @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash })
        foreach ($options in @(@{}, @{ Format = 'json' }, @{ Write = $true }, @{ Check = $true })) {
            (Invoke-Ledger -SquadRoot $fixture.Root @options).ExitCode | Should -Be 1
        }
        @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash }) | Should -Be $before
    }

    It 'CONN-36 rejects missing <Marker> for <RoleMode> history without changing persisted files' -ForEach @(
        @{ Marker = 'External provenance'; RoleMode = 'replace' },
        @{ Marker = 'Verification'; RoleMode = 'replace' },
        @{ Marker = 'External-unmetered'; RoleMode = 'replace' },
        @{ Marker = 'External provenance'; RoleMode = 'add' },
        @{ Marker = 'Verification'; RoleMode = 'add' },
        @{ Marker = 'External-unmetered'; RoleMode = 'add' },
        @{ Marker = 'External provenance'; RoleMode = 'legacy' },
        @{ Marker = 'Verification'; RoleMode = 'legacy' },
        @{ Marker = 'External-unmetered'; RoleMode = 'legacy' }
    ) {
        $fixture = New-ConnectorLedgerRoot -RoleMode $(if ($RoleMode -eq 'add') { 'add' } else { 'replace' })
        if ($RoleMode -eq 'legacy') {
            Change-LedgerBinding $fixture
            $legacy = [System.IO.File]::ReadAllText($fixture.HistoryPath).Replace('binding=external-research', 'binding=legacy-1.0')
            [System.IO.File]::WriteAllText($fixture.HistoryPath, $legacy)
        }
        $positive = Invoke-Ledger -SquadRoot $fixture.Root -Write
        $positive.ExitCode | Should -Be 0 -Because $positive.Output
        $history = [System.IO.File]::ReadAllText($fixture.HistoryPath) -replace "(?m)^\* ${Marker}:[^\r\n]*\r?\n", ''
        [System.IO.File]::WriteAllText($fixture.HistoryPath, $history)
        (Get-SquadStateModel -SquadRoot $fixture.Root).ConnectorHistoryIssues.Count | Should -BeGreaterThan 0
        $protected = @('consumption.md', 'state.json', 'history/Squad Connector.md')
        $before = @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash })
        foreach ($options in @(@{}, @{ Format = 'json' }, @{ Write = $true }, @{ Check = $true })) {
            $result = Invoke-Ledger -SquadRoot $fixture.Root @options
            $result.ExitCode | Should -Be 1 -Because $result.Output
            $result.Output | Should -Match ([regex]::Escape($Marker))
        }
        @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash }) | Should -Be $before
    }

    It 'CONN-36 rejects an empty <Marker> value rather than falling back to the roster' -ForEach @(
        @{ Marker = 'External provenance' }, @{ Marker = 'Verification' }, @{ Marker = 'External-unmetered' }
    ) {
        $fixture = New-ConnectorLedgerRoot
        (Invoke-Ledger -SquadRoot $fixture.Root -Write).ExitCode | Should -Be 0
        $history = [System.IO.File]::ReadAllText($fixture.HistoryPath) -replace "(?m)^(\* ${Marker}:)[^\r\n]*", '$1   '
        [System.IO.File]::WriteAllText($fixture.HistoryPath, $history)
        foreach ($options in @(@{}, @{ Format = 'json' }, @{ Write = $true }, @{ Check = $true })) {
            $result = Invoke-Ledger -SquadRoot $fixture.Root @options
            $result.ExitCode | Should -Be 1 -Because $result.Output
        }
    }

    It 'CONN-36 rejects missing provenance after <RoleMode> <Change> without losing valid retired identity' -ForEach @(
        @{ RoleMode = 'replace'; Change = 'unbind' }, @{ RoleMode = 'replace'; Change = 'rebind' },
        @{ RoleMode = 'add'; Change = 'unbind' }, @{ RoleMode = 'add'; Change = 'rebind' }
    ) {
        $fixture = New-ConnectorLedgerRoot -RoleMode $RoleMode
        (Invoke-Ledger -SquadRoot $fixture.Root -Write).ExitCode | Should -Be 0
        Save-LedgerRetirement $fixture
        Change-LedgerBinding $fixture $Change
        $positive = Invoke-Ledger -SquadRoot $fixture.Root -Write
        $positive.ExitCode | Should -Be 0 -Because $positive.Output
        $history = [System.IO.File]::ReadAllText($fixture.HistoryPath) -replace '(?m)^\* External provenance:[^\r\n]*\r?\n', ''
        [System.IO.File]::WriteAllText($fixture.HistoryPath, $history)
        $protected = @('consumption.md', 'state.json', 'history/Squad Connector.md')
        $before = @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash })
        foreach ($options in @(@{}, @{ Format = 'json' }, @{ Write = $true }, @{ Check = $true })) {
            $result = Invoke-Ledger -SquadRoot $fixture.Root @options
            $result.ExitCode | Should -Be 1 -Because $result.Output
            $result.Output | Should -Match 'External provenance'
        }
        @($protected | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $fixture.Root $_)).Hash }) | Should -Be $before
    }

    It 'CONN-36 validates required metadata even when its consumption block is missing' {
        $fixture = New-ConnectorLedgerRoot
        $history = [System.IO.File]::ReadAllText($fixture.HistoryPath) -replace '(?m)^\* External provenance:[^\r\n]*\r?\n', ''
        $history = $history -replace '(?s)\r?\n#### Consumption.*', ''
        [System.IO.File]::WriteAllText($fixture.HistoryPath, $history)
        foreach ($options in @(@{}, @{ Format = 'json' }, @{ Write = $true }, @{ Check = $true })) {
            $result = Invoke-Ledger -SquadRoot $fixture.Root @options
            $result.ExitCode | Should -Be 1 -Because $result.Output
            $result.Output | Should -Match 'External provenance'
        }
    }

    It 'CONN-36 never treats an appended valid entry as authority to ignore earlier missing provenance' {
        $fixture = New-ConnectorLedgerRoot
        (Invoke-Ledger -SquadRoot $fixture.Root -Write).ExitCode | Should -Be 0
        $original = [System.IO.File]::ReadAllText($fixture.HistoryPath)
        $bad = $original -replace '(?m)^\* External provenance:[^\r\n]*\r?\n', ''
        $newEntry = ($original -split '(?m)(?=^### )', 2)[1].Replace('2026-09-27T10:00:00Z', '2026-10-21T21:00:00Z')
        [System.IO.File]::WriteAllText($fixture.HistoryPath, $bad + "`n" + $newEntry)
        $before = (Get-FileHash -LiteralPath $fixture.HistoryPath).Hash
        foreach ($options in @(@{}, @{ Format = 'json' }, @{ Write = $true }, @{ Check = $true })) {
            $result = Invoke-Ledger -SquadRoot $fixture.Root @options
            $result.ExitCode | Should -Be 1 -Because $result.Output
            $result.Output | Should -Match 'External provenance'
        }
        (Get-FileHash -LiteralPath $fixture.HistoryPath).Hash | Should -Be $before
    }

    It 'refuses <Mutation> retirement evidence without rewriting ledger or state' -ForEach @(
        @{ Mutation = 'unconfirmed' }, @{ Mutation = 'missing confirmation' }, @{ Mutation = 'missing snapshot' },
        @{ Mutation = 'wrong manifest' }, @{ Mutation = 'unknown field' }, @{ Mutation = 'invalid prior target' },
        @{ Mutation = 'postdated entry' }, @{ Mutation = 'unlisted entry' }, @{ Mutation = 'wrong member' },
        @{ Mutation = 'wrong verification' }, @{ Mutation = 'wrong unmetered marker' }, @{ Mutation = 'invalid active binding' }
    ) {
        $fixture = New-ConnectorLedgerRoot
        (Invoke-Ledger -SquadRoot $fixture.Root -Write).ExitCode | Should -Be 0
        Save-LedgerRetirement $fixture $Mutation
        Change-LedgerBinding $fixture $(if ($Mutation -eq 'invalid active binding') { 'rebind' } else { 'unbind' })
        $history = [System.IO.File]::ReadAllText($fixture.HistoryPath)
        switch ($Mutation) {
            'unlisted entry' { $history = $history.Replace('2026-09-27T10:00:00Z', '2026-10-21T13:00:00Z') }
            'wrong member' { $history = $history.Replace('* Member Name: External Researcher', '* Member Name: Unknown Member') }
            'wrong verification' { $history = $history.Replace('* Verification: external, unverified', '* Verification: approved') }
            'wrong unmetered marker' { $history = $history.Replace('External-unmetered: connector=external-agent', 'External-unmetered: connector=other') }
            'invalid active binding' {
                $teamPath = Join-Path $fixture.Root 'team.md'
                Set-Content -LiteralPath $teamPath -Value ([System.IO.File]::ReadAllText($teamPath).Replace('role:researcher/Alpha', 'role:researcher/Missing'))
            }
        }
        Set-Content -LiteralPath $fixture.HistoryPath -Value $history -NoNewline
        $ledgerPath = Join-Path $fixture.Root 'consumption.md'
        $statePath = Join-Path $fixture.Root 'state.json'
        $ledgerHash = (Get-FileHash -LiteralPath $ledgerPath).Hash
        $stateHash = (Get-FileHash -LiteralPath $statePath).Hash
        $rewrite = Invoke-Ledger -SquadRoot $fixture.Root -Write
        $rewrite.ExitCode | Should -Be 1 -Because $rewrite.Output
        (Get-FileHash -LiteralPath $ledgerPath).Hash | Should -Be $ledgerHash
        (Get-FileHash -LiteralPath $statePath).Hash | Should -Be $stateHash
    }
}

# P01b / C2: the history-identity guard. consumption.md's own '### Derivation'
# block records, per history file, the ordered short-hash identities of that
# file's '###' dispatch-entry headings at the time the ledger was last written.
# -Check (and render mode, covered separately below) must treat the recorded
# list as failing unless it is an ordered prefix of history/'s current list --
# an overwritten or removed entry fails even at the same recorded count, a
# plain append still passes, and an older-format ledger recording no
# identities at all only warns. See tests/fixtures/ledger-identity-*/.
Describe 'Measure-SquadLedger C2 history-identity guard' {
    BeforeAll {
        $script:AppendRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-identity-append'
        $script:OverwriteRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-identity-overwrite'
        $script:RemovalRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-identity-removal'
        $script:LegacyRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-identity-legacy'
    }

    It 'a plain append (recorded identities are a prefix of current) passes -Check cleanly' {
        $result = Invoke-Ledger -SquadRoot $script:AppendRoot -Check
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'PASS'
        $result.Output | Should -Not -Match 'overwritten or reordered'
        $result.Output | Should -Not -Match 'entry was removed'
    }

    It 'a same-count overwrite (an entry''s heading text changed in place) fails -Check, naming the file' {
        $result = Invoke-Ledger -SquadRoot $script:OverwriteRoot -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "'Squad Researcher\.md'.*overwritten or reordered"
    }

    It 'a removal (an entry recorded in consumption.md no longer exists in history/) fails -Check, naming the file' {
        $result = Invoke-Ledger -SquadRoot $script:RemovalRoot -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "'Squad Researcher\.md'.*entry was removed"
    }

    It 'an older-format ledger recording no identities at all only warns, and still passes -Check' {
        $result = Invoke-Ledger -SquadRoot $script:LegacyRoot -Check
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'older-format ledger'
        $result.Output | Should -Match 'PASS'
    }

    It 'render mode refuses to print a new fragment while the identity guard already fails (overwrite root)' {
        $result = Invoke-Ledger -SquadRoot $script:OverwriteRoot
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'overwritten or reordered'
    }

    It 'render mode refuses to print a new fragment while the identity guard already fails (removal root)' {
        $result = Invoke-Ledger -SquadRoot $script:RemovalRoot
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'entry was removed'
    }

    It 'render mode still prints normally over a passing (plain-append) history' {
        $result = Invoke-Ledger -SquadRoot $script:AppendRoot
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match '^## Attribution'
    }
}

# F3 review-fix / C2 post-write hardening: the Scribe's own post-write
# self-check always pairs `-Check` with `-ExpectedHistoryCounts` (see
# scribe-procedure.md's Write-Completeness Self-Check Step 3). In that
# combination a Derivation missing identities -- entirely, or for only some of
# the touched history files (a partial paste) -- must FAIL rather than only
# warn, because that call always follows a fresh write: a missing or partial
# paste there is this run's own defect, never a genuinely old ledger. A plain
# `-Check` (no `-ExpectedHistoryCounts`) keeps the C2 warn-only legacy
# behavior unchanged, and a fully and correctly recorded Derivation passes
# cleanly even in post-write mode. See tests/fixtures/ledger-identity-missing-
# postwrite/, ledger-identity-partial/, and ledger-identity-full-postwrite/.
Describe 'Measure-SquadLedger C2 history-identity guard: post-write (-Check + -ExpectedHistoryCounts) hardening' {
    BeforeAll {
        $script:MissingPostWriteRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-identity-missing-postwrite'
        $script:PartialRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-identity-partial'
        $script:FullPostWriteRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-identity-full-postwrite'
    }

    It 'a Derivation missing every identity, without -ExpectedHistoryCounts, only warns and still passes -Check' {
        $result = Invoke-Ledger -SquadRoot $script:MissingPostWriteRoot -Check
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'older-format ledger'
        $result.Output | Should -Match 'PASS'
    }

    It 'a Derivation missing every identity, with -Check -ExpectedHistoryCounts, FAILS naming the paste instruction' {
        $result = Invoke-Ledger -SquadRoot $script:MissingPostWriteRoot -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1 }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'FAIL'
        $result.Output | Should -Match 'rerun this helper with -Write, which writes identity lines for every history file'
    }

    It 'a partial paste (one file''s identities recorded, another file''s missing entirely), without -ExpectedHistoryCounts, only warns and still passes -Check' {
        $result = Invoke-Ledger -SquadRoot $script:PartialRoot -Check
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match "'Squad Developer\.md'"
        $result.Output | Should -Match 'PASS'
    }

    It 'a partial paste, with -Check -ExpectedHistoryCounts, FAILS naming the file missing identities' {
        $result = Invoke-Ledger -SquadRoot $script:PartialRoot -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Developer' = 1 }
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'FAIL'
        $result.Output | Should -Match "'Squad Developer\.md'.*partial paste"
        $result.Output | Should -Not -Match "'Squad Researcher\.md'.*partial paste"
    }

    It 'a fully and correctly recorded Derivation passes cleanly even with -Check -ExpectedHistoryCounts' {
        $result = Invoke-Ledger -SquadRoot $script:FullPostWriteRoot -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1 }
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'PASS'
        $result.Output | Should -Not -Match 'older-format ledger'
        $result.Output | Should -Not -Match 'partial paste'
    }
}

# P01 / C3: the ledger<->state.json currentRun divergence check. -Check must
# fail when state.json's currentRun.estCostUsd/estCreditsTotal diverge from
# this script's own derived totals beyond the existing float tolerance, naming
# both values and the delta; must fail (naming the reason) when history holds
# consumption blocks but state.json is missing or unparseable; and must log a
# `not-applicable: federation root` line -- never a silent pass, never a
# failure -- when the squad root carries federation.md. See
# tests/fixtures/ledger-state-*/ and ledger-federation-root/.
Describe 'Measure-SquadLedger C3 ledger-vs-state.json currentRun divergence check' {
    BeforeAll {
        $script:DivergenceRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-state-divergence'
        $script:MissingStateRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-state-missing'
        $script:UnparseableStateRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-state-unparseable'
        $script:FederationRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-federation-root'
    }

    It 'fails and names both estCostUsd values and the delta when state.json diverges from the derived total' {
        $result = Invoke-Ledger -SquadRoot $script:DivergenceRoot -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'estCostUsd -- ledger derives 0\.3000, currentRun says 0\.9000 \(delta 0\.6000'
    }

    It 'fails and names both estCreditsTotal values and the delta when state.json diverges from the derived total' {
        $result = Invoke-Ledger -SquadRoot $script:DivergenceRoot -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'estCreditsTotal -- ledger derives 30\.00, currentRun says 90\.00 \(delta 60\.00'
    }

    It 'fails, naming the reason, when history holds consumption blocks but state.json does not exist' {
        $result = Invoke-Ledger -SquadRoot $script:MissingStateRoot -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "currentRun cost/credits could not be read \(state\.json not found"
    }

    It 'fails, naming the reason, when history holds consumption blocks but state.json is unparseable' {
        $result = Invoke-Ledger -SquadRoot $script:UnparseableStateRoot -Check
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "currentRun cost/credits could not be read \(state\.json at '.*' failed to parse"
    }

    It 'logs not-applicable (never a silent pass, never a failure) on a federation root, regardless of state.json divergence' {
        $result = Invoke-Ledger -SquadRoot $script:FederationRoot -Check
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'not-applicable: federation root'
        $result.Output | Should -Match 'PASS'
    }

    It 'passes cleanly when the ledger and state.json currentRun agree (the plain-append C2 fixture doubles as the C3 match case)' {
        $matchRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-identity-append'
        $result = Invoke-Ledger -SquadRoot $matchRoot -Check
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Not -Match 'divergence'
    }
}

# ---------------------------------------------------------------------------
# U1 (Amendment 3 §2, tasks P03-T06/P03-T07): -EmitBaseline/-BaselinePath and
# caller-named -ProtectedPath/-AllowedWritePath verification. Every baseline
# JSON below is generated at test time into $TestDrive (never the repo or a
# squad root); the squad root each test mutates is always a fresh $TestDrive
# copy of the known-good scribe-benchmark 'applied' fixture (New-BaselineTestRootLocal).
# See .copilot-tracking/squad/members/routing-performance/changes/2026-09-29-u1-ledger-baseline-tooling.md.
# ---------------------------------------------------------------------------
Describe 'Measure-SquadLedger -EmitBaseline / -BaselinePath (U1 item 1)' {
    It 'emits a baseline JSON and a sibling .files/ directory outside the squad root, and an unmutated -BaselinePath -Check round-trip passes' {
        $root = New-BaselineTestRootLocal
        $baselinePath = Join-Path $TestDrive 'baseline-roundtrip.json'

        $emit = Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath
        $emit.ExitCode | Should -Be 0
        Test-Path -LiteralPath $baselinePath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath "$baselinePath.files" -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path "$baselinePath.files" 'history\Squad Researcher.md') -PathType Leaf | Should -BeTrue

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $check.Output | Should -Match 'PASS'
    }

    It 'the emitted baseline JSON never records state.json or consumption.md (both are excluded from append-only/protected scope by design)' {
        $root = New-BaselineTestRootLocal
        $baselinePath = Join-Path $TestDrive 'baseline-scope.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath).ExitCode | Should -Be 0

        $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
        @($baseline.appendOnly.PSObject.Properties.Name) | Should -Not -Contain 'state.json'
        @($baseline.appendOnly.PSObject.Properties.Name) | Should -Not -Contain 'consumption.md'
    }

    It 'FAILs -BaselinePath -Check when an append-only history file shrinks (a 48-byte-style truncation to 8 bytes)' {
        $root = New-BaselineTestRootLocal
        $baselinePath = Join-Path $TestDrive 'baseline-truncate.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath).ExitCode | Should -Be 0

        $historyFile = Join-Path $root 'history\Squad Researcher.md'
        $bytes = [System.IO.File]::ReadAllBytes($historyFile)
        [System.IO.File]::WriteAllBytes($historyFile, $bytes[0..7])

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check
        $check.ExitCode | Should -Be 1
        $check.Output | Should -Match 'Baseline:.*shrank'
    }

    It 'FAILs -BaselinePath -Check when an append-only history file''s original bytes are edited in place (a prefix edit, not only an append)' {
        $root = New-BaselineTestRootLocal
        $baselinePath = Join-Path $TestDrive 'baseline-prefix.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath).ExitCode | Should -Be 0

        $historyFile = Join-Path $root 'history\Squad Researcher.md'
        $content = Get-Content -LiteralPath $historyFile -Raw
        $edited = $content -replace 'Squad Researcher', 'SQUAD RESEARCHER'
        Set-Content -LiteralPath $historyFile -Value $edited -NoNewline

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check
        $check.ExitCode | Should -Be 1
        $check.Output | Should -Match 'Baseline:.*prefix edit'
    }

    It 'FAILs -BaselinePath -Check when a caller-named protected artifact changes and is not in the allowed-write set' {
        $root = New-BaselineTestRootLocal
        $protectedRel = 'research/2026-09-27-fixture-topic.md'
        $baselinePath = Join-Path $TestDrive 'baseline-protected.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath -ProtectedPath $protectedRel).ExitCode | Should -Be 0

        Add-Content -LiteralPath (Join-Path $root 'research\2026-09-27-fixture-topic.md') -Value "`nUnauthorized edit."

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check -ProtectedPath $protectedRel
        $check.ExitCode | Should -Be 1
        $check.Output | Should -Match 'Baseline:.*Protected artifact changed'
    }

    It 'does NOT fail a protected-artifact change when the path is named in -AllowedWritePath (a concurrent Role(N+1) write, or an authorized correction)' {
        $root = New-BaselineTestRootLocal
        $protectedRel = 'research/2026-09-27-fixture-topic.md'
        $baselinePath = Join-Path $TestDrive 'baseline-allowed.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath -ProtectedPath $protectedRel).ExitCode | Should -Be 0

        Add-Content -LiteralPath (Join-Path $root 'research\2026-09-27-fixture-topic.md') -Value "`nRole(N+1) concurrent write."

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check -ProtectedPath $protectedRel -AllowedWritePath $protectedRel
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $check.Output | Should -Not -Match 'Protected artifact changed'
    }

    # Review fix (coordinator finding, fail-open): the protected set verified at
    # -Check time must be the baseline's own recorded `protected` map, not only
    # whatever -ProtectedPath the caller happens to re-supply -- a verifier that
    # omits -ProtectedPath must still catch a change to an artifact the matching
    # -EmitBaseline call protected.
    It 'FAILs -BaselinePath -Check on a baseline-recorded protected artifact''s change even when -ProtectedPath is NOT re-supplied at check time' {
        $root = New-BaselineTestRootLocal
        $protectedRel = 'research/2026-09-27-fixture-topic.md'
        $baselinePath = Join-Path $TestDrive 'baseline-protected-omitted.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath -ProtectedPath $protectedRel).ExitCode | Should -Be 0

        Add-Content -LiteralPath (Join-Path $root 'research\2026-09-27-fixture-topic.md') -Value "`nUnauthorized edit, no -ProtectedPath at check time."

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check
        $check.ExitCode | Should -Be 1
        $check.Output | Should -Match 'Baseline:.*Protected artifact changed'
    }

    It 'does NOT fail a baseline-recorded protected artifact''s change when the path is named in -AllowedWritePath, even without re-supplying -ProtectedPath' {
        $root = New-BaselineTestRootLocal
        $protectedRel = 'research/2026-09-27-fixture-topic.md'
        $baselinePath = Join-Path $TestDrive 'baseline-protected-allowed-omitted.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath -ProtectedPath $protectedRel).ExitCode | Should -Be 0

        Add-Content -LiteralPath (Join-Path $root 'research\2026-09-27-fixture-topic.md') -Value "`nRole(N+1) concurrent write, no -ProtectedPath at check time."

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check -AllowedWritePath $protectedRel
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $check.Output | Should -Not -Match 'Protected artifact changed'
    }

    It 'FAILs -BaselinePath -Check when a baseline-recorded protected artifact is deleted after baseline, even without re-supplying -ProtectedPath' {
        $root = New-BaselineTestRootLocal
        $protectedRel = 'research/2026-09-27-fixture-topic.md'
        $baselinePath = Join-Path $TestDrive 'baseline-protected-deleted-omitted.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath -ProtectedPath $protectedRel).ExitCode | Should -Be 0

        Remove-Item -LiteralPath (Join-Path $root 'research\2026-09-27-fixture-topic.md') -Force

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check
        $check.ExitCode | Should -Be 1
        $check.Output | Should -Match 'Baseline:.*Protected artifact missing'
    }

    It 'does NOT fail a state.json / consumption.md rewrite (both are outside baseline scope by design)' {
        $root = New-BaselineTestRootLocal
        $baselinePath = Join-Path $TestDrive 'baseline-replace.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath).ExitCode | Should -Be 0

        # A genuine rewrite -- same currentRun numbers (so C3 keeps agreeing), only
        # the "updated" timestamp changes, exactly as the Scribe does every stage.
        $statePath = Join-Path $root 'state.json'
        ((Get-Content -LiteralPath $statePath -Raw) -replace '"updated":\s*"[^"]*"', '"updated": "2026-09-27T12:00:00Z"') |
            Set-Content -LiteralPath $statePath -NoNewline
        Add-Content -LiteralPath (Join-Path $root 'consumption.md') -Value "`n<!-- rewritten by Scribe -->"

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check
        $check.ExitCode | Should -Be 0 -Because $check.Output
        $check.Output | Should -Match 'PASS'
    }

    It 'FAILs -BaselinePath -Check when the baseline file itself is missing' {
        $root = New-BaselineTestRootLocal
        $missingBaseline = Join-Path $TestDrive 'does-not-exist.json'
        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $missingBaseline -Check
        $check.ExitCode | Should -Be 1
        $check.Output | Should -Match "Baseline file '.*' not found"
    }

    It 'refuses (throws) an -EmitBaseline / -BaselinePath that resolves under a .copilot-tracking/squad tree' {
        $root = New-BaselineTestRootLocal
        $badPath = Join-Path $TestDrive '.copilot-tracking\squad\baseline.json'
        $result = Invoke-Ledger -SquadRoot $root -EmitBaseline $badPath
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match '\.copilot-tracking/squad'
    }

    It 'refuses (throws) naming a replace-semantics ledger file as -ProtectedPath' {
        $root = New-BaselineTestRootLocal
        foreach ($name in @('state.json', 'consumption.md', 'consumption-sessions.json')) {
            $result = Invoke-Ledger -SquadRoot $root -EmitBaseline (Join-Path $TestDrive "baseline-guard-$($name.Replace('.', '-')).json") -ProtectedPath $name
            $result.ExitCode | Should -Not -Be 0
            $result.Output | Should -Match 'must not name'
        }
    }
}

# ---------------------------------------------------------------------------
# U1 (Amendment 3 §2 item 2): -LookupRunId/-LookupTopic/-LookupStage/-LookupSlot
# key-lookup mode. A model-free existence check for resume logic: a literal
# substring search across history/*.md for the composed
# "{RunId}::{Topic}::{Stage}::{Slot}" key (see the script's own comment-help).
# ---------------------------------------------------------------------------
Describe 'Measure-SquadLedger -LookupRunId/-LookupTopic/-LookupStage/-LookupSlot (U1 item 2: key-lookup mode)' {
    BeforeAll {
        $script:LookupRoot = Join-Path $script:FixtureRoot 'applied'
    }

    It 'reports MISSING (exit 1) for a key that appears in no history/*.md file' {
        $result = Invoke-Ledger -SquadRoot $script:LookupRoot -LookupRunId 'rp-fixture-01' -LookupTopic 'no-such-topic' -LookupStage 'research' -LookupSlot '1'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'MISSING'
    }

    It 'reports EXISTS (exit 0) once the composed key is embedded verbatim in a history entry' {
        $root = Join-Path $TestDrive 'lookup-exists'
        Copy-Item -LiteralPath $script:LookupRoot -Destination $root -Recurse
        Add-Content -LiteralPath (Join-Path $root 'history\Squad Researcher.md') -Value "`nLedgerLookupKey: rp-lookup-01::topic-x::research::1"

        $result = Invoke-Ledger -SquadRoot $root -LookupRunId 'rp-lookup-01' -LookupTopic 'topic-x' -LookupStage 'research' -LookupSlot '1'
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'EXISTS'
        $result.Output | Should -Match 'Squad Researcher\.md'
    }

    It 'emits a structured exists/missing object with -Format json' {
        $root = Join-Path $TestDrive 'lookup-json'
        Copy-Item -LiteralPath $script:LookupRoot -Destination $root -Recurse
        Add-Content -LiteralPath (Join-Path $root 'history\Squad Researcher.md') -Value "`nLedgerLookupKey: rp-lookup-02::topic-y::research::2"

        $result = Invoke-Ledger -SquadRoot $root -LookupRunId 'rp-lookup-02' -LookupTopic 'topic-y' -LookupStage 'research' -LookupSlot '2' -Format json
        $result.ExitCode | Should -Be 0
        $parsed = $result.Output | ConvertFrom-Json
        $parsed.exists | Should -BeTrue
        $parsed.key | Should -Be 'rp-lookup-02::topic-y::research::2'
    }

    It 'throws when only some of the four -Lookup* parameters are supplied' {
        $result = Invoke-Ledger -SquadRoot $script:LookupRoot -LookupRunId 'rp-fixture-01' -LookupTopic 'partial'
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'must be supplied together'
    }
}

# ---------------------------------------------------------------------------
# U1 (Amendment 3 §2 items 3 and 4): baseline-scoped WARN-vs-FAIL for a
# malformed or illegal-model_source consumption block, and the no-throw rate
# fallback for a block whose priced_as/model_tier don't resolve. Static
# fixture: tests/fixtures/ledger-baseline/root/history/Legacy Agent.md carries
# five pre-baseline blocks (two orphaned headings -- a single-backtick fence
# and a markdown table pasted in place of one --, an illegal model_source, a
# whitespace-padded priced_as, and one fully well-formed block); the tests
# below baseline a fresh copy of it, then append additional post-baseline
# blocks at test time.
# ---------------------------------------------------------------------------
Describe 'Measure-SquadLedger baseline-scoped malformed/illegal-model_source WARN-vs-FAIL and no-throw rate fallback (U1 items 3 and 4)' {
    BeforeAll {
        $script:LegacyFixtureRoot = Join-Path -Path $script:FixtureRoot -ChildPath '..' -AdditionalChildPath 'ledger-baseline', 'root'

        function New-LegacyTestRootLocal {
            $dest = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath $script:LegacyFixtureRoot -Destination $dest -Recurse
            $dest
        }

        $script:PostBaselineWellFormedBlock = @'


### 2026-09-25T09:00:00Z Post-baseline well-formed consumption block

* Turn: 1
* Request: Post-baseline synthetic entry, well-formed.
* Deliverable: `fixtures/ledger-baseline/post-1.md`
* Outcome: Synthetic.

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "session-inherited",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 1,
  "input_tokens": 100,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 50,
  "basis": "estimated"
}
```
'@

        $script:PostBaselineIllegalModelSourceBlock = @'


### 2026-09-25T09:05:00Z Post-baseline illegal model_source consumption block

* Turn: 1
* Request: Post-baseline synthetic entry with an illegal model_source value.
* Deliverable: `fixtures/ledger-baseline/post-2.md`
* Outcome: Synthetic.

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "session",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 1,
  "input_tokens": 100,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 50,
  "basis": "estimated"
}
```
'@

        $script:PostBaselineUnparseableBlock = @'


### 2026-09-25T09:10:00Z Post-baseline unparseable (bad fence) consumption block

* Turn: 1
* Request: Post-baseline synthetic entry with no fence at all.
* Deliverable: `fixtures/ledger-baseline/post-3.md`
* Outcome: Synthetic.

#### Consumption

model: Claude Sonnet 4.6
'@
    }

    It 'without any -BaselinePath at all, every malformed/illegal shape only WARNs -- "cannot scope, so it never throws"' {
        $root = New-LegacyTestRootLocal
        $result = Invoke-Ledger -SquadRoot $root -Format json
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'bad fence, or non-JSON content'
        $result.Output | Should -Match "illegal model_source 'session'"
        $result.Output | Should -Match "priced_as ' Claude Opus 5 ' only resolves.*after trimming"
        # Still aggregates the three blocks that do resolve (the collapsed-fence
        # block, whose JSON is intact and which only warns since 0.18.1, the
        # trimmed-whitespace block, and the one fully well-formed block): 1 + 1 + 2 = 4.
        ($result.Output | ConvertFrom-Json).total.turns | Should -Be 4.0
        $result.Output | Should -Match 'collapsed code fence'
    }

    It 'with -BaselinePath, the same four pre-baseline (legacy) shapes still only WARN, never FAIL/throw' {
        $root = New-LegacyTestRootLocal
        $baselinePath = Join-Path $TestDrive 'baseline-legacy.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath).ExitCode | Should -Be 0

        $result = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Format json
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'WARN:.*bad fence, or non-JSON content'
        $result.Output | Should -Match "WARN:.*illegal model_source 'session'"
        $result.Output | Should -Match "WARN:.*priced_as ' Claude Opus 5 ' only resolves.*after trimming"
        $result.Output | Should -Match 'pre-baseline/legacy block'
    }

    It 'a post-baseline illegal-model_source block FAILs under -BaselinePath -Check (and throws outside -Check)' {
        $root = New-LegacyTestRootLocal
        $baselinePath = Join-Path $TestDrive 'baseline-post-illegal.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath).ExitCode | Should -Be 0
        Add-Content -LiteralPath (Join-Path $root 'history\Legacy Agent.md') -Value $script:PostBaselineIllegalModelSourceBlock

        $render = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Format json
        $render.ExitCode | Should -Not -Be 0
        $render.Output | Should -Match 'Refusing to compute a ledger'

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check
        $check.ExitCode | Should -Be 1
        $check.Output | Should -Match "Post-baseline block:.*illegal model_source 'session'"
    }

    It 'a post-baseline unparseable (bad fence) block FAILs under -BaselinePath -Check (and throws outside -Check)' {
        $root = New-LegacyTestRootLocal
        $baselinePath = Join-Path $TestDrive 'baseline-post-unparseable.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath).ExitCode | Should -Be 0
        Add-Content -LiteralPath (Join-Path $root 'history\Legacy Agent.md') -Value $script:PostBaselineUnparseableBlock

        $render = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Format json
        $render.ExitCode | Should -Not -Be 0
        $render.Output | Should -Match 'Refusing to compute a ledger'

        $check = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Check
        $check.ExitCode | Should -Be 1
        $check.Output | Should -Match 'Post-baseline block:.*bad fence, or non-JSON content'
    }

    It 'a well-formed post-baseline block passes cleanly with no WARN naming it' {
        $root = New-LegacyTestRootLocal
        $baselinePath = Join-Path $TestDrive 'baseline-post-wellformed.json'
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath).ExitCode | Should -Be 0
        Add-Content -LiteralPath (Join-Path $root 'history\Legacy Agent.md') -Value $script:PostBaselineWellFormedBlock

        $result = Invoke-Ledger -SquadRoot $root -BaselinePath $baselinePath -Format json
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Not -Match 'Post-baseline block'
        # The new block aggregates alongside the three pre-existing resolvable ones
        # (4 turns, the collapsed-fence block included) -- confirm the post-baseline
        # block's own 1 turn is included without any WARN/FAIL naming it.
        ($result.Output | ConvertFrom-Json).total.turns | Should -Be 5.0
    }
}

# ---------------------------------------------------------------------------
# U1 (Amendment 3 §2 item 5): an empty/absent Agent cell in consumption.md's
# Attribution table must never crash Get-AttributionCompositeKeyLocal -- it
# reports a mismatch (a ledger row nothing matches) instead.
# ---------------------------------------------------------------------------
Describe 'Measure-SquadLedger -Check: an empty Agent cell in the Attribution table reports a mismatch, never throws (U1 item 5)' {
    BeforeAll {
        $script:EmptyAgentRoot = Join-Path $TestDrive 'empty-agent-cell'
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $script:EmptyAgentRoot -Recurse

        # Same Primary+Fallback `architect` shape used elsewhere in this file: two
        # rows sharing one Role, disambiguated only by Agent -- exactly the case
        # where Get-AttributionCompositeKeyLocal's lookup is load-bearing, so an
        # empty Agent cell on one row is guaranteed to reach it.
        Add-Content -LiteralPath (Join-Path $script:EmptyAgentRoot 'team.md') -Value "| architect | Zeta | System Architecture Reviewer | ADR Creator | — | runSubagent / task | default | docs/architecture/ |"

        $primaryHistory = @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: System Architecture Reviewer

### 2026-09-27T12:00:00Z Reviewing the fixture-topic design tradeoffs

* Turn: 4
* Request: Review the recommended fixture shape's design tradeoffs.
* Deliverable: `docs/architecture/2026-09-27-design-review.md`
* Outcome: Confirmed the minimal shape.

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "agent-pinned",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 4,
  "input_tokens": 2000,
  "cached_tokens": 8000,
  "cache_write_tokens": 1000,
  "output_tokens": 2500,
  "basis": "estimated"
}
```
'@
        Set-Content -LiteralPath (Join-Path $script:EmptyAgentRoot 'history/System Architecture Reviewer.md') -Value $primaryHistory -NoNewline

        $fallbackHistory = @'
---
description: "Append-only dispatch history for a single squad agent"
---

# History: ADR Creator

### 2026-09-27T13:00:00Z Capturing the fixture-topic decision record

* Turn: 2
* Request: Capture the fixture-topic decision as an ADR.
* Deliverable: `docs/architecture/2026-09-27-decision-record.md`
* Outcome: ADR captured.

#### Consumption

```json
{
  "model": "Claude Opus 5",
  "model_source": "agent-pinned",
  "priced_as": "Claude Opus 5",
  "model_tier": "extended",
  "internal_turns": 2,
  "input_tokens": 1000,
  "cached_tokens": 4000,
  "cache_write_tokens": 500,
  "output_tokens": 1200,
  "basis": "estimated"
}
```
'@
        Set-Content -LiteralPath (Join-Path $script:EmptyAgentRoot 'history/ADR Creator.md') -Value $fallbackHistory -NoNewline

        # Splice the helper's own printed fragment in, exactly like the existing
        # composite-key Describe block above, then blank the ADR Creator row's
        # Agent cell only -- the Role cell, and every other row, stay intact.
        $fragment = (Invoke-Ledger -SquadRoot $script:EmptyAgentRoot -Format markdown).Output.Trim()
        $originalLedger = Get-Content -LiteralPath (Join-Path $script:FixtureRoot 'applied/consumption.md') -Raw
        $h1Line = [regex]::Match($originalLedger, '(?m)^#\s+Squad Consumption Ledger.*$')
        $basisIndex = $originalLedger.IndexOf('> Basis:')
        $head = $originalLedger.Substring(0, $h1Line.Index + $h1Line.Length)
        $tail = $originalLedger.Substring($basisIndex)
        $ledgerContent = "$head`n`n$fragment`n`n$tail"
        $ledgerContent = $ledgerContent -replace '(\|\s*architect\s*\|\s*Zeta\s*\|\s*)ADR Creator(\s*\|)', '$1$2'
        $ledgerPath = Join-Path $script:EmptyAgentRoot 'consumption.md'
        Set-Content -LiteralPath $ledgerPath -Value $ledgerContent -NoNewline
        Sync-LedgerStateLocal -SquadRoot $script:EmptyAgentRoot
    }

    It 'does not throw or crash, and reports a mismatch for the row an empty Agent cell can no longer be matched against' {
        $result = Invoke-Ledger -SquadRoot $script:EmptyAgentRoot -Check
        $result.Output | Should -Not -Match 'Exception'
        $result.Output | Should -Not -Match 'Get-AttributionCompositeKeyLocal'
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "Attribution:.*role 'architect'"
    }
}

Describe 'Measure-SquadLedger prices spelling variants and falls back to the block model' {
    BeforeAll {
        function Initialize-PricingRootLocal {
            param([string]$PricedAs, [string]$Model)
            $dest = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $dest -Recurse
            $historyPath = Join-Path $dest 'history/Squad Researcher.md'
            $raw = Get-Content -LiteralPath $historyPath -Raw
            $raw = $raw.Replace('"priced_as": "Claude Sonnet 4.6"', "`"priced_as`": `"$PricedAs`"").Replace('"model": "Claude Sonnet 4.6"', "`"model`": `"$Model`"")
            Set-Content -LiteralPath $historyPath -Value $raw -NoNewline
            $dest
        }
    }

    It 'prices "claude-sonnet-4.6 (copilot)" at the Claude Sonnet 4.6 row with no tier-fallback warning (a live run wrote "GPT-5.3 Codex" for the "GPT-5.3-Codex" row)' {
        $root = Initialize-PricingRootLocal -PricedAs 'claude-sonnet-4.6 (copilot)' -Model 'Claude Sonnet 4.6'
        $result = Invoke-Ledger -SquadRoot $root -Format json
        ($result.Output | ConvertFrom-Json).total.estCostUsd | Should -Be 0.3171
        $result.Output | Should -Not -Match 'tier fallback'
    }

    It 'prices an unresolvable priced_as at the block''s own model, with a warning, before any tier fallback' {
        $root = Initialize-PricingRootLocal -PricedAs 'Not A Row' -Model 'Claude Sonnet 4.6'
        $result = Invoke-Ledger -SquadRoot $root -Format json
        $result.Output | Should -Match "priced at its recorded model 'Claude Sonnet 4.6'"
        ($result.Output -split '\r?\n' | Where-Object { $_ -notmatch '^(WARNING|AVERTISSEMENT)' }) -join "`n" | ConvertFrom-Json | ForEach-Object { $_.total.estCostUsd } | Should -Be 0.3171
    }
}

Describe 'Measure-SquadLedger -SessionLog replaces completed estimates with exact native role usage' {
    BeforeAll {
        function New-SessionFixtureLocal {
            <#
            .SYNOPSIS
                A repo with the applied fixture as its squad root, plus a fake
                session-state directory whose workspace.yaml points at that repo.
            #>
            param([string]$Member, [string[]]$EventLines, [string]$Fixture = 'applied')
            $repo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
            $squad = Join-Path $repo '.copilot-tracking/squad'
            $root = if ($Member) { Join-Path $squad "members/$Member" } else { $squad }
            New-Item -ItemType Directory -Path (Split-Path -Parent $root) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:FixtureRoot $Fixture) -Destination $root -Recurse

            $copilotHome = Join-Path $repo '_copilot_home'
            $sessionDir = Join-Path $copilotHome 'session-state/sess-0001'
            New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $sessionDir 'workspace.yaml') -Value "id: sess-0001`ncwd: $repo`n"
            Set-Content -LiteralPath (Join-Path $sessionDir 'events.jsonl') -Value ($EventLines -join "`n")
            [pscustomobject]@{ Repo = $repo; Root = $root; Home = $copilotHome; SessionDir = $sessionDir }
        }

        function Invoke-LedgerWithSessionLocal {
            param([string]$Root, [string]$SessionLog, [string]$CopilotHome, [switch]$Write, [string]$Format, [string]$BaselineModel)
            $parts = @("& '$script:LedgerScript' -SquadRoot '$Root' -SessionLog '$SessionLog'")
            if ($Write) { $parts += '-Write' }
            if ($Format) { $parts += "-Format $Format" }
            if ($BaselineModel) { $parts += "-BaselineModel '$BaselineModel'" }
            $command = $parts -join ' '
            if ($CopilotHome) { $command = "`$env:COPILOT_HOME = '$CopilotHome'; $command" }
            $output = & pwsh -NoProfile -Command $command 2>&1 | Out-String
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }

        function New-ExactUsageEventLocal {
            param(
                [string]$AgentId,
                [string]$SourceSessionId,
                [string]$UsageId,
                [string]$Model,
                [long]$FreshInput,
                [long]$Cached,
                [long]$CacheWrite,
                [long]$Output,
                [double]$InputRate,
                [double]$CachedRate,
                [double]$CacheWriteRate,
                [double]$OutputRate,
                [string]$Timestamp
            )
            $details = @(
                @{ tokenType = 'input'; tokenCount = $FreshInput; batchSize = 1000000; costPerBatch = [decimal]$InputRate * [decimal]1e11 }
                @{ tokenType = 'cache_read'; tokenCount = $Cached; batchSize = 1000000; costPerBatch = [decimal]$CachedRate * [decimal]1e11 }
                @{ tokenType = 'cache_write'; tokenCount = $CacheWrite; batchSize = 1000000; costPerBatch = [decimal]$CacheWriteRate * [decimal]1e11 }
                @{ tokenType = 'output'; tokenCount = $Output; batchSize = 1000000; costPerBatch = [decimal]$OutputRate * [decimal]1e11 }
            )
            $nanoAiu = [decimal]0
            foreach ($detail in $details) {
                $nanoAiu += [decimal]$detail.tokenCount * [decimal]$detail.costPerBatch / [decimal]$detail.batchSize
            }
            @{
                type = 'session.usage_record'
                agentId = $AgentId
                timestamp = $Timestamp
                data = @{
                    usage = @{
                        model = $Model
                        inputTokens = $FreshInput + $Cached + $CacheWrite
                        outputTokens = $Output
                        cacheReadTokens = $Cached
                        cacheWriteTokens = $CacheWrite
                        aiCreditsStatus = 'complete'
                        copilotUsage = @{ totalNanoAiu = $nanoAiu; tokenDetails = $details }
                        accounting = @{ sourceSessionId = $SourceSessionId; usageId = $UsageId }
                    }
                }
            } | ConvertTo-Json -Depth 12 -Compress
        }

        function Add-SecondSessionHistoryLocal {
            param([Parameter(Mandatory)][string]$Root)
            Add-Content -LiteralPath (Join-Path $Root 'history/Squad Researcher.md') -Encoding utf8NoBOM -Value @'

### 2026-10-02T10:00:00Z Surveying the next fixture increment

* Turn: 3
* Request: Survey the next fixture increment.
* Deliverable: `research/2026-10-02-fixture-topic.md`
* Outcome: Recorded the next exact-session increment.

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "session-inherited",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 4,
  "input_tokens": 2000,
  "cached_tokens": 8000,
  "cache_write_tokens": 0,
  "output_tokens": 2000,
  "basis": "estimated"
}
```
'@
            Add-Content -LiteralPath (Join-Path $Root 'history/Squad Scribe.md') -Encoding utf8NoBOM -Value @'

### 2026-10-02T10:05:00Z Recording the next fixture increment

* Turn: 3
* Request: Record the next fixture increment and advance state.
* Deliverable: `state.json`, `consumption.md`, `history/Squad Researcher.md`
* Outcome: Recorded the next exact-session increment.

#### Consumption — Orchestration

```json
{
  "model": "Claude Haiku 4.5",
  "model_source": "agent-pinned",
  "priced_as": "Claude Haiku 4.5",
  "model_tier": "fast",
  "internal_turns": 2,
  "input_tokens": 1000,
  "cached_tokens": 1000,
  "cache_write_tokens": 0,
  "output_tokens": 1000,
  "basis": "estimated"
}
```
'@
        }

        function Add-SecondSessionLogLocal {
            param([Parameter(Mandatory)]$Fixture)
            $session2 = Join-Path $Fixture.Home 'session-state/sess-0002'
            New-Item -ItemType Directory -Path $session2 -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $session2 'workspace.yaml') -Value "id: sess-0002`ncwd: $($Fixture.Repo)`n"
            $events2 = @(
                '{"type":"session.start","data":{"sessionId":"sess-0002"},"timestamp":"2026-10-02T09:59:00.000Z"}'
                '{"type":"subagent.started","agentId":"research-2","data":{"toolCallId":"t3","agentName":"Squad Researcher","agentDisplayName":"researcher","model":"claude-sonnet-4.6"},"timestamp":"2026-10-02T10:00:01.000Z"}'
                (New-ExactUsageEventLocal -AgentId 'research-2' -SourceSessionId 'research-session-2' -UsageId 'three' -Model 'claude-sonnet-4.6' -FreshInput 20000 -Cached 10000 -CacheWrite 0 -Output 2000 -InputRate 3 -CachedRate 0.3 -CacheWriteRate 3.75 -OutputRate 15 -Timestamp '2026-10-02T10:02:00.000Z')
                '{"type":"subagent.started","agentId":"scribe-2","data":{"toolCallId":"t4","agentName":"Squad Scribe","agentDisplayName":"scribe","model":"claude-haiku-4.5"},"timestamp":"2026-10-02T10:02:01.000Z"}'
                (New-ExactUsageEventLocal -AgentId 'scribe-2' -SourceSessionId 'scribe-session-2' -UsageId 'four' -Model 'claude-haiku-4.5' -FreshInput 1000 -Cached 1000 -CacheWrite 0 -Output 1000 -InputRate 1 -CachedRate 0.1 -CacheWriteRate 1.25 -OutputRate 5 -Timestamp '2026-10-02T10:03:00.000Z')
            )
            $eventsPath = Join-Path $session2 'events.jsonl'
            Set-Content -LiteralPath $eventsPath -Value ($events2 -join "`n")
            $session1Events = Join-Path $Fixture.SessionDir 'events.jsonl'
            if (Test-Path -LiteralPath $session1Events -PathType Leaf) {
                (Get-Item -LiteralPath $session1Events).LastWriteTimeUtc = [datetime]'2026-10-01T10:04:00Z'
            }
            (Get-Item -LiteralPath $eventsPath).LastWriteTimeUtc = [datetime]'2026-10-02T10:03:00Z'
            $session2
        }

        $script:BaseEvents = @(
            '{"type":"session.start","data":{"sessionId":"sess-0001"},"timestamp":"2026-09-27T09:59:00.000Z"}'
            '{"type":"tool.execution_start","data":{"toolCallId":"t1","toolName":"task","arguments":{"agent_type":"Squad Researcher","prompt":"Write to .copilot-tracking/research/x.md"}},"timestamp":"2026-10-01T10:00:01.000Z"}'
            '{"type":"subagent.started","agentId":"owner-research","data":{"toolCallId":"t1","agentName":"Squad Researcher","agentDisplayName":"researcher","model":"claude-sonnet-4.6"},"timestamp":"2026-10-01T10:00:02.000Z"}'
            (New-ExactUsageEventLocal -AgentId 'owner-research' -SourceSessionId 'research-session' -UsageId 'one' -Model 'claude-sonnet-4.6' -FreshInput 100000 -Cached 80000 -CacheWrite 0 -Output 10000 -InputRate 3 -CachedRate 0.3 -CacheWriteRate 3.75 -OutputRate 15 -Timestamp '2026-10-01T10:02:00.000Z')
            '{"type":"subagent.completed","agentId":"owner-research","data":{"toolCallId":"t1","agentName":"Squad Researcher","model":"claude-sonnet-4.6","totalTokens":190000,"durationMs":120000},"timestamp":"2026-10-01T10:02:01.000Z"}'
            '{"type":"subagent.started","agentId":"owner-scribe","data":{"toolCallId":"t2","agentName":"Squad Scribe","agentDisplayName":"scribe","model":"claude-haiku-4.5"},"timestamp":"2026-10-01T10:02:02.000Z"}'
            (New-ExactUsageEventLocal -AgentId 'owner-scribe' -SourceSessionId 'scribe-session' -UsageId 'two' -Model 'claude-haiku-4.5' -FreshInput 10000 -Cached 40000 -CacheWrite 10000 -Output 5000 -InputRate 1 -CachedRate 0.1 -CacheWriteRate 1.25 -OutputRate 5 -Timestamp '2026-10-01T10:03:00.000Z')
            '{"type":"subagent.completed","agentId":"owner-scribe","data":{"toolCallId":"t2","agentName":"Squad Scribe","model":"claude-haiku-4.5","totalTokens":65000,"durationMs":60000},"timestamp":"2026-10-01T10:03:01.000Z"}'
            '{"type":"session.usage_checkpoint","data":{"totalNanoAiu":123450000000},"timestamp":"2026-10-01T10:04:00.000Z"}'
            '{"type":"assistant.message","data":{"content":"partial'
        )
    }

    It 'writes one exact ledger, removes the observed section, and compares exact traffic on one baseline model' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $ledger = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        $ledger | Should -Not -Match '(?m)^## Observed Usage'
        $ledger | Should -Match '\| Role \| Requests \| In Tokens \| Cached \| Cache Wr \| Out Tokens \| Exact Cost \(USD\) \| Exact Credits \| Basis \|'
        $ledger | Should -Match '\| researcher \| 1 \| 100,000 \| 80,000 \| 0 \| 10,000 \| 0\.4740 \| 47\.40 \| exact-native \|'
        $ledger | Should -Match '\| orchestration \| 1 \| 10,000 \| 40,000 \| 10,000 \| 5,000 \| 0\.0515 \| 5\.15 \| exact-native \|'
        $ledger | Should -Match '\| \*\*Total\*\* \| \*\*2\*\* \| \*\*110,000\*\* \| \*\*120,000\*\* \| \*\*10,000\*\* \| \*\*15,000\*\* \| \*\*0\.5255\*\* \| \*\*52\.55\*\* \| \*\*exact-native\*\* \|'
        $ledger | Should -Match 'Native usage snapshot .* records: 2; .* digest: [A-F0-9]{64}'
        $ledger | Should -Match '(?m)^## Cost Comparison \(exact native actual\)\s*$'
        $ledger | Should -Match 'Without HVE Squad: same exact role-request token categories on `claude-sonnet-4\.6`, no coordinator or Scribe'

        $check = Invoke-Ledger -SquadRoot $f.Root -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Scribe' = 1 }
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'writes the ledger when only the Scribe has completed, as at the first hand-off of a run (a live run rolled back on ''Sum'' cannot be found)' {
        $f = New-SessionFixtureLocal -Fixture seed -EventLines @($script:BaseEvents | Where-Object { $_ -notmatch 'owner-research|research-session|toolCallId":"t1"' })
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $ledger = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        $ledger | Should -Match '\| orchestration \| 1 \| 10,000 \| 40,000 \| 10,000 \| 5,000 \|'
        $ledger | Should -Not -Match 'Without HVE Squad' -Because 'no role work exists to reprice'
    }

    It 'writes the ledger when the session has billed units but no completed dispatch' {
        $f = New-SessionFixtureLocal -EventLines @($script:BaseEvents | Where-Object { $_ -notmatch 'subagent\.completed' })
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output
        Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw | Should -Match '\*\*52\.55\*\* \| \*\*exact-native\*\*'
    }

    It 'writes the ledger at every point a live session can be cut, falling back until exact attribution is complete' {
        # Live order: the Scribe's roster refresh completes and is billed before any owner finishes.
        $live = @($script:BaseEvents)
        for ($n = 1; $n -le $live.Count; $n++) {
            $f = New-SessionFixtureLocal -EventLines @($live | Select-Object -First $n)
            $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
            $result.ExitCode | Should -Be 0 -Because "the session cut after event $n must still write: $($result.Output)"
        }
    }

    It 'falls back to estimates with a warning, and still writes and checks the ledger, when exact native records are unavailable' {
        $f = New-SessionFixtureLocal -EventLines @('{"type":"subagent.completed","data":{"toolCallId":"t9","agentName":"Squad Researcher","model":"claude-sonnet-4.6","totalTokens":"not-a-number","durationMs":1},"timestamp":"2026-10-01T10:00:00.000Z"}')
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'estimates remain the fallback'
        Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw | Should -Not -Match '## Observed Usage'
        Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw | Should -Match 'Est\. Cost \(USD\)'
        (Invoke-Ledger -SquadRoot $f.Root -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Scribe' = 1 }).ExitCode | Should -Be 0
    }

    It 'falls back when the squad history predates the selected host session' {
        $events = @($script:BaseEvents)
        $events[0] = $events[0].Replace('2026-09-27T09:59:00.000Z', '2026-10-01T10:00:00.000Z')
        $f = New-SessionFixtureLocal -EventLines $events
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'history predates the selected host session'
        $ledger = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        $ledger | Should -Match 'Est\. Cost \(USD\)'
        $ledger | Should -Not -Match 'Exact Cost \(USD\)'
    }

    It 'rewrites the exact ledger idempotently instead of appending duplicate exact sections' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        (Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write).ExitCode | Should -Be 0
        $first = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        (Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write).ExitCode | Should -Be 0
        $second = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        @([regex]::Matches($second, '(?m)^## Cost Comparison \(exact native actual\)')).Count | Should -Be 1
        @([regex]::Matches($second, '(?m)^Native usage snapshot')).Count | Should -Be 1
        $second | Should -Be $first
    }

    It 'accumulates exact native usage across sessions without requiring the older session log or double counting a replay' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        (Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write).ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $f.Root 'consumption-sessions.json') -PathType Leaf | Should -BeTrue

        Add-SecondSessionHistoryLocal -Root $f.Root
        Remove-Item -LiteralPath $f.SessionDir -Recurse -Force
        $session2 = Add-SecondSessionLogLocal -Fixture $f

        $secondWrite = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $session2 -Write
        $secondWrite.ExitCode | Should -Be 0 -Because $secondWrite.Output
        $ledger = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        $ledger | Should -Match 'Native usage snapshots — sessions: 2; records: 4;'
        $ledger | Should -Match '\| \*\*Total\*\* \| \*\*4\*\* \| \*\*131,000\*\* \| \*\*131,000\*\* \| \*\*10,000\*\* \| \*\*18,000\*\* \| \*\*0\.6246\*\* \| \*\*62\.46\*\* \| \*\*exact-native\*\* \|'
        $cacheText = Get-Content -LiteralPath (Join-Path $f.Root 'consumption-sessions.json') -Raw
        $cacheText | Should -Not -Match 'research-session|scribe-session'
        $cache = $cacheText | ConvertFrom-Json
        @($cache.sessions).Count | Should -Be 2
        @($cache.sessions.sessionId) | Should -Be @('sess-0001', 'sess-0002')
        @($cache.sessions.contentDigest | Where-Object { $_ -match '^[A-F0-9]{64}$' }).Count | Should -Be 2

        (Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $session2 -Write).ExitCode | Should -Be 0
        $replayed = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        $replayed | Should -Match 'Native usage snapshots — sessions: 2; records: 4;'
        @((Get-Content -LiteralPath (Join-Path $f.Root 'consumption-sessions.json') -Raw | ConvertFrom-Json).sessions).Count | Should -Be 2
        (Invoke-Ledger -SquadRoot $f.Root -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 2; 'Squad Scribe' = 2 }).ExitCode | Should -Be 0
    }

    It 'bootstraps a missing journal from complete auto-selected sessions that uniquely cover existing history' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        Add-SecondSessionHistoryLocal -Root $f.Root
        $null = Add-SecondSessionLogLocal -Fixture $f

        $write = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog 'auto' -CopilotHome $f.Home -Write
        $write.ExitCode | Should -Be 0 -Because $write.Output
        $write.Output | Should -Not -Match 'estimates remain the fallback'

        $ledger = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        $ledger | Should -Match 'Native usage snapshots — sessions: 2; records: 4;'
        $ledger | Should -Match '\| \*\*Total\*\* \| \*\*4\*\* \| \*\*131,000\*\* \| \*\*131,000\*\* \| \*\*10,000\*\* \| \*\*18,000\*\* \| \*\*0\.6246\*\* \| \*\*62\.46\*\* \| \*\*exact-native\*\* \|'
        $cache = Get-Content -LiteralPath (Join-Path $f.Root 'consumption-sessions.json') -Raw | ConvertFrom-Json
        @($cache.sessions.sessionId) | Should -Be @('sess-0001', 'sess-0002')

        $replay = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog 'auto' -CopilotHome $f.Home -Write
        $replay.ExitCode | Should -Be 0 -Because $replay.Output
        $replay.Output | Should -Not -Match 'consumption-sessions\.json is unavailable or inconsistent'
        (Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw) | Should -Match 'Native usage snapshots — sessions: 2; records: 4;'
    }

    It 'finds the session with -SessionLog auto through COPILOT_HOME and the workspace cwd' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog 'auto' -CopilotHome $f.Home -Format json
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $json = ($result.Output -split '\r?\n' | Where-Object { $_ -notmatch '^(WARNING|AVERTISSEMENT)' }) -join "`n" | ConvertFrom-Json
        $json.basis | Should -Be 'exact-native'
        $json.exact.sessionId | Should -Be 'sess-0001'
        $json.exact.records | Should -Be 2
        $json.exact.baselineModel | Should -Be 'claude-sonnet-4.6'
        $json.total.estCostUsd | Should -Be $json.total.costUsd
        $json.total.estCredits | Should -Be $json.total.credits
    }

    It 'warns and adds nothing when auto finds no session for this repository' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        Set-Content -LiteralPath (Join-Path $f.SessionDir 'workspace.yaml') -Value "cwd: C:\elsewhere`n"
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog 'auto' -CopilotHome $f.Home -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'found no Copilot session'
        (Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw) | Should -Not -Match 'Observed Usage'
        (Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw) | Should -Match 'Est\. Cost \(USD\)'
    }

    It 'uses the host model as authoritative when it differs from the estimated history model' {
        $events = @($script:BaseEvents | ForEach-Object { $_.Replace('"model":"claude-sonnet-4.6"', '"model":"claude-opus-5"') })
        $f = New-SessionFixtureLocal -EventLines $events
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw) | Should -Match '\| researcher \| Alpha \| Squad Researcher \| claude-opus-5 \| host-reported \| native credits \|'
    }

    It 'prices the comparison at -BaselineModel when supplied' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Format json -BaselineModel 'Claude Opus 5'
        $json = ($result.Output -split '\r?\n' | Where-Object { $_ -notmatch '^(WARNING|AVERTISSEMENT)' }) -join "`n" | ConvertFrom-Json
        $json.exact.baselineModel | Should -Be 'Claude Opus 5'
        $json.exact.baselineCostUsd | Should -Be 0.79 -Because '100,000 uncached x 5 + 80,000 cached x 0.5 + 10,000 output x 25, divided by 1e6'
    }

    It 'counts only dispatches whose prompt names the sub-squad root' {
        $events = @(
            '{"type":"tool.execution_start","data":{"toolCallId":"p1","toolName":"task","arguments":{"agent_type":"Squad Researcher","prompt":"Write to .copilot-tracking/squad/members/product/research/x.md"}},"timestamp":"2026-10-01T10:00:01.000Z"}'
            '{"type":"subagent.completed","data":{"toolCallId":"p1","agentName":"Squad Researcher","model":"claude-sonnet-4.6","totalTokens":400000,"durationMs":1000},"timestamp":"2026-10-01T10:00:02.000Z"}'
            '{"type":"tool.execution_start","data":{"toolCallId":"a1","toolName":"task","arguments":{"agent_type":"Squad Researcher","prompt":"Write to .copilot-tracking/squad/members/azure/research/y.md"}},"timestamp":"2026-10-01T10:00:03.000Z"}'
            '{"type":"subagent.completed","data":{"toolCallId":"a1","agentName":"Squad Researcher","model":"claude-sonnet-4.6","totalTokens":900000,"durationMs":1000},"timestamp":"2026-10-01T10:00:04.000Z"}'
        )
        $f = New-SessionFixtureLocal -Member 'product' -EventLines $events
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Format json
        $json = ($result.Output -split '\r?\n' | Where-Object { $_ -notmatch '^(WARNING|AVERTISSEMENT)' }) -join "`n" | ConvertFrom-Json
        $json.basis | Should -Be 'estimated'
        $json.exact | Should -BeNullOrEmpty
    }

    It 'records hydrafusion-max native credits exactly and reprices the same exact traffic on the default baseline' {
        $events = @(
            '{"type":"session.start","data":{"sessionId":"sess-0001","selectedModel":"hydrafusion-max"},"timestamp":"2026-09-27T09:59:00.000Z"}'
            '{"type":"subagent.started","agentId":"hydra-owner","data":{"toolCallId":"h1","agentName":"Squad Researcher","agentDisplayName":"researcher","model":"hydrafusion-max"},"timestamp":"2026-10-01T10:00:01.000Z"}'
            (New-ExactUsageEventLocal -AgentId 'hydra-owner' -SourceSessionId 'hydra-session' -UsageId 'h1' -Model 'hydrafusion-max' -FreshInput 100000 -Cached 80000 -CacheWrite 0 -Output 20000 -InputRate 0.8 -CachedRate 0.05 -CacheWriteRate 1 -OutputRate 4 -Timestamp '2026-10-01T10:02:00.000Z')
            '{"type":"subagent.completed","agentId":"hydra-owner","data":{"toolCallId":"h1","agentName":"Squad Researcher","model":"hydrafusion-max","totalTokens":200000,"durationMs":60000},"timestamp":"2026-10-01T10:02:01.000Z"}'
            '{"type":"subagent.started","agentId":"hydra-scribe","data":{"toolCallId":"h2","agentName":"Squad Scribe","agentDisplayName":"scribe","model":"claude-haiku-5.5"},"timestamp":"2026-10-01T10:02:02.000Z"}'
            (New-ExactUsageEventLocal -AgentId 'hydra-scribe' -SourceSessionId 'hydra-scribe-session' -UsageId 'h2' -Model 'claude-haiku-5.5' -FreshInput 1000 -Cached 1000 -CacheWrite 0 -Output 1000 -InputRate 0.1 -CachedRate 0.01 -CacheWriteRate 0.125 -OutputRate 0.5 -Timestamp '2026-10-01T10:03:00.000Z')
            '{"type":"subagent.completed","agentId":"hydra-scribe","data":{"toolCallId":"h2","agentName":"Squad Scribe","model":"claude-haiku-5.5","totalTokens":3000,"durationMs":30000},"timestamp":"2026-10-01T10:03:01.000Z"}'
        )
        $f = New-SessionFixtureLocal -EventLines $events
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $ledger = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        $ledger | Should -Match '\| researcher \| Alpha \| Squad Researcher \| hydrafusion-max \| host-reported \| native credits \|'
        $ledger | Should -Match '\| researcher \| 1 \| 100,000 \| 80,000 \| 0 \| 20,000 \| 0\.1640 \| 16\.40 \| exact-native \|'
        $ledger | Should -Match 'Without HVE Squad: same exact role-request token categories on `claude-sonnet-4\.6`'

        $jsonResult = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Format json
        $json = ($jsonResult.Output -split '\r?\n' | Where-Object { $_ -notmatch '^(WARNING|AVERTISSEMENT)' }) -join "`n" | ConvertFrom-Json
        $json.exact.baselineModel | Should -BeIn @('claude-sonnet-4.6', 'Claude Sonnet 4.6')
        $json.exact.baselineCostUsd | Should -Be 0.624
    }

    It 'sums mixed native models under the same owning role without a separate observed table' {
        $events = @(
            '{"type":"session.start","data":{"sessionId":"sess-0001"},"timestamp":"2026-09-27T09:59:00.000Z"}'
            '{"type":"subagent.started","agentId":"mixed-owner","data":{"toolCallId":"h1","agentName":"Squad Researcher","agentDisplayName":"researcher","model":"hydrafusion-max"},"timestamp":"2026-10-01T10:00:01.000Z"}'
            (New-ExactUsageEventLocal -AgentId 'mixed-owner' -SourceSessionId 'mixed-session' -UsageId 'h1' -Model 'hydrafusion-max' -FreshInput 10000 -Cached 0 -CacheWrite 0 -Output 1000 -InputRate 0.8 -CachedRate 0.05 -CacheWriteRate 1 -OutputRate 4 -Timestamp '2026-10-01T10:00:02.000Z')
            (New-ExactUsageEventLocal -AgentId 'mixed-owner' -SourceSessionId 'mixed-session' -UsageId 's1' -Model 'claude-sonnet-4.6' -FreshInput 20000 -Cached 0 -CacheWrite 0 -Output 2000 -InputRate 3 -CachedRate 0.3 -CacheWriteRate 3.75 -OutputRate 15 -Timestamp '2026-10-01T10:00:03.000Z')
            '{"type":"subagent.completed","agentId":"mixed-owner","data":{"toolCallId":"h1","agentName":"Squad Researcher","model":"claude-sonnet-4.6","totalTokens":33000,"durationMs":1000},"timestamp":"2026-10-01T10:00:04.000Z"}'
            '{"type":"subagent.started","agentId":"mixed-scribe","data":{"toolCallId":"h2","agentName":"Squad Scribe","agentDisplayName":"scribe","model":"claude-haiku-4.5"},"timestamp":"2026-10-01T10:00:05.000Z"}'
            (New-ExactUsageEventLocal -AgentId 'mixed-scribe' -SourceSessionId 'mixed-scribe-session' -UsageId 'h2' -Model 'claude-haiku-4.5' -FreshInput 1000 -Cached 0 -CacheWrite 0 -Output 100 -InputRate 1 -CachedRate 0.1 -CacheWriteRate 1.25 -OutputRate 5 -Timestamp '2026-10-01T10:00:06.000Z')
        )
        $f = New-SessionFixtureLocal -EventLines $events
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Format json
        $json = ($result.Output -split '\r?\n' | Where-Object { $_ -notmatch '^(WARNING|AVERTISSEMENT)' }) -join "`n" | ConvertFrom-Json

        $json.basis | Should -Be 'exact-native'
        $researcher = $json.roles | Where-Object role -eq 'researcher'
        $researcher.requests | Should -Be 2
        ($json.attribution | Where-Object role -eq 'researcher').model | Should -Match 'claude-sonnet-4\.6'
        ($json.attribution | Where-Object role -eq 'researcher').model | Should -Match 'hydrafusion-max'
    }

    It 'uses exact Hydra token categories directly without applying the old estimated inverse factor' {
        $events = @(
            '{"type":"session.start","data":{"sessionId":"sess-0001"},"timestamp":"2026-09-27T09:59:00.000Z"}'
            '{"type":"subagent.started","agentId":"factor-owner","data":{"toolCallId":"h1","agentName":"Squad Researcher","agentDisplayName":"researcher","model":"hydrafusion-max"},"timestamp":"2026-10-01T10:00:01.000Z"}'
            (New-ExactUsageEventLocal -AgentId 'factor-owner' -SourceSessionId 'factor-session' -UsageId 'h1' -Model 'hydrafusion-max' -FreshInput 415380 -Cached 1661520 -CacheWrite 0 -Output 70000 -InputRate 0.8 -CachedRate 0.05 -CacheWriteRate 1 -OutputRate 4 -Timestamp '2026-10-01T10:00:02.000Z')
            '{"type":"subagent.started","agentId":"factor-scribe","data":{"toolCallId":"h2","agentName":"Squad Scribe","agentDisplayName":"scribe","model":"claude-haiku-4.5"},"timestamp":"2026-10-01T10:00:03.000Z"}'
            (New-ExactUsageEventLocal -AgentId 'factor-scribe' -SourceSessionId 'factor-scribe-session' -UsageId 'h2' -Model 'claude-haiku-4.5' -FreshInput 1000 -Cached 0 -CacheWrite 0 -Output 100 -InputRate 1 -CachedRate 0.1 -CacheWriteRate 1.25 -OutputRate 5 -Timestamp '2026-10-01T10:00:04.000Z')
        )
        $f = New-SessionFixtureLocal -EventLines $events

        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Format json
        $json = ($result.Output -split '\r?\n' | Where-Object { $_ -notmatch '^(WARNING|AVERTISSEMENT)' }) -join "`n" | ConvertFrom-Json
        $researcher = $json.roles | Where-Object role -eq 'researcher'
        $researcher.input | Should -Be 415380
        $researcher.cached | Should -Be 1661520
        $researcher.output | Should -Be 70000
        $json.exact.baselineCostUsd | Should -Be 2.7946
    }
}
Describe 'Measure-SquadLedger names an insert-above-the-end as an ordering defect, not lost content' {
    It 'reports entries inserted inside the file, with every original byte kept, distinctly from a prefix edit' {
        $root = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $historyPath = Join-Path $root 'history/Squad Researcher.md'
        $baselinePath = Join-Path $TestDrive "$([System.Guid]::NewGuid().ToString('N')).json"
        (Invoke-Ledger -SquadRoot $root -EmitBaseline $baselinePath).ExitCode | Should -Be 0

        # A live Scribe inserted its new entry directly under the "below this line" marker,
        # above the existing entry, instead of after it.
        $raw = Get-Content -LiteralPath $historyPath -Raw
        $raw = $raw.Replace('# History: Squad Researcher', "# History: Squad Researcher`n`n### 2026-10-01T16:10:00Z Inserted above the older entry`n`n* Turn: 3")
        Set-Content -LiteralPath $historyPath -Value $raw -NoNewline

        $result = Invoke-Ledger -SquadRoot $root -Check -BaselinePath $baselinePath
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "entries were inserted inside the file, not appended: 'history/Squad Researcher\.md' keeps every original byte"
        $result.Output | Should -Not -Match 'a prefix edit, not only an append'
    }
}

Describe 'Measure-SquadLedger exact mode removes duplicate estimate-versus-observed presentation' {
    It 'contains one authoritative cost total and no observed section after an exact write' {
        $repo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        $root = Join-Path $repo '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Split-Path -Parent $root) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $sessionDir = Join-Path $repo 'session'
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sessionDir 'events.jsonl') -Value (@(
                '{"type":"session.start","data":{"sessionId":"sess"},"timestamp":"2026-09-27T09:59:00.000Z"}'
                '{"type":"subagent.started","agentId":"r1","data":{"toolCallId":"t1","agentName":"Squad Researcher","agentDisplayName":"researcher"},"timestamp":"2026-10-01T10:00:00.000Z"}'
                '{"type":"session.usage_record","agentId":"r1","data":{"usage":{"model":"claude-sonnet-4.6","inputTokens":180000,"outputTokens":10000,"cacheReadTokens":80000,"cacheWriteTokens":0,"aiCreditsStatus":"complete","copilotUsage":{"totalNanoAiu":47400000000,"tokenDetails":[{"tokenType":"input","tokenCount":100000,"batchSize":1000000,"costPerBatch":300000000000},{"tokenType":"cache_read","tokenCount":80000,"batchSize":1000000,"costPerBatch":30000000000},{"tokenType":"cache_write","tokenCount":0,"batchSize":1000000,"costPerBatch":375000000000},{"tokenType":"output","tokenCount":10000,"batchSize":1000000,"costPerBatch":1500000000000}]},"accounting":{"sourceSessionId":"r1-session","usageId":"one"}}},"timestamp":"2026-10-01T10:00:30.000Z"}'
                '{"type":"subagent.started","agentId":"s1","data":{"toolCallId":"t2","agentName":"Squad Scribe","agentDisplayName":"scribe"},"timestamp":"2026-10-01T10:00:31.000Z"}'
                '{"type":"session.usage_record","agentId":"s1","data":{"usage":{"model":"claude-haiku-4.5","inputTokens":1000,"outputTokens":100,"cacheReadTokens":0,"cacheWriteTokens":0,"aiCreditsStatus":"complete","copilotUsage":{"totalNanoAiu":150000000,"tokenDetails":[{"tokenType":"input","tokenCount":1000,"batchSize":1000000,"costPerBatch":100000000000},{"tokenType":"cache_read","tokenCount":0,"batchSize":1000000,"costPerBatch":10000000000},{"tokenType":"cache_write","tokenCount":0,"batchSize":1000000,"costPerBatch":125000000000},{"tokenType":"output","tokenCount":100,"batchSize":1000000,"costPerBatch":500000000000}]},"accounting":{"sourceSessionId":"s1-session","usageId":"two"}}},"timestamp":"2026-10-01T10:00:32.000Z"}'
            ) -join "`n")

        $output = & pwsh -NoProfile -Command "& '$script:LedgerScript' -SquadRoot '$root' -Write -SessionLog '$sessionDir'" 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $ledger = Get-Content -LiteralPath (Join-Path $root 'consumption.md') -Raw
        @([regex]::Matches($ledger, 'Exact Cost \(USD\)')).Count | Should -Be 1
        $ledger | Should -Not -Match 'Observed Usage|Exact host usage for this session so far|Est\. Cost \(USD\)'
        $ledger | Should -Match '(?m)^## Cost Comparison \(exact native actual\)\s*$'

        $check = Invoke-Ledger -SquadRoot $root -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Scribe' = 1 }
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }
}

Describe 'Unit economics (value) section' {
    BeforeAll {
        # Each block prices at exactly 30 credits (100,000 input tokens at 3.00 USD per 1M).
        function New-UnitEconomicsRootLocal {
            param([Parameter(Mandatory)][object[]]$Entries)
            $root = New-BaselineTestRootLocal
            Remove-Item -LiteralPath (Join-Path $root 'history') -Recurse -Force
            New-Item -ItemType Directory -Path (Join-Path $root 'history') | Out-Null
            $team = @(
                '# Squad Roster', '', '## Members', '',
                '| Role | Member Name | Agent Name (Primary) | Alternate Agents | Selection Cue | Invocation | Model Tier | Deliverable Root |',
                '| ---- | ----------- | -------------------- | ---------------- | ------------- | ---------- | ---------- | ---------------- |',
                '| implementor | Alpha | Squad Implementor | — | — | task | default | src/ |',
                '| writer | Beta | Squad Writer | — | — | task | default | docs/ |',
                '| tester | Gamma | Squad Tester | — | — | task | default | reviews/ |',
                '| scribe | | Squad Scribe | — | — | task | default | (squad state) |'
            ) -join "`n"
            Set-Content -LiteralPath (Join-Path $root 'team.md') -Value $team -NoNewline
            $fence = '```'
            foreach ($group in ($Entries | Group-Object Agent)) {
                $text = ''
                foreach ($e in $group.Group) {
                    $heading = if ($e.Agent -eq 'Squad Scribe') { '#### Consumption — Orchestration' } else { '#### Consumption' }
                    $text += "`n### $($e.Stamp) Dispatch $($e.Stamp)`n`n* Turn: $($e.Turn)`n* Request: Synthetic.`n* Deliverable: ``$($e.Deliverable)```n* Outcome: $($e.Outcome)`n"
                    if ($e.Workstream) { $text += "* Workstream: $($e.Workstream)`n" }
                    $text += "`n$heading`n`n${fence}json`n{`n  `"model`": `"Claude Sonnet 4.6`",`n  `"model_source`": `"session-inherited`",`n  `"priced_as`": `"Claude Sonnet 4.6`",`n  `"model_tier`": `"default`",`n  `"internal_turns`": 1,`n  `"input_tokens`": 100000,`n  `"cached_tokens`": 0,`n  `"cache_write_tokens`": 0,`n  `"output_tokens`": 0,`n  `"basis`": `"estimated`"`n}`n${fence}`n"
                }
                Set-Content -LiteralPath (Join-Path $root "history/$($group.Name).md") -Value $text -NoNewline
            }
            # The fixture's recorded identities describe the removed history; drop them so the guard only warns.
            $ledger = Join-Path $root 'consumption.md'
            Set-Content -LiteralPath $ledger -Value ((Get-Content -LiteralPath $ledger -Raw) -replace ' — identities: [^\r\n]*', '') -NoNewline
            (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0
            $root
        }

        function New-EntryLocal {
            param($Agent, $Stamp, $Turn, $Deliverable, $Outcome = 'Done.', $Workstream = '')
            [pscustomobject]@{ Agent = $Agent; Stamp = "2026-10-04T$Stamp`:00Z"; Turn = $Turn; Deliverable = $Deliverable; Outcome = $Outcome; Workstream = $Workstream }
        }

        $script:AcceptedEntries = @(
            New-EntryLocal 'Squad Implementor' '10:00' 2 'src/a.md'
            New-EntryLocal 'Squad Writer' '10:05' 2 'docs/b.md'
            New-EntryLocal 'Squad Tester' '10:10' 2 'reviews/r2.md' 'Verdict Pass, no findings.'
            New-EntryLocal 'Squad Implementor' '11:00' 3 'src/c.md'
            New-EntryLocal 'Squad Tester' '11:10' 3 'reviews/r3.md' 'Verdict FAIL: two defects.'
            New-EntryLocal 'Squad Scribe' '12:00' 3 'decisions.md'
        )
        $script:ReworkEntries = @(
            New-EntryLocal 'Squad Implementor' '10:00' 2 'src/a.md'
            New-EntryLocal 'Squad Tester' '10:10' 2 'reviews/r2.md' 'Verdict Fail.'
            New-EntryLocal 'Squad Implementor' '10:20' 2 'SRC\A.md'
            New-EntryLocal 'Squad Tester' '10:30' 2 'reviews/r2b.md' 'Verdict Pass-with-findings.'
            New-EntryLocal 'Squad Writer' '10:40' 5 'docs/b.md'
            New-EntryLocal 'Squad Scribe' '12:00' 5 'decisions.md'
        )
    }

    It 'counts accepted, rejected, and unreviewed deliverables and prices per accepted deliverable' {
        $root = New-UnitEconomicsRootLocal -Entries $script:AcceptedEntries
        $out = (Invoke-Ledger -SquadRoot $root).Output
        $out | Should -Match '(?m)^## Unit Economics \(value\)\s*$'
        $out | Should -Match '\| Deliverables produced \| 3 \| derived \|'
        $out | Should -Match '\| Accepted by an independent review \| 2 \| derived \|'
        $out | Should -Match '\| Rejected \| 1 \| derived \|'
        $out | Should -Match '\| Unreviewed \| 0 \| derived \|'
        $out | Should -Match '\| Dispatches \(excluding Scribe\) \| 5 \| derived \|'
        $out | Should -Match '\| Rework dispatches \| 0 \| derived \|'
        $out | Should -Match '\| First-pass yield \| 100\.0% \| derived \|'
        $out | Should -Match '\| Est\. credits per accepted deliverable \| 90\.00 \| estimated \|'
        $out | Should -Match '\| Orchestration share of est\. credits \| 16\.7% \| estimated \|'
    }

    It 'counts a re-dispatch on the same agent and deliverable as rework and excludes it from first-pass yield' {
        $root = New-UnitEconomicsRootLocal -Entries $script:ReworkEntries
        $out = (Invoke-Ledger -SquadRoot $root).Output
        $out | Should -Match '\| Deliverables produced \| 2 \| derived \|'
        $out | Should -Match '\| Accepted by an independent review \| 1 \| derived \|'
        $out | Should -Match '\| Unreviewed \| 1 \| derived \|'
        $out | Should -Match '\| Rework dispatches \| 1 \| derived \|'
        $out | Should -Match '\| First-pass yield \| 0\.0% \| derived \|'
        $out | Should -Match '\| Est\. credits per accepted deliverable \| 180\.00 \| estimated \|'
        $out | Should -Match '\| Rework share of est\. credits \| 16\.7% \| estimated \|'
    }

    It 'requires the same Workstream, when either entry has one, for a review to cover a work entry' {
        $entries = @(
            New-EntryLocal 'Squad Implementor' '10:00' 2 'src/a.md' -Workstream 'ws1'
            New-EntryLocal 'Squad Tester' '10:10' 2 'reviews/r2.md' 'Verdict Pass.' 'ws2'
            New-EntryLocal 'Squad Scribe' '12:00' 2 'decisions.md'
        )
        $out = (Invoke-Ledger -SquadRoot (New-UnitEconomicsRootLocal -Entries $entries)).Output
        $out | Should -Match '\| Accepted by an independent review \| 0 \| derived \|'
        $out | Should -Match '\| Unreviewed \| 1 \| derived \|'
        $out | Should -Match '\| Est\. credits per accepted deliverable \| n/a \| estimated \|'
    }

    It 'a review that names deliverables covers only those it names' {
        $named = @(
            New-EntryLocal 'Squad Implementor' '10:00' 2 'src/a.md'
            New-EntryLocal 'Squad Writer' '10:05' 2 'docs/b.md'
            New-EntryLocal 'Squad Tester' '10:10' 2 'reviews/r2.md' 'Verdict Pass for `src/a.md`.'
            New-EntryLocal 'Squad Scribe' '12:00' 2 'decisions.md'
        )
        $out = (Invoke-Ledger -SquadRoot (New-UnitEconomicsRootLocal -Entries $named)).Output
        $out | Should -Match '\| Accepted by an independent review \| 1 \| derived \|'
        $out | Should -Match '\| Unreviewed \| 1 \| derived \|'

        $split = @(
            New-EntryLocal 'Squad Implementor' '10:00' 2 'src/a.md'
            New-EntryLocal 'Squad Writer' '10:05' 2 'docs/b.md'
            New-EntryLocal 'Squad Tester' '10:10' 2 'reviews/r2.md' 'Verdict Pass on a.md.'
            New-EntryLocal 'Squad Tester' '10:20' 2 'reviews/r3.md' 'Verdict Fail on docs/b.md.'
            New-EntryLocal 'Squad Scribe' '12:00' 2 'decisions.md'
        )
        $out = (Invoke-Ledger -SquadRoot (New-UnitEconomicsRootLocal -Entries $split)).Output
        $out | Should -Match '\| Accepted by an independent review \| 1 \| derived \|'
        $out | Should -Match '\| Rejected \| 1 \| derived \|'
        $out | Should -Match '\| Unreviewed \| 0 \| derived \|'
        $out | Should -Match ([regex]::Escape('A review that names deliverables covers only those it names.'))
        $out | Should -Match ([regex]::Escape('so the rework figures are a floor'))
    }

    It 'accepts a file-name mention only when no other deliverable of the turn and workstream shares that name (F1)' {
        $byPath = @(
            New-EntryLocal 'Squad Implementor' '10:00' 2 'src/readme.md'
            New-EntryLocal 'Squad Writer' '10:05' 2 'docs/readme.md'
            New-EntryLocal 'Squad Tester' '10:10' 2 'reviews/r2.md' 'Verdict Pass for `src/readme.md`.'
            New-EntryLocal 'Squad Scribe' '12:00' 2 'decisions.md'
        )
        $out = (Invoke-Ledger -SquadRoot (New-UnitEconomicsRootLocal -Entries $byPath)).Output
        $out | Should -Match '\| Accepted by an independent review \| 1 \| derived \|'
        $out | Should -Match '\| Unreviewed \| 1 \| derived \|'

        $byLeaf = @(
            New-EntryLocal 'Squad Implementor' '10:00' 2 'src/readme.md'
            New-EntryLocal 'Squad Writer' '10:05' 2 'docs/readme.md'
            New-EntryLocal 'Squad Tester' '10:10' 2 'reviews/r2.md' 'Verdict Pass on readme.md.'
            New-EntryLocal 'Squad Scribe' '12:00' 2 'decisions.md'
        )
        $out = (Invoke-Ledger -SquadRoot (New-UnitEconomicsRootLocal -Entries $byLeaf)).Output
        $out | Should -Match '\| Accepted by an independent review \| 0 \| derived \|' -Because 'an ambiguous file name names neither deliverable'
        $out | Should -Match '\| Unreviewed \| 2 \| derived \|' -Because 'the mention also keeps the review from covering every deliverable'

        $otherWorkstream = @(
            New-EntryLocal 'Squad Implementor' '10:00' 2 'src/readme.md' -Workstream 'ws1'
            New-EntryLocal 'Squad Writer' '10:05' 2 'docs/readme.md' -Workstream 'ws2'
            New-EntryLocal 'Squad Tester' '10:10' 2 'reviews/r2.md' 'Verdict Pass on readme.md.' 'ws1'
            New-EntryLocal 'Squad Scribe' '12:00' 2 'decisions.md'
        )
        $out = (Invoke-Ledger -SquadRoot (New-UnitEconomicsRootLocal -Entries $otherWorkstream)).Output
        $out | Should -Match '\| Accepted by an independent review \| 1 \| derived \|' -Because 'the name is unique within its own turn and workstream'
    }

    It 'never changes the -Check result or its failure class (F2): <Case>' -ForEach @(
        @{ Case = 'ledger-only'; Class = 'ledger-only' }
        @{ Case = 'history-integrity'; Class = 'history-integrity' }
    ) {
        $root = New-UnitEconomicsRootLocal -Entries $script:AcceptedEntries
        $ledgerPath = Join-Path $root 'consumption.md'
        $checkArgs = @{}
        if ($Case -eq 'ledger-only') {
            $state = Join-Path $root 'state.json'
            Set-Content -LiteralPath $state -Value ((Get-Content -LiteralPath $state -Raw) -replace '"estCostUsd":\s*[0-9.]+', '"estCostUsd": 9.9999') -NoNewline
        }
        else { $checkArgs.ExpectedHistoryCounts = @{ 'Squad Implementor' = 9 } }
        $with = Invoke-Ledger -SquadRoot $root -Check @checkArgs
        $with.ExitCode | Should -Be 1 -Because $with.Output
        $with.Output | Should -Match "failure class: $Class"
        $text = Get-Content -LiteralPath $ledgerPath -Raw
        Set-Content -LiteralPath $ledgerPath -Value ($text -replace '(?s)## Unit Economics \(value\).*?(?=## Cost Comparison)', '') -NoNewline
        $without = Invoke-Ledger -SquadRoot $root -Check @checkArgs
        $without.ExitCode | Should -Be $with.ExitCode
        $without.Output | Should -Be $with.Output
    }
    It '-Write reports that it rewrote the Unit Economics section' {
        $root = New-UnitEconomicsRootLocal -Entries $script:AcceptedEntries
        (Invoke-Ledger -SquadRoot $root -Write).Output | Should -Match ([regex]::Escape('Derivation, Unit Economics, and Cost Comparison sections'))
    }

    It '-Format json exposes unitEconomics with numeric fields' {
        $root = New-UnitEconomicsRootLocal -Entries $script:AcceptedEntries
        $ue = ((Invoke-Ledger -SquadRoot $root -Format json).Output | ConvertFrom-Json).unitEconomics
        $ue.deliverablesProduced | Should -Be 3
        $ue.accepted | Should -Be 2
        $ue.rejected | Should -Be 1
        $ue.estCreditsPerAccepted | Should -Be 90
        $ue.firstPassYieldPct | Should -Be 100
        foreach ($name in 'deliverablesProduced', 'accepted', 'rejected', 'unreviewed', 'dispatches', 'reworkDispatches', 'firstPassYieldPct', 'estCreditsPerAccepted', 'reworkSharePct', 'orchestrationSharePct') {
            $ue.$name | Should -Not -BeOfType [string] -Because $name
        }
    }

    It '-Write inserts the section before Cost Comparison and a second -Write replaces rather than duplicates it' {
        $root = New-UnitEconomicsRootLocal -Entries $script:AcceptedEntries
        $ledgerPath = Join-Path $root 'consumption.md'
        $first = Get-Content -LiteralPath $ledgerPath -Raw
        ([regex]::Matches($first, '(?m)^## Unit Economics \(value\)')).Count | Should -Be 1
        $first.IndexOf('## Unit Economics (value)') | Should -BeGreaterThan $first.IndexOf('### Derivation')
        $first.IndexOf('## Unit Economics (value)') | Should -BeLessThan $first.IndexOf('## Cost Comparison')

        (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0
        $second = Get-Content -LiteralPath $ledgerPath -Raw
        ([regex]::Matches($second, '(?m)^## Unit Economics \(value\)')).Count | Should -Be 1
        $second | Should -Be $first
    }

    It '-Check ignores the section: the result is the same with and without it' {
        $root = New-UnitEconomicsRootLocal -Entries $script:AcceptedEntries
        $ledgerPath = Join-Path $root 'consumption.md'
        $with = Invoke-Ledger -SquadRoot $root -Check
        $with.ExitCode | Should -Be 0 -Because $with.Output

        $text = Get-Content -LiteralPath $ledgerPath -Raw
        Set-Content -LiteralPath $ledgerPath -Value ($text -replace '(?s)## Unit Economics \(value\).*?(?=## Cost Comparison)', '') -NoNewline
        (Get-Content -LiteralPath $ledgerPath -Raw) | Should -Not -Match 'Unit Economics'
        $without = Invoke-Ledger -SquadRoot $root -Check
        $without.ExitCode | Should -Be $with.ExitCode
        $without.Output | Should -Be $with.Output
    }
    It 'counts value with the same review-class roles as Write-SquadHandoff.ps1' {
        $scripts = Split-Path -Parent $script:LedgerScript
        $listOf = {
            param($Path, $Name)
            $m = [regex]::Match((Get-Content -LiteralPath $Path -Raw), "(?m)^\`$$Name\s*=\s*@\((?<list>[^)]*)\)")
            $m.Success | Should -BeTrue -Because "$Name is declared in $Path"
            @([regex]::Matches($m.Groups['list'].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        }
        $value = & $listOf $script:LedgerScript 'script:UnitEconomicsReviewRoles'
        $handoff = & $listOf (Join-Path $scripts 'Write-SquadHandoff.ps1') 'ReviewRoles'
        $value.Count | Should -BeGreaterThan 0
        ($value -join ',') | Should -Be ($handoff -join ',')
        (Get-Content -LiteralPath $script:LedgerScript -Raw) | Should -Match ([regex]::Escape('# Keep identical to $ReviewRoles in Write-SquadHandoff.ps1.'))
    }
}

Describe 'Squad Cost Manager reviews the squad''s own AI spend by value' {
    BeforeAll {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'squad-src', '.github', 'agents', 'squad', 'squad-cost-manager.agent.md'
        $text = (Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n"
        $script:CostManagerBody = $text.Substring($text.IndexOf("`n---", 4) + 5)
    }

    It 'has an AI spend review mode that measures cost per accepted deliverable, not per dispatch' {
        $script:CostManagerBody | Should -Match ([regex]::Escape('An AI spend review (the squad''s own model spend, not an Azure workload) skips Steps 2 to 4 and runs Step 5.'))
        $script:CostManagerBody | Should -Match ([regex]::Escape('A deliverable no review accepted carries zero value: never divide by dispatches or by deliverables merely produced.'))
        $script:CostManagerBody | Should -Match ([regex]::Escape('`## Unit Economics (value)`'))
    }

    It 'labels every figure, compares medians of several like runs, and keeps pin, ceiling, and roster changes at confirm tier' {
        $script:CostManagerBody | Should -Match ([regex]::Escape('Mark each number `measured`'))
        $script:CostManagerBody | Should -Match ([regex]::Escape('with at least three runs per side, reporting medians and the spread'))
        $script:CostManagerBody | Should -Match ([regex]::Escape('Each recommendation that changes a pin, a ceiling, or the roster is `confirm`-tier.'))
        $script:CostManagerBody.Length | Should -BeLessOrEqual 30000
    }
}
