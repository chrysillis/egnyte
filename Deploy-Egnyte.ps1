<#
.Synopsis
    Install Egnyte Desktop Client.

.Description
    Deploys the Egnyte Desktop Client if it isn't installed or updates it if it is out of date.
    It parses the website to automatically download the latest version of the software, always staying up to date.
    After handling the Egnyte client, it then creates a scheduled task to launch another script to handle mapping the drives.

.Example
    .\Deploy-Egnyte.ps1

.Outputs
    Log files stored in C:\Logs\Egnyte.

.Notes
    Author: Chrysi
    Link:   https://github.com/DarkSylph/egnyte
    Date:   01/12/2022
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Requires -Version 5.1
#Requires -RunAsAdministrator

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script version
$ScriptVersion = "v5.2.1"
#Script name
$App = "Egnyte Desktop App"
#Application installation path
$Default = "C:\Program Files (x86)\Egnyte Connect\EgnyteClient.exe"
#Application registry version
$Registry = Get-ItemProperty HKLM:\Software\WOW6432Node\Egnyte\* -ErrorAction SilentlyContinue | Select-Object setup.msi.version.product
#Finds the current Active Directory domain
$Domain = [System.Directoryservices.ActiveDirectory.Domain]::GetCurrentDomain() | ForEach-Object { $_.Name }
#Location of the mapping script
$File = "\\" + $domain + "\sysvol\" + "\$domain\scripts\Mount-Egnyte-AD.ps1"
#Today's date
$Date = Get-Date -Format "MM-dd-yyyy-HH-mm-ss"
#Destination to store logs
$LogFilePath = "C:\Logs\Egnyte\" + $date + "-Install-Logs.log"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Get-EgnyteUrl {
    <#
    .Synopsis
    Grabs the latest Egnyte download URL and outputs it into a readable format.
    #>
    process {
        Try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $URL = (Invoke-WebRequest -UseBasicParsing -Uri "https://helpdesk.egnyte.com/hc/en-us/articles/205237150").Links.Href | Select-String -Pattern '.msi'
            $Version = $URL.ToString()
            $i = $Version.IndexOf("_")
            $Version = $Version.Substring($i + 1) -replace "_", "."
            $Version = $Version -replace ".msi", ""
            $websiteObject = [PSCustomObject]@{
                URL     = $URL
                Version = $Version
            }
        }
        Catch {
            Throw "Cannot display results: $($_.Exception.Message)"
        }
        Return $websiteObject
    }
}
function New-PSTask {
    <#
    .Synopsis
    Creates a new scheduled task that starts a Powershell script under the currently logged on user.
    .Parameter File
    Input the filepath to the script you want the task to execute
    #>
    [CmdletBinding(DefaultParameterSetName = "Path")]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = "Path")]
        [ValidateNotNullOrEmpty()]
        [String]
        $Path
    )
    process {
        try {
            $Task = Get-ScheduledTask -TaskName "Map Network Drives"
            if ($Task) {
                Write-Host "Task already exists, starting now."
                Start-ScheduledTask -TaskName "Map Network Drives"    
            }
            else {
                $TaskDetails = @{
                    Action      = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument $Path
                    Principal   = New-ScheduledTaskPrincipal -GroupId "NT AUTHORITY\Interactive"
                    Settings    = New-ScheduledTaskSettingsSet -DontStopOnIdleEnd -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Parallel
                    TaskName    = "Map Network Drives"
                    Description = "Maps network drives through the Egnyte Desktop App."
                }
                Register-ScheduledTask @TaskDetails -Force
                Start-ScheduledTask -TaskName "Map Network Drives"
            }
        }
        catch {
            Throw "Could not create the task: $($_.Exception.Message)"
        }
    }
}
function Install-Egnyte {
    <#
    .Synopsis
    Installs the Egnyte Desktop App
    .Description
    After downloading the software, it adds two new firewall rules and then proceeds to install Egnyte.
    .Parameter File
    Inputs the file path to the Egnyte drive mapping script for the client.
    #>
    $Download = Get-EgnyteUrl
    if (-Not (Test-Path -Path "C:\Deploy")) {
        Write-Verbose -Message "Creating new deploy folder."
        New-Item -ItemType Directory -Force -Path C:\Deploy
    }
    $outpath = "C:\Deploy\EgnyteDesktopApp.msi"
    Write-Host "$(Get-Date): Downloading files to $outpath..."
    $job = Measure-Command { (New-Object System.Net.WebClient).DownloadFile($Download.URL, $outpath) }
    $jobtime = $job.TotalSeconds
    $timerounded = [math]::Round($jobtime)
    if (Test-Path $outpath) {
        Write-Host "$(Get-Date): Files downloaded successfully in $timerounded seconds. Now starting setup..."		
    }
    else {
        Write-Host "$(Get-Date): Download failed, please check your connection and try again..." -ForegroundColor Red
        Remove-Item "C:\Deploy" -Force -Recurse
        exit
    }
    Write-Host "$(Get-Date): Updating firewall rules for $app..."
    $firewallrule1 = @{
        DisplayName = "Egnyte TCP"
        Description = "Egnyte Desktop App"
        Direction   = "Inbound"
        Program     = "C:\Program Files (x86)\Egnyte Connect\EgnyteDrive.exe"
        Profile     = "Any"
        Action      = "Allow"
        Protocol    = "TCP"
    }
    $firewallstatus = New-NetFirewallRule @firewallrule1
    Write-Host $firewallstatus.status
    $firewallrule2 = @{
        DisplayName = "Egnyte UDP"
        Description = "Egnyte Desktop App"
        Direction   = "Inbound"
        Program     = "C:\Program Files (x86)\Egnyte Connect\EgnyteDrive.exe"
        Profile     = "Any"
        Action      = "Allow"
        Protocol    = "UDP"
    }
    $firewallstatus = New-NetFirewallRule @firewallrule2
    Write-Host $firewallstatus.status
    Write-Verbose -Message "Starting install process..."
    $arguments = '/i C:\Deploy\EgnyteDesktopApp.msi ED_SILENT=1 /passive'
    $process = Start-Process -PassThru -FilePath msiexec -Verb RunAs -ArgumentList $arguments
    $process.WaitForExit()
    Start-Sleep -Seconds 5
    if (Test-Path $default) {
        Write-Host "$(Get-Date): $app installed successfully on $env:computername! Proceeding to map drives..." -ForegroundColor Green
        Remove-Item "C:\Deploy" -Force -Recurse
        New-PSTask -Path $File
    }
    else {
        Write-Host "$(Get-Date): $app failed to install on $env:computername. Please try again. Cleaning up downloaded files..." -ForegroundColor Red
        Remove-Item "C:\Deploy" -Force -Recurse
        exit
    }
}
function Update-Egnyte {
    <#
    .Synopsis
    Updates the Egnyte Desktop App to the latest version.
    .Description
    Uninstalls the previous version of Egnyte before installing the new version to ensure the new version installs successfully.
    #>
    $Download = Get-EgnyteUrl
    if (-Not (Test-Path -Path "C:\Deploy")) {
        Write-Verbose -Message "Creating new directory."
        New-Item -ItemType Directory -Force -Path C:\Deploy | Out-Null
    }
    $outpath = "C:\Deploy\EgnyteDesktopApp.msi"
    Write-Host "$(Get-Date): Downloading files to $outpath..."
    $job = Measure-Command { (New-Object System.Net.WebClient).DownloadFile($Download.URL, $outpath) }
    $jobtime = $job.TotalSeconds
    $timerounded = [math]::Round($jobtime)
    if (Test-Path $outpath) {
        Write-Host "$(Get-Date): Files downloaded successfully in $timerounded seconds. Now starting setup..."		
    }
    else {
        Write-Host "$(Get-Date): Download failed, please check your connection and try again..." -ForegroundColor Red
        Remove-Item "C:\Deploy" -Force -Recurse
        exit
    }
    $arguments2 = '/x C:\Deploy\EgnyteDesktopApp.msi /passive'
    Write-Verbose -Message "Uninstalling previous version now."
    $process = Start-Process -PassThru -FilePath msiexec -Verb RunAs -ArgumentList $arguments2
    $process.WaitForExit()
    Start-Sleep -Seconds 5
    Write-Verbose -Message "Starting install process for new version."
    $arguments = '/i C:\Deploy\EgnyteDesktopApp.msi ED_SILENT=1 /passive'
    $process = Start-Process -PassThru -FilePath msiexec -Verb RunAs -ArgumentList $arguments
    $process.WaitForExit()
    Start-Sleep -Seconds 5
    if ($registry.'setup.msi.version.product' -eq $Download.version) {
        Write-Host "$(Get-Date): $app installed successfully on $env:computername! Proceeding to map drives..." -ForegroundColor Green
        Remove-Item "C:\Deploy" -Force -Recurse
        New-PSTask -File $File
    }
    else {
        Write-Host "$(Get-Date): $app failed to install on $env:computername. Please try again. Cleaning up downloaded files..." -ForegroundColor Red
        Remove-Item "C:\Deploy" -Force -Recurse
        exit
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
Start-Transcript -Path $logfilepath -Force
Write-Host "$(Get-Date): Successfully started $app install script $ScriptVersion on $env:computername"
Write-Host "$(Get-Date): Checking to see if $app is already installed..."
if (Test-Path $default) {
    Write-Host "$(Get-Date): $app is already installed, checking version..."
    $Download = Get-EgnyteUrl
    if ($registry.'setup.msi.version.product' -ge $Download.version) {
        Write-Host "$(Get-Date): $app is already up to date! Proceeding to map drives..."
        New-PSTask -Path $File
    }
    else {
        Write-Host "$(Get-Date): Version $($registry.'setup.msi.version.product') was found, proceeding to update to $($Download.Version)"
        Update-Egnyte
    }
}
Write-Host "$(Get-Date): $app was not found, installing now..."
Install-Egnyte
#Ends the logging process
Stop-Transcript
#Terminates the script
exit