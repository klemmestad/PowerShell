###########################################################
# Script to gather healthstatus of disk sensors
#
# Parameters - ESXHost ESXUSer ESXPassword 
#
###########################################################

###########################################################
# Version Information
###########################################################
# $LastChangedDate: 2013-03-19 13:35:43 +0000 (Tues, 19 March 2013) $
# $Rev: 36208 $
###########################################################

param( [string]$hostName = '', [string]$userName = '', [string]$password = '',[string]$logFile )

Set ERROR_INVALID_ARGS								-Option Constant -Value 1
Set ERROR_CANNOT_FIND_SNAPIN						-Option Constant -Value 1005
Set ERROR_CANNOT_CONNECT_TO_SERVER_CREDENTIALS		-Option Constant -Value 1001
Set ERROR_CANNOT_CONNECT_TO_SERVER_UNREACHABLE		-Option Constant -Value 1002
Set ERROR_DOES_NOT_EXIST							-Option Constant -Value 2005
Set CHECK_PASSED									-Option Constant -Value 0
Set CHECK_FAILED									-Option Constant -Value 2003

function Exit-WithCode( [int]$innCode, [string]$insText = '' ) {
	Write-Host $insText
	if( $global:oVMServer -ne $null ) {
		Disconnect-VIServer -Server $global:oVMServer -Force -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
	}
	Exit $innCode
}

function Add-RequiredPSSnapin() {
	$sSnapInName = 'VMware.VimAutomation.Core'
	foreach( $oSnapIn in Get-PSSnapIn -Registered ) {
		if( $oSnapIn.Name -eq $sSnapInName ) {
			Add-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue
			return
		}
	}
	Exit-WithCode $ERROR_CANNOT_FIND_SNAPIN ("{0}|{1}" -f $ERROR_CANNOT_FIND_SNAPIN, 'Snapin does not exist '+ $sSnapInName) 
}

# HELPER FUNCTIONS

function Add-Record( [REF]$sbXml, $name, $healthstateKey, $healthstateSummary ){
	[void]$sbXml.value.Append( "<sensor " )
	[void]$sbXml.value.Append( " type = 'storage_and_numericdisk'" )
	[void]$sbXml.value.Append( " name = '" ).append( $name ).append( "'" )
	[void]$sbXml.value.Append( " healthstatesummary = '" ).append( $healthstateSummary ).append( "'" )
	[void]$sbXml.value.Append( " health_state = '" ).append( $healthstateKey.ToLower() ).append( "'" )
	[void]$sbXml.value.Append( " />" )
}

function Record-Healthstate( $healthKey ){
	if( $healthKey -eq 'green' ){
		$global:okCount += 1
	}elseif( $healthKey -eq 'unknown' ){
		$global:unknownCount += 1
	}else{
		$global:failCount += 1
	}
}


# BEGIN SCRIPT

if( $hostName -eq '' -or $userName -eq '' -or $password -eq '') {
	Exit-WithCode $ERROR_INVALID_ARGS ("{0}|{1}" -f $ERROR_INVALID_ARGS, 'Error: Invalid Arguments') 
}
 
Add-RequiredPSSnapIn

$Error.Clear()

$global:oVMServer = Connect-VIServer -Server $hostName -User $userName -Password $password -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
if( $oVMServer -eq $null ) {
	if( $Error[0].Exception -match 'Cannot complete login due to an incorrect user name or password' ) {
		Exit-WithCode $ERROR_CANNOT_CONNECT_TO_SERVER_CREDENTIALS ("{0}|{1}" -f $ERROR_CANNOT_CONNECT_TO_SERVER_CREDENTIALS, 'Error: Cannot connect to Server - credentials invalid') 
	} else {
		Exit-WithCode $ERROR_CANNOT_CONNECT_TO_SERVER_UNREACHABLE ("{0}|{1}" -f $ERROR_CANNOT_CONNECT_TO_SERVER_UNREACHABLE, 'Error: Cannot connect to Server - unreachable') 
	}
}

#get health status system view
$hostView = Get-VMHost | Get-View  
$healthStatusSystem = Get-View $hostView.ConfigManager.HealthStatusSystem

$global:failCount = 0
$global:okCount = 0
$global:unknownCount = 0

$output = new-object System.Text.StringBuilder
[void]$output.AppendLine( "<?xml version='1.0' encoding='UTF-8'?>" )
[void]$output.AppendLine( "<dataset>" )
[void]$output.AppendLine( "<storagecheck>" )

ForEach ( $entry in  $healthStatusSystem.Runtime.HardwareStatusInfo.storageStatusInfo) {
	if( $entry.name ){
		Add-Record([REF]$output) $entry.name $entry.status.key $entry.status.summary
		Record-Healthstate $entry.status.key
	}
}

#some esx versions / hardware does not show anything under storagestatusinfo, so query numericsensor info
ForEach ( $entry in  $healthStatusSystem.Runtime.SystemHealthInfo.numericSensorInfo) {
	if( ( $entry.name.ToLower().Contains("disk") -or ( $entry.sensorType.ToLower() -eq "storage" ) ) -and $entry.name ){ #show items containing "disk" - may be disk, disk cable, disk battery etc sensors, and any sensors with type "Storage"
		Add-Record([REF]$output) $entry.name $entry.healthState.key $entry.healthState.summary
		Record-Healthstate $entry.healthState.key
	}
}

[void]$output.AppendLine( "</storagecheck>" )
[void]$output.AppendLine( "</dataset>" )

if( $global:okCount + $global:failCount + $global:unknownCount -eq 0 ){
	Exit-WithCode $ERROR_DOES_NOT_EXIST ("{0}|{1}" -f $ERROR_DOES_NOT_EXIST, 'Error: No Storage sensors') 
}

if ( $global:failCount -eq 0 ){
	Exit-WithCode $CHECK_PASSED ("{0}|{1}|{2}|{3}|{4}" -f $CHECK_PASSED, $output.ToString(), $global:okCount, $global:failCount, $global:unknownCount) 
}else{
	Exit-WithCode $CHECK_FAILED ("{0}|{1}|{2}|{3}|{4}" -f $CHECK_FAILED, $output.ToString(), $global:okCount, $global:failCount, $global:unknownCount)
}