<#
.Synopsis
    Install the Egnyte Desktop Client.

.Description
    Installs the Egnyte Desktop Client if it isn't installed.
    After installing the Egnyte client, it then creates a scheduled task to launch another script to handle mapping the drives.

.Example
    .\Deploy-Egnyte.ps1

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
$ScriptVersion = "v5.2.9"
#Application name
$Application = "Egnyte Desktop App"
#Application installation path
$DefaultPath = "C:\Program Files (x86)\Egnyte Connect\EgnyteClient.exe"
#Location of the mapping script
$MountingScriptPath = "C:\Deploy\Egnyte\Mount-Egnyte-AD.ps1"
#Today's date
$TodaysDate = Get-Date -Format "MM-dd-yyyy-HH-mm-ss"
#Destination to store logs
$LogFilePath = "C:\Logs\Egnyte\" + $TodaysDate + "-Install-Logs.log"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function New-PSTask {
    <#
    .Synopsis
    Creates a new scheduled task that starts a Powershell script under the currently logged on user.
    The mounting script must run as a regular user because it checks their security group memberships.
    .Parameter Path
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
            $Task = Get-ScheduledTask -TaskName "Map Egnyte Drives" -ErrorAction SilentlyContinue
            if ($Task) {
                Write-Host "$(Get-Date): Task already exists, removing now."
                Unregister-ScheduledTask -TaskName "Map Egnyte Drives" -Confirm:$false
            }
            Write-Host "$(Get-Date): Creating new scheduled task."
            $TaskDetails = @{
                Action      = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-noprofile -executionpolicy bypass -file $($Path)"
                Principal   = New-ScheduledTaskPrincipal -GroupId "NT AUTHORITY\Interactive"
                Settings    = New-ScheduledTaskSettingsSet -DontStopOnIdleEnd -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Parallel
                TaskName    = "Map Egnyte Drives"
                Description = "Maps Egnyte drives through the Egnyte Desktop App."
            }
            Register-ScheduledTask @TaskDetails -Force
            Write-Host "$(Get-Date): Finished registering task. Starting task now."
            Start-ScheduledTask -TaskName "Map Egnyte Drives"
            Stop-Transcript
            exit
        }
        catch {
            Throw "Could not create the task: $($_.Exception.Message)"
        }
    }
}
function Install-Egnyte {
    <#
    .Synopsis
    Downloads and installs the Egnyte Desktop App
    .Description
    After downloading the software, it adds two new firewall rules and then proceeds to install Egnyte Desktop App.
    #>
    $source = "https://egnyte-cdn.egnyte.com/egnytedrive/win/en-us/latest/EgnyteConnectWin.msi"
    $destination = "C:\Deploy\Egnyte\EgnyteDesktopApp.msi"
    Write-Host "$(Get-Date): Downloading files to $destination..."
    $job = Measure-Command { Start-BitsTransfer -Source $source -Destination $destination -DisplayName "Egnyte" }
    $jobtime = $job.TotalSeconds
    $timerounded = [math]::Round($jobtime)
    if (Test-Path $destination) {
        Write-Host "$(Get-Date): Files downloaded successfully in $timerounded seconds. Now starting setup..."		
    }
    else {
        Write-Host "$(Get-Date): Download failed, please check your connection and try again..." -ForegroundColor Red
        exit
    }
    Write-Host "$(Get-Date): Updating firewall rules for $Application..."
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
    $arguments = '/i C:\Deploy\Egnyte\EgnyteDesktopApp.msi ED_SILENT=1 /passive'
    $process = Start-Process -PassThru -FilePath msiexec -Verb RunAs -ArgumentList $arguments
    $process.WaitForExit()
    Start-Sleep -Seconds 5
    if (Test-Path $DefaultPath) {
        Write-Host "$(Get-Date): $Application installed successfully on $env:computername! Proceeding to map drives..." -ForegroundColor Green
    }
    else {
        Write-Host "$(Get-Date): $Application failed to install on $env:computername. Please try again. Cleaning up downloaded files..." -ForegroundColor Red
        exit
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
Write-Host "$(Get-Date): Successfully started $Application $ScriptVersion on $env:computername"
Write-Host "$(Get-Date): Checking to see if $Application is already installed..."
if (Test-Path $DefaultPath) {
    Write-Host "$(Get-Date): $Application is already installed..."
    New-PSTask -Path $MountingScriptPath
}
Write-Host "$(Get-Date): $Application was not found, installing now..."
Install-Egnyte
New-PSTask -Path $MountingScriptPath