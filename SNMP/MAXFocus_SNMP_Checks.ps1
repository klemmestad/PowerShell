 <#
.DESCRIPTION
	Scan an SNMP target for known OIDs with values.
	Add SNMP checks to agent.
   
.AUTHOR
   Hugo L. Klemmestad <hugo@klemmestad.com>
.DATE
   003.11.2014
#>

Param (
	[string]$Community = "public",
	[string]$Target = "localhost",
	[int]$UDPport = 161,
	[switch]$Apply = $false,
	[string]$ReportMode = "On"
)
# Invert Reportmode
If ($ReportMode -match 'y|yes|On|true') { 
	$ReportMode = $true 
} Else {
	$ReportMode = $false 
}

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
    $ver = [Lextm.SharpSnmpLib.VersionCode]::V1
 
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

$Sets = @("247", "DSC")

# Other Pathnames
$IniFile = $gfimaxpath + "\settings.ini"
$ScriptLib = $gfimaxpath + "\scripts\lib"
$ConfigChanged = $false

# Read ini-files
$settingsContent = Get-IniContent($IniFile)

# Load SNMP Library. Download file if it does not exist
$SNMP_lib = $ScriptLib + "\SharpSnmpLib.dll"
$SNMP_lib_URL = "https://www.dropbox.com/s/2iqvpmuxs80kuvb/SharpSnmpLib.dll?dl=1"

If (!(Test-Path $SNMP_lib)) {
	If (!(Test-Path -PathType Container $ScriptLib)) {
		New-Item -ItemType Directory -Force -Path $ScriptLib
	}
	
	$webclient = New-Object System.Net.WebClient
	$webclient.DownloadFile($SNMP_lib_URL,$SNMP_lib)
}

$null = [reflection.assembly]::LoadFrom($SNMP_lib)

# First of all, check if it is safe to make any changes
If ($Apply) {
	# Make sure a failure to aquire settings correctly will disable changes
	$Apply = $false
	If ($settingsContent["DAILYSAFETYCHECK"]["RUNTIME"]) { # This setting must exist
		$lastRuntime = $settingsContent["DAILYSAFETYCHECK"]["RUNTIME"]
		[int]$currenttime = $((Get-Date).touniversaltime() | get-date -UFormat %s) -replace ",","." # Handle decimal comma 
		$timeSinceLastRun = $currenttime - $lastRuntime
		If($lastRuntime -eq 0 -or $timeSinceLastRun -gt 360) {
			# If we have never been run or it is at least 6 minutes ago
			# enable changes again
			$Apply = $true
		}
	}
	If (!($Apply)) {
		Write-Host "CHANGES APPLIED - Verifying changes:"
	}
}


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

# Check Agent mode, workstation or server
$AgentMode = $AgentConfig.agentconfiguration.agentmode

If (Test-Path $snmp_sys) {
	$snmp_presets.Load($snmp_sys)
}

$System = ".1.3.6.1.2.1.1.2.0"
$SNMPhosts = @()

If ($Target -match "/") {
	$FirstIP = @((Get-IPV4NetworkStartIP ($Target)).ToString().Split("."))
	$LastIP = @((Get-IPV4NetworkEndIP ($Target)).ToString().Split("."))

	ForEach ($Byte1 in $FirstIP[0]..$LastIP[0]) {
		ForEach ($Byte2 in $FirstIP[1]..$LastIP[1]) {
			ForEach ($Byte3 in $FirstIP[2]..$LastIP[2]) {
				ForEach ($Byte4 in $FirstIP[3]..$LastIP[3]) {
					$SNMPhost = "{0}.{1}.{2}.{3}" -f $Byte1, $Byte2, $Byte3, $Byte4
					
					# Test if Target responds on SNMP port
					$oidValue = Invoke-SNMPget $SNMPhost $System $Community $UDPport

					If ($oidValue.Data -notmatch "Error") {
						$SNMPhosts += $SNMPhost
					}
				}
			}
		}
	}
} Else {
	$SNMPhosts = $Target.Split(", ")
}


ForEach ($SNMPhost in $SNMPhosts) {
	# Create REF variable of correct type
	$ip = [System.Net.IPAddress]::Parse("127.0.0.1")
	# Try to parse $SNMPhost as IP address
	If (!([System.Net.IPAddress]::TryParse($SNMPhost, [ref] $ip))) {
		# $SNMPhost is not a valid IP address. Maybe it is a hostname?
		Try {
			 $ip = [System.Net.Dns]::GetHostAddresses($SNMPhost)[0]
		} Catch {
			Write-Host $("ERROR: Could not resolve hostname ""{0}""" -f $SNMPhost)
			Continue
		}
	}

	ForEach ($preset in $snmp_presets.presets.preset) {
		$NewCheck = @{}
		$oidValue = Invoke-SNMPget $ip $preset.oid $Community $UDPport
		If ("NoSuchObject","NoSuchInstance","Error" -notcontains $oidValue.Data) {
			$oid = $preset.oid
			$CheckExists = $XmlConfig["247"].checks.SelectSingleNode("SnmpCheck[host=""$SNMPhost"" and oid=""$oid""]")
			If(!($CheckExists)) {
				$NewCheck = @{
					"checktype" = "SnmpCheck";
					"checkset" = "247";
					"product" = $SNMPhost + " - " +$preset.description;
					"host" = $SNMPhost;
					"port" = $UDPport;
					"community" = $Community;
					"oid" = $oid;
					"op" = $preset.op;
					"testvalue" = $preset.testvalue;
					"snmpversion" = 1
					}
				
				$NewChecks += $NewCheck
			}
		}
	}
}

If($NewChecks[0]) 
{
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
	
	If ($Apply) {
		# Save updated NEXTCHECKUID
		$settingsContent["GENERAL"]["NEXTCHECKUID"] = $uid
		
		# Stop agent before writing new config files
		Stop-Service $gfimaxagent.Name
		
		# Save all config files
		$XmlConfig["247"].Save($XmlFile["247"])
		
		Out-IniFile $settingsContent $IniFile
		
		# Start monitoring agent again
		Start-Service $gfimaxagent.Name
		
		# Write output to Dashboard
		Write-Host "Checks added:"
		If ($NewChecks) 
		{
			ForEach ($Check in $NewChecks) {
				Write-Host $Check["product"]
			}
		}
		If ($ReportMode) {
			Exit 0 # Needed changes have been reported, but do not fail the check
		} Else {
			Exit 1001 # Internal status code: Suggested changes, but nothing has been touched
		}
	} Else {
		Write-Host "New SNMP Checks Available:"
		If ($NewChecks) 
		{
			ForEach ($Check in $NewChecks) {
				Write-Host $Check["product"]
			}
		}
		If ($ReportMode) {
			Exit 0 # Needed changes have been reported, but do not fail the check
		} Else {
			Exit 1001 # Internal status code: Suggested changes, but nothing has been touched
		}
	}
} Else {
	# We have nothing to do. 
	Write-Host "Nothing to do."
	Exit 0 # SUCCESS
}
