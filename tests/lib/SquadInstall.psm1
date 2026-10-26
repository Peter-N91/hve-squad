# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Provisions the package a consumer actually receives, for any tier to assert against.
# AI cost: none; package builds/APM dependency downloads do not dispatch models.
#
# Both Tier 0 and the Tier 1 live harness need the same tree, and they need it built
# the same way: a divergence between "the tree Tier 0 inspected" and "the tree Tier 1
# ran" would make a Tier 1 failure unattributable.

#Requires -Version 7.4

Set-StrictMode -Version Latest

function Copy-SquadSource {
    <#
    .SYNOPSIS
        Replaces squad-owned content with a working copy's squad-src/, matching APM's layout.
    .PARAMETER NativeCli
        Uses the plugin builder's lossless rule port for conditional squad instructions.
        The unconditional floor and all other installed instructions remain active.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$From,

        [Parameter(Mandatory)]
        [string]$To,

        [switch]$NativeCli
    )

    # APM flattens agents, prompts, and instructions; skills keep their directory.
    $flat = @{
        'agents'       = '.github/agents'
        'prompts'      = '.github/prompts'
        'instructions' = '.github/instructions'
    }

    $ownershipPath = Join-Path $To '.github/squad-source-ownership.json'
    $owned = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if (Test-Path -LiteralPath $ownershipPath) {
        foreach ($path in (Get-Content -LiteralPath $ownershipPath -Raw | ConvertFrom-Json)) {
            if ($path -notmatch '^(?:\.github/(?:agents|prompts|instructions)/[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*\.md|\.agents/skills/[A-Za-z0-9_-]+)$') {
                throw 'Invalid squad source ownership path.'
            }
            [void]$owned.Add($path)
        }
    }
    # Pre-manifest APM installs flatten these reserved squad names. The three
    # non-squad skills and brand instruction also belong to this package, not hve-core.
    foreach ($kind in $flat.Keys) {
        $destination = Join-Path $To $flat[$kind]
        if (Test-Path -LiteralPath $destination) {
            foreach ($file in Get-ChildItem -LiteralPath $destination -File -Filter '*.md' |
                    Where-Object { $_.Name -like 'squad-*.md' -or $_.Name -ceq 'squad.prompt.md' }) {
                [void]$owned.Add("$($flat[$kind])/$($file.Name)")
            }
        }
    }
    [void]$owned.Add('.github/instructions/pptx-brand-template.instructions.md')
    foreach ($name in @('squad', 'azure-scaffold', 'python-diagrams', 'sql-migration-advisor')) {
        [void]$owned.Add(".agents/skills/$name")
    }
    foreach ($path in $owned) {
        $installed = Join-Path $To $path
        if (Test-Path -LiteralPath $installed) { Remove-Item -LiteralPath $installed -Recurse -Force }
    }
    $selected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($kind in $flat.Keys) {
        $source = Join-Path $From ".github/$kind"
        if (-not (Test-Path -LiteralPath $source)) { continue }

        $destination = Join-Path $To $flat[$kind]
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.md') {
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            [void]$selected.Add("$($flat[$kind])/$($file.Name)")
        }
    }

    $skillSource = Join-Path $From '.github/skills'
    if (Test-Path -LiteralPath $skillSource) {
        $skillDestination = Join-Path $To '.agents/skills'
        New-Item -ItemType Directory -Path $skillDestination -Force | Out-Null
        foreach ($directory in Get-ChildItem -LiteralPath $skillSource -Directory) {
            $destination = Join-Path $skillDestination $directory.Name
            if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
            Copy-Item -LiteralPath $directory.FullName -Destination $skillDestination -Recurse -Force
            [void]$selected.Add(".agents/skills/$($directory.Name)")
        }
    }
    New-Item -ItemType Directory -Path (Split-Path $ownershipPath -Parent) -Force | Out-Null
    ConvertTo-Json -InputObject @($selected | Sort-Object) | Set-Content -LiteralPath $ownershipPath -Encoding utf8NoBOM

    if ($NativeCli) {
        $sourceRoot = Split-Path -Path ([IO.Path]::GetFullPath($From)) -Parent
        $builder = Join-Path $sourceRoot 'scripts/Build-SquadPlugin.ps1'
        if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
            throw "Native CLI preparation requires the canonical plugin builder at '$builder'."
        }
        . $builder -SourceRoot $sourceRoot -RepoRoot $sourceRoot
        $source = Resolve-BuildSource -RepoRoot $sourceRoot `
            -RefSpecified $false -Ref $null -SourceRootSpecified $true -SourceRoot $sourceRoot
        $script:OutputRootResolved = Join-Path $To '.agents'
        $script:GeneratedPaths = [Collections.Generic.List[string]]::new()
        $script:RuleCitationMap = [ordered]@{}
        $null = Copy-InstructionRules -Source $source -RepoRoot $sourceRoot -OutputRoot $script:OutputRootResolved

        $markdown = @(
            Get-ChildItem -LiteralPath (Join-Path $To '.agents/skills/squad') -Recurse -File -Filter '*.md'
            Get-Item -LiteralPath (Join-Path $To '.github/instructions/squad-floor.instructions.md')
            Get-ChildItem -LiteralPath (Join-Path $From '.github/agents') -Recurse -File -Filter '*.md' |
                ForEach-Object { Get-Item -LiteralPath (Join-Path $To ".github/agents/$($_.Name)") }
        )
        foreach ($file in $markdown) {
            $content = Convert-AgentCitations -FileName $file.Name -Content (Get-Content -LiteralPath $file.FullName -Raw)
            $content = $content -replace '(?<![A-Za-z0-9/._-])skills/squad/', '.agents/skills/squad/'
            $content = $content.Replace(
                'In this plugin distribution they do not auto-apply at all — there is no instructions channel to apply them — so read the rule file that owns a decision before making it, and treat `rules/squad-floor.md` as unconditional.',
                'In this native CLI workspace, conditional squad rules are read on demand; the unconditional floor still auto-applies. Read the rule file that owns a decision before making it.'
            ).Replace(
                'the eleven companion instruction files that auto-apply when squad state is touched are catalogued in',
                'the companion rule references, read before the decisions they govern, are catalogued in'
            ).Replace(
                'The `squad` skill complements eleven instruction files that auto-apply when squad state is touched. Their `applyTo` globs only fire in a host that loads modular instructions, so a rule that must hold unconditionally belongs in a reference file above, not only here.',
                'Conditional squad rules are available in full as references below; read the rule that owns a decision before making it. The unconditional floor still auto-applies, and mandatory gates remain in the floor and the core references.'
            )
            Set-Content -LiteralPath $file.FullName -Value $content -Encoding utf8NoBOM -NoNewline
        }
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $From '.github/instructions/squad') -File -Filter '*.instructions.md') {
            if ($file.Name -eq 'squad-floor.instructions.md') { continue }
            Remove-Item -LiteralPath (Join-Path $To ".github/instructions/$($file.Name)") -Force
        }
    }
}

function Assert-TolerableInstallFailure {
    <#
    .SYNOPSIS
        Rethrows an install failure unless every error is a self-reference the overlay supplies.
    .DESCRIPTION
        A branch that ADDS a squad file cannot install: the manifest's self-references are
        bare paths, APM resolves them against the default branch, and the new file is
        reported missing. That is the failure source mode exists to work around, so
        aborting on it would make every additive branch untestable — including the ones
        most worth testing.

        The tolerance is narrow on purpose. Each failure must name a file that exists in
        the working copy, because that is the file the overlay is about to supply. A
        failure naming anything else is a real one and still throws. Validate each
        failed dependency record independently: an agent and prompt can share a package slug.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallLog,

        [string]$SourceRoot
    )

    $generic = "apm install failed with exit code $LASTEXITCODE. See $InstallLog."
    if (-not $SourceRoot) { throw $generic }

    # APM wraps its output at the terminal width, so the log is flattened before matching.
    $log = ((Get-Content -LiteralPath $InstallLog -Raw) -replace '\s+', ' ')

    $failed = @([regex]::Matches($log, '\+- (?<package>\S+) -- (?<error>.*?)(?= \+- \S+ -- |\z)'))
    if ($failed.Count -eq 0) { throw $generic }

    $missing = @(
        foreach ($record in $failed) {
            $errorText = $record.Groups['error'].Value
            # APM 0.29 uses the second form after its sparse-checkout fallback.
            $paths = @(@([regex]::Matches($errorText, 'File not found: (?<path>\S+) in ')) +
                @([regex]::Matches($errorText, "File '(?<path>[^']+)' not found after git sparse checkout")) |
                ForEach-Object { $_.Groups['path'].Value } | Sort-Object -Unique)
            if ($paths.Count -ne 1) { throw "$generic Unexplained failure for $($record.Groups['package'].Value)." }
            $paths[0]
        }
    )
    $unexplained = @($missing | Where-Object {
        $_ -notmatch '^squad-src/\.github/' -or $_ -match '(?:^|/)\.\.?(?:/|$)' -or
        -not (Test-Path -LiteralPath (Join-Path $SourceRoot $_))
    })
    if ($unexplained.Count -gt 0) {
        throw "$generic Not explained by the working copy: $($unexplained -join ', ')."
    }

    Write-Warning ("apm install reported {0} unresolvable self-reference record(s); every one names content this branch supplies through the overlay: {1}" -f $failed.Count, (($missing | Sort-Object -Unique) -join ', '))
}

function Install-SquadPackage {
    <#
    .SYNOPSIS
        Installs the squad package into a directory, from a published ref or a working copy.
    .DESCRIPTION
        Ref mode installs a published ref exactly as a consumer would.

        Source mode exists because a pull request branch cannot be installed: the
        manifest's self-references are bare paths, so APM resolves them against the
        default branch and every file the branch ADDS is reported missing. Source mode
        installs the manifest normally, then overlays the working copy's squad-src/ on
        top, which is the tree the branch would deliver once merged.
    .PARAMETER Destination
        Directory to install into. Created if absent; APM expects it empty.
    .PARAMETER Ref
        Published ref to install, for example 'v0.16.0' or 'main'.
    .PARAMETER SourceRoot
        Repository root holding apm.yml and squad-src/. Mutually exclusive with -Ref.
    .PARAMETER Package
        Package slug to install in ref mode.
    .PARAMETER Target
        Harness to deploy to. APM refuses to guess in an empty directory, so it is
        always passed explicitly.
    .PARAMETER InstallCommand
        Test hook that replaces `apm install`. Returns an object with ExitCode and Output.
    .PARAMETER SleepCommand
        Test hook that replaces Start-Sleep for GitHub throttle back-off.
    .OUTPUTS
        A hashtable with Root, InstallLog, Mode, and Ref.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Ref')]
    param(
        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter(ParameterSetName = 'Ref')]
        [string]$Ref = 'main',

        [Parameter(ParameterSetName = 'Ref')]
        [string]$Package = 'Peter-N91/hve-squad',

        [Parameter(Mandatory, ParameterSetName = 'Source')]
        [string]$SourceRoot,

        [string]$Target = 'copilot',

        [scriptblock]$InstallCommand,

        [scriptblock]$SleepCommand = { param([int]$Seconds) Start-Sleep -Seconds $Seconds }
    )

    if (-not $InstallCommand -and -not (Get-Command apm -ErrorAction SilentlyContinue)) {
        throw "The 'apm' CLI was not found on PATH."
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $Destination = (Resolve-Path -LiteralPath $Destination).Path
    $installLog = Join-Path $Destination 'install.log'

    if ($PSCmdlet.ParameterSetName -eq 'Source') {
        $SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
        Copy-Item -LiteralPath (Join-Path $SourceRoot 'apm.yml') -Destination $Destination -Force
        $installArgs = @()
    }
    else {
        $installArgs = @("$Package#$Ref")
    }

    $backoffs = @(30, 60, 120)
    $attempt = 0
    $installSucceeded = $false
    Set-Content -LiteralPath $installLog -Value '' -Encoding utf8NoBOM
    Push-Location $Destination
    try {
        while (-not $installSucceeded) {
            $attempt++
            # Both streams are captured: the unpinned-reference warning PKG-01 asserts on is
            # emitted to stderr. Write-Host rather than Out-Host, so a caller redirecting the
            # run still sees the log, and so the pass-through never joins the return value.
            if ($InstallCommand) {
                $result = & $InstallCommand -InstallArgs $installArgs -Target $Target -Attempt $attempt
                $output = @($result.Output)
                $exitCode = [int]$result.ExitCode
            }
            else {
                $output = @(& apm install @installArgs --target $Target *>&1)
                $exitCode = $LASTEXITCODE
            }
            $output | Tee-Object -FilePath $installLog -Append | ForEach-Object { Write-Host $_ }

            if ($exitCode -eq 0) {
                $installSucceeded = $true
                break
            }

            $logText = Get-Content -LiteralPath $installLog -Raw
            if ((Test-ApmThrottleFailure -Text $logText) -and $attempt -le $backoffs.Count) {
                $delay = $backoffs[$attempt - 1]
                Write-Warning "apm install hit GitHub throttling; retrying after $delay seconds (attempt $($attempt + 1) of $($backoffs.Count + 1))."
                & $SleepCommand -Seconds $delay
                continue
            }
            if (Test-ApmThrottleFailure -Text $logText) {
                throw "apm install failed after $($backoffs.Count + 1) attempts because GitHub throttling persisted. See $installLog."
            }

            $global:LASTEXITCODE = $exitCode
            $overlay = if ($PSCmdlet.ParameterSetName -eq 'Source') { $SourceRoot } else { '' }
            Assert-TolerableInstallFailure -InstallLog $installLog -SourceRoot $overlay
            $installSucceeded = $true
        }
    }
    finally {
        Pop-Location
    }

    if ($PSCmdlet.ParameterSetName -eq 'Source') {
        Copy-SquadSource -From (Join-Path $SourceRoot 'squad-src') -To $Destination
    }

    @{
        Root       = $Destination
        InstallLog = $installLog
        Mode       = $PSCmdlet.ParameterSetName
        Ref        = if ($PSCmdlet.ParameterSetName -eq 'Source') { $SourceRoot } else { $Ref }
    }
}

function Test-ApmThrottleFailure {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)
    $Text -match '(?is)(GitHub API throttle|HTTP\s*429|HTTP\s*403.*?(throttl|rate limit)|(throttl|rate limit).*?HTTP\s*403|\brate limit(ed)?\b|too many requests)'
}

Export-ModuleMember -Function Install-SquadPackage, Copy-SquadSource
