 Function Convert-Path {
    <#
        .SYNOPSIS
        Replaces paths with environment variables
    #>
    Param (
        [Parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
        [System.String] $Path
    )
    Switch ($Path) {
        { $_ -match "Microsoft.PowerShell.Core\\Registry::HKEY_LOCAL_MACHINE" } { $Path = $Path -replace "Microsoft.PowerShell.Core\\Registry::HKEY_LOCAL_MACHINE", "HKLM" }
        { $_ -match "HKEY_LOCAL_MACHINE" } { $Path = $Path -replace "HKEY_LOCAL_MACHINE", "HKLM" }
        { $_ -match "HKLM:" } { $Path = $Path -replace "HKLM:", "HKLM" }
        { $_ -match "C:\\Program Files (x86)" } { $Path = $Path -replace "C:\\Program Files (x86)", "%ProgramFilesFolder32%" }
        { $_ -match "C:\\Program Files" } { $Path = $Path -replace "C:\\Program Files", "%ProgramFilesFolder64%" }
        { $_ -match "C:\\ProgramData\\Microsoft\\Windows\\Start Menu" } { $Path = $Path -replace "C:\\ProgramData\\Microsoft\\Windows\\Start Menu", "%CommonStartMenuFolder%" }
        { $_ -match "C:\\ProgramData" } { $Path = $Path -replace "C:\\ProgramData", "%CommonAppDataFolder%" }
        { $_ -match "C:\\Users" } { $Path = $Path -replace "C:\\Users", "%SystemDriveFolder%\Users" }
        
    }
    Write-Output -InputObject $Path
}

Clear-Host
$StartDTM = (Get-Date)

Write-Verbose "Setting Arguments" -Verbose
$ProgressPreference = 'SilentlyContinue'
$Icons = "C:\Icons"
$Path = "C:\Win32App"
$Template = "$Path\AppV_Template.appvt"
$TemplateURL = "https://raw.githubusercontent.com/haavarstein/Applications/master/AppV_Template.appvt"
$XML = "$Path\Applications.xml"
$XMLURL = "https://raw.githubusercontent.com/haavarstein/Applications/master/Applications.xml"
$PatchMyPC = "$Path\Definitions.xml"
$PatchMyPCURL = "https://patchmypc.com/freeupdater/definitions/definitions.xml"
$TeamsWebHook = "https://xenappblog.webhook.office.com/webhookb2/5b224351-8e14-42ac-9852-93a58e0b158d@681d484d-388f-4da7-a72b-91f4a58253de/IncomingWebhook/b3f7a55835274b188b773e2bd7990e90/121e06e7-eed2-4958-9007-c51914d0c77f"

If (!(Test-Path -Path $Icons)) { 
    Write-Verbose "Copying Icons Files to Local Drive" -Verbose
    New-Item -ItemType directory -Path $Icons | Out-Null 
    Copy-Item -Path "\\br-fs-01\xa\icons\*" -Destination $Icons -Recurse -Force
}

Write-Verbose "Removing MSStore from WinGet due to EULA" -Verbose
winget source remove msstore

# Set Timeout
[System.Net.ServicePointManager]::MaxServicePointIdleTime = 5000000

Write-Verbose "Installing Required PowerShell Modules" -Verbose
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
if (!(Test-Path -Path "C:\Program Files\PackageManagement\ProviderAssemblies\nuget")) { Install-PackageProvider -Name 'Nuget' -ForceBootstrap -IncludeDependencies }
if (!(Get-Module -ListAvailable -Name Evergreen)) { Install-Module Evergreen -Force | Import-Module Evergreen }
if (!(Get-Module -ListAvailable -Name IntuneWin32App)) {Install-Module IntuneWin32App -Force | Import-Module IntuneWin32App}
If (!(Test-Path -Path $Path)) {New-Item -ItemType directory -Path $Path | Out-Null}
Invoke-WebRequest -UseBasicParsing -Uri $TemplateURL -OutFile $Template
Invoke-WebRequest -UseBasicParsing -Uri $XMLURL -OutFile $XML
Invoke-WebRequest -UseBasicParsing -Uri $PatchMyPCURL -OutFile $PatchMyPC

$MyConfigFileloc = ("$XML")
[xml]$MyConfigFile = (Get-Content $MyConfigFileLoc)

$MyDefinitionFileloc = ("$PathMyPC")
[xml]$MyDefinitionFile = (Get-Content $Path\Definitions.xml)

$TentantID = "xenappblog.com"

foreach ($App in $MyConfigFile.Applications.ChildNodes)
{

Connect-MSIntuneGraph -TenantID $TentantID | Out-Null

$Product = $App.Product
$Vendor = $App.Vendor
$Architecture = $App.Architecture
$DisplayName = $App.DisplayName
$PackageName = "$Product"
$Evergreen = $App.Evergreen
$Version = $MyDefinitionFile.Data.ARPData.$("$Product" + "Ver")
$URL = $MyDefinitionFile.Data.ARPData.$("$Product" + "Download")
$InstallerType = $App.Installer
$InstallerPath = $App.Path
$UnattendedArgs = $App.Install
$UnattendedArgs = $UnattendedArgs.Replace("/i ","")
$LogApp = "${env:SystemRoot}" + "\Temp\$Product $Version.log"

$IntuneCustomer = $App.Assignments.Customer
$IntuneGroup = $App.Assignments.Group
$IntuneRequiredGroup = $App.Assignments.RequiredGroup
$IntunePilotGroup = $App.Assignments.PilotGroup

CD $Path

    If ($App.Enabled -eq "True" -and $App.PMPC -eq "True") {
        Write-Verbose "Download Method for $Product is PatchMyPC" -Verbose
        $Version = $MyDefinitionFile.Data.ARPData.$("$Product" + "Ver")
        $URL = $MyDefinitionFile.Data.ARPData.$("$Product" + "Download")
        $Source = "$PackageName" + "_" + "$Version" + "_" + "$Architecture" + "." + "$InstallerType"

    } 

    If ($App.Enabled -eq "True" -and $App.PMPC -notlike "True" -and $App.WinGet -notlike "True") {
        Write-Verbose "Download Method for $Product is Evergreen" -Verbose
        $Evergreen = Invoke-Expression $App.Evergreen -ErrorAction SilentlyContinue
        $Version = $Evergreen.Version
        $URL = $Evergreen.uri
        $Source = "$PackageName" + "_" + "$Version" + "_" + "$Architecture" + "." + "$InstallerType"

    } 

    If ($App.Enabled -eq "True" -and $App.WinGet -eq "True") {
        Write-Verbose "Download Method for $Product is WinGet" -Verbose
        $File = "$Product" + ".txt"
        WinGet show "$Product" | Out-File $File
        WinGet show "$Product" | Out-File $File
        (Get-Content $File| Select-Object -Skip 2) | Set-Content $File
        $PsYaml = ConvertFrom-Yaml (cat -raw $File)
        $Version = $PsYaml.Version
        $URL = $PsYaml.Installer.'Download Url'    
        $Source = "$PackageName" + "_" + "$Version" + "_" + "$Architecture" + "." + "$InstallerType"

    } 

If (!(Test-Path -Path "$("$PackageName" + "_" + "$Version" + "_" + "$Architecture" + ".intunewin")") -and $($App.Enabled) -eq "True") { 
             
    Write-Verbose "Downloading $($App.DisplayName) $Version ($Architecture)" -Verbose
    If (!(Test-Path -Path $Source)) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Source -TimeoutSec 3600 | Out-Null }
    $Size = ((Get-Item $Source).Length/1mb).ToString('N2')
    
    # Creating Temp Folder
    If (!(Test-Path -Path $Path\Temp)) {New-Item -ItemType directory -Path $Path\Temp | Out-Null}

    # Copy Setup File
    Copy-Item -Path $Source -Destination $Path\Temp   

    Write-Verbose "Creating Intune Application for $($App.DisplayName) $Version ($Architecture)" -Verbose
    $Win32AppPackage = New-IntuneWin32AppPackage -SourceFolder $Path\Temp -SetupFile $Source -OutputFolder $Path
        
    # Get Application meta data from .intunewin file
    $IntuneWinFile = $Win32AppPackage.Path
    $IntuneWinMetaData = Get-IntuneWin32AppMetaData -FilePath $IntuneWinFile

    # Create custom display name
    $DisplayName = $($App.DisplayName) + " " + $Version + " " + "($Architecture)"
    $Publisher = $Vendor

    # Convert image file to icon
    if (!(Test-Path -Path $Icons\$Product.png)) { 
        $ImageFile = "$Icons\MSI.png"
        $Icon = New-IntuneWin32AppIcon -FilePath $ImageFile
        } 
        else
        {
        $ImageFile = "$Icons\$Product.png"
        $Icon = New-IntuneWin32AppIcon -FilePath $ImageFile

    }

    If ($App.Installer -eq "msi") {
        $ProductCode = $IntuneWinMetaData.ApplicationInfo.MsiInfo.MsiProductCode
        $InstallCommandLine = "msiexec /i `"$Source`" ALLUSERS=1 REBOOT=ReallySuppress /norestart /qn /L*V `"$LogApp`""
        $UninstallCommandLine = "msiexec /x $ProductCode /qn"
        $DetectionRule = New-IntuneWin32AppDetectionRuleMSI -ProductCode $ProductCode -ProductVersionOperator "greaterThanOrEqual" -ProductVersion $IntuneWinMetaData.ApplicationInfo.MsiInfo.MsiProductVersion
        $Win32App = Add-IntuneWin32App -FilePath $IntuneWinFile -DisplayName Evergreen-$DisplayName -AppVersion $Version -Description "$($App.Description)" -Developer "Automation Framework" -Owner "Trond Eirik Haavarstein" -Publisher $Publisher -InstallExperience "system" -RestartBehavior "suppress" -DetectionRule $DetectionRule -InstallCommandLine $InstallCommandLine -UninstallCommandLine $UninstallCommandLine -Icon $Icon -CompanyPortalFeaturedApp $true

    } 

     If ($App.Installer -eq "exe") {
        
        $Script = "$Path\Temp\$Product.ps1"
        "if (Test-Path -Path ""$($App.Path)"")" | Set-Content -Encoding Ascii -Force $Script
        "{ Write-Host 'Found it' }" | Add-Content -Encoding Ascii $Script

        $DetectionScriptFile = $Script
        #$DetectionRule = New-IntuneWin32AppDetectionRuleScript -ScriptFile $DetectionScriptFile -EnforceSignatureCheck $false -RunAs32Bit $false
        $DetectionRule = New-IntuneWin32AppDetectionRuleFile -Version -Path $App.Path -FileOrFolder $App.DetectionFile -Operator "greaterThanOrEqual" -VersionValue $Version
        $InstallCommandLine = $Source + " " + $($App.Install)
        $UninstallCommandLine = $App.Path + "\" +  $($App.Uninstall)
        $Win32App = Add-IntuneWin32App -FilePath $IntuneWinFile -DisplayName Evergreen-$DisplayName -AppVersion $Version -Description "$($App.Description)" -Developer "Automation Framework" -Owner "Trond Eirik Haavarstein" -Publisher $Publisher -InstallExperience "system" -RestartBehavior "suppress" -DetectionRule $DetectionRule -InstallCommandLine $InstallCommandLine -UninstallCommandLine $UninstallCommandLine -Icon $Icon -CompanyPortalFeaturedApp $true

    } 

    #Write-Verbose "Installing $($App.DisplayName) $Version ($Architecture) to get File Version" -Verbose
    #$UnattendedArgs = "/i $Source ALLUSERS=1 /qb"
    #(Start-Process msiexec.exe -ArgumentList $UnattendedArgs -Wait -Passthru).ExitCode
    #$FileVersion = (Get-Command "$InstallerPath\7zG.exe").FileVersionInfo.FileVersion
    #$FileVersion = $FileVersion -replace ",","."

    #Write-Verbose "File Version is $FileVersion" -Verbose

    #Write-Verbose "Uninstalling $($App.DisplayName) $Version ($Architecture)" -Verbose
    #$UnattendedArgs = "/x $Source /qb"
    #(Start-Process msiexec.exe -ArgumentList $UnattendedArgs -Wait -Passthru).ExitCode

    # Add assignment for all users
    Add-IntuneWin32AppAssignmentAllUsers -ID $Win32App.id -Intent "available" -Notification "showAll"

    # Create Update Package
    $RequirementRule = New-IntuneWin32AppRequirementRuleFile -Version -Path $App.Path -FileOrFolder $App.DetectionFile -Operator lessThan -VersionValue $Version
    #$RequirementRule = New-IntuneWin32AppRequirementRuleFile -Existence -DetectionType exists -Path $App.Path -FileOrFolder $App.DetectionFile -Check32BitOn64System $false 
    #$RequirementRule = New-IntuneWin32AppDetectionRuleRegistry -Existence -KeyPath "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" -ValueName $ProductCode -DetectionType exists
    $Win32App = Add-IntuneWin32App -FilePath $IntuneWinFile -DisplayName Update-Evergreen-$DisplayName -AppVersion $Version -Description "$($App.Description)" -Developer "Automation Framework" -Owner "Trond Eirik Haavarstein" -Publisher $Publisher -InstallExperience "system" -RestartBehavior "suppress" -DetectionRule $DetectionRule -InstallCommandLine $InstallCommandLine -UninstallCommandLine $UninstallCommandLine -Icon $Icon -AdditionalRequirementRule $RequirementRule

    # Add assignment for all devices
    Add-IntuneWin32AppAssignmentAllDevices -ID $Win32App.id -Intent "required" -Notification "showAll"


    Start-Sleep -s 30

    # Delete Temp Folder
    Remove-Item -Path $Path\Temp -Confirm:$false -Recurse

    

$body = @"
    {
        "title": "Intune Application Created: $($App.DisplayName) $Version ($Architecture)",
        "text": "`n
        Created: $(Get-Date)
        Version: $Version
        Size: $Size MB
        Type: $InstallerType
        Tentant: $($TentantID)
        Assignment: Available - All Devices
        "
     }
"@

Invoke-RestMethod -uri $TeamsWebHook -Method Post -body $body -ContentType 'application/json' | Out-Null

Start-Sleep -s 300

}
}

$EndDTM = (Get-Date)
Write-Verbose "Elapsed Time: $(($EndDTM-$StartDTM).TotalMinutes) Minutes" -Verbose 
