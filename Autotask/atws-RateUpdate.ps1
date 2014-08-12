#REQUIRES -Version 2

<#  
.SYNOPSIS  
	Script to update hourly rates in Autotask. The script is not generic, you
	need to modify it before each use.
	
.DESCRIPTION  
    This script uses Autotask Web Services API to update all hourly rates with
	a percentage defined as variable in this script. The change will be effecive
	immediately, so this script is only meant to be used by someone who knows
	what they are doing!
	   
.NOTES  
    File Name      : atwsPriceUpdate.ps1  
    Author         : Hugo Klemmestad hugo@klemmestad.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Copyright 2014 - Hugo Klemmestad    
.LINK  
    Inspired by av:  
    https://community.autotask.com/forums/p/15090/38343.aspx#38343
.LINK
    Oppdragsgiver:
    http://www.office-center.no 
.LINK
	Blog post:
	http://klemmestad.com/2014/08/01/batch-update-your-hourly-rates-in-autotask-using-powershell
.EXAMPLE  
    atwsPriceUpdate     
#>

# A small QueryXML function I got from Jon Czerwinski in an autotask forum
# https://community.autotask.com/forums/p/15090/38343.aspx#38343
# I have modified it to handle more fields and expressions

function New-ATWSQuery {
    [CmdletBinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [string]$Entity,
        [Parameter(Position=1,Mandatory=$true)]
        [string]$Field,
        [Parameter(Position=2,Mandatory=$false)]
        [string]$Expression,
        [Parameter(Position=3,Mandatory=$false)]
        [string]$Value,
        [Parameter(Position=4,Mandatory=$false)]
        [string]$Field2,
        [Parameter(Position=5,Mandatory=$false)]
        [string]$Expression2,
        [Parameter(Position=6,Mandatory=$false)]
        [string]$Value2,
        [Parameter(Position=7,Mandatory=$false)]
        [string]$Field3,
        [Parameter(Position=8,Mandatory=$false)]
        [string]$Expression3,
        [Parameter(Position=9,Mandatory=$false)]
        [string]$Value3,
        [Parameter(Position=10,Mandatory=$false)]
        [string]$Field4,
        [Parameter(Position=11,Mandatory=$false)]
        [string]$Expression4,
        [Parameter(Position=12,Mandatory=$false)]
        [string]$Value4,
        [Parameter(Position=13,Mandatory=$false)]
        [string]$Field5,
        [Parameter(Position=14,Mandatory=$false)]
        [string]$Expression5,
        [Parameter(Position=15,Mandatory=$false)]
        [string]$Value5

 )
    $query = "<queryxml><entity>$Entity</entity><query><condition><field>$Field<expression op=""$Expression"">$Value</expression></field></condition>"
	
	If (!($Field2 -eq ""))  {
        $query= "$query <condition><field>$Field2<expression op=""$Expression2"">$Value2</expression></field></condition>"
    }

    If (!($Field3 -eq ""))  {
         $query= "$query <condition><field>$Field3<expression op=""$Expression3"">$Value3</expression></field></condition>"
    } 
	
    If (!($Field4 -eq ""))  {
         $query= "$query <condition><field>$Field4<expression op=""$Expression4"">$Value4</expression></field></condition>"
    }
	
    If (!($Field5 -eq ""))  {
         $query= "$query <condition><field>$Field5<expression op=""$Expression5"">$Value5</expression></field></condition>"
    } 
	
	$query = "$query </query></queryxml>"
	
$query
 
}

# Log file
$myDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = $myDir + "\atws.log"

# Username and password for Autotask 
# The username must begin with a backslash, otherwise Windows will add a domain
# element that Autotask do not understand.
$username = "\your_autotask_user@domain.com"
$password = ConvertTo-SecureString "your_autotask_password" -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential($username,$password) 

# Create an Autotask SOAP object
$AutotaskURL = "https://webservices4.Autotask.net/atservices/1.5/atws.wsdl"
$atws = New-WebServiceProxy -URI $AutotaskURL -Credential $credentials
$zoneInfo = $atws.getZoneInfo($username)
If ($zoneInfo.Url -ne $AutotaskURL)
{
	$atws = New-WebServiceProxy -URI $zoneInfo.Url -Credential $credentials
}

# Todays date for logging
[datetime]$toDay = Get-Date -Format s

# Get all Time and Materials contracts
# Important: I have created a special contract category to mark updated contracts
# as updated. That way I may run the script more than once without getting a contract
# updated twice. I created the contract categori in Autotask and used
# powershell to learn its numerical ID
$contractQuery = New-ATWSQuery "Contract" "ContractType" "Equals" "1" "Status" "Equals" "1" "ContractCategory" "NotEqual" "16"
$contracts = $atws.query($contractQuery)

# Verify we have a result to work with
# Exit if we don't
If(!($contracts.EntityResults.Count -gt 0)) { 
	$logFileText = "{0,-25} | Ingenting" -f $toDay
	Add-Content $logFile $logFileText

	Exit 2 
}

# Get your main role by name
$roleQuery = New-ATWSQuery "Role" "Name" "Equals" "your_role_name_goes_here"
$mainRole = $atws.query($roleQuery).EntityResults[0]


$percentage = 4.3

foreach ($contract in $contracts.EntityResults) {
	
	# Update main role first
	$rateQuery = New-ATWSQuery "ContractRate" "ContractID" "Equals" $contract.id "RoleID" "Equals" $mainRole.id
	$baserate = $atws.query($rateQuery).EntityResults[0]
	
	# Calculate new hourly rate slowly to make sure you know what the code does
	# Round up(!) to nearest 5
	$hourlyRate = $hourlyRate + $hourlyRate * $percentage / 100 # manual percentage for code clarity
	$hourlyRate = $hourlyRate - ($hourlyRate % 5) + 5 # Round UP to nearest 5
	
	# Save hourly rate back to $baserate. We are not saving just yet.
	$baserate.ContractHourlyRate = $hourlyRate

	
	# Get other roles on contracts
	# In this script all rates will be set equal. You may not want this. Be 
	# careful!
	$rateQuery = New-ATWSQuery "ContractRate" "ContractID" "Equals" $contract.id "RoleID" "NotEqual" $mainRole.id "ContractHourlyRate" "GreaterThan" "0"
	$rates = $atws.query($rateQuery)
	foreach ($rate in $rates.EntityResults) {
		$rate.ContractHourlyRate = $hourlyRate
		$result = $atws.update($rate)
		If(!($result.ReturnCode -eq 1)) {
			$logFileText = "{0,-25} | Contract {1,30} | Role {2,15} | {3}" -f $toDay, $contract.ContractName, $rate.id, $result.Errors[1].Message
			Add-Content $logFile $logFileText
			Exit 2
		}		
	}
	# If we gotten this far: Update $baserate
	# It is important to wait until now. If the script fails before this, 
	# the hourly rate of your main role is still untouched. Since we use it to 
	# set the other rates, the script may still be used to fix things.
	$result = $atws.update($baserate)
	If(!($result.ReturnCode -eq 1)) {
		$logFileText = "{0,-25} | Contract {1,30} | Main Role {2,15} | {3}" -f $toDay, $contract.ContractName, $rate.id, $result.Errors[1].Message
		Add-Content $logFile $logFileText
		Exit 2
	}		
	
	# Remember: Your custom category may have a different ID
	$contract.ContractCategory = 16
	$atws.update($contract)
	If(!($result.ReturnCode -eq 1)) {
		$logFileText = "{0,-25} | Contract {1,30} | Could not update contract | {3}" -f $toDay, $contract.ContractName, $result.Errors[1].Message
		Add-Content $logFile $logFileText
		Exit 2
	}		

	# Save a note of the work you have done
	$noteToCreate = New-Object  Microsoft.PowerShell.Commands.NewWebserviceProxy.AutogeneratedTypes.WebServiceProxy1k_net_atservices_1_5_atws_wsdl.ContractNote
	$noteToCreate.ContractID = $contract.id
	$noteToCreate.Title = "Price Update"
	$noteToCreate.Description = "Hourly rates updated to $hourlyRate the $toDay."
	$atws.create($noteToCreate)
	
	# Write some info to the log file
	$logFileText = "{0,-25} | Contract {1,30} | {2,30}" -f $toDay, $contract.ContractName, $noteToCreate.Description
	Add-Content $logFile $logFileText

}

Exit 0