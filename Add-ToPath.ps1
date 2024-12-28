# Get the directory where the script is located
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Get the current PATH
$currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')

# Check if the path is already in PATH
if ($currentPath -notlike "*$scriptPath*") {
    # Add the new path
    $newPath = $currentPath + ";$scriptPath"
    
    # Set the new PATH
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    
    Write-Host "Successfully added '$scriptPath' to your PATH" -ForegroundColor Green
    Write-Host "Please restart your command prompt for the changes to take effect."
} else {
    Write-Host "The path '$scriptPath' is already in your PATH" -ForegroundColor Yellow
}
