<#
    .SYNOPSIS
        Enables a hardware events subscription if IPMI is available.

    .DESCRIPTION
        Checks whether IPMI is available and creates a hardware events
		subscription if it is missing. Such a subscription is maintained
		by Windows service Wecsvc. It is started if it isn't running and
		startupmode set to Auto.

    .PARAMETER None
        No parameters are needed. Any parameters given are ignored.

    .NOTES
        Name: Enable-HardwareEvents
        Author: Hugo L. Klemmestad
        DateCreated: 14 NOV 2014

    .EXAMPLE
        Enable-HardwareEvents
		HardwareEvents Enabled

        Description
        -----------
        Returns IPMI NOT AVAILABLE if IPMI driver not loaded.
#>

## I put the literal string at top for esthetic reasons only
[xml]$WSManSelRg = @"
<Subscription xmlns="http://schemas.microsoft.com/2006/03/windows/events/subscription">
    <Description>A subscription for the HardwareEvents</Description>
    <SubscriptionId>WSManSelRg</SubscriptionId>
    <Uri>http://schemas.microsoft.com/wbem/wsman/1/logrecord/sel</Uri>
    <EventSources>
        <EventSource>
            <Address>LOCALHOST</Address>
        </EventSource>
    </EventSources>
    <LogFile>HardwareEvents</LogFile>
    <Delivery Mode="pull">
        <PushSettings>
            <Heartbeat Interval="10000" />
        </PushSettings>
    </Delivery>
</Subscription>
"@


$ErrorActionPreference = "Stop"

## First we try if IPMI is available. It is always present if BMC is avaliable
Try {
	$ipmi = Get-WmiObject -Namespace root/wmi -Class Microsoft_IPMI 2>$null
	# IPMI is available.
	$ErrorActionPreference  = "Continue"
	## SETUP
	$FilePath = $env:TEMP + "\WSManSelRg.xml"
	$Wecsvc = Get-WmiObject Win32_service | where { $_.Name -eq "Wecsvc" }
	$HardwareEvents = Get-WmiObject Win32_NTEventLogFile | where { $_.LogFileName -eq "HardwareEvents" }
	
	$SubscriptionStatus = wecutil gr wsmanselrg 2>$null
	
	If ($LASTEXITCODE -gt 0) {
		# Create Subscription
		If (!($Wecsvc.Started)) {
			Start-Service -Name "Wecsvc"
		}
		If (!($Wecsvc.StartMode -eq "Auto")) {
			Set-Service -Name "Wecsvc" -StartupType Automatic
		}
		# Create the subscription file
		$WSManSelRg.Save($FilePath)
		
		# Create the subscription
		wecutil cs $FilePath 2>$null
		
		If ($LASTEXITCODE -gt 0) {
			Write-Host "'wecutil cs $FilePath' Failed!"
			Remove-Item $FilePath -Force
			Exit 1001 # Error
		}
		# Clean up file system
		Remove-Item $FilePath -Force

		$SubscriptionStatus = wecutil gr wsmanselrg
	}
	
} Catch {
	Write-Host "IPMI not available. This check should be removed now."
	Exit 0
}
$HardwareEventsOK = $SubscriptionStatus | Select-String "LastError: 0"
If ($HardwareEventsOK) {
	Write-Host "HardwareEvents Enabled. This check should be removed now."
	Exit 0
} Else {
	Write-Host "Enabling HardwareEvents failed."
	Write-Host $SubscriptionStatus
	Exit 1001
}