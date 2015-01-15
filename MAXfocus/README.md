Scripts to run as Automated Tasks or Script Checks with MAXfocus
==========

## Enable-HardwareEvents.ps1
Makes hardware events show up in the eventlog HardwareEvents. It is created to run on any server and only perform actions where 
required.

On hardware servers (as opposed to virtual servers) there are usually a management chip. On this chip any hardware events are usually logged.
If a hardware chip is available, Windows automatically loads an IPMI driver. However, you must still enable an event subscription manually for the events to actuall show up in Hardware Events.

This script checks if IPMI is available and creates an event subscription if it is. You only need to run this script once.

If no IPMI driver is avaiable, the script does nothing.

## Install-ApplicationsFromMAXfocus.ps1
Installs software silently on servers and workstations using Chocolatey. The script is to be uploaded to your dashboard account as a user script. It can run both as a script check and as a scheduled task. You list package names as parameter to script. Chocolatey will update packages that are already installed. 

## MAXfocus_PatchSettings.ps1
A script that reads MAXfocus patchmanagement settings from a device and writes them back to the dashboard in a human-readable format.

The script does not modify anything.

## ReadRecoveryOptions.ps1
A script that reads a Windows machines crash report configuration and prints it back to the dashboard in a (somewhat) human-readable format.

The script does not modify anything.

## Verify-MAXfocusConfig.ps1
See http://klemmestad.com/2014/12/22/automate-maxfocus-with-powershell/

Configures default checks on a MAXfocus monitored device. Any change requires a rewrite of agent configuration files and a restart of the agent service.

## Verify-MAXfocusVMwareChecks.ps1
A script to automatically add VMware checks to a MAXfocus monitored device. *Warning!* This script is a hack. It downloads script items from GitHub, not the dashboard. 
