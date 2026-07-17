param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$OutputDir = ".",
    [int]$TargetMaxMb = 75,
    [int]$HardFailMb = 100
)

$ErrorActionPreference = "Stop"

$required = @(
    "glitch-canvas-youtube.html",
    "glitch-canvas-youtube.css",
    "revision-r-final-engine.js"
)

foreach ($file in $required) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        throw "Missing required file at repo root: $file"
    }
}

$resolvedOutputDir = Join-Path $RepoRoot $OutputDir
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$artifactName = "standalone-revision-R-final-1.0-package.zip"
$artifactPath = Join-Path $resolvedOutputDir $artifactName

$stagingRoot = Join-Path $env:TEMP ("srf1_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null

try {
    $payloadRoot = Join-Path $stagingRoot "payload"
    New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null

    Copy-Item -Path (Join-Path $RepoRoot "glitch-canvas-youtube.html") -Destination (Join-Path $payloadRoot "glitch-canvas-youtube.html") -Force
    Copy-Item -Path (Join-Path $RepoRoot "glitch-canvas-youtube.css") -Destination (Join-Path $payloadRoot "glitch-canvas-youtube.css") -Force
    Copy-Item -Path (Join-Path $RepoRoot "revision-r-final-engine.js") -Destination (Join-Path $payloadRoot "revision-r-final-engine.js") -Force

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

    Compress-Archive -Path (Join-Path $payloadRoot "*") -DestinationPath $artifactPath -Force

    $sizeBytes = (Get-Item $artifactPath).Length
    $sizeMb = [Math]::Round($sizeBytes / 1MB, 2)

    Write-Host "Artifact: $artifactPath"
    Write-Host "Size: $sizeMb MB"

    if ($sizeMb -gt $HardFailMb) {
        throw "Package is $sizeMb MB, above hard fail limit of $HardFailMb MB."
    }

    if ($sizeMb -gt $TargetMaxMb) {
        throw "Package is $sizeMb MB, above target limit of $TargetMaxMb MB."
    }

    Write-Host "Build successful within cap ($TargetMaxMb MB)."
}
finally {
    if (Test-Path $stagingRoot) {
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
