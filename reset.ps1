[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

if (-not $Force) {
    Write-Host ""
    Write-Host "SENAC BOOTSTRAP RESET" -ForegroundColor Cyan
    Write-Host "This will uninstall everything bootstrap.ps1 installs:" -ForegroundColor Yellow
    Write-Host "  - All winget packages in config/packages.json"
    Write-Host "  - All npm global packages in config/npm-packages.json (Claude Code, Codex, Gemini)"
    Write-Host "  - Neovim config at %LOCALAPPDATA%\nvim"
    Write-Host ""
    Write-Host "Run with -Force to proceed: ./reset.ps1 -Force" -ForegroundColor Yellow
    exit 0
}

function Test-CommandExists {
    param([string]$CommandName)
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

$packageFile = Join-Path $PSScriptRoot "config/packages.json"
if (-not (Test-Path $packageFile)) {
    Write-Host "Could not find config/packages.json - skipping winget uninstalls." -ForegroundColor Yellow
    $packages = @()
}
else {
    $packages = Get-Content -Raw -Path $packageFile | ConvertFrom-Json
}

Write-Host ""
Write-Host "=== Uninstalling npm global packages ===" -ForegroundColor Cyan

$npmPackageFile = Join-Path $PSScriptRoot "config/npm-packages.json"
if (-not (Test-Path $npmPackageFile)) {
    Write-Host "Could not find config/npm-packages.json - skipping npm uninstalls." -ForegroundColor Yellow
    $npmPackages = @()
}
else {
    $npmPackages = Get-Content -Raw -Path $npmPackageFile | ConvertFrom-Json
}

if (Test-CommandExists -CommandName "npm") {
    foreach ($npkg in $npmPackages) {
        Write-Host "Stopping $($npkg.cmd) process if running..." -ForegroundColor DarkCyan
        Stop-Process -Name $npkg.cmd -Force -ErrorAction SilentlyContinue
        Write-Host "Uninstalling $($npkg.name) ($($npkg.package))..." -ForegroundColor DarkCyan
        npm uninstall -g $npkg.package 2>$null
    }
}
else {
    Write-Host "npm not found - skipping npm package uninstalls." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Uninstalling winget packages ===" -ForegroundColor Cyan

if (Test-CommandExists -CommandName "winget") {
    foreach ($pkg in $packages) {
        Write-Host "Uninstalling $($pkg.name) ($($pkg.id))..." -ForegroundColor DarkCyan
        winget uninstall --id $pkg.id -e --disable-interactivity 2>$null
    }
}
else {
    Write-Host "winget not found - skipping package uninstalls." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Removing Neovim ===" -ForegroundColor Cyan

$nvimConfig = Join-Path $env:LOCALAPPDATA "nvim"
if (Test-Path $nvimConfig) {
    Write-Host "Removing config at $nvimConfig..." -ForegroundColor DarkCyan
    Remove-Item -Path $nvimConfig -Recurse -Force
    Write-Host "Removed." -ForegroundColor Green
}
else {
    Write-Host "No Neovim config found at $nvimConfig - skipping." -ForegroundColor Yellow
}

$nvimInstall = Join-Path $env:LOCALAPPDATA "Programs\Neovim"
if (Test-Path $nvimInstall) {
    Write-Host "Removing portable install at $nvimInstall..." -ForegroundColor DarkCyan
    Remove-Item -Path $nvimInstall -Recurse -Force
    Write-Host "Removed." -ForegroundColor Green

    $binDir = Join-Path $nvimInstall "bin"
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -like "*$binDir*") {
        $newPath = ($userPath -split ";" | Where-Object { $_ -ne $binDir }) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Removed $binDir from user PATH." -ForegroundColor Green
    }
}
else {
    Write-Host "No portable Neovim found at $nvimInstall - skipping." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Reset complete." -ForegroundColor Green
Write-Host "You can now re-run bootstrap.ps1 for a clean install." -ForegroundColor Green
