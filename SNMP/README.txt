VERSION HISTORY
1.0	INITIAL RELEASE
	Initial release posted on LinkedIn. Last modification before release was to
	include native parameter validation. The $Target parameter was changed from
	[String] to [Array] to catch multiple targets correctly.

1.01	BUGFIX
	The type change in parameter $Target in previous release introduced a bug for
	any scenario where $Target was NOT an array. This is fixed in this release.

1.10	FEATURE
	The script now accepts  a -Name parameter. If -Name is used the script will
	use this name to mark each check added with a friendly name. Target is
	included, too, as the script may have more than 1 target.

	Warning! Do NOT use a name with spaces, even if you use quotes. It will break
	parameter validation because of parameters passing from script to script
	and powershell being invoked as a command line from Windows scripting host.

	If -Verbose is used the script now outputs detailed information.

	If -Debug is used the script outputs everything to a local logfile.
	Logfile name is supplied by agent automatically and cannot be changed.
	It is located in the agent directory and is named task_XX.log whree

	BUGFIX
	By trial and error I have learnt that a MAX powershell script must ALWAYS
	accept positional paramerers and NEVER perform native parameter validation.
	A Powershell parameter error can easily be caused by task_start.js mungling
	your parameters. A Powershell parameter error will result in no output
	whatsoever (errors are written to the Error stream, not STDOUT).

	The script now accepts positional parameters (but do not use them) and
	tries to feed problems back to you as well as task_start.js permits.
	
	The script now accepts -logfile parameter explicitly. It is used if running
	with -Debug. When an agent runs a script it embeds it in task_start.js to
	capture output. It always appends a parameter -logfile. This parameter MUST
	be accepted by the script, or the script will fail silently (no output to
	Dashboard).
1.11	FEATURE
	Fall back to Restart-Service if Powershell version < v3

1.12 	BUGFIX
	Not all machines with powershell version 3 has PSScheduledJob! Switched from
	version check to Try-Catch.
