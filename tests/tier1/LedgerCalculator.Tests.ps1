#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

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

    It 'leaves the frontmatter, H1, Basis note, and Cost Comparison section byte-identical' {
        $root = Initialize-WriteTestRootLocal
        $ledgerPath = Join-Path $root 'consumption.md'
        $before = Get-Content -LiteralPath $ledgerPath -Raw
        (Invoke-Ledger -SquadRoot $root -Write).ExitCode | Should -Be 0
        $after = Get-Content -LiteralPath $ledgerPath -Raw

        $headOf = { param($text) $text.Substring(0, $text.IndexOf('## Attribution')) }
        $tailOf = { param($text) $text.Substring($text.IndexOf('## Cost Comparison')) }
        (& $headOf $after) | Should -Be (& $headOf $before)
        (& $tailOf $after) | Should -Be (& $tailOf $before)
        $after | Should -Match '(?m)^Squad Researcher\.md — 1 block\(s\) — identities: '
        $after | Should -Match '\*\*0\.3171\*\*'
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

    It 'refuses (throws) naming state.json or consumption.md as -ProtectedPath' {
        $root = New-BaselineTestRootLocal
        $result = Invoke-Ledger -SquadRoot $root -EmitBaseline (Join-Path $TestDrive 'baseline-guard.json') -ProtectedPath 'state.json'
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'must not name'
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
* Request: Post-baseline synthetic entry with a bad fence.
* Deliverable: `fixtures/ledger-baseline/post-3.md`
* Outcome: Synthetic.

#### Consumption

`json
{
  "model": "Claude Sonnet 4.6"
}
`
'@
    }

    It 'without any -BaselinePath at all, every malformed/illegal shape only WARNs -- "cannot scope, so it never throws"' {
        $root = New-LegacyTestRootLocal
        $result = Invoke-Ledger -SquadRoot $root -Format json
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'bad fence, or non-JSON content'
        $result.Output | Should -Match "illegal model_source 'session'"
        $result.Output | Should -Match "priced_as ' Claude Opus 5 ' only resolves.*after trimming"
        # Still aggregates the two blocks that do resolve (the trimmed-whitespace
        # block and the one fully well-formed block): turns 1 + 2 = 3.
        ($result.Output | ConvertFrom-Json).total.turns | Should -Be 3.0
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
        # The new block aggregates alongside the two pre-existing resolvable ones:
        # turns 1 (legacy well-formed... already 2) -- confirm the post-baseline
        # block's own 1 turn is included without any WARN/FAIL naming it.
        ($result.Output | ConvertFrom-Json).total.turns | Should -Be 4.0
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

Describe 'Measure-SquadLedger -SessionLog adds host-reported usage beside the estimates' {
    BeforeAll {
        function New-SessionFixtureLocal {
            <#
            .SYNOPSIS
                A repo with the applied fixture as its squad root, plus a fake
                session-state directory whose workspace.yaml points at that repo.
            #>
            param([string]$Member, [string[]]$EventLines)
            $repo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
            $squad = Join-Path $repo '.copilot-tracking/squad'
            $root = if ($Member) { Join-Path $squad "members/$Member" } else { $squad }
            New-Item -ItemType Directory -Path (Split-Path -Parent $root) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse

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

        $script:BaseEvents = @(
            '{"type":"session.start","data":{},"timestamp":"2026-10-01T10:00:00.000Z"}'
            '{"type":"tool.execution_start","data":{"toolCallId":"t1","toolName":"task","arguments":{"agent_type":"Squad Researcher","prompt":"Write to .copilot-tracking/research/x.md"}},"timestamp":"2026-10-01T10:00:01.000Z"}'
            '{"type":"subagent.completed","data":{"toolCallId":"t1","agentName":"Squad Researcher","model":"claude-sonnet-4.6","totalTokens":500000,"durationMs":120000},"timestamp":"2026-10-01T10:02:01.000Z"}'
            '{"type":"subagent.completed","data":{"toolCallId":"t2","agentName":"Squad Scribe","model":"claude-haiku-4.5","totalTokens":300000,"durationMs":60000},"timestamp":"2026-10-01T10:03:01.000Z"}'
            '{"type":"session.usage_checkpoint","data":{"totalNanoAiu":123450000000},"timestamp":"2026-10-01T10:04:00.000Z"}'
            '{"type":"assistant.message","data":{"content":"partial'
        )
    }

    It 'writes the observed section with real tokens, blended cost, session AI units, and the without-HVE-Squad comparison, and -Check still passes' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output

        $ledger = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        $ledger | Should -Match '(?m)^## Observed Usage \(host-reported\)\s*$'
        $ledger | Should -Match '\| Squad Researcher \| 1 \| claude-sonnet-4\.6 \| Claude Sonnet 4\.6 \| yes \| 500,000 \|'
        $ledger | Should -Match '\| Squad Scribe \| 1 \| claude-haiku-4\.5 \|'
        $ledger | Should -Match '\*\*Subagents total\*\* \| \*\*2\*\* \| \| \| \| \*\*800,000\*\*'
        $ledger | Should -Match '\*\*0\.8640\*\*'
        $ledger | Should -Match '\*\*123\.45 AI units\*\*'
        $ledger | Should -Match 'Without HVE Squad: the same role work on one model, no Scribe \| 500,000 \| claude-sonnet-4\.6 \| 0\.7200'
        $ledger.IndexOf('## Observed Usage') | Should -BeLessThan $ledger.IndexOf('## Cost Comparison')
        $ledger | Should -Match '\*\*0\.3171\*\*' -Because 'the estimated tables are kept unchanged'

        $check = Invoke-Ledger -SquadRoot $f.Root -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Scribe' = 1 }
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }

    It 'replaces the section on a later rewrite instead of appending a second one' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        (Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write).ExitCode | Should -Be 0
        $first = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        (Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write).ExitCode | Should -Be 0
        $second = Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw
        @([regex]::Matches($second, '(?m)^## Observed Usage')).Count | Should -Be 1
        $second | Should -Be $first
    }

    It 'finds the session with -SessionLog auto through COPILOT_HOME and the workspace cwd' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog 'auto' -CopilotHome $f.Home -Format json
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $json = ($result.Output -split '\r?\n' | Where-Object { $_ -notmatch '^(WARNING|AVERTISSEMENT)' }) -join "`n" | ConvertFrom-Json
        $json.observed.sessionId | Should -Be 'sess-0001'
        $json.observed.observedTokens | Should -Be 800000
        $json.observed.baselineModel | Should -Be 'claude-sonnet-4.6'
    }

    It 'warns and adds nothing when auto finds no session for this repository' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        Set-Content -LiteralPath (Join-Path $f.SessionDir 'workspace.yaml') -Value "cwd: C:\elsewhere`n"
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog 'auto' -CopilotHome $f.Home -Write
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'found no Copilot session'
        (Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw) | Should -Not -Match 'Observed Usage'
    }

    It 'flags a dispatch whose observed model differs from the model its history records' {
        $events = $script:BaseEvents.Clone()
        $events[2] = $events[2].Replace('"model":"claude-sonnet-4.6"', '"model":"claude-opus-5"')
        $f = New-SessionFixtureLocal -EventLines $events
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Write
        $result.Output | Should -Match "observed model for 'Squad Researcher' is claude-opus-5 but its history blocks record Claude Sonnet 4\.6"
        (Get-Content -LiteralPath (Join-Path $f.Root 'consumption.md') -Raw) | Should -Match '\| Squad Researcher \| 1 \| claude-opus-5 \| Claude Sonnet 4\.6 \| no \|'
    }

    It 'prices the comparison at -BaselineModel when supplied' {
        $f = New-SessionFixtureLocal -EventLines $script:BaseEvents
        $result = Invoke-LedgerWithSessionLocal -Root $f.Root -SessionLog $f.SessionDir -Format json -BaselineModel 'Claude Opus 5'
        $json = ($result.Output -split '\r?\n' | Where-Object { $_ -notmatch '^(WARNING|AVERTISSEMENT)' }) -join "`n" | ConvertFrom-Json
        $json.observed.baselineModel | Should -Be 'Claude Opus 5'
        $json.observed.baselineCostUsd | Should -Be 1.2 -Because '500,000 tokens x (0.20x5 + 0.80x0.5 + 0.08x6.25 + 0.02x25 = 2.40) / 1e6'
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
        $json.observed.observedTokens | Should -Be 400000
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

Describe 'Measure-SquadLedger puts the billed session total next to the estimated total' {
    It 'adds a billed line with the estimate-to-billed ratio under the Usage & Cost total, and -Check still passes' {
        $repo = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        $root = Join-Path $repo '.copilot-tracking/squad'
        New-Item -ItemType Directory -Path (Split-Path -Parent $root) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:FixtureRoot 'applied') -Destination $root -Recurse
        $sessionDir = Join-Path $repo 'session'
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sessionDir 'events.jsonl') -Value (@(
                '{"type":"subagent.completed","data":{"toolCallId":"t1","agentName":"Squad Researcher","model":"claude-sonnet-4.6","totalTokens":100000,"durationMs":1000},"timestamp":"2026-10-01T10:00:00.000Z"}'
                '{"type":"session.usage_checkpoint","data":{"totalNanoAiu":15855000000},"timestamp":"2026-10-01T10:01:00.000Z"}'
            ) -join "`n")

        $output = & pwsh -NoProfile -Command "& '$script:LedgerScript' -SquadRoot '$root' -Write -SessionLog '$sessionDir'" 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
        $ledger = Get-Content -LiteralPath (Join-Path $root 'consumption.md') -Raw
        $ledger | Should -Match '(?s)\*\*0\.3171\*\*.*?> \*\*Billed by the host for this session so far: 15\.86 AI units, about 0\.16 USD\.\*\* The estimate above is 2\.00x that figure\.'
        $ledger.IndexOf('Billed by the host') | Should -BeLessThan $ledger.IndexOf('### Derivation')

        $check = Invoke-Ledger -SquadRoot $root -Check -ExpectedHistoryCounts @{ 'Squad Researcher' = 1; 'Squad Scribe' = 1 }
        $check.ExitCode | Should -Be 0 -Because $check.Output
    }
}