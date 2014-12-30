VERSION HISTORY
1.0	INITIAL RELEASE

1.1	BUGFIX
	Removed all Powershell native parameter validation. Added parameters -Debug,
	-Verbose and -logfile to avoid parameter validation failure. Added code for
	parameter validation.

	Removed bug in parsing of Windows services if using "Default" as option.

1.2	MODIFICATION
	-Debug now implies -Verbose.