<#
.Synopsis
   Installs software silently on servers and workstations using Chocolatey.
.DESCRIPTION
   The script is to be uploaded to your dashboard account as a user script.
   It can run both as a script check and as a scheduled task. You list package 
   names as parameter to script. Chocolatey will update packages that are 
   already installed. 
   
   Warning: If you later omit a package name it will NOT be uninstalled!
.EXAMPLE
   Install-ApplicationsFromMAXfocus notepadplusplus adobereader
.EXAMPLE
   Install-ApplicationsFromMAXfocus dropbox googlechrome
.EXAMPLE
   Install-ApplicationsFromMAXfocus google-chrome-x64
.OUTPUTS
   Installed applications and text log
.LINK
   http://klemmestad.com/2015/01/15/install-and-update-software-with-maxfocus-and-chocolatey/
.LINK
   https://chocolatey.org
.LINK
   https://chocolatey.org/packages
.EMAIL
   hugo@klemmestad.com
.VERSION
   1.0
#>


# We are only binding -logfile. Leave the rest unbound.
param (	
	# Make sure -logfile is NOT positional
	[Parameter(Mandatory=$false)]
	[string]$logfile = 'ScriptMicrosoftUpdate.log',
	
	# Capture entire parameterlist, save -logfile, as Packages
	[Parameter(Position=0,ValueFromRemainingArguments=$true)]
	[array]$Packages
)

If (-not ($Packages)) {
	Write-Host "No packages selected."
	Write-Host "USAGE:"
	Write-Host "List package names as parameter to Check or Task."
	Write-Host "See https://chocolatey.org/packages for available packages."
	Exit 1001
}

#Region Functions

function Restart-MAXfocusService ([bool]$Safely=$true) {
	If ($Safely) {	
		# Update last runtime to prevent changes too often
		[int]$currenttime = $(get-date -UFormat %s) -replace ",","." # Handle decimal comma 
		$settingsContent["DAILYSAFETYCHECK"]["RUNTIME"] = $currenttime
	}
	# Clear lastcheckday to make DSC run immediately
	$settingsContent["DAILYSAFETYCHECK"]["LASTCHECKDAY"] = "0"
	Out-IniFile $settingsContent $IniFile
		
	# Prepare restartscript
	$RestartScript = $env:TEMP + "\RestartMAXfocusAgent.cmd"
	$RestartScriptContent = @"
net stop "Advanced Monitoring Agent"
net start "Advanced Monitoring Agent"
Del /F $RestartScript
"@
	$RestartScriptContent | Out-File -Encoding OEM $RestartScript
	# Start time in the future
	$JobTime = (Get-Date).AddMinutes(-2)
	$StartTime = Get-Date $JobTime -Format HH:mm
	$TaskName = "Restart Advanced Monitoring Agent"
	$Result = &schtasks.exe /Create /TN $TaskName /TR "$RestartScript" /RU SYSTEM /SC ONCE /ST $StartTime /F
	If ($Result) {
		Output-Debug "Restarting Agent using scheduled task now."
		$Result = &schtasks.exe /run /TN "$TaskName"
	} 
		
	If (!($Result -like 'SUCCESS:*')) {
		Output-Debug "SCHTASKS.EXE failed. Restarting service the hard way."
		Restart-Service 'Advanced Monitoring Agent'
	}
	
	
}



# Downloaded from 
# http://blogs.technet.com/b/heyscriptingguy/archive/2011/08/20/use-powershell-to-work-with-any-ini-file.aspx
# modified to use ordered list by me
function Get-IniContent ($filePath) {
    $ini = New-Object System.Collections.Specialized.OrderedDictionary
    switch -regex -file $FilePath
    {
        "^\[(.+)\]" # Section
        {
			$section = $matches[1]
            $ini[$section] = New-Object System.Collections.Specialized.OrderedDictionary
            $CommentCount = 0
        }
        "^(;.*)$" # Comment
        {
            $value = $matches[1]
            $CommentCount = $CommentCount + 1
            $name = "Comment" + $CommentCount
            $ini[$section][$name] = $value
        } 
        "(.+?)\s*=(.*)" # Key
        {
            $name,$value = $matches[1..2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}
# Downloaded from 
# http://blogs.technet.com/b/heyscriptingguy/archive/2011/08/20/use-powershell-to-work-with-any-ini-file.aspx
# Modified to force overwrite by me
function Out-IniFile($InputObject, $FilePath) {
    $outFile = New-Item -ItemType file -Path $Filepath -Force
    foreach ($i in $InputObject.keys)
    {
        if ("Hashtable","OrderedDictionary" -notcontains $($InputObject[$i].GetType().Name))
        {
            #No Sections
            Add-Content -Path $outFile -Value "$i=$($InputObject[$i])"
        } else {
            #Sections
            Add-Content -Path $outFile -Value "[$i]"
            Foreach ($j in ($InputObject[$i].keys | Sort-Object))
            {
                if ($j -match "^Comment[\d]+") {
                    Add-Content -Path $outFile -Value "$($InputObject[$i][$j])"
                } else {
                    Add-Content -Path $outFile -Value "$j=$($InputObject[$i][$j])" 
                }

            }
            Add-Content -Path $outFile -Value ""
        }
    }
}


#EndRegion Functions

# Find "Advanced Monitoring Agent" service and use path to locate files
$gfimaxagent = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq 'Advanced Monitoring Agent' }
$gfimaxexe = $gfimaxagent.PathName
$gfimaxpath = Split-Path $gfimaxagent.PathName.Replace('"',"") -Parent

#Region Setup Run Environment
# Package installation requires Desktop Interaction for quite a few packages
# Desktop interaction for services requires the UI0Detect service to run

# Get service
$ServiceName = 'UI0Detect'
$interactiveservice = Get-WmiObject Win32_Service | Where { $_.Name -eq $ServiceName }

# Make sure interactive services are allowed
$InteractiveSetting = $(Get-ItemProperty $(Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Windows').PSPath).NoInteractiveServices
If ($InteractiveSetting -eq 1) {
	Set-ItemProperty $($(Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Windows').PSPath) -name NoInteractiveServices -value 0 -Force
}

# Make sure startup mode is automatic
If ($interactiveservice.StartMode -ne 'Auto') {
	$result = $interactiveservice.Change($null,$null,$null,$null,'Automatic')
	If ($result.ReturnValue -ne 0) {
		Write-Host 'ERROR: Could not set Interactive Service Detection servie to Automatic start.'
		Write-Host 'You can make this change from Remote Background in Dashboard and this script'
		Write-host 'will continue next time it runs.'
		Write-Host 'Exiting.'
		Exit 1001
	}
}

#  Refresh service and make sure service is running
$interactiveservice = Get-WmiObject Win32_Service | Where { $_.Name -eq $ServiceName }
If ($interactiveservice.State -ne 'Running') {
	Start-Service -Name $ServiceName
}

## Modify environment to support application install from User System
#  Set Shell folders to correct values for application install
#  If Shell folders must be modified the agent must be restarted
#  The point of the changes is to make pr user installations 
#  put icons and files where the user can see and reach them.

$RestartNeeded = $false
Push-Location # Save current location
cd "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
Foreach ($Property in (Get-Item . | Select -ExpandProperty Property)) {
	$NewValue = ''
	Switch ($Property) {
		'Desktop' 			{ $NewValue = '{0}\Desktop' -f $Env:PUBLIC }
		'Personal' 			{ $NewValue = '{0}\Documents' -f $Env:PUBLIC }
		'My Music'			{ $NewValue = '{0}\Music' -f $Env:PUBLIC }
		'My Pictures'		{ $NewValue = '{0}\Pictures' -f $Env:PUBLIC }
		'My Video'			{ $NewValue = '{0}\Videos' -f $Env:PUBLIC }
		'Favorites'			{ $NewValue = '{0}\Favorites' -f $Env:PUBLIC }
		'Local AppData'		{ $NewValue = '{0}\Chocolatey\' -f $Env:ALLUSERSPROFILE }
		'AppData'			{ $NewValue = '{0}' -f $Env:ALLUSERSPROFILE }
		'Start Menu'		{ $NewValue = '{0}\Microsoft\Windows\Start Menu' -f $Env:ALLUSERSPROFILE }
		'Programs'			{ $NewValue = '{0}\Microsoft\Windows\Start Menu\Programs' -f $Env:ALLUSERSPROFILE }
		'Startup'			{ $NewValue = '{0}\Microsoft\Windows\Start Menu\Programs\Startup' -f $Env:ALLUSERSPROFILE }
	}
	$OldValue = (Get-ItemProperty . -Name $Property).($Property)
	If (($NewValue) -and ($NewValue -ne $OldValue )) {
		Set-ItemProperty -Path . -Name $Property -Value $NewValue -Force
		$RestartNeeded = $true
	}
	
}
If ($RestartNeeded) {
	Write-Host 'Application install enviroment has been modified.'
}
Pop-Location # Return to scripts directory

# Make sure Desktopinteract is enabled for max agent. If it isn't the
# service must unfortunately be restarted and this job resumed later
If (!$gfimaxagent.DesktopInteract) {
	$result = $gfimaxagent.Change($null,$null,$null,$null,$null,$true)
	If ($result.ReturnValue -eq 0) {
		Write-Host 'Enabled Desktop Interact for Advanced Monitoring Agent OK.'
		$RestartNeeded = $true
	} Else {
		Write-Host 'Failed to enable Desktop Interact for Advanced Monitoring Agent.'
		Write-Host 'Exiting...'
		Exit 1001
	}
}

## Check if service must be restarted
If ($RestartNeeded) {
	Write-Host 'Service needs a restart before setting takes effect.'
	Write-Host 'Restarting Now.'
	Write-Host 'WARNING: Software installation will NOT happen until next run!'
	Restart-MAXfocusService
	Exit 0
}

#EndRegion

#force this to run in 32 bit

if ($env:Processor_Architecture -ne "x86") {

    Write-Host "Switching to x86 PowerShell..."
 
	&"$env:WINDIR\syswow64\windowspowershell\v1.0\powershell.exe" -ExecutionPolicy bypass  -NoProfile $myInvocation.Line
    exit $LASTEXITCODE
}



# Look for parameter '-uninstall'
# We can't have more than 1 non-positional parameter
$ParsedArray = @()
$Uninstall = $false
Foreach ($Package in $Packages) {
	If ($Package -eq '-uninstall') {
		$Uninstall = $true
	} Else {
		$ParsedArray += $Package
	}
}

$Packages = $ParsedArray

$inifile = $gfimaxpath + '\settings.ini'
$settings = Get-IniContent $inifile

If (!($Settings['CHOCOLATEY'])) {
	$Settings['CHOCOLATEY'] = @{}
}

# Chocolatey commands
$Choco = $env:ProgramData + "\chocolatey\chocolateyinstall\chocolatey.ps1"

#Region Install Chocolatey if necessary
If (!(Test-Path $Choco)) {
	Write-Host "Chocolatey not installed. Trying to install."
	$ErrorActionPreference = 'Stop'
	Try {
		iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
	} Catch {
		$ErrorActionPreference = 'Continue'
		Write-Host "ERROR: Installing Chocolatey failed with error:"
		Write-Host $_.Exception.Message
		Exit 1001
	}
	$ErrorActionPreference = 'Continue'
	If (Test-Path $Choco) {
		Write-Host "Chocolatey is installed. Proceeding."
	} Else {
		Write-Host "ERROR: Installation succeeded, but Chocolatey still not found! Exiting."
		Exit 1001
	}
}
#EndRegion

Write-Host "Verifying package installation:"

If ($Uninstall) {
	# Make a copy of installed packages as the hashtable cannot be changed while
	# using it as base for a foreach loop
	$packageList = @()
	Foreach ($InstalledPackage in $settings['CHOCOLATEY'].Keys) {
		$Packagelist += $InstalledPackage.ToString()
	}
	
	# Loop through copy of hashtable keys, updating hashtable if necessary
	Foreach ($InstalledPackage in $Packagelist) {
		$ErrorActionPreference = 'Stop'
		Try {
			If ($Packages -notcontains $InstalledPackage) {
				. $Choco uninstall $InstalledPackage
			}
			$settings['CHOCOLATEY'].Remove($Package)
			Out-IniFile $settings $inifile 
		} Catch {
			$ErrorActionPreference = 'Continue'
			Write-Host ("ERROR: Package {0} uninstallation failed with error:" -f $Package)
			Write-Host $_.Exception.Message
		}
		$ErrorActionPreference = 'Continue'
	}
}

# Get installed packages and separate package name from version
$InstalledPackages = ( &choco list -localonly)
$InstalledList = @{}
Foreach ($InstalledPackage in $InstalledPackages) {
	$Package = $InstalledPackage.Split(' ')
	$InstalledList[$Package[0]] = $Package[1]
}

# Loop through package names given to us from command line
$InstallPackages = @()
Foreach ($Package in $Packages) {
	# Maintain installed package list in agent settings.ini
	If ($Settings['CHOCOLATEY'][$Package] -notmatch '\d\d\.\d\d\.\d{4}') {
		$Settings['CHOCOLATEY'][$Package] = Get-Date -Format 'dd.MM.yyyy'
		Out-IniFile $settings $inifile 
	}
	If (!($InstalledList.ContainsKey($Package))) {
		$InstallPackages += $Package
	}
}

Write-Host 'Updating All'
Try {
	$ErrorActionPreference = 'Stop'
	. $choco update all
} Catch {
	$ErrorActionPreference = 'Continue'
	Write-Host "ERROR: Update failed with error:"
	Write-Host $_.Exception.Message
}
	Write-Host ('Installing packages {0}' -f $InstallPackages)
If ($InstallPackages.Count -gt 0) {	
	Try {
		$ErrorActionPreference = 'Stop'
		. $choco install @InstallPackages
	} Catch {
		$ErrorActionPreference = 'Continue'
		Write-Host "ERROR: Package installation failed with error:"
		Write-Host $_.Exception.Message
	}
}

Exit 0