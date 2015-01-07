#VERSION HISTORY

##1.0	INITIAL RELEASE

### 1.1	BUGFIX
Removed all Powershell native parameter validation. Added parameters -Debug, 	-Verbose and -logfile to avoid parameter validation failure. Added code for 	parameter validation.

	Removed bug in parsing of Windows services if using "Default" as option.

### 1.2	MODIFICATION
	-Debug now implies -Verbose.
	
### 1.21 BUGFIX AND MODIFICATION
I took module PSScheduledJob for granted. That was wrong. I have added code to detect If the module is available. If it is, it will be used. If not I fall back to hard restart of the agent service.
	 
### 1.22 BUGFIX
Not all devices with Powershell v3 has PSScheduledJob. I am loath to use 

	Get-Module -ListAvailable 

because it is way to slow. I use Try-Catch to fail silently back to Restart-Service without too much cost.

### 1.23 BUGFIX AND MODIFICATION
Added text "PARAMETER: " as prefix to verbose out put for parameter validation.

Fixed sc.exe parameters. Using a fixed interval for all devices to avoid variable 	parsing errors.

### 1.24 MODIFICATION
I have dropped PSScheduledJob entirely and use schtasks.exe to restart monitoring agent.