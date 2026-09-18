# Bootstrap-PSGet.ps1  — run: powershell -NoProfile -ExecutionPolicy Bypass -File .\Bootstrap-PSGet.ps1

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# --- diagnostics (read these if anything fails) ---
Write-Host "LanguageMode : $($ExecutionContext.SessionState.LanguageMode)"
Write-Host "ExecPolicy   :"
Get-ExecutionPolicy -List | Format-Table -AutoSize
Write-Host "PSModulePath :"
$env:PSModulePath -split ';' | ForEach-Object { Write-Host "  $_" }

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- kill other hosts ---
Get-Process powershell,pwsh -ErrorAction SilentlyContinue |
    Where-Object Id -ne $PID |
    Stop-Process -Force -ErrorAction SilentlyContinue

# --- unload ---
Remove-Module PowerShellGet, PackageManagement -Force -ErrorAction SilentlyContinue

# --- delete USER/OneDrive copies only ---
$docs = [Environment]::GetFolderPath('MyDocuments')
$userRoots = @(
    "$docs\WindowsPowerShell\Modules"
    "$docs\PowerShell\Modules"
) | Where-Object { Test-Path $_ }

foreach ($root in $userRoots) {
    foreach ($m in 'PackageManagement','PowerShellGet') {
        $p = Join-Path $root $m
        if (Test-Path $p) {
            Write-Host "Removing user copy: $p" -ForegroundColor Yellow
            cmd /c "attrib -R -S -H `"$p\*`" /S /D" | Out-Null
            Remove-Item -LiteralPath $p -Recurse -Force
        }
    }
}

# --- download + extract into Program Files ---
$destRoot = 'C:\Program Files\WindowsPowerShell\Modules'
$work     = Join-Path $env:TEMP 'psget-bootstrap'
New-Item $work -ItemType Directory -Force | Out-Null

$packages = @(
    @{ Name = 'PackageManagement'; Version = '1.4.8.1' }
    @{ Name = 'PowerShellGet';     Version = '2.2.5'   }
)

foreach ($pkg in $packages) {
    $nupkg = Join-Path $work "$($pkg.Name).$($pkg.Version).nupkg"
    $url   = "https://www.powershellgallery.com/api/v2/package/$($pkg.Name)/$($pkg.Version)"
    Write-Host "Downloading $($pkg.Name) $($pkg.Version) ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing

    $extract = Join-Path $work $pkg.Name
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -LiteralPath $nupkg -DestinationPath $extract -Force

    $target = Join-Path $destRoot "$($pkg.Name)\$($pkg.Version)"
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item $target -ItemType Directory -Force | Out-Null

    # Gallery nupkg layout: module files are at the root of the package
    Get-ChildItem $extract -Force | Where-Object {
        $_.Name -notin @('_rels','package','[Content_Types].xml',"$($pkg.Name).nuspec")
    } | ForEach-Object {
        Copy-Item $_.FullName -Destination $target -Recurse -Force
    }
    Write-Host "Installed to $target" -ForegroundColor Green
}

# --- load from Program Files explicitly ---
$pm = 'C:\Program Files\WindowsPowerShell\Modules\PackageManagement\1.4.8.1\PackageManagement.psd1'
$pg = 'C:\Program Files\WindowsPowerShell\Modules\PowerShellGet\2.2.5\PowerShellGet.psd1'

Write-Host "`nImporting PackageManagement..." -ForegroundColor Cyan
Import-Module $pm -Force -ErrorAction Stop

Write-Host "Installing NuGet provider..." -ForegroundColor Cyan
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

Write-Host "Importing PowerShellGet..." -ForegroundColor Cyan
Import-Module $pg -Force -ErrorAction Stop

Write-Host "`n=== SUCCESS ===" -ForegroundColor Green
Get-Module PackageManagement, PowerShellGet |
    Select-Object Name, Version, ModuleBase | Format-Table -AutoSize

Get-Command Install-Module, Find-Module, Update-Module |
    Select-Object Name, Source | Format-Table -AutoSize

Write-Host "Close this window and open a NEW PowerShell before installing other modules."
