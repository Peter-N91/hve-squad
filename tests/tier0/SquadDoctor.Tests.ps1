#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'PackageRoot',
    Justification = 'Read in Pester BeforeAll.')]
param([Parameter(Mandatory)][string]$PackageRoot)

BeforeAll {
    Set-StrictMode -Version Latest
    $script:Package = $PackageRoot
    $script:OriginalCopilotHome = $env:COPILOT_HOME
    $env:COPILOT_HOME = Join-Path $TestDrive 'empty-copilot-home'
    $null = New-Item -ItemType Directory -Path $env:COPILOT_HOME
    $script:Skill = Join-Path $PackageRoot '.agents/skills/squad'
    $script:Doctor = Join-Path $script:Skill 'scripts/Invoke-SquadDoctor.ps1'
    $script:Seeder = Join-Path $script:Skill 'scripts/Initialize-SquadConsumptionRates.ps1'
    Import-Module (Join-Path $PSScriptRoot 'SquadPackage.psm1') -Force
    $script:Model = Get-SquadPackageModel -PackageRoot $PackageRoot
    $script:Inventory = @('hve-core:security-planner', 'hve-core:rai-planner', 'hve-core:privacy-planner',
        'hve-core:accessibility-framework-assessor', 'hve-core:prd-builder', 'hve-core:dt-coach', 'hve-core:code-review-functional')

    function Write-DoctorFile {
        param([string]$Path, [string]$Text)
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
        [IO.File]::WriteAllText($Path, $Text)
    }

    function New-DoctorFixture {
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repo
        Write-DoctorFile (Join-Path $repo 'inventory.json') (ConvertTo-Json -InputObject $script:Inventory -Compress)
        [pscustomobject]@{ Repo = $repo; Root = Join-Path $repo '.copilot-tracking/squad' }
    }

    function Invoke-Doctor {
        param($Fixture, [string[]]$Extra = @(), [switch]$WithoutInventory, [string]$Script = $script:Doctor)
        $arguments = @('-RepoRoot', $Fixture.Repo)
        if (-not $WithoutInventory) { $arguments += @('-InventoryPath', 'inventory.json') }
        $output = & pwsh -NoProfile -File $Script @arguments @Extra | Out-String
        $code = $LASTEXITCODE
        [pscustomobject]@{ Code = $code; Data = ConvertFrom-Json -InputObject $output; Raw = $output }
    }

    function New-DoctorTeam {
        param([string]$Root)
        Write-DoctorFile (Join-Path $Root 'team.md') "# Squad Roster`n"
    }

    function Get-DoctorSnapshot {
        param([string]$Root)
        (Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
            "$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)|$((Get-FileHash -LiteralPath $_.FullName).Hash)"
        }) -join "`n"
    }
}

AfterAll { $env:COPILOT_HOME = $script:OriginalCopilotHome }

Describe 'Squad Doctor entrypoints and recovery (SDOC-01, SDOC-06)' {
    It 'ships a user-selectable dispatchable agent and bound prompt' {
        $agent = @($script:Model.SquadAgents | Where-Object Name -eq 'squad-doctor.agent.md')
        $prompt = @($script:Model.Prompts | Where-Object Name -eq 'squad-doctor.prompt.md')
        $agent | Should -HaveCount 1
        $prompt | Should -HaveCount 1
        $agent[0].Meta['user-invocable'] | Should -Be 'true'
        $agent[0].Meta['disable-model-invocation'] | Should -Not -Be 'true'
        $prompt[0].Meta['agent'] | Should -BeExactly 'Squad Doctor'
        $agent[0].Body | Should -Match 'No squad state is required'
        $agent[0].Body | Should -Match 'Only the installed `Invoke-SquadDoctor.ps1` may perform repairs'
    }

    It 'allows both coordinators to dispatch maintenance before a broken roster is planned' {
        foreach ($name in @('squad-coordinator.agent.md', 'squad-federation-coordinator.agent.md')) {
            $agent = @($script:Model.SquadAgents | Where-Object Name -eq $name)[0]
            $agent.Meta['agents'] | Should -Contain 'Squad Doctor'
        }
        foreach ($name in @('coordinator-runtime.md', 'federation-runtime.md')) {
            $body = [IO.File]::ReadAllText((Join-Path $script:Skill "references/$name"))
            $body | Should -Match 'doctor.md'
            $body | Should -Match 'stop work; use `doctor.md` before Init/planning'
        }
        $contract = [IO.File]::ReadAllText((Join-Path $script:Skill 'references/doctor.md'))
        $contract | Should -Match 'invoke Doctor once'
        $contract | Should -Match 'all original gates/admission still hold'
        $contract | Should -Match 'rerun the original failing operation once'
        $contract | Should -Match 'unattended run it returns the repair request as a blocker'
    }
}

Describe 'Squad Doctor deterministic checks (SDOC-02)' {
    It 'checks all seven host domains without initializing or writing files' {
        $f = New-DoctorFixture
        $before = Get-DoctorSnapshot $f.Repo
        $result = Invoke-Doctor $f
        $result.Code | Should -Be 0 -Because $result.Raw
        $result.Data.status | Should -Be 'healthy'
        @($result.Data.findings | Where-Object id -Like 'domain:*') | Should -HaveCount 7
        @($result.Data.findings | Where-Object status -ne 'pass') | Should -HaveCount 0
        Test-Path -LiteralPath $f.Root | Should -BeFalse
        Get-DoctorSnapshot $f.Repo | Should -BeExactly $before
    }

    It 'distinguishes unavailable inventory from an empty host inventory' {
        $f = New-DoctorFixture
        $unknown = Invoke-Doctor $f -WithoutInventory
        $unknown.Code | Should -Be 2
        @($unknown.Data.findings | Where-Object status -eq 'unverified') | Should -HaveCount 7
        Write-DoctorFile (Join-Path $f.Repo 'inventory.json') '[]'
        $empty = Invoke-Doctor $f
        $empty.Code | Should -Be 2
        @($empty.Data.findings | Where-Object { $_.id -like 'domain:*' -and $_.status -eq 'fail' }) | Should -HaveCount 7
    }

    It 'does not accept Squad glue or similar names as a domain representative' {
        $f = New-DoctorFixture
        Write-DoctorFile (Join-Path $f.Repo 'inventory.json') '["squad:squad-reviewer","custom:security-planner-extra"]'
        $result = Invoke-Doctor $f -Extra @('-Scope', 'security')
        $result.Code | Should -Be 2
        @($result.Data.findings | Where-Object id -Like 'domain:*') | Should -HaveCount 1
        @($result.Data.findings | Where-Object id -eq 'domain:security')[0].status | Should -Be 'fail'
    }

    It 'reports partial state as blocked without repairing or seeding it' {
        $f = New-DoctorFixture
        Write-DoctorFile (Join-Path $f.Root 'state.json') '{}'
        $before = Get-DoctorSnapshot $f.Repo
        $result = Invoke-Doctor $f -Extra @('-Repair', 'rates', '-Confirmed')
        $result.Code | Should -Be 2
        $result.Data.repairs | Should -HaveCount 0
        Get-DoctorSnapshot $f.Repo | Should -BeExactly $before
    }
}

Describe 'Squad Doctor allowlisted repairs (SDOC-03)' {
    It 'returns repaired then healthy against a real initialized squad and ledger' {
        $f = New-DoctorFixture
        $null = New-Item -ItemType Directory -Path (Join-Path $f.Repo '.github') -Force
        Copy-Item -LiteralPath (Join-Path $script:Package '.github/agents') -Destination (Join-Path $f.Repo '.github/agents') -Recurse
        Copy-Item -LiteralPath (Join-Path $script:Package '.github/instructions') -Destination (Join-Path $f.Repo '.github/instructions') -Recurse
        $choices = @{
            confirmed = $true; squadRoot = '.copilot-tracking/squad'; runId = 'doctor-fixture'
            profile = 'default'; naming = 'aliases'
            notify = @{ approvalChannel = 'in-chat'; enabled = $false }
            sessionModel = 'claude-sonnet-5.5'
        }
        Write-DoctorFile (Join-Path $f.Repo 'choices.json') ($choices | ConvertTo-Json -Depth 6)
        $payload = Join-Path $f.Repo 'init.json'
        $prepared = & pwsh -NoProfile -File (Join-Path $script:Skill 'scripts/Get-SquadInitContext.ps1') `
            -RepoRoot $f.Repo -ChoicesPath (Join-Path $f.Repo 'choices.json') -PayloadPath $payload 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $prepared
        $initialized = & pwsh -NoProfile -File (Join-Path $script:Skill 'scripts/Initialize-Squad.ps1') `
            -RepoRoot $f.Repo -PayloadPath $payload -Direct 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $initialized
        $healthy = Invoke-Doctor $f
        $healthy.Code | Should -Be 0 -Because $healthy.Raw
        $healthy.Data.status | Should -Be 'healthy'
        Remove-Item -LiteralPath (Join-Path $f.Root 'consumption-rates.md')
        $repaired = Invoke-Doctor $f -Extra @('-Repair', 'rates', '-Confirmed')
        $repaired.Code | Should -Be 0 -Because $repaired.Raw
        $repaired.Data.status | Should -Be 'repaired'
        (Invoke-Doctor $f).Data.status | Should -Be 'healthy'
    }

    It 'rejects repair without confirmation before any writes' {
        $f = New-DoctorFixture
        New-DoctorTeam $f.Root
        $before = Get-DoctorSnapshot $f.Repo
        $result = Invoke-Doctor $f -Extra @('-Repair', 'rates')
        $result.Code | Should -Be 1
        $result.Raw | Should -Match 'explicit -Confirmed'
        Get-DoctorSnapshot $f.Repo | Should -BeExactly $before
    }

    It 'repairs missing rates, rechecks, and leaves unsupported state faults unresolved' {
        $f = New-DoctorFixture
        New-DoctorTeam $f.Root
        $check = Invoke-Doctor $f
        $check.Code | Should -Be 2
        Test-Path (Join-Path $f.Root 'consumption-rates.md') | Should -BeFalse
        $result = Invoke-Doctor $f -Extra @('-Repair', 'rates', '-Confirmed')
        $result.Code | Should -Be 2
        $result.Data.status | Should -Be 'attention'
        $result.Data.repairs | Should -HaveCount 1
        $result.Data.repairs[0].status | Should -Be 'repaired'
        $result.Data.repairs[0].backup | Should -BeNullOrEmpty
        $before = Get-DoctorSnapshot $f.Repo
        $again = Invoke-Doctor $f -Extra @('-Repair', 'rates', '-Confirmed')
        $again.Data.repairs | Should -HaveCount 0
        Get-DoctorSnapshot $f.Repo | Should -BeExactly $before
    }

    It 'preserves an invalid file in a content-addressed backup before repair' {
        $f = New-DoctorFixture
        New-DoctorTeam $f.Root
        $path = Join-Path $f.Root 'consumption-rates.md'
        Write-DoctorFile $path "# obsolete rates`n"
        $hash = (Get-FileHash -LiteralPath $path).Hash
        $result = Invoke-Doctor $f -Extra @('-Repair', 'rates', '-Confirmed')
        $result.Data.repairs[0].status | Should -Be 'repaired' -Because $result.Raw
        (Get-FileHash -LiteralPath $result.Data.repairs[0].backup).Hash | Should -Be $hash
        @($result.Data.findings | Where-Object id -eq 'rates')[0].status | Should -Be 'pass'
    }

    It 'refuses a seeder rewrite that would discard malformed operator rows' {
        $f = New-DoctorFixture
        New-DoctorTeam $f.Root
        & pwsh -NoProfile -File $script:Seeder -SquadRoot $f.Root | Out-Null
        $path = Join-Path $f.Root 'consumption-rates.md'
        $text = [IO.File]::ReadAllText($path)
        $text = [regex]::new('(?m)^(\| GPT-5.4 nano[^\r\n]+)$').Replace(
            $text, ('$1' + "`n| Custom Model | ``custom-model`` | fast | invalid | 0 | 0 | 0 |"), 1)
        $text | Should -Match 'custom-model'
        Write-DoctorFile $path $text
        $hash = (Get-FileHash -LiteralPath $path).Hash
        $result = Invoke-Doctor $f -Extra @('-Repair', 'rates', '-Confirmed')
        $result.Code | Should -Be 2 -Because $result.Raw
        $result.Data.repairs[0].status | Should -Be 'failed'
        (Get-FileHash -LiteralPath $path).Hash | Should -Be $hash
    }

    It 'does not reseed or reprice an already valid customized table' {
        $f = New-DoctorFixture
        New-DoctorTeam $f.Root
        & pwsh -NoProfile -File $script:Seeder -SquadRoot $f.Root | Out-Null
        $path = Join-Path $f.Root 'consumption-rates.md'
        $text = [IO.File]::ReadAllText($path) -replace 'calibration_factor: 1.0', 'calibration_factor: 1.25'
        $text = [regex]::new('(?m)^(\| GPT-5.4 nano[^\r\n]+)$').Replace(
            $text, ('$1' + "`n| Custom Model | ``custom-model`` | fast | 1 | 0.1 | 0 | 2 |"), 1)
        Write-DoctorFile $path $text
        $before = Get-DoctorSnapshot $f.Repo
        $result = Invoke-Doctor $f -Extra @('-Repair', 'rates', '-Confirmed')
        $result.Data.repairs | Should -HaveCount 0 -Because $result.Raw
        Get-DoctorSnapshot $f.Repo | Should -BeExactly $before
    }
}

Describe 'Squad Doctor safety and federation scope (SDOC-04, SDOC-05)' {
    It 'rejects repository escape and malformed host inventory' {
        $f = New-DoctorFixture
        (Invoke-Doctor $f -Extra @('-SquadRoot', '..\outside')).Code | Should -Be 1
        Write-DoctorFile (Join-Path $f.Repo 'inventory.json') '{"agents":[]}'
        (Invoke-Doctor $f).Code | Should -Be 1
    }

    It 'fails closed on missing installed runtime' {
        $f = New-DoctorFixture
        $broken = Join-Path $f.Repo 'broken-skill'
        Copy-Item -LiteralPath $script:Skill -Destination $broken -Recurse
        Remove-Item -LiteralPath (Join-Path $broken 'scripts/Measure-SquadLedger.ps1')
        $result = Invoke-Doctor $f -Script (Join-Path $broken 'scripts/Invoke-SquadDoctor.ps1')
        $result.Code | Should -Be 1
        $result.Raw | Should -Match 'Installed runtime file missing'
    }

    It 'does not write while a handoff owns the shared root lock' {
        $f = New-DoctorFixture
        New-DoctorTeam $f.Root
        $key = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes($f.Root.ToLowerInvariant()))).Substring(0, 16)
        $lockPath = Join-Path ([IO.Path]::GetTempPath()) "hve-squad-handoff-$key.lock"
        $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $result = Invoke-Doctor $f -Extra @('-Repair', 'rates', '-Confirmed')
            $result.Code | Should -Be 2 -Because $result.Raw
            $result.Raw | Should -Match 'Writer lock unavailable'
            Test-Path (Join-Path $f.Root 'consumption-rates.md') | Should -BeFalse
        }
        finally { $lock.Dispose() }
    }

    It 'rejects linked member roots without writing through them' {
        $f = New-DoctorFixture
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $outside
        New-DoctorTeam $outside
        $null = New-Item -ItemType Directory -Path $f.Root -Force
        $link = Join-Path $f.Root 'linked'
        $type = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $type -Path $link -Target $outside
        $result = Invoke-Doctor $f -Extra @('-SquadRoot', $link, '-Repair', 'rates', '-Confirmed')
        $result.Code | Should -Be 1
        $result.Raw | Should -Match 'Linked repository path refused'
        Test-Path (Join-Path $outside 'consumption-rates.md') | Should -BeFalse
    }

    It 'repairs registered federation members but not unregistered or sibling roots in member scope' {
        $f = New-DoctorFixture
        Write-DoctorFile (Join-Path $f.Root 'federation.md') @'
| Sub-squad | Location |
|---|---|
| one | members/one/ |
| two | members/two/ |
'@
        foreach ($name in @('one', 'two', 'unregistered')) {
            New-DoctorTeam (Join-Path $f.Root "members/$name")
        }
        $one = Join-Path $f.Root 'members/one'
        $two = Join-Path $f.Root 'members/two'
        $scoped = Invoke-Doctor $f -Extra @('-SquadRoot', $one, '-Repair', 'rates', '-Confirmed')
        $scoped.Data.repairs | Should -HaveCount 1
        Test-Path (Join-Path $two 'consumption-rates.md') | Should -BeFalse
        $whole = Invoke-Doctor $f -Extra @('-Repair', 'rates', '-Confirmed')
        $whole.Code | Should -Be 2 -Because $whole.Raw
        Test-Path (Join-Path $two 'consumption-rates.md') | Should -BeTrue
        Test-Path (Join-Path $f.Root 'members/unregistered/consumption-rates.md') | Should -BeFalse
    }

    It 'rejects a federation registry path that escapes the member layout' {
        $f = New-DoctorFixture
        Write-DoctorFile (Join-Path $f.Root 'federation.md') "| Sub-squad | Location |`n|---|---|`n| one | ../outside |"
        $result = Invoke-Doctor $f
        $result.Code | Should -Be 1
        $result.Raw | Should -Match 'Unsafe federation member location'
    }
}
