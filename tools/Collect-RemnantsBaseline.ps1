[CmdletBinding()]
param(
    [string]$ProjectZomboidPath,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workshopId = "3738362476"
$expectedModId = "ProjectRemnants"

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Find-ProjectZomboidInstall {
    param([string]$ExplicitPath)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates.Add($ExplicitPath)
    }

    try {
        $steamPath = (Get-ItemProperty -LiteralPath "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath
        if (-not [string]::IsNullOrWhiteSpace($steamPath)) {
            $candidates.Add((Join-Path $steamPath "steamapps\common\ProjectZomboid"))
        }
    }
    catch {
        # Registry discovery is optional.
    }

    foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
        $candidates.Add((Join-Path $drive.Root "Steam\steamapps\common\ProjectZomboid"))
        $candidates.Add((Join-Path $drive.Root "SteamLibrary\steamapps\common\ProjectZomboid"))
    }

    foreach ($candidate in $candidates) {
        $full = Get-FullPath -Path $candidate
        if (Test-Path -LiteralPath (Join-Path $full "projectzomboid.jar") -PathType Leaf) {
            return $full
        }
    }

    throw "Could not locate Project Zomboid. Pass -ProjectZomboidPath explicitly."
}

function Get-FileEvidence {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path
    $hash = Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256
    return [ordered]@{
        path = $item.FullName
        length = $item.Length
        lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString("o")
        sha256 = $hash.Hash.ToLowerInvariant()
    }
}

function Read-ModInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([^#=]+?)\s*=\s*(.*?)\s*$') {
            $key = $matches[1].Trim()
            $value = $matches[2]
            $values[$key] = $value
        }
    }
    return $values
}

function Find-RemnantsRoot {
    param([Parameter(Mandatory = $true)][string]$WorkshopItemPath)

    $expected = Join-Path $WorkshopItemPath "mods\ProjectRemnants"
    if (Test-Path -LiteralPath $expected -PathType Container) {
        return (Get-FullPath -Path $expected)
    }

    $modsPath = Join-Path $WorkshopItemPath "mods"
    if (-not (Test-Path -LiteralPath $modsPath -PathType Container)) {
        return $null
    }

    foreach ($candidate in Get-ChildItem -LiteralPath $modsPath -Directory) {
        $manifests = Get-ChildItem -LiteralPath $candidate.FullName -Filter mod.info -File -Recurse -ErrorAction SilentlyContinue
        foreach ($manifest in $manifests) {
            $data = Read-ModInfo -Path $manifest.FullName
            if ($data.Contains("id") -and $data["id"] -eq $expectedModId) {
                return $candidate.FullName
            }
        }
    }

    return $null
}

function Get-AgentArguments {
    param([Parameter(Mandatory = $true)][string]$LaunchConfigPath)

    $result = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $LaunchConfigPath -PathType Leaf)) {
        return $result
    }

    try {
        $config = Get-Content -LiteralPath $LaunchConfigPath -Raw | ConvertFrom-Json
        foreach ($argument in @($config.vmArgs)) {
            $value = [string]$argument
            if ($value.StartsWith("-javaagent:", [System.StringComparison]::OrdinalIgnoreCase)) {
                $result.Add($value.Substring("-javaagent:".Length))
            }
        }
    }
    catch {
        $result.Add("<launch-config-parse-error: $($_.Exception.Message)>")
    }
    return $result
}

$gamePath = Find-ProjectZomboidInstall -ExplicitPath $ProjectZomboidPath
$steamAppsPath = Split-Path -Parent (Split-Path -Parent $gamePath)
$appManifestPath = Join-Path $steamAppsPath "appmanifest_108600.acf"
$workshopItemPath = Join-Path $steamAppsPath "workshop\content\108600\$workshopId"
$remnantsRoot = Find-RemnantsRoot -WorkshopItemPath $workshopItemPath

$appBuildId = $null
if (Test-Path -LiteralPath $appManifestPath -PathType Leaf) {
    $appManifestText = Get-Content -LiteralPath $appManifestPath -Raw
    if ($appManifestText -match '"buildid"\s+"([0-9]+)"') {
        $appBuildId = $matches[1]
    }
}

$launchConfigPath = Join-Path $gamePath "ProjectZomboid64.json"
$agentArguments = @(Get-AgentArguments -LaunchConfigPath $launchConfigPath)

$jarCandidates = [System.Collections.Generic.List[object]]::new()
$gameJarCandidate = Join-Path $gamePath "NPCFW.jar"
if (Test-Path -LiteralPath $gameJarCandidate -PathType Leaf) {
    $jarCandidates.Add((Get-FileEvidence -Path $gameJarCandidate))
}
if ($null -ne $remnantsRoot) {
    foreach ($jar in Get-ChildItem -LiteralPath $remnantsRoot -Filter "NPCFW.jar" -File -Recurse -ErrorAction SilentlyContinue) {
        $jarCandidates.Add((Get-FileEvidence -Path $jar.FullName))
    }
}

$distinctJarHashes = @($jarCandidates | ForEach-Object { $_.sha256 } | Sort-Object -Unique)

$remnantsManifests = [System.Collections.Generic.List[object]]::new()
$remnantsFiles = [System.Collections.Generic.List[object]]::new()
$npcfwReferences = [System.Collections.Generic.List[object]]::new()

if ($null -ne $remnantsRoot) {
    foreach ($manifest in Get-ChildItem -LiteralPath $remnantsRoot -Filter mod.info -File -Recurse) {
        $remnantsManifests.Add([ordered]@{
            file = Get-FileEvidence -Path $manifest.FullName
            values = Read-ModInfo -Path $manifest.FullName
        })
    }

    $evidenceFiles = Get-ChildItem -LiteralPath $remnantsRoot -File -Recurse | Where-Object {
        $_.Name -eq "mod.info" -or
        $_.Extension -eq ".lua" -or
        $_.Extension -eq ".jar" -or
        $_.Name -eq "install_project_remnants.ps1"
    } | Sort-Object FullName

    foreach ($file in $evidenceFiles) {
        $remnantsFiles.Add((Get-FileEvidence -Path $file.FullName))

        if ($file.Extension -eq ".lua") {
            foreach ($matchInfo in Select-String -LiteralPath $file.FullName -Pattern '\bnpcfw[A-Za-z0-9_]*' -AllMatches) {
                $symbols = @($matchInfo.Matches | ForEach-Object { $_.Value } | Sort-Object -Unique)
                $npcfwReferences.Add([ordered]@{
                    path = $file.FullName
                    line = $matchInfo.LineNumber
                    symbols = $symbols
                    text = $matchInfo.Line.Trim()
                })
            }
        }
    }
}

$normalItemsPath = Join-Path $gamePath "media\scripts\generated\items\normal.txt"
$sterileItems = [System.Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $normalItemsPath -PathType Leaf) {
    foreach ($itemName in @("AlcoholBandage", "AlcoholRippedSheets")) {
        $declaration = Select-String -LiteralPath $normalItemsPath -Pattern "^\s*item\s+$itemName\s*$" | Select-Object -First 1
        $sterileItems.Add([ordered]@{
            fullType = "Base.$itemName"
            declarationFound = $null -ne $declaration
            declarationLine = if ($null -ne $declaration) { $declaration.LineNumber } else { $null }
        })
    }
}

$report = [ordered]@{
    schemaVersion = 1
    collectorVersion = "0.1.0-dev"
    collectedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    game = [ordered]@{
        installPath = $gamePath
        appManifest = if (Test-Path -LiteralPath $appManifestPath -PathType Leaf) { Get-FileEvidence -Path $appManifestPath } else { $null }
        appBuildId = $appBuildId
        projectZomboidJar = Get-FileEvidence -Path (Join-Path $gamePath "projectzomboid.jar")
        launchConfig = if (Test-Path -LiteralPath $launchConfigPath -PathType Leaf) { Get-FileEvidence -Path $launchConfigPath } else { $null }
    }
    remnants = [ordered]@{
        workshopId = $workshopId
        expectedModId = $expectedModId
        workshopItemPath = $workshopItemPath
        present = $null -ne $remnantsRoot
        root = $remnantsRoot
        manifests = $remnantsManifests
        fileEvidence = $remnantsFiles
        npcfwReferences = $npcfwReferences
    }
    agent = [ordered]@{
        configuredPaths = $agentArguments
        configured = $agentArguments.Count -gt 0
        jarCandidates = $jarCandidates
        divergentJarHashes = $distinctJarHashes.Count -gt 1
    }
    semanticItems = [ordered]@{
        sourceFile = if (Test-Path -LiteralPath $normalItemsPath -PathType Leaf) { Get-FileEvidence -Path $normalItemsPath } else { $null }
        sterileDressing = $sterileItems
    }
    limitations = @(
        "This collector is read-only and does not launch the game.",
        "Runtime readiness and companion discovery still require a disposable in-game session.",
        "Unknown NPCFW.jar bytecode is not decompiled."
    )
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $repositoryRoot "artifacts\baselines\remnants-baseline-$timestamp.json"
}

$outputFull = Get-FullPath -Path $OutputPath
$outputDirectory = Split-Path -Parent $outputFull
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputFull -Encoding UTF8

Write-Output "Wrote baseline: $outputFull"
Write-Output "Project Zomboid app build ID: $appBuildId"
Write-Output "Project Remnants present: $($report.remnants.present)"
Write-Output "Java agent configured: $($report.agent.configured)"

