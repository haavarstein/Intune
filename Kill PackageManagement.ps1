# Fix-PackageManagement.ps1
# Kills other PowerShell hosts, unloads locked modules, then reinstalls PackageManagement + PowerShellGet

#Requires -RunAsAdministrator

Write-Host "=== Current session PID: $PID ===" -ForegroundColor Cyan

# 1. Kill OTHER powershell / pwsh processes (do NOT kill this session)
$hosts = @('powershell', 'pwsh')
$others = Get-Process -Name $hosts -ErrorAction SilentlyContinue |
          Where-Object { $_.Id -ne $PID }

if ($others) {
    Write-Host "Stopping other PowerShell processes:" -ForegroundColor Yellow
    $others | Select-Object Id, ProcessName, Path | Format-Table -AutoSize
    $others | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
} else {
    Write-Host "No other powershell/pwsh processes found." -ForegroundColor Green
}

# 2. Unload the locked modules from THIS session
Remove-Module PackageManagement, PowerShellGet -Force -ErrorAction SilentlyContinue

# 3. TLS 1.2 (required for PowerShell Gallery on older Windows)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 4. Trust PSGallery
try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
} catch {
    Write-Warning "Could not set PSGallery trusted: $_"
}

# 5. NuGet provider first (Install-Module depends on it)
Write-Host "`nInstalling NuGet provider..." -ForegroundColor Cyan
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

# 6. Reinstall modules (CurrentUser is safer if AllUsers is locked)
Write-Host "`nInstalling PackageManagement..." -ForegroundColor Cyan
Install-Module -Name PackageManagement -Force -AllowClobber -Scope CurrentUser -SkipPublisherCheck

Write-Host "Installing PowerShellGet..." -ForegroundColor Cyan
Install-Module -Name PowerShellGet -Force -AllowClobber -Scope CurrentUser -SkipPublisherCheck

# 7. Verify
Write-Host "`n=== Installed versions ===" -ForegroundColor Green
Get-Module PackageManagement, PowerShellGet -ListAvailable |
    Select-Object Name, Version, ModuleBase |
    Format-Table -AutoSize

Write-Host "`nDone. Close this window and open a NEW PowerShell session before installing other modules." -ForegroundColor Green
