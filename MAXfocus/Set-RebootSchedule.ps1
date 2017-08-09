param (
	[string]$Day = 'Wed',
	[string]$Time = '05:30',
	[string]$logfile
)

# Validate day
$Days = @('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')
If ($Days -notcontains $Day) {
	Write-Host ('ERROR: Parameter -Day {0} is wrong. Value must be one of:' -f $Day)
	Write-host @Days
	Exit 1001
}

If ($Time -notmatch '(^\d\d):(\d\d)$') {
	Write-Host ('ERROR: Parameter -Time {0} is wrong. Value must be in 24 hour format HH:MM' -f $Time)
	Exit 1001
} ElseIf ($Matches[1] -gt 23 -or $Matches[1] -lt 0) {
	Write-Host ('ERROR: Parameter -Time {0} is wrong. Value must be in 24 hour format HH:MM' -f $Time)
	Exit 1001
} ElseIf ($Matches[2] -gt 59 -or $Matches[2] -lt 0) {
	Write-Host ('ERROR: Parameter -Time {0} is wrong. Value must be in 24 hour format HH:MM' -f $Time)
	Exit 1001
}


# Prepare restartscript
$RestartScript = 'shutdown.exe /r /t 300'  

$TaskName = "Restart Server on Schedule"
$Result = &schtasks.exe /query /tn "$TaskName"
If (!($Result)) {
	Write-Host "Task missing. Creating Scheduled Task."
	$Result = &schtasks.exe /Create /TN $TaskName /TR "$RestartScript" /RU SYSTEM /SC WEEKLY /D $Day /ST $Time
}

# Try again
$Result = &schtasks.exe /query /tn "$TaskName"
If ($Result) {
	Write-Host $Result[4]
} Else {
	Write-Host "ERROR: SCHTASKS.EXE failed. "
	Exit 1001
}

$DayIsWrong = $false
$TimeIsWrong = $false
If ($Result[4] -match '\d.{17}\d') {
	$NextRun = Get-Date $Matches[0]
	
	If (!($NextRun.DayOfWeek -match $Day)) {
		$DayIsWrong = $true
	} ElseIf ((Get-Date $NextRun -format 'hh:mm') -ne $Time) {
		$TimeIsWrong = $true
	}
	
} Else {
	Write-Host 'ERROR: Could not parse Next Run time. Verify script and settings!'
	Exit 1001
}


If ($DayIsWrong -or $TimeIsWrong) {
	Write-Host ('Schedule parsed as {0} on {1}. Expected {2} on {3}.' -f (Get-Date $NextRun -format 'hh:mm'),$NextRun.DayOfWeek.ToString().Substring(0,3), $Time, $Day)
	Write-Host 'Reconfiguring Shedule'
	$Result = &schtasks.exe /Create /TN $TaskName /TR "$RestartScript" /RU SYSTEM /SC WEEKLY /D $Day /ST $Time /F
	If (!($Result -like 'SUCCESS:*')) {
		Write-Host "SCHTASKS.EXE failed. Verify script and settings."
		Exit 1001
	}
} Else {
	Write-Host ('Schedule {0} on {1} Confirmed.' -F $Time, $Day)
	Exit 0
}