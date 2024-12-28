<#
.SYNOPSIS
    Initializes a Git repository and sets up GitHub integration.

.DESCRIPTION
    This script creates a new Git repository, sets up GitHub integration,
    generates appropriate .gitignore files, and performs initial commit and push.

.PARAMETER ProjectName
    Project name (default: current folder name - $((Split-Path -Leaf (Get-Location))))

.EXAMPLE
    .\Initialize-GitRepo.ps1 -ProjectName "my-awesome-project"
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidatePattern('^[a-zA-Z0-9-_\.]+$')]
    [string]$ProjectName = $((Get-Location | Split-Path -Leaf))
)

# Error handling preference
$ErrorActionPreference = "Stop"

Write-Host "Project name (default: $((Get-Location | Split-Path -Leaf))): " -NoNewline
$userInput = Read-Host
if ([string]::IsNullOrWhiteSpace($userInput)) {
    $ProjectName = Get-Location | Split-Path -Leaf
}
else {
    $ProjectName = $userInput
}

function Test-CommandExists {
    param($Command)
    $null -ne (Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

function Get-GitIgnoreContent {
    $ignorePatterns = @()

    # Generic patterns
    $ignorePatterns += @(
        ".DS_Store"
        "Thumbs.db"
        "*.log"
        ".env"
    )

    # Node.js
    if (Test-Path "package.json") {
        $ignorePatterns += @(
            "# Node.js"
            "node_modules/"
            "npm-debug.log*"
            "yarn-debug.log*"
            "yarn-error.log*"
        )
    }

    # Python
    if ((Get-ChildItem -Filter "*.py" -Recurse | Select-Object -First 1) -or (Test-Path "pyproject.toml")) {
        $ignorePatterns += @(
            "# Python"
            "__pycache__/"
            "*.py[cod]"
            "*$py.class"
            ".Python"
            ".env/"
            ".venv/"
            "venv/"
            "ENV/"
        )
    }

    # .NET
    if (Get-ChildItem -Filter "*.csproj" -Recurse | Select-Object -First 1) {
        $ignorePatterns += @(
            "# .NET"
            "bin/"
            "obj/"
            ".vs/"
            "*.user"
            "*.suo"
        )
    }

    $ignorePatterns -join "`n"
}

function Initialize-Repository {
    # Check prerequisites
    Write-Host "Checking prerequisites..." -ForegroundColor Cyan

    if (-not (Test-CommandExists "git")) {
        throw "Git is not installed or not in PATH"
    }

    # Set git configuration to allow the current directory ownership
    Write-Host "Configuring repository ownership settings..." -ForegroundColor Cyan
    # Set git config for safe directory using PWD (current working directory).
    git config --global --add safe.directory $PWD

    if (-not (Test-CommandExists "gh")) {
        throw "GitHub CLI is not installed. Please install GitHub CLI and try again."
    }

    # Check GitHub authentication
    Write-Host "Checking GitHub authentication..." -ForegroundColor Cyan
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "GitHub CLI not authenticated. Initiating login..." -ForegroundColor Yellow
        gh auth login
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub authentication failed."
        }
    }

    # Get GitHub username
    $githubUser = (gh api user -q .login)
    if (-not $githubUser) {
        throw "Could not determine GitHub username."
    }

    # Check if repository exists
    Write-Host "Checking if repository exists..." -ForegroundColor Cyan
    try {
        gh repo view "$githubUser/$ProjectName" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $continue = Read-Host "Repository already exists. Continue anyway? (y/N)"
            if ($continue -ne "y") {
                throw "Operation cancelled by user."
            }
        }
    } catch {
        # Repository doesn't exist, create it
        Write-Host "Creating new repository..." -ForegroundColor Cyan
        gh repo create "$githubUser/$ProjectName" --public --confirm
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create repository."
        }
    }

    # Initialize local repository
    Write-Host "Initializing local repository..." -ForegroundColor Cyan
    git init
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to initialize local repository."
    }

    # Check for source files
    $hasFiles = (Get-ChildItem -File | Where-Object { $_.Name -ne "Initialize-GitRepo.ps1" })
    if (-not $hasFiles) {
        $continue = Read-Host "No source files found. Continue anyway? (y/N)"
        if ($continue -ne "y") {
            throw "Operation cancelled by user."
        }
    }

    # Create or update .gitignore
    Write-Host "Generating .gitignore..." -ForegroundColor Cyan
    $gitignoreContent = Get-GitIgnoreContent
    if (Test-Path ".gitignore") {
        $existingContent = Get-Content ".gitignore" -Raw
        $gitignoreContent = "$existingContent`n$gitignoreContent"
    }
    $gitignoreContent | Set-Content ".gitignore" -Force

    # Stage and commit changes
    Write-Host "Staging and committing changes..." -ForegroundColor Cyan
    git add .
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to stage changes."
    }

    git commit -m "Initial commit"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to commit changes."
    }

    # Set up remote and push
    Write-Host "Setting up remote and pushing..." -ForegroundColor Cyan
    git remote add origin "https://github.com/$githubUser/$ProjectName.git"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add remote."
    }

    try {
        $defaultBranch = gh repo view "$githubUser/$ProjectName" --json defaultBranchRef --jq '.defaultBranchRef.name'
        if (-not $defaultBranch) {
            $defaultBranch = 'main'
        }
    } catch {
        $defaultBranch = 'main'
    }
    git push -u origin $defaultBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push to remote repository."
    }

    Write-Host "`nRepository successfully initialized!" -ForegroundColor Green
    Write-Host "Repository URL: https://github.com/$githubUser/$ProjectName" -ForegroundColor Green

    # Optional IDE launch commands (commented out by default)
    # Write-Host "`nUncomment these lines in the script to automatically launch your preferred IDE:" -ForegroundColor Yellow
    # code .
    # idea .
}

# Main execution
try {
    Initialize-Repository
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
