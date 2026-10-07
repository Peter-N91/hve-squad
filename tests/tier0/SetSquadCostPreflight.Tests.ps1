#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Behavioral coverage for the deterministic Cost Preflight transaction, squad skill
# scripts/Set-SquadCostPreflight.ps1. Runs the script as a child process against TestDrive
# roots, because it calls `exit` and would otherwise end the Pester run. Invokes no model.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read inside BeforeAll, which PSScriptAnalyzer treats as an unrelated scope.')]
param(
    [Parameter(Mandatory)]
    [string]$PackageRoot
)

BeforeAll {
    $script:Script = Join-Path $PackageRoot '.agents/skills/squad/scripts/Set-SquadCostPreflight.ps1'
    $script:Utf8 = [System.Text.UTF8Encoding]::new($false)

    function Invoke-Preflight {
        param([Parameter(Mandatory)][string[]]$Arguments)
        $output = & pwsh -NoProfile -File $script:Script @Arguments *>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    function New-PreflightJson {
        param(
            [string]$Decision = 'within-ceiling',
            [string]$RunId = 'run-1',
            [string]$RoundId = 'round-1',
            [object]$Ceiling = 5
        )
        if ($Decision -eq 'not-requested') {
            return '{"runId":"","roundId":"","ceilingUsd":null,"evaluatedSpendUsd":0,"remainingUsd":null,"plannedDispatches":0,"projectedCostUsd":0,"reserveMultiplier":3.0,"admissionCostUsd":0,"confidence":"not-applicable","basis":"not-requested","decision":"not-requested","reason":"No cost ceiling configured."}'
        }
        '{"runId":"' + $RunId + '","roundId":"' + $RoundId + '","ceilingUsd":' + $Ceiling + ',"evaluatedSpendUsd":0.5,"remainingUsd":4.5,"plannedDispatches":3,"projectedCostUsd":1.25,"reserveMultiplier":3.0,"admissionCostUsd":3.75,"confidence":"medium","basis":"calibrated","decision":"' + $Decision + '","reason":"Fits."}'
    }

    function New-DecisionText {
        param([string]$Decision = 'within-ceiling', [string]$RunId = 'run-1', [string]$RoundId = 'round-1')
        "## Cost Preflight 2026-10-03T19:00:00Z $RunId $RoundId`n`n* Ceiling USD: 5`n* Decision: $Decision`n* Reason: Fits.`n"
    }

    function New-SquadFixture {
        <#
        .SYNOPSIS
            Writes a squad root whose state.json mirrors the Scribe seed, optionally in legacy form.
        #>
        param(
            [ValidateSet('current', 'legacy', 'federation-legacy', 'current-missing')][string]$Kind = 'current',
            [AllowEmptyString()][string]$RoutingLine = 'Model routing: economy'
        )
        $root = Join-Path $TestDrive "squad-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $team = @('# Squad Roster', '')
        if ($RoutingLine) { $team += @($RoutingLine, '') }
        [System.IO.File]::WriteAllText((Join-Path $root 'team.md'), (($team + '## Members') -join "`n") + "`n", $script:Utf8)
        $preflight = '"costPreflight": {"runId":"","roundId":"","ceilingUsd":null,"evaluatedSpendUsd":0,"remainingUsd":null,"plannedDispatches":0,"projectedCostUsd":0,"reserveMultiplier":3.0,"admissionCostUsd":0,"confidence":"not-applicable","basis":"not-requested","decision":"not-requested","reason":"No cost ceiling configured."}'
        $runBody = '"sessionModel": "claude-sonnet-5.5", "modelOverrides": {"developer": "gpt-5.6-sol"}, "estCostUsd": 1.5, "estCreditsTotal": 150'
        if ($Kind -notin 'current') { $currentRun = '{' + $runBody + '}' } else { $currentRun = '{' + $runBody + ', ' + $preflight + '}' }
        $schema = switch ($Kind) { 'current' { '1.4' } 'current-missing' { '1.4' } 'legacy' { '1.3' } default { '1.2' } }
        $roleKey = if ($Kind -eq 'federation-legacy') { '"subSquads": ["a"], "activeSubSquads": [], ' } else { '"activeRoles": ["researcher"], ' }
        $json = '{"schemaVersion": "' + $schema + '", "updated": "2026-10-03T18:00:00Z", "turn": 4, "mode": "interactive", ' + $roleKey + '"openEscalations": [], "currentRun": ' + $currentRun + ', "trigger": {"ref": "o/r#1"}, "notify": {"approvalChannel": "in-chat", "enabled": false, "email": "", "github": {"handle": "", "repo": ""}}}'
        $pretty = $json | ConvertFrom-Json | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText((Join-Path $root 'state.json'), $pretty + "`n", $script:Utf8)
        [System.IO.File]::WriteAllText((Join-Path $root 'decisions.md'), "# Decisions`n`n## Earlier 2026-10-01`n`n* Note: prior.`n", $script:Utf8)
        $root
    }

    function Get-Bytes {
        param([string]$Root)
        @{
            State     = [System.IO.File]::ReadAllBytes((Join-Path $Root 'state.json'))
            Decisions = [System.IO.File]::ReadAllBytes((Join-Path $Root 'decisions.md'))
        }
    }

    function Assert-Untouched {
        param([string]$Root, $Before)
        $after = Get-Bytes -Root $Root
        [System.Convert]::ToBase64String($after.State) | Should -BeExactly ([System.Convert]::ToBase64String($Before.State))
        [System.Convert]::ToBase64String($after.Decisions) | Should -BeExactly ([System.Convert]::ToBase64String($Before.Decisions))
    }

    function Read-State {
        param([string]$Root)
        [System.IO.File]::ReadAllText((Join-Path $Root 'state.json')) | ConvertFrom-Json -Depth 20
    }
}

Describe 'Set-SquadCostPreflight.ps1 runs only under Model routing: economy (G2)' {
    It 'refuses with exit 7 and leaves both files untouched when team.md records <Case>' -ForEach @(
        @{ Case = 'Model routing: ranked'; Line = 'Model routing: ranked' }
        @{ Case = 'no Model routing line'; Line = '' }
    ) {
        $root = New-SquadFixture -RoutingLine $Line
        $before = Get-Bytes -Root $root
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 7 -Because $result.Output
        $result.Output | Should -Match 'economy-only'
        Assert-Untouched -Root $root -Before $before
    }

    It 'refuses with exit 7 when the squad root has no team.md' {
        $root = New-SquadFixture
        Remove-Item -LiteralPath (Join-Path $root 'team.md')
        $before = Get-Bytes -Root $root
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 7 -Because $result.Output
        Assert-Untouched -Root $root -Before $before
    }

    It 'writes the transaction when team.md records Model routing: economy' {
        $root = New-SquadFixture
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 0 -Because $result.Output
    }
}

Describe 'Set-SquadCostPreflight.ps1 writes the transaction' {
    It 'the script ships in the squad skill' {
        Test-Path -LiteralPath $script:Script -PathType Leaf | Should -BeTrue
    }

    It 'appends the decision once, replaces only costPreflight, and reports the Decision Ref' {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'WRITTEN decision=within-ceiling'
        $result.Output | Should -Match 'decisionRef=decisions\.md#cost-preflight-2026-10-03t190000z-run-1-round-1'

        $state = Read-State -Root $root
        $state.currentRun.costPreflight.decision | Should -Be 'within-ceiling'
        $state.currentRun.costPreflight.ceilingUsd | Should -Be 5
        $state.currentRun.costPreflight.reserveMultiplier | Should -Be 3
        $state.schemaVersion | Should -Be '1.4'

        $decisions = [System.IO.File]::ReadAllText((Join-Path $root 'decisions.md'))
        ([regex]::Matches($decisions, '(?m)^## Cost Preflight ')).Count | Should -Be 1
        $decisions.StartsWith([System.Text.Encoding]::UTF8.GetString($before.Decisions)) | Should -BeTrue
    }

    It 'preserves every other state value, including trigger, models, totals, and notify' {
        $root = New-SquadFixture
        $original = Read-State -Root $root
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $state = Read-State -Root $root
        $state.updated | Should -Be $original.updated
        $state.turn | Should -Be 4
        $state.mode | Should -Be 'interactive'
        @($state.activeRoles) | Should -Be @('researcher')
        $state.trigger.ref | Should -Be 'o/r#1'
        $state.currentRun.sessionModel | Should -Be 'claude-sonnet-5.5'
        $state.currentRun.modelOverrides.developer | Should -Be 'gpt-5.6-sol'
        $state.currentRun.estCostUsd | Should -Be 1.5
        $state.currentRun.estCreditsTotal | Should -Be 150
        $state.notify.approvalChannel | Should -Be 'in-chat'
        $state.notify.github.handle | Should -Be ''
        @($state.openEscalations).Count | Should -Be 0
    }

    It 'migrates legacy single-squad 1.3 to exactly 1.4 and adds the object' {
        $root = New-SquadFixture -Kind legacy
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $state = Read-State -Root $root
        $state.schemaVersion | Should -Be '1.4'
        $state.currentRun.costPreflight.decision | Should -Be 'within-ceiling'
        $state.currentRun.sessionModel | Should -Be 'claude-sonnet-5.5'
        $state.currentRun.estCostUsd | Should -Be 1.5
        $state.trigger.ref | Should -Be 'o/r#1'
    }

    It 'migrates a legacy federation root 1.2 to exactly 1.3' {
        $root = New-SquadFixture -Kind federation-legacy
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Read-State -Root $root).schemaVersion | Should -Be '1.3'
    }

    It 'a no-ceiling legacy migration persists not-requested without touching decisions.md' {
        $root = New-SquadFixture -Kind legacy
        $before = Get-Bytes -Root $root
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson -Decision 'not-requested'))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Read-State -Root $root).schemaVersion | Should -Be '1.4'
        [System.Convert]::ToBase64String((Get-Bytes -Root $root).Decisions) | Should -BeExactly ([System.Convert]::ToBase64String($before.Decisions))
    }

    It 'writes nothing and exits 0 when the same not-requested object is already persisted' {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson -Decision 'not-requested'))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match 'UNCHANGED'
        Assert-Untouched -Root $root -Before $before
    }

    It 'a 1.4 state lacking currentRun.costPreflight accepts a ceiling write and adds the object without a schema change' {
        $root = New-SquadFixture -Kind current-missing
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $state = Read-State -Root $root
        $state.schemaVersion | Should -Be '1.4'
        $state.currentRun.costPreflight.decision | Should -Be 'within-ceiling'
        $state.currentRun.estCostUsd | Should -Be 1.5
        ([regex]::Matches([System.IO.File]::ReadAllText((Join-Path $root 'decisions.md')), '(?m)^## Cost Preflight ')).Count | Should -Be 1
    }

    It 'a 1.4 state lacking currentRun.costPreflight accepts a not-requested write' {
        $root = New-SquadFixture -Kind current-missing
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson -Decision 'not-requested'))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $state = Read-State -Root $root
        $state.schemaVersion | Should -Be '1.4'
        $state.currentRun.costPreflight.decision | Should -Be 'not-requested'
    }

    It 'a second round appends a second entry and the first stays byte-identical' {
        $root = New-SquadFixture
        $null = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $mid = [System.IO.File]::ReadAllText((Join-Path $root 'decisions.md'))
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson -Decision 'over-ceiling' -RoundId 'round-2'), '-DecisionText', (New-DecisionText -Decision 'over-ceiling' -RoundId 'round-2'))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $after = [System.IO.File]::ReadAllText((Join-Path $root 'decisions.md'))
        $after.StartsWith($mid) | Should -BeTrue
        ([regex]::Matches($after, '(?m)^## Cost Preflight ')).Count | Should -Be 2
    }

    It 'accepts -PreflightPath and -DecisionPath and writes the same transaction' {
        $root = New-SquadFixture
        $pre = Join-Path $TestDrive "pre-$([guid]::NewGuid().ToString('N')).json"
        $dec = Join-Path $TestDrive "dec-$([guid]::NewGuid().ToString('N')).md"
        [System.IO.File]::WriteAllText($pre, (New-PreflightJson), $script:Utf8)
        [System.IO.File]::WriteAllText($dec, (New-DecisionText), $script:Utf8)
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightPath', $pre, '-DecisionPath', $dec)
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Read-State -Root $root).currentRun.costPreflight.decision | Should -Be 'within-ceiling'
        ([regex]::Matches([System.IO.File]::ReadAllText((Join-Path $root 'decisions.md')), '(?m)^## Cost Preflight ')).Count | Should -Be 1
    }

    It 'does not mistake round-10 for a replay of round-1 with the same timestamp' {
        $root = New-SquadFixture
        $path = Join-Path $root 'decisions.md'
        $prior = [System.IO.File]::ReadAllText($path) + "`n## Cost Preflight 2026-10-03T19:00:00Z run-1 round-10`n`n* Decision: within-ceiling`n"
        [System.IO.File]::WriteAllText($path, $prior, $script:Utf8)
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 0 -Because $result.Output
        ([regex]::Matches([System.IO.File]::ReadAllText($path), '(?m)^## Cost Preflight ')).Count | Should -Be 2
    }
}

Describe 'Set-SquadCostPreflight.ps1 rejects without writing' {
    It 'a stale ExpectedUpdated is a collision (exit 2) and both files stay byte-identical' {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T17:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match 'collision'
        Assert-Untouched -Root $root -Before $before
    }

    It 'an unknown key is rejected (exit 1) and both files stay byte-identical' {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $json = (New-PreflightJson).TrimEnd('}') + ',"scratch":1}'
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', $json, '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match "unknown key 'scratch'"
        Assert-Untouched -Root $root -Before $before
    }

    It 'a missing key is rejected (exit 1)' {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $json = (New-PreflightJson) -replace '"reason":"Fits."', '"why":"x"'
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', $json, '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 1
        Assert-Untouched -Root $root -Before $before
    }

    It 'an invalid decision, confidence, or non-positive ceiling is rejected (exit 1)' -ForEach @(
        @{ Name = 'decision'; Edit = { param($j) $j -replace '"decision":"within-ceiling"', '"decision":"maybe"' } }
        @{ Name = 'confidence'; Edit = { param($j) $j -replace '"confidence":"medium"', '"confidence":"high"' } }
        @{ Name = 'ceiling'; Edit = { param($j) $j -replace '"ceilingUsd":5', '"ceilingUsd":0' } }
        @{ Name = 'type'; Edit = { param($j) $j -replace '"plannedDispatches":3', '"plannedDispatches":"3"' } }
        @{ Name = 'reserveMultiplier'; Edit = { param($j) $j -replace '"reserveMultiplier":3.0', '"reserveMultiplier":1.0' } }
    ) {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $json = & $Edit (New-PreflightJson)
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', $json, '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 1 -Because "${Name}: $($result.Output)"
        Assert-Untouched -Root $root -Before $before
    }

    It 'a decision text whose heading ids or Decision line mismatch the object is rejected' -ForEach @(
        @{ Name = 'round'; Text = { New-DecisionText -RoundId 'round-9' } }
        @{ Name = 'decision line'; Text = { New-DecisionText -Decision 'over-ceiling' } }
        @{ Name = 'missing'; Text = { '' } }
        @{ Name = 'second heading'; Text = { (New-DecisionText) + "`n## Cost Preflight 2026-10-03T19:00:00Z run-1 round-2`n" } }
        @{ Name = 'second Decision line'; Text = { (New-DecisionText) + "* Decision: over-ceiling`n" } }
    ) {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $arguments = @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson))
        $text = & $Text
        if ($text) { $arguments += @('-DecisionText', $text) }
        $result = Invoke-Preflight -Arguments $arguments
        $result.ExitCode | Should -Be 1 -Because "${Name}: $($result.Output)"
        Assert-Untouched -Root $root -Before $before
    }

    It 'replaying the same round is rejected so the entry is appended exactly once' {
        $root = New-SquadFixture
        $arguments = @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        (Invoke-Preflight -Arguments $arguments).ExitCode | Should -Be 0
        $before = Get-Bytes -Root $root
        $replay = Invoke-Preflight -Arguments $arguments
        $replay.ExitCode | Should -Be 1
        Assert-Untouched -Root $root -Before $before
    }

    It 'an unsupported schema version is rejected' {
        $root = New-SquadFixture
        $path = Join-Path $root 'state.json'
        [System.IO.File]::WriteAllText($path, ([System.IO.File]::ReadAllText($path) -replace '"schemaVersion": "1.4"', '"schemaVersion": "9.9"'), $script:Utf8)
        $before = Get-Bytes -Root $root
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        $result.ExitCode | Should -Be 1
        Assert-Untouched -Root $root -Before $before
    }

    It 'a read-only state.json fails without corrupting either file' {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $path = Join-Path $root 'state.json'
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
            $result.ExitCode | Should -Be 3
            $result.Output | Should -Match 'read-only'
        }
        finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false
        }
        Assert-Untouched -Root $root -Before $before
    }

    It 'a read-only decisions.md fails without corrupting either file' {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $path = Join-Path $root 'decisions.md'
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
            $result.ExitCode | Should -Be 3
        }
        finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false
        }
        Assert-Untouched -Root $root -Before $before
    }

    It 'a not-requested decision refuses a decision entry' {
        $root = New-SquadFixture -Kind legacy
        $before = Get-Bytes -Root $root
        $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson -Decision 'not-requested'), '-DecisionText', (New-DecisionText -Decision 'not-requested'))
        $result.ExitCode | Should -Be 1
        Assert-Untouched -Root $root -Before $before
    }

    # A held handle without delete sharing makes only the state.json move fail, after decisions.md was written.
    It 'restores decisions.md byte-for-byte when the state.json write fails' -Skip:(-not $IsWindows) {
        $root = New-SquadFixture
        $before = Get-Bytes -Root $root
        $handle = [System.IO.File]::Open((Join-Path $root 'state.json'), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try {
            $result = Invoke-Preflight -Arguments @('-SquadRoot', $root, '-ExpectedUpdated', '2026-10-03T18:00:00Z', '-PreflightJson', (New-PreflightJson), '-DecisionText', (New-DecisionText))
        }
        finally {
            $handle.Dispose()
        }
        $result.ExitCode | Should -Be 3 -Because $result.Output
        $result.Output | Should -Match 'decisions\.md restored'
        Assert-Untouched -Root $root -Before $before
        @(Get-ChildItem -LiteralPath $root -Force -Filter '*.tmp').Count | Should -Be 0
    }
}
