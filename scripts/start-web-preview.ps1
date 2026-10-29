param([int]$Port = 7357)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mobile-env.ps1')
Set-Location (Join-Path $PSScriptRoot '../apps/mobile')
# 对齐 Playra：渲染资源由本地 SDK 提供，预览首帧不再等待外部 CanvasKit CDN。
flutter run -d web-server -t web/main.dart --no-web-resources-cdn --web-hostname 127.0.0.1 --web-port $Port --dart-define=DUOSCENE_STYLE_PREVIEW=true
