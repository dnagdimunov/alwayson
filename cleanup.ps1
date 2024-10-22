. ./New-DockerRootPath.ps1

docker-compose down
$dockerMountPath = New-DockerRootPath

$null = Remove-Item "$dockerMountPath/Data/sql/TEST-SQL-DEV" -Recurse -Force -ErrorAction SilentlyContinue