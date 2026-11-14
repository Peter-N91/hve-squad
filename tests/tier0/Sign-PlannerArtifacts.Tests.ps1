#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT

# AI cost: none; hashes owned local fixtures, without network or signing tools.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside BeforeAll.')]
param([Parameter(Mandatory)][string]$SourceRoot)

BeforeAll {
    $script:Cli = Join-Path $SourceRoot 'scripts' -AdditionalChildPath 'security', 'Sign-PlannerArtifacts.ps1'
    . $script:Cli -ProjectSlug unused
    $script:FixtureBase = Join-Path $PSScriptRoot ".rai-manifest-fixtures-$([guid]::NewGuid().ToString('N'))"
    [void][IO.Directory]::CreateDirectory($script:FixtureBase)
    $script:Links = [Collections.Generic.List[string]]::new()

    function New-ManifestFixture {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Creates only an owned local fixture; no supplied directory is modified.')]
        [CmdletBinding()]
        param()

        $Root = Join-Path $script:FixtureBase ([guid]::NewGuid().ToString('N'))
        $Session = Join-Path $Root '.copilot-tracking' -AdditionalChildPath 'rai-plans', 'demo-ai'
        [void][IO.Directory]::CreateDirectory($Session)
        @{ Root = $Root; Session = $Session; Manifest = Join-Path $Session 'artifact-manifest.json' }
    }

    function Invoke-ManifestCli {
        param([string]$ScriptPath = $script:Cli, [string]$WorkingDirectory, [string[]]$Arguments)
        $Start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        foreach ($Argument in @('-NoProfile', '-NonInteractive', '-File', $ScriptPath) + $Arguments) {
            $Start.ArgumentList.Add($Argument)
        }
        $Start.WorkingDirectory = $WorkingDirectory
        $Start.UseShellExecute = $false
        $Start.RedirectStandardOutput = $true
        $Start.RedirectStandardError = $true
        $Process = [Diagnostics.Process]::Start($Start)
        try {
            $Stdout = $Process.StandardOutput.ReadToEndAsync()
            $Stderr = $Process.StandardError.ReadToEndAsync()
            if (-not $Process.WaitForExit(30000)) {
                $Process.Kill($true)
                $Process.WaitForExit()
                throw 'Manifest CLI test watchdog expired.'
            }
            @{
                ExitCode = $Process.ExitCode
                Output = $Stdout.GetAwaiter().GetResult()
                ErrorText = $Stderr.GetAwaiter().GetResult()
            }
        }
        finally { $Process.Dispose() }
    }
}

Describe 'Local planner artifact integrity manifest' -Tag 'Unit' {
    It 'resolves a relative repository against PowerShell location without writing another root' {
        $Fixture = New-ManifestFixture
        $Other = New-ManifestFixture
        [IO.File]::WriteAllText((Join-Path $Fixture.Session 'plan.md'), 'selected repository')
        [IO.File]::WriteAllText((Join-Path $Other.Session 'plan.md'), 'other repository')
        $Location = Get-Location
        $ProcessDirectory = [Environment]::CurrentDirectory
        try {
            [Environment]::CurrentDirectory = $Other.Root
            Set-Location -LiteralPath $Fixture.Root

            $null = New-PlannerArtifactManifest -ProjectSlug demo-ai -RepoRoot '.'

            Test-Path -LiteralPath $Fixture.Manifest | Should -BeTrue
            Test-Path -LiteralPath $Other.Manifest | Should -BeFalse
            (Get-Content -LiteralPath $Fixture.Manifest -Raw | ConvertFrom-Json).artifacts.sha256 |
                Should -BeExactly ((Get-FileHash -LiteralPath (Join-Path $Fixture.Session 'plan.md')).Hash.ToLowerInvariant())
        }
        finally {
            Set-Location -LiteralPath $Location.Path
            [Environment]::CurrentDirectory = $ProcessDirectory
        }
    }

    It 'hashes exact bytes and inventories literal, nested and hidden paths in ordinal order' {
        $Fixture = New-ManifestFixture
        $Inputs = [ordered]@{
            'zeta.bin' = [byte[]](0..255)
            'alpha.txt' = [Text.Encoding]::UTF8.GetBytes('abc')
            'nested\[literal].json' = [Text.Encoding]::UTF8.GetBytes('{"a":1}')
            'nested\artifact-manifest.json' = [Text.Encoding]::UTF8.GetBytes('nested artifact')
            '.notes.md' = [Text.Encoding]::UTF8.GetBytes('private notes')
        }
        foreach ($InputFile in $Inputs.GetEnumerator()) {
            $Path = Join-Path $Fixture.Session $InputFile.Key
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
            [IO.File]::WriteAllBytes($Path, $InputFile.Value)
        }
        if ($IsWindows) {
            [IO.File]::SetAttributes((Join-Path $Fixture.Session '.notes.md'), [IO.FileAttributes]::Hidden)
        }
        $Before = [DateTime]::UtcNow
        $null = New-PlannerArtifactManifest -ProjectSlug demo-ai -RepoRoot $Fixture.Root
        $Json = Get-Content -LiteralPath $Fixture.Manifest -Raw
        $Manifest = $Json | ConvertFrom-Json

        $Manifest.fileCount | Should -Be 5
        $Manifest.artifacts.path | Should -Be @('.notes.md', 'alpha.txt', 'nested/[literal].json', 'nested/artifact-manifest.json', 'zeta.bin')
        foreach ($Artifact in $Manifest.artifacts) {
            $Path = Join-Path $Fixture.Session $Artifact.path
            $Artifact.sizeBytes | Should -Be ([IO.FileInfo]::new($Path).Length)
            $Artifact.sha256 | Should -BeExactly ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant())
        }
        $Manifest.artifacts[1].sha256 | Should -BeExactly 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        $Manifest.sessionPath | Should -BeExactly '.copilot-tracking/rai-plans/demo-ai'
        $Json | Should -Match '"generatedAt": "\d{4}-\d\d-\d\dT[^"]+Z"'
        ([DateTime]$Manifest.generatedAt).ToUniversalTime() | Should -BeGreaterOrEqual $Before
        ([DateTime]$Manifest.generatedAt).ToUniversalTime() | Should -BeLessOrEqual ([DateTime]::UtcNow)
    }

    It 'replaces only its manifest on repeat runs and excludes prior signatures and bundles' {
        $Fixture = New-ManifestFixture
        [IO.File]::WriteAllText((Join-Path $Fixture.Session 'plan.md'), 'first')
        $null = New-PlannerArtifactManifest -ProjectSlug demo-ai -RepoRoot $Fixture.Root
        $OldManifest = [IO.File]::ReadAllText($Fixture.Manifest)
        foreach ($Name in @('artifact-manifest.json.sig', 'artifact-manifest.json.bundle', 'prior.SIG')) {
            [IO.File]::WriteAllText((Join-Path $Fixture.Session $Name), 'keep these bytes')
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $Fixture.Session 'nested'))
        [IO.File]::WriteAllText((Join-Path $Fixture.Session 'nested\prior.bundle'), 'keep nested bytes')
        [IO.File]::WriteAllText((Join-Path $Fixture.Session 'added.md'), 'second')
        $null = New-PlannerArtifactManifest -ProjectSlug demo-ai -RepoRoot $Fixture.Root
        $Manifest = Get-Content -LiteralPath $Fixture.Manifest -Raw | ConvertFrom-Json
        $Manifest.fileCount | Should -Be 2
        $Manifest.artifacts.path | Should -Be @('added.md', 'plan.md')
        [IO.File]::ReadAllText($Fixture.Manifest) | Should -Not -BeExactly $OldManifest
        [IO.File]::ReadAllText((Join-Path $Fixture.Session 'artifact-manifest.json.sig')) | Should -BeExactly 'keep these bytes'
        [IO.File]::ReadAllText((Join-Path $Fixture.Session 'nested\prior.bundle')) | Should -BeExactly 'keep nested bytes'
    }

    It 'rejects invalid or traversing slug <Slug> without writing a manifest' -ForEach @(
        @{ Slug = '../outside' }, @{ Slug = '..\outside' }, @{ Slug = 'nested/session' }
        @{ Slug = 'nested\session' }, @{ Slug = 'C:\outside' }, @{ Slug = 'demo:stream' }
        @{ Slug = '.' }, @{ Slug = '..' }, @{ Slug = 'demo.' }, @{ Slug = ' demo' }
        @{ Slug = 'DEMO' }, @{ Slug = 'con' }, @{ Slug = 'demo--ai' }, @{ Slug = "demo`n" }
    ) {
        $Fixture = New-ManifestFixture
        { New-PlannerArtifactManifest -ProjectSlug $Slug -RepoRoot $Fixture.Root } | Should -Throw '*Invalid ProjectSlug*'
        Test-Path -LiteralPath $Fixture.Manifest | Should -BeFalse
    }

    It 'fails visibly for <Case> rather than producing an empty success manifest' -ForEach @(
        @{ Case = 'missing root' }, @{ Case = 'root is a file' }, @{ Case = 'missing session' }
        @{ Case = 'session is a file' }, @{ Case = 'empty session' }
        @{ Case = 'only excluded files' }, @{ Case = 'empty artifact' }, @{ Case = 'manifest is a directory' }
    ) {
        $Fixture = New-ManifestFixture
        $Root = $Fixture.Root
        switch ($Case) {
            'missing root' { $Root = Join-Path $Fixture.Root 'absent' }
            'root is a file' {
                $Root = Join-Path $Fixture.Root 'not-a-directory'
                [IO.File]::WriteAllText($Root, 'content')
            }
            'missing session' { [IO.Directory]::Delete($Fixture.Session) }
            'session is a file' {
                [IO.Directory]::Delete($Fixture.Session)
                [IO.File]::WriteAllText($Fixture.Session, 'content')
            }
            'only excluded files' {
                [IO.File]::WriteAllText($Fixture.Manifest, '{"old":true}')
                [IO.File]::WriteAllText((Join-Path $Fixture.Session 'old.sig'), 'signature')
            }
            'empty artifact' { [IO.File]::WriteAllBytes((Join-Path $Fixture.Session 'empty.md'), [byte[]]@()) }
            'manifest is a directory' {
                [void][IO.Directory]::CreateDirectory($Fixture.Manifest)
                [IO.File]::WriteAllText((Join-Path $Fixture.Session 'plan.md'), 'content')
            }
        }
        { New-PlannerArtifactManifest -ProjectSlug demo-ai -RepoRoot $Root } | Should -Throw
        if ($Case -eq 'only excluded files') {
            [IO.File]::ReadAllText($Fixture.Manifest) | Should -BeExactly '{"old":true}'
        }
        elseif ($Case -ne 'manifest is a directory') {
            Test-Path -LiteralPath $Fixture.Manifest | Should -BeFalse
        }
    }

    It 'preserves an existing manifest when an artifact cannot be read' {
        $Fixture = New-ManifestFixture
        $Artifact = Join-Path $Fixture.Session 'plan.md'
        [IO.File]::WriteAllText($Artifact, 'content')
        $null = New-PlannerArtifactManifest -ProjectSlug demo-ai -RepoRoot $Fixture.Root
        $OldManifest = [IO.File]::ReadAllText($Fixture.Manifest)
        $Lock = [IO.File]::Open($Artifact, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            { New-PlannerArtifactManifest -ProjectSlug demo-ai -RepoRoot $Fixture.Root } | Should -Throw
            [IO.File]::ReadAllText($Fixture.Manifest) | Should -BeExactly $OldManifest
        }
        finally { $Lock.Dispose() }
    }

    It 'rejects a reparse escape at <Location> without touching its target' -ForEach @(
        @{ Location = 'repository' }, @{ Location = 'tracking root' }, @{ Location = 'plans root' }
        @{ Location = 'session' }, @{ Location = 'nested directory' }, @{ Location = 'artifact' }
        @{ Location = 'output manifest' }, @{ Location = 'excluded signature' }
    ) {
        $Fixture = New-ManifestFixture
        $Outside = Join-Path $script:FixtureBase ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($Outside)
        $Sentinel = Join-Path $Outside 'sentinel.md'
        [IO.File]::WriteAllText($Sentinel, 'must remain untouched')
        $Root = $Fixture.Root
        $IsFileLink = $Location -in 'artifact', 'output manifest', 'excluded signature'
        $LinkPath = switch ($Location) {
            'repository' {
                $Root = Join-Path $script:FixtureBase ([guid]::NewGuid().ToString('N'))
                $Root
            }
            'tracking root' { Join-Path $Fixture.Root '.copilot-tracking' }
            'plans root' { Join-Path $Fixture.Root '.copilot-tracking\rai-plans' }
            'session' { $Fixture.Session }
            'nested directory' { Join-Path $Fixture.Session 'linked' }
            'artifact' { Join-Path $Fixture.Session 'linked.md' }
            'output manifest' { $Fixture.Manifest }
            'excluded signature' { Join-Path $Fixture.Session 'old.sig' }
        }
        if (Test-Path -LiteralPath $LinkPath) {
            # Only the empty directory tree created by this fixture is removed.
            [IO.Directory]::Delete($LinkPath, $true)
        }
        $Target = if ($IsFileLink) { $Sentinel } else { $Outside }
        $LinkType = if ($IsWindows -and -not $IsFileLink) { 'Junction' } else { 'SymbolicLink' }
        try {
            $null = New-Item -ItemType $LinkType -Path $LinkPath -Target $Target -ErrorAction Stop
            $script:Links.Add($LinkPath)
        }
        catch {
            Set-ItResult -Skipped -Because "Cannot create $LinkType on this host: $($_.Exception.Message)"
            return
        }

        { New-PlannerArtifactManifest -ProjectSlug demo-ai -RepoRoot $Root } | Should -Throw '*Reparse points*'
        [IO.File]::ReadAllText($Sentinel) | Should -BeExactly 'must remain untouched'
        Test-Path -LiteralPath (Join-Path $Outside 'artifact-manifest.json') | Should -BeFalse
    }

    It 'rejects UNC roots before filesystem access' {
        { New-PlannerArtifactManifest -ProjectSlug demo-ai -RepoRoot '\\invalid.example\share' } |
            Should -Throw '*Network and device paths*'
    }

    It 'resolves its default root from the script location, not the caller working directory' {
        $Fixture = New-ManifestFixture
        [IO.File]::WriteAllText((Join-Path $Fixture.Session 'plan.md'), 'abc')
        $Copy = Join-Path $Fixture.Root 'scripts' -AdditionalChildPath 'security', 'Sign-PlannerArtifacts.ps1'
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Copy))
        [IO.File]::Copy($script:Cli, $Copy)
        $Result = Invoke-ManifestCli -ScriptPath $Copy -WorkingDirectory $script:FixtureBase -Arguments @('-ProjectSlug', 'demo-ai')
        $Result.ExitCode | Should -Be 0 -Because $Result.ErrorText
        $Result.Output | Should -Match 'Integrity manifest written'
        $Result.Output | Should -Match 'not a signature or proof of cryptographic authorship'
        $Manifest = Get-Content -LiteralPath $Fixture.Manifest -Raw | ConvertFrom-Json
        $Manifest.fileCount | Should -Be 1
        $Manifest.artifacts[0].sha256 | Should -BeExactly 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }

    It 'returns a nonzero CLI exit and contextual console error for a missing session' {
        $Fixture = New-ManifestFixture
        $Result = Invoke-ManifestCli -WorkingDirectory $script:FixtureBase -Arguments @('-ProjectSlug', 'missing', '-RepoRoot', $Fixture.Root)
        $Result.ExitCode | Should -Be 1
        $Result.ErrorText | Should -Match 'Sign-PlannerArtifacts failed:'
        $Result.Output | Should -Not -Match 'manifest written'
        Test-Path -LiteralPath $Fixture.Manifest | Should -BeFalse
    }
}

AfterAll {
    foreach ($Link in $script:Links) {
        Remove-Item -LiteralPath $Link -Force -ErrorAction Stop
    }
    # FixtureBase is an exclusively owned GUID directory, never a supplied root.
    if (Test-Path -LiteralPath $script:FixtureBase) {
        Remove-Item -LiteralPath $script:FixtureBase -Recurse -Force
    }
}
