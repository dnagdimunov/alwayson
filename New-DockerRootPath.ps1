function New-DockerRootPath {
    # Get the path to the current user's home directory
    $userHome = $env:HOME

    # Define the path to the Docker folder
    $dockerFolder = "$userHome/docker"

    # Check if the Docker folder exists
    if (-not (Test-Path $dockerFolder)) {
        # Create the Docker folder
        $retval = New-Item -Path $dockerFolder -ItemType Directory
        Write-Output "Docker folder created at $dockerFolder"
    } else {
        $retval = Get-Item $dockerFolder
    }

    return $retval
}
