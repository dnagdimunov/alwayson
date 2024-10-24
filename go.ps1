If ((Get-PSRepository -Name PSGallery).InstallationPolicy -eq "Untrusted") {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}

if ($null -eq (get-module sqlserver)) {install-module sqlserver -AllowClobber -AcceptLicense -Scope CurrentUser}
if ($null -eq (get-module dbatools)) {install-module dbatools -AllowClobber -AcceptLicense -Scope CurrentUser}

Import-Module dbatools
Import-Module SqlServer


Set-DbaToolsConfig -FullName sql.connection.trustcert -Value $true;
Set-DbaToolsConfig -FullName sql.connection.encrypt -Value $true;

#includes
. ./New-DockerRootPath.ps1
. ./Get-AdventureWorks.ps1
. ./Restore-AdventureWorks.ps1
. ./Wait-ForLogEntry.ps1

#docker ps -a -q | ForEach {docker start $_}
#create folder to mount data for docker images
$dockerMountPath = New-DockerRootPath

# create mssqlserver:2022-latest image
# build new docker image with enabled sql agent

./sqlserverimage/build.ps1

<#
    1. Create data path on host C:\docker\data
    2. Build SQL Server docker image with enabled AG features
    4. Download AdventureWorks from MSFT
    5. Use docker compose to start up containers.
        4.1 container will have mounted shared path for backups
    6. Copy AdventureWorks backup file into shared path
    7. Restore AdventureWorks to Primary node, change database recovery model to full
    8. Take full backup AdventureWorks to shared follder
    9. Create and Backup certificate.
    10. Restore backup to secondary containers.
    11. Configure AG Group
    12. Add Addventure Works db to AG Group.
    13. Dump SA password generated for all instances

#>

<#
    Slightly different method configuring ag in docker using init scripts
    https://www.sqlservercentral.com/articles/sql-server-alwayson-with-docker-containers
#>

<#
    to execute sqlcmd within docker container, following method can be used if sql command line tools are installed in the image
    docker exec $primarynode /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$pass" -Q "select @@version";
#>
#region declares
    $global:pass = $(New-Guid);
    $env:SA_PASSWORD = $global:pass
    
    Write-Verbose "Instance pwd: $pass"
    if ([string]::IsNullOrEmpty($pass) ) {$pass = [System.Web.Security.Membership]::GeneratePassword(10,2)};

    $CNAME = "TEST-SQL-DEV";
    $AGNAME = "TEST";
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'sa', $($pass | ConvertTo-SecureString -AsPlainText -Force )


    $containers = @(
    (New-Object -Type PSObject -Property @{ServerName="DC1-DEVSQLTST01";agrole="Primary"  ;address="localhost,20001"; }),
    (New-Object -Type PSObject -Property @{ServerName="DC1-DEVSQLTST02";agrole="Secondary";address="localhost,20002"; }),
    (New-Object -Type PSObject -Property @{ServerName="DC2-DEVSQLTST01";agrole="Secondary";address="localhost,20003"; })
    );
#endregion declares 

#create data files paths
$paths = @();
$paths += "$($dockerMountPath.FullName)/Data/sql/$CNAME/backup/";
$containers | ForEach-Object {
    $paths += "$($dockerMountPath.FullName)/Data/sql/$CNAME/$($_.ServerName)/data/";
    $paths += "$($dockerMountPath.FullName)/Data/sql/$CNAME/$($_.ServerName)/log/";
}
$paths | ForEach-Object {
    If (-Not (Test-Path $_)) {
        Write-Host "Creating $_"
        $null = New-Item -ItemType Directory -Path $_
    }
}


#create containers
Write-Host "Script path $PSScriptRoot"
Push-Location $PSScriptRoot
    #start containers
    docker-compose up -d
Pop-Location

#for ag group, need to wait for a message that is past ready for client connections, since ag replica manager is not started yet.
#wait for containers to start up
Write-Host "Waiting for sql server nodes to startup"
$containers| ForEach-Object {
    $containerName = $_.ServerName;
    Wait-ForLogEntry -ContainerName $containerName -LogMessage "The tempdb database has"
}

#pull adventure works db, this is a backup of a database from 2017 server, needs to be restored and backed up as 2022 version, in order to seed AG
$AdventureWorksDbPath = Get-AdventureWorks -DownloadPath "$($dockerMountPath.FullName)/Data/sql/AdventureWorks/"
Write-Host "Downloaded AdventureWorks Backup Path: $AdventureWorksDbPath"


#default backup up path for all containers is mounted to same path on host, copy downloaded file to this mount
if (-NOT (Test-Path "$($dockerMountPath.FullName)/Data/sql/$CNAME/backup/AdventureWorks2017/")) {
    $null = New-Item -ItemType Directory "$($dockerMountPath.FullName)/Data/sql/$CNAME/backup/AdventureWorks2017/"
}
$null = Copy-Item $AdventureWorksDbPath/*.* "$($dockerMountPath.FullName)/Data/sql/$CNAME/backup/AdventureWorks2017/" -Force -Confirm:$False

#region primary node config
    #Restore  AdventureWorks on primary node, by default downloaded from msdn it's in simple recovery model
    $nodename = ($containers | Where-Object {$_.agrole -eq "Primary"}).ServerName
    $primarynode = & docker ps -f NAME="$nodename" -q

    Restore-AdventureWorks -ServerInstance $(($containers | Where-Object {$_.agrole -eq 'Primary'}).address) `
        -BackupPath "/var/opt/mssql/backup/AdventureWorks2017/" `
        -NoRecovery:$False `
        -Credential $cred

    #change recovery mode
    $databases = @("master", "msdb", "AdventureWorks2017")
    $databases | ForEach-Object {
        Set-DbaDBRecoveryModel -SqlInstance $(($containers | Where-Object {$_.agrole -eq 'Primary'}).address) `
            -Database $_ `
            -RecoveryModel Full `
            -Confirm:$false `
            -SqlCredential $cred
        }

    #create new backup to seed to secondary instances.
    Backup-DbaDatabase -SqlInstance $(($containers | Where-Object {$_.agrole -eq 'Primary'}).address) `
        -Database AdventureWorks2017 `
        -Type Full `
        -Path '/var/opt/mssql/backup/AdventureWorksFull/' `
        -SqlCredential $cred

    New-DbaDbCertificate -SqlInstance $(($containers | Where-Object {$_.agrole -eq 'Primary'}).address) `
        -Database "master" `
        -Name "dbm_certificate" `
        -Subject  "AG Connectivity" `
        -StartDate $(Get-Date -Year (Get-Date).Year -Month 1 -Day 1) `
        -ExpirationDate $(Get-Date -Year ((Get-Date).Year + 1) -Month 12 -Day 31) `
        -SecurePassword $($pass | ConvertTo-SecureString -AsPlainText -Force) `
        -SqlCredential $cred
    
    Backup-DbaDbCertificate -SqlInstance $(($containers | Where-Object {$_.agrole -eq 'Primary'}).address) `
        -Certificate "dbm_certificate" `
        -EncryptionPassword $($pass | ConvertTo-SecureString -AsPlainText -Force) `
        -DecryptionPassword $($pass | ConvertTo-SecureString -AsPlainText -Force) `
        -Path "/var/opt/mssql/backup/certificates/" `
        -Suffix "" `
        -SqlCredential $cred `
        -Confirm:$false
#endregion

$containers | ForEach-Object {
    $containerName = $_.ServerName;
    New-DbaLogin -SqlInstance $($_.address) `
        -Login "dbm_login" `
        -PasswordExpirationEnabled:$false `
        -PasswordPolicyEnforced:$false `
        -PasswordMustChange:$false `
        -SecurePassword $($pass | ConvertTo-SecureString -AsPlainText -Force) `
        -SqlCredential $cred `
        -Confirm:$False

    Invoke-Sqlcmd -ServerInstance $($_.Address) `
        -Database "master" `
        -Query "ALTER SERVICE MASTER KEY FORCE REGENERATE" `
        -Credential $cred `
        -TrustServerCertificate 
    
    New-DbaServiceMasterKey -SqlInstance $($_.address) `
        -SqlCredential $cred `
        -SecurePassword $($pass | ConvertTo-SecureString -AsPlainText -Force) `
        -Confirm:$False
    
    Get-DbaDbCertificate -SqlInstance $($_.address) -Certificate dbm_certificate -SqlCredential $cred | Remove-DbaDbCertificate -Confirm:$false

    Restore-DbaDbCertificate -SqlInstance $($_.address) `
        -Path "/var/opt/mssql/backup/certificates" `
        -Database "master" `
        -Name "dbm_certificate" `
        -DecryptionPassword $($pass | ConvertTo-SecureString -AsPlainText -Force) `
        -SqlCredential $cred `
        -Confirm:$false `

    New-DbaEndpoint -SqlInstance $($_.address) `
        -Name "hadr_endpoint" `
        -Type DatabaseMirroring `
        -Port 5022 `
        -EncryptionAlgorithm AES `
        -Certificate dbm_certificate `
        -Role All `
        -SqlCredential $cred `
        -Confirm:$False

    Start-DbaEndpoint  -SqlInstance $($_.address) `
        -Endpoint "hadr_endpoint" `
        -SqlCredential $cred

    Invoke-Sqlcmd -ServerInstance $($_.Address) `
        -Database "master" `
        -Query "GRANT CONNECT ON ENDPOINT::[hadr_endpoint] TO [dbm_login]" `
        -Credential $cred `
        -TrustServerCertificate 

    Wait-ForLogEntry -ContainerName $containerName -LogMessage "The Database Mirroring endpoint is now listening for connections."
    Wait-ForLogEntry -ContainerName $containerName -LogMessage "Database mirroring has been enabled on this instance of SQL Server."
}

#restore AdventureWorks and  certificate on secondary nodes with norecovery
$containers | Where-Object {$_.agrole -eq "Secondary"} | ForEach-Object {
    $containerAddress = $_.address
    
    Restore-AdventureWorks -ServerInstance $containerAddress `
        -BackupPath "/var/opt/mssql/backup/AdventureWorksFull/" `
        -NoRecovery:$True `
        -Credential $cred
}

#create availability group
$createAgGroupParams = @{
    Primary = $(($containers | Where-Object {$_.agrole -eq 'Primary'}).address)
    PrimarySqlCredential = $cred
    Name = "TEST"
    ClusterType = "None"
    SeedingMode = "Automatic"
    FailoverMode = "Manual"
    Confirm = $false
    }

#New-DbaAvailabilityGroup @createAgGroupParams

$agQueries = @(
"
    CREATE AVAILABILITY GROUP [$AGNAME]
    WITH (CLUSTER_TYPE = NONE)
    FOR REPLICA ON 
            N'DC1-DEVSQLTST01'
            WITH (
            ENDPOINT_URL = N'tcp://DC1-DEVSQLTST01:5022',
                AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
                SEEDING_MODE = MANUAL,
                FAILOVER_MODE = MANUAL, SECONDARY_ROLE (ALLOW_CONNECTIONS=ALL)),
            N'DC1-DEVSQLTST02'
            WITH (
            ENDPOINT_URL = N'tcp://DC1-DEVSQLTST02:5022',
                AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
                SEEDING_MODE = MANUAL,
                FAILOVER_MODE = MANUAL, SECONDARY_ROLE (ALLOW_CONNECTIONS=ALL)),
            N'DC2-DEVSQLTST01'
            WITH (
            ENDPOINT_URL = N'tcp://DC2-DEVSQLTST01:5022',
                AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
                SEEDING_MODE = MANUAL,
                FAILOVER_MODE = MANUAL, SECONDARY_ROLE (ALLOW_CONNECTIONS=ALL))
    "
,"ALTER AVAILABILITY GROUP [$AGNAME] GRANT CREATE ANY DATABASE"
,"ALTER AVAILABILITY GROUP [$AGNAME] ADD DATABASE AdventureWorks2017"
)

Write-Host "Creating Availability Group on primary node."
$agQueries | ForEach-Object {
    docker exec $primarynode /opt/mssql-tools/bin/sqlcmd `
    -S localhost -U sa -P "$pass" `
    -Q $_;
}


$agQueries = @(
"
    IF NOT EXISTS (
    SELECT * 
    from sys.dm_hadr_availability_replica_states 
        inner join sys.availability_groups ON dm_hadr_availability_replica_states.group_id = availability_groups.group_id
        inner join sys.availability_replicas ON availability_replicas.group_id = availability_groups.group_id and 
            dm_hadr_availability_replica_states.replica_id = availability_replicas.replica_id
    WHERE Role_desc = 'PRIMARY'
        and replica_server_name = @@SERVERNAME
    )
        BEGIN
            print 'Joining Availability Group [$AGNAME]'

            ALTER AVAILABILITY GROUP [$AGNAME] JOIN WITH (CLUSTER_TYPE = NONE);
            ALTER AVAILABILITY GROUP [$AGNAME] GRANT CREATE ANY DATABASE;
        END
    "
)

$containers | ForEach-Object {
    $n = $_.ServerName;
    $agQueries | ForEach-Object {
    docker exec $n /opt/mssql-tools/bin/sqlcmd `
    -S localhost -U sa -P "$pass" `
    -Q $_;
    }
}


$containers | Where-Object {$_.agrole -eq "secondary"} | ForEach-Object {
    $containerName = $_.ServerName;
    docker exec $containerName  /opt/mssql-tools/bin/sqlcmd `
        -S localhost -U sa -P "$pass" `
             -Q "
            IF DB_ID('AdventureWorks2017') IS NOT NULL 
            BEGIN
                ALTER DATABASE AdventureWorks2017 SET HADR AVAILABILITY GROUP = $AGNAME; 
            END

            "
            ;
}


<# 
Import-Module DBATools;
$containers | ForEach {
    if ($(Get-DbaClientAlias | Where {$_.AliasName -eq $($_.ServerName)}) -eq $null) {
        New-DbaClientAlias -ServerName $($_.address) -Alias $($_.ServerName);
    }
}

New-DbaClientAlias -ServerName $primarynode.address -Alias $CNAME;
#>

Write-Host "SA password:$global:pass"
Write-Host ([string]($a.Config.Env | Where-Object {$_ -Like "*SA_PASSWORD*"}) -split '=')[1] 
