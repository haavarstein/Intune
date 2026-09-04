# Detection Script Only
# Remediation script: Enable & Activate Ultimate Performance + Custom Logging
# Also sets PlatformAoAcOverride = 0 for Modern Standby (S0) laptops

$logPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$logFile = "$logPath\UltimatePowerPlan_Remediation.log"

# Ensure log directory exists (SYSTEM context should have access)
if (-not (Test-Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}

# Start full transcript logging (appends to file + visible in Intune logs)
Start-Transcript -Path $logFile -Append -Force -IncludeInvocationHeader

Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting Ultimate Performance activation remediation"

$ultimateHiddenGUID = "e9a42b02-d5df-448d-aa00-03f14749eb61"
$activeScheme = ""
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
$regName = "PlatformAoAcOverride"
$regValue = 0

try {
    # --- Modern Standby (S0) override ---
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Checking registry value $regPath\$regName"

    if (-not (Test-Path $regPath)) {
        throw "Registry path not found: $regPath"
    }

    $currentReg = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue

    if ($null -eq $currentReg) {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $regName not present - creating DWORD = $regValue"
        New-ItemProperty -Path $regPath -Name $regName -PropertyType DWord -Value $regValue -Force | Out-Null
    }
    elseif ([int]$currentReg.$regName -ne $regValue) {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $regName currently = $($currentReg.$regName) - updating to $regValue"
        Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Type DWord -Force
    }
    else {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $regName already set to $regValue"
    }

    $verifyReg = (Get-ItemProperty -Path $regPath -Name $regName).$regName
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Verified $regName = $verifyReg"
    if ([int]$verifyReg -ne $regValue) {
        throw "Failed to set $regName to $regValue"
    }

    # --- Ultimate Performance plan ---
    # Check if Ultimate is already listed
    $listOutput = powercfg /list
    $existingUltimate = $listOutput | Where-Object { $_ -match $ultimateHiddenGUID }

    if ($existingUltimate) {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Ultimate Performance plan already exists (GUID found in list)."
        $activeScheme = $ultimateHiddenGUID
    } else {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Ultimate Performance not found - duplicating scheme..."
        $duplicateOutput = powercfg -duplicatescheme $ultimateHiddenGUID
        # Output example: "Power Scheme GUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  (Ultimate Performance)"
        $newGUIDLine = $duplicateOutput | Where-Object { $_ -match "GUID:" }
        if ($newGUIDLine -match "([0-9a-f\-]{36})") {
            $activeScheme = $matches[1]
            Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Successfully duplicated. New GUID: $activeScheme"
        } else {
            throw "Failed to parse new GUID from duplicatescheme output."
        }
    }

    # Set as active
    if ($activeScheme) {
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Setting active power plan to: $activeScheme"
        $setResult = powercfg -setactive $activeScheme
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] powercfg setactive result: $setResult"

        # Quick verification
        $current = powercfg /getactivescheme
        Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Current active scheme: $current"
        if ($current -match $activeScheme) {
            Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] SUCCESS: Ultimate Performance is now active."
        } else {
            throw "Active scheme verification failed."
        }
    }

} catch {
    Write-Error "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR during remediation: $_"
    Stop-Transcript
    exit 1  # Signal failure → Intune will report non-compliant / retry possible
}

# End transcript (also flushes to file)
Stop-Transcript

# Exit success → Intune marks remediation as successful
Write-Output "Ultimate Performance Active"
exit 0
