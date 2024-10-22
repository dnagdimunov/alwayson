function Wait-ForLogEntry(){
    param (
        [string]$ContainerName
        ,[string]$LogMessage
    )
    $logEntryFound = $false;
    While ($logEntryFound -ne $true) {
        $output = & docker logs $containerName 2>&1;
        if (($output | select-string $LogMessage).Length -gt 0) {
            Write-Host "Log entry '$LogMessage' was found on $ContainerName";
            $logEntryFound = $true;
        }
        else
        {
            Write-Host "Waiting for sql server instance to log '$LogMessage' on $ContainerName"
            Start-Sleep -s 1; 
            $logEntryFound = $false;
        }
    }
}