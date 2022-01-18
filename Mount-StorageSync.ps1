#Requires -Version 5.1
<#
.Synopsis
    Mounts Egnyte network drives.

.Description
    This script mounts Egnyte network drives based on group membership in Active Directory.
    Utilizes a CSV file with all of the drive mappings and group names located in the SYSVOL directory.

.Example
    .\Mount-Egnyte-AD.ps1 without administrator rights.

.Outputs
    Log files stored in C:\Logs\Egnyte.

.Notes
    Author: Chrysi
    Link:   https://github.com/DarkSylph/egnyte
    Date:   01/12/2022
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Requires -Version 5.1

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script version
$ScriptVersion = "v5.2.1"
#Script name
$App = "Egnyte Drive Mapping"
#Finds the current Active Directory domain
$Domain = [System.Directoryservices.ActiveDirectory.Domain]::GetCurrentDomain() | ForEach-Object { $_.Name }
#Location of the mappings
$File = "\\" + $Domain + "\sysvol\" + "\$Domain\scripts\client-drives.csv"
#Today's date
$Date = Get-Date -Format "MM-dd-yyyy-HH-mm-ss"
#Destination to store logs
$LogFilePath = "C:\Logs\Egnyte\" + $Date + "" + "-" + $env:USERNAME + "-Mount-Logs.log"
#IP address of the StorageSync device
$StorageSync = "192.168.1.1"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

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
            foreach ($Drive in $DriveList) {
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
        }
        catch {
            Throw "Unable to map or connect drives: $($_.Exception.Message)"
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
                $CheckMembers = $GroupMember -contains $Drive.GroupName
                $DiscDrives = Get-CimInstance -Class Win32_NetworkConnection | Where-Object {$_.ConnectionState -eq "Disconnected" }
                if ((Test-Path -Path "$($Drive.DriveLetter):") -Or ($DiscDrives)) {
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
            Throw "Could not map drives: $($_.Exception.Message)"
        }
    }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Sets up a destination for the logs
if (-Not (Test-Path -Path "C:\Logs")) {
    Write-Host -Message "Creating new log folder."
    New-Item -ItemType Directory -Force -Path C:\Logs | Out-Null
}
if (-Not (Test-Path -Path "C:\Logs\Egnyte")) {
    Write-Host -Message "Creating new log folder."
    New-Item -ItemType Directory -Force -Path C:\Logs\Egnyte | Out-Null
}
#Begins the logging process to capture all output
Start-Transcript -Path $LogFilePath -Force
Write-Host "$(Get-Date): Successfully started $App $ScriptVersion on $env:computername"
#Imports the mapping file into the script
$Drives = Import-Csv -Path $File
#Tests the paths to see if they are already mapped or not and maps them if needed
Test-Paths -DriveList $Drives
#Ends the logging process
Stop-Transcript
#Terminates the script
exit