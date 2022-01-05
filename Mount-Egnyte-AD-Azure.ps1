#Requires -Version 5.1
<#
.Synopsis
Mounts Egnyte network drives.
.Description
This script mounts Egnyte network drives based on group membership in Active Directory.
Feed it a CSV file with all of the drive mappings and it will handle the rest.
.Example
.\Mount-Egnyte-AD.ps1 without administrator rights.
.Notes
Author: Chrysillis Collier
Email: ccollier@micromenders.com
#>


#Defines path to application.
$Default = "C:\Program Files (x86)\Egnyte Connect\EgnyteClient.exe"
#Defines script name.
$App = "Egnyte Drive Mapping"
#States the current version of this script
$Version = "v5.1.5"
#Today's date and time
$Date = Get-Date -Format "MM-dd-yyyy-HH-mm-ss"
#Destination for application logs
$LogFilePath = "C:\temp\Egnyte Logs\" + $Date + "" + "-" + $env:USERNAME + "-Egnyte-Mount-Logs.log"


function Get-Files {
    <#
    .Synopsis
    Downloads files.
    .Parameter URL
    Input the URL to the file to be downloaded.
    #>
    [CmdletBinding(DefaultParameterSetName = "URL")]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = "URL")]
        [ValidateNotNullOrEmpty()]
        [String]
        $URL
    )
    process {
        try {
            #Creates local working directory if it does not already exist.
            if (-Not (Test-Path -Path "C:\Deploy")) {
                Write-Verbose -Message "Creating new directory."
                New-Item -ItemType Directory -Force -Path C:\Deploy
            }
            #Local destination to save downloaded files to.
            $Outpath = "C:\Deploy\client-drives.csv"
            Write-Host "$(Get-Date): Downloading files to $Outpath..."
            #Downloads the files to the local destination and measures the time it takes.
            $Job = Measure-Command { (New-Object System.Net.WebClient).DownloadFile($URL, $Outpath) }
            $JobTime = $Job.TotalSeconds
            #Checks if the download was successful or not.
            if (Test-Path $Outpath) {
                Write-Host "$(Get-Date): Files downloaded successfully in $JobTime seconds..."		
            }
            else {
                Write-Host "$(Get-Date): Download failed, please check your connection and try again..." -ForegroundColor Red
                #Deletes the working directory and all data inside it.
                Remove-Item "C:\Deploy" -Force -Recurse
                #Ends the logging process.
                Stop-Transcript
                #Terminates the script.
                exit
            }
        }
        catch {
            #Displays any major errors that might have occured.
            Throw "There was an unrecoverable error: $($_.Exception.Message) Cannot download files."
        }
    }
}
function Start-Egnyte {
    <#
    .Synopsis
    Starts Egnyte if any of its processes aren't running.
    #>
    $arguments = '--auto-silent'
    try {
        $egnyteclient = Get-WmiObject -Class Win32_Process -Filter "Name = 'egnyteclient.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.GetOwner().User -eq $env:USERNAME }
        $egnytedrive = Get-WmiObject -Class Win32_Process -Filter "Name = 'egnytedrive.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.GetOwner().User -eq $env:USERNAME }
        $egnytesync = Get-WmiObject -Class Win32_Process -Filter "Name = 'egnytesyncservice.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.GetOwner().User -eq $env:USERNAME }
        if (!$egnyteclient -or !$egnytedrive -or !$egnytesync) {
            Write-Host "$(Get-Date): Starting $app before mapping drives..."
            Start-Process -PassThru -FilePath $default -ArgumentList $arguments
            Start-Sleep -Seconds 8
            $egnyteclient = Get-WmiObject -Class Win32_Process -Filter "Name = 'egnyteclient.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.GetOwner().User -eq $env:USERNAME }
            if ($egnyteclient) {
                Write-Host "$(Get-Date): $app has successfully started up!"
            }
        }
        else {
            Write-Host "$(Get-Date): $app is already running, proceeding to map drives."
        }
    }
    catch {
        Write-Host "$(Get-Date): There was an error: $($_.Exception.Message) Unable to confirm if $app is running or not, attempting to start $app by force."
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
        $DriveList
    )
    process {
        try {
            foreach ($Drive in $DriveList) {
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
        }
        catch {
            Throw "There was an unrecoverable error: $($_.Exception.Message) Unable to map or connect drives."
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
                $CheckMembers = $GroupMember -contains $Drive.GroupName
                if (Test-Path -Path "$($Drive.DriveLetter):") {
                    $Root = Get-PSDrive | Where-Object { $_.DisplayRoot -match "EgnyteDrive" -and $_.Name -eq $Drive.DriveLetter }  
                    if (!$Root) {
                        Write-host "$(Get-Date): $($Drive.DriveName) is not mapped to the cloud. Unmapping now."
                        $NetDrive = $($Drive.DriveLetter) + ":"
                        net use $NetDrive /delete
                        Mount-Drives -DriveList $Drive
                    }
                    else {
                        Write-Host "$(Get-Date): $($Drive.DriveName) is already mapped..."
                    }
                }
                elseif ($CheckMembers) {
                    Write-Host "$(Get-Date): $($Drive.DriveName) not found, proceeding to map drive..."
                    Mount-Drives -DriveList $Drive
                }
                else {
                    Write-Host "$(Get-Date): Not authorized for this drive, moving to next drive..."    
                }
            }
            Write-Host "$(Get-Date): All drives checked on $env:computername, proceeding to exit script..."
            Start-Sleep -Seconds 2
        }
        catch {
            Throw "There was an unrecoverable error: $($_.Exception.Message) Unable to connect to AD to check membership."
        }
    }
}
#Begins the logging process to capture all output.
Start-Transcript -Path $LogFilePath -Force
Write-Host "$(Get-Date): Successfully started $App $Version on $env:computername"
Write-Host "$(Get-Date): Checking if Egnyte is running before continuing..."
#Starts Egnyte up if it isn't already running.
Start-Egnyte
#Initiates the file download process.
Get-Files -URL "https://aimlp.blob.core.windows.net/egnyte/client-drives.csv"
$Drives = Import-Csv -Path "C:\Deploy\client-drives.csv"
#Tests the paths to see if they are already mapped or not and maps them if needed.
Test-Paths -DriveList $Drives
#Ends the logging process.
Stop-Transcript
#Terminates the script.
exit