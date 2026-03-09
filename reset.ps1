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
    Write-Host "  - WSL Ubuntu-24.04 distro (wsl --unregister) — this deletes all WSL data"
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
    Write-Host "Could not find config/packages.json — skipping winget uninstalls." -ForegroundColor Yellow
    $packages = @()
}
else {
    $packages = Get-Content -Raw -Path $packageFile | ConvertFrom-Json
}

Write-Host ""
Write-Host "=== Unregistering WSL Ubuntu ===" -ForegroundColor Cyan

if (Test-CommandExists -CommandName "wsl") {
    $distros = @("Ubuntu-24.04", "Ubuntu")
    foreach ($distro in $distros) {
        Write-Host "Attempting: wsl --unregister $distro" -ForegroundColor DarkCyan
        wsl --unregister $distro 2>$null
    }
}
else {
    Write-Host "WSL not found — skipping distro unregister." -ForegroundColor Yellow
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
    Write-Host "winget not found — skipping package uninstalls." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Removing Neovim config ===" -ForegroundColor Cyan

$nvimPath = Join-Path $env:LOCALAPPDATA "nvim"
if (Test-Path $nvimPath) {
    Write-Host "Removing $nvimPath..." -ForegroundColor DarkCyan
    Remove-Item -Path $nvimPath -Recurse -Force
    Write-Host "Removed." -ForegroundColor Green
}
else {
    Write-Host "No Neovim config found at $nvimPath — skipping." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Reset complete." -ForegroundColor Green
Write-Host "You can now re-run bootstrap.ps1 for a clean install." -ForegroundColor Green
Write-Host ""
Write-Host "Note: After WSL + Ubuntu reinstall, open Ubuntu once manually to initialize" -ForegroundColor Yellow
Write-Host "the distro before running bootstrap.ps1 again." -ForegroundColor Yellow
