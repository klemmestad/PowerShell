###########################################################
# Script to check power state of a specified VM
###########################################################

###########################################################
# Version Information
###########################################################
# $LastChangedDate: 2012-12-13 15:17:00 +0000 (Thu, 13 Dec 2012) $
# $Rev: 36386 $
###########################################################

param( [string]$HostName = '', [string]$UserName = '', [string]$Password = '', [string]$VMName = '', [Parameter(Mandatory=$false)][string]$LogFile )

Set ERROR_INVALID_ARGS							-Option Constant -Value 1
Set ERROR_CANNOT_FIND_SNAPIN					-Option Constant -Value 1005
Set ERROR_CANNOT_CONNECT_TO_SERVER_CREDENTIALS	-Option Constant -Value 1001
Set ERROR_CANNOT_CONNECT_TO_SERVER_UNREACHABLE	-Option Constant -Value 1002
Set ERROR_CANNOT_FIND_VM						-Option Constant -Value 1506
Set ERROR_VM_POWERED_DOWN						-Option Constant -Value 1505

function Get-StatRange( $inoEntity, $insStatName, $innIntervalSecs = 20, $inoStartTime = $null, $inoFinishTime = $null ) {
	if( $inoStartTime -eq $null ) {
		$inoStartTime = $global:oStartTime
	}
	if( $inoFinishTime -eq $null ) {
		$inoFinishTime = $global:oFinishTime
	}
	$oValue = get-stat -Entity $inoEntity -Stat $insStatName -MaxSamples 1000 -start $inoStartTime -finish $inoFinishTime -IntervalSecs 20
	return $oValue | Measure-Object -Property value -Average -Maximum -Minimum
}

function Exit-WithCode( [int]$innCode, [string]$insText = '' ) {
	Write-Host ( "{0}|{1}" -f $innCode, $insText )
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

	Exit-WithCode $ERROR_CANNOT_FIND_SNAPIN ( "Error: {0} Snapin does not exist" -f $sSnapInName )
}

# BEGIN SCRIPT

if( $HostName -eq '' -or $UserName -eq '' -or $VMName -eq '' ) {
	Exit-WithCode $ERROR_INVALID_ARGS 'Error: Invalid Arguments'
}

$Error.Clear()

Add-RequiredPSSnapIn

$global:oStartTime = ( Get-Date ).AddMinutes( -15 )
$global:oFinishTime = Get-Date
$global:oVMServer = Connect-VIServer -Server $HostName -User $UserName -Password $Password -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
if( $oVMServer -eq $null ) {
	if( $Error[0].Exception -match 'Cannot complete login due to an incorrect user name or password' ) {
		Exit-WithCode $ERROR_CANNOT_CONNECT_TO_SERVER_CREDENTIALS "Error: Cannot connect to Server - credentials invalid|$VMName"
	} else { # $Error[0].Exception -match 'Could not connect using the requested protocol'
		Exit-WithCode $ERROR_CANNOT_CONNECT_TO_SERVER_UNREACHABLE "Error: Cannot connect to Server - unreachable|$VMName"
	}
}

$aVMs = Get-VM -Server $oVMServer -Name $VMName -ErrorAction SilentlyContinue
if( $aVMs -eq $null ) {
	Exit-WithCode $ERROR_CANNOT_FIND_VM "Error: Cannot find Virtual Machine|$VMName"
}

$oVM = @( $aVMs )[0]
$sSelectedVMName = $oVM.Name

$fPoweredOn = $oVM.PowerState -eq 'PoweredOn'
if( !$fPoweredOn ) {
	Exit-WithCode $ERROR_VM_POWERED_DOWN "Error: Virtual Machine is not running|$sSelectedVMName"
}

$aOutput = @( "<?xml version='1.0' encoding='UTF-8'?>" )
$aOutput += "<dataset>"

$aOutput += "<ram_allocated value='{0}' unit='3.3' />" -f $oVM.MemoryMB
$aOutput += "<ram_usage value='{0:F2}' unit='4' />" -f ( Get-StatRange $oVM 'mem.usage.average' ).Average
$aOutput += "<cpu_usage value='{0:F2}' unit='4' />" -f ( Get-StatRange $oVM 'cpu.usage.average' ).Average
$aOutput += "<network_usage value='{0:F2}' unit='2.2' rate='3' />" -f ( ( Get-StatRange $oVM 'net.usage.average' ).Average * 8 )
$aOutput += "<network_received value='{0:F2}' unit='2.2' rate='3' />" -f ( ( Get-StatRange $oVM 'net.received.average' ).Average * 8 )
$aOutput += "<network_transmitted value='{0:F2}' unit='2.2' rate='3' />" -f ( ( Get-StatRange $oVM 'net.transmitted.average' ).Average * 8 )
$aOutput += "<network_max value='{0:F2}' unit='2.2' rate='3' />" -f ( ( Get-StatRange $oVM 'net.usage.average' 7200, ( ( Get-Date ).AddDays( -7 ) ) ).Average * 8 )

$nTotalDiskCapacity = 0
$nTotalDiskFree = 0
$oVMGuest = Get-VMGuest -VM $oVM | Where { $_.Disks } | Foreach { $_.Disks | Foreach {
	$nTotalDiskCapacity += $_.Capacity
	$nTotalDiskFree += $_.FreeSpace
} }

if( $nTotalDiskCapacity -gt 0 ) {
	$aOutput += "<disk_allocated value='{0:F2}' unit='3.3' />" -f ( $nTotalDiskCapacity / 1048576 )
	$aOutput += "<disk_usage value='{0:F2}' unit='4' />" -f ( ( 1.0 - $nTotalDiskFree / $nTotalDiskCapacity ) * 100 )
}

$aOutput += "</dataset>"

Exit-WithCode 0 ( ( $aOutput -join "`r`n" ) + "|$sSelectedVMName" )