function Test-DuoscenePrivateIPv4 {
    param([string]$Address)
    if ($Address -notmatch '^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$') { return $false }
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$parsed)) { return $false }
    $bytes = $parsed.GetAddressBytes()
    return $bytes.Length -eq 4 -and ($bytes[0] -eq 10 -or ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31))
}

function Select-DuosceneLanInterface {
    param([object[]]$Candidates, [string]$Address, [string]$InterfaceAlias)
    $available = @($Candidates | Where-Object {
        $_.Physical -and $_.Up -and $_.Gateway -and (Test-DuoscenePrivateIPv4 $_.Address) -and
        (-not $Address -or $_.Address -eq $Address) -and (-not $InterfaceAlias -or $_.InterfaceAlias -eq $InterfaceAlias)
    })
    if ($available.Count -ne 1) { throw 'Select one connected private LAN interface using -Address or -InterfaceAlias.' }
    return $available[0]
}

function Get-DuosceneLanInterface {
    param([string]$Address, [string]$InterfaceAlias)
    $candidates = foreach ($configuration in Get-NetIPConfiguration) {
        foreach ($ip in $configuration.IPv4Address) {
            [pscustomobject]@{
                Address = $ip.IPAddress
                PrefixLength = $ip.PrefixLength
                InterfaceAlias = $configuration.InterfaceAlias
                InterfaceIndex = $configuration.InterfaceIndex
                Physical = [bool]$configuration.NetAdapter.HardwareInterface
                Up = $configuration.NetAdapter.Status -eq 'Up'
                Gateway = [bool]$configuration.IPv4DefaultGateway
            }
        }
    }
    return Select-DuosceneLanInterface -Candidates $candidates -Address $Address -InterfaceAlias $InterfaceAlias
}
