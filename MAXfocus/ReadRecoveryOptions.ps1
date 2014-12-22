# List of settings that indicate the action to be taken by a computer
# Runs on Windows 7,8 workstations
Try {
    $RecoveryConf = get-wmiobject  "Win32_OSRecoveryConfiguration" 
    foreach ($RCItem in $RecoveryConf) { 
        switch ($RCItem.DebugInfoType) {
                0{$DebugInfoType= "None"}
                1{$DebugInfoType= "Complete Memory Dump"}
                2{$DebugInfoType= "Kernel Memory Dump"}
                3{$DebugInfoType= "Small Memory Dump"}
            }   
        write-host "Automatically reboot is          "  $RCItem.AutoReboot
        write-host "Description is                   "  $RCItem.Description
        write-host "Debug file path       is         "  $RCItem.DebugFilePath
        write-host "Debug information type is        "  $DebugInfoType
        write-host "Expanded debug file path is      "  $RCItem.ExpandedDebugFilePath
        write-host "Expanded mini dump directory is  "  $RCItem.ExpandedMiniDumpDirectory
        write-host "Name is                          "  $RCItem.Name 
        write-host "Send admin alert ID is           "  $RCItem.SendAdminAlert
        write-host "Overwrite existing debug file is "  $RCItem.OverwriteExistingDebugFile
    } 
    write-host "Successfully passed"
    exit 0
    }
Catch {
    write-host "Failure"
    exit 1001
      }