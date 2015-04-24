<#
.DESCRIPTION
	Scan an SNMP target for known OIDs with values.
	Add SNMP checks to agent.
   
.AUTHOR
   Hugo L. Klemmestad <hugo@klemmestad.com>
.DATE
   03.11.2014
.LINK
   http://klemmestad.com/2014/12/10/add-snmp-checks-to-maxfocus-automatically/
.VERSION
   1.14
#>

# Using [string] for almost all parameters to avoid parameter validation fail
Param (
	[string]$Community = "public",

	[array]$Target = "localhost",

	[string]$UDPport = 161,

	[switch]$Apply = $false,

	[string]$ReportMode = "On",

	[string]$Name,
	
	# We must accept -logfile, because it is always given by task_start.js
	# Not accepting it will make the script fail with not output to Dashboard
	# Put it in %TEMP% if script is run interactively
	[string]$logfile = "{0}\logfile.log" -f $env:TEMP,
	
	[switch]$Debug = $false,
	[switch]$Verbose = $false
	
)



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
		[string]$Text = ""
		Foreach ($arg in $args) { $Text += $arg }
		('{0}: {1}' -f (Get-Date),$Text) | Out-File -Append $logfile
	}
}

# Output text to STDOUT if Verbose set
function Output-Verbose {
	If ($Verbose) {
		[string]$Text = "VERBOSE: "
		Foreach ($arg in $args) { $Text += $arg }
		Output-Host $Text
	}
}

# Print to STDOUT to make sure task_start.js gets some output
Output-Host "Result: "

# Require version 2.0
If (!($PSVersionTable)) {
	Output-Host "Error: Script requires Powershell version 2.0 or greater."
	Output-Host "Aborting.."
	#Exit 0
}

Output-Verbose ("Hostname: {0}" -f $env:COMPUTERNAME)
Output-Verbose ("PowerShell PSVersion: {0}" -f $PSVersionTable.PSVersion)
Output-Verbose ("PowerShell CLRVersion: {0}" -f $PSVersionTable.CLRVersion)
Output-Verbose ("PowerShell BuildVersion: {0}" -f $PSVersionTable.BuildVersion)

# Validate $Community
If ($Community.Length -eq 0) {
	Output-Verbose "-Community has Zero length. Using Default value of public."
	$Community = "public"
}
Output-Verbose ("Using {0} as value for Community string." -f $Community)

# Give early feedback on Target
Output-Verbose ("Number of Targets: {0}" -f $Target.Count)
[int]$Count = 1
Foreach ($element in $Target) {
	Output-Verbose ("Target {0}: {1}" -f $Count,$element)
	$Count++
}

# Validate $UDPport
$x2 = 0
$isNum = [System.Int32]::TryParse($UDPport, [ref]$x2)
If ($isNUM) {
	[int]$UDPport = $UDPport
	If ($UDPport -lt 1 -or $UDPport -gt 65535) {
		Output-Verbose "-UDPport $UDPport is out of bounds. Using Default value of 161."
		[int]$UDPport = 161
	}
} Else {
	Output-Verbose "-UDPport cannot be converted to Integer. Using Default value of 161."
	[int]$UDPport = 161
}
Output-Verbose "Using $UDPport for -UDPport."

# Invert Reportmode
If ($ReportMode -match 'Off' -or $ReportMode -match 'false') { 
	[bool]$ReportMode = $false 
	Output-Verbose "Report Mode is OFF"
} Else {
	[bool]$ReportMode = $true 
	Output-Verbose "Report Mode is ON"
}
Output-Verbose "Using $ReportMode as value for -ReportMode."

## VARIUS FUNCTIONS

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

Function New-GenericObject {
	param(
	    ## The generic type to create
	    [Parameter(Mandatory = $true)]
	    [string] $TypeName,

	    ## The types that should be applied to the generic object
	    [Parameter(Mandatory = $true)]
	    [string[]] $TypeParameters,

	    ## Arguments to be passed to the constructor
	    [object[]] $ConstructorParameters
	)

	Set-StrictMode -Version Latest

	## Create the generic type name
	$genericTypeName = $typeName + '`' + $typeParameters.Count
	$genericType = [Type] $genericTypeName

	if(-not $genericType)
	{
	    throw "Could not find generic type $genericTypeName"
	}

	## Bind the type arguments to it
	[type[]] $typedParameters = $typeParameters
	$closedType = $genericType.MakeGenericType($typedParameters)
	if(-not $closedType)
	{
	    throw "Could not make closed type $genericType"
	}

	## Create the closed version of the generic type
	,[Activator]::CreateInstance($closedType, $constructorParameters)
}

function Invoke-SNMPget ([string]$sIP, $sOIDs, [string]$Community = "public", [int]$UDPport = 161, [int]$TimeOut=3000) {
    # $OIDs can be a single OID string, or an array of OID strings
    # $TimeOut is in msec, 0 or -1 for infinite
	If ($Verbose) {
	 	Output-Debug ('Invoke-SNMPget called with $sIP={0}, $sOIDs={1}, $Community={2}, $UDPport={3}, $TimeOut={4}' -f $sIP, $sOIDs, $Community, $UDPport, $TimeOut)
	}
    # Create OID variable list
	If ($PSVersionTable.PSVersion.Major -lt 3) {
    	$vList = New-GenericObject System.Collections.Generic.List Lextm.SharpSnmpLib.Variable                        # PowerShell v1 and v2
	} Else {
    	$vList = New-Object 'System.Collections.Generic.List[Lextm.SharpSnmpLib.Variable]'                          # PowerShell v3
	}
    foreach ($sOID in $sOIDs) {
        $oid = New-Object Lextm.SharpSnmpLib.ObjectIdentifier ($sOID)
        $vList.Add($oid)
    }
 
    # Create endpoint for SNMP server
    $ip = [System.Net.IPAddress]::Parse($sIP)
	$svr = New-Object System.Net.IpEndPoint ($ip, $UDPport)
 
    # Use SNMP v2
    $ver = [Lextm.SharpSnmpLib.VersionCode]::V2
 
    # Perform SNMP Get
    try {
        $msg = [Lextm.SharpSnmpLib.Messaging.Messenger]::Get($ver, $svr, $Community, $vList, $TimeOut)
    } catch {
        $line = "" | Select OID, Data
		$line.OID = $oid
        $line.Data =  "Error"
        Return $line
    }
 
    $res = @()
    foreach ($var in $msg) {
        $line = "" | Select OID, Data
        $line.OID = $var.Id.ToString()
        $line.Data = $var.Data.ToString()
        $res += $line
    }
 
    $res
}

Function Get-IPV4NetworkStartIP ($strNetwork) {
	$StrNetworkAddress = ($strNetwork.split("/"))[0]
	$NetworkIP = ([System.Net.IPAddress]$StrNetworkAddress).GetAddressBytes()
	[Array]::Reverse($NetworkIP)
	$NetworkIP = ([System.Net.IPAddress]($NetworkIP -join ".")).Address
	$StartIP = $NetworkIP +1
	#Convert To Double
	If (($StartIP.Gettype()).Name -ine "double") {
		$StartIP = [Convert]::ToDouble($StartIP)
	}
	$StartIP = [System.Net.IPAddress]$StartIP
	Return $StartIP
}

Function Get-IPV4NetworkEndIP ($strNetwork) {
	$StrNetworkAddress = ($strNetwork.split("/"))[0]
	[int]$NetworkLength = ($strNetwork.split("/"))[1]
	$IPLength = 32-$NetworkLength
	$NumberOfIPs = ([System.Math]::Pow(2, $IPLength)) -1
	$NetworkIP = ([System.Net.IPAddress]$StrNetworkAddress).GetAddressBytes()
	[Array]::Reverse($NetworkIP)
	$NetworkIP = ([System.Net.IPAddress]($NetworkIP -join ".")).Address
	$EndIP = $NetworkIP + $NumberOfIPs
	If (($EndIP.Gettype()).Name -ine "double") {
		$EndIP = [Convert]::ToDouble($EndIP)
	}
	$EndIP = [System.Net.IPAddress]$EndIP
	Return $EndIP
}

## SETUP ENVIRONMENT
# Find "Advanced Monitoring Agent" service and use path to locate files
Output-Verbose "Locating Advanced Monitoring service and setting up variables."
$gfimaxagent = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq 'Advanced Monitoring Agent' }
$gfimaxexe = $gfimaxagent.PathName
$gfimaxpath = Split-Path $gfimaxagent.PathName.Replace('"',"") -Parent

# XML Document objects
$snmp_presets = New-Object -TypeName XML
$XmlConfig = @{}

# XML Document Pathnames
$snmp_sys = $gfimaxpath + "\snmp_sys.xml"
$XmlFile = @{}

# We need an array of hashes to remember which checks to add
$NewChecks = @()

$Sets = @("247")

# Other Pathnames
$IniFile = $gfimaxpath + "\settings.ini"
$ScriptLib = $gfimaxpath + "\scripts\lib"
$LastChangeFile = $gfimaxpath + "\LastSNMPChange.log"
$ConfigChanged = $false

# Read ini-files
$settingsContent = Get-IniContent($IniFile)

# Load SNMP Library. Download file if it does not exist
$SNMP_lib = $ScriptLib + "\SharpSnmpLib.dll"
$SNMP_lib_URL = "https://github.com/klemmestad/PowerShell/raw/master/SNMP/lib/SharpSnmpLib.dll"

# Catch and output any errors
$ErrorActionPreference = 'STOP'
Try {
	If (!(Test-Path $SNMP_lib)) {
		Output-Verbose "SharpSnmpLib.dll not found. Trying to download."
		If (!(Test-Path -PathType Container $ScriptLib)) {
			Output-Verbose "Creating directory $Scriptlib"
			New-Item -ItemType Directory -Force -Path $ScriptLib
		}
		
		$webclient = New-Object System.Net.WebClient
		Output-Verbose ("Starting download from {0}" -f $SNMP_lib_URL)
		$webclient.DownloadFile($SNMP_lib_URL,$SNMP_lib)
		Output-Verbose "SNMP library not found. Downloaded from web."
		If ($PSVersionTable.PSVersion.Major -gt 2) {
            Unblock-File -Path $SNMP_lib
        }
	}

	$null = [reflection.assembly]::LoadFrom($SNMP_lib)

	# Read configuration of checks. Create an XML object if they do not exist yet.
	ForEach ($Set in $Sets) {
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
		}
	}

	# Check Agent mode, workstation or server
	$AgentMode = $AgentConfig.agentconfiguration.agentmode

	If (Test-Path $snmp_sys) {
		$snmp_presets.Load($snmp_sys)
	}

	$System = ".1.3.6.1.2.1.1.2.0"
	$SNMPhosts = @()

	If ($Target -match "/") {
		$FirstIP = @((Get-IPV4NetworkStartIP ($Target[0])).ToString().Split("."))
		$LastIP = @((Get-IPV4NetworkEndIP ($Target[0])).ToString().Split("."))

		ForEach ($Byte1 in $FirstIP[0]..$LastIP[0]) {
			ForEach ($Byte2 in $FirstIP[1]..$LastIP[1]) {
				ForEach ($Byte3 in $FirstIP[2]..$LastIP[2]) {
					ForEach ($Byte4 in $FirstIP[3]..$LastIP[3]) {
						$SNMPhost = "{0}.{1}.{2}.{3}" -f $Byte1, $Byte2, $Byte3, $Byte4
						
						# Test if Target responds on SNMP port
						Output-Verbose ('Trying to read value of "System" on {0}.' -f $SNMPhost)
						$oidValue = Invoke-SNMPget $SNMPhost $System $Community $UDPport

						If ($oidValue.Data -notmatch "Error") {
							Output-Verbose ('Host {0} responded with {1}' -f $SNMPhost, $oidValue.Data)
							$SNMPhosts += $SNMPhost
						} Else {
							Output-Verbose ('Host {0} did not respond.' -f $SNMPhost)
						}
					}
				}
			}
		}
	} Else {
		$SNMPhosts = $Target
	}
} Catch {
	Output-Host ("ERROR: Script failed on item: {0}" -f $_.Exception.ItemName)
	Output-Host $_.Exception.Message
	Exit 1000
}

ForEach ($SNMPhost in $SNMPhosts) {
	# Create REF variable of correct type
	$ip = [System.Net.IPAddress]::Parse("127.0.0.1")
	# Try to parse $SNMPhost as IP address
	If (!([System.Net.IPAddress]::TryParse($SNMPhost, [ref] $ip))) {
		Output-Verbose ('Tried to parse {0} as IP address. Assuming it is a DNS name.' -f $SNMPhost)
		# $SNMPhost is not a valid IP address. Maybe it is a hostname?
		Try {
			 $ip = [System.Net.Dns]::GetHostAddresses($SNMPhost)[0]
			 If ($ip -eq "::1") { $ip = [System.Net.IPAddress]::Parse("127.0.0.1") }
		} Catch {
			Output-Host ("ERROR: Could not resolve hostname ""{0}""" -f $SNMPhost)
			Continue
		}
		Output-Verbose ('Resolved {0} to IP address {1}' -f $SNMPhost, $ip)
	} Else {
		Output-Verbose ('Current Target is an IP address: {0}' -f $ip)
	}
	Output-Verbose ('Using {0} as IP address of current SNMPhost' -f $ip)
	Try {
		# Test if Target responds on SNMP port
		Output-Verbose ('Trying to read value of "System" on {0}.' -f $SNMPhost)
		$oidValue = Invoke-SNMPget $ip $System $Community $UDPport

		If ($oidValue.Data -notmatch "Error") {
			Output-Verbose ('Host {0} responded to SNMP. Testing presets.' -f $SNMPhost)
		} Else {
			Output-Verbose ('Host {0} did not respond to SNMP using {1} as Community String.' -f $SNMPhost,$Community)
			Continue
		}
		Output-Verbose "Looping through all presets. Use -Debug for full details."
		ForEach ($preset in $snmp_presets.presets.preset) {
			$NewCheck = @{}
			$oidValue = Invoke-SNMPget $ip $preset.oid $Community $UDPport
			If ("NoSuchObject","NoSuchInstance","Error" -notcontains $oidValue.Data) {
				If ($Name) {
					$Description = '{0} ({1}) - {3} {4} - {2}' -f $Name, $SNMPhost, $preset.description, $preset.vendor, $preset.product
				} Else {
					$Description = '{0} - {2} {3} - {1}' -f  $SNMPhost, $preset.description, $preset.vendor, $preset.product
				}
				$oid = $preset.oid
				$CheckExists = $XmlConfig["247"].checks.SelectSingleNode("SnmpCheck[host=""$SNMPhost"" and oid=""$oid""]")
				If(!($CheckExists)) {
					Output-Verbose ("Valid check {0}" -f $Description)
					$NewCheck = @{
						"checktype" = "SnmpCheck";
						"checkset" = "247";
						"product" = $Description;
						"host" = $SNMPhost;
						"port" = $UDPport;
						"community" = $Community;
						"oid" = $oid;
						"op" = $preset.op;
						"testvalue" = $preset.testvalue;
						"snmpversion" = 2
						}
					
					$NewChecks += $NewCheck
				} Else {
					Output-Debug ('Testing {0}' -f $Description)
					If ($CheckExists.product -is [System.Xml.XmlElement]) { $Checkname = $CheckExists.product.InnerText}
					Else { $Checkname = $CheckExists.product}
					Output-Verbose ("This check already exist with name '{0}'" -f $Checkname ) 
				}
			}
		}
	} Catch {
		Output-Host ("ERROR: Script failed on item: {0}" -f $_.Exception.ItemName)
		Output-Host $_.Exception.Message
		Exit 1000
	}
}

If($NewChecks[0]) 
{
	Foreach ($Check in $NewChecks) {
		$xmlCheck = $XmlConfig[$Check.checkset].CreateElement($Check.checktype)
		$xmlCheck.SetAttribute('modified', '1')
	
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
	
	If ($Apply) {
		
		# Save all config files
		$XmlConfig["247"].Save($XmlFile["247"])
		
		# Check if PSScheduledJob module is available. Use delayed restart of agent if it does.
		Try { 
			Output-Debug 'Trying to restart agent using PSScheduledJob'
			$ErrorActionPreference = 'Stop'
			# Restart monitoring agent with a scheduled task with 2 minutes delay.
			# Register a new task if it does not exist, set a new trigger if it does.
			Import-Module PSScheduledJob
			$JobTime = (Get-Date).AddMinutes(2)
			$JobTrigger = New-JobTrigger -Once -At $JobTime.ToShortTimeString()
			$JobOption = New-ScheduledJobOption -StartIfOnBattery -RunElevated 
			$RegisteredJob = Get-ScheduledJob -Name RestartAdvancedMonitoringAgent -ErrorAction SilentlyContinue
			If ($RegisteredJob) {
				Set-ScheduledJob $RegisteredJob -Trigger $JobTrigger
			} Else {
				Register-ScheduledJob -Name RestartAdvancedMonitoringAgent -ScriptBlock { Restart-Service 'Advanced Monitoring Agent' } -Trigger $JobTrigger -ScheduledJobOption $JobOption
			}	
			$RestartMethod = 'PSScheduledJob'
		} Catch {
			Output-Debug 'EXCEPTION: PSScheduledJob not available. Using Restart-Service.'
		    # No scheduled job control available
		    # Restart the hard way
		    Restart-Service 'Advanced Monitoring Agent'
			$RestartMethod = 'Restart-Service'
		} Finally {
			$ErrorActionPreference = 'Continue'
		}
		# Write output to $LastChangeFile
		# Overwrite file with first command
		"Last Change applied {0} (Restarted using {1}):" -f $(Get-Date), $RestartMethod | Out-File $LastChangeFile
		"------------------------------------------------------" | Out-File -Append $LastChangeFile
		If ($NewChecks) {
			"`nAdded the following checks to configuration file:" | Out-File -Append $LastChangeFile
			ForEach ($Check in $NewChecks) {
				$Check["product"] | Out-File -Append $LastChangeFile
			}
		}	

		If ($ReportMode) {
			Exit 0 # Needed changes have been reported, but do not fail the check
		} Else {
			Exit 1001 # Internal status code: Suggested changes, but nothing has been touched
		}
	} Else {
		Output-Host "New SNMP Checks Available:"
		If ($NewChecks) 
		{
			ForEach ($Check in $NewChecks) {
				Output-Host $Check["product"]
			}
		}
		If (Test-Path $LastChangeFile) {
			# Print last change to STDOUT
			Output-Host "------------------------------------------------------"
			Get-Content $LastChangeFile
			Output-Host "------------------------------------------------------"
		}
		If ($ReportMode) {
			Exit 0 # Needed changes have been reported, but do not fail the check
		} Else {
			Exit 1001 # Internal status code: Suggested changes, but nothing has been touched
		}
	}
} Else {
	# We have nothing to do. 
	Output-Host "Nothing to do."
	If (Test-Path $LastChangeFile) {
		# Print last change to STDOUT
		Output-Host "------------------------------------------------------"
		Get-Content $LastChangeFile
		Output-Host "------------------------------------------------------"
	}
	Exit 0 # SUCCESS
}
