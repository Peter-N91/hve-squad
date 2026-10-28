# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
#Requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-SquadPromotionText {
    param(
        [Parameter(Mandatory)]$Value,
        [switch]$AllowEmpty
    )
    if ($Value -isnot [string] -or $Value -match '[\r\n|\x00-\x1f]' -or
        (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value))) {
        throw 'Expected a single-line value without table delimiters or control characters.'
    }
}

function Get-SquadPromotionHash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Get-SquadPromotionTreeSnapshot {
    param([Parameter(Mandatory)][string]$Root)
    $rootItem = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Promotion source must be an unlinked directory: $Root"
    }
    $lines = [Collections.Generic.List[string]]::new()
    $fileCount = 0
    $directoryCount = 0
    $bytes = 0L
    $paths = [string[]]@(Get-ChildItem -LiteralPath $rootItem.FullName -Recurse -Force | ForEach-Object FullName)
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    foreach ($path in $paths) {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked promotion source refused: $($item.FullName)"
        }
        $relative = [IO.Path]::GetRelativePath($rootItem.FullName, $item.FullName) -replace '\\', '/'
        if ($relative -match '[\r\n\t\x00]') { throw "Promotion path contains a control character: $relative" }
        if ($item.PSIsContainer) {
            $directoryCount++
            $lines.Add("D`t$relative")
            continue
        }
        $fileCount++
        $bytes += $item.Length
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        $lines.Add("F`t$relative`t$($item.Length)`t$hash")
    }
    $manifest = [Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n"))
    [ordered]@{
        digest = Get-SquadPromotionHash $manifest
        files = $fileCount
        directories = $directoryCount
        bytes = $bytes
    }
}

function Assert-SquadPromotionSnapshot {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [string]$Label = 'promotion source'
    )
    foreach ($field in @('digest', 'files', 'directories', 'bytes')) {
        if (-not $Expected.Contains($field) -or $Expected[$field] -cne $Actual[$field]) {
            throw "$Label changed after the promotion plan was captured."
        }
    }
}

function Copy-SquadPromotionTree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)]$ExpectedSnapshot
    )
    if (Test-Path -LiteralPath $Destination) { throw "Promotion destination already exists: $Destination" }
    $null = [IO.Directory]::CreateDirectory($Destination)
    foreach ($item in Get-ChildItem -LiteralPath $Source -Recurse -Force | Sort-Object FullName) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked promotion source refused: $($item.FullName)"
        }
        $relative = [IO.Path]::GetRelativePath($Source, $item.FullName)
        $target = [IO.Path]::GetFullPath($relative, $Destination)
        if ($item.PSIsContainer) {
            $null = [IO.Directory]::CreateDirectory($target)
        }
        else {
            $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $target))
            [IO.File]::Copy($item.FullName, $target, $false)
        }
    }
    Assert-SquadPromotionSnapshot -Expected $ExpectedSnapshot -Actual (Get-SquadPromotionTreeSnapshot $Destination) -Label "copied destination '$Destination'"
}

function Get-SquadPromotionTopDirectory {
    param([AllowEmptyString()][string]$Value)
    if (-not $Value) { return $null }
    $clean = $Value.Trim().Trim('`')
    $label = [regex]::Match($clean, '\s+\((?:ADO|Jira)\)$')
    if ($label.Success) { $clean = $clean.Substring(0, $label.Index).Trim() }
    $match = [regex]::Match($clean, '^\.copilot-tracking/(?<name>[^/<>:\r\n]+)(?:/|$)', 'IgnoreCase')
    if (-not $match.Success) { return $null }
    $name = $match.Groups['name'].Value.Trim()
    if (-not $name -or $name -in @('.', '..') -or $name -ieq 'squad') { return $null }
    $name
}

function Get-SquadPromotionRequiredDirectoryMap {
    param(
        [Parameter(Mandatory)][string]$TeamPath,
        [Parameter(Mandatory)][string]$HistoryRoot
    )
    $required = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $team = [IO.File]::ReadAllText($TeamPath)
    $lines = $team -split "`r?`n"
    $headerIndex = -1
    $columnIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $lines[$i].TrimStart().StartsWith('|')) { continue }
        $cells = @($lines[$i].Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        $candidate = [Array]::IndexOf($cells, 'Deliverable Root')
        if ($candidate -ge 0) {
            $headerIndex = $i
            $columnIndex = $candidate
            break
        }
    }
    if ($headerIndex -lt 0) { throw 'Promotion could not find the roster Deliverable Root column.' }
    for ($i = $headerIndex + 2; $i -lt $lines.Count; $i++) {
        if (-not $lines[$i].TrimStart().StartsWith('|')) { break }
        $cells = @($lines[$i].Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($columnIndex -ge $cells.Count) { throw 'Malformed roster row during promotion planning.' }
        foreach ($alternative in $cells[$columnIndex] -split '\s+or\s+') {
            $name = Get-SquadPromotionTopDirectory $alternative
            if (-not $name) { continue }
            if (-not $required.ContainsKey($name)) { $required[$name] = [Collections.Generic.List[string]]::new() }
            if ('roster Deliverable Root' -notin $required[$name]) { $required[$name].Add('roster Deliverable Root') }
        }
    }
    if (Test-Path -LiteralPath $HistoryRoot -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $HistoryRoot -File -Force | Sort-Object Name) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($file.FullName), '(?m)^\* Deliverable:\s*(?<path>[^\r\n]+)$')) {
                $name = Get-SquadPromotionTopDirectory $match.Groups['path'].Value
                if (-not $name) { continue }
                if (-not $required.ContainsKey($name)) { $required[$name] = [Collections.Generic.List[string]]::new() }
                if ('append-only history' -notin $required[$name]) { $required[$name].Add('append-only history') }
            }
        }
    }
    $required
}

function Get-SquadPromotionProfile {
    param(
        [Parameter(Mandatory)][string]$DecisionsPath,
        [Parameter(Mandatory)]$Roster,
        [Parameter(Mandatory)]$InitData
    )
    $profileMatches = [regex]::Matches([IO.File]::ReadAllText($DecisionsPath), '(?m)^\* Provenance:\s*(?<profile>[^\r\n|]+?)\s*$')
    if ($profileMatches.Count) { return $profileMatches[-1].Groups['profile'].Value.Trim() }
    $roles = @($Roster | ForEach-Object Role | Sort-Object -Unique)
    $profiles = @(
        foreach ($row in $InitData.profiles) {
            $candidate = @($row['Members (roles)'] -split ',\s*' | Sort-Object -Unique)
            if (($candidate -join "`n") -ceq ($roles -join "`n")) { $row.Profile }
        }
    )
    if ($profiles.Count -eq 1) { return $profiles[0] }
    'custom'
}

function ConvertTo-SquadPromotionTeam {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf
    $encoding = [Text.UTF8Encoding]::new($hasBom)
    $contentBytes = if ($hasBom) { $bytes[3..($bytes.Length - 1)] } else { $bytes }
    $text = [Text.UTF8Encoding]::new($false).GetString($contentBytes)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $trailingNewline = $text.EndsWith("`n")
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in ($text -split "`r?`n")) { $lines.Add($line) }
    if ($trailingNewline -and $lines.Count -and $lines[-1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $headerIndex = -1
    $columnIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $lines[$i].TrimStart().StartsWith('|')) { continue }
        $cells = @($lines[$i].Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        $candidate = [Array]::IndexOf($cells, 'Deliverable Root')
        if ($candidate -ge 0) {
            $headerIndex = $i
            $columnIndex = $candidate
            break
        }
    }
    if ($headerIndex -lt 0) { throw 'Promotion could not find the roster Deliverable Root column.' }
    $roots = [Collections.Generic.List[string]]::new()
    $changed = 0
    for ($i = $headerIndex + 2; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if (-not $line.TrimStart().StartsWith('|')) { break }
        $pipes = @([regex]::Matches($line, '\|') | ForEach-Object Index)
        if ($columnIndex + 1 -ge $pipes.Count) { throw 'Malformed roster row during promotion.' }
        $start = $pipes[$columnIndex] + 1
        $length = $pipes[$columnIndex + 1] - $start
        $raw = $line.Substring($start, $length)
        $value = $raw.Trim()
        if ($value -match '(?i)\.copilot-tracking/squad/members/') {
            throw 'A plain squad roster already points at a federation member root.'
        }
        $updated = [regex]::Replace(
            $value,
            '(?<![A-Za-z0-9_.-])\.copilot-tracking/',
            ".copilot-tracking/squad/members/$Name/",
            [Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($updated -cne $value) {
            $leading = $raw.Length - $raw.TrimStart().Length
            $trailing = $raw.Length - $raw.TrimEnd().Length
            $replacement = $raw.Substring(0, $leading) + $updated
            if ($trailing) { $replacement += $raw.Substring($raw.Length - $trailing) }
            $lines[$i] = $line.Substring(0, $start) + $replacement + $line.Substring($start + $length)
            $changed++
        }
        $roots.Add($updated)
    }
    if ($changed -eq 0) { throw 'Promotion found no .copilot-tracking Deliverable Root to rebase.' }
    [ordered]@{
        text = ($lines -join $newline) + $(if ($trailingNewline) { $newline })
        encoding = $encoding
        roots = $roots.ToArray()
        changedRows = $changed
    }
}

function Get-SquadPromotionDeliverableDirectory {
    param(
        [Parameter(Mandatory)][string[]]$Roots,
        [Parameter(Mandatory)][string]$Name
    )
    $prefix = ".copilot-tracking/squad/members/$Name/"
    $directories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $Roots) {
        foreach ($alternative in $root -split '\s+or\s+') {
            $clean = $alternative.Trim().Trim('`')
            $label = [regex]::Match($clean, '\s+\((?:ADO|Jira)\)$')
            if ($label.Success) { $clean = $clean.Substring(0, $label.Index).Trim() }
            if (-not $clean.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $placeholder = $clean.IndexOf('<')
            if ($placeholder -ge 0) { $clean = $clean.Substring(0, $placeholder) }
            $clean = $clean.TrimEnd('/')
            if ($clean.Length -le $prefix.TrimEnd('/').Length) { continue }
            $relative = $clean.Substring($prefix.Length).Trim('/')
            if ($relative -and $relative -notmatch '(^|/)\.\.(/|$)|[:\x00-\x1f]') { $null = $directories.Add($relative) }
        }
    }
    @($directories | Sort-Object)
}

function Add-SquadPromotionEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Header,
        [Parameter(Mandatory)][string]$Entry
    )
    $before = if (Test-Path -LiteralPath $Path) { ,([IO.File]::ReadAllBytes($Path)) } else { ,([byte[]]::new(0)) }
    $text = [Text.Encoding]::UTF8.GetString($before)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $tail = if ($before.Length) {
        $(if ($before[-1] -ne 10) { $newline }) + $newline + ($Entry -replace "`r?`n", $newline) + $newline
    }
    else {
        ($Header + "`n`n" + $Entry + "`n") -replace "`r?`n", $newline
    }
    $stream = [IO.MemoryStream]::new()
    try {
        $stream.Write($before)
        $stream.Write([Text.UTF8Encoding]::new($false).GetBytes($tail))
        ,$stream.ToArray()
    }
    finally { $stream.Dispose() }
}

function Write-SquadPromotionText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

Export-ModuleMember -Function Assert-SquadPromotionText, Get-SquadPromotionHash, Get-SquadPromotionTreeSnapshot, Assert-SquadPromotionSnapshot, Copy-SquadPromotionTree, Get-SquadPromotionRequiredDirectoryMap, Get-SquadPromotionProfile, ConvertTo-SquadPromotionTeam, Get-SquadPromotionDeliverableDirectory, Add-SquadPromotionEntry, Write-SquadPromotionText
