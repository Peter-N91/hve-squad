#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Guides setup and launches the bounded efficiency benchmark unattended.
.DESCRIPTION
    Installs and authenticates only after consent. Never reads or records tokens.
    Archive-only cleanup preserves evidence; a failed stage stops dependent work.
.PARAMETER SourceRoot
    Source checkout holding squad-src and apm.yml.
.PARAMETER WorkRoot
    Dedicated scratch directory outside the source checkout.
.PARAMETER BaselineEvidencePath
    Optional saved control-series.json to recommend for Series mode.
.PARAMETER ParallelTrials
    Select three simultaneous observations without the execution-choice prompt.
.EXAMPLE
    pwsh -NoProfile -File ./tests/tier2/live-benchmark/Start-EfficiencyWizard.ps1
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')),
    [string]$WorkRoot = '',
    [string]$BaselineEvidencePath = '',
    [switch]$ParallelTrials
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:WizardDefaultsFields = @('Mode', 'WorkRoot', 'BaselineSourceRoot', 'CandidateSourceRoot', 'BaselineEvidencePath', 'Model', 'PerRunCredits', 'TotalCredits', 'ParallelTrials')

function Get-WizardDefaultsPath {
    <# .SYNOPSIS
    Locates per-checkout nonsecret settings, independent of the evidence root.
    #>
    [CmdletBinding()]
    param()
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../.efficiency-wizard-defaults.json'))
}

function Read-WizardDefaults {
    <# .SYNOPSIS
    Reads only recognized settings and rejects invalid memory with reset guidance.
    #>
    [CmdletBinding()]
    param([string]$Path = (Get-WizardDefaultsPath))
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    $Invalid = "Saved wizard defaults are invalid: $Path. Remove this file to reset them."
    try { $Defaults = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
    catch [ArgumentException] { throw $Invalid }
    if ($Defaults -isnot [Collections.IDictionary] -or $Defaults['schemaVersion'] -cne 'efficiency-wizard-defaults-v1') { throw $Invalid }
    $Allowed = @('schemaVersion', 'SpendingAuthorization') + $script:WizardDefaultsFields
    foreach ($Key in $Defaults.Keys) { if ($Key -notin $Allowed) { throw $Invalid } }
    foreach ($Key in @('WorkRoot', 'BaselineSourceRoot', 'CandidateSourceRoot', 'Model', 'BaselineEvidencePath')) {
        if ($Defaults.Contains($Key) -and ($Defaults[$Key] -isnot [string] -or ($Key -ne 'BaselineEvidencePath' -and [string]::IsNullOrWhiteSpace($Defaults[$Key])))) { throw $Invalid }
    }
    if ($Defaults.Contains('Mode') -and $Defaults['Mode'] -notin @('Establish', 'Series', 'Complete', 'Offline')) { throw $Invalid }
    foreach ($Key in @('PerRunCredits', 'TotalCredits')) {
        if ($Defaults.Contains($Key)) {
            $Value = $Defaults[$Key]
            if (($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double]) -or -not [double]::IsFinite([double]$Value) -or $Value -le 0) { throw $Invalid }
        }
    }
    if ($Defaults.Contains('ParallelTrials') -and $Defaults['ParallelTrials'] -isnot [bool]) { throw $Invalid }
    if ($Defaults.Contains('SpendingAuthorization')) {
        $Authorization = $Defaults['SpendingAuthorization']
        if ($Authorization -isnot [Collections.IDictionary] -or $Authorization['approved'] -isnot [bool] -or $Authorization['planHash'] -cnotmatch '^[0-9a-f]{64}$' -or @($Authorization.Keys | Where-Object { $_ -notin @('approved', 'planHash') }).Count) { throw $Invalid }
    }
    $Defaults
}

function Get-WizardSpendingPlanHash {
    <# .SYNOPSIS
    Identifies the spending configuration without binding a fresh run directory.
    #>
    [CmdletBinding()]
    param([Collections.IDictionary]$Config)
    $Identity = [ordered]@{}
    foreach ($Key in $script:WizardDefaultsFields) { $Identity[$Key] = $Config[$Key] }
    $Json = ConvertTo-Json -InputObject $Identity -Compress
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Json))).ToLowerInvariant()
}

function Save-WizardDefaults {
    <# .SYNOPSIS
    Atomically remembers answered fields, never credentials or reusable consent.
    #>
    [CmdletBinding()]
    param([Collections.IDictionary]$Config, [Collections.IDictionary]$Previous = @{}, [bool]$SpendingAuthorized, [string]$Path = (Get-WizardDefaultsPath))
    $Defaults = @{ schemaVersion = 'efficiency-wizard-defaults-v1' }
    foreach ($Key in @($script:WizardDefaultsFields) + 'SpendingAuthorization') {
        if ($Previous.Contains($Key)) { $Defaults[$Key] = $Previous[$Key] }
    }
    $Answered = @('Mode', 'WorkRoot')
    if ($Config.Mode -ne 'Offline') {
        $Answered += @('Model', 'PerRunCredits', 'TotalCredits', 'ParallelTrials')
        if ($Config.Mode -eq 'Series') { $Answered += 'BaselineEvidencePath' }
        if ($Config.Mode -in @('Establish', 'Complete') -or ($Config.Mode -eq 'Series' -and -not $Config.BaselineEvidencePath)) { $Answered += 'BaselineSourceRoot' }
        if ($Config.Mode -in @('Series', 'Complete')) { $Answered += 'CandidateSourceRoot' }
    }
    foreach ($Key in $Answered) { $Defaults[$Key] = $Config[$Key] }
    if ($PSBoundParameters.ContainsKey('SpendingAuthorized')) {
        $Defaults.SpendingAuthorization = @{ approved = $SpendingAuthorized; planHash = Get-WizardSpendingPlanHash $Config }
    }
    $Temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $Defaults | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Temporary -Encoding utf8NoBOM
        [IO.File]::Move($Temporary, [IO.Path]::GetFullPath($Path), $true)
    }
    finally { if (Test-Path -LiteralPath $Temporary) { Remove-Item -LiteralPath $Temporary -Force } }
}

function Read-WizardText {
    <# .SYNOPSIS
    Reads nonsecret setup input; cancellation never implies consent.
    #>
    [CmdletBinding()]
    param([string]$Question, [string]$Default = '', [switch]$Required)
    $Answer = Read-Host "$Question [$Default] (q cancels)"
    if ($null -eq $Answer -or $Answer.Trim() -eq 'q') { throw [OperationCanceledException]::new('Wizard cancelled.') }
    if ([string]::IsNullOrWhiteSpace($Answer)) { $Answer = $Default }
    if ($Required -and [string]::IsNullOrWhiteSpace($Answer)) { throw 'A required setup value was not supplied.' }
    $Answer.Trim()
}

function Read-WizardChoice {
    <# .SYNOPSIS
    Explains choices and validates a bounded number of nonsecret answers.
    #>
    [CmdletBinding()]
    param([string]$Question, [Collections.IDictionary]$Options, [string]$Default)
    Write-Host $Question
    foreach ($Key in $Options.Keys) { Write-Host "  $Key. $($Options[$Key])$(if ($Key -eq $Default) { ' [recommended]' })" }
    foreach ($Attempt in 1..3) {
        $Answer = Read-WizardText -Question 'Choice' -Default $Default -Required
        if ($Options.Contains($Answer)) { return $Answer }
        Write-Host 'Choose a listed option.'
    }
    throw 'Too many invalid choices; no work launched.'
}

function Confirm-WizardAction {
    <# .SYNOPSIS
    Requires an affirmative answer before a setup mutation or launch.
    #>
    [CmdletBinding()]
    param([string]$Question)
    while ($true) {
        $Answer = Read-WizardText -Question "$Question (yes/no; y/n accepted)" -Default 'no'
        switch ($Answer.Trim().ToLowerInvariant()) {
            'yes' { return $true }
            'y' { return $true }
            'no' { return $false }
            'n' { return $false }
            default { Write-Host 'Please enter yes/y or no/n, or q to cancel. Blank means no.' }
        }
    }
}

function Get-WizardMode {
    <# .SYNOPSIS
    Reuses the last mode, otherwise recommends Establish or Series from controls.
    #>
    [CmdletBinding()]
    param([switch]$HasBaseline, [string]$DefaultMode = '')
    $Modes = @{ '1' = 'Establish'; '2' = 'Series'; '3' = 'Complete'; '4' = 'Offline' }
    $Default = if ($HasBaseline) { '2' } else { '1' }
    foreach ($Key in $Modes.Keys) { if ($Modes[$Key] -eq $DefaultMode) { $Default = $Key } }
    $Choice = Read-WizardChoice -Question 'What should run?' -Default $Default -Options ([ordered]@{
        '1' = 'Establish: all offline checks, then three baseline observations, retaining failures; no improvement claim.'
        '2' = 'Series: all offline checks, then three candidates against compatible saved controls, or six fresh paired trials.'
        '3' = 'Complete: all offline checks, establish three fresh controls, then run three candidates and compare.'
        '4' = 'Offline: all benchmark self-tests only; no model requests, login or accepted-baseline changes.'
    })
    $Modes[$Choice]
}

function Read-WizardCreditLimit {
    <# .SYNOPSIS
    Reads a positive finite AI-credit ceiling using unambiguous numeric syntax.
    #>
    [CmdletBinding()]
    param([string]$Question, [double]$Default)
    $Text = Read-WizardText -Question $Question -Default $Default.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    $Value = 0.0
    if (-not [double]::TryParse($Text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$Value) -or [double]::IsNaN($Value) -or [double]::IsInfinity($Value) -or $Value -le 0) { throw 'Credit ceilings must be finite positive numbers.' }
    $Value
}

function Assert-WizardScratchPath {
    <# .SYNOPSIS
    Refuses source overlaps, filesystem roots and reparse-point ancestors.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Source)
    $Full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $SourceFull = [IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $Separator = [string][IO.Path]::DirectorySeparatorChar
    if (-not $Full -or $Full -eq [IO.Path]::GetPathRoot($Full).TrimEnd([IO.Path]::DirectorySeparatorChar) -or $Full.Equals($SourceFull, [StringComparison]::OrdinalIgnoreCase) -or $Full.StartsWith($SourceFull + $Separator, [StringComparison]::OrdinalIgnoreCase) -or $SourceFull.StartsWith($Full + $Separator, [StringComparison]::OrdinalIgnoreCase)) { throw 'Scratch paths must be dedicated directories outside the source checkout, not its ancestors or a filesystem root.' }
    $Current = $Full
    while ($Current) {
        if (Test-Path -LiteralPath $Current) {
            $Item = Get-Item -LiteralPath $Current -Force
            if (-not $Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Scratch paths cannot traverse files, junctions or symbolic links.' }
        }
        $Parent = [IO.Path]::GetDirectoryName($Current)
        if ($Parent -eq $Current) { break }
        $Current = $Parent
    }
    $Full
}

function New-WizardRunPlan {
    <# .SYNOPSIS
    Builds a fixed no-retry execution sequence and checks its total reservation.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Constructs an in-memory plan only; does not mutate system state.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Config)
    $Steps = [Collections.Generic.List[object]]::new()
    $Steps.Add(@{ name = 'Offline self-tests'; kind = 'Offline'; arguments = @{} })
    if ($Config.Mode -eq 'Offline') { return ,@($Steps) }
    foreach ($Limit in @($Config.PerRunCredits, $Config.TotalCredits)) { if ([double]$Limit -le 0 -or [double]::IsNaN([double]$Limit) -or [double]::IsInfinity([double]$Limit)) { throw 'Finite positive credit ceilings are required.' } }
    Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
    $null = Get-EfficiencyRecoveryPolicy -MaxCredits $Config.PerRunCredits -ObservationOnly
    $NeededRuns = if ($Config.Mode -eq 'Establish' -or ($Config.Mode -eq 'Series' -and $Config.BaselineEvidencePath)) { 3 } else { 6 }
    if ($Config.TotalCredits -lt $NeededRuns * $Config.PerRunCredits) { throw 'Total credit ceiling is smaller than the scheduled run reservations.' }
    $Common = @{ InstallRoot = $Config.InstallRoot; Model = $Config.Model; MaxCredits = $Config.PerRunCredits; Live = $true; IsolatedEnvironment = $true; ObservationOnly = $true }
    if ($Config['ParallelTrials']) {
        if ($Config.Mode -eq 'Series' -and -not $Config.BaselineEvidencePath) { throw 'Parallel trials require three independent observations; six fresh paired trials remain serial.' }
        $Common.ParallelTrials = $true
    }
    if ($Config.Mode -in @('Establish', 'Complete')) {
        $Arguments = $Common.Clone(); $Arguments.Mode = 'Establish'; $Arguments.SourceRoot = $Config.BaselineSourceRoot; $Arguments.TrialRoot = Join-Path $Config.RunRoot 'control'; $Arguments.MaxSeriesCredits = 3 * $Config.PerRunCredits
        $Steps.Add(@{ name = 'Establish controls'; kind = 'Benchmark'; arguments = $Arguments })
    }
    if ($Config.Mode -in @('Series', 'Complete')) {
        $Arguments = $Common.Clone(); $Arguments.Mode = 'Series'; $Arguments.CandidateSourceRoot = $Config.CandidateSourceRoot; $Arguments.TrialRoot = Join-Path $Config.RunRoot 'comparison'
        if ($Config.Mode -eq 'Complete') { $Arguments.BaselineEvidencePath = Join-Path $Config.RunRoot 'control/out/control-series.json' }
        elseif ($Config.BaselineEvidencePath) { $Arguments.BaselineEvidencePath = $Config.BaselineEvidencePath }
        else { $Arguments.BaselineSourceRoot = $Config.BaselineSourceRoot }
        $Arguments.MaxSeriesCredits = $(if ($Arguments.ContainsKey('BaselineEvidencePath')) { 3 } else { 6 }) * $Config.PerRunCredits
        $Steps.Add(@{ name = 'Compare candidates'; kind = 'Benchmark'; arguments = $Arguments })
    }
    ,@($Steps)
}

function Get-WizardRepair {
    <# .SYNOPSIS
    Gives stage-specific repair guidance without echoing secret-bearing command output.
    #>
    [CmdletBinding()]
    param([string]$Stage, [int]$ExitCode = 1)
    switch -Regex ($Stage) {
        'auth|login' { 'Complete gh auth login --web and copilot login in your terminal. Check organization SSO, Copilot entitlement and overriding token environment variables. Never paste a token into the wizard.'; break }
        'install|prerequisite' { 'Check the package manager output, trusted TLS/proxy configuration and PATH. Open a fresh PowerShell 7.4+ terminal after an OS install. Ask the package owner to perform any required administrator installation; no automatic elevation is attempted.'; break }
        'Offline' { 'Repair the failed Pester assertions or provision Python/pytest using a trusted package feed. Fix proxy/certificate trust for TLS errors; do not disable verification. Rerun the offline self-tests before any paid work.'; break }
        default { "Inspect the retained out/report.md, out/report.json, out/error.json and per-stage stderr. Exit $ExitCode means this stage did not pass. Repair the named check or compatibility/auth/budget issue, then explicitly start a new bounded run. Do not delete failed evidence or promote it." }
    }
}

function Get-WizardBenchmarkSummary {
    <# .SYNOPSIS
    Links retained records and separates collection from quality without model calls.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][Collections.IDictionary]$Options)
    $Out = Join-Path $Options.TrialRoot 'out'
    $ReportPath = Join-Path $Out 'report.json'
    $ExportPath = Join-Path $Out 'benchmark-export.json'
    try {
        $Report = Get-Content -LiteralPath $ReportPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $Export = Get-Content -LiteralPath $ExportPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    catch { throw "Benchmark result evidence is missing or unreadable. Inspect $ReportPath and $ExportPath; repair offline, without paid retries." }
    $Portable = Join-Path $Options.TrialRoot 'portable'
    if ($Report -isnot [Collections.IDictionary] -or $Report['schemaVersion'] -cne 'efficiency-series-v1' -or
        $Report['quality'] -isnot [Collections.IDictionary] -or $Report['quality']['checksPassed'] -isnot [bool] -or
        $Report['regressionVerdict'] -cnotin @('passed', 'regression', 'not-evaluable') -or
        $Export -isnot [Collections.IDictionary] -or $Export['status'] -cne 'exported' -or
        ($Export['recordedTrials'] -isnot [int] -and $Export['recordedTrials'] -isnot [long]) -or
        $Export['recordedTrials'] -lt 1 -or $Export['recordedTrials'] -gt 3 -or
        $Export['publicationCommand'] -isnot [string] -or [string]::IsNullOrWhiteSpace($Export['publicationCommand']) -or
        -not (Test-Path -LiteralPath (Join-Path $Out 'report.md') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $Portable 'campaign-report.md') -PathType Leaf)) {
        throw "Benchmark result evidence is incomplete or invalid. Inspect $ReportPath and $ExportPath; repair offline, without paid retries."
    }
    $Control = Join-Path $Out 'control-series.json'
    @{
        collection = 'recorded'; independentChecks = if ($Report.quality.checksPassed) { 'passed' } else { 'failed' }
        comparison = $Report['regressionVerdict']; recordedTrials = $Export.recordedTrials
        reportPath = Join-Path $Out 'report.md'; rawReportPath = $ReportPath
        controlEvidencePath = if (Test-Path -LiteralPath $Control -PathType Leaf) { $Control } else { $null }
        portableReportPath = Join-Path $Portable 'campaign-report.md'; exportManifestPath = $ExportPath
        publication = 'local-only'; publicationCommand = $Export.publicationCommand
    }
}

function Invoke-WizardRunPlan {
    <# .SYNOPSIS
    Executes each scheduled step once, preserving a structured fail-fast outcome.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Steps, [Parameter(Mandatory)][scriptblock]$Execute)
    $Results = [Collections.Generic.List[object]]::new()
    foreach ($Step in $Steps) {
        Write-Host "Starting: $($Step.name) (step $($Results.Count + 1)/$($Steps.Count); step counts are not time estimates)"
        $Code = 1; $Summary = $null; $ResultEvidenceFailed = $false
        try {
            $Code = & $Execute $Step
            if ($Code -isnot [int]) { $Code = 1; throw 'Executor did not return one status code.' }
            if ($Step.kind -eq 'Benchmark') {
                $ResultEvidenceFailed = $true
                $Summary = Get-WizardBenchmarkSummary -Options $Step.arguments
                $ResultEvidenceFailed = $false
            }
        }
        catch {
            Write-Warning "Wizard step '$($Step.name)' failed or its result evidence could not be read. Inspect the retained stage log and out/report.json and out/benchmark-export.json."
            if ($Code -eq 0) { $Code = 1 }
        }
        $Entry = @{ stage = $Step.name; exitCode = $Code }
        if ($Summary) { $Entry.benchmark = $Summary }
        $Results.Add($Entry)
        Write-Host "Finished: $($Step.name) (exit $Code; $($Results.Count)/$($Steps.Count) scheduled steps finished)"
        if ($Summary) {
            Write-Host "Collection: $($Summary.collection), $($Summary.recordedTrials) exported observations. Independent checks: $($Summary.independentChecks). Comparison: $($Summary.comparison)."
            Write-Host "Recorded report: $($Summary.reportPath)"
            Write-Host "Portable records: $($Summary.portableReportPath). Publication: local only, not committed to Git; offline publication command is in $($Summary.exportManifestPath)."
        }
        if ($Code -ne 0) {
            return @{ outcome = 'failed'; exitCode = if ($Step.kind -eq 'Offline' -or $Code -eq 2) { 2 } else { 1 }; failedStage = $Step.name; repair = if ($ResultEvidenceFailed) { 'Repair retained out/report.json, out/benchmark-export.json and portable records offline, without paid retries. Keep raw trial evidence and accepted baseline unchanged.' } else { Get-WizardRepair $Step.name $Code }; stages = @($Results); notRun = $Steps.Count - $Results.Count; acceptedBaselineChanged = $false }
        }
    }
    $Benchmarks = @($Results | Where-Object { $_.ContainsKey('benchmark') })
    $Findings = @($Benchmarks | Where-Object { $_.benchmark.independentChecks -ne 'passed' }).Count -gt 0
    @{ outcome = if ($Findings) { 'completed-with-findings' } elseif ($Benchmarks.Count) { 'completed' } else { 'passed' }; exitCode = 0; failedStage = $null; repair = $null; stages = @($Results); notRun = 0; acceptedBaselineChanged = $false }
}

function Invoke-WizardCommand {
    <# .SYNOPSIS
    Runs a native setup command without collecting interactive prompts or secrets.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments = @(), [switch]$Quiet, [Collections.IDictionary]$ProgressPaths)
    if ($ProgressPaths) {
        Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1')
        $Log = Join-Path (Get-Location).Path ('wizard-stage-' + [guid]::NewGuid().ToString('N') + '.log')
        $PreviousSnapshots = @{}
        $Observer = { param($Seconds) Write-EfficiencyProgressSummary -Paths $ProgressPaths -ElapsedSeconds $Seconds -PreviousSnapshots $PreviousSnapshots }.GetNewClosure()
        $Process = Invoke-EfficiencyProcess -FilePath $Command -Arguments $Arguments -WorkingDirectory (Get-Location).Path -OutputPath $Log -TimeoutSeconds ([int]::MaxValue) -OnProgress $Observer
        Get-Content -LiteralPath $Log | Out-Host
        Get-Content -LiteralPath ($Log + '.stderr') | Out-Host
        Write-Host "Stage output retained: $Log"
        if ($Process.stopCause -ne 'none') { throw "Wizard child stopped: $($Process.stopCause). Inspect $Log and its .stderr file." }
        return [int]$Process.exitCode
    }
    $global:LASTEXITCODE = 0
    if ($Quiet) { & $Command @Arguments *> $null }
    else { & $Command @Arguments | Out-Host }
    [int]$LASTEXITCODE
}

function Update-WizardProcessPath {
    <# .SYNOPSIS
    Refreshes this process only after an installer updates the user PATH.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $Parts = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Value in @($env:PATH, [Environment]::GetEnvironmentVariable('PATH', 'User'), [Environment]::GetEnvironmentVariable('PATH', 'Machine'))) {
        foreach ($Part in @($Value -split [regex]::Escape([string][IO.Path]::PathSeparator))) { if ($Part) { $Parts.Add($Part) | Out-Null } }
    }
    if ($PSCmdlet.ShouldProcess('Current process PATH', 'Refresh from existing user and machine paths')) {
        $env:PATH = @($Parts) -join [IO.Path]::PathSeparator
    }
}

function Get-WizardHostPlatform {
    <# .SYNOPSIS
    Identifies installer routing without binding tests to their host OS.
    #>
    [CmdletBinding()]
    param()
    if ($IsWindows) { 'Windows' } else { 'Unix' }
}

function Install-WizardTool {
    <# .SYNOPSIS
    Offers one exact user-scope WinGet installation and verifies command discovery.
    #>
    [CmdletBinding()]
    param([string]$Name, [string]$PackageId)
    if (Get-Command $Name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue) { return }
    if ((Get-WizardHostPlatform) -ne 'Windows') {
        $Reference = switch ($Name) {
            'git' { 'https://git-scm.com/download/linux' }
            'gh' { 'https://github.com/cli/cli/blob/trunk/docs/install_linux.md' }
            'copilot' { 'https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli' }
            'apm' { 'https://microsoft.github.io/apm/getting-started/installation/' }
            'python' { 'https://www.python.org/downloads/' }
            default { 'the tool publisher installation instructions' }
        }
        throw "$Name is missing. On Ubuntu/non-Windows, install it using $Reference, reopen the terminal and rerun. No sudo, downloaded script, or Windows installer was executed."
    }
    Write-Host "$Name is missing. Proposed install: winget install --id $PackageId --exact --source winget --scope user"
    if (-not (Confirm-WizardAction "Install $Name for this user?")) { throw [OperationCanceledException]::new("Installation declined: $Name") }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'WinGet is unavailable. Install Microsoft App Installer from the Microsoft Store, then restart this wizard. No installer was downloaded or executed.' }
    $Code = Invoke-WizardCommand -Command 'winget' -Arguments @('install', '--id', $PackageId, '--exact', '--source', 'winget', '--scope', 'user', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')
    if ($Code -ne 0) { throw "Installation failed for $Name (exit $Code). Use the package owner's supported installer or ask an administrator; this wizard does not elevate or retry." }
    Update-WizardProcessPath
    if (-not (Get-Command $Name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue)) { throw "$Name is still unavailable. Open a new PowerShell terminal and repair PATH before restarting." }
}

function Get-WizardPython {
    <# .SYNOPSIS
    Resolves Python 3.12 without relying on platform-specific command aliases.
    #>
    [CmdletBinding()]
    param()
    foreach ($Name in @('python3.12', 'python3', 'python')) {
        $Python = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $Python) { continue }
        & $Python.Source -c 'import sys; sys.exit(sys.version_info[:2] != (3, 12))'
        if ($LASTEXITCODE -eq 0) { return $Python.Source }
    }
}

function Install-WizardPrerequisite {
    <# .SYNOPSIS
    Repairs the tools needed by the chosen workload, without authenticating Offline mode.
    #>
    [CmdletBinding()]
    param([switch]$LiveMode)
    Install-WizardTool -Name git -PackageId 'Git.Git'
    if (-not (Get-WizardPython)) {
        Install-WizardTool -Name python -PackageId 'Python.Python.3.12'
        if (-not (Get-WizardPython)) { throw 'Python 3.12 is required. Install it and expose python3.12, python3 or python on PATH, then rerun.' }
    }
    if ($LiveMode) {
        Install-WizardTool -Name gh -PackageId 'GitHub.cli'
        Install-WizardTool -Name copilot -PackageId 'GitHub.Copilot'
        Install-WizardTool -Name apm -PackageId 'Microsoft.APM'
    }
    $Pester = @(Get-Module -ListAvailable Pester | Where-Object Version -GE ([version]'5.7.1') | Sort-Object Version -Descending | Select-Object -First 1)
    if (-not $Pester.Count) {
        if (-not (Confirm-WizardAction 'Install Pester 5.7.1 in CurrentUser scope from PSGallery?')) { throw [OperationCanceledException]::new('Pester installation declined.') }
        Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Repository PSGallery -Force -ErrorAction Stop
        $Pester = @(Get-Module -ListAvailable Pester | Where-Object Version -GE ([version]'5.7.1') | Sort-Object Version -Descending | Select-Object -First 1)
        if (-not $Pester.Count) { throw 'Pester remains unavailable after installation; repair PowerShell module discovery.' }
    }
    $GitVersion = (& git --version | Out-String)
    if ($LASTEXITCODE -ne 0 -or $GitVersion -notmatch '(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt [version]'2.28.0') { throw 'Git 2.28+ is required. Upgrade using the installer that owns your Git installation, then rerun.' }
    if ($LiveMode) {
        $ApmVersion = (& apm --version | Out-String)
        if ($LASTEXITCODE -ne 0 -or $ApmVersion -notmatch '(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt [version]'0.29.0') { throw 'APM 0.29+ is required. Upgrade through its owning package manager, then rerun.' }
        $HelpText = (& copilot --help | Out-String)
        if ($LASTEXITCODE -ne 0) { throw 'Copilot CLI help failed; repair the installed CLI.' }
        Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
        foreach ($Flag in @('--session-id', '--max-ai-credits', '--no-ask-user', '--max-autopilot-continues', '--usage-output-file')) {
            if (-not $HelpText.Contains($Flag)) { throw "Copilot CLI lacks $Flag. Upgrade through its owning package manager before benchmarking." }
        }
        $null = Get-EfficiencyCliLocalArguments -HelpText $HelpText
    }
    Write-Host 'Offline tests use an isolated Python 3.12 venv and pytest 8.3.5 via pip; downloads may be required. No global Python packages are installed.'
    $Pester[0].Path
}

function Connect-WizardGitHub {
    <# .SYNOPSIS
    Delegates OAuth and protected token entry to native CLIs; never reads tokens.
    #>
    [CmdletBinding()]
    param()
    foreach ($Name in @('COPILOT_PROVIDER_BASE_URL', 'COPILOT_PROVIDER_API_KEY', 'ANTHROPIC_API_KEY', 'OPENAI_API_KEY')) {
        if (Test-Path "Env:$Name") { throw 'A custom/BYOK provider environment is active. The GitHub credit ceilings cannot bound third-party spending. Use a clean isolated GitHub-backed environment.' }
    }
    Write-Host 'OAuth obtains and stores credentials through native CLIs. Review permissions in the browser; no additional scopes or PATs are silently created.'
    if ((Invoke-WizardCommand gh @('auth', 'status', '--hostname', 'github.com') -Quiet) -ne 0) {
        if (-not (Confirm-WizardAction 'Run gh auth login --hostname github.com --web?')) { throw [OperationCanceledException]::new('GitHub sign-in declined.') }
        if ((Invoke-WizardCommand gh @('auth', 'login', '--hostname', 'github.com', '--web')) -ne 0 -or (Invoke-WizardCommand gh @('auth', 'status', '--hostname', 'github.com') -Quiet) -ne 0) { throw 'GitHub authentication did not succeed; complete browser/SSO approval in gh.' }
    }
    $Present = @('COPILOT_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN') | Where-Object { Test-Path "Env:$_" }
    if ($Present) { Write-Host "Credential environment variables are set: $($Present -join ', '). Their values are not read. They can override stored OAuth; the wizard will not clear them." }
    Write-Host 'A GitHub login does not prove Copilot entitlement. Copilot may fall back to gh OAuth, but organization policy, token validity and model access are verified only by the later bounded live run.'
    $Choice = Read-WizardChoice -Question 'Copilot authorization' -Default '1' -Options ([ordered]@{
        '1' = 'Run copilot login now (native browser/device OAuth).'
        '2' = 'Use existing Copilot/GitHub CLI authorization or supported environment credentials; not live-verified here.'
        '3' = 'Enter an existing fine-grained PAT directly into copilot login --with-token, never into the wizard.'
    })
    if ($Choice -eq '2') { return }
    if ($Choice -eq '3') { Write-Host 'Create a user-owned fine-grained PAT with Copilot Requests at https://github.com/settings/personal-access-tokens/new. Classic ghp_ PATs are unsupported. Organization approval cannot be bypassed.' }
    $Arguments = if ($Choice -eq '3') { @('login', '--with-token') } else { @('login') }
    if ((Invoke-WizardCommand copilot $Arguments) -ne 0) { throw 'Copilot login failed. Check SSO, account policy and overriding token environment variables in your terminal.' }
}

function Test-WizardInstall {
    <# .SYNOPSIS
    Checks deployed requirements agents and RPI skills, not just an uninstalled source overlay.
    #>
    [CmdletBinding()]
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container) -or (Test-Path -LiteralPath (Join-Path $Path '.copilot-tracking'))) { return $false }
    $Agents = Join-Path $Path '.github/agents'; $Skills = Join-Path $Path '.agents/skills'
    if (-not (Test-Path -LiteralPath $Agents) -or -not (Test-Path -LiteralPath $Skills)) { return $false }
    foreach ($Name in @('squad-coordinator.agent.md', 'brd-builder.agent.md', 'prd-builder.agent.md')) { if (-not (Get-ChildItem -LiteralPath $Agents -Recurse -File -Filter $Name)) { return $false } }
    foreach ($Name in @('rpi-research', 'rpi-plan', 'rpi-implement', 'rpi-review', 'requirements-author')) {
        if (-not (Get-ChildItem -LiteralPath $Skills -Recurse -File -Filter SKILL.md | Where-Object { $_.Directory.Name -eq $Name })) { return $false }
    }
    $true
}

function Move-WizardInstallArchive {
    <# .SYNOPSIS
    Archives only an explicitly confirmed managed install, without deleting evidence.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ManagedRoot, [Parameter(Mandatory)][string]$Source)
    $Root = Assert-WizardScratchPath $ManagedRoot $Source
    $Full = Assert-WizardScratchPath $Path $Source
    if (-not $Full.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $Full -ne (Join-Path $Root 'install')) { throw 'Only the managed install directory can be archived; choose a fresh WorkRoot instead.' }
    if (-not (Confirm-WizardAction "Archive stale install $Full (ensure no other run is using it), preserving all contents?")) { throw [OperationCanceledException]::new('Archive declined; existing files preserved.') }
    $Destination = Join-Path $Root ('install-archive-' + [guid]::NewGuid())
    if ($PSCmdlet.ShouldProcess($Full, 'Archive managed install')) { Move-Item -LiteralPath $Full -Destination $Destination -ErrorAction Stop }
    $Destination
}

function Initialize-WizardInstall {
    <# .SYNOPSIS
    Reuses a clean compatible prepared install or creates one after explicit consent.
    #>
    [CmdletBinding()]
    param([string]$Path, [string]$ManagedRoot, [string]$Source)
    $ManifestHash = (Get-FileHash -LiteralPath (Join-Path $Source 'apm.yml')).Hash
    $Receipt = Join-Path $Path 'wizard-install.json'
    $MatchesManifest = $true
    if (Test-Path -LiteralPath $Receipt) {
        try { $MatchesManifest = (Get-Content -LiteralPath $Receipt -Raw | ConvertFrom-Json).manifestHash -ceq $ManifestHash } catch { $MatchesManifest = $false }
    }
    if ((Test-WizardInstall $Path) -and $MatchesManifest) {
        if (-not (Confirm-WizardAction "Reuse clean prepared install ${Path}?")) { throw [OperationCanceledException]::new('Install reuse declined; choose a new WorkRoot.') }
        return
    }
    if (Test-Path -LiteralPath $Path) { Move-WizardInstallArchive -Path $Path -ManagedRoot $ManagedRoot -Source $Source | Out-Null }
    if (-not (Confirm-WizardAction "Prepare the full pinned squad/hve-core package from $Source into $Path (network access and package trust prompts may be needed)?")) { throw [OperationCanceledException]::new('Package preparation declined.') }
    Import-Module (Join-Path $PSScriptRoot '../../lib/SquadInstall.psm1') -Force
    Install-SquadPackage -Destination $Path -SourceRoot $Source | Out-Null
    if (-not (Test-WizardInstall $Path)) { throw 'Prepared package is incomplete or contains runtime state. Inspect install.log; keep the evidence and choose a fresh WorkRoot after repair.' }
    @{ manifestHash = $ManifestHash; schemaVersion = 'wizard-install-v1' } | ConvertTo-Json | Set-Content -LiteralPath $Receipt -Encoding utf8NoBOM
}

function Get-WizardConfiguration {
    <# .SYNOPSIS
    Explains defaults and collects all routine decisions before launch.
    #>
    [CmdletBinding()]
    param([string]$Source, [string]$Scratch, [string]$SavedControl = '', [switch]$ParallelTrials)
    $Source = (Resolve-Path -LiteralPath $Source).Path
    foreach ($Required in @('squad-src', 'apm.yml')) { if (-not (Test-Path -LiteralPath (Join-Path $Source $Required))) { throw "Source checkout lacks $Required." } }
    $Defaults = Read-WizardDefaults
    $ExplicitControl = [bool]$SavedControl
    if (-not $Scratch -and $Defaults['WorkRoot']) { $Scratch = $Defaults['WorkRoot'] }
    if (-not $Scratch) { $Scratch = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hve-squad/efficiency' }
    $Scratch = Assert-WizardScratchPath $Scratch $Source
    if (-not $SavedControl -and $Defaults.Contains('BaselineEvidencePath')) { $SavedControl = $Defaults['BaselineEvidencePath'] }
    if (-not $SavedControl -and -not $Defaults.Contains('BaselineEvidencePath') -and (Test-Path -LiteralPath $Scratch)) {
        $Previous = @(Get-ChildItem -LiteralPath $Scratch -Directory -Filter 'run-*' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 20)
        foreach ($Directory in $Previous) {
            $Path = Join-Path $Directory.FullName 'control/out/control-series.json'
            if (Test-Path -LiteralPath $Path -PathType Leaf) { $SavedControl = $Path; break }
        }
    }
    $Mode = Get-WizardMode -HasBaseline:([bool]$SavedControl) -DefaultMode $(if ($ExplicitControl) { 'Series' } else { $Defaults['Mode'] })
    $DefaultModel = if ($Defaults['Model']) { $Defaults['Model'] } else { 'claude-sonnet-5.5' }
    $DefaultCredits = if ($Defaults['PerRunCredits']) { [double]$Defaults['PerRunCredits'] } else { 100.0 }
    $ScenarioDefaults = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'efficiency-scenario.json') -Raw | ConvertFrom-Json -AsHashtable
    Write-Host "Defaults: offline self-tests first; model $DefaultModel; $DefaultCredits AI credits per run (ceiling, not predicted cost); three observations; no outer retries or request-count cap; $($ScenarioDefaults.observationTimeoutMinutes)-minute hung-run watchdog; quality/readiness failures are recorded, not collection gates; no automatic promotion."
    Write-Host 'Isolation is NOT created by the wizard. Live modes require a disposable OS-isolated environment, restricted credentials and no sensitive source data. Fresh run directories preserve previous evidence.'
    $Scratch = Assert-WizardScratchPath (Read-WizardText -Question 'Dedicated work/evidence root outside the checkout' -Default $Scratch -Required) $Source
    $Config = @{
        Mode = $Mode; SourceRoot = $Source; WorkRoot = $Scratch; InstallRoot = Join-Path $Scratch 'install'
        RunRoot = Join-Path $Scratch ('run-' + [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        BaselineSourceRoot = $Source; CandidateSourceRoot = $Source; BaselineEvidencePath = ''; Model = $DefaultModel
        PerRunCredits = 0.0; TotalCredits = 0.0; ParallelTrials = [bool]$ParallelTrials
    }
    if ($Mode -eq 'Offline') { Save-WizardDefaults -Config $Config -Previous $Defaults; return $Config }
    if ($Mode -eq 'Series') {
        $Default = if ($SavedControl) { $SavedControl } else { 'none' }
        $Answer = Read-WizardText -Question 'Saved control-series.json path, or none for six fresh paired trials' -Default $Default -Required
        if ($Answer -ne 'none') {
            $Config.BaselineEvidencePath = (Resolve-Path -LiteralPath $Answer).Path
            $Control = Get-Content -LiteralPath $Config.BaselineEvidencePath -Raw | ConvertFrom-Json -AsHashtable
            if ($Control['schemaVersion'] -ne 'efficiency-control-v1' -or @($Control['runs']).Count -ne 3) { throw 'Saved control file is not a complete three-control series.' }
        }
    }
    if ($Mode -in @('Establish', 'Complete') -or ($Mode -eq 'Series' -and -not $Config.BaselineEvidencePath)) {
        $DefaultSource = if ($Defaults['BaselineSourceRoot']) { $Defaults['BaselineSourceRoot'] } else { $Source }
        $Config.BaselineSourceRoot = (Resolve-Path -LiteralPath (Read-WizardText -Question 'Baseline source checkout' -Default $DefaultSource -Required)).Path
    }
    if ($Mode -in @('Series', 'Complete')) {
        $DefaultSource = if ($Defaults['CandidateSourceRoot']) { $Defaults['CandidateSourceRoot'] } else { $Source }
        $Config.CandidateSourceRoot = (Resolve-Path -LiteralPath (Read-WizardText -Question 'Candidate source checkout' -Default $DefaultSource -Required)).Path
        if (-not $Config.BaselineEvidencePath -and $Config.BaselineSourceRoot -eq $Config.CandidateSourceRoot) { Write-Host 'Both arms use the same checkout. This is a repeatability exercise, not a patch-improvement claim; it may correctly fail the 10% improvement gate.' }
    }
    foreach ($Checkout in @($Config.BaselineSourceRoot, $Config.CandidateSourceRoot) | Sort-Object -Unique) {
        foreach ($Required in @('squad-src', 'apm.yml', '.git')) { if (-not (Test-Path -LiteralPath (Join-Path $Checkout $Required))) { throw "A source checkout lacks $Required." } }
        Assert-WizardScratchPath $Scratch $Checkout | Out-Null
    }
    $Config.Model = Read-WizardText -Question 'Coordinator/judge model (must match saved controls)' -Default $Config.Model -Required
    $Config.PerRunCredits = Read-WizardCreditLimit 'Maximum AI credits per complete run' $DefaultCredits
    $Number = if ($Mode -eq 'Establish' -or ($Mode -eq 'Series' -and $Config.BaselineEvidencePath)) { 3 } else { 6 }
    $DefaultTotal = [Math]::Max([double]$Defaults['TotalCredits'], $Number * $Config.PerRunCredits)
    $Config.TotalCredits = Read-WizardCreditLimit "Total ceiling for all $Number new runs (all reservations must fit)" $DefaultTotal
    if ($Config.ParallelTrials) { Write-Host 'Parallel trials selected by command-line option; all reservations and isolation/spending authorization still apply.' }
    elseif ($Mode -ne 'Series' -or $Config.BaselineEvidencePath) {
        Write-Host 'Execution: serial or three observations in parallel (higher host load; requires matching parallel controls). Complete still runs controls before candidates.'
        $Config.ParallelTrials = (Read-WizardChoice -Question 'Execution' -Options ([ordered]@{ '1' = 'Serial'; '2' = 'Three observations in parallel' }) -Default $(if ($Defaults['ParallelTrials']) { '2' } else { '1' })) -eq '2'
    }
    else { Write-Host 'Six fresh paired trials remain serial to preserve their alternating arm order.' }
    New-WizardRunPlan $Config | Out-Null
    Save-WizardDefaults -Config $Config -Previous $Defaults
    $Config
}

function Test-WizardCompatibility {
    <# .SYNOPSIS
    Checks model/dependency identity and saved-control integrity without launching a model.
    #>
    [CmdletBinding()]
    param([Collections.IDictionary]$Config)
    Import-Module (Join-Path $PSScriptRoot 'EfficiencyBenchmark.psm1') -Force
    $Expected = Get-EfficiencyCompatibility -SourceRoot $Config.CandidateSourceRoot -InstallRoot $Config.InstallRoot -CliPath (Get-Command copilot).Source -Model $Config.Model -MaxCredits $Config.PerRunCredits -ObservationOnly -ParallelTrials:([bool]$Config['ParallelTrials'])
    if ($Config.BaselineEvidencePath) {
        $Controls = Get-Content -LiteralPath $Config.BaselineEvidencePath -Raw | ConvertFrom-Json -AsHashtable
        $Identity = $null; $Pairs = [Collections.Generic.HashSet[int]]::new(); $Ids = [Collections.Generic.HashSet[string]]::new()
        if ($Controls['schemaVersion'] -ne 'efficiency-control-v1' -or @($Controls['runs']).Count -ne 3) { throw 'Saved controls are incomplete.' }
        foreach ($Run in $Controls['runs']) {
            if (-not (Test-EfficiencyObservation $Run) -or $Run.metadata.arm -ne 'baseline' -or $Run.metadata.pair -notin @(1, 2, 3) -or -not $Pairs.Add([int]$Run.metadata.pair) -or -not $Ids.Add([string]$Run.metadata.runId)) { throw 'Saved observations are unmetered, incomplete, duplicated or incorrectly paired.' }
            $Current = $Run.metadata.revision + ':' + $Run.metadata.sourceHash
            if ($Identity -and $Identity -cne $Current) { throw 'Saved controls mix different source revisions.' }
            $Identity = $Current
            foreach ($Key in $Expected.Keys) {
                if (($Run.metadata.compatibility[$Key] | ConvertTo-Json -Depth 10 -Compress) -cne ($Expected[$Key] | ConvertTo-Json -Depth 10 -Compress)) { throw "Saved controls differ in $Key. Establish new controls or restore the exact compatible environment; do not edit evidence." }
            }
        }
    }
    elseif ($Config.Mode -in @('Series', 'Complete')) {
        $Baseline = Get-EfficiencyCompatibility -SourceRoot $Config.BaselineSourceRoot -InstallRoot $Config.InstallRoot -CliPath (Get-Command copilot).Source -Model $Config.Model -MaxCredits $Config.PerRunCredits -ObservationOnly -ParallelTrials:([bool]$Config['ParallelTrials'])
        foreach ($Key in $Expected.Keys) { if (($Baseline[$Key] | ConvertTo-Json -Depth 10 -Compress) -cne ($Expected[$Key] | ConvertTo-Json -Depth 10 -Compress)) { throw "Baseline/candidate environments differ in $Key; repair compatibility before launching." } }
    }
}

function Invoke-WizardOfflineTest {
    <# .SYNOPSIS
    Runs all existing and new benchmark tests in an isolated pinned Python environment.
    #>
    [CmdletBinding()]
    param([string]$PesterPath)
    $Runner = Join-Path $PSScriptRoot 'Invoke-LiveBenchmarkTests.ps1'
    $Python = Get-WizardPython
    if (-not $Python) { throw 'Python 3.12 is unavailable; repair the prerequisite before running offline tests.' }
    $Environment = Join-Path (Get-Location).Path '.offline-venv'
    if (Test-Path -LiteralPath $Environment) { throw "Offline environment already exists: $Environment. Use a fresh run directory." }
    $Code = Invoke-WizardCommand -Command $Python -Arguments @('-m', 'venv', $Environment)
    if ($Code -ne 0) { throw "Python venv creation failed (exit $Code). Install Python 3.12 venv/ensurepip support and rerun." }
    $Bin = Join-Path $Environment $(if ($IsWindows) { 'Scripts' } else { 'bin' })
    $EnvironmentPython = Join-Path $Bin $(if ($IsWindows) { 'python.exe' } else { 'python' })
    $Code = Invoke-WizardCommand -Command $EnvironmentPython -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', '--quiet', 'pytest==8.3.5')
    if ($Code -ne 0) { throw "Installing pinned pytest into the isolated environment failed (exit $Code). Repair pip connectivity/certificates and rerun." }
    $OldPath = $env:PATH
    try {
        $env:PATH = $Bin + [IO.Path]::PathSeparator + $OldPath
        $Progress = Join-Path (Get-Location).Path 'offline-progress.json'
        Invoke-WizardCommand -Command (Get-Command pwsh).Source -Arguments @('-NoProfile', '-File', $Runner, '-PesterPath', $PesterPath, '-Output', 'Normal', '-ProgressPath', $Progress) -ProgressPaths ([ordered]@{ 'Offline self-tests' = $Progress })
    }
    finally { $env:PATH = $OldPath }
}

function Invoke-WizardBenchmark {
    <# .SYNOPSIS
    Launches the existing harness in a child host, preserving its exit status.
    #>
    [CmdletBinding()]
    param([Collections.IDictionary]$Options)
    $Arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-EfficiencyExercise.ps1'))
    foreach ($Key in $Options.Keys) {
        if ($Options[$Key] -is [bool]) { if ($Options[$Key]) { $Arguments += "-$Key" } }
        else { $Arguments += @("-$Key", [Convert]::ToString($Options[$Key], [Globalization.CultureInfo]::InvariantCulture)) }
    }
    $Progress = [ordered]@{}
    $Arms = if ($Options.Mode -eq 'Establish') { @('baseline') } elseif ($Options.Contains('BaselineEvidencePath')) { @('candidate') } else { @('baseline', 'candidate') }
    foreach ($Pair in 1..3) {
        foreach ($Arm in $Arms) { $Progress["$Arm-$Pair"] = Join-Path $Options.TrialRoot "trials/$Arm-$Pair/out/progress.json" }
    }
    $Code = 1
    try { $Code = Invoke-WizardCommand -Command (Get-Command pwsh).Source -Arguments $Arguments -ProgressPaths $Progress }
    finally { $Export = Complete-WizardBenchmarkExport -Options $Options }
    if ($Code -ne 0) { return $Code }
    if ($Export.status -ne 'exported') { return 1 }
    return 0
}

function Complete-WizardBenchmarkExport {
    <# .SYNOPSIS
    Finalizes available observations offline without writing into measured source.
    #>
    [CmdletBinding()]
    param([Collections.IDictionary]$Options)
    $Arm = if ($Options.Mode -eq 'Establish') { 'baseline' } else { 'candidate' }
    $Source = if ($Arm -eq 'candidate') { $Options.CandidateSourceRoot } else { $Options.SourceRoot }
    $Directories = @(foreach ($Slot in 1..3) {
        $Directory = Join-Path $Options.TrialRoot "trials/$Arm-$Slot"
        if (Test-Path -LiteralPath (Join-Path $Directory 'out/run.json') -PathType Leaf) { $Directory }
    })
    $Id = 'observed-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $Destination = Join-Path $Options.TrialRoot 'portable'
    $Result = @{ status = 'unavailable'; recordedTrials = $Directories.Count; outputDirectory = $Destination; publicationCommand = $null; reason = 'no-run-evidence' }
    if ($Directories.Count) {
        function Quote-WizardExport([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
        $Path = Join-Path $PSScriptRoot 'Export-BenchmarkResults.ps1'
        $TrialArguments = (@($Directories | ForEach-Object { Quote-WizardExport $_ })) -join ', '
        $Result.publicationCommand = "& $(Quote-WizardExport $Path) -ObservationOnly -Repository $(Quote-WizardExport $Source) -TrialDirectories @($TrialArguments) -SeriesId '$Id'"
    }
    try {
        if ($Directories.Count -eq 0) { throw 'No run.json files exist. Inspect retained child diagnostics; no observation can be exported.' }
        $Source = [IO.Path]::GetFullPath($Source)
        $Destination = Assert-WizardScratchPath $Destination $Source
        Import-Module (Join-Path $PSScriptRoot 'BenchmarkResults.psm1')
        $null = Export-BenchmarkCampaign -Repository $Source -TrialDirectories $Directories -CampaignId $Id -OutputDirectory $Destination
        $Result.status = 'exported'; $Result.reason = 'observational-campaign-not-comparable'
        Write-Host "Portable observations: $Destination. No measured source files were changed. To publish offline, run this in PowerShell 7.5+ from the writable delivery checkout, review and commit the generated files:"
        Write-Host $Result.publicationCommand
        Write-Host 'Use -Repository for the intended delivery checkout if the measured source is frozen. Source/protocol identity must still match. Missing quality/accounting stays unavailable; current.json is not selected.'
    }
    catch {
        $Result.status = 'failed'; $Result.reason = 'offline-export-failed'
        Write-Host 'Offline export failed. Retain all evidence. In PowerShell 7.5+, run Export-BenchmarkResults.ps1 -ObservationOnly -Repository <delivery-checkout> -TrialDirectories <available-trial-directories> -SeriesId <new-id>. Inspect source/protocol, evidence files and document hashes; do not rerun paid trials to repair export.'
        if ($_.Exception.Message -cmatch '^(invalid-record|stale-record|operational-error):[A-Za-z0-9/-]+$') {
            $Result.reason = $_.Exception.Message
            Write-Host "Export diagnostic: $($Result.reason)"
        }
        if ($Result.publicationCommand) { Write-Host $Result.publicationCommand }
    }
    if (Test-Path -LiteralPath (Join-Path $Options.TrialRoot 'out') -PathType Container) {
        $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Options.TrialRoot 'out/benchmark-export.json') -Encoding utf8NoBOM
    }
    $Result
}

function Invoke-EfficiencyWizard {
    <# .SYNOPSIS
    Coordinates interactive setup, then executes a question-free fixed plan.
    #>
    [CmdletBinding()]
    param([string]$Source, [string]$Scratch = '', [string]$SavedControl = '', [switch]$ParallelTrials)
    $Stage = 'Configuration'; $Config = $null
    $OldLocation = Get-Location
    try {
        Write-Host 'Squad efficiency benchmark wizard. No baseline is promoted by this workflow. Type q at any wizard input to cancel.'
        $Config = Get-WizardConfiguration -Source $Source -Scratch $Scratch -SavedControl $SavedControl -ParallelTrials:$ParallelTrials
        $Stage = 'Prerequisite installation'
        $PesterPath = Install-WizardPrerequisite -LiveMode:($Config.Mode -ne 'Offline')
        $Stage = 'Work directory preparation'
        if (-not (Test-Path -LiteralPath $Config.WorkRoot)) {
            if (-not (Confirm-WizardAction "Create dedicated work root $($Config.WorkRoot)?")) { throw [OperationCanceledException]::new('Work directory creation declined.') }
            New-Item -ItemType Directory -Path $Config.WorkRoot | Out-Null
        }
        if (Test-Path -LiteralPath $Config.RunRoot) { throw 'Fresh run directory already exists; restart to obtain a new path.' }
        if ($Config.Mode -ne 'Offline') {
            $Stage = 'Authentication'
            Connect-WizardGitHub
            $Stage = 'Prepared package installation'
            Initialize-WizardInstall -Path $Config.InstallRoot -ManagedRoot $Config.WorkRoot -Source $Config.BaselineSourceRoot
            $Stage = 'Compatibility preflight'
            Test-WizardCompatibility $Config
            Write-Host "Mode: $($Config.Mode); model: $($Config.Model); per-run ceiling: $($Config.PerRunCredits) credits; total ceiling: $($Config.TotalCredits) credits. Reports: $($Config.RunRoot)"
            $Defaults = Read-WizardDefaults
            $Authorization = $Defaults['SpendingAuthorization']
            if ($Authorization -and $Authorization['planHash'] -ceq (Get-WizardSpendingPlanHash $Config)) {
                Write-Host "Previous spending authorization for this configuration: $(if ($Authorization['approved']) { 'yes' } else { 'no' }). Fresh confirmation is still required; blank means no."
            }
            $Authorized = Confirm-WizardAction 'I confirm this is a disposable OS-isolated environment with restricted credentials and no sensitive data, and authorize the displayed bounded spending after offline checks pass'
            Save-WizardDefaults -Config $Config -Previous $Defaults -SpendingAuthorized $Authorized
            if (-not $Authorized) { throw [OperationCanceledException]::new('Isolation/spending authorization declined.') }
        }
        else { Write-Host "Mode: Offline. No login/model requests. Reports: $($Config.RunRoot)" }
        if (-not (Confirm-WizardAction 'Provision isolated Python/pytest if needed and run the selected plan unattended (retain quality failures; stop for execution/accounting errors)?')) { throw [OperationCanceledException]::new('Launch declined.') }
        New-Item -ItemType Directory -Path $Config.RunRoot | Out-Null
        Set-Location $Config.RunRoot
        $Stage = 'Unattended execution'
        $Steps = New-WizardRunPlan $Config
        $Executor = {
            param($Step)
            if ($Step.kind -eq 'Offline') { Invoke-WizardOfflineTest -PesterPath $PesterPath }
            else { Invoke-WizardBenchmark -Options $Step.arguments }
        }
        $Result = Invoke-WizardRunPlan -Steps $Steps -Execute $Executor
        $Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Config.RunRoot 'wizard-result.json') -Encoding utf8NoBOM
        Write-Host "Wizard outcome: $($Result.outcome). Exit: $($Result.exitCode). Summary: $(Join-Path $Config.RunRoot 'wizard-result.json')"
        if ($Result.repair) { Write-Host "Stopped at $($Result.failedStage). $($Result.repair)" }
        elseif ($Result.outcome -eq 'completed-with-findings') { Write-Host 'Collection completed and records were retained, but independent quality/readiness checks failed. This is not quality approval. Accepted baseline unchanged; do not rerun paid trials to repair reporting or publication.' }
        else { Write-Host 'Selected stages completed; retained record paths are listed above and in the summary. Accepted baseline unchanged.' }
        $Result
    }
    catch {
        $Cancelled = $_.Exception -is [OperationCanceledException]
        $Result = @{ outcome = if ($Cancelled) { 'cancelled' } else { 'failed' }; exitCode = if ($Cancelled) { 3 } else { 1 }; failedStage = $Stage; repair = Get-WizardRepair $Stage; acceptedBaselineChanged = $false }
        Write-Host "Wizard stopped at $Stage. $($_.Exception.Message)"
        Write-Host $Result.repair
        if ($Config -and (Test-Path -LiteralPath $Config.RunRoot)) { $Result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Config.RunRoot 'wizard-result.json') -Encoding utf8NoBOM }
        $Result
    }
    finally { Set-Location $OldLocation }
}

if ($MyInvocation.InvocationName -ne '.') {
    $Result = Invoke-EfficiencyWizard -Source $SourceRoot -Scratch $WorkRoot -SavedControl $BaselineEvidencePath -ParallelTrials:$ParallelTrials
    exit $Result.exitCode
}