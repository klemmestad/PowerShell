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

#Region Functions
# We are only binding -logfile. Leave the rest unbound.
param (	
	[Parameter(Mandatory=$false)]
	[string]$logfile = 'ScriptMicrosoftUpdate.log',
	[Parameter(Position=0,ValueFromRemainingArguments=$true)]
	[array]$Packages
)

$Debug = $true
$DebugPreference = 'Continue'

# Enhanced Output-Host function to capture log info
function Output-Host  {
	[string]$Text = ""
	Foreach ($arg in $args) { $Text += $arg }
	Write-Host $Text
	# Include normal output in debug log
	Output-Debug $Text
}


# Output text to $logfile if Debug set
function Output-Debug  {
	If ($Debug) {
		[string]$Text = ''
		Foreach ($arg in $args) { $Text += $arg }
		('{0}: {1}' -f (Get-Date),$Text) | Out-File -Append $logfile
	}
}

function get-buffer { 
  param( 
    [int]$last = 50000,             # how many lines to get, back from current position 
    [switch]$all                  # if true, get all lines in buffer 
    ) 
  $ui = $host.ui.rawui 
  [int]$start = 0 
  if ($all) {  
    [int]$end = $ui.BufferSize.Height   
    [int]$start = 0 
  } 
  else {  
    [int]$end = $ui.CursorPosition.Y  
    [int]$start = $end - $last 
    if ($start -le 0) { $start = 0 } 
  } 
  $width = $ui.BufferSize.Width 
  $height = $end - $start 
  $dims = 0,$start,($width-1),($end-1) 
  $rect = new-object Management.Automation.Host.Rectangle -argumentList $dims 
  $cells = $ui.GetBufferContents($rect) 
 
  $line  = ""  
  for ([int]$row=0; $row -lt $height; $row++ ) { 
    for ([int]$col=0; $col -lt $width; $col++ ) { 
      $cell = $cells[$row,$col] 
      $ch = $cell.Character 
      $line += $ch 
    } 
    $line.TrimEnd() # dump the line in the output pipe 
    $line="" 
  } 
} 

#EndRegion

If (-not ($Packages)) {
	Output-Host "No packages selected."
	Output-Host "USAGE:"
	Output-Host "List package names as parameter to Check or Task."
	Output-Host "See https://chocolatey.org/packages for available packages."
	Exit 1001
}

$Choco = $env:ProgramData + "\chocolatey\chocolateyinstall\chocolatey.ps1"
$Cup = $env:ProgramData + "\chocolatey\bin\cup.exe"
If (Test-Path $Choco) {
	Output-Host "Chocolatey is installed. Checking for new versions."
	$ErrorActionPreference = 'Stop'
	Try {
		&$Cup
	} Catch {
		$ErrorActionPreference = 'Continue'
		Output-Host "ERROR: Updating Chocolatey failed with error:"
		Output-Host $_.Exception.Message
		Exit 1001
	}
	$ErrorActionPreference = 'Continue'

} Else {
	Output-Host "Chocolatey not installed. Trying to install."
	$ErrorActionPreference = 'Stop'
	Try {
		iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
	} Catch {
		$ErrorActionPreference = 'Continue'
		Output-Host "ERROR: Installing Chocolatey failed with error:"
		Output-Host $_.Exception.Message
		get-buffer
		Exit 1001
	}
	$ErrorActionPreference = 'Continue'
	If (Test-Path $Choco) {
		Output-Host "Chocolatey is installed. Proceeding."
	} Else {
		$ErrorActionPreference = 'Continue'
		Write-Host "ERROR: Installation succeeded, but Chocolatey still not found! Exiting."
		get-buffer
		Exit 1001
	}
}

Output-Host "Verifying package installation:"

$ErrorActionPreference = 'Stop'
Try {
	. $Choco install @Packages
} Catch {
	$ErrorActionPreference = 'Continue'
	Output-Host "ERROR: Package installation failed with error:"
	Output-Host $_.Exception.Message
	get-buffer 
	Exit 1001
}
Exit 0