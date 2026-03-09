[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Mac,
    [string]$DotfilesRepoUrl = "https://github.com/jdserenity/nvim-lazyvim-config.git",
    [string]$DotfilesSubPath = ".",
    [switch]$NoDashboard
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ManualSteps = New-Object System.Collections.Generic.List[string]
$script:Installed = New-Object System.Collections.Generic.List[string]
$script:Skipped = New-Object System.Collections.Generic.List[string]
$script:Failed = New-Object System.Collections.Generic.List[string]
$script:Tasks = New-Object System.Collections.Generic.List[object]
$script:DoneStates = @("installed", "skipped", "failed", "completed")

if ($Mac -and (-not $DryRun)) {
    throw "Use -Mac only with -DryRun. Example: ./bootstrap.ps1 -DryRun -Mac"
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

function Add-Task {
    param([string]$Title)
    $task = [PSCustomObject]@{
        Title = $Title
        Status = "pending"
        Details = ""
    }
    [void]$script:Tasks.Add($task)
    return ($script:Tasks.Count - 1)
}

function Set-TaskStatus {
    param(
        [int]$Index,
        [string]$Status,
        [string]$Details = ""
    )
    $script:Tasks[$Index].Status = $Status
    $script:Tasks[$Index].Details = $Details
}

function Get-CompletedTaskCount {
    $count = 0
    foreach ($task in $script:Tasks) {
        if ($script:DoneStates -contains $task.Status) {
            $count++
        }
    }
    return $count
}

function Render-Dashboard {
    param([string]$CurrentStep = "Working")

    if ($NoDashboard) {
        return
    }

    try {
        Clear-Host
    }
    catch {
        # Ignore if host does not support clearing.
    }

    $total = [Math]::Max($script:Tasks.Count, 1)
    $done = Get-CompletedTaskCount
    $percent = [int][Math]::Floor(($done / $total) * 100)
    $barWidth = 40
    $filled = [int][Math]::Floor(($percent / 100) * $barWidth)
    $empty = $barWidth - $filled

    Write-Host "SENAC BOOTSTRAP" -ForegroundColor Cyan
    if ($DryRun -and $Mac) {
        Write-Host "MODE: DRY RUN (mac preview)" -ForegroundColor Yellow
    }
    elseif ($DryRun) {
        Write-Host "MODE: DRY RUN" -ForegroundColor Yellow
    }
    Write-Host ("[{0}{1}] {2}% ({3}/{4} tasks)" -f ("#" * $filled), ("-" * $empty), $percent, $done, $total) -ForegroundColor White
    Write-Host ("Current: {0}" -f $CurrentStep) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host ("Installed: {0}  Skipped: {1}  Failed: {2}  Manual: {3}" -f $script:Installed.Count, $script:Skipped.Count, $script:Failed.Count, $script:ManualSteps.Count)
    Write-Host ""
    Write-Host "Steps:" -ForegroundColor White

    foreach ($task in $script:Tasks) {
        $prefix = "[ ]"
        $color = "DarkGray"
        switch ($task.Status) {
            "running" {
                $prefix = "[>]"
                $color = "Cyan"
            }
            "installed" {
                $prefix = "[OK]"
                $color = "Green"
            }
            "completed" {
                $prefix = "[OK]"
                $color = "Green"
            }
            "skipped" {
                $prefix = "[SKIP]"
                $color = "Yellow"
            }
            "failed" {
                $prefix = "[FAIL]"
                $color = "Red"
            }
        }

        $line = "{0} {1}" -f $prefix, $task.Title
        if (-not [string]::IsNullOrWhiteSpace($task.Details)) {
            $line = "{0} - {1}" -f $line, $task.Details
        }
        Write-Host $line -ForegroundColor $color
    }
}

function Write-FinalReport {
    Render-Dashboard -CurrentStep "Bootstrap complete"

    Write-Host ""
    Write-Host "=== Final Summary ===" -ForegroundColor Cyan
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
        Write-Host "Skipped items:" -ForegroundColor Yellow
        $script:Skipped | ForEach-Object { Write-Host "- $_" }
    }

    if ($script:Failed.Count -gt 0) {
        Write-Host ""
        Write-Host "Failed items:" -ForegroundColor Red
        $script:Failed | ForEach-Object { Write-Host "- $_" }
    }

    Write-Host ""
    Write-Host "Manual steps:" -ForegroundColor White
    $script:ManualSteps | Select-Object -Unique | ForEach-Object { Write-Host "- $_" }
}

function Install-WingetPackage {
    param(
        [string]$Name,
        [string]$Id,
        [int]$TaskIndex
    )

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Checking existing install"
    Render-Dashboard -CurrentStep "Install $Name"

    if ($DryRun -and $Mac) {
        $script:Skipped.Add("$Name ($Id) [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run (mac): would check/install"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    if (Test-WingetPackageInstalled -PackageId $Id) {
        $script:Skipped.Add("$Name ($Id)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Already installed"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    if ($DryRun) {
        $script:Skipped.Add("$Name ($Id) [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would install"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    try {
        winget install --id $Id -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity --scope user
        $script:Installed.Add("$Name ($Id)")
        Set-TaskStatus -Index $TaskIndex -Status "installed" -Details "Installed"
    }
    catch {
        $script:Failed.Add("$Name ($Id)")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Install failed"
        Add-ManualStep "Install $Name manually: https://winget.run/pkg/$($Id.Replace('.', '/'))"
    }
    Render-Dashboard -CurrentStep "Install $Name"
}

# Returns $true if WSL is installed and the default Ubuntu distro is initialized.
# An uninitialized distro hangs waiting for first-run setup, so we probe with
# a non-interactive command and a short timeout via Start-Job.
function Test-WslReady {
    $job = Start-Job -ScriptBlock {
        wsl -- bash -c "echo ready" 2>&1
    }
    $completed = Wait-Job $job -Timeout 8
    if ($null -eq $completed) {
        Stop-Job $job
        Remove-Job $job -Force
        return $false
    }
    $out = Receive-Job $job
    Remove-Job $job -Force
    return ($out -match "ready")
}

function Ensure-WslNode {
    param([int]$TaskIndex)

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Checking WSL"
    Render-Dashboard -CurrentStep "Setup Node.js in WSL"

    if ($DryRun -and $Mac) {
        $script:Skipped.Add("Node.js in WSL [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run (mac): would install nvm + node in WSL"
        Render-Dashboard -CurrentStep "Setup Node.js in WSL"
        return
    }

    if ($DryRun) {
        $script:Skipped.Add("Node.js in WSL [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would install nvm + node LTS via nvm"
        Render-Dashboard -CurrentStep "Setup Node.js in WSL"
        return
    }

    if (-not (Test-CommandExists -CommandName "wsl")) {
        $script:Skipped.Add("Node.js in WSL")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "WSL not installed yet — re-run bootstrap after WSL setup"
        Add-ManualStep "WSL was just installed. Restart your PC if prompted, then open 'Ubuntu 24.04' from the Start Menu, complete the username/password setup, and re-run bootstrap.ps1."
        Render-Dashboard -CurrentStep "Setup Node.js in WSL"
        return
    }

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Checking if Ubuntu is initialized"
    Render-Dashboard -CurrentStep "Setup Node.js in WSL"

    if (-not (Test-WslReady)) {
        $script:Skipped.Add("Node.js in WSL")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Ubuntu not initialized yet — re-run bootstrap after setup"
        Add-ManualStep "Ubuntu 24.04 needs first-time setup: open 'Ubuntu 24.04' from the Start Menu, choose a username and password, then re-run bootstrap.ps1."
        Render-Dashboard -CurrentStep "Setup Node.js in WSL"
        return
    }

    $nodeCheck = wsl -- bash -lc "node --version" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $script:Skipped.Add("Node.js in WSL ($nodeCheck)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Already installed ($nodeCheck)"
        Render-Dashboard -CurrentStep "Setup Node.js in WSL"
        return
    }

    try {
        Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Installing nvm"
        Render-Dashboard -CurrentStep "Setup Node.js in WSL"
        wsl -- bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"

        Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Installing Node.js LTS"
        Render-Dashboard -CurrentStep "Setup Node.js in WSL"
        wsl -- bash -lc "nvm install --lts"

        $version = wsl -- bash -lc "node --version" 2>$null
        $script:Installed.Add("Node.js in WSL ($version)")
        Set-TaskStatus -Index $TaskIndex -Status "installed" -Details "Installed ($version)"
    }
    catch {
        $script:Failed.Add("Node.js in WSL")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Install failed"
        Add-ManualStep "Install Node.js manually in WSL: open Ubuntu and run 'nvm install --lts' (install nvm first if needed)"
    }
    Render-Dashboard -CurrentStep "Setup Node.js in WSL"
}

function Install-WslNpmPackage {
    param(
        [string]$Name,
        [string]$Package,
        [string]$Cmd,
        [int]$TaskIndex
    )

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Checking WSL install"
    Render-Dashboard -CurrentStep "Install $Name in WSL"

    if ($DryRun -and $Mac) {
        $script:Skipped.Add("$Name ($Package) [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run (mac): would npm install -g $Package in WSL"
        Render-Dashboard -CurrentStep "Install $Name in WSL"
        return
    }

    if ($DryRun) {
        $script:Skipped.Add("$Name ($Package) [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would npm install -g $Package in WSL"
        Render-Dashboard -CurrentStep "Install $Name in WSL"
        return
    }

    if (-not (Test-CommandExists -CommandName "wsl")) {
        $script:Skipped.Add("$Name ($Package)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "WSL not available — re-run bootstrap after WSL setup"
        Render-Dashboard -CurrentStep "Install $Name in WSL"
        return
    }

    if (-not (Test-WslReady)) {
        $script:Skipped.Add("$Name ($Package)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Ubuntu not initialized yet — re-run bootstrap after setup"
        Render-Dashboard -CurrentStep "Install $Name in WSL"
        return
    }

    $checkCmd = wsl -- bash -lc "$Cmd --version" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $script:Skipped.Add("$Name ($Package)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Already installed"
        Render-Dashboard -CurrentStep "Install $Name in WSL"
        return
    }

    try {
        wsl -- bash -lc "npm install -g $Package"
        $script:Installed.Add("$Name ($Package) in WSL")
        Set-TaskStatus -Index $TaskIndex -Status "installed" -Details "Installed in WSL"
    }
    catch {
        $script:Failed.Add("$Name ($Package)")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Install failed"
        Add-ManualStep "Install $Name manually in WSL: open Ubuntu and run 'npm install -g $Package'"
    }
    Render-Dashboard -CurrentStep "Install $Name in WSL"
}

function Apply-NvimConfigFromDotfiles {
    param(
        [string]$RepoUrl,
        [string]$SubPath,
        [int]$TaskIndex
    )

    if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
        $script:Skipped.Add("Neovim config [no dotfiles repo configured]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "No dotfiles repo configured"
        Render-Dashboard -CurrentStep "Setup Neovim config"
        return
    }

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Preparing dotfiles sync"
    Render-Dashboard -CurrentStep "Setup Neovim config"

    if ($DryRun) {
        $script:Skipped.Add("Neovim config [dry-run]")
        if ($Mac) {
            Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run (mac): would clone and copy config"
        }
        else {
            Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would clone and copy config"
        }
        Render-Dashboard -CurrentStep "Setup Neovim config"
        return
    }

    if (-not (Test-CommandExists -CommandName "git")) {
        $script:Failed.Add("Neovim config setup")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Git is unavailable in this shell"
        Add-ManualStep "Git is missing, so Neovim config could not be cloned. Install Git, open a new PowerShell session, and rerun bootstrap.ps1."
        Render-Dashboard -CurrentStep "Setup Neovim config"
        return
    }

    $target = Join-Path $env:LOCALAPPDATA "nvim"
    if (Test-Path $target) {
        $script:Skipped.Add("Neovim config ($target already exists)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Existing config kept"
        Add-ManualStep "Neovim config already exists at $target. Delete or move it first if you want a fresh clone from $RepoUrl."
        Render-Dashboard -CurrentStep "Setup Neovim config"
        return
    }

    $tempRoot = Join-Path $env:TEMP ("dotfiles_" + [Guid]::NewGuid().ToString("N"))

    try {

        git clone --depth 1 $RepoUrl $tempRoot | Out-Null

        $source = $tempRoot
        if (-not [string]::IsNullOrWhiteSpace($SubPath) -and $SubPath -ne ".") {
            $source = Join-Path $tempRoot $SubPath
        }

        if (-not (Test-Path $source)) {
            throw "Subpath '$SubPath' not found in dotfiles repo"
        }

        New-Item -ItemType Directory -Path $target -Force | Out-Null

        $sourceItems = Get-ChildItem -Path $source -Force
        foreach ($item in $sourceItems) {
            if ($item.Name -eq ".git") {
                continue
            }
            Copy-Item -Path $item.FullName -Destination $target -Recurse -Force
        }

        $script:Installed.Add("Neovim config from jdserenity/nvim-lazyvim-config")
        Set-TaskStatus -Index $TaskIndex -Status "completed" -Details "Copied to $target"
        Add-ManualStep "Launch Neovim once (`nvim`) to let LazyVim install plugins."
    }
    catch {
        $script:Failed.Add("Neovim config setup")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Dotfiles sync failed"
        Add-ManualStep "Neovim config copy failed: $($_.Exception.Message). Clone $RepoUrl and copy '$SubPath' into $target manually."
    }
    finally {
        if ((Test-Path $tempRoot) -and (-not $DryRun)) {
            Remove-Item -Path $tempRoot -Recurse -Force
        }
    }
    Render-Dashboard -CurrentStep "Setup Neovim config"
}

$packageFile = Join-Path $PSScriptRoot "config/packages.json"
if (-not (Test-Path $packageFile)) {
    throw "Missing package config: $packageFile"
}

$wslPackageFile = Join-Path $PSScriptRoot "config/wsl-npm-packages.json"
if (-not (Test-Path $wslPackageFile)) {
    throw "Missing WSL package config: $wslPackageFile"
}

$packages = Get-Content -Raw -Path $packageFile | ConvertFrom-Json
$wslPackages = Get-Content -Raw -Path $wslPackageFile | ConvertFrom-Json

$preflightTask = Add-Task -Title "Preflight checks"
$packageTaskMap = @{}
foreach ($pkg in $packages) {
    $packageTaskMap[$pkg.id] = Add-Task -Title ("Install {0}" -f $pkg.name)
}
$wslNodeTask = Add-Task -Title "Setup Node.js in WSL"
$wslPackageTaskMap = @{}
foreach ($wpkg in $wslPackages) {
    $wslPackageTaskMap[$wpkg.package] = Add-Task -Title ("Install {0} in WSL" -f $wpkg.name)
}
$nvimTask = Add-Task -Title "Setup Neovim config"

Render-Dashboard -CurrentStep "Starting bootstrap"

Set-TaskStatus -Index $preflightTask -Status "running" -Details "Checking winget availability"
Render-Dashboard -CurrentStep "Preflight checks"

if ($DryRun -and $Mac) {
    Set-TaskStatus -Index $preflightTask -Status "completed" -Details "Dry run (mac): bypassed winget check"
}
else {
    if (-not (Test-CommandExists -CommandName "winget")) {
        Set-TaskStatus -Index $preflightTask -Status "failed" -Details "winget is unavailable"
        Add-ManualStep "Install/enable App Installer (`winget`). If blocked by school policy, ask IT for winget access."
        Add-ManualStep "Install required apps manually using the list in config/packages.json."
        Write-FinalReport
        exit 1
    }

    Set-TaskStatus -Index $preflightTask -Status "completed" -Details "winget is ready"
}

Render-Dashboard -CurrentStep "Preflight checks"

foreach ($pkg in $packages) {
    Install-WingetPackage -Name $pkg.name -Id $pkg.id -TaskIndex $packageTaskMap[$pkg.id]
}

Ensure-WslNode -TaskIndex $wslNodeTask

foreach ($wpkg in $wslPackages) {
    Install-WslNpmPackage -Name $wpkg.name -Package $wpkg.package -Cmd $wpkg.cmd -TaskIndex $wslPackageTaskMap[$wpkg.package]
}

Apply-NvimConfigFromDotfiles -RepoUrl $DotfilesRepoUrl -SubPath $DotfilesSubPath -TaskIndex $nvimTask

Add-ManualStep "All winget installs run as your user (no admin needed). If one fails anyway, IT may have blocked that specific package — ask them to allow it."
Add-ManualStep "WSL requires the VirtualMachinePlatform Windows Feature. If 'winget install Microsoft.WSL' fails, ask IT to enable it — it is a one-time unlock."
Add-ManualStep "Claude Code, Codex CLI, and Gemini CLI require auth — after install, open Ubuntu and run 'claude', 'codex', or 'gemini' to sign in interactively."
if ($DryRun -and $Mac) {
    Add-ManualStep "Mac dry run mode ran. No system changes were made."
}

Write-FinalReport
