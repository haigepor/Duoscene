#Requires -Version 7.4
param([string]$Address, [string]$InterfaceAlias,
    [ValidateSet('Debug', 'Profile')][string]$Mode = 'Debug',
    [switch]$CapturePerformance)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'start-lan.ps1') -Address $Address -InterfaceAlias $InterfaceAlias
if (-not $?) { throw 'LAN service is not ready.' }
. (Join-Path $PSScriptRoot 'mobile-env.ps1')
Push-Location (Join-Path $project 'apps/mobile/android')
try {
    # 只清理打包任务的既有输出，避免增量 ZIP 留下旧 kernel 空洞；不清编译缓存。
    & .\gradlew.bat ":app:cleanPackage$Mode" --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'APK package-output cleanup failed.' }
} finally { Pop-Location }
$defines = Join-Path $project '.local/lan/defines.json'
Push-Location (Join-Path $project 'apps/mobile')
try {
    $modeName = $Mode.ToLowerInvariant()
    $flags = @('build', 'apk', "--$modeName", '--target-platform', 'android-arm64', "--dart-define-from-file=$defines")
    if ($CapturePerformance) { $flags += '--dart-define=PERF_CAPTURE=true' }
    flutter @flags
    if ($LASTEXITCODE -ne 0) { throw 'LAN APK build failed.' }
} finally { Pop-Location }
$directory = Join-Path $project 'output/android'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$suffix = if ($CapturePerformance) { '-perf' } else { '' }
$apk = Join-Path $directory "duoscene-lan-arm64-$modeName$suffix.apk"
Copy-Item -LiteralPath (Join-Path $project "apps/mobile/build/app/outputs/flutter-apk/app-$modeName.apk") -Destination $apk
$metadata = [ordered]@{ artifact = $apk; sha256 = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant(); apiBaseUrl = (Get-Content -Raw -Encoding utf8 -LiteralPath $defines | ConvertFrom-Json).API_BASE_URL; mode = $modeName; platform = 'android-arm64'; allowLanHttp = $true; performanceCapture = [bool]$CapturePerformance }
$metadataName = if ($CapturePerformance) { "lan-$modeName-perf-build-info.json" } elseif ($Mode -eq 'Debug') { 'lan-build-info.json' } else { 'lan-profile-build-info.json' }
[IO.File]::WriteAllText((Join-Path $directory $metadataName), (($metadata | ConvertTo-Json) + "`n"), [Text.UTF8Encoding]::new($false))
Write-Output "LAN 安装包：$apk"
