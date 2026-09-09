# Run elevated. Enables File and Printer Sharing binding + firewall,
# keeps Client for Microsoft Networks and IPv4, disables common extras.

$ErrorActionPreference = 'SilentlyContinue'

$enableIds = @(
    'ms_server',   # File and Printer Sharing for Microsoft Networks
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
    'vms_pp',      # Hyper-V Extensible Virtual Switch
    'npcap'        # Npcap
)

$adapters = Get-NetAdapter | Where-Object {
    $_.HardwareInterface -eq $true -or $_.Name -like 'Ethernet*'
}

if (-not $adapters) {
    Write-Host 'No Ethernet / physical adapters found.' -ForegroundColor Yellow
    $adapters = Get-NetAdapter
}

Write-Host "`n=== BEFORE ===" -ForegroundColor Cyan
Get-NetAdapterBinding -Name $adapters.Name |
    Where-Object { $_.ComponentID -in ($enableIds + $disableIds) } |
    Select-Object Name, DisplayName, ComponentID, Enabled |
    Format-Table -AutoSize

foreach ($nic in $adapters) {
    Write-Host "`nAdapter: $($nic.Name)" -ForegroundColor Cyan

    # If File and Printer Sharing is missing from the list entirely, install it
    $serverBinding = Get-NetAdapterBinding -Name $nic.Name -ComponentID ms_server -AllBindings
    if (-not $serverBinding) {
        Write-Host "  ms_server not present — installing..." -ForegroundColor Yellow
        netcfg.exe -c s -i ms_server | Out-Null
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
}

# Binding checkbox is not enough — firewall + Server service must be on
Write-Host "`nEnabling File and Printer Sharing firewall rules (Domain/Private)..."
Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -Profile Domain,Private
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes | Out-Null

Set-Service -Name LanmanServer -StartupType Automatic
Start-Service -Name LanmanServer
Write-Host "LanmanServer status: $((Get-Service LanmanServer).Status)"

Write-Host "`n=== AFTER ===" -ForegroundColor Cyan
Get-NetAdapterBinding -Name $adapters.Name |
    Where-Object { $_.ComponentID -in ($enableIds + $disableIds) } |
    Select-Object Name, DisplayName, ComponentID, Enabled |
    Format-Table -AutoSize
