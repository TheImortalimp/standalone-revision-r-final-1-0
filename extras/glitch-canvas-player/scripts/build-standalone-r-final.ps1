param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$OutputDir = "extras\glitch-canvas-player\dist",
    [int]$TargetMaxMb = 75,
    [int]$HardFailMb = 100
)

$ErrorActionPreference = "Stop"

$webUiRoot = Join-Path $RepoRoot "extras\glitch-canvas-player\webui"
if (-not (Test-Path (Join-Path $webUiRoot "glitch-canvas-youtube.html"))) {
    throw "Missing web UI root: $webUiRoot"
}

$iexpressPath = Join-Path $env:WINDIR "System32\iexpress.exe"
if (-not (Test-Path $iexpressPath)) {
    throw "IExpress not found at $iexpressPath"
}

$resolvedOutputDir = Join-Path $RepoRoot $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$zipArtifactName = "standalone-revision-R-final-1.0-package.zip"
$zipArtifactPath = Join-Path $resolvedOutputDir $zipArtifactName
$exeArtifactName = "standalone-revision-R-final-1.0-installer.exe"
$exeArtifactPath = Join-Path $resolvedOutputDir $exeArtifactName

$stagingRoot = Join-Path $env:TEMP ("srf1_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null

try {
    $payloadRoot = Join-Path $stagingRoot "payload"
    New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null

    Copy-Item -Path $webUiRoot -Destination (Join-Path $payloadRoot "webui") -Recurse -Force

    $authorsPath = Join-Path $RepoRoot "AUTHORS.TXT"
    if (Test-Path $authorsPath) {
        Copy-Item -Path $authorsPath -Destination (Join-Path $payloadRoot "AUTHORS.TXT") -Force
    }

    $manifest = @{
        name = "standalone revision-R final 1.0"
        baseline = "r2"
        subtleLayers = @("r1", "r3", "r4")
        generatedAtUtc = [DateTime]::UtcNow.ToString("o")
        targetMaxMb = $TargetMaxMb
        hardFailMb = $HardFailMb
    } | ConvertTo-Json -Depth 4

    Set-Content -Path (Join-Path $payloadRoot "build-manifest.json") -Value $manifest -Encoding UTF8

    $installScriptPath = Join-Path $payloadRoot "install.ps1"
    $installScript = @'
param(
    [string]$InstallRoot = "$env:USERPROFILE\Desktop\standalone-revision-R-final-1.0"
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

$sourceRoot = Split-Path -Parent $PSCommandPath
$files = @(
    "AUTHORS.TXT",
    "build-manifest.json"
)

foreach ($file in $files) {
    $src = Join-Path $sourceRoot $file
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $InstallRoot $file) -Force
    }
}

$webuiTarget = Join-Path $InstallRoot "webui"
New-Item -ItemType Directory -Force -Path $webuiTarget | Out-Null
Copy-Item -Path (Join-Path $sourceRoot "webui\*") -Destination $webuiTarget -Recurse -Force

$launcher = Join-Path $InstallRoot "Launch-Standalone-Revision-R-Final.cmd"
$launcherLines = @(
    "@echo off",
    "setlocal",
    "set BASE=%~dp0",
    "set PAGE=%BASE%webui\glitch-canvas-youtube.html",
    "if exist \"C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe\" (",
    "  start \"\" \"C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe\" \"%PAGE%\"",
    "  exit /b 0",
    ")",
    "if exist \"C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe\" (",
    "  start \"\" \"C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe\" \"%PAGE%\"",
    "  exit /b 0",
    ")",
    "start \"\" \"%PAGE%\""
)
Set-Content -Path $launcher -Value $launcherLines -Encoding ASCII

Write-Host "Installed to: $InstallRoot"
'@
    Set-Content -Path $installScriptPath -Value $installScript -Encoding UTF8

    Compress-Archive -Path (Join-Path $payloadRoot "*") -DestinationPath $zipArtifactPath -Force

    $zipSizeBytes = (Get-Item $zipArtifactPath).Length
    $zipSizeMb = [Math]::Round($zipSizeBytes / 1MB, 2)

    $sourceFiles = @(
        "AUTHORS.TXT",
        "build-manifest.json",
        "install.ps1",
        "webui\glitch-canvas-youtube.html",
        "webui\glitch-canvas-youtube.css",
        "webui\revision-r-final-engine.js"
    )

    $sourceCabinetRoot = Join-Path $stagingRoot "payload"
    $sedPath = Join-Path $stagingRoot "build-installer.sed"
    $targetEscaped = $exeArtifactPath -replace '\\', '\\\\'
    $sourceEscaped = $sourceCabinetRoot -replace '\\', '\\\\'

    $sedLines = @(
        "[Version]",
        "Class=IEXPRESS",
        "SEDVersion=3",
        "",
        "[Options]",
        "PackagePurpose=InstallApp",
        "ShowInstallProgramWindow=0",
        "HideExtractAnimation=1",
        "UseLongFileName=1",
        "InsideCompressed=0",
        "CAB_FixedSize=0",
        "CAB_ResvCodeSigning=0",
        "RebootMode=N",
        "InstallPrompt=",
        "DisplayLicense=",
        "FinishMessage=Standalone Revision-R Final 1.0 extracted.",
        "TargetName=$targetEscaped",
        "FriendlyName=Standalone Revision-R Final 1.0 Installer",
        "AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1",
        "PostInstallCmd=<None>",
        "AdminQuietInstCmd=",
        "UserQuietInstCmd=",
        "SourceFiles=SourceFiles",
        "",
        "[Strings]"
    )

    for ($index = 0; $index -lt $sourceFiles.Count; $index++) {
        $key = "FILE$index"
        $value = $sourceFiles[$index]
        $sedLines += "$key=$value"
    }

    $sedLines += ""
    $sedLines += "[SourceFiles]"
    $sedLines += "SourceFiles0=$sourceEscaped"
    $sedLines += ""
    $sedLines += "[SourceFiles0]"

    for ($index = 0; $index -lt $sourceFiles.Count; $index++) {
        $key = "FILE$index"
        $sedLines += "%$key%="
    }

    Set-Content -Path $sedPath -Value $sedLines -Encoding ASCII

    & $iexpressPath /N /Q $sedPath | Out-Null
    if (-not (Test-Path $exeArtifactPath)) {
        throw "Installer EXE was not created: $exeArtifactPath"
    }

    $exeSizeBytes = (Get-Item $exeArtifactPath).Length
    $exeSizeMb = [Math]::Round($exeSizeBytes / 1MB, 2)

    Write-Host "ZIP artifact: $zipArtifactPath"
    Write-Host "ZIP size: $zipSizeMb MB"
    Write-Host "EXE artifact: $exeArtifactPath"
    Write-Host "EXE size: $exeSizeMb MB"

    if ($zipSizeMb -gt $HardFailMb) {
        throw "ZIP package is $zipSizeMb MB, above hard fail limit of $HardFailMb MB."
    }

    if ($zipSizeMb -gt $TargetMaxMb) {
        throw "ZIP package is $zipSizeMb MB, above target limit of $TargetMaxMb MB."
    }

    if ($exeSizeMb -gt $HardFailMb) {
        throw "EXE package is $exeSizeMb MB, above hard fail limit of $HardFailMb MB."
    }

    if ($exeSizeMb -gt $TargetMaxMb) {
        throw "EXE package is $exeSizeMb MB, above target limit of $TargetMaxMb MB."
    }

    Write-Host "Build successful within cap ($TargetMaxMb MB) for ZIP and EXE."
}
finally {
    if (Test-Path $stagingRoot) {
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
