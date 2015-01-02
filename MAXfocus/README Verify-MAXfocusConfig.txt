VERSION HISTORY
1.0	INITIAL RELEASE

1.1	BUGFIX
	Removed all Powershell native parameter validation. Added parameters -Debug,
	-Verbose and -logfile to avoid parameter validation failure. Added code for
	parameter validation.

	Removed bug in parsing of Windows services if using "Default" as option.

1.2	MODIFICATION
	-Debug now implies -Verbose.
	
1.21 BUGFIX AND MODIFICATION
	 I took module PSScheduledJob for granted. That was wrong. I have added code to detect
	 If the module is available. If it is, it will be used. If not I fall back to hard
	 restart of the agent service.
	 
	 Copied LastChangeLog functionality from Verify-MAXfocusConfig.