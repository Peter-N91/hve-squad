# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

<#
.SYNOPSIS
    Deterministic squad governance report: reads squad state, computes the report model, renders self-contained HTML.
.DESCRIPTION
    Pure and read-only. Same state files plus the same -AsOf produce byte-identical output. The
    consumption ledger is read as a document and shown in full, so a section or column it gains
    later needs no change here; only the headline figures (cost, tokens, ROI) are recognized by
    header text and degrade to "not derivable" when a ledger no longer states them.
#>

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'SquadGovernanceReport.Markdown.ps1')
. (Join-Path $PSScriptRoot 'SquadGovernanceReport.State.ps1')
. (Join-Path $PSScriptRoot 'SquadGovernanceReport.Ledger.ps1')
. (Join-Path $PSScriptRoot 'SquadGovernanceReport.Economics.ps1')
. (Join-Path $PSScriptRoot 'SquadGovernanceReport.Model.ps1')
. (Join-Path $PSScriptRoot 'SquadGovernanceReport.Html.ps1')

Export-ModuleMember -Function Get-SquadGovernanceModel, ConvertTo-SquadGovernanceHtml, Get-SquadGovernanceReceipt, New-SquadGovernanceStop, Get-SquadGovernanceExitCode, ConvertFrom-SqMarkdown, ConvertTo-SqInlineHtml
