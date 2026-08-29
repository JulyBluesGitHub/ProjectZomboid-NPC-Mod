[CmdletBinding()]
param(
    [string]$DestinationRoot = (Join-Path $env:USERPROFILE "Zomboid\mods"),
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-DirectChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )

    $parentFull = (Get-FullPath -Path $Parent).TrimEnd('\', '/')
    $childFull = Get-FullPath -Path $Child
    $expectedPrefix = $parentFull + [System.IO.Path]::DirectorySeparatorChar

    if (-not $childFull.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside destination root: $childFull"
    }

    $relative = $childFull.Substring($expectedPrefix.Length)
    if ($relative.Contains('\') -or $relative.Contains('/')) {
        throw "Expected a direct child of destination root, got: $childFull"
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourceMod = Get-FullPath -Path (Join-Path $repositoryRoot "mod\NPCDepth")
$destinationRootFull = Get-FullPath -Path $DestinationRoot
$destination = Get-FullPath -Path (Join-Path $destinationRootFull "NPCDepth")

if (-not (Test-Path -LiteralPath (Join-Path $sourceMod "42\mod.info") -PathType Leaf)) {
    throw "NPCDepth source manifest is missing: $sourceMod\42\mod.info"
}

New-Item -ItemType Directory -Path $destinationRootFull -Force | Out-Null
Assert-DirectChildPath -Parent $destinationRootFull -Child $destination

if ((Test-Path -LiteralPath $destination) -and -not $Force) {
    throw "A development install already exists at $destination. Re-run with -Force to create a backup and replace it."
}

$stageName = ".NPCDepth.stage.$([Guid]::NewGuid().ToString('N'))"
$stage = Get-FullPath -Path (Join-Path $destinationRootFull $stageName)
Assert-DirectChildPath -Parent $destinationRootFull -Child $stage
New-Item -ItemType Directory -Path $stage | Out-Null

Get-ChildItem -LiteralPath $sourceMod -Force | Copy-Item -Destination $stage -Recurse -Force

if (-not (Test-Path -LiteralPath (Join-Path $stage "42\mod.info") -PathType Leaf)) {
    throw "Staged install failed manifest validation. Files were left for inspection at $stage"
}

$backup = $null
if (Test-Path -LiteralPath $destination) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Get-FullPath -Path (Join-Path $destinationRootFull "NPCDepth.backup.$timestamp")
    Assert-DirectChildPath -Parent $destinationRootFull -Child $backup
    if (Test-Path -LiteralPath $backup) {
        throw "Backup target already exists: $backup"
    }
    Move-Item -LiteralPath $destination -Destination $backup
}

try {
    Move-Item -LiteralPath $stage -Destination $destination
}
catch {
    if ($null -ne $backup -and (Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $destination)) {
        Move-Item -LiteralPath $backup -Destination $destination
    }
    throw
}

Write-Output "Installed NPCDepth development mod to: $destination"
if ($null -ne $backup) {
    Write-Output "Previous install moved to recoverable backup: $backup"
}

