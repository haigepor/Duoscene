param([switch]$Restart, [string[]]$Devices = @('127.0.0.1:5557', 'emulator-5558'))
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'mobile-env.ps1')
Push-Location $workspace
try {
    $voiceFile = Join-Path $workspace '.local/voice.env'
    if (-not (Test-Path -LiteralPath $voiceFile)) {
        $secret = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(48)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        [IO.Directory]::CreateDirectory((Split-Path $voiceFile -Parent)) | Out-Null
        [IO.File]::WriteAllText($voiceFile, "TURN_SECRET=$secret`nTURN_URLS=turn:127.0.0.1:3478?transport=tcp`nTURN_RELAY_ONLY=true`n", [Text.UTF8Encoding]::new($false))
    }
    docker compose --progress quiet --env-file .local/voice.env -f infra/compose/compose.voice.local.yaml up -d
    if ($LASTEXITCODE -ne 0) { throw 'Local coturn startup failed' }
    npm run db:migrate
    if ($LASTEXITCODE -ne 0) { throw 'Local database migrations failed' }
    $listener = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($listener) {
        $recorded = @('.local/realtime-api-process.json', '.local/ui-polish-api-process.json') | ForEach-Object {
            if (Test-Path -LiteralPath $_) { (Get-Content -LiteralPath $_ -Raw -Encoding utf8 | ConvertFrom-Json).pid }
        }
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
        if (-not $Restart -or $listener.OwningProcess -notin $recorded -or $processInfo.CommandLine -notmatch 'apps[\\/]api[\\/]src[\\/]server\.ts') {
            throw 'Port 3000 is occupied. Only a recorded Duoscene process may be restarted with -Restart.'
        }
        Stop-Process -Id $listener.OwningProcess
    }
    $process = Start-Process -FilePath (Get-Command node).Source -ArgumentList @('--env-file=.env', '--env-file=.local/voice.env', 'apps/api/src/server.ts') -WorkingDirectory $workspace -WindowStyle Hidden -RedirectStandardOutput (Join-Path $workspace '.local/realtime-api.stdout.log') -RedirectStandardError (Join-Path $workspace '.local/realtime-api.stderr.log') -PassThru
    @{ pid = $process.Id; host = '127.0.0.1'; port = 3000; started = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath '.local/realtime-api-process.json' -Encoding utf8
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try { $ready = (Invoke-RestMethod 'http://127.0.0.1:3000/health/ready' -TimeoutSec 2).data.status -eq 'ready' } catch {}
        if ($ready) { break }
        Start-Sleep -Milliseconds 200
    }
    if (-not $ready) { throw 'API did not become ready; inspect .local/realtime-api.stderr.log' }
    foreach ($device in $Devices) {
        & "$env:ANDROID_SDK_ROOT/platform-tools/adb.exe" -s $device reverse tcp:3000 tcp:3000
        & "$env:ANDROID_SDK_ROOT/platform-tools/adb.exe" -s $device reverse tcp:3478 tcp:3478
        if ($LASTEXITCODE -ne 0) { throw "ADB mapping failed for $device" }
    }
    Write-Output 'Local API ready on 127.0.0.1:3000; authenticated TURN/TCP mapped to both Android clients.'
} finally { Pop-Location }
