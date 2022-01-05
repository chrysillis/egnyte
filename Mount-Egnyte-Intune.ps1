#Requires -Version 5.1
<#
.Synopsis
Mounts Egnyte network drives.
.Description
This script mounts Egnyte network drives based on group membership in Azure Active Directory.
Feed it a CSV file with all of the drive mappings and it will handle the rest.
.Example
.\Mount-Egnyte-AD.ps1 without administrator rights.
.Notes
Author: Chrysillis Collier
Email: ccollier@micromenders.com
#>


#Defines global variables for installing the app
$default = "C:\Program Files (x86)\Egnyte Connect\EgnyteClient.exe"
$app = "Egnyte Desktop App"
$version = "v5.1.5"
$date = Get-Date -Format "MM-dd-yyyy"
$logfilepath = "C:\temp\Egnyte Logs\" + $date + "" + "-" + $env:USERNAME + "-Egnyte-Mount-Logs.log"

function Get-Mapping {
    <#
    .Synopsis
    Downloads the mapping file.
    .Parameter URL
    Input the URL to the mapping file. Must be publicly accessible.
    #>
    [CmdletBinding(DefaultParameterSetName = "URL")]
    [OutputType([String], ParameterSetName = "URL")]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = "URL")]
        [ValidateNotNullOrEmpty()]
        [String]
        $URL
    )
    process {
        try {
            if (-Not (Test-Path -Path "C:\Deploy")) {
                Write-Verbose -Message "Creating new directory."
                New-Item -ItemType Directory -Force -Path C:\Deploy
            }
            $outpath = "C:\Deploy\client-drives.csv"
            Write-Host "$(Get-Date): Downloading files to $outpath..."
            $job = Measure-Command { (New-Object System.Net.WebClient).DownloadFile($URL, $outpath) }
            $jobtime = $job.TotalSeconds
            $timerounded = [math]::Round($jobtime)
            if (Test-Path $outpath) {
                Write-Host "$(Get-Date): Files downloaded successfully in $timerounded seconds...."		
            }
            else {
                Write-Host "$(Get-Date): Download failed, please check your connection and try again..." -ForegroundColor Red
                Remove-Item "C:\Deploy" -Force -Recurse
                exit
            }        
        }
        catch {
            Throw "There was an unrecoverable error: $($_.Exception.Message). Unable to download mapping file."
        }
    }
}
function Get-Groups {
    #Define data to connect to Microsoft Graph API
    $AppID = '556e5c74-4c46-4922-9743-d8e6931a3c2d'
    $AppSecret = 'Ef9Ed9DUX48yrc_~msDPm~Vg0bI_4YnL7.'
    $Scope = "https://graph.microsoft.com/.default"
    $TenantName = "AmericanInfrastructureFunds.onmicrosoft.com"
    $GraphURL = "https://login.microsoftonline.com/$TenantName/oauth2/v2.0/token"

    #Add System.Web for urlencode
    Add-Type -AssemblyName System.Web

    #Create body
    $Body = @{
        client_id = $AppId
	    client_secret = $AppSecret
	    scope = $Scope
	    grant_type = 'client_credentials'
    }

    #Splat the parameters for Invoke-Restmethod for cleaner code
    $PostSplat = @{
        ContentType = 'application/x-www-form-urlencoded'
        Method = 'POST'
        #Create string by joining bodylist with '&'
        Body = $Body
        Uri = $GraphUrl
    }

    #Request the token!
    Write-Host "$(Get-Date): Connecting to Microsoft Graph..."
    $Request = Invoke-RestMethod @PostSplat

    #Create header
    $Header = @{
        'Authorization' = "$($Request.token_type) $($Request.access_token)"
        'Content-Type' = "application/json"
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
        Write-Host "$(Get-Date): There was an error: $($_.Exception.Message). Unable to confirm if $app is running or not, attempting to start $app by force."
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
                    "-d $($Drive.DomainName)"
                    "-sso use_sso"
                    "-t $($Drive.DriveLetter)"
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
            Throw "There was an unrecoverable error: $($_.Exception.Message). Unable to map or connect drives."
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
            Write-Host "$(Get-Date): Successfully started $app mounting script $version on $env:computername"
            Write-Host "$(Get-Date): Checking if $app is running before continuing..."
            Start-Egnyte
            Write-Host "$(Get-Date): Checking to see if the paths are already mapped..."
            $GroupMember = Get-Groups
            foreach ($Drive in $DriveList) {
                $CheckMembers = $GroupMember -contains $Drive.GroupID
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
            Throw "There was an unrecoverable error: $($_.Exception.Message). Unable to connect to AD to check membership."
        }
        finally {
            Remove-Item "C:\Deploy" -Force -Recurse
            Stop-Transcript
            exit
        }
    }
}
Start-Transcript -Path $logfilepath -Force
Get-Mapping -URL "https://aimlp.blob.core.windows.net/egnyte/client-drives.csv"
$Drives = Import-Csv -Path "C:\Deploy\client-drives.csv"
Test-Paths -DriveList $Drives