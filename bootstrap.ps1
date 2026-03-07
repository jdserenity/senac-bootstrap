[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$DotfilesRepoUrl = "",
    [string]$DotfilesSubPath = "nvim"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ManualSteps = New-Object System.Collections.Generic.List[string]
$script:Installed = New-Object System.Collections.Generic.List[string]
$script:Skipped = New-Object System.Collections.Generic.List[string]
$script:Failed = New-Object System.Collections.Generic.List[string]

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Add-ManualStep {
    param([string]$Text)
    $script:ManualSteps.Add($Text)
}

function Test-CommandExists {
    param([string]$CommandName)
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Test-WingetPackageInstalled {
    param([string]$PackageId)

    $raw = winget list --id $PackageId -e --disable-interactivity 2>$null | Out-String
    return ($raw -match [Regex]::Escape($PackageId))
}

function Install-WingetPackage {
    param(
        [string]$Name,
        [string]$Id
    )

    Write-Host "Checking $Name ($Id)..."
    if (Test-WingetPackageInstalled -PackageId $Id) {
        Write-Host "  Already installed" -ForegroundColor DarkGray
        $script:Skipped.Add("$Name ($Id)")
        return
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would install" -ForegroundColor Yellow
        $script:Skipped.Add("$Name ($Id) [dry-run]")
        return
    }

    try {
        winget install --id $Id -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
        Write-Host "  Installed" -ForegroundColor Green
        $script:Installed.Add("$Name ($Id)")
    }
    catch {
        Write-Host "  Failed" -ForegroundColor Red
        $script:Failed.Add("$Name ($Id)")
        Add-ManualStep "Install $Name manually: https://winget.run/pkg/$($Id.Replace('.', '/'))"
    }
}

function Apply-NvimConfigFromDotfiles {
    param(
        [string]$RepoUrl,
        [string]$SubPath
    )

    if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
        return
    }

    if (-not (Test-CommandExists -CommandName "git")) {
        Add-ManualStep "Git is missing, so dotfiles could not be cloned. Install Git first, then rerun with -DotfilesRepoUrl."
        return
    }

    $target = Join-Path $env:LOCALAPPDATA "nvim"
    if (Test-Path $target) {
        Write-Host "Neovim config already exists at $target; skipping dotfiles copy" -ForegroundColor DarkGray
        return
    }

    $tempRoot = Join-Path $env:TEMP ("dotfiles_" + [Guid]::NewGuid().ToString("N"))

    try {
        if (-not $DryRun) {
            git clone --depth 1 $RepoUrl $tempRoot | Out-Null
            $source = Join-Path $tempRoot $SubPath
            if (-not (Test-Path $source)) {
                throw "Subpath '$SubPath' not found in dotfiles repo"
            }

            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Copy-Item -Path (Join-Path $source "*") -Destination $target -Recurse -Force
            Write-Host "Copied Neovim config to $target" -ForegroundColor Green
        }
        else {
            Write-Host "[DryRun] Would clone dotfiles and copy '$SubPath' to $target" -ForegroundColor Yellow
        }
    }
    catch {
        Add-ManualStep "Dotfiles copy failed: $($_.Exception.Message). Manually copy '$SubPath' from your dotfiles repo to $target."
    }
    finally {
        if ((Test-Path $tempRoot) -and (-not $DryRun)) {
            Remove-Item -Path $tempRoot -Recurse -Force
        }
    }
}

Write-Section "Preflight"
if (-not (Test-CommandExists -CommandName "winget")) {
    Write-Host "winget is not available on this machine." -ForegroundColor Red
    Add-ManualStep "Install/enable App Installer (winget). If blocked by school policy, ask IT for winget access."
    Add-ManualStep "Install required apps manually using the list in config/packages.json."

    Write-Section "Manual Steps"
    $script:ManualSteps | ForEach-Object { Write-Host "- $_" }
    exit 1
}

$packageFile = Join-Path $PSScriptRoot "config/packages.json"
if (-not (Test-Path $packageFile)) {
    throw "Missing package config: $packageFile"
}

$packages = Get-Content -Raw -Path $packageFile | ConvertFrom-Json

Write-Section "Install Packages"
foreach ($pkg in $packages) {
    Install-WingetPackage -Name $pkg.name -Id $pkg.id
}

Write-Section "Optional Config"
Apply-NvimConfigFromDotfiles -RepoUrl $DotfilesRepoUrl -SubPath $DotfilesSubPath

Add-ManualStep "Sign in to Arc and/or Chrome manually (account sync, MFA, and policies cannot be safely automated)."
Add-ManualStep "If school policy blocks installs, rerun from an elevated PowerShell or contact IT."

Write-Section "Summary"
Write-Host "Installed: $($script:Installed.Count)"
Write-Host "Skipped:   $($script:Skipped.Count)"
Write-Host "Failed:    $($script:Failed.Count)"

if ($script:Installed.Count -gt 0) {
    Write-Host ""
    Write-Host "Installed items:" -ForegroundColor Green
    $script:Installed | ForEach-Object { Write-Host "- $_" }
}

if ($script:Skipped.Count -gt 0) {
    Write-Host ""
    Write-Host "Skipped items:" -ForegroundColor DarkGray
    $script:Skipped | ForEach-Object { Write-Host "- $_" }
}

if ($script:Failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed items:" -ForegroundColor Red
    $script:Failed | ForEach-Object { Write-Host "- $_" }
}

Write-Section "Manual Steps"
$script:ManualSteps | Select-Object -Unique | ForEach-Object { Write-Host "- $_" }
