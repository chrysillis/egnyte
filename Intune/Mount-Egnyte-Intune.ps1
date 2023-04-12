<#
.Synopsis
    Mounts Egnyte network drives.

.Description
    This script mounts Egnyte network drives based on group membership in Azure Active Directory.
    Utilizes a CSV file with all of the drive mappings and group names located in an Azure Storage Account.

.Example
    .\Mount-Egnyte-Intune.ps1 without administrator rights.

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
$ScriptVersion = "v5.3.2"
#Script name
$App = "Egnyte Drive Mapping"
#Application installation path
$Default = "C:\Program Files (x86)\Egnyte Connect\EgnyteClient.exe"
#Remote location of the mappings
$RemoteFile = "https://contoso.blob.core.windows.net/storage/client-drives-intune.csv"
#Local location of the mappings
$LocalFile = "C:\Deploy\Egnyte\Client-Drives-Intune.csv"
#Egnyte tenant name
$Tenant = "contoso"
#Today's date
$Date = Get-Date -Format "MM-dd-yyyy-HH-mm-ss"
#Destination to store logs
$LogFilePath = "C:\Logs\Egnyte\" + $Date + "" + "-" + $env:USERNAME + "-Mount-Logs.log"
#Defines the data needed to connect to the Microsoft Graph API
$AppID = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
$AppSecret = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
$Scope = "https://graph.microsoft.com/.default"
$TenantName = "contoso.onmicrosoft.com"
$GraphURL = "https://login.microsoftonline.com/$TenantName/oauth2/v2.0/token"

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
function Get-Mappings {
    <#
    .Synopsis
    Downloads the mapping file.
    .Parameter URL
    Input the URL to the mapping file. Must be publicly accessible.
    #>
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $URL
    )
    process {
        try {
            if (-Not (Test-Path -Path "C:\Deploy")) {
                Write-Host -Message "Creating new log folder."
                New-Item -ItemType Directory -Force -Path C:\Deploy | Out-Null
            }
            Write-Host "$(Get-Date): Downloading files to $LocalFile..."
            $job = Measure-Command { Start-BitsTransfer -Source $URL -Destination $LocalFile -DisplayName "Scripts" }
            $jobtime = $job.TotalSeconds
            $timerounded = [math]::Round($jobtime)
            if (Test-Path $LocalFile) {
                Write-Host "$(Get-Date): Files downloaded successfully in $timerounded seconds...."		
            }
            else {
                Write-Host "$(Get-Date): Download failed, please check your connection and try again..." -ForegroundColor Red
                Remove-Item "C:\Deploy" -Force -Recurse
                exit
            }        
        }
        catch {
            Throw "Unable to download mapping file: $($_.Exception.Message)"
        }
    }
}
function Get-Groups {
    #Add System.Web for urlencode
    Add-Type -AssemblyName System.Web

    #Create body
    $Body = @{
        client_id     = $AppId
        client_secret = $AppSecret
        scope         = $Scope
        grant_type    = 'client_credentials'
    }

    #Splat the parameters for Invoke-Restmethod for cleaner code
    $PostSplat = @{
        ContentType = 'application/x-www-form-urlencoded'
        Method      = 'POST'
        #Create string by joining bodylist with '&'
        Body        = $Body
        Uri         = $GraphUrl
    }

    #Request the token!
    Write-Host "$(Get-Date): Connecting to Microsoft Graph..."
    $Request = Invoke-RestMethod @PostSplat

    #Create header
    $Header = @{
        'Authorization' = "$($Request.token_type) $($Request.access_token)"
        'Content-Type'  = "application/json"
    }
    #Define user ID to check for group memberships
    $userID = whoami.exe /upn
    Write-Host "$(Get-Date): Currently logged on user found is $userID..."

    #Graph URL to run check against
    $Uri = "https://graph.microsoft.com/v1.0/users/$userID/getMemberGroups"

    #Define JSON payload
    $Payload = @'
    {
        "securityEnabledOnly": false
    }
'@

    #Fetch group membership
    Write-Host "$(Get-Date): Grabbing list of group memberships..."
    $GroupMemberRequest = Invoke-RestMethod -Uri $Uri -Headers $Header -Method 'Post' -Body $Payload
    $GroupMemberRequest.Value
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
            $GroupMember = Get-Groups
            foreach ($Drive in $DriveList) {
                $DriveLetter = "$($Drive.DriveLetter)" + ":"
                $PathTest = Test-Path -Path $DriveLetter
                if ($GroupMember -contains $Drive.GroupID) {
                    if (!$PathTest) {
                    Write-Host "$(Get-Date): $($Drive.DriveName) not found. Mapping now."
                    Mount-Drives -Drive $Drive
                }
                elseif ($PathTest) {
                    Write-Host "$(Get-Date): $($Drive.DriveName) is already mapped."
                    $Root = Get-PSDrive | Where-Object { $_.DisplayRoot -match "EgnyteDrive" -and $_.Name -eq $Drive.DriveLetter }
                    if (!$Root) {
                        Write-host "$(Get-Date): $($Drive.DriveName) is not mapped to the cloud. Unmapping now."
                        net use $DriveLetter /delete
                        Mount-Drives -Drive $Drive
                    }
                }
            }
            elseif ($GroupMember -notcontains $Drive.GroupID) {
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
Get-Mappings -URL $RemoteFile
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