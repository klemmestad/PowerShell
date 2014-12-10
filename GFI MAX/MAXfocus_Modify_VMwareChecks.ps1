<#
.DESCRIPTION
	Detect missing VMware checks automatically.
	Add or report according to script settings.
   
.AUTHOR
   Hugo L. Klemmestad <hugo@klemmestad.com>
.DATE
   23.05.2014
#>



## SETTINGS
# A few settings are handled as parameters 
param (	
	[switch]$Apply = $false,
	[switch]$ReportMode = $true,
	[string]$User = "root", 
	[string]$Pass = "vmware",
	[string]$Hosts = ""
)
## Constants
# May need updating from time to time



$Scripts = @{
	"script_1024_28.vbs" = @{
		"arguments" = "";
		"url" = "https://www.dropbox.com/s/5j056a0c92bk452/script_1024_28.vbs?dl=1" };
	"script_1024_29.vbs" = @{
		"arguments" = "";
		"url" = "https://www.dropbox.com/s/yz1ynvgxhtqsu6h/script_1024_29.vbs?dl=1" };
	"script_1024_30.vbs" = @{
		"arguments" = "";
		"url" = "https://www.dropbox.com/s/zjhg0tv3ou2gt5y/script_1024_30.vbs?dl=1" };
	"script_1024_32.vbs" = @{
		"arguments" = "";
		"url" = "https://www.dropbox.com/s/rad6pf77f9u4m30/script_1024_32.vbs?dl=1" };
	"script_1024_33.vbs" = @{
		"arguments" = "";
		"url" = "https://www.dropbox.com/s/f2x5wfc6kccvnvm/script_1024_33.vbs?dl=1" };
	"script_1024_34.ps1" = @{
		"arguments" = "";
		"url" = "https://www.dropbox.com/s/a2rv0l8pulorc42/script_1024_34.ps1?dl=1" };
	"script_1024_35.ps1" = @{
		"arguments" = " -vmname ""*""";
		"url" = "https://www.dropbox.com/s/m80qbif1slx3hgu/script_1024_35.ps1?dl=1" };
	"script_1024_38.ps1" = @{
		"arguments" = " -datastorename ""*"" -units ""GB"" -threshold ""20""";
		"url" = "https://www.dropbox.com/s/0m6qpugu2pegt4b/script_1024_38.ps1?dl=1" };
	"script_1024_39.ps1" = @{
		"arguments" = "";
		"url" = "https://www.dropbox.com/s/k4iqpf4fu47gf52/script_1024_39.ps1?dl=1" };
}

$DefaultChecks =  @(
	@{ "checktype" = "ScriptCheck";
	   "checkset" = "247";
	   "description" = "VMware ESXi Health - Fans"; 
	   "scriptname" = "script_1024_28.vbs" ;
	   "scriptlanguage" = "0";
	   "timeout" = "10";
	   "arguments" = "-host ""{0}"" -username ""{1}"" -password ""{2}""" } 
	@{ "checktype" = "ScriptCheck";
	   "checkset" = "247";
	   "description" = "VMware ESXi Health - CPUs"; 
	   "scriptname" = "script_1024_29.vbs" ;
	   "scriptlanguage" = "0";
	   "timeout" = "10";
	   "arguments" = "-host ""{0}"" -username ""{1}"" -password ""{2}""" } 
	@{ "checktype" = "ScriptCheck";
	   "checkset" = "247";
	   "description" = "VMware ESXi Health - Memory"; 
	   "scriptname" = "script_1024_30.vbs" ;
	   "scriptlanguage" = "0";
	   "timeout" = "10";
	   "arguments" = "-host ""{0}"" -username ""{1}"" -password ""{2}""" } 
	@{ "checktype" = "ScriptCheck";
	   "checkset" = "247";
	   "description" = "VMware ESXi Health - PSUs"; 
	   "scriptname" = "script_1024_32.vbs" ;
	   "scriptlanguage" = "0";
	   "timeout" = "10";
	   "arguments" = "-host ""{0}"" -username ""{1}"" -password ""{2}""" } 
	@{ "checktype" = "ScriptCheck";
	   "checkset" = "247";
	   "description" = "VMware ESXi Health - Sensors"; 
	   "scriptname" = "script_1024_33.vbs" ;
	   "scriptlanguage" = "0";
	   "timeout" = "10";
	   "arguments" = "-host ""{0}"" -username ""{1}"" -password ""{2}""" } 
	@{ "checktype" = "ScriptCheck";
	   "checkset" = "247";
	   "description" = "VMware ESXi Health - Storage"; 
	   "scriptname" = "script_1024_39.ps1" ;
	   "scriptlanguage" = "1";
	   "timeout" = "150";
	   "arguments" = "-hostname ""{0}"" -username ""{1}"" -password ""{2}""" } 
	@{ "checktype" = "ScriptCheck";
	   "checkset" = "DSC";
	   "description" = "VMware ESXi Virtual Machine Inventory"; 
	   "scriptname" = "script_1024_34.ps1" ;
	   "scriptlanguage" = "1";
	   "timeout" = "150";
	   "arguments" = "-hostname ""{0}"" -username ""{1}"" -password ""{2}""" } 
#	@{ "checktype" = "ScriptCheck";
#	   "checkset" = "DSC";
#	   "description" = "VMware ESXi Virtual Machine Power State"; 
#	   "scriptname" = "script_1024_35.ps1" ;
#	   "scriptlanguage" = "1";
#	   "timeout" = "150";
#	   "arguments" = "-hostname ""{0}"" -username ""{1}"" -password ""{2}"" -vmname ""*""" } #-hostname "oc-esx01.hverven.local" -username "root" -password "vmware" -vmname "*"
	@{ "checktype" = "ScriptCheck";
	   "checkset" = "DSC";
	   "description" = "VMware ESXi - Datastore Free Space"; 
	   "scriptname" = "script_1024_38.ps1" ;
	   "scriptlanguage" = "1";
	   "timeout" = "150";
	   "arguments" = "-hostname ""{0}"" -username ""{1}"" -password ""{2}"" -datastorename ""*"" -units ""MB"" -threshold ""20000""" } 
)

## VARIUS FUNCTIONS
# Return an array of values from an array of XML Object
function Get-GFIMAXChecks ($xmlArray, $property) {
	$returnArray = @()
	foreach ($element in $xmlArray) {
		If ($element.$property -is [System.Xml.XmlElement]) {
			$returnArray += $element.$property.InnerText
		} Else {
			$returnArray += $element.$property
		}
	}
	If ($returnArray) {
		Return $returnArray
	}
}

function Format-Output ($ArrayOfHash) {
	ForEach ($Check in $ArrayOfHash) {
		Write-Host $Check["description"] $Check["arguments"]#.Split(" ")[1]
	}
}

function Make-ScriptAvailable ([string]$ScriptName) {
	$ScriptPath =  $ScriptDir + $ScriptName
	If (!(Test-Path $ScriptPath)) {
		$Source = $Scripts[$ScriptName]["url"]
		$Destination = $ScriptDir + $ScriptName
		$webclient.DownloadFile($Source,$Destination)
	} ElseIf ($ScriptName -eq "script_1024_38.ps1") {
		If (!(Get-Content $ScriptPath | Select-String "PowerCli 4.x does not provide GB values" -quiet)) {
			$Source = $Scripts[$ScriptName]["url"]
			$Destination = $ScriptDir + $ScriptName
			$webclient.DownloadFile($Source,$Destination)
		}
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

## SETUP ENVIRONMENT
# Find "Advanced Monitoring Agent" service and use path to locate files
$gfimaxagent = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq 'Advanced Monitoring Agent' }
$gfimaxexe = $gfimaxagent.PathName
$gfimaxpath = Split-Path $gfimaxagent.PathName.Replace('"',"") -Parent

# XML Document objects
$XmlConfig = @{}

# XML Document Pathnames
$XmlFile = @{}

# We need an array of hashes to remember which checks to add
$NewChecks = @()

$Sets = @("247", "DSC")

$IniFile = $gfimaxpath + "\settings.ini"
$ScriptDir = $gfimaxpath + "\scripts\"
$ScriptLib = $ScriptDir + "lib\"

$ConfigChanged = $false

$webclient = New-Object System.Net.WebClient

# Read ini-files
$settingsContent = Get-IniContent($IniFile)

If (!(Test-Path -PathType Container $ScriptLib)) {
	$Silent = New-Item -ItemType Directory -Force -Path $ScriptLib
}

$PSSnapinVMware = $false
$PowerCli = "https://www.dropbox.com/s/331nzom43zstpx3/VMware-PowerCLI-5.0.0-435426.exe?dl=1"
$sSnapInName = 'VMware.VimAutomation.Core'
foreach( $oSnapIn in Get-PSSnapIn -Registered ) {
	if( $oSnapIn.Name -eq $sSnapInName ) {
		Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
		$PSSnapinVMware = $true
	}
}

#If (!($PSSnapinVMware))
#{
#	$PowerCliExe = $ScriptLib + "VMware-PowerCLI.exe"
#	
#	$webclient.DownloadFile($PowerCli,$PowerCliExe)
#	&$PowerCliExe /s /v /qn
#	If ($LASTEXITCODE -eq 1)
#	{
#		$PSSnapinVMware = $true
#	}
#}
#

# Read configuration of checks. Create an XML object if they do not exist yet.
$MaxUid = @()
ForEach ($Set in $Sets + "ST") {
	$XmlConfig[$Set]  = New-Object -TypeName XML
	$XmlFile[$Set] = $gfimaxpath + "\{0}_Config.xml" -f $Set
	If (Test-Path $XmlFile[$Set]) { 
		$XmlConfig[$Set].Load($XmlFile[$Set])
		$XmlConfig[$Set].DocumentElement.SetAttribute("modified","1")
	} Else { 
		$decl = $XmlConfig[$Set].CreateXmlDeclaration("1.0", "ISO-8859-1", $null)
		$rootNode = $XmlConfig[$Set].CreateElement("checks")
		$result = $rootNode.SetAttribute("modified", "1")
		$result = $XmlConfig[$Set].InsertBefore($decl, $XmlConfig[$Set].DocumentElement)
		$result = $XmlConfig[$Set].AppendChild($rootNode)
		$uid = 1
	}
	$MaxUid +=  ($XmlConfig[$Set].checks.ChildNodes | select -Expandproperty uid | measure -Maximum).Maximum
}

$MaxUid = $MaxUid | Measure -Maximum
$InUseUid = $MaxUid.Maximum + 1

$SettingsUid = $settingsContent["GENERAL"]["NEXTCHECKUID"]

If($SettingsUid -gt $InUseUid) {
	[int]$uid = $SettingsUid
} Else {
	[int]$uid = $InUseUid
}



[array]$EsxHosts = @([regex]::Split($Hosts,"[,\s]"))


$CurrentChecks = Get-GFIMAXChecks ($XmlConfig.Values | % { $_.checks.ScriptCheck }) scriptname
ForEach ($EsxHost in $EsxHosts) {
	Foreach ($Check in $DefaultChecks) {
		# The name of the script is important. 
		$ScriptName = $Check.scriptname
		
		# Download the script from our own repository if it is missing
		Make-ScriptAvailable $ScriptName
		
		# Put passed parameters into $Arguments
		$Arguments = $Check.arguments -f $EsxHost, $User, $Pass
		
		# Delete any existing checks running this very script on this very host
		# We may be replacing it with a new password
		$CurrentScriptChecks = @($XmlConfig.Values | % { $_.checks.ScriptCheck } | where {($_.scriptname.Innertext -eq $ScriptName -or $_.scriptname -eq $ScriptName) -and ($_.arguments.Innertext -match $EsxHost -or $_.arguments -match $EsxHost)})
	 	$CheckExists = $false
		Foreach ($xmlCheck in $CurrentScriptChecks) {
			If ($false) { #($xmlCheck.arguments.InnerText -eq $Arguments -or $xmlCheck.arguments -eq $Arguments ) -and ($CurrentScriptChecks.Count -eq 1) -and $xmlCheck.BaseURI.Contains($Check.checkset)) {
			 	$CheckExists = $true
			} Else {
				$null = $xmlCheck.ParentNode.RemoveChild($xmlCheck) 
			}
		}
		
		If ($CheckExists) { Continue }
		
		# Create a Check
		$NewCheck = @{
			"checktype" = "ScriptCheck";
			"checkset" = $Check.checkset;
			"scriptname" = $ScriptName;
			"description" = $Check.description;
			"scriptlanguage" = $Check.scriptlanguage;
			"arguments" = $Arguments;
			"timeout" = $Check.timeout
		}
		$NewChecks += $NewCheck
	}
}


If($NewChecks[0]) {
	Foreach ($Check in $NewChecks) {
		$xmlCheck = $XmlConfig[$Check.checkset].CreateElement($Check.checktype)
		$xmlCheck.SetAttribute('modified', '1')
		$xmlCheck.SetAttribute('uid', $uid)
		$uid++ # Increase unique ID identifier to keep it unique
		
		Foreach ($property in $Check.Keys) {
		 	If ("checkset", "checktype" -notcontains $property) {
				$xmlProperty = $XmlConfig[$Check.checkset].CreateElement($property)
				$propertyValue = $Check.get_Item($property)
				If ([bool]($propertyValue -as [int]) -or $propertyValue -eq "0") # Is this a number?
				{ # If its a number we just dump it in there
					$xmlProperty.set_InnerText($propertyValue)
				} Else { # If it is text we encode it in CDATA
					$rs = $xmlProperty.AppendChild($XmlConfig[$Check.checkset].CreateCDataSection($propertyValue))
				}
				# Add Property to Check element
				$rs = $xmlCheck.AppendChild($xmlProperty)
			}
		}
		# Add Check to file in check section
		$rs = $XmlConfig[$Check.checkset].checks.AppendChild($xmlCheck)

	}
	$XmlConfig[$Check.checkset].checks.SetAttribute("modified", "1")
	$ConfigChanged = $true
}


If($ConfigChanged) { 
	
	If ($Apply) {
		# Update last runtime to prevent changes too often
		[int]$currenttime = $(get-date -UFormat %s) -replace ",","." # Handle decimal comma 
		$settingsContent["DAILYSAFETYCHECK"]["RUNTIME"] = $currenttime
		
		# Clear lastcheckday to make DSC run immediately
		$settingsContent["DAILYSAFETYCHECK"]["LASTCHECKDAY"] = "0"
		
		# Save updated NEXTCHECKUID
		$settingsContent["GENERAL"]["NEXTCHECKUID"] = $uid
		
		# Stop agent before writing new config files
		Stop-Service $gfimaxagent.Name
		
		# Save all config files
		ForEach ($Set in $Sets) {
			$XmlConfig[$Set].Save($XmlFile[$Set])
		}
		Out-IniFile $settingsContent $IniFile
		
		# Start monitoring agent again
		Start-Service $gfimaxagent.Name
		
		# Write output to Dashboard
		Write-Host "CHANGES APPLIED:"
		If ($NewChecks) {
			Write-Host "Added the following checks to configuration file:"
			Format-Output $NewChecks 
		}
		If ($ReportMode) {
			Exit 0 # Needed changes have been reported, but do not fail the check
		} Else {
			Exit 1001 # Internal status code: Changes made
		}
	} Else {
		Write-Host "MISSING CHECKS"
		If ($NewChecks) 
		{
			Write-Host "You should add the following checks:"
			Format-Output $NewChecks 
		}
		If ($ReportMode) {
			Exit 0 # Needed changes have been reported, but do not fail the check
		} Else {
			Exit 1000 # Internal status code: Suggested changes, but nothing has been touched
		}
	}
} Else {
	# We have nothing to do. This Device has passed the test!
	Write-Host "CHECKS VERIFIED"
	Exit 0 # SUCCESS
}
