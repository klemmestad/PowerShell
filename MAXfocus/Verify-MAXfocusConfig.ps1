<#
.Synopsis
   Compares existing configuration of a MAXfocus monitoring agent against
   default settings stored in this script. Can add missing default checks
   automatically.
.DESCRIPTION
   The script is to be uploaded to your dashboard account as a user script.
   It can run both as a script check and as a scheduled task. You select
   check types to verify on a agent by giving the script parameters.
.EXAMPLE
   Verify-MAXfocusConfig -Apply -All
.EXAMPLE
   Verify-MAXfocusConfig -Apply -WinServiceCheck All
.EXAMPLE
   Verify-MAXfocusConfig -Apply -Performance -SMART -ServerInterval 15 -All
.OUTPUTS
   Correct XML configuration files that will reconfigure an MAXfocus agent
   upon agent restart.
.LINK
   http://klemmestad.com/2014/12/22/automate-maxfocus-with-powershell/
.LINK
   https://www.maxfocus.com/remote-management/automated-maintenance
.VERSION
   1.25
.FUNCTIONALITY
   When the script finds that checks has to be added it will create valid XML
   entries and add them to agent configuration files. It uses Windows scheduled
   tasks to restart agent after the script completes.
#>

#Region SETTINGS
# A few settings are handled as parameters 
param (	
	[switch]$All = $false, # Accept all default check values in one go
	[switch]$Apply = $false, # -Apply will write new checks to configfiles and reload agent
	[string]$ReportMode = "On", # -ReportMode will report missing checks, but not fail the script
	[switch]$Performance = $false, # Set to $false if you do not want performance checks
	[switch]$PingCheck = $false, # This is useful on a Fault History report. Otherwise useless.
	[switch]$MSSQL = $false, # Detect SQL servers
	[switch]$SMART = $false, # Enable physical disk check if SMART status is available
	[switch]$Backup = $false, # Configure a basic backup check if a compatible product is recognized
	[switch]$Antivirus = $false, # Configure an Antivirus check if a compatible product is recognized
	[switch]$LogChecks = $false, # Configure default log checks
	[string]$DriveSpaceCheck = $null, # Freespace as number+unit, i.e 10%, 5GB or 500MB
	[string]$WinServiceCheck = "",# "All" or "DefaultOnly". 
	[string]$DiskSpaceChange, # percentage as integer
	[string]$ServerInterval = "15", # 5 or 15 minutes
	[string]$PCInterval = "60", # 30 or 60 minutes
	[string]$DSCHour = "8", # When DSC check should run in whole hours. Minutes not supported by agent.
	[switch]$Reset = $false, # A one-time reset switch that will remove overwrite existing checks in all chosen categories.
	[switch]$Debug = $false,
	[switch]$Verbose = $false,
	[string]$logfile, # A parameter always supplied by MAXfocus. We MUST accept it.
	[switch]$Library = $false # Used to source this script for its functions
)

If ($Debug) { $Verbose = $true}

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

If ($All)
{
	Output-Verbose "Parameter -All detected. Loading default values."
	## DEFAULT CHECKS
	$Performance = $true # Set to $false if you do not want performance checks
	$PingCheck = $false # This is useful on a Fault History report. Otherwise useless.
	$MSSQL = $true # Detect SQL servers
	$SMART = $true # Enable physical disk check if SMART status is available
	$Antivirus = $true # Configure an Antivirus check if a compatible product is recognized
	$DriveSpaceCheck = "10%" # Freespace as number+unit, i.e 10%, 5GB or 500MB
	$WinServiceCheck = "All" # "All" or "Default". 
	$DiskSpaceChange = 10 # percentage as integer
	$Backup = $true # Try to configure Backup Monitoring
	$LogChecks = $true # Configure default eventlog checks
	$ServerInterval = "5"
	$PCInterval = "30"
}

# Convert Reportmode to Boolean
If ($ReportMode -Match 'On') { 
	[bool]$ReportMode = $true 
} Else {
	[bool]$ReportMode = $false 
}

# Test DriveSpaceCheck
If (($DriveSpaceCheck) -and ($DriveSpaceCheck -match '\d+(%|MB|GB)$')) {
	Output-Verbose ('Parameter -DrivespaceCheck {0} validated OK.' -f $DriveSpaceCheck)
} ElseIf ($DriveSpaceCheck) {
	Output-Host ('ERROR: -DriveSpaceCheck {0} could not be validated. Use 10%, 10MB or 10GB where "10" is any integer.' -f $DriveSpaceCheck)
	Output-Host 'WARNING: Ignoring -DriveSpaceCheck.'
	$DriveSpaceCheck = ''
}

# Test WinServiceCheck
If (($WinServiceCheck) -and ('All', 'Default', 'DefaultOnly' -contains $WinServiceCheck)) {
	Output-Verbose ('Parameter  -WinServiceCheck {0} validated OK.' -f $WinServiceCheck)
} ElseIf ($WinServiceCheck) {
	Output-Host ('ERROR: -WinServiceCheck {0} could not be validated. Use All, Default or DefaultOnly' -f $WinServiceCheck)
	Output-Host 'WARNING: Ignoring -WinServiceCheck.'
	$WinServiceCheck = ''
}

# Test DiskSpaceChange
If ($DiskSpaceChange) {
	$x2 = 0
	$isNum = [System.Int32]::TryParse($DiskSpaceChange, [ref]$x2)
	If ($isNUM) {
		[int]$DiskSpaceChange = $DiskSpaceChange
		Output-Verbose ("Parameter -DiskSpaceChange {0} validated OK." -f $DiskSpaceChange)
	} Else {
		Output-Host ("ERROR: -DiskSpaceChange {0} could not be validated. Use a valid integer." -f $DiskSpaceChange)
		Output-Host 'WARNING: Ignoring -DiskSpaceChange.'
		[string]$DiskSpaceChange = ""
	}
}

# Test ServerInterval
If ("5", "15" -contains $ServerInterval) {
	Output-Verbose ('Parameter -ServerInterval {0} validated OK.' -f $ServerInterval)
} Else {
	Output-Host ('ERROR: -ServerInterval {0} could not be validated. Use 5 or 15.' -f $ServerInterval)
	Output-Host 'WARNING: Setting value of -ServerInterval to default of 15.'
	$ServerInterval = "15"
}

# Test PCInterval
If ("30", "60" -contains $PCInterval) {
	Output-Verbose ('Parameter -PCInterval {0} validated OK.' -f $PCInterval)
} Else {
	Output-Host ('ERROR: -PCInterval {0} could not be validated. Use 30 or 60.' -f $PCInterval)
	Output-Host 'WARNING: Setting value of -PCInterval to default of 60.'
	$PCInterval = "60"
}

# Test DSChour
If ($DSChour) {
	$x2 = 0
	$isNum = [System.Int32]::TryParse($DSChour, [ref]$x2)
	If (($isNUM) -and ($x2 -ge 0 -and $x2 -lt 24)) {
		Output-Verbose ("Parameter -DSChour {0} validated OK." -f $DSChour)
	} Else {
		Output-Host ("ERROR: -DSChour {0} could not be validated. Use a valid number between 0 (12 AM) and 23 (11 PM)." -f $DSChour)
		Output-Host 'WARNING: Setting value of -DSChour to default of 8.'
		[string]$DSChour = "8"
	}
}

# Set strict mode if running interactively. Very useful when testing new code
If (!((Get-WmiObject Win32_Process -Filter "ProcessID=$PID").CommandLine -match '-noni')) {
	Output-Debug "WARNING: Running Interactively. Using Strict Mode."
	Write-Warning "Running Interactively. Using Strict Mode."
	Set-StrictMode -Version 2
}
#EndRegion

#Region Functions
function Restart-MAXfocusService ([bool]$Safely=$true) {
	# Save all relevant config files
	If ($Safely) {	
		# Update last runtime to prevent changes too often
		[int]$currenttime = $(get-date -UFormat %s) -replace ",","." # Handle decimal comma 
		$settingsContent["DAILYSAFETYCHECK"]["RUNTIME"] = $currenttime
	}
	# Clear lastcheckday to make DSC run immediately
	$settingsContent["DAILYSAFETYCHECK"]["LASTCHECKDAY"] = "0"
	Out-IniFile $settingsContent $IniFile.Replace('.ini','.newini')
	# Save XML files to NEW files
	ForEach ($Set in $Sets) {
		$XmlConfig[$Set].Save($XmlFile[$Set].Replace('.xml','.newxml'))
	}
	
	# Prepare restartscript
	$RestartScript = $env:TEMP + "\RestartMAXfocusAgent.cmd"
	$RestartScriptContent = @"
net stop "Advanced Monitoring Agent"
cd "$gfimaxpath"
move /y 247_config.newxml 247_config.xml
move /y DSC_config.newxml DSC_config.xml
move /y settings.newini settings.ini
net start "Advanced Monitoring Agent"
Del /F "$RestartScript"
"@
	$RestartScriptContent | Out-File -Encoding OEM $RestartScript
	# Start time in the future
	$JobTime = (Get-Date).AddMinutes(-2)
	$StartTime = Get-Date $JobTime -Format HH:mm
	$TaskName = "Restart Advanced Monitoring Agent"
	$Result = &schtasks.exe /Create /TN $TaskName /TR "$RestartScript" /RU SYSTEM /SC ONCE /ST $StartTime /F 2>&1
	If ($Result) {
		Output-Debug "Restarting Agent using scheduled task now."
		$Result = &schtasks.exe /run /TN "$TaskName" 2>&1
	} 
		
	If ($LASTEXITCODE -ne 0) {
		Output-Host "SCHTASKS.EXE failed. Could not restart agent. Changes lost."
	}
}

function New-MAXfocusCheck (
	[string]$checktype, 
	[string]$option1,
	[string]$option2,
	[string]$option3,
	[string]$option4,
	[string]$option5,
	[string]$option6) {
	
	Switch ($checktype) {
		"DriveSpaceCheck" {
			$object = "" | Select driveletter,freespace,spaceunits
			$checkset = "247"
			$object.driveletter = $option1
			$object.freespace = $FreeSpace
			$object.spaceunits = $SpaceUnits
		}
		"DiskSpaceChange" {
			$object = "" | Select driveletter,threshold
			$checkset = "DSC"
			$object.driveletter = $option1
			$object.threshold = $DiskSpaceChange
		}
		"WinServiceCheck" {
			$object = "" | Select servicename,servicekeyname,failcount,startpendingok,restart,consecutiverestartcount,cumulativerestartcount
			$checkset = "247"
			$object.servicename = $option1
			$object.servicekeyname = $option2
			$object.failcount = 1 # How many consecutive failures before check fails
			$object.startpendingok = 0 # Is Startpending OK, 1 0 Yes, 0 = No
			$object.restart = 1 # Restart = 1 (Restart any stopped service as default)
			$object.consecutiverestartcount = 2 # ConsecutiveRestartCount = 2 (Fail if service doesnt run after 2 tries)
			$object.cumulativerestartcount = "4|24"  # Cumulative Restart Count = 4 in 24 hours
		}
		"PerfCounterCheck" {
			$object = "" | Select type,instance,threshold1,threshold2,threshold3,threshold4
			$checkset = "247"
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
						$object.threshold1 = 4  # Read queue
						$object.threshold2 = 4  # Write queue
					}
					$object.threshold3 = 100 # Disk time, and again we are talking ALERTS
				}
			}
		}
		"PingCheck" {
			$object = "" | Select name,pinghost,failcount
			$checkset = "247"
			$object.name = $option1
			$object.pinghost = $option2
		}
		"BackupCheck" {
			$object = "" | Select BackupProduct,checkdays,partial,count
			$checkset = "DSC"
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
			$object = "" | Select AVProduct,checkdays
			$checkset = "DSC"
			$object.avproduct = $option1
			$object.checkdays = "MTWTFSS"
		}
		"CriticalEvents" {
			$object = "" | Select eventlog,mode,option
			$checkset = "DSC"
			$object.eventlog = $option1
			If ($option2) {
				$object.mode = $option2
			} Else {
				$object.mode = 0 # Report mode
			}
			$object.option = 0
	  	}
		"EventLogCheck" {
			$object = "" | Select uid,log,flags,ids,source,contains,exclude,ignoreexclusions
			$checkset = "DSC"
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
	   		$object = "" | Select schedule1,schedule2,devtype,mode,autoapproval,scandelaytime,failureemails,rebootdevice,rebootcriteria
			$checkset = "DSC"
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
       "PhysDiskCheck" {
            $object = "" | Select volcheck
			$checkset = "DSC"
			$object.volcheck = 1
       }
	}
	
	$XmlCheck = $XmlConfig[$checkset].CreateElement($checktype)
	
	# Modified and uid are attributes, not properties. Do not set uid for new checks.
	# Let the agent deal with that. 
	$XmlCheck.SetAttribute('modified', '1')

	Foreach ($property in $object|Get-Member -MemberType NoteProperty) {
		$xmlProperty = $XmlConfig[$checkset].CreateElement($property.Name)
		$propertyValue = $object.($property.Name)
		# Is this a number?
		If ([bool]($propertyValue -as [int]) -or $propertyValue -eq "0") { 
			# If its a number we just dump it in there
			$xmlProperty.set_InnerText($propertyValue)
		} ElseIf ($propertyValue) { 
			# If it is text we encode it in CDATA
			$rs = $xmlProperty.AppendChild($XmlConfig[$checkset].CreateCDataSection($propertyValue))
		}
		# Add Property to Check element
		$rs = $xmlCheck.AppendChild($xmlProperty)
	}
	$rs = $XmlConfig[$checkset].checks.AppendChild($XmlCheck)
	$Script:NewChecks += $XmlCheck
	$Script:ConfigChanged = $true

}

function Get-XmlPropertyValue ($xmlProperty) {
	If ($XmlProperty -is [System.Xml.XmlElement]) {
		Return $XmlProperty.InnerText
	} Else {
		Return $XmlProperty
	}
}


function Get-MAXfocusCheckList ([string]$checktype, [string]$property, [string]$value, [bool]$ExactMatch = $true ) {
	$return = @()
	$ChecksToFilter = @()
	$ChecksToFilter = $XmlConfig.Values | % {$_.SelectNodes("//{0}" -f $checktype)}
	If (!($ChecksToFilter)) { Return }
	If ($value) {
		Foreach ($XmlCheck in $ChecksToFilter) {
			$XmlValue = Get-XmlPropertyValue $XmlCheck.$property
			If ($ExactMatch) { 
				If ($XmlValue -eq $value) { $return += $XmlCheck }
			} Else {
				If ($XmlValue -match $value) { $return += $XmlCheck }
			}
		}
	} Else {
		Return $ChecksToFilter
	}
	Return $return
}

function Remove-MAXfocusChecks ([array]$ChecksToRemove) {
	If (!($ChecksToRemove.Count -gt 0)) { Return }
	ForEach ($XmlCheck in $ChecksToRemove) {
		$XmlCheck.ParentNode.RemoveChild($XmlCheck)
		$Script:RemoveChecks += $XmlCheck
	}
	$Script:ConfigChanged = $true
}

function Get-MAXfocusCheck ([System.Xml.XmlElement]$XmlCheck) {
	$ChecksToFilter = @()
	$ChecksToFilter = Get-MAXfocusCheckList $XmlCheck.LocalName
	If ($ChecksToFilter.Count -eq 0) { Return $false }
	Foreach ($ExistingCheck in $ChecksToFilter) {
		$Match = $True
		Foreach ($ChildNode in $XmlCheck.ChildNodes) {
			If ($ChildNode.LocalName -eq "uid") { Continue }
			$property = $ChildNode.LocalName
			$ExistingValue = Get-XmlPropertyValue $ExistingCheck.$property
			If ($ChildNode.Innertext -ne $ExistingValue) {
				$Match = $false
				Break
			}
			If ($Match) {
				Return $ExistingCheck
			}
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

# Small function to give missing checks output some structure
function Format-Output($ArrayOfChecks) {
	$Result = @()
	Foreach ($CheckItem in $ArrayOfChecks){
		Switch ($CheckItem.LocalName)	{
			{"DriveSpaceCheck","DiskSpaceChange" -contains $_ } {
				$Result += $CheckItem.LocalName + " " + $CheckItem.driveletter.InnerText }
			"WinServicecheck" {
				$Result += $CheckItem.LocalName + " " + $CheckItem.servicename.InnerText }
			"PerfCounterCheck" { 
				Switch ($CheckItem.type) {
					"1" { $Result += $CheckItem.LocalName + " Processor Queue Length"}
					"2" { $Result += $CheckItem.LocalName + " Average CPU Usage"}
					"3" { $Result += $CheckItem.LocalName + " Memory Usage"}
					"4" { $Result += $CheckItem.LocalName + " Network Interface " + $CheckItem.instance.InnerText}
					"5" { $Result += $CheckItem.LocalName + " Physical Disk " + $CheckItem.instance.InnerText}
				}}
			{"PingCheck","AVUpdateCheck","BackupCheck","FileSizeCheck" -contains $CheckItem.LocalName } {
				$Result += $CheckItem.LocalName + " " + $CheckItem.name.InnerText }
			"EventLogCheck" {
				$Result += $CheckItem.LocalName + " " + $CheckItem.log.InnerText }
			"CriticalEvents" {
				switch ($CheckItem.mode) { 
					0 { $Result += $CheckItem.LocalName + " " + $CheckItem.eventlog.InnerText + " (Report)" }
					1 { $Result += $CheckItem.LocalName + " " + $CheckItem.eventlog.InnerText + " (Alert)" }}}
			default { 
				$Result += $CheckItem.LocalName }

		}
		
	}
	$Result += "" # Add blank line
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

Function Is-SMARTavailable () {
    $PrevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    Try {
        $Result = Get-WmiObject MSStorageDriver_FailurePredictStatus -Namespace root\wmi
    } Catch {
        $ErrorActionPreference = $PrevErrorAction
        Return $False
    }
    $ErrorActionPreference = $PrevErrorAction
    Return $True
}

#EndRegion

## Exit if sourced as Library
If ($Library) { Exit 0 }

#Region Setup
# Force the script to output something to STDOUT, else errors may cause script timeout.
Output-Host " "


$DefaultLogChecks = @(
#	@{ "log" = "Application|Application Hangs"; # Application log | Human readable name
#	   "flags" = 32512;
#	   "ids" = "*";
#	   "source" = "Application Hang" }
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

# Services you do not wish to monitor, regardless. Important list when you
# are adding service checks automatically
$DoNotMonitorServices = @(
	"wuauserv", # Windows Update Service. Does not run continously.
	"gupdate", "gupdatem", # Google Update Services. Does not always run.
	"AdobeARMservice", # Another service you may not want to monitor
	"Windows Agent Maintenance Service", # Clean up after N-Able
	"Windows Agent Service", # Clean up after N-Able
	"RSMWebServer", # Clean up after N-Able
	"gpsvc" # Group Policy Client
)
$AlwaysMonitorServices = @( # Services that always are to be monitored if present and autorun
	"wecsvc" # Windows Event Collector
)
	

# Find "Advanced Monitoring Agent" service and use path to locate files
$gfimaxagent = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq 'Advanced Monitoring Agent' }
$gfimaxexe = $gfimaxagent.PathName
$gfimaxpath = Split-Path $gfimaxagent.PathName.Replace('"',"") -Parent

# XML Document objects
$XmlConfig = @{}
$AgentConfig = New-Object -TypeName XML
$DeviceConfig = New-Object -TypeName XML

# XML Document Pathnames
$XmlFile = @{}
$AgentFile = $gfimaxpath + "\agentconfig.xml"
$DeviceFile = $gfimaxpath + "\Config.xml"
$LastChangeFile = $gfimaxpath + "\LastChange.log"

# We need an array of hashes to remember which checks to add
$NewChecks = @()
$RemoveChecks = @()
$oldChecks = @()
$ChangedSettings = @{}

# The prefix to the config files we need to read
$Sets = @("247", "DSC")

# An internal counter for new checks since we store them in a hashtable
[int]$uid = 1

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
		Output-Host "Changes Applied."
		If (Test-Path $LastChangeFile) {
			# Print last change to STDOUT
			Output-Host "------------------------------------------------------"
			Get-Content $LastChangeFile
			Output-Host "------------------------------------------------------"
		}
	Exit 0 # SUCCESS
	}
}


ForEach ($Set in $Sets) {
	$XmlConfig[$Set]  = New-Object -TypeName XML
	$XmlFile[$Set] = $gfimaxpath + "\{0}_Config.xml" -f $Set
	If  (Test-Path $XmlFile[$Set]) { 
		$XmlConfig[$Set].Load($XmlFile[$Set])
		$XmlConfig[$Set].DocumentElement.SetAttribute("modified","1")
	} Else {
		# File does not exist. Create a new, emtpy XML document
		$XmlConfig[$Set]  = New-Object -TypeName XML
		$decl = $XmlConfig[$Set].CreateXmlDeclaration("1.0", "ISO-8859-1", $null)
		$rootNode = $XmlConfig[$Set].CreateElement("checks")
		$result = $XmlConfig[$Set].InsertBefore($decl, $XmlConfig[$Set].DocumentElement)
		$result = $XmlConfig[$Set].AppendChild($rootNode)
		
		# Mark checks as modified. We will onøy write this to disk if we have modified anything
		$result = $rootNode.SetAttribute("modified", "1")
	}

} 


# Read agent config
$AgentConfig.Load($AgentFile)

# Read autodetected machine info
$DeviceConfig.Load($DeviceFile)

# Check Agent mode, workstation or server
$AgentMode = $AgentConfig.agentconfiguration.agentmode

#EndRegion

# Set interval according to $AgentMode
If ($AgentMode -eq "server") { $247Interval = $ServerInterval }
Else { $247Interval = $PCInterval }

#Region Monitoring Settings
# Check intervals. They can be modified together with other files.
If ($settingsContent["247CHECK"]["INTERVAL"] -ne $247Interval) {
	$settingsContent["247CHECK"]["INTERVAL"] = $247Interval
	$ChangedSettings['247_Interval'] = $247Interval
	$ConfigChanged = $true
}

If ($settingsContent["DAILYSAFETYCHECK"]["HOUR"] -ne $DSCHour) {
	$settingsContent["DAILYSAFETYCHECK"]["HOUR"] = $DSCHour
	$ChangedSettings['DSC_Hour'] = $DSCHour
	$ConfigChanged = $true
}

#EndRegion

# Check for new services that we'd like to monitor'
If ($settingsContent["247CHECK"]["ACTIVE"] -eq "1") {
	#Region 24/7 Checks
	
	If ($Reset) {
		$CheckTypes = @()
		If ($DriveSpaceCheck)	{$CheckTypes += 'DriveSpaceCheck'}
		If ($WinServiceCheck)	{$CheckTypes += 'WinServiceCheck'}
		If ($Performance)		{$CheckTypes += 'PerfCounterCheck'}
		If ($PingCheck) 		{$CheckTypes += 'PingCheck'}
		Foreach ($OldCheck in $XmlConfig['247'].checks.ChildNodes) {
			If ($CheckTypes.Contains($OldCheck.LocalName)) {
				$OldCheck.ParentNode.RemoveChild($OldCheck)
			}
		}
	}
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
			$oldChecks = Get-MAXfocusCheckList DriveSpaceCheck driveletter $DriveLetter
			If (!($oldChecks)) {
				New-MAXfocusCheck DriveSpaceCheck $DriveLetter
			}
		}
	}

	## WINSERVICECHECK
	#  By default we only monitor services on servers
	If (("All", "Default" -contains $WinServiceCheck) -and ($AgentMode -eq "server")) {
		# We really dont want to keep annoying services in our setup
		Foreach ($service in $DoNotMonitorServices) {
			$oldChecks = Get-MAXfocusCheckList WinServiceCheck servicekeyname $service
			If ($oldChecks) {
				Remove-MAXfocusChecks $oldChecks
			}
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
					$ServicesToMonitor += $service
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
				$oldChecks = Get-MAXfocusCheckList WinServiceCheck servicekeyname $service.Name
				If (!($oldChecks)) {
					New-MAXfocusCheck WinServiceCheck $service.DisplayName $service.Name
				}
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
				$sqlService = Get-WmiObject Win32_Service | where { $_.DisplayName -match $instance.SQLInstance -and $_.PathName -match "sqlservr.exe" -and $_.StartMode -eq 'Auto'}
				$oldChecks = Get-MAXfocusCheckList WinServiceCheck servicekeyname $sqlService.Name
				If (!($oldChecks)) {
					New-MAXfocusCheck WinServiceCheck $sqlService.DisplayName $sqlService.Name
				}
			}
		}
	}

	# Configure Performance Monitoring Checks
	If ($Performance -and ($AgentMode -eq "server")) { # Performance monitoring is only available on servers
		$ThisDevice = Get-WmiObject Win32_ComputerSystem
		
		## Processor Queue
		If ($ThisDevice.Model -notmatch "^virtual|^vmware") {
			# We are on a physical machine
			$oldChecks = Get-MAXfocusCheckList PerfCounterCheck type 1
			If (!($oldChecks)) {
				New-MAXfocusCheck PerfCounterCheck Queue
			}
		}
		
		## CPU
		$oldChecks = Get-MAXfocusCheckList PerfCounterCheck type 2
		If (!($oldChecks)) {
			New-MAXfocusCheck PerfCounterCheck CPU
		}
		
		## RAM
		[int]$nonpagedpool = 128
		If ([System.IntPtr]::Size -gt 4) { # 64-bit
			[int]$TotalMemoryInMB = $ThisDevice.TotalPhysicalMemory / 1MB
			[int]$nonpagedpool = $nonpagedpool / 1024 * $TotalMemoryInMB
		}

		$oldChecks = Get-MAXfocusCheckList PerfCounterCheck type 3
		If (!($oldChecks)) {
			New-MAXfocusCheck PerfCounterCheck RAM $nonpagedpool
		}
		
		## Net
		#  Not on Hyper-V
		If ($ThisDevice.Model -notmatch "^virtual") {
			$NetConnections = Get-WmiObject Win32_PerfRawData_Tcpip_Networkinterface | where {$_.BytesTotalPersec -gt 0} | Select -ExpandProperty Name
			$oldChecks = Get-MAXfocusCheckList PerfCounterCheck Type 4
			If (!($oldChecks)) {
				Foreach ($Adapter in $NetConnections) {
					New-MAXfocusCheck PerfCounterCheck Net $Adapter
				}
			}
		}
		## Disk
		# Needs physical disks
		$PhysicalDisks =  $DeviceConfig.configuration.physicaldisks | select -ExpandProperty name | where {$_ -ne "_Total"}

		$oldChecks = Get-MAXfocusCheckList PerfCounterCheck Type 5
		If (!($oldChecks)) {
			Foreach	($Disk in $PhysicalDisks ) {
				New-MAXfocusCheck PerfCounterCheck Disk $Disk
			}
		}
	}

	# Configure ping check
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
			$oldChecks = Get-MAXfocusCheckList PingCheck pinghost $trace
			If (!($oldChecks)) {
				New-MAXfocusCheck PingCheck 'Router Next Hop' $trace
			}
		}
		
	}

	#EndRegion
} Else {
	Output-Host '24/7 Checks are disabled. Enable 24/7 checks on agent'
	Output-Host 'to configure 24/7 Checks automatically. To bulk update'
	Output-Host 'use Add Checks... and add a single, relevant 24/7 check'
	Output-Host 'to any device you want to use with this script. '
	Output-Host 'With Agent v09.5.7+ you can use Apply Template (preferred'
    Output-Host 'Option).'

}


If ($settingsContent["DAILYSAFETYCHECK"]["ACTIVE"] -eq "1") {
	#Region DSC Checks
	
	If ($Reset) {
		$CheckTypes = @()
		If ($DiskSpaceChange)	{$CheckTypes += 'DiskSpaceChange'}
		If ($SMART)				{$CheckTypes += 'PhysDiskCheck'}
		If ($Backup)			{$CheckTypes += 'BackupCheck'}
		If ($Antivirus) 		{$CheckTypes += 'AVUpdateCheck'}
		If ($LogChecks) 		{$CheckTypes += 'EventLogCheck'}
		Foreach ($OldCheck in $XmlConfig['DSC'].checks.ChildNodes) {
			If ($CheckTypes.Contains($OldCheck.LocalName)) {
				$OldCheck.ParentNode.RemoveChild($OldCheck)
			}
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
			$oldChecks = Get-MAXfocusCheckList DiskSpaceChange driveletter $DriveLetter
			If (!($oldChecks)) {
				New-MAXfocusCheck DiskSpaceChange $DriveLetter
			}
		}
	}

	## Disk Health Status
	If (($SMART) -and (Is-SMARTavailable)) {
	    $oldChecks = Get-MAXfocusCheckList PhysDiskCheck
		If (!($oldChecks)) {
			New-MAXfocusCheck PhysDiskCheck
		}
	}

	If ($Backup) {
		$oldChecks = Get-MAXfocusCheckList BackupCheck
		If (!($oldChecks)) {
			$DetectedBackups = $DeviceConfig.configuration.backups | Select -ExpandProperty name -ErrorAction SilentlyContinue
			Foreach ($BackupProduct in $DetectedBackups){
				$JobCount = 1
				$AddCheck = $true
				Switch ($BackupProduct) {
					"Backup Exec" {
						$JobCount = 99 # Make sure unconfigured checks fail
						$bengine =  Get-WmiObject win32_service | where { $_.PathName -match "bengine.exe" -and $_.DisplayName -match "Backup Exec"}
						If (!($bengine)){
							# Only add backup exec check if job engine is present
							 $AddCheck = $false
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
							Output-Host "Unable to load Veeam snapin, you must run this on your Veeam backup server, and the Powershell snapin must be installed.`n`n"
						} Else {
							$JobCount = (Get-VBRJob|select Name).Count
						}
					}
					"AppAssure v5" {
						# Accept Default Jobcount, but add check
					}
					Default {
						# Don't add any checks
						 $AddCheck = $false
					}
				}
				If ($AddCheck) { 
					# We cannot know how many jobs or which days. Better a 
					# failed check that someone investigates than no check at all
					New-MAXfocusCheck BackupCheck $BackupProduct $JobCount
				}
			}
		}
	}

	If ($Antivirus) {
		$oldChecks = Get-MAXfocusCheckList AVUpdateCheck
		If (!($oldChecks)) {
			$DetectedAntiviruses = $DeviceConfig.configuration.antiviruses | Select -ExpandProperty name -ErrorAction SilentlyContinue
			If (($DetectedAntiviruses) -and ($DetectedAntiviruses -notcontains "Managed Antivirus")) {
				Foreach ($AVProduct in $DetectedAntiviruses) {
					$AddCheck = $true
					Switch -regex ($AVProduct) {
						'Windows Defender' { $AddCheck = $false }
						'Trend.+Conventional Scan' {
							If (Get-TMScanType -ne "Conventional") { $AddCheck = $false }	
						}
						'Trend.+Smart Scan' {
							If (Get-TMScanType -ne "Smart") { $AddCheck = $false }
						}
					}
					If ($AddCheck) {
						# Only add a single AV check. Break after adding.
						New-MAXfocusCheck AVUpdateCheck $AVProduct
						Break
					}
				}
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
			$oldChecks = Get-MAXfocusCheckList EventLogCheck log $Check.log
			If (!($oldChecks)) {
				New-MAXfocusCheck EventLogCheck $NextUid $Check.log $Check.flags $Check.source $Check.ids
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
			$oldChecks = Get-MAXfocusCheckList CriticalEvents eventlog $Check.eventlog
			If (!($oldChecks)) {
				New-MAXfocusCheck CriticalEvents $Check.eventlog $Check.mode
			}
		}
	}
	#EndRegion
} Else {
	Output-Host 'Daily Safety Checks are disabled. Enable DSC checks on agent'
	Output-Host 'to configure DSC automatically. To bulk update'
	Output-Host 'use Add Checks... and add a single, relevant DSC check'
	Output-Host 'to any device you want to use with this script. '
	Output-Host 'Adding this script as a script check is our own preferred choice.'
	Output-Host 'With Agent v09.5.7+ you can use Apply Template, too.'
}


#Region Save and Restart

If ($ConfigChanged) {
	If ($Apply) {
		# Remove Reset Switch, but changes to ST_Config does not sync back to
		# Dashboard.
		If ($Reset) {
			If ($logfile -match '_(\d+)\.log') {
				$scriptuid = $Matches[1]
			}
			$OldCheck = $XmlConfig['DSC'].SelectSingleNode(("//*[@uid=$scriptuid]"))
			If (!$OldCheck) {
				$STConfig = New-Object -TypeName XML
				$STConfig.Load($gfimaxpath + '\ST_Config.xml')
				$OldCheck = $STConfig.SelectSingleNode(("//*[@uid=$scriptuid]"))
			}
			If ($OldCheck.arguments -is [System.Xml.XmlElement]) {
				$OldCheck.arguments.set_InnerText($OldCheck.arguments.InnerText.Replace('-Reset',''))
			} Else {
				$OldCheck.arguments = $OldCheck.arguments.Replace('-Reset','')
			}
			If ($STConfig) {
				$STConfig.Save($gfimaxpath + '\ST_Config.xml')
			}
		}
		
		# Write output to $LastChangeFile
		# Overwrite file with first command
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
		Output-Host 'Configuration has been changed. Initiating restart of agent.'
		Restart-MAXfocusService
		
		If ($ReportMode) {
			Exit 0 # Needed changes have been reported, but do not fail the check
		} Else {
			Exit 1001 # Internal status code: Changes made
		}
	} Else {
		Output-Host "Recommended changes:"

		If ($RemoveChecks.Count -gt 0) {
			Output-Host "Checks to be removed:"
			Format-Output $RemoveChecks 
		}
		If ($NewChecks.Count -gt 0) {
			Output-Host "Checks to be added:"
			Format-Output $NewChecks 
		}
		If ($ChangedSettings.Count -gt 0) {
			Output-Host "Settings to be changed:"
			$ChangedSettings
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
			Exit 1000 # Internal status code: Suggested changes, but nothing has been touched
		}
	}
} Else {
	# We have nothing to do. This Device has passed the test!
	Output-Host "Current Configuration Verified  - OK:"
	If ($Performance) 		{ Output-Host "Performance Monitoring checks verified: OK"}
	If ($DriveSpaceCheck) 	{ Output-Host "Disk usage monitored on all harddrives: OK"}
	If ($WinServiceCheck) 	{ Output-Host "All Windows services are now monitored: OK"}
	If ($DiskSpaceChange) 	{ Output-Host "Disk space change harddrives monitored: OK"}
	If ($PingCheck) 		{ Output-Host "Pingcheck Router Next Hop check tested: OK"}
	If ($SqlInstances.count -gt 0) { Output-Host "SQL Server installed:"; $SqlInstances }
	If ($SMART) 			{ Output-Host "Physical Disk Health monitoring tested: OK"}
	If ($Backup) 			{ Output-Host "Unmonitored Backup Products not found: OK"}
	If ($Antivirus) 		{ Output-Host "Unmonitored Antivirus checks verified: OK"}
	Output-Host "All checks verified. Nothing has been changed."
	If (Test-Path $LastChangeFile) {
		# Print last change to STDOUT
		Output-Host "------------------------------------------------------"
		Get-Content $LastChangeFile
		Output-Host "------------------------------------------------------"
	}
	# Try to make Windows autostart monitoring agent if it fails
	# Try to read the FailureActions property of Advanced Monitoring Agent
	# If it does not exist, create it with sc.exe
	$FailureActions = Get-ItemProperty "HKLM:\System\CurrentControlSet\Services\Advanced Monitoring Agent" FailureActions -ErrorAction SilentlyContinue
	If (!($FailureActions)) {
		# Reset count every 24 hours, restart service after twice the 247Interval minutes
		$servicename = $gfimaxagent.Name
		&sc.exe failure "$servicename" reset= 86400 actions= restart/600000
	}
	Exit 0 # SUCCESS
}

#EndRegion