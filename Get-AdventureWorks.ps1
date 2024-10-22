function Get-AdventureWorks() {
    param (
        [string]$DownloadPath,
        [string]$SourceUri = "https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2017.bak"
    )

    If (-Not (Test-Path $DownloadPath)) {
        $null = New-Item -ItemType Directory -Path $$DownloadPath  
    }

    If (-Not (Test-Path "$DownloadPath/AdventureWorks2017.bak")) {
        Invoke-WebRequest -Uri $SourceUri -OutFile "$DownloadPath\AdventureWorks2017.bak"
        }

    return $DownloadPath;
}