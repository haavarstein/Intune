# Run elevated. Ethernet: enable File and Printer Sharing + firewall.
# Wi-Fi*: disable File and Printer Sharing.
# Both: keep Client + IPv4, disable extras and NetBIOS over TCP/IP.

$ErrorActionPreference = 'SilentlyContinue'

$enableIds = @(
    'ms_msclient', # Client for Microsoft Networks
    'ms_tcpip'     # IPv4
)

$disableIds = @(
    'ms_tcpip6',   # IPv6
    'ms_pacer',    # QoS Packet Scheduler
    'ms_lldp',     # Microsoft LLDP Protocol Driver
    'ms_rspndr',   # Link-Layer Topology Discovery Responder
    'ms_lltdio',   # Link-Layer Topology Discovery Mapper I/O Driver
    'ms_implat',   # Microsoft Network Adapter Multiplexor Protocol
    'npcap'        # Npcap
)

$adapters = Get-NetAdapter | Where-Object {
    $_.HardwareInterface -eq $true -or
    $_.Name -like 'Ethernet*' -or
    $_.Name -like 'Wi-Fi*' -or
    $_.Name -like 'WiFi*'
}

if (-not $adapters) {
    Write-Host 'No Ethernet / Wi-Fi / physical adapters found.' -ForegroundColor Yellow
    $adapters = Get-NetAdapter
}

$ethernet = $adapters | Where-Object { $_.Name -notlike 'Wi-Fi*' -and $_.Name -notlike 'WiFi*' }
$wifi     = $adapters | Where-Object { $_.Name -like 'Wi-Fi*' -or $_.Name -like 'WiFi*' }

Write-Host "`n=== BEFORE ===" -ForegroundColor Cyan
Get-NetAdapterBinding -Name $adapters.Name |
    Where-Object { $_.ComponentID -in (@('ms_server') + $enableIds + $disableIds) } |
    Select-Object Name, DisplayName, ComponentID, Enabled |
    Format-Table -AutoSize

Write-Host "NetBIOS (WINS) before:" -ForegroundColor Cyan
Get-CimInstance Win32_NetworkAdapterConfiguration |
    Where-Object { $_.SettingID -in $adapters.InterfaceGuid } |
    Select-Object Description, TcpipNetbiosOptions |
    Format-Table -AutoSize

foreach ($nic in $adapters) {
    $isWifi = ($nic.Name -like 'Wi-Fi*' -or $nic.Name -like 'WiFi*')
    Write-Host "`nAdapter: $($nic.Name)$(if ($isWifi) {' [Wi-Fi]'} else {' [Ethernet]'})" -ForegroundColor Cyan

    if (-not $isWifi) {
        $serverBinding = Get-NetAdapterBinding -Name $nic.Name -ComponentID ms_server -AllBindings
        if (-not $serverBinding) {
            Write-Host "  ms_server not present — installing..." -ForegroundColor Yellow
            netcfg.exe -c s -i ms_server | Out-Null
        }
        Enable-NetAdapterBinding -Name $nic.Name -ComponentID ms_server
        Write-Host "  ENABLED  ms_server"
    } else {
        $b = Get-NetAdapterBinding -Name $nic.Name -ComponentID ms_server -AllBindings
        if ($b -and $b.Enabled) {
            Disable-NetAdapterBinding -Name $nic.Name -ComponentID ms_server
            Write-Host "  DISABLED ms_server"
        }
    }

    foreach ($id in $enableIds) {
        $b = Get-NetAdapterBinding -Name $nic.Name -ComponentID $id -AllBindings
        if ($b) {
            Enable-NetAdapterBinding -Name $nic.Name -ComponentID $id
            Write-Host "  ENABLED  $id"
        }
    }

    foreach ($id in $disableIds) {
        $b = Get-NetAdapterBinding -Name $nic.Name -ComponentID $id -AllBindings
        if ($b -and $b.Enabled) {
            Disable-NetAdapterBinding -Name $nic.Name -ComponentID $id
            Write-Host "  DISABLED $id"
        }
    }

    $guid = $nic.InterfaceGuid.ToString().ToUpper()
    $nbPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_$guid"
    if (Test-Path $nbPath) {
        Set-ItemProperty -Path $nbPath -Name NetbiosOptions -Value 2 -Type DWord
        Write-Host "  DISABLED NetBIOS over TCP/IP (NetbiosOptions=2)"
    } else {
        Write-Host "  NetBIOS registry key not found for $guid" -ForegroundColor Yellow
    }
}

Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' `
    -Name EnableLMHOSTS -Value 0 -Type DWord
Write-Host "`nLMHOSTS lookup disabled."

if ($ethernet) {
    Write-Host "`nEnabling File and Printer Sharing firewall rules (Domain/Private)..."
    Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -Profile Domain,Private
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes | Out-Null

    Set-Service -Name LanmanServer -StartupType Automatic
    Start-Service -Name LanmanServer
    Write-Host "LanmanServer status: $((Get-Service LanmanServer).Status)"
}

Write-Host "`n=== AFTER ===" -ForegroundColor Cyan
Get-NetAdapterBinding -Name $adapters.Name |
    Where-Object { $_.ComponentID -in (@('ms_server') + $enableIds + $disableIds) } |
    Select-Object Name, DisplayName, ComponentID, Enabled |
    Format-Table -AutoSize

Write-Host "NetBIOS (WINS) after:" -ForegroundColor Cyan
Get-CimInstance Win32_NetworkAdapterConfiguration |
    Where-Object { $_.SettingID -in $adapters.InterfaceGuid } |
    Select-Object Description, TcpipNetbiosOptions |
    Format-Table -AutoSize

Write-Host "TcpipNetbiosOptions: 0=Default(DHCP)  1=Enabled  2=Disabled"
