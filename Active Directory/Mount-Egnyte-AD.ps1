<#
.Synopsis
    Mounts Egnyte network drives.

.Description
    This script mounts Egnyte network drives based on group membership in Active Directory.
    Utilizes a CSV file with all of the drive mappings and group names located in the Deploy directory.

.Example
    .\Mount-Egnyte-AD.ps1 without administrator rights.

.Outputs
    Log files stored in C:\Logs\Egnyte.

.Notes
    Author: Chrysi
    Link:   https://github.com/chrysillis/egnyte
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Requires -Version 5.1

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script version
$ScriptVersion = "v5.3.1"
#Script name
$App = "Egnyte Drive Mapping"
#Application installation path
$Default = "C:\Program Files (x86)\Egnyte Connect\EgnyteClient.exe"
#Location of the mappings
$LocalFile = "C:\Deploy\Egnyte\Client-Drives-AD.csv"
#Egnyte tenant name
$Tenant = "contoso"
#Today's date
$Date = Get-Date -Format "MM-dd-yyyy-HH-mm-ss"
#Destination to store logs
$LogFilePath = "C:\Logs\Egnyte\" + $Date + "" + "-" + $env:USERNAME + "-Mount-Logs.log"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Start-Egnyte {
    <#
    .Synopsis
    Starts Egnyte if any of its processes aren't running.
    #>
    $arguments = '--auto-silent'
    try {
        $egnyteclient = Get-WmiObject -Class Win32_Process -Filter "Name = 'egnyteclient.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.GetOwner().User -eq $env:USERNAME }
        $egnytedrive = Get-WmiObject -Class Win32_Process -Filter "Name = 'egnytedrive.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.GetOwner().User -eq $env:USERNAME }
        if (!$egnyteclient -or !$egnytedrive) {
            Write-Host "$(Get-Date): Starting Egnyte before mapping drives..."
            Start-Process -PassThru -FilePath $default -ArgumentList $arguments | Out-Null
            Start-Sleep -Seconds 8
            $egnyteclient = Get-WmiObject -Class Win32_Process -Filter "Name = 'egnyteclient.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.GetOwner().User -eq $env:USERNAME }
            if ($egnyteclient) {
                Write-Host "$(Get-Date): Egnyte has successfully started up!"
            }
        }
        else {
            Write-Host "$(Get-Date): Egnyte is already running, proceeding to map drives."
        }
    }
    catch {
        Write-Host "$(Get-Date): Unable to confirm if $app is running or not, attempting to start $app by force: $($_.Exception.Message)"
        Start-Process -PassThru -FilePath $default -ArgumentList $arguments
        Start-Sleep -Seconds 8
        $egnyteclient = Get-WmiObject -Class Win32_Process -Filter "Name = 'egnyteclient.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.GetOwner().User -eq $env:USERNAME }
        if ($egnyteclient) {
            Write-Host "$(Get-Date): $app has successfully started up!"
        }
        else {
            Write-Host "$(Get-Date): Status of $app is unknown, proceeding with rest of script..."
        }
    }
}
function Mount-Drives {
    <#
    .Synopsis
    Map and connect each drive in the array.
    .Parameter DriveList
    Accepts an array of drives and then feeds them into Egnyte to be mounted.
    #>
    [CmdletBinding(DefaultParameterSetName = "DriveList")]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = "DriveList")]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject[]]
        $Drive
    )
    process {
        try {
            Write-Host "$(Get-Date): Mapping $($Drive.DriveName) to $($Drive.DriveLetter)" -ForegroundColor Green
            $arguments = @(
                "-command add"
                "-l ""$($Drive.DriveName)"""
                "-d ""$($Drive.DomainName)"""
                "-sso use_sso"
                "-t ""$($Drive.DriveLetter)"""
                "-m ""$($Drive.DrivePath)"""
            )
            $process = Start-Process -PassThru -FilePath $default -ArgumentList $arguments
            $process.WaitForExit()
            $connect = @(
                "-command connect"
                "-l ""$($Drive.DriveName)"""
            )
            $process = Start-Process -PassThru -FilePath $default -ArgumentList $connect
            $process.WaitForExit()
        }
        catch {
            Throw "Unable to map or connect drives: $($_.Exception.Message)"
        }
    }
}
function Remove-Drives {
    <#
    .Synopsis
    Removes drives that are not authorized.
    .Parameter DriveList
    Accepts an array of drives and then feeds them into Egnyte to be removed.
    #>
    [CmdletBinding(DefaultParameterSetName = "DriveList")]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = "DriveList")]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject[]]
        $Drive
    )
    process {
        try {
            Write-Host "$(Get-Date): Not authorized, removing $($Drive.DriveName) drive." -ForegroundColor Magenta
            $arguments = @(
                "-command remove"
                "-l ""$($Drive.DriveName)"""
            )
            $process = Start-Process -PassThru -FilePath $default -ArgumentList $arguments
            $process.WaitForExit()
        }
        catch {
            Throw "Unable to remove drives: $($_.Exception.Message)"
        }
    }
}
function Mount-Personal {
    <#
    .Synopsis
    Map and connect personal drives.
    #>
    process {
        try {
            Write-Host "$(Get-Date): Mapping Private to P" -ForegroundColor Green
            $User = $env:USERNAME
            $arguments = @(
                "-command add"
                "-l ""Private"""
                "-d ""$Tenant"""
                "-sso use_sso"
                "-t ""P"""
                "-m ""/Private/$($User)"""
            )
            $process = Start-Process -PassThru -FilePath $default -ArgumentList $arguments
            $process.WaitForExit()
            $connect = @(
                "-command connect"
                "-l ""Private"""
            )
            $process = Start-Process -PassThru -FilePath $default -ArgumentList $connect
            $process.WaitForExit()
        }
        catch {
            Throw "Unable to map or connect private drive: $($_.Exception.Message)"
        }
    }
}
function Test-Paths {
    <#
    .Synopsis
    Tests existing paths to see if the drives have already been mapped.
    .Description
    Checks group membership before mapping each drive to ensure end user has appropriate permissions.
    Tests the paths first so as to not waste time re-mapping drives that are already mapped.
    Checks whether the path is mapped to a local server versus Egnyte. If mapped to local, then removes the mapping and remaps it to Egnyte.
    Also checks if drive is disconnected and if it is, will unmap it and then remap it to Egnyte.
    #>
    [CmdletBinding(DefaultParameterSetName = "DriveList")]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = "DriveList")]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject[]]
        $DriveList
    )
    process {
        try {
            Write-Host "$(Get-Date): Checking to see if the paths are already mapped..."
            $GroupMember = ([adsisearcher]"samaccountname=$($env:USERNAME)").FindOne().Properties.memberof -replace '^CN=([^,]+).+$', '$1'
            foreach ($Drive in $DriveList) {
                $DriveLetter = "$($Drive.DriveLetter)" + ":"
                $PathTest = Test-Path -Path $DriveLetter
                if ($GroupMember -contains $Drive.GroupName) {
                    if (!$PathTest) {
                        Write-Host "$(Get-Date): $($Drive.DriveName) not found. Mapping now."
                        Mount-Drives -Drive $Drive
                    }
                    elseif ($PathTest) {
                        Write-Host "$(Get-Date): $($Drive.DriveName) was found."
                        $Root = Get-PSDrive | Where-Object { $_.DisplayRoot -match "EgnyteDrive" -and $_.Name -eq $Drive.DriveLetter }
                        if (!$Root) {
                            Write-host "$(Get-Date): $($Drive.DriveName) is not mapped to the cloud. Unmapping now."
                            net use $DriveLetter /delete
                            Mount-Drives -Drive $Drive
                        }
                    }
                }
                elseif ($GroupMember -notcontains $Drive.GroupName) {
                    if ($PathTest) {
                        Remove-Drives -Drive $Drive
                    }
                }
            }
        }
        catch {
            Throw "Could not map drives: $($_.Exception.Message)"
        }
    }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Sets up a destination for the logs
if (-Not (Test-Path -Path "C:\Logs")) {
    Write-Host "$(Get-Date): Creating new log folder."
    New-Item -ItemType Directory -Force -Path C:\Logs | Out-Null
}
if (-Not (Test-Path -Path "C:\Logs\Egnyte")) {
    Write-Host "$(Get-Date): Creating new Egnyte log folder."
    New-Item -ItemType Directory -Force -Path C:\Logs\Egnyte | Out-Null
}
#Begins the logging process to capture all output
Start-Transcript -Path $LogFilePath -Force
Write-Host "$(Get-Date): Successfully started $App $ScriptVersion on $env:computername"
Write-Host "$(Get-Date): Checking if Egnyte is running before continuing..."
#Starts Egnyte up if it isn't already running
Start-Egnyte
#Imports the mapping file into the script
$Drives = Import-Csv -Path $LocalFile
#Tests the paths to see if they are already mapped or not and maps them if needed
Test-Paths -DriveList $Drives
#Maps the personal drive
$Personal = Get-PSDrive | Where-Object { $_.DisplayRoot -match "EgnyteDrive" -and $_.Name -eq "P" }  
if (!$Personal) {
    Write-Host "$(Get-Date): Personal not found, proceeding to map drive..."
    Mount-Personal
}
else {
    Write-Host "$(Get-Date): Personal is already mapped..."
}
#Ends the logging process
Stop-Transcript
#Terminates the script
exit