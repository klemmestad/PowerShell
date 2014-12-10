<#
.DESCRIPTION
	Detect missing checks automatically.
	Add or report according to script settings.
   
.AUTHOR
   Hugo L. Klemmestad <hugo@klemmestad.com>
.DATE
   23.05.2014
#>



## SETTINGS
# A few settings are handled as parameters 
param (	
	[switch]$All = $false,
	[switch]$ReUid = $false, # For when this script as messed up your monitoring configuration
	[switch]$Apply = $false, # -Apply will write new checks to configfiles and reload agent
	[switch]$Replace = $false, # Automated task only: -Replace will dump any existing checks if -Apply is used
	[switch]$ReportMode = $true, # -ReportMode will report missing checks, but not fail the script
	[switch]$Performance = $false, # Set to $false if you do not want performance checks
	[switch]$PingCheck = $false, # This is useful on a Fault History report. Otherwise useless.
	[switch]$MSSQL = $false, # Detect SQL servers
	[switch]$SMART = $false, # Enable physical disk check if SMART status is available
	[switch]$Backup = $false, # Configure a basic backup check if a compatible product is recognized
	[switch]$Antivirus = $false, # Configure an Antivirus check if a compatible product is recognized	
	[switch]$LogChecks = $false, # Configure default log checks
	[string]$DriveSpaceCheck = $null, # Freespace as number+unit, i.e 10%, 5GB or 500MB
	[string]$WinServiceCheck = "", # "All" or "DefaultOnly". 
	[string]$DiskSpaceChange = $null, # percentage as integer
	[string]$ServerInterval = "5", # 5 or 15 minutes
	[string]$PCInterval = "30", # 30 or 60 minutes
	[string]$DSCHour = "8", # When DSC check should run in whole hours. Minutes not supported by agent.
	[int]$Weekday = 7 # When detected changes should be applied
)

# Force the script to output something to STDOUT, else errors may cause script timeout.
Write-Host " "

If ($All)
{
	## DEFAULT CHECKS
	$Performance = $false # Set to $false if you do not want performance checks
	$PingCheck = $false # This is useful on a Fault History report. Otherwise useless.
	$MSSQL = $true # Detect SQL servers
	$SMART = $true # Enable physical disk check if SMART status is available
	$Antivirus = $true # Configure an Antivirus check if a compatible product is recognized
	$DriveSpaceCheck = "10%" # Freespace as number+unit, i.e 10%, 5GB or 500MB
	$WinServiceCheck = "All" # "All" or "Default". 
	$DiskSpaceChange = 10 # percentage as integer
	$Backup = $false # Try to configure Backup Monitoring
	$LogChecks = $true # Configure default eventlog checks
	$PMSchedule = "Wed@4" # Wednesdays at 4 AM
}

$DefaultLogChecks = @(
	@{ "log" = "Application|Application Hangs"; # Application log | Human readable name
	   "flags" = 32512;
	   "ids" = "*";
	   "source" = "Application Hang" }
	@{ "log" = "System|NTFS Errors";
	   "flags" = 32513;
	   "ids" = "*";
	   "source" = "Ntfs*" }
	@{ "log" = "System|BSOD Stop Errors";
	   "flags" = 32513;
	   "ids" = "1003";
	   "source" = "System" }
)	   

$DefaultCriticalEvents = @(
	@{ "eventlog" = "Directory Service";
	   "mode" = 1 }
	@{ "eventlog" = "File Replication Service";
	   "mode" = 1 }
	@{ "eventlog" = "HardwareEvents";
	   "mode" = 1 }
	@{ "eventlog" = "System";
	   "mode" = 0 }
	@{ "eventlog" = "Application";
	   "mode" = 0 }
)

$DoNotMonitorServices = @( # Services you do not wish to monitor, regardless
	"wuauserv", # Windows Update Service. Does not run continously.
	"gupdate", "gupdatem", # Google Update Services. Does not always run.
	"AdobeARMservice", # Another service you may not want to monitor
	"Windows Agent Maintenance Service", # Clean up after N-Able
	"Windows Agent Service",
	"RSMWebServer"
)
$AlwaysMonitorServices = @( # Services that always are to be monitored if present and autorun
	"wecsvc" # Windows Event Collector
)
	

## VARIUS FUNCTIONS
# 
function New-MAXfocusCheck ([string]$checktype, 
							[string]$option1,
							[string]$option2,
							[string]$option3,
							[string]$option4,
							[string]$option5,
							[string]$option6) {
	Switch ($checktype) {
		"DriveSpaceCheck" {
			$object = "" | Select checktype,checkset,driveletter,freespace,spaceunits
			$object.checktype = $checktype
			$object.checkset = "247"
			$object.driveletter = $option1
			$object.freespace = $FreeSpace
			$object.spaceunits = $SpaceUnits
		}
		"DiskSpaceChange" {
			$object = "" | Select checktype,checkset,driveletter,threshold
			$object.checktype = $checktype
			$object.checkset = "DSC"
			$object.driveletter = $option1
			$object.threshold = $DiskSpaceChange
		}
		"WinServiceCheck" {
			$object = "" | Select checktype,checkset,servicename,servicekeyname,failcount,startpendingok,restart,consecutiverestartcount,cumulativerestartcount
			$object.checktype = $checktype
			$object.checkset = "247"
			$object.servicename = $option1
			$object.servicekeyname = $option2
			$object.failcount = 1 # How many consecutive failures before check fails
			$object.startpendingok = 0 # Is Startpending OK, 1 0 Yes, 0 = No
			$object.restart = 1 # Restart = 1 (Restart any stopped service as default)
			$object.consecutiverestartcount = 2 # ConsecutiveRestartCount = 2 (Fail if service doesnt run after 2 tries)
			$object.cumulativerestartcount = "4|24"  # Cumulative Restart Count = 4 in 24 hours
		}
		"PerCounterCheck" {
			$object = "" | Select checktype,checkset,type,instance,threshold1,threshold2,threshold3,threshold4
			$object.checktype = $checktype
			$object.checkset = "247"
			Switch ($option1) {
				"Queue" {
					$object.type = 1
					If ($option2) {
						$object.threshold1 = $option2
					} Else {
						$object.threshold1 = 2 # Recommended threshold by Microsoft for physical servers.
					}
				}
				"CPU" {
					$object.type = 2
					If ($option2) {
						$object.threshold1 = $option2
					} Else {
						$object.threshold1 = 99 # We are talking ALERTS here. We are not doing this for fun.
					}
				}
				"RAM" {
					$object.type = 3
					$object.instance = 2 # Fails if committed memory is more than twice that of physical RAM
					$object.threshold1 = 10 # Fails if average available RAM is less than 10 MB
					$object.threshold2 = 5000 # Fails if average pages/sec > 5000
					$object.threshold3 = 99 # % Page file usage
					If ($option2) {			# Nonpaged pool
						$object.threshold4 = $option2
					} Else {
						$object.threshold4 = 128
					}
				}
				"Net" {
					$object.type = 4
					$object.instance = $option2
					$object.threshold1 = 80 # We don't want alerts unless there really are problems 
				}
				"Disk" {
					$object.type = 5
					$object.instance = $option2
					If ($option3) {			
						$object.threshold1 = $option3  # Read queue
						$object.threshold2 = $option3  # Write queue
					} Else {
						$object.threshold1 = 2  # Read queue
						$object.threshold2 = 2  # Write queue
					}
					$object.threshold3 = 100 # Disk time, and again we are talking ALERTS
				}
			}
		}
		"PingCheck" {
			$object = "" | Select checktype,checkset,name,pinghost,failcount
			$object.checktype = $checktype
			$object.checkset = "247"
			$object.name = $option1
			$object.pinghost = $option2
		}
		"BackupCheck" {
			$object = "" | Select checktype,checkset,BackupProduct,checkdays,partial,count
			$object.checktype = $checktype
			$object.checkset = "DSC"
			$object.backupproduct = $option1
			$object.checkdays = "MTWTFSS"
			$object.partial = 0
			If ($option2) {
				$object.count = $option2
			} Else {
				$object.count = 99 # Dont know jobcount, make check fail 
			}
		}
		"AVUpdateCheck" {
			$object = "" | Select checktype,checkset,AVProduct,checkdays
			$object.checktype = $checktype
			$object.checkset = "DSC"
			$object.avproduct = $option1
			$object.checkdays = "MTWTFSS"
		}
		"CriticalEvents" {
			$object = "" | Select checktype,checkset,eventlog,mode,option
			$object.checktype = $checktype
			$object.checkset = "DSC"
			$object.eventlog = $option1
			If ($option2) {
				$object.mode = $option2
			} Else {
				$object.mode = 0 # Report mode
			}
			$object.option = 0
	  	}
		"EventLogCheck" {
			$object = "" | Select checktype,checkset,uid,log,flags,ids,source,contains,exclude,ignoreexclusions
			$object.checktype = $checktype
			$object.checkset = "DSC"
			$object.uid = $option1
			$object.log = $option2
			$object.flags = $option3
			$object.source = $option4
			If($option5) {
				$object.ids = $option5
			} Else {
				$object.ids = "*"
			}
			$object.contains = ""
			$object.exclude = ""
			$object.ignoreexclusions = "false"
	   }
	   "VulnerabilityCheck" {
	   		$object = "" | Select checktype,checkset,schedule1,schedule2,devtype,mode,autoapproval,scandelaytime,failureemails,rebootdevice,rebootcriteria
			$object.checktype = $checktype
			$object.checkset = "DSC"
			$object.schedule1 = ""
			$object.schedule2 = "2|0|{0}|0|{1}|0" -f $option1, $option2
			If ($AgentMode -eq "Server") {
				$object.devtype = 2
			} Else {
				$object.devtype = 1
			}
			$object.mode = 0
			$object.autoapproval = "2|2|2|2|2,2|2|2|2|2"
			$object.scandelaytime = ""
			$object.failureemails = 1
			$object.rebootdevice = 0
			$object.rebootcriteria = "0|1"
	   }
	}
	Return $object
}

function Convert-MAXfocusXmlToObject ([System.Xml.XmlElement]$xmlCheck) {
	$FilePath =  $xmlCheck.BaseURI -replace "file:///", ""
	$Set = (Split-Path $FilePath -Leaf).Substring(0,3)
	If ($Set -eq "ST_") {$Set = "ST"}
	$object = "" | Select checktype,checkset
	$object.checktype = $xmlCheck.LocalName;
	$object.checkset = $Set
	ForEach ($Node in $xmlCheck.ChildNodes) {
		$object | Add-Member -MemberType NoteProperty -Name $Node.Name -Value $Node.InnerText
	}
	Return $object
}

function Convert-MAXfocusObjectToXml ([System.Object]$object, $uid) {
	$xmlCheck = $XmlConfig[$object.checkset].CreateElement($object.checktype)
	$xmlCheck.SetAttribute('modified', '1')
	$xmlCheck.SetAttribute('uid', $uid)
		
	Foreach ($property in $object|Get-Member -MemberType NoteProperty) {
		 If ("checkset", "checktype" -notcontains $property.Name) {
			$xmlProperty = $XmlConfig[$object.checkset].CreateElement($property.Name)
			$propertyValue = $object.($property.Name)
			# Is this a number?
			If ([bool]($propertyValue -as [int]) -or $propertyValue -eq "0") { 
				# If its a number we just dump it in there
				$xmlProperty.set_InnerText($propertyValue)
			} Else { 
				# If it is text we encode it in CDATA
				$rs = $xmlProperty.AppendChild($XmlConfig[$object.checkset].CreateCDataSection($propertyValue))
			}
			# Add Property to Check element
			$rs = $xmlCheck.AppendChild($xmlProperty)
		}
	}
	Return $xmlCheck
}

function Convert-MAXfocusChecksToObjects ([array]$xmlChecks) {
	$objects = @{}
	ForEach ($xmlCheck in $xmlChecks) {
		If ($xmlCheck.uid -is [System.Array]) {
			$uid = $xmlCheck.uid[0]
		} Else {
			$uid= $xmlCheck.uid
		}
		$objects[$uid] = Convert-MAXfocusXmlToObject $xmlCheck
	}
	Return $objects
}

function Convert-MAXfocusObjectsToChecks ([hashtable]$objects) {
	ForEach ($object in $objects.GetEnumerator()) {
		$xmlCheck = Convert-MAXfocusObjectToXml $object.Value $object.Name
		# Add Check to file in check section
		$rs = $XmlConfig[$object.Value.checkset].checks.AppendChild($xmlCheck)
	}
}

function Get-MAXfocusChecks ([string]$checktype, [string]$property, [string]$value) {
	$return = @{}
	Foreach ($object in $objConfig.GetEnumerator()) {
		If ($object.Value.checktype -ne $checktype) { Continue }
		If ($value) {
			If ($object.Value.$property -eq $value) { $return[$object.Key]  = $object.Value }
		} Else {
			$return[$object.Key]  = $object.Value
		}
	}
	Return $return
}

function Remove-MAXfocusChecks ([hashtable]$ChecksToRemove) {
	If (!($ChecksToRemove.Count -gt 0)) { Return }
	ForEach ($object in $ChecksToRemove.GetEnumerator()) {
		$objConfig.Remove($object.Key)
		$RemoveChecks[$object.Key] = $object.Value
	}
	$Global:ConfigChanged = $true
}

function Get-MAXfocusCheckUid ([PSObject]$Check) {
	$Checks = Get-MAXfocusChecks $Check.checktype
	Foreach ($object in $Checks.GetEnumerator()) {
		$Match = $true
		Foreach ($property in $Check.PSObject.properties) {
			$name = $property.Name
			If  ($name -eq "uid") { Continue }
			$value = $property.Value
			If ($object.Value.$name -ne $value) { 
				$Match = $false
				Continue
			}
		}
		If ($Match) {		
			Return $object.Key
		}
	}
	Return $false
}

function Exist-MAXfocusCheck ([PSObject]$Check) {
	$result = Get-MAXfocusCheckUid $Check
	If ($result) {
		Return $true
	} Else {
		Return $false
	}
}

function Add-MAXfocusCheck ([PSObject]$Check, [HashTable]$oldChecks, [int]$checkuid) {
	If (!($checkuid)) {
		$checkuid = $Global:uid
	}
	If ($oldChecks.Count -gt 0) {
		If ($Replace) {
			$olduid = Get-MAXfocusCheckUid $Check
			If ($olduid) {
				$oldChecks.Remove($olduid)
			}
			Remove-MAXfocusChecks $oldChecks
		} Else {
			Return
		}
	}
	If (!(Exist-MAXfocusCheck $Check)) {
		$objConfig[$checkuid] = $Check
		$NewChecks[$checkuid] = $Check
		$Global:ConfigChanged = $true
		If ($checkuid -eq $Global:uid) { $Global:uid++ }
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

# Small function to give missing checks output some structure
function Format-Output($CheckTable) {
	$Result = @()
	Foreach ($Check in $CheckTable.GetEnumerator()){
		$CheckItem = $Check.Value
		Switch ($CheckItem.checktype)	{
			{"DriveSpaceCheck","DiskSpaceChange" -contains $_ } {
				$Result += $CheckItem.checktype + " " + $CheckItem.driveletter }
			"WinServicecheck" {
				$Result += $CheckItem.checktype + " " + $CheckItem.servicename }
			"PerfCounterCheck" { 
				Switch ($CheckItem.type) {
					"1" { $Result += $CheckItem.checktype + " Processor Queue Length"}
					"2" { $Result += $CheckItem.checktype + " Average CPU Usage"}
					"3" { $Result += $CheckItem.checktype + " Memory Usage"}
					"4" { $Result += $CheckItem.checktype + " Network Interface " + $CheckItem.instance}
					"5" { $Result += $CheckItem.checktype + " Physical Disk " + $CheckItem.instance}
				}}
			{"PingCheck","AVUpdateCheck","BackupCheck","FileSizeCheck" -contains $_ } {
				$Result += $CheckItem.checktype + " " + $CheckItem.name }
			"EventLogCheck" {
				$Result += $CheckItem.checktype + " " + $CheckItem.log }
			"CriticalEvents" {
				switch ($CheckItem.mode) { 
					0 { $Result += $CheckItem.checktype + " " + $CheckItem.eventlog + " (Report)" }
					1 { $Result += $CheckItem.checktype + " " + $CheckItem.eventlog + " (Alert)" }}}
			default { 
				$Result += $CheckItem.checktype }

		}
		
	}
	$result += "" # Add blank line
	$Result
}

## Adopted from https://gallery.technet.microsoft.com/scriptcenter/Get-SQLInstance-9a3245a0
## I changed it to check both 32 and 64 bit
Function Get-SQLInstance {
	$Computer = $env:COMPUTERNAME
	Try { 
	    $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $Computer) 
	    $baseKeys = "SOFTWARE\\Microsoft\\Microsoft SQL Server",
	    "SOFTWARE\\Wow6432Node\\Microsoft\\Microsoft SQL Server"
		ForEach ($basekey in $baseKeys)
		{
		    If ($reg.OpenSubKey($basekey)) {
		        $regPath = $basekey
		    } Else {
		        Continue
		    }
		    $regKey= $reg.OpenSubKey("$regPath")
		    If ($regKey.GetSubKeyNames() -contains "Instance Names") {
		        $regKey= $reg.OpenSubKey("$regpath\\Instance Names\\SQL" ) 
		        $instances = @($regkey.GetValueNames())
		    } ElseIf ($regKey.GetValueNames() -contains 'InstalledInstances') {
		        $isCluster = $False
		        $instances = $regKey.GetValue('InstalledInstances')
		    } Else {
		        Continue
		    }
		    If ($instances.count -gt 0) { 
		        ForEach ($instance in $instances) {
		            $nodes = New-Object System.Collections.Arraylist
		            $clusterName = $Null
		            $isCluster = $False
		            $instanceValue = $regKey.GetValue($instance)
		            $instanceReg = $reg.OpenSubKey("$regpath\\$instanceValue")
		            If ($instanceReg.GetSubKeyNames() -contains "Cluster") {
		                $isCluster = $True
		                $instanceRegCluster = $instanceReg.OpenSubKey('Cluster')
		                $clusterName = $instanceRegCluster.GetValue('ClusterName')
		                $clusterReg = $reg.OpenSubKey("Cluster\\Nodes")                            
		                $clusterReg.GetSubKeyNames() | ForEach {
		                    $null = $nodes.Add($clusterReg.OpenSubKey($_).GetValue('NodeName'))
		                }
		            }
		            $instanceRegSetup = $instanceReg.OpenSubKey("Setup")
		            Try {
		                $edition = $instanceRegSetup.GetValue('Edition')
		            } Catch {
		                $edition = $Null
		            }
		            Try {
		                $ErrorActionPreference = 'Stop'
		                #Get from filename to determine version
		                $servicesReg = $reg.OpenSubKey("SYSTEM\\CurrentControlSet\\Services")
		                $serviceKey = $servicesReg.GetSubKeyNames() | Where {
		                    $_ -match "$instance"
		                } | Select -First 1
		                $service = $servicesReg.OpenSubKey($serviceKey).GetValue('ImagePath')
		                $file = $service -replace '^.*(\w:\\.*\\sqlservr.exe).*','$1'
		                $version = (Get-Item ("\\$Computer\$($file -replace ":","$")")).VersionInfo.ProductVersion
		            } Catch {
		                #Use potentially less accurate version from registry
		                $Version = $instanceRegSetup.GetValue('Version')
		            } Finally {
		                $ErrorActionPreference = 'Continue'
		            }
		            New-Object PSObject -Property @{
		                Computername = $Computer
		                SQLInstance = $instance
		                Edition = $edition
						BitVersion = {Switch -regex ($basekey) {
							"Wow6432Node" { '32-bit' }
							Default { '64-bit' }
						}}.InvokeReturnAsIs()
		                Version = $version
		                Caption = {Switch -Regex ($version) {
		                    "^14" {'SQL Server 2014';Break}
		                    "^11" {'SQL Server 2012';Break}
		                    "^10\.5" {'SQL Server 2008 R2';Break}
		                    "^10" {'SQL Server 2008';Break}
		                    "^9"  {'SQL Server 2005';Break}
		                    "^8"  {'SQL Server 2000';Break}
		                    Default {'Unknown'}
		                }}.InvokeReturnAsIs()
		                isCluster = $isCluster
		                isClusterNode = ($nodes -contains $Computer)
		                ClusterName = $clusterName
		                ClusterNodes = ($nodes -ne $Computer)
		                FullName = {
		                    If ($Instance -eq 'MSSQLSERVER') {
		                        $Computer
		                    } Else {
		                        "$($Computer)\$($instance)"
		                    }
		                }.InvokeReturnAsIs()
						FullRecoveryModel = ""
		            }
		        }
		    }
		}
	} Catch { 
	    Write-Warning ("{0}: {1}" -f $Computer,$_.Exception.Message)
	}
}

function Get-TMScanType {
	$tmlisten = Get-WmiObject Win32_Service | where { $_.Name -eq "tmlisten" }
	$TrendDir = Split-Path $tmlisten.PathName.Replace( '"',"") -Parent
	$SmartPath = "{0}\*icrc`$oth.*" -f $TrendDir
	$ConvPath = "{0}\*lpt`$vpn.*" -f $TrendDir
	$SmartScan = Test-Path $SmartPath
	$ConvScan = Test-Path $ConvPath
	
	If (($SmartScan) -and ($ConvScan)) {
		$SmartFile = Get-Item $SmartPath | Sort LastAccessTime -Descending | Select -First 1
		$ConvFile = Get-Item $ConvPath | Sort LastAccessTime -Descending | Select -First 1
		If ($SmartFile.LastAccessTime -gt $ConvFile.LastAccessTime) {
			$ConvScan = $false
		} Else {
			$SmartScan = $false
		}
	}
	
	If ($SmartScan) {
		Return "Smart"
	} ElseIf ($ConvScan) {
		Return "Conventional"
	} Else {
		Return $false
	}
}

## SETUP ENVIRONMENT
# Find "Advanced Monitoring Agent" service and use path to locate files
$gfimaxagent = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq 'Advanced Monitoring Agent' }
$gfimaxexe = $gfimaxagent.PathName
$gfimaxpath = Split-Path $gfimaxagent.PathName.Replace('"',"") -Parent

# XML Document objects
$XmlConfig = @{}
$objConfig = @{}
$AgentConfig = New-Object -TypeName XML
$DeviceConfig = New-Object -TypeName XML

# XML Document Pathnames
$XmlFile = @{}
$AgentFile = $gfimaxpath + "\agentconfig.xml"
$DeviceFile = $gfimaxpath + "\Config.xml"
$LastChangeFile = $gfimaxpath + "\LastChange.log"

# We need an array of hashes to remember which checks to add
$NewChecks = @()

$Sets = @("247", "DSC")

$IniFile = $gfimaxpath + "\settings.ini"
$ConfigChanged = $false
$settingsChanged = $false

# Read ini-files
$settingsContent = Get-IniContent($IniFile)
$servicesContent = Get-IniContent($gfimaxpath + "\services.ini")

# First of all, check if it is safe to make any changes
If ($Apply) {
	# Make sure a failure to aquire settings correctly will disable changes
	$Apply = $false
	If ($settingsContent["DAILYSAFETYCHECK"]["RUNTIME"]) { # This setting must exist
		$lastRuntime = $settingsContent["DAILYSAFETYCHECK"]["RUNTIME"]
		[int]$currenttime = $((Get-Date).touniversaltime() | get-date -UFormat %s) -replace ",","." # Handle decimal comma 
		$timeSinceLastRun = $currenttime - $lastRuntime
		If($lastRuntime -eq 0 -or $timeSinceLastRun -gt 360){
			# If we have never been run or it is at least 6 minutes ago
			# enable changes again
			$Apply = $true
		}
	}
	If (!($Apply)) {
		Write-Host "Changes Applied:"
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
		$objConfig += Convert-MAXfocusChecksToObjects @($XmlConfig[$Set].checks.ChildNodes)
	}
	$XmlConfig[$Set]  = New-Object -TypeName XML
	$decl = $XmlConfig[$Set].CreateXmlDeclaration("1.0", "ISO-8859-1", $null)
	$rootNode = $XmlConfig[$Set].CreateElement("checks")
	$result = $rootNode.SetAttribute("modified", "1")
	$result = $XmlConfig[$Set].InsertBefore($decl, $XmlConfig[$Set].DocumentElement)
	$result = $XmlConfig[$Set].AppendChild($rootNode)
	
}

$MaxUid = $objConfig.Keys | Measure -Maximum
$InUseUid = $MaxUid.Maximum + 1

# Get next available UID from INI file
# $uid = [int]$settingsContent["GENERAL"]["NEXTCHECKUID"]
# Ini file cannot be trusted if script checks are being used
$SettingsUid = $settingsContent["GENERAL"]["NEXTCHECKUID"]

If($SettingsUid -gt $InUseUid) {
	[int]$uid = $SettingsUid
} Else {
	[int]$uid = $InUseUid
}

If ($ReUid) {
	# So, we have messed up your configuration files? We will try to fix them...
	$NewObjConfig = @{}
	ForEach ($key in $objConfig.Keys) {
		$NewObjConfig[$uid] = $objConfig[$key]
		$uid++
	}
	$objConfig = $NewObjConfig
}

# Read agent config
$AgentConfig.Load($AgentFile)

# Read autodetected machine info
$DeviceConfig.Load($DeviceFile)


# The UID problems caused trouble with web protection check. But it can be fixed.
#$WebProtection = @($XmlConfig[$Set].checks.wpcategorycounternotificationcheck)
#If ($WebProtection.Count -gt 1)
#{
#	$MinUid = (Get-GFIMAXChecks ($WebProtection | select uid) "uid" | Measure -Minimum).minimum
#	$WrongCheck = $XmlConfig[$Set].checks.SelectSingleNode("wpcategorycounternotificationcheck[@uid=$MinUid]")
#	$null = $XmlConfig[$Set].checks.RemoveChild($WrongCheck)
#	$ConfigChanged = $true
#}


# Check Agent mode, workstation or server
$AgentMode = $AgentConfig.agentconfiguration.agentmode

# Set interval according to $AgentMode
If ($AgentMode = "server") { $247Interval = $ServerInterval }
Else { $247Interval = $PCInterval }

# Check if INI file is correct
If ($settingsContent["247CHECK"]["ACTIVE"] -ne "1") {
	$settingsContent["247CHECK"]["ACTIVE"] = "1"
	$ConfigChanged = $true
	$settingsChanged = $true
}

If ($settingsContent["247CHECK"]["INTERVAL"] -ne $247Interval) {
	$settingsContent["247CHECK"]["INTERVAL"] = $247Interval
	$ConfigChanged = $true
	$settingsChanged = $true
}

If ($settingsContent["DAILYSAFETYCHECK"]["ACTIVE"] -ne "1") {
	$settingsContent["DAILYSAFETYCHECK"]["ACTIVE"] = "1"
	$ConfigChanged = $true
	$settingsChanged = $true
}

If ($settingsContent["DAILYSAFETYCHECK"]["HOUR"] -ne $DSCHour) {
	$settingsContent["DAILYSAFETYCHECK"]["HOUR"] = $DSCHour
	$ConfigChanged = $true
	$settingsChanged = $true
}


# We need a hashtable to remember which checks to add
$NewChecks = @{}
$RemoveChecks = @{}

# Check for new services that we'd like to monitor'

## DRIVESPACECHECK
If ($DriveSpaceCheck) {
	# Process parameters that need processing
	$SpaceMatch = "^([0-9]+)([gmb%]+)"
	$Spacetype = $DriveSpaceCheck -replace $SpaceMatch,'$2'
	$FreeSpace = $DriveSpaceCheck -replace $SpaceMatch,'$1'

	Switch ($Spacetype.ToUpper().Substring(0,1)) { # SpaceUnits: 0 = Bytes, 1 = MBytes, 2 = GBytes, 3 = Percent
		"B" { $SpaceUnits = 0 }
		"M" { $SpaceUnits = 1 }
		"G" { $SpaceUnits = 2 }
		"%" { $SpaceUnits = 3 }
	}
	
	# Get current fixed drives from WMI
	$DetectedDrives = GET-WMIOBJECT -query "SELECT * from win32_logicaldisk where DriveType = '3'" | select -Expandproperty DeviceID
	
	# Add any disk not currently in CurrentDiskSpaceChecks
	foreach ($Disk in $DetectedDrives) {
		If (($Disk -ne $env:SystemDrive) -and ($AgentMode -eq "workstation")){
			# Workstations are only monitoring %SystemDrive%
			Continue
		}
		$DriveLetter = $Disk + "\"
		$NewCheck = New-MAXfocusCheck "DriveSpaceCheck" $DriveLetter
		$oldChecks = Get-MAXfocusChecks "DriveSpaceCheck" "driveletter" $DriveLetter
		Add-MAXfocusCheck $NewCheck $oldChecks
	}
}


## DISKSPACECHANGE
#  We only use this on servers
If (($DiskSpaceChange) -and ($AgentMode -eq "server")) {
		
	# Get current fixed drives from WMI
	$DetectedDrives = GET-WMIOBJECT -query "SELECT * from win32_logicaldisk where DriveType = '3'" | select -ExpandProperty DeviceID

	# Add any disk not currently in CurrentDiskSpaceChecks
	foreach ($Disk in $DetectedDrives) {
		$DriveLetter = $Disk + "\"
		$NewCheck = New-MAXfocusCheck "DiskSpaceChange" $DriveLetter
		$oldChecks = Get-MAXfocusChecks "DiskSpaceChange" "driveletter" $DriveLetter
		Add-MAXfocusCheck $NewCheck $oldChecks
	}
}

## WINSERVICECHECK
#  By default we only monitor services on servers

If (("All", "Default" -contains $WinServiceCheck) -and ($AgentMode -eq "server")) {
	# We really dont want to keep annoying services in our setup
	Foreach ($service in $DoNotMonitorServices) {
		$oldChecks = Get-MAXfocusChecks "WinServiceCheck" "servicekeyname" $service
		Remove-MAXfocusChecks $oldChecks
	}
	# An array to store names of services to monitor
	$ServicesToMonitor = @()

	## SERVICES TO MONITOR
	If ($WinServiceCheck -eq "Default") { # Only add services that are listed in services.ini

		# Get all currently installed services with autostart enabled from WMI
		$autorunsvc = Get-WmiObject Win32_Service |  
		Where-Object { $_.StartMode -eq 'Auto' } | select Displayname,Name
		
		Foreach ($service in $autorunsvc) {
			If (($servicesContent["SERVICES"][$service.Name] -eq "1") -or ($AlwaysMonitorServices -contains $service.Name)) {
				$ServicesToMonitor += $service.Name
			}
		}
	} Else { 
	  	# Add all services configured to autostart if pathname is outside %SYSTEMROOT%
		# if the service is currently running
		$autorunsvc = Get-WmiObject Win32_Service | 
		Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName -notmatch ($env:systemroot -replace "\\", "\\") -and $_.State -eq "Running"} | select Displayname,Name
		Foreach ($service in $autorunsvc) {
			$ServicesToMonitor += $service
		}

		# Add all services located in %SYSTEMROOT% only if listed in services.ini
		$autorunsvc = Get-WmiObject Win32_Service | 
		Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName -match ($env:systemroot -replace "\\", "\\") } | select Displayname,Name
		Foreach ($service in $autorunsvc) {
			If (($servicesContent["SERVICES"][$service.Name] -eq "1") -or ($AlwaysMonitorServices -contains $service.Name)) {
				$ServicesToMonitor += $service
			}
		}
	}

	# Ignore Web Protection Agent
	$DoNotMonitorServices += "WebMonAgent"
	## SERVICES TO ADD
	Foreach ($service in $ServicesToMonitor) {
		If ($DoNotMonitorServices -notcontains $service.Name) {
			$NewCheck = New-MAXfocusCheck "WinServiceCheck" $service.DisplayName $service.Name
			$oldChecks = Get-MAXfocusChecks "WinServiceCheck" "servicekeyname" $service.Name
			Add-MAXfocusCheck $NewCheck $oldChecks
		}
	}

}

## Detect any databases and add relevant checks
If ($MSSQL) {
	
	# Get any SQL services registered on device
	$SqlInstances = @(Get-SQLInstance)

	If ($SqlInstances.count -gt 0) {
		# Load SQL server management assembly
		#[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null 
	
		Foreach ($Instance in $SqlInstances){
			$sqlService = Get-WmiObject Win32_Service | where { $_.DisplayName -match $instance.SQLInstance -and $_.PathName -match "sqlservr.exe"}
			$NewCheck = New-MAXfocusCheck "WinServiceCheck" $sqlService.DisplayName $sqlService.Name
			$oldChecks = Get-MAXfocusChecks "WinServiceCheck" "servicekeyname" $sqlService.Name
			Add-MAXfocusCheck $NewCheck $oldChecks
		
	
		# Create a managment handle for this instance
#		$sqlhandle = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $Instance.FullName
#		Try {
#			# Retrieve any databases on instance
#			$dbs = $sqlhandle.Databases 
#			Foreach ($db in $dbs) {
#				# Loop through logfiles and retain directory
#				$locations = @()
#				$logfiles = $db.LogFiles | select -ExpandProperty Filename
#				If ($logfile.Count -gt 0) {
#					Foreach ($logfile in $logfiles) {
#						$parent = Split-Path -Parent $logfile
#						If ($locations -notcontains $parent) { $locations += $parent }
#					}
#					Foreach ($location in $locations) {
#						If (!($CurrentFileSizeChecks -Contains "0|" + $location + "|*.ldf")) {
#								$NewChecks += @{	"checktype" = "FileSizeCheck";
#									"checkset" = $Set;
#									"Name" = $instance;
#									"Threshold" = "5"; "Units" = "3|0";
#										# Units: 0 = Bytes, 1 = KBytes, 2 = MBytes, 3 = GBytes
#										# Units, element 2: 0 = Greater Than, 1 = Less Than
#									"Include" = "0|" + $location + "|*.ldf";
#										# First element: 1 = Include subfolders, 0 = This folder only
#										# Second element: Folder where files are located
#										# Third element: File pattern
#									"Exclude" = "" }# Same syntax as Include 
#						}
#					}
#				}
#				# Retrive RecoveryModel and save name if it isn't Simple
#				If ($db.RecoveryModel -ne "Simple") {
#					$Instance.FullRecoveryModel += $db.Name + " "
#				}
#			}
#		} Catch {
#			Write-Host ("SQL Server Detection: Access to {0} Failed" -F $Instance.FullName)
#		}
		}
	}
}



If ($Performance -and ($AgentMode -eq "server")) { # Performance monitoring is only available on servers
	$ThisDevice = Get-WmiObject Win32_ComputerSystem
	
	## Processor Queue
	If ($ThisDevice.Model -match "^virtual|^vmware") {
		# We are on a virtual machine
		$NewCheck = New-MAXfocusCheck "PerfCounterCheck" "Queue" "10"
	} Else {
		$NewCheck = New-MAXfocusCheck "PerfCounterCheck" "Queue"
	}
	$oldChecks = Get-MAXfocusChecks "PerfCounterCheck" "type" 1
	Add-MAXfocusCheck $NewCheck $oldChecks
	
	## CPU
	$NewCheck = New-MAXfocusCheck "PerfCounterCheck" "CPU"
	$oldChecks = Get-MAXfocusChecks "PerfCounterCheck" "type" 2
	Add-MAXfocusCheck $NewCheck $oldChecks
	
	## RAM
	[int]$nonpagedpool = 128
	If ([System.IntPtr]::Size -gt 4) { # 64-bit
		[int]$TotalMemoryInGB = $ThisDevice.TotalPhysicalMemory /(1024*1024)
		[int]$nonpagedpool = $nonpagedpool/1024*$TotalMemoryInGB
	}
	$NewCheck = New-MAXfocusCheck "PerfCounterCheck" "RAM" $nonpagedpool
	$oldChecks = Get-MAXfocusChecks "PerfCounterCheck" "type" 2
	Add-MAXfocusCheck $NewCheck $oldChecks
	
	## Net
	#  Not on Hyper-V
	If ($ThisDevice.Model -notmatch "^virtual") {
		$NetConnections = $DeviceConfig.configuration.networkadapters | select -ExpandProperty name | where {$_ -notmatch "isatap" -and $_ -notmatch "Teredo"}
		Foreach ($Adapter in $NetConnections) {
			$NewCheck = New-MAXfocusCheck "PerfCounterCheck" "Net" $Adapter
			$oldChecks = Get-MAXfocusChecks "PerfCounterCheck" "instance" $Adapter
			Add-MAXfocusCheck $NewCheck $oldChecks
		}
	}
	## Disk
	# Needs physical disks
	$PhysicalDisks =  $DeviceConfig.configuration.physicaldisks | select -ExpandProperty name | where {$_ -ne "_Total"}

	Foreach	($Disk in $PhysicalDisks ) {
		$NewCheck = New-MAXfocusCheck "PerfCounterCheck" "Disk" $Disk
		$oldChecks = Get-MAXfocusChecks "PerfCounterCheck" "Type" 5
		Add-MAXfocusCheck $NewCheck $oldChecks
	}
}

if($PingCheck -and ($AgentMode -eq "server")) { # Pingcheck only supported on servers
	# Get the two closest IP addresses counted from device
	$trace = @()
	$trace = Invoke-Expression "tracert -d -w 10 -h 2 8.8.8.8" |
       Foreach-Object {
           if ($_ -like "*ms*" ) {
               $chunks = $_ -split "  " | Where-Object { $_ }
               $ip = $chunks[-1]
			   $ip = @($ip)[0].Trim() -as [IPAddress] 
			   $ip
       }
	}
	# If the firewall does not answer to ICMP we wont have an array
	If ($trace.Count -gt 1)	{ $trace = $trace[1]}
	If ($trace -is [Net.IPAddress]) {
		$Newcheck = New-MAXfocusCheck "PingCheck" "Router Next Hop" $trace
		$oldChecks = Get-MAXfocusChecks "PingCheck" "pinghost" $trace
		Add-MAXfocusCheck $NewCheck $oldChecks
	}
	
}

If ($Backup) {
	$DetectedBackups = $DeviceConfig.configuration.backups | Select -ExpandProperty name
	$oldChecks = Get-MAXfocusChecks "BackupCheck"
	If ($oldChecks.Count -eq 0) {
		Foreach ($BackupProduct in $DetectedBackups){
			$JobCount = 99
			Switch ($BackupProduct) {
				"Backup Exec" {
					$bengine =  Get-WmiObject win32_service | where { $_.PathName -match "bengine.exe" -and $_.DisplayName -match "Backup Exec"}
					If (!($bengine)){
						# Only add backup exec check if job engine is present
						Continue
					}
				}
				"Managed Online Backup" {
					$MOBsessionFile = "$env:programdata\Managed Online Backup\Backup Manager\SessionReport.xml"
					[xml]$MOBsessions = Get-Content $MOBsessionFile

					$MOBplugins = @()
					ForEach ($Session in $MOBsessions.SessionStatistics.Session){
						If ($MOBplugins -notcontains $Session.plugin){
							$MOBplugins += $Session.plugin
						}
					}
					$JobCount = $MOBplugins.Count
				} 
				"Veeam" {
					Add-PSSnapin VeeamPSSnapin -ErrorAction SilentlyContinue
					If ((Get-PSSnapin "*Veeam*" -ErrorAction SilentlyContinue) -eq $null){ 
						Write-Host "Unable to load Veeam snapin, you must run this on your Veeam backup server, and the Powershell snapin must be installed.`n`n"
					} Else {
						$JobCount = (Get-VBRJob|select Name).Count
					}
				}
				"AppAssure v5" {
					# Accept Default Jobcount, but add check
				}
				Default {
					# Don't add any checks
					Continue
				}
			}
			# We cannot know how many jobs or which days. Better a 
			# failed check that someone investigates than no check at all
			$NewCheck = New-MAXfocusCheck "BackupCheck" $BackupProduct $JobCount
			Add-MAXfocusCheck $NewCheck
								
		}
	}
}

If ($Antivirus) {
	$DetectedAntiviruses =  $DeviceConfig.configuration.antiviruses | Select -ExpandProperty name
	$oldChecks = Get-MAXfocusChecks "AVUpdateCheck"
	If ($oldChecks.Count -eq 0) {
		Foreach ($AVProduct in $DetectedAntiviruses) {
			Switch -regex ($AVProduct) {
				'Windows Defender' { Continue }
				'Trend.+Conventional Scan' {
					If (Get-TMScanType -ne "Smart") { Continue }	
				}
				'Trend.+Smart Scan' {
					If (Get-TMScanType -ne "Conventional") { Continue }
				}
			}
			$NewCheck = New-MAXfocusCheck "AVUpdateCheck" $AVProduct
			Add-MAXfocusCheck $NewCheck
		}
	}
}


If ($LogChecks -and $AgentMode -eq "server") {
	# Get next Eventlog check UID from settings.ini
	Try {
		$rs = $settingsContent["TEST_EVENTLOG"]["NEXTUID"]
	} Catch {
		$settingsContent["TEST_EVENTLOG"] = @{ "NEXTUID" = "1" }
	}
	[int]$NextUid = $settingsContent["TEST_EVENTLOG"]["NEXTUID"]
	If ($NextUid -lt 1) { $NextUid = 1 }
	ForEach ($Check in $DefaultLogChecks) {
		$NewCheck = New-MAXfocusCheck "EventLogCheck" $NextUid $Check.log $Check.flags $Check.source $Check.ids
		$oldChecks = Get-MAXfocusChecks "EventLogCheck" "log" $Check.log
		Add-MAXfocusCheck $NewCheck $oldChecks
		$checkuid = Get-MAXfocusCheckUid $NewCheck
		If ($NewChecks.ContainsKey($checkuid)) {
			$NextUid++
		}
	}
	# Save updated Eventlog test UID back to settings.ini
	$settingsContent["TEST_EVENTLOG"]["NEXTUID"] = $NextUid
	
	# Get Windows Eventlog names on this device
	$LogNames = Get-WmiObject win32_nteventlogfile | select -ExpandProperty logfilename
	ForEach ($Check in $DefaultCriticalEvents) {
		# If this device doesn't have a targeted eventlog, skip the check
		If($LogNames -notcontains $Check.eventlog) { Continue }
		
		If ($Check["eventlog"] -eq "HardwareEvents") {
			#This guy is special. We need to check if there are any events
			$HardwareEvents = Get-WmiObject Win32_NTEventLogFile | where { $_.LogFileName -eq "HardwareEvents" }
			If ($HardwareEvents.NumberOfRecords -eq 0) {
				Continue
			}
		}
		# Add check if missing
		$NewCheck = New-MAXfocusCheck "CriticalEvents" $Check.eventlog $Check.mode
		$oldChecks = Get-MAXfocusChecks "CriticalEvents" "eventlog" $Check.eventlog
		Add-MAXfocusCheck $NewCheck $oldChecks
	}
}

## HOUSEKEEPING
#  Remove duplicate checks if found
$NewConfig = @{}
$Duplicates = $false
Foreach ($Check in $objConfig.GetEnumerator()) {
	$Instances = @{}
	$objCheck = $Check.Value
	Foreach ($object in $objConfig.GetEnumerator()) {
		$Match = $true
		Foreach ($property in $objCheck.PSObject.properties) {
			$name = $property.Name
			If  ($name -eq "uid") { Continue }
			$value = $property.Value
			If ($object.Value.$name -ne $value) { 
				$Match = $false
				Continue
			}
		}
		If ($Match) {		
			$Instances[$object.Key] = $object.Value
		}
	}
	# Add random occurence of check (Hashtables are not ordered) - should be only one, really
	Foreach ($Instance in $Instances.GetEnumerator()) {
		$NewConfig[$Instance.Key] = $Instance.Value
		Break
	}
	If ($instances.count -gt 1) {
		$Duplicates = $true
	}
}

If ($Duplicates) {
	Write-Host "Duplicate Checks found"
	Foreach ($object in $objConfig.GetEnumerator()) {
		IF (!($NewConfig.ContainsKey($object.Key))) {
			$RemoveChecks[$object.Key] = $object.Value
		}
	}
	$objConfig = $NewConfig
	$ConfigChanged = $true
}



If ($ConfigChanged) {
	$Today = (Get-Date).DayOfWeek.value__
	If (($Apply) -and ($Today -eq $WeekDay)) {
		
		# Update last runtime to prevent changes too often
		[int]$currenttime = $(get-date -UFormat %s) -replace ",","." # Handle decimal comma 
		$settingsContent["DAILYSAFETYCHECK"]["RUNTIME"] = $currenttime
		
		# Clear lastcheckday to make DSC run immediately
		$settingsContent["DAILYSAFETYCHECK"]["LASTCHECKDAY"] = "0"
		
		# Save updated NEXTCHECKUID
		$settingsContent["GENERAL"]["NEXTCHECKUID"] = $uid
		
		# Stop agent before writing new config files
		Stop-Service $gfimaxagent.Name
		
		# Recreate XML objects
		Convert-MAXfocusObjectsToChecks $objConfig
		
		# Save all relevant config files
		ForEach ($Set in $Sets) {
			$XmlConfig[$Set].Save($XmlFile[$Set])
		}
		Out-IniFile $settingsContent $IniFile
		
		# Start monitoring agent again
		Start-Service $gfimaxagent.Name
		If (Test-Path $LastChangeFile) {
			# Delete last changelog
			Get-Content $LastChangeFile
		}

		# Write output to Dashboard
		"Last Change applied {0}:" -f $(Get-Date) | Out-File $LastChangeFile
		"------------------------------------------------------" | Out-File -Append $LastChangeFile
		If ($RemoveChecks.Count -gt 0) {
			"`nRemoved the following checks to configuration file:" | Out-File -Append $LastChangeFile
			Format-Output $RemoveChecks | Out-File -Append $LastChangeFile
		}
		If ($NewChecks.Count -gt 0) {
			"`nAdded the following checks to configuration file:" | Out-File -Append $LastChangeFile
			Format-Output $NewChecks | Out-File -Append $LastChangeFile
		}
		If ($ReportMode) {
			Exit 0 # Needed changes have been reported, but do not fail the check
		} Else {
			Exit 1001 # Internal status code: Changes made
		}
	} Else {
		If (Test-Path $LastChangeFile) {
			# Print last change to STDOUT
			Write-Host "------------------------------------------------------"
			Get-Content $LastChangeFile
			Write-Host "------------------------------------------------------"
		}
		If ($Apply) {
			$DayNames = (New-Object System.Globalization.CultureInfo("en-US")).DateTimeFormat.DayNames
			Write-Host ("Following changes will be applied on {0}:" -f $DayNames[$Weekday - 1])
		} Else {
			Write-Host "Recommended changes:"
		}
		If ($RemoveChecks.Count -gt 0) {
			Write-Host "Checks to be removed:"
			Format-Output $RemoveChecks 
		}
		If ($NewChecks.Count -gt 0) {
			Write-Host "Checks to be added:"
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
	If (Test-Path $LastChangeFile) {
		# Print last change to STDOUT
		Write-Host "------------------------------------------------------"
		Get-Content $LastChangeFile
		Write-Host "------------------------------------------------------"
	}
	Write-Host "Current Configuration Verified  - OK:"
	If ($Performance) 		{ Write-Host "Performance Monitoring checks verified: OK"}
	If ($DriveSpaceCheck) 	{ Write-Host "Disk usage monitored on all harddrives: OK"}
	If ($WinServiceCheck) 	{ Write-Host "All Windows services are now monitored: OK"}
	If ($DiskSpaceChange) 	{ Write-Host "Disk space change harddrives monitored: OK"}
	If ($PingCheck) 		{ Write-Host "Pingcheck Router Next Hop check tested: OK"}
	If ($SqlInstances.count -gt 0) { Write-Host "SQL Server installed:"; $SqlInstances }
	If ($SMART) 			{ Write-Host "Physical Disk Health monitoring tested: OK"}
	If ($Backup) 			{ Write-Host "Unmonitored Backup Products not found: OK"}
	If ($Antivirus) 		{ Write-Host "Unmonitored Antivirus checks verified: OK"}
	Write-Host "All checks verified. Nothing has been changed."
	Exit 0 # SUCCESS
}

