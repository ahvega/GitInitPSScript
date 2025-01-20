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
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-._]*[a-zA-Z0-9]$')]
    [ValidateScript({
        if ($_ -match '\.\.') {
            throw "Repository name cannot contain consecutive dots"
        }
        if ($_ -match '\.$') {
            throw "Repository name cannot end with a dot"
        }
        return $true
    })]
    [string]$ProjectName = $((Get-Location | Split-Path -Leaf))
)

# Error handling preference
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Check if a command exists
function Test-CommandExists {
    param($Command)
    $null -ne (Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

# Generate .gitignore content based on project type
function Get-GitIgnoreContent {
    $ignorePatterns = @()

    # Generic patterns
    $ignorePatterns += @(
        ".DS_Store",
        "Thumbs.db",
        "*.log",
        ".env"
    )

    # Node.js
    if (Test-Path "package.json") {
        $ignorePatterns += @(
            "# Node.js",
            "node_modules/",
            "npm-debug.log*",
            "yarn-debug.log*",
            "yarn-error.log*"
        )
    }

    # Python
    if ((Get-ChildItem -Filter "*.py" -Recurse | Select-Object -First 1) -or (Test-Path "pyproject.toml")) {
        $ignorePatterns += @(
            "# Python",
            "__pycache__/",
            "*.py[cod]",
            "*.pyc",
            ".Python",
            ".env/",
            ".venv/",
            "venv/",
            "ENV/"
        )
    }

    # .NET
    if (Get-ChildItem -Filter "*.csproj" -Recurse | Select-Object -First 1) {
        $ignorePatterns += @(
            "# .NET",
            "bin/",
            "obj/",
            ".vs/",
            "*.user",
            "*.suo"
        )
    }

    $ignorePatterns -join "`n"
}

# Main function to initialize the repository
function Initialize-Repository {
    Write-Log "Starting repository initialization..."

    # Check prerequisites
    Write-Log "Checking prerequisites..." -Level "INFO"
    if (-not (Test-CommandExists "git")) {
        throw "Git is not installed or not in PATH"
    }
    if (-not (Test-CommandExists "gh")) {
        Write-Log "GitHub CLI is not installed. Please install it from https://cli.github.com/" -Level "ERROR"
        throw "GitHub CLI installation required"
    }

    # Configure repository ownership settings
    Write-Log "Configuring repository ownership settings..." -Level "INFO"
    git config --global --add safe.directory $PWD

    # Check GitHub authentication
    Write-Log "Checking GitHub authentication..." -Level "INFO"
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "GitHub CLI not authenticated. Initiating login..." -Level "WARN"
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
    Write-Log "Checking if repository exists..." -Level "INFO"
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
        Write-Log "Creating new repository..." -Level "INFO"
        $isPrivate = Read-Host "Create private repository? (y/N)"
        $privateFlag = if ($isPrivate -eq 'y') { '--private' } else { '--public' }
        gh repo create "$githubUser/$ProjectName" $privateFlag --confirm
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create repository."
        }
    }

    # Initialize local repository
    Write-Log "Initializing local repository..." -Level "INFO"
    if (-not (Test-Path ".git")) {
        git init
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to initialize local repository."
        }
        Write-Log "Local repository initialized successfully" -Level "INFO"
    } else {
        Write-Log "Local repository already exists" -Level "INFO"
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
    Write-Log "Generating .gitignore..." -Level "INFO"
    $gitignoreContent = Get-GitIgnoreContent
    if (Test-Path ".gitignore") {
        $existingContent = Get-Content ".gitignore" -Raw
        $gitignoreContent = "$existingContent`n$gitignoreContent"
    }
    $gitignoreContent | Set-Content ".gitignore" -Force
    Write-Log ".gitignore file created/updated successfully" -Level "INFO"

    # Stage and commit changes
    Write-Log "Staging and committing changes..." -Level "INFO"
    git add .
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to stage changes."
    }
    Write-Log "Changes staged successfully" -Level "INFO"

    git commit -m "Initial commit"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to commit changes."
    }
    Write-Log "Initial commit created successfully" -Level "INFO"

    # Set up remote and push
    Write-Log "Setting up remote and pushing..." -Level "INFO"

    # Add remote
    if (-not (git remote | Where-Object { $_ -eq "origin" })) {
        git remote add origin "https://github.com/$githubUser/$ProjectName.git"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to add remote."
        }
        Write-Log "Remote added successfully" -Level "INFO"
    } else {
        Write-Log "Remote already exists" -Level "INFO"
    }

    # Determine default branch
    try {
        $defaultBranch = gh repo view "$githubUser/$ProjectName" --json defaultBranchRef --jq '.defaultBranchRef.name'
        if (-not $defaultBranch) {
            $defaultBranch = 'main'
        }
    } catch {
        $defaultBranch = 'main'
    }

    # Verify branch exists
    if (-not (git branch --list $defaultBranch)) {
        git branch $defaultBranch
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create default branch '$defaultBranch'"
        }
    }

    # Rename local branch if needed
    $currentBranch = git branch --show-current
    if ($currentBranch -ne $defaultBranch) {
        Write-Log "Renaming local branch from '$currentBranch' to '$defaultBranch'..." -Level "WARN"
        git branch -m $defaultBranch
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to rename branch to '$defaultBranch'"
        }
        Write-Log "Branch renamed to '$defaultBranch' successfully" -Level "INFO"
    }

    # Push changes
    Write-Log "Pushing changes to $defaultBranch branch..." -Level "INFO"
    git push -u origin $defaultBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push to remote repository."
    }
    Write-Log "Changes pushed successfully to $defaultBranch branch" -Level "INFO"
    Write-Log "Repository initialized at: https://github.com/$githubUser/$ProjectName" -Level "INFO"
}

try {
    Initialize-Repository
}
catch {
    Write-Log $_.Exception.Message -Level "ERROR"
    exit 1
}
