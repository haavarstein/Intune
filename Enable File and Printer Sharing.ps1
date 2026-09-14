# Run elevated. Ethernet: enable File and Printer Sharing + firewall.
# Wi-Fi* / Bluetooth*: disable File and Printer Sharing.
# Bluetooth*: configure, then disable the adapter.
# All: keep Client + IPv4, disable extras and NetBIOS over TCP/IP.

$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'

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

$adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    $_.HardwareInterface -eq $true -or
    $_.Name -like 'Ethernet*' -or
    $_.Name -like 'Wi-Fi*' -or
    $_.Name -like 'WiFi*' -or
    $_.Name -like 'Bluetooth*'
}

if (-not $adapters) {
    Write-Host 'No Ethernet / Wi-Fi / Bluetooth / physical adapters found.' -ForegroundColor Yellow
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue
}

$ethernet = $adapters | Where-Object {
    $_.Name -notlike 'Wi-Fi*' -and
    $_.Name -notlike 'WiFi*' -and
    $_.Name -notlike 'Bluetooth*'
}

Write-Host "`n=== BEFORE ===" -ForegroundColor Cyan
Get-NetAdapterBinding -Name $adapters.Name -ErrorAction SilentlyContinue |
    Where-Object { $_.ComponentID -in (@('ms_server') + $enableIds + $disableIds) } |
    Select-Object Name, DisplayName, ComponentID, Enabled |
    Format-Table -AutoSize

Write-Host "NetBIOS (WINS) before:" -ForegroundColor Cyan
Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
    Where-Object { $_.SettingID -in $adapters.InterfaceGuid } |
    Select-Object Description, TcpipNetbiosOptions |
    Format-Table -AutoSize

foreach ($nic in $adapters) {
    $isBluetooth = ($nic.Name -like 'Bluetooth*')
    $disableShare = (
        $nic.Name -like 'Wi-Fi*' -or
        $nic.Name -like 'WiFi*' -or
        $isBluetooth
    )

    if ($isBluetooth) { $kind = 'Bluetooth' }
    elseif ($disableShare) { $kind = 'Wi-Fi' }
    else { $kind = 'Ethernet' }

    Write-Host "`nAdapter: $($nic.Name) [$kind]" -ForegroundColor Cyan

    $bindings = @(Get-NetAdapterBinding -Name $nic.Name -AllBindings -ErrorAction SilentlyContinue)

    if (-not $disableShare) {
        $serverBinding = $bindings | Where-Object { $_.ComponentID -eq 'ms_server' }
        if (-not $serverBinding) {
            Write-Host "  ms_server not present — installing..." -ForegroundColor Yellow
            netcfg.exe -c s -i ms_server 2>$null | Out-Null
            $bindings = @(Get-NetAdapterBinding -Name $nic.Name -AllBindings -ErrorAction SilentlyContinue)
        }
        Enable-NetAdapterBinding -Name $nic.Name -ComponentID ms_server -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  ENABLED  ms_server"
    } else {
        $b = $bindings | Where-Object { $_.ComponentID -eq 'ms_server' }
        if ($b -and $b.Enabled) {
            Disable-NetAdapterBinding -Name $nic.Name -ComponentID ms_server -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  DISABLED ms_server"
        }
    }

    foreach ($id in $enableIds) {
        $b = $bindings | Where-Object { $_.ComponentID -eq $id }
        if ($b) {
            Enable-NetAdapterBinding -Name $nic.Name -ComponentID $id -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  ENABLED  $id"
        }
    }

    foreach ($id in $disableIds) {
        $b = $bindings | Where-Object { $_.ComponentID -eq $id }
        if ($b -and $b.Enabled) {
            Disable-NetAdapterBinding -Name $nic.Name -ComponentID $id -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  DISABLED $id"
        }
    }

    $guid = $nic.InterfaceGuid.ToString().ToUpper()
    $nbPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_$guid"
    if (Test-Path $nbPath) {
        Set-ItemProperty -Path $nbPath -Name NetbiosOptions -Value 2 -Type DWord -ErrorAction SilentlyContinue
        Write-Host "  DISABLED NetBIOS over TCP/IP (NetbiosOptions=2)"
    }

    if ($isBluetooth) {
        Disable-NetAdapter -Name $nic.Name -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  DISABLED adapter $($nic.Name)"
    }
}

Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters' `
    -Name EnableLMHOSTS -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Host "`nLMHOSTS lookup disabled."

if ($ethernet) {
    Write-Host "`nEnabling File and Printer Sharing firewall rules (Domain/Private)..."
    Set-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -Enabled True -Profile Domain,Private -ErrorAction SilentlyContinue
    netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes 2>$null | Out-Null

    Set-Service -Name LanmanServer -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name LanmanServer -ErrorAction SilentlyContinue
    Write-Host "LanmanServer status: $((Get-Service LanmanServer -ErrorAction SilentlyContinue).Status)"
}

Write-Host "`n=== AFTER ===" -ForegroundColor Cyan
Get-NetAdapterBinding -Name $adapters.Name -ErrorAction SilentlyContinue |
    Where-Object { $_.ComponentID -in (@('ms_server') + $enableIds + $disableIds) } |
    Select-Object Name, DisplayName, ComponentID, Enabled |
    Format-Table -AutoSize

Write-Host "NetBIOS (WINS) after:" -ForegroundColor Cyan
Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
    Where-Object { $_.SettingID -in $adapters.InterfaceGuid } |
    Select-Object Description, TcpipNetbiosOptions |
    Format-Table -AutoSize

Write-Host "`nAdapter status:" -ForegroundColor Cyan
$adapters | Select-Object Name, Status, AdminStatus, InterfaceDescription | Format-Table -AutoSize

Write-Host "TcpipNetbiosOptions: 0=Default(DHCP)  1=Enabled  2=Disabled"
