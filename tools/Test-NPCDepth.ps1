[CmdletBinding()]
param(
    [string]$ProjectZomboidPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-ProjectZomboidInstall {
    param([string]$ExplicitPath)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates.Add($ExplicitPath)
    }
    foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
        $candidates.Add((Join-Path $drive.Root "Steam\steamapps\common\ProjectZomboid"))
        $candidates.Add((Join-Path $drive.Root "SteamLibrary\steamapps\common\ProjectZomboid"))
    }
    foreach ($candidate in $candidates) {
        $full = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path -LiteralPath (Join-Path $full "projectzomboid.jar") -PathType Leaf) {
            return $full
        }
    }
    throw "Could not locate Project Zomboid. Pass -ProjectZomboidPath explicitly."
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modRoot = Join-Path $repositoryRoot "mod\NPCDepth"
$manifestPath = Join-Path $modRoot "42\mod.info"
$luaRoot = Join-Path $modRoot "common\media\lua"

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing Build 42 manifest: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw
foreach ($required in @("id=NPCDepth", "modversion=0.1.0-dev", "versionMin=42.20.0")) {
    if (-not $manifest.Contains($required)) {
        throw "Manifest is missing required entry: $required"
    }
}

# Full-line comments are stripped before scanning so a module may describe the
# globals it is forbidden to call without tripping its own guard.
function Get-LuaCodeLines {
    param([string]$Path)

    $lines = @(Get-Content -LiteralPath $Path)
    $code = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*--') {
            continue
        }
        $code.Add([pscustomobject]@{ Number = $index + 1; Text = $lines[$index] })
    }
    return $code
}

function Assert-LuaPatternAbsent {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )

    foreach ($line in Get-LuaCodeLines -Path $Path) {
        if ($line.Text -match $Pattern) {
            throw ($Message + ": " + $Path + ":" + $line.Number)
        }
    }
}

$luaFiles = @(Get-ChildItem -LiteralPath $luaRoot -Filter *.lua -File -Recurse)
$globalStorePath = [System.IO.Path]::GetFullPath((Join-Path $luaRoot "client\NPCDepth\GlobalStore.lua"))

if (-not (Test-Path -LiteralPath $globalStorePath -PathType Leaf)) {
    throw "Missing GlobalStore module: $globalStorePath"
}

# ModData is the persistence seam: exactly one module may touch it.
foreach ($file in $luaFiles) {
    Assert-LuaPatternAbsent -Path $file.FullName -Pattern '\bgetPlayer\b' -Message "getPlayer() is not part of the proven surface yet"
    if ([System.IO.Path]::GetFullPath($file.FullName) -ne $globalStorePath) {
        Assert-LuaPatternAbsent -Path $file.FullName -Pattern '\bModData\b' -Message "ModData access escaped GlobalStore.lua"
    }
}

# The shared tree is the pure domain layer: plain tables in, plain tables out.
$sharedRoot = Join-Path $luaRoot "shared"
foreach ($file in @(Get-ChildItem -LiteralPath $sharedRoot -Filter *.lua -File -Recurse)) {
    Assert-LuaPatternAbsent -Path $file.FullName -Pattern '\b(ModData|getPlayer|Events|getActivatedMods|getModInfoByID|getGameVersion)\b|\bnpcfw\w*' -Message "Pure domain module referenced a Project Zomboid global"
    Assert-LuaPatternAbsent -Path $file.FullName -Pattern '\b(os|io)\.' -Message "Pure domain module referenced os/io"
    Assert-LuaPatternAbsent -Path $file.FullName -Pattern 'math\.random' -Message "Pure domain module used math.random"
}

$upstreamReads = @($luaFiles | Select-String -Pattern '\b(getActivatedMods|getModInfoByID)\b|pairs\(_G\)')
$adapterPath = [System.IO.Path]::GetFullPath((Join-Path $luaRoot "client\NPCDepth\ProjectRemnantsAdapter.lua"))
foreach ($read in $upstreamReads) {
    if ([System.IO.Path]::GetFullPath($read.Path) -ne $adapterPath) {
        throw "Upstream observation escaped ProjectRemnantsAdapter.lua: $($read.Path):$($read.LineNumber)"
    }
}

$gamePath = Find-ProjectZomboidInstall -ExplicitPath $ProjectZomboidPath
$projectZomboidJar = Join-Path $gamePath "projectzomboid.jar"
$gameJava = Join-Path $gamePath "jre64\bin\java.exe"
$javaSource = Join-Path $PSScriptRoot "LuaSyntaxCheck.java"
$runtimeJavaSource = Join-Path $PSScriptRoot "LuaRuntimeCheck.java"
$buildRoot = Join-Path ([System.IO.Path]::GetTempPath()) "NPCDepth-LuaCheck-$([Guid]::NewGuid().ToString('N'))"
$buildFull = [System.IO.Path]::GetFullPath($buildRoot)
$tempFull = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

if (-not $buildFull.StartsWith($tempFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing temporary build path outside system temp: $buildFull"
}

New-Item -ItemType Directory -Path $buildFull | Out-Null
try {
    & javac -encoding UTF-8 -d $buildFull $javaSource $runtimeJavaSource
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to compile LuaSyntaxCheck.java"
    }

    if (-not (Test-Path -LiteralPath $gameJava -PathType Leaf)) {
        throw "Project Zomboid's Java runtime is missing: $gameJava"
    }

    & $gameJava -classpath "$buildFull;$projectZomboidJar" LuaSyntaxCheck $luaRoot
    if ($LASTEXITCODE -ne 0) {
        throw "One or more Lua files failed Project Zomboid Kahlua compilation."
    }

    $runtimeFiles = @(
        (Join-Path $luaRoot "shared\NPCDepth\Config.lua"),
        (Join-Path $luaRoot "shared\NPCDepth\State.lua"),
        (Join-Path $luaRoot "shared\NPCDepth\Migrations.lua"),
        (Join-Path $luaRoot "client\NPCDepth\ProjectRemnantsAdapter.lua"),
        (Join-Path $luaRoot "client\NPCDepth\CompatibilityProbe.lua"),
        (Join-Path $luaRoot "client\NPCDepth\GlobalStore.lua"),
        (Join-Path $luaRoot "client\NPCDepth\Debug.lua"),
        (Join-Path $luaRoot "client\NPCDepth\Runtime.lua"),
        (Join-Path $repositoryRoot "tests\fixtures\iteration_a_probe.lua"),
        (Join-Path $repositoryRoot "tests\fixtures\iteration_b_state.lua")
    )

    Push-Location $gamePath
    try {
        & $gameJava -classpath "$buildFull;$projectZomboidJar" LuaRuntimeCheck @runtimeFiles
        if ($LASTEXITCODE -ne 0) {
            throw "NPCDepth runtime fixtures failed under Project Zomboid Kahlua."
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    if (Test-Path -LiteralPath $buildFull) {
        Remove-Item -LiteralPath $buildFull -Recurse -Force
    }
}

Write-Output "PASS manifest contract"
Write-Output "PASS ModData persistence boundary"
Write-Output "PASS pure domain layer boundary"
Write-Output "PASS Project Remnants observation boundary"
Write-Output "PASS Kahlua syntax compilation"
Write-Output "PASS Kahlua compatibility-probe runtime fixtures"
Write-Output "PASS Kahlua schema/migration/sentinel runtime fixtures"
