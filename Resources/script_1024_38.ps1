###########################################################
# Script to check free space of datastores
#
# Params - ESXHost ESXUser ESXPassword ESXDatastore(supports * wildcard) unit(MB/ GB / PERCENT) threshold
#
###########################################################

###########################################################
# Version Information
###########################################################
# $LastChangedDate: 2013-03-19 13:35:43 +0000 (Tues, 19 March 2013) $
# $Rev: 36208 $
###########################################################

param( [string]$hostName = '', [string]$userName = '', [string]$password = '', [string]$datastoreName = '', [string]$units = '', [string]$threshold = '', [string]$logFile )

Set ERROR_INVALID_ARGS							-Option Constant -Value 1
Set ERROR_CANNOT_FIND_SNAPIN						-Option Constant -Value 1005
Set ERROR_CANNOT_CONNECT_TO_SERVER_CREDENTIALS				-Option Constant -Value 1001
Set ERROR_CANNOT_CONNECT_TO_SERVER_UNREACHABLE				-Option Constant -Value 1002
Set ERROR_CANNOT_FIND_DATASTORE						-Option Constant -Value 1508
Set CHECK_PASSED							-Option Constant -Value 0
Set CHECK_FAILED							-Option Constant -Value 2004

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


# BEGIN SCRIPT




#params have default value so if they are not passed in they will be empty - this way we can check and provide out own exit code
if( $hostName -eq '' -or $userName -eq '' -or $password -eq '' -or $datastoreName -eq '' -or $units -eq '' -or $threshold -eq '') {
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


$failCount = 0
$okCount = 0
$output = new-object System.Text.StringBuilder
[void]$output.AppendLine("<?xml version='1.0' encoding='UTF-8'?>" )
[void]$output.AppendLine("<dataset>")
[void]$output.AppendLine("<datastores>")

$datastores = Get-Datastore -Name $DatastoreName -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
if( $datastores -eq $null ) {
	Exit-WithCode $ERROR_CANNOT_FIND_DATASTORE ("{0}|{1}" -f $ERROR_CANNOT_FIND_DATASTORE, 'Error: Cannot find datastore') 
}

ForEach ( $dataStore in $datastores ){
	$nCapacityMB = $dataStore.CapacityMB
	$nCapacityGB = $dataStore.CapacityGB
	$nFreeSpaceMB = $dataStore.FreeSpaceMB
	$nFreeSpaceGB = $dataStore.FreeSpaceGB
	
	# PowerCli 4.x does not provide GB values, only MB	
	If ($nCapacityGB -eq 0) { $nCapacityGB = $nCapacityMB/1024 }
	If ($nFreeSpaceGB -eq 0) { $nFreeSpaceGB = $nFreeSpaceMB/1024 }
	
	#prepare values not provided by api
	$usedMB = $nCapacityMB - $nFreeSpaceMB
	
	#PowerCLI 5.0 has a known issue whereby free and capacity is mixed up - therefore if used value is negative, switch the core values around
	if( $usedMB -lt 0 ){
		$nCapacityMB = $dataStore.FreeSpaceMB
		$nFreeSpaceMB = $dataStore.CapacityMB
		$usedMB = $nCapacityMB - $nFreeSpaceMB
	}
	
	$usedGB = $nCapacityGB - $nFreeSpaceGB
	if( $usedGB -lt 0 ){
		$nCapacityGB = $dataStore.FreeSpaceGB
		$nFreeSpaceGB = $dataStore.CapacityGB
		$usedGB = $nCapacityGB - $nFreeSpaceGB
	}
	
	$percentFree = [math]::Round( ( 100 * $nFreeSpaceMB / $nCapacityMB ) ,0)
	
	#prepare value to check based on units passed in
	$valueToCheck = 0
	if($units -ieq "MB"){
		$valueToCheck = $nFreeSpaceMB
	}elseif($units -ieq "GB"){
		$valueToCheck = $nFreeSpaceGB
	}elseif($units -ieq "PERCENT"){
		$valueToCheck = $percentFree
	}	
	
	#check if threshold has been breached
	[Bool]$thresholdBreached = $false #assume false
	if( $valueToCheck -lt $threshold){
		$thresholdBreached = $true
		$failCount += 1
	}else{
		$okCount += 1
	}
	
	[void]$output.AppendLine("<sensor")
	[void]$output.Append(" type = 'datastore'")
	[void]$output.Append(" name = '").Append( $dataStore.Name ).Append("'")
	[void]$output.Append(" capacitygb = '").Append( $nCapacityGB ).Append("'")
	[void]$output.Append(" usedgb = '").Append( $usedGB ).Append("'")
	[void]$output.Append(" freespacegb = '").Append( $nFreeSpaceGB ).Append("'")
	[void]$output.Append(" percentfree = '").Append( $percentFree ).Append("'")
	[void]$output.Append(" thresholdbreached = '").Append( $thresholdBreached ).Append("'")
	[void]$output.Append(" />")
}

[void]$output.AppendLine("</datastores>")
[void]$output.AppendLine("</dataset>")

if ($failCount -eq 0){
	Exit-WithCode $CHECK_PASSED ("{0}|{1}|{2}|{3}" -f $CHECK_PASSED, $output.ToString(), $okCount, $failCount) 
}else{
	Exit-WithCode $CHECK_FAILED ("{0}|{1}|{2}|{3}" -f $CHECK_FAILED, $output.ToString(), $okCount, $failCount)
}
