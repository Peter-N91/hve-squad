#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

# False positive: $SourceRoot is read inside BeforeDiscovery and BeforeAll, which
# PSScriptAnalyzer treats as scopes unrelated to the param block.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SourceRoot',
    Justification = 'Read inside Pester BeforeDiscovery and BeforeAll blocks.')]
param(
    [Parameter(Mandatory)]
    [string]$SourceRoot
)

# PKG-11 closes the gap between authoring a file and shipping it. A squad artifact that
# is not named in apm.yml is invisible to every consumer, and nothing else in Tier 0 can
# see it: the installed tree simply never contains the file, so there is no failure to
# observe - only a capability that silently does not exist.
BeforeDiscovery {
    $squadSrc = Join-Path $SourceRoot 'squad-src/.github'
    $manifest = Get-Content -LiteralPath (Join-Path $SourceRoot 'apm.yml') -Raw

    $script:DeclarableFiles = @(
        foreach ($kind in 'agents', 'prompts', 'instructions') {
            $directory = Join-Path $squadSrc $kind
            if (-not (Test-Path -LiteralPath $directory)) { continue }

            foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -File -Filter '*.md') {
                $relative = $file.FullName.Substring($SourceRoot.Length).TrimStart('\', '/') -replace '\\', '/'
                @{
                    Relative = $relative
                    Declared = $manifest -match [regex]::Escape("/$relative")
                }
            }
        }
    )

    $script:DeclarableSkills = @(
        $skillRoot = Join-Path $squadSrc 'skills'
        if (Test-Path -LiteralPath $skillRoot) {
            foreach ($skill in Get-ChildItem -LiteralPath $skillRoot -Directory) {
                $relative = "squad-src/.github/skills/$($skill.Name)"
                @{
                    Relative = $relative
                    Declared = $manifest -match [regex]::Escape("/$relative")
                }
            }
        }
    )
}

Describe 'PKG-11 Every squad artifact is declared in apm.yml' {
    # -ForEach is evaluated during discovery, which is the only scope that can see the
    # enumeration above.
    It 'finds squad source to check' -ForEach @(@{ Found = @($script:DeclarableFiles).Count }) {
        $Found | Should -BeGreaterThan 0 -Because 'an empty source tree means this suite is pointed at the wrong root'
    }

    It '<Relative> is declared' -ForEach $script:DeclarableFiles {
        $Declared | Should -BeTrue -Because 'an artifact missing from the manifest is authored but never shipped, and no consumer can tell'
    }

    It 'skill <Relative> is declared' -ForEach $script:DeclarableSkills {
        $Declared | Should -BeTrue -Because 'an undeclared skill directory never reaches a consumer'
    }
}
