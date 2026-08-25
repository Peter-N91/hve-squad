# PSScriptAnalyzer configuration.
#
# VS Code and the PowerShell extension pick this file up automatically, and
# .github/workflows/lint-powershell.yml passes it explicitly so local and CI
# results match.
#
# The CI gate blocks on Error severity only. Warning and Information findings
# are reported in the job summary so they stay visible without holding a merge
# for a stylistic preference.
@{
    IncludeDefaultRules = $true

    Severity = @('Error', 'Warning', 'Information')

    ExcludeRules = @(
        # These scripts are interactive CLI tools whose console output is the
        # point. Write-Host is the correct call for progress and prompts that
        # must not enter the pipeline, and rewriting them to Write-Output would
        # corrupt the values the runners return.
        'PSAvoidUsingWriteHost',

        # Reports the absence of an [OutputType] attribute on functions that
        # are internal helpers and never part of a published surface.
        'PSUseOutputTypeCorrectly',

        # This rule wants a UTF-8 BOM on every non-ASCII file. Every script here
        # begins with a `#!/usr/bin/env pwsh` shebang, and a BOM places bytes
        # ahead of it, which stops the kernel recognising the interpreter line
        # and breaks execution on Linux. CI runs these scripts on ubuntu-latest,
        # so honouring this rule would break the build.
        'PSUseBOMForUnicodeEncodedFile'
    )

    Rules = @{
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
        }

        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            IndentationSize = 4
        }
    }
}
