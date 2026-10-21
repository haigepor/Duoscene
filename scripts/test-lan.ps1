$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lan-common.ps1')
foreach ($address in @('192.168.0.4', '10.0.0.2', '172.16.0.1', '172.31.255.254')) {
    if (-not (Test-DuoscenePrivateIPv4 $address)) { throw "Expected private address: $address" }
}
foreach ($address in @('8.8.8.8', '172.32.0.1', '169.254.1.1', '127.0.0.1', '0.0.0.0', '192.168.999.1', '192.168.0.4.evil', '192.168.000.4')) {
    if (Test-DuoscenePrivateIPv4 $address) { throw "Rejected address accepted: $address" }
}
$wifi = [pscustomobject]@{ Address = '192.168.0.4'; InterfaceAlias = 'WLAN'; Physical = $true; Up = $true; Gateway = $true }
$virtual = [pscustomobject]@{ Address = '172.20.0.1'; InterfaceAlias = 'vEthernet'; Physical = $false; Up = $true; Gateway = $true }
if ((Select-DuosceneLanInterface @($wifi, $virtual)).Address -ne $wifi.Address) { throw 'Virtual adapter selected' }
$other = [pscustomobject]@{ Address = '10.1.0.2'; InterfaceAlias = 'Ethernet'; Physical = $true; Up = $true; Gateway = $true }
$failed = $false
try { Select-DuosceneLanInterface @($wifi, $other) | Out-Null } catch { $failed = $true }
if (-not $failed) { throw 'Ambiguous network selection must fail' }
if ((Select-DuosceneLanInterface @($wifi, $other) -Address '10.1.0.2').InterfaceAlias -ne 'Ethernet') { throw 'Explicit selection failed' }
Write-Output 'PASS: private IPv4 boundaries, physical adapter selection, ambiguity guard and explicit override'
