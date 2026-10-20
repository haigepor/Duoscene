param([int]$Port = 7357)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mobile-env.ps1')
Set-Location (Join-Path $PSScriptRoot '../apps/mobile')
# 独立开发入口；仅本机访问，不启动移动端的真实会话。
flutter run -d web-server -t lib/main_preview.dart --web-hostname 127.0.0.1 --web-port $Port --dart-define=DUOSCENE_STYLE_PREVIEW=true
