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

$Choco = $env:ProgramData + "\chocolatey\chocolateyinstall\chocolatey.ps1"
$Cup = $env:ProgramData + "\chocolatey\bin\cup.exe"
If (Test-Path $Choco) {
	Write-Host "Chocolatey is installed. Checking for new versions."
	$ErrorActionPreference = 'Stop'
	Try {
		&$Cup
	} Catch {
		$ErrorActionPreference = 'Continue'
		Write-Host "ERROR: Updating Chocolatey failed with error:"
		Write-Host $_.Exception.Message
		Exit 1001
	}
	$ErrorActionPreference = 'Continue'

} Else {
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
		$ErrorActionPreference = 'Continue'
		Write-Host "ERROR: Installation succeeded, but Chocolatey still not found! Exiting."
		Exit 1001
	}
}

Write-Host "Verifying package installation:"

$ErrorActionPreference = 'Stop'
Try {
	# The magic bit: Source chocolatey.ps1, don't fork processes with choco.exe.
	. $Choco install @Packages
} Catch {
	$ErrorActionPreference = 'Continue'
	Write-Host "ERROR: Package installation failed with error:"
	Write-Host $_.Exception.Message
	Exit 1001
}
Exit 0