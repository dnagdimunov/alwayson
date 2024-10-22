
$dockerFile = Get-ChildItem -Recurse dockerfile 
Push-Location $dockerFile.DirectoryName
docker build --platform linux/amd64 -t mssqlserver:2022-latest .
Pop-Location

