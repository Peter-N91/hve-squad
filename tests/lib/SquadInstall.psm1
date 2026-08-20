# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# Provisions the package a consumer actually receives, for any tier to assert against.
#
# Both Tier 0 and the Tier 1 live harness need the same tree, and they need it built
# the same way: a divergence between "the tree Tier 0 inspected" and "the tree Tier 1
# ran" would make a Tier 1 failure unattributable.

#Requires -Version 7.4

Set-StrictMode -Version Latest

function Copy-SquadSource {
    <#
    .SYNOPSIS
        Overlays a working copy's squad-src/ onto an installed tree, matching APM's layout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$From,

        [Parameter(Mandatory)]
        [string]$To
    )

    # APM flattens agents, prompts, and instructions; skills keep their directory.
    $flat = @{
        'agents'       = '.github/agents'
        'prompts'      = '.github/prompts'
        'instructions' = '.github/instructions'
    }

    foreach ($kind in $flat.Keys) {
        $source = Join-Path $From ".github/$kind"
        if (-not (Test-Path -LiteralPath $source)) { continue }

        $destination = Join-Path $To $flat[$kind]
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Get-ChildItem -LiteralPath $source -Recurse -File -Filter '*.md' |
            Copy-Item -Destination $destination -Force
    }

    $skillSource = Join-Path $From '.github/skills'
    if (Test-Path -LiteralPath $skillSource) {
        $skillDestination = Join-Path $To '.agents/skills'
        New-Item -ItemType Directory -Path $skillDestination -Force | Out-Null
        Get-ChildItem -LiteralPath $skillSource -Directory |
            Copy-Item -Destination $skillDestination -Recurse -Force
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
        failure naming anything else is a real one and still throws.
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

    $missing = @([regex]::Matches($log, 'File not found: (?<path>\S+) in ') |
            ForEach-Object { $_.Groups['path'].Value } | Sort-Object -Unique)
    $failed = @([regex]::Matches($log, '\+- (?<package>\S+) -- ') |
            ForEach-Object { $_.Groups['package'].Value } | Sort-Object -Unique)

    if ($missing.Count -eq 0 -or $failed.Count -ne $missing.Count) { throw $generic }

    $unexplained = @($missing | Where-Object { -not (Test-Path -LiteralPath (Join-Path $SourceRoot $_)) })
    if ($unexplained.Count -gt 0) {
        throw "$generic Not explained by the working copy: $($unexplained -join ', ')."
    }

    Write-Warning ("apm install reported {0} unresolvable self-reference(s); every one names a file this branch adds, and the overlay supplies them: {1}" -f $missing.Count, ($missing -join ', '))
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

        [string]$Target = 'copilot'
    )

    if (-not (Get-Command apm -ErrorAction SilentlyContinue)) {
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

    Push-Location $Destination
    try {
        # Both streams are captured: the unpinned-reference warning PKG-01 asserts on is
        # emitted to stderr. Write-Host rather than Out-Host, so a caller redirecting the
        # run still sees the log, and so the pass-through never joins the return value.
        & apm install @installArgs --target $Target *>&1 |
            Tee-Object -FilePath $installLog |
            ForEach-Object { Write-Host $_ }

        if ($LASTEXITCODE -ne 0) {
            $overlay = if ($PSCmdlet.ParameterSetName -eq 'Source') { $SourceRoot } else { '' }
            Assert-TolerableInstallFailure -InstallLog $installLog -SourceRoot $overlay
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

Export-ModuleMember -Function Install-SquadPackage, Copy-SquadSource
