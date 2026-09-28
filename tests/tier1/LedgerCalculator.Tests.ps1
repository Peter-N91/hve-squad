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
        #>
        param(
            [Parameter(Mandatory)][string]$SquadRoot,
            [switch]$Check,
            [string]$Format
        )
        $scriptArgs = @('-NoProfile', '-File', $script:LedgerScript, '-SquadRoot', $SquadRoot)
        if ($Check) { $scriptArgs += '-Check' }
        if ($Format) { $scriptArgs += @('-Format', $Format) }
        $output = & pwsh @scriptArgs 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
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
