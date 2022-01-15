Clear-Host

$Temp = "C:\Temp"
$VCx64 = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$VCx86 = "https://aka.ms/vs/17/release/vc_redist.x86.exe"
$ProgressPreference = 'SilentlyContinue'

$MPVersion = "https://www.masterpackager.com/uploads/file_archive/version.txt"
$MPPath = "C:\Program Files (x86)\Master Packager"
$MPSnap = "C:\MRP\Snapshots"
$MPEmail = "XXXXX"
$MPKey = "XXXXX"

$CabLocation = "inside"
$MSIArchitecture = "x64"
$CompressionLevel = "min"
$CabSize = "300"
$MsiPath = "C:\MRP\Repack_$(get-date -Format "ddMMyy")_$(get-date -Format "HHmmss")\repack.msi"

If (!(Test-Path -Path $Temp)) { New-Item -ItemType directory -Path $Temp | Out-Null }

CD $Temp

Write-Verbose "Downloading Latest Master Packager Version" -Verbose
$tmp = New-TemporaryFile
Invoke-WebRequest -UseBasicParsing -Uri $MPVersion -OutFile $tmp -ErrorAction SilentlyContinue
$Version = get-content $tmp
$MP = "https://www.masterpackager.com/installer/masterpackager_$($Version).0.msi"
Invoke-WebRequest -UseBasicParsing -Uri $MP -OutFile "MasterPackager.msi"

Write-Verbose "Downloading Latest Microsoft Visual C++ 2015-2019 (x64)" -Verbose
Invoke-WebRequest -UseBasicParsing -Uri $VCx64 -OutFile "vc_redist.x64.exe"

Write-Verbose "Downloading Latest Microsoft Visual C++ 2015-2019 (x86)" -Verbose
Invoke-WebRequest -UseBasicParsing -Uri $VCx86 -OutFile "vc_redist.x86.exe"

Write-Verbose "Starting Installating of Master Packager" -Verbose
$UnattendedArgs = "/i MasterPackager.msi ALLUSERS=1 /qn"
(Start-Process msiexec.exe -ArgumentList $UnattendedArgs -Wait -Passthru).ExitCode

Write-Verbose "Starting Installating of Microsoft Visual C++ 2015-2019 (x64)" -Verbose
$UnattendedArgs = '/q /norestart'
(Start-Process "vc_redist.x64.exe" $UnattendedArgs -Wait -Passthru).ExitCode

Write-Verbose "Starting Installating of Microsoft Visual C++ 2015-2019 (x86)" -Verbose
$UnattendedArgs = '/q /norestart'
(Start-Process "vc_redist.x86.exe" $UnattendedArgs -Wait -Passthru).ExitCode

Write-Verbose "Registering Master Packager License" -Verbose
(Start-Process $MPPath\mrp.exe -ArgumentList "activate -email $MPEmail -licensekey ""$MPKey""" -Wait -Passthru).ExitCode

Write-Verbose "Creating First Snapshot" -Verbose
If (!(Test-Path -Path $MPSnap)) { New-Item -ItemType directory -Path $MPSnap | Out-Null }
$FirstSnapshot = "$MPSnap\FirstSnapshot_$(get-date -Format "ddMMyy")_$(get-date -Format "HHmmss").mrps"
(Start-Process -FilePath $MPPath\mrp.exe -ArgumentList "capture ""$FirstSnapshot""" -Wait -Passthru).ExitCode

Read-Host -Prompt "Install your Application and Press <ENTER> when done or CTRL+C to quit" 

Write-Verbose "Creating Second Snapshot" -Verbose
If (!(Test-Path -Path $MPSnap)) { New-Item -ItemType directory -Path $MPSnap | Out-Null }
$SecondSnapshot = "C:\MRP\Snapshots\SecondSnapshot_$(get-date -Format "ddMMyy")_$(get-date -Format "HHmmss").mrps"
(Start-Process -FilePath $MPPath\mrp.exe -ArgumentList "capture ""$SecondSnapshot""" -Wait -Passthru).ExitCode

Write-Verbose "Building Repackaged MSI" -Verbose
(Start-Process -FilePath $MPPath\mrp.exe -ArgumentList "build -FirstSnapshot ""$FirstSnapshot"" -SecondSnapshot ""$SecondSnapshot"" -$CabLocation -$MSIArchitecture -Compression $CompressionLevel -CabSize $CabSize -MsiPath ""$MsiPath""" -Wait -Passthru).ExitCode

Write-Verbose "Completed" -Verbose
Invoke-Item "C:\MRP"
