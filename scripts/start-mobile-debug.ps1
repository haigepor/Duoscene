param(
    [string]$Device = '127.0.0.1:5557'
)

$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'mobile-env.ps1')

if ($Device -match '^127\.0\.0\.1:\d+$') {
    & "$env:ANDROID_HOME\platform-tools\adb.exe" connect $Device
    if ($LASTEXITCODE -ne 0) { throw 'Unable to connect to the emulator.' }
}
& "$env:ANDROID_HOME\platform-tools\adb.exe" -s $Device get-state
if ($LASTEXITCODE -ne 0) { throw 'Start the Android emulator before running this script.' }

# 通过 ADB 回环访问本机服务，兼容雷电、官方模拟器与 USB 手机。
foreach ($port in @(3000, 3478)) {
    & "$env:ANDROID_HOME\platform-tools\adb.exe" -s $Device reverse "tcp:$port" "tcp:$port"
    if ($LASTEXITCODE -ne 0) { throw "ADB reverse failed for port $port." }
}

Push-Location (Join-Path $workspace 'apps/mobile')
try {
    Write-Output 'Keep this terminal open: r = hot reload, R = hot restart, d = detach, q = quit.'
    flutter run --debug -d $Device -t lib/main.dart --dart-define=API_BASE_URL=http://127.0.0.1:3000
    if ($LASTEXITCODE -ne 0) { throw 'Flutter debug session exited with an error.' }
} finally {
    Pop-Location
}
