#Requires -Version 5.1
<#
.Synopsis
Maps network drives.
.Description
This script mounts network drives based on group membership in Active Directory.
Give it a CSV file with all of the drive mappings and group names and it will handle the rest.
Need to change the $StorageSync variable to the current IP address of the device.
.Example
.\Mount-StorageSync.ps1 without administrator rights.
.Notes
Author: Chrysillis Collier
Email: ccollier@micromenders.com
Date: 09-10-2021
#>


#Defines script name.
$App = "Drive Mapping"
#States the current version of this script.
$ScriptVersion = "v5.2.0"
#Today's date and time.
$Date = Get-Date -Format "MM-dd-yyyy-HH-mm-ss"
#Destination for application logs.
$LogFilePath = "C:\temp\Logs\" + $Date + "" + "-" + $env:USERNAME + "-Mount-Logs.log"
#Grabs the current domain name of the AD domain.
$Domain = [System.Directoryservices.ActiveDirectory.Domain]::GetCurrentDomain() | ForEach-Object { $_.Name }
#Path to the drive mapping file.
$File = "\\" + $Domain + "\sysvol\" + "\$Domain\scripts\client-drives.csv"
#IP address of the StorageSync device.
$StorageSync = "192.168.1.1"


function Mount-Drives {
    <#
    .Synopsis
    Map and connect each drive in the array.
    .Parameter DriveList
    Accepts an array of drives and then maps them.
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
            Write-Host "$(Get-Date): Mapping $($Drive.DriveName) to $($Drive.DriveLetter)" -ForegroundColor Green
            $Arguments = @{
                Name        = "$($Drive.DriveLetter)"
                PSProvider  = "FileSystem"
                Root        = "$($Drive.DrivePath)"
                Persist     = $True
                Description = "$($Drive.DriveName)"
                Scope       = "Global"
            }
            New-PSDrive @Arguments | Out-Null
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
                    $Root = Get-PSDrive | Where-Object { $_.DisplayRoot -match $StorageSync -and $_.Name -eq $Drive.DriveLetter }
                    if (!$Root) {
                        Write-host "$(Get-Date): $($Drive.DriveName) is not mapped to Egnyte. Unmapping now."
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
            Throw "There was an unrecoverable error: $($_.Exception.Message)"
        }
    }
}
#Begins the logging process to capture all output.
Start-Transcript -Path $LogFilePath -Force
Write-Host "$(Get-Date): Successfully started $App $ScriptVersion on $env:computername"
#Imports the mapping file into the script.
$Drives = Import-Csv -Path $File
#Tests the paths to see if they are already mapped or not and maps them if needed.
Test-Paths -DriveList $Drives
#Ends the logging process.
Stop-Transcript
#Terminates the script.
exit