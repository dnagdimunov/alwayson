function Restore-AdventureWorks() {
    param (
        [string]$ServerInstance,
        [string]$BackupPath,
        [switch]$NoRecovery,
        [PSCredential]$Credential
    )
    $DestinationDataDirectory = "/var/opt/mssql/data/"
    $DestinationLogDirectory = "/var/opt/mssql/log/"

    $history = Get-DbaBackupInformation  -SqlInstance $ServerInstance `
        -Path $BackupPath `
        -SqlCredential $Credential 
    
    $filelist = $history.FileList;
    $fileMapping = @{};

    $filelist | ForEach-Object {
        if ($_.Type -eq "D") {
            $_.PhysicalName = $DestinationDataDirectory + $_.PhysicalName.Substring($_.PhysicalName.LastIndexOf('\') +  1)
        }
        if ($_.Type -eq "L") {
            $_.PhysicalName = $DestinationLogDirectory + $_.PhysicalName.Substring($_.PhysicalName.LastIndexOf('\') +  1)
        }
        $fileMapping[$($_.LogicalName)] = $_.PhysicalName;
    }
    
    Restore-DbaDatabase -SqlInstance $ServerInstance `
        -Path $BackupPath `
        -DatabaseName "AdventureWorks2017" `
        -NoRecovery:$NoRecovery `
        -FileMapping $fileMapping `
        -SqlCredential $Credential `
        -UseDestinationDefaultDirectories:$true

    return;
}