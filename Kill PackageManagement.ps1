# Reset-PackageManagement.ps1
# Wipe user/OneDrive copies of PackageManagement + PowerShellGet, then install clean to AllUsers
# Run from an elevated prompt. Do not delete the Windows inbox 1.0.0.1 folders.

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'
$modules = @('PackageManagement', 'PowerShellGet')

Write-Host "Session PID: $PID" -ForegroundColor Cyan

# --- 1. Kill other PowerShell hosts (keep this window) ---
Get-Process -Name powershell, pwsh -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -ne $PID } |
    ForEach-Object {
        Write-Host "Stopping $($_.ProcessName) PID $($_.Id)" -ForegroundColor Yellow
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
Start-Sleep -Seconds 2

# --- 2. Unload from this session ---
$modules | ForEach-Object {
    Remove-Module $_ -Force -ErrorAction SilentlyContinue
}

# --- 3. Uninstall every version PowerShellGet knows about ---
foreach ($name in $modules) {
    Write-Host "`nUninstalling all versions of $name ..." -ForegroundColor Cyan
    Get-InstalledModule -Name $name -AllVersions -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Host "  Uninstall-Module $($_.Name) $($_.Version)"
            Uninstall-Module -Name $_.Name -RequiredVersion $_.Version -Force -ErrorAction SilentlyContinue
        }
}

# --- 4. Delete leftover USER / OneDrive folders only ---
# Do NOT delete:
#   C:\Program Files\WindowsPowerShell\Modules\PackageManagement\1.0.0.1
#   C:\Program Files\WindowsPowerShell\Modules\PowerShellGet\1.0.0.1
$userModuleRoots = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
    "$env:USERPROFILE\Documents\PowerShell\Modules"
    "$env:OneDrive\Documents\WindowsPowerShell\Modules"
    "$env:OneDrive\Documents\PowerShell\Modules"
    "$env:OneDriveCommercial\Documents\WindowsPowerShell\Modules"
    "$env:OneDriveCommercial\Documents\PowerShell\Modules"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

# Also catch the exact OneDrive path from your screenshot
$docs = [Environment]::GetFolderPath('MyDocuments')
if ($docs) {
    $userModuleRoots += Join-Path $docs 'WindowsPowerShell\Modules'
    $userModuleRoots += Join-Path $docs 'PowerShell\Modules'
}

$userModuleRoots = $userModuleRoots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

Write-Host "`nUser module roots:" -ForegroundColor Cyan
$userModuleRoots | ForEach-Object { Write-Host "  $_" }

foreach ($root in $userModuleRoots) {
    foreach ($name in $modules) {
        $path = Join-Path $root $name
        if (Test-Path $path) {
            Write-Host "Deleting $path" -ForegroundColor Yellow
            try {
                attrib -R -S -H "$path\*" /S /D 2>$null
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                Write-Host "  Removed." -ForegroundColor Green
            } catch {
                Write-Warning "Locked: $path"
                Write-Warning $_.Exception.Message
                Write-Host "Pause OneDrive sync, close File Explorer on that folder, then re-run." -ForegroundColor Red
            }
        }
    }
}

# --- 5. Fresh install to AllUsers (NOT OneDrive) ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try {
    Set-
