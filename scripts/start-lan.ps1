#Requires -Version 7.4
param([string]$Address, [string]$InterfaceAlias)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'lan-common.ps1')
$network = Get-DuosceneLanInterface -Address $Address -InterfaceAlias $InterfaceAlias
$node = Join-Path $project '.local/tools/node-v24.22.0-win-x64/node.exe'
$starter = Join-Path $project '.local/test-account/start.ps1'
if (-not (Test-Path -LiteralPath $node) -or -not (Test-Path -LiteralPath $starter)) { throw 'Run the local test-account setup before starting the LAN service.' }
$admin = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this LAN startup script as administrator to configure its narrowly scoped firewall rule.' }
$ruleName = 'Duoscene-LAN-API-3000'
$group = 'Duoscene local development'
$existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
if ($existing -and $existing.Group -ne $group) { throw 'Firewall rule name is already owned by another configuration.' }
if ($existing) { Remove-NetFirewallRule -Name $ruleName }
# 即使 Wi-Fi 被标为 Public，也只允许该网卡、该本机地址的同子网访问此进程端口。
New-NetFirewallRule -Name $ruleName -DisplayName 'Duoscene LAN API 3000' -Group $group -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol TCP -LocalPort 3000 -Program $node -InterfaceAlias $network.InterfaceAlias -LocalAddress $network.Address -RemoteAddress LocalSubnet -EdgeTraversalPolicy Block | Out-Null
& $starter -BindAddress '0.0.0.0'
if (-not $?) { throw 'LAN backend startup failed.' }
$baseUrl = "http://$($network.Address):3000"
$ready = Invoke-RestMethod -Uri "$baseUrl/health/ready" -TimeoutSec 5 -NoProxy
if ($ready.data.status -ne 'ready') { throw 'API is not reachable through its LAN address.' }
$output = Join-Path $project '.local/lan'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$defines = [ordered]@{ API_BASE_URL = $baseUrl; ALLOW_LAN_HTTP = 'true' }
[IO.File]::WriteAllText((Join-Path $output 'defines.json'), (($defines | ConvertTo-Json) + "`n"), [Text.UTF8Encoding]::new($false))
$status = [ordered]@{ address = $network.Address; interfaceAlias = $network.InterfaceAlias; apiBaseUrl = $baseUrl; bind = '0.0.0.0'; port = 3000; firewallRule = $ruleName }
[IO.File]::WriteAllText((Join-Path $output 'status.json'), (($status | ConvertTo-Json) + "`n"), [Text.UTF8Encoding]::new($false))
Write-Output "局域网服务就绪：$baseUrl"
Write-Output "同一 Wi-Fi 的设备请安装 LAN 版 APK；旧的 127.0.0.1 安装包不能直接用于 Wi-Fi 登录。"
Write-Output '测试账号：test123；数据库仍仅监听本机，启动不再依赖 USB/ADB。'
