
# Send something to STDOUT to prevent task_start.js to lock if the script fails 
Write-Host " "

## SETUP ENVIRONMENT
# Find "Advanced Monitoring Agent" service and use path to locate files
$gfimaxagent = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq 'Advanced Monitoring Agent' }
$gfimaxexe = $gfimaxagent.PathName
$gfimaxpath = Split-Path $gfimaxagent.PathName.Replace('"',"") -Parent

$DSCfile = $gfimaxpath + "\DSC_Config.xml"
$DSC_Config = New-Object -TypeName XML
$DSC_Config.Load($DSCfile)

$PatchManagement = $DSC_Config.checks.VulnerabilityCheck

If (!($PatchManagement)) {
	Write-Host "Patch Management not in use."
	Exit 0
}

$Schedule = $PatchManagement.schedule2
If ($Schedule -is [System.Xml.XmlElement]) { $Schedule = $Schedule.InnerText}
$Mode = $PatchManagement.mode
$RebootDevice = $PatchManagement.rebootdevice
$RebootCriteria = $PatchManagement.rebootcriteria
If ($RebootCriteria -is [System.Xml.XmlElement]) { $RebootCriteria = $RebootCriteria.InnerText}
$AutoApproval = $PatchManagement.autoapproval
If ($AutoApproval -is [System.Xml.XmlElement]) { $AutoApproval = $AutoApproval.InnerText}

$ApprovalOptions = @([regex]::Split($AutoApproval,","))
$Vendors = @("Microsoft", "Other Vendors")
$Category = @("Critical", "Important", "Moderate", "Low", "Other")

$ScheduleOptions = @([regex]::Split($Schedule,"\|"))
$Time = "{0}:{1}" -f $ScheduleOptions[2], $ScheduleOptions[3]
$DayConfig = $ScheduleOptions[4]

$WeekDays = ""
For ($i = 0;$i -le 6;$i++) {

	If ($DayConfig.Substring($i,1) -eq "X") {
		Switch ($i) {
			0 { $WeekDay = "Monday "}
			1 { $WeekDay = "Tuesday "}
			2 { $WeekDay = "Wednesday "}
			3 { $WeekDay = "Thursday "}
			4 { $WeekDay = "Friday "}
			5 { $WeekDay = "Saturday "}
			6 { $WeekDay = "Sunday "}
		}
		$WeekDays = "$WeekDays $WeekDay"
	}
}

Switch ($RebootCriteria) {
	"0|0" { $ScheduleMissed = "not run" }
	"0|1" { $ScheduleMissed = "run ASAP, reboot NOT included" }
	"1|1" { $ScheduleMissed = "run ASAP, including reboot" }
}

If ($Mode -eq 0) {
	$ReportMode = "report only"
} Else {
	$ReportMode = "fail"
}

Switch ($RebootDevice) {
	0 { $RebootPolicy = "device will never be rebooted" }
	1 { $RebootPolicy = "device will reboot when needed" }
	2 { $RebootPolicy = "device will always reboot" }
}



Write-Host ("Device will be patched at {0} on every{1}" -f $Time, $WeekDays)
Write-Host ("After patching {0}." -f $RebootPolicy)
Write-Host ("If schedule is missed Patch Management will {0}." -f $ScheduleMissed)
Write-Host ("If patches are missing this check will {0}." -f $ReportMode)

For ($i = 0; $i -le 1; $i++) {
	Write-Host ("`nApprovalpolicy for {0}" -f $Vendors[$i])
	$ApprovalPolicy = @([regex]::Split($ApprovalOptions[$i],"\|"))
	For ($y = 0; $y -le 4; $y++) {
		Switch ($ApprovalPolicy[$y]) {
			1 { $Policy = "Ignore" }
			2 { $Policy = "Approve" }
			3 { $Policy = "Manual" }
		}
		Write-Host ("    {0,-10} {1}" -f $Category[$y], $Policy)
	}
}

If (($ScheduleOptions[2] -ge 8)) {
	# FAIL SCRIPT
	Exit 1001
}
Exit 0