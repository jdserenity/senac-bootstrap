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
$script:ActivityLog = New-Object System.Collections.Generic.List[string]

if ($Mac -and (-not $DryRun)) {
    throw "Use -Mac only with -DryRun. Example: ./bootstrap.ps1 -DryRun -Mac"
}

function Add-ManualStep {
    param([string]$Text)
    $script:ManualSteps.Add($Text)
}

function Write-Log {
    param([string]$Msg)
    $script:ActivityLog.Add($Msg)
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

    if ($script:ActivityLog.Count -gt 0) {
        Write-Host ""
        Write-Host "Activity:" -ForegroundColor DarkGray
        $recentLogs = $script:ActivityLog | Select-Object -Last 5
        foreach ($entry in $recentLogs) {
            Write-Host "  $entry" -ForegroundColor DarkGray
        }
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

function Open-AppAfterInstall {
    param([string]$Cmd)
    if ([string]::IsNullOrWhiteSpace($Cmd)) { return }
    try {
        Start-Process $Cmd -ErrorAction Stop
    }
    catch {
        # Silently ignore launch errors — install succeeded even if open fails.
    }
}

function Open-InNewTerminalTab {
    param([string]$Cmd)
    if ([string]::IsNullOrWhiteSpace($Cmd)) { return }
    try {
        $shell = if (Test-CommandExists "pwsh") { "pwsh" } else { "powershell" }
        if (Test-CommandExists "wt") {
            Start-Process wt -ArgumentList "new-tab", "--", $shell, "-NoExit", "-Command", $Cmd
        }
        else {
            Start-Process $shell -ArgumentList "-NoExit", "-Command", $Cmd
        }
    }
    catch {
        # Silently ignore launch errors — install succeeded even if open fails.
    }
}

function Install-WingetPackage {
    param(
        [string]$Name,
        [string]$Id,
        [int]$TaskIndex,
        [string]$Scope = "user",
        [string]$LaunchCmd = "",
        [string]$CheckCmd = "",
        [string]$MinVersion = ""
    )

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Checking existing install"
    Write-Log "Checking if $Name ($Id) is already installed..."
    Render-Dashboard -CurrentStep "Install $Name"

    if ($DryRun -and $Mac) {
        $script:Skipped.Add("$Name ($Id) [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run (mac): would check/install"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    # Check if the command is already on PATH (catches non-winget installs e.g. pre-imaged machines)
    $needsUpgrade = $false
    if (-not [string]::IsNullOrWhiteSpace($CheckCmd) -and (Test-CommandExists -CommandName $CheckCmd)) {
        # If a minimum version is required, verify the installed version is new enough
        if (-not [string]::IsNullOrWhiteSpace($MinVersion)) {
            try {
                $verOutput = (& $CheckCmd --version 2>$null).Trim()
                $verMatch  = [regex]::Match($verOutput, '\d+\.\d+\.\d+')
                if ($verMatch.Success) {
                    $installedVer = [Version]$verMatch.Value
                    $requiredVer  = [Version]$MinVersion
                    if ($installedVer -lt $requiredVer) {
                        Write-Log "$Name version $installedVer is below minimum $requiredVer - upgrading."
                        $needsUpgrade = $true
                    }
                }
            }
            catch {
                # Can't determine version; assume it's fine
            }

            if (-not $needsUpgrade) {
                Write-Log "$Name already on PATH ($CheckCmd) and meets minimum version, skipping."
                $script:Skipped.Add("$Name ($Id)")
                Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Already on PATH"
                Render-Dashboard -CurrentStep "Install $Name"
                return
            }
        }
        else {
            Write-Log "$Name already on PATH ($CheckCmd), skipping."
            $script:Skipped.Add("$Name ($Id)")
            Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Already on PATH"
            Render-Dashboard -CurrentStep "Install $Name"
            return
        }
    }

    # Skip if winget already has it installed and we don't need to upgrade
    if (-not $needsUpgrade -and (Test-WingetPackageInstalled -PackageId $Id)) {
        Write-Log "$Name already installed, skipping."
        $script:Skipped.Add("$Name ($Id)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Already installed"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    if ($DryRun) {
        $script:Skipped.Add("$Name ($Id) [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would install/upgrade"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    # When upgrading an outdated package, use 'install --force' without --scope so winget
    # matches the existing installation's scope (avoids exit code 0x8A150013 when the
    # original install was system-wide but we'd otherwise pass --scope user).
    if ($needsUpgrade) {
        Write-Log "Running: winget install --force --id $Id"
        winget install --id $Id -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity --force
    }
    else {
        $scopeArg = if ($Scope) { @("--scope", $Scope) } else { @() }
        $wingetAction = if (Test-WingetPackageInstalled -PackageId $Id) { "upgrade" } else { "install" }
        Write-Log "Running: winget $wingetAction --id $Id --scope $Scope"
        winget $wingetAction --id $Id -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity @scopeArg
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Log "$Name installed/upgraded successfully."
        $script:Installed.Add("$Name ($Id)")
        Set-TaskStatus -Index $TaskIndex -Status "installed" -Details "Installed"
        Open-AppAfterInstall -Cmd $LaunchCmd
    }
    else {
        Write-Log "$Name install failed (exit code $LASTEXITCODE)."
        $script:Failed.Add("$Name ($Id)")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Install failed (exit code $LASTEXITCODE)"
        Add-ManualStep "Install $Name manually: winget install --id $Id -e --scope user"
    }
    Render-Dashboard -CurrentStep "Install $Name"
}

function Install-NpmPackageGlobal {
    param(
        [string]$Name,
        [string]$Package,
        [string]$Cmd,
        [int]$TaskIndex,
        [string]$OpenCmd = ""
    )

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Checking install"
    Write-Log "Checking if $Name ($Package) is already installed..."
    Render-Dashboard -CurrentStep "Install $Name"

    if ($DryRun -and $Mac) {
        $script:Skipped.Add("$Name ($Package) [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run (mac): would npm install -g $Package"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    if ($DryRun) {
        $script:Skipped.Add("$Name ($Package) [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would npm install -g $Package"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    if (-not (Test-CommandExists -CommandName "npm")) {
        $script:Skipped.Add("$Name ($Package)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "npm not available - re-run bootstrap after Node.js install"
        Add-ManualStep "Install $Name after Node.js is available: npm install -g $Package"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    if (Test-CommandExists -CommandName $Cmd) {
        Write-Log "$Name already installed, skipping."
        $script:Skipped.Add("$Name ($Package)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Already installed"
        Render-Dashboard -CurrentStep "Install $Name"
        return
    }

    Write-Log "Running: npm install -g $Package"
    try {
        # Codex has a Windows-specific bug (introduced in v0.100.0) where the
        # platform optional dep (@openai/codex-win32-x64) isn't on the registry.
        # Workaround: install the current version and alias the win32 dist-tag.
        if ($Package -eq "@openai/codex") {
            $v = (& npm view @openai/codex version 2>$null).Trim()
            if ($v) {
                npm install -g "@openai/codex@$v" "@openai/codex-win32-x64@npm:@openai/codex@$v-win32-x64" --loglevel=error
            }
            else {
                npm install -g $Package --loglevel=error
            }
        }
        else {
            npm install -g $Package --loglevel=error
        }
        Write-Log "$Name installed successfully."
        $script:Installed.Add("$Name ($Package)")
        Set-TaskStatus -Index $TaskIndex -Status "installed" -Details "Installed"
        # Open-InNewTerminalTab -Cmd $OpenCmd  # disabled: new-tab not working reliably
    }
    catch {
        $script:Failed.Add("$Name ($Package)")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Install failed"
        Add-ManualStep "Install $Name manually: npm install -g $Package"
    }
    Render-Dashboard -CurrentStep "Install $Name"
}

function Install-NeovimPortable {
    param([int]$TaskIndex)

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Checking existing install"
    Write-Log "Checking for existing Neovim install..."
    Render-Dashboard -CurrentStep "Install Neovim"

    if ($DryRun -and $Mac) {
        $script:Skipped.Add("Neovim [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run (mac): would install portable Neovim"
        Render-Dashboard -CurrentStep "Install Neovim"
        return
    }

    $installDir = Join-Path $env:LOCALAPPDATA "Programs\Neovim"
    $nvimExe    = Join-Path $installDir "bin\nvim.exe"

    if (Test-Path $nvimExe) {
        $script:Skipped.Add("Neovim (already installed at $installDir)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Already installed"
        Render-Dashboard -CurrentStep "Install Neovim"
        return
    }

    if ($DryRun) {
        $script:Skipped.Add("Neovim [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would download and extract portable Neovim"
        Render-Dashboard -CurrentStep "Install Neovim"
        return
    }

    $zipUrl  = "https://github.com/neovim/neovim/releases/download/stable/nvim-win64.zip"
    $zipPath = Join-Path $env:TEMP "nvim-win64.zip"

    try {
        Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Downloading nvim-win64.zip"
        Write-Log "Downloading $zipUrl ..."
        Render-Dashboard -CurrentStep "Install Neovim"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

        Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Extracting"
        Write-Log "Extracting nvim-win64.zip to $installDir ..."
        Render-Dashboard -CurrentStep "Install Neovim"
        $extractTemp = Join-Path $env:TEMP "nvim-win64-extract"
        if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $extractTemp -Force

        # The zip contains a single top-level folder (e.g. nvim-win64); move its contents to installDir
        $inner = Get-ChildItem $extractTemp | Select-Object -First 1
        if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $installDir -Parent)
        Move-Item $inner.FullName $installDir

        # Add bin dir to user PATH if not already present
        $binDir     = Join-Path $installDir "bin"
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentPath -notlike "*$binDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binDir", "User")
            $env:Path += ";$binDir"
        }

        Write-Log "Neovim installed to $installDir and added to PATH."
        $script:Installed.Add("Neovim (portable, $installDir)")
        Set-TaskStatus -Index $TaskIndex -Status "installed" -Details "Installed to $installDir"

        # Disabled: opening nvim in a new terminal tab not working reliably
        # try {
        #     if (Test-CommandExists "wt") {
        #         Start-Process wt -ArgumentList "new-tab", "--", "pwsh", "-NoExit", "-Command", "`"& '$nvimExe'`""
        #     }
        #     else {
        #         Start-Process powershell -ArgumentList "-NoExit", "-Command", "& '$nvimExe'"
        #     }
        # }
        # catch {
        #     # Silently ignore — install succeeded even if open fails.
        # }
    }
    catch {
        $script:Failed.Add("Neovim")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Download/extract failed: $($_.Exception.Message)"
        Add-ManualStep "Neovim install failed. Download nvim-win64.zip from https://github.com/neovim/neovim/releases/latest, extract to $installDir, and add $installDir\bin to your user PATH."
    }
    finally {
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Render-Dashboard -CurrentStep "Install Neovim"
}

function Repair-PathEntries {
    param([int]$TaskIndex)

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Checking PATH entries"
    Write-Log "Checking PATH entries for installed tools..."
    Render-Dashboard -CurrentStep "Repair PATH"

    if ($DryRun) {
        $script:Skipped.Add("PATH repair [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would check and repair PATH"
        Render-Dashboard -CurrentStep "Repair PATH"
        return
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $added = New-Object System.Collections.Generic.List[string]

    # Build probe list from packages that declare pathProbes
    $probeTargets = @()
    foreach ($pkg in $packages) {
        if (-not $pkg.PSObject.Properties["checkCmd"])   { continue }
        if (-not $pkg.PSObject.Properties["pathProbes"]) { continue }
        $probeTargets += [PSCustomObject]@{
            Name       = $pkg.name
            CheckCmd   = $pkg.checkCmd
            PathProbes = $pkg.pathProbes
        }
    }

    # Neovim is not in packages.json so add it directly
    $probeTargets += [PSCustomObject]@{
        Name       = "Neovim"
        CheckCmd   = "nvim"
        PathProbes = @("%LOCALAPPDATA%\Programs\Neovim\bin")
    }

    foreach ($target in $probeTargets) {
        if (Test-CommandExists -CommandName $target.CheckCmd) {
            Write-Log "$($target.Name) ($($target.CheckCmd)) already on PATH, skipping."
            continue
        }

        $resolved = $null
        foreach ($probe in $target.PathProbes) {
            $expanded = [Environment]::ExpandEnvironmentVariables($probe)
            try {
                $match = Get-Item $expanded -ErrorAction Stop | Select-Object -First 1
                if ($match) { $resolved = $match.FullName; break }
            }
            catch { }
        }

        if ($resolved) {
            if ($userPath -notlike "*$resolved*") {
                $userPath += ";$resolved"
                $env:Path += ";$resolved"
                $added.Add("$($target.Name): $resolved")
                Write-Log "Added to PATH: $resolved (for $($target.Name))"
            }
        }
        else {
            Write-Log "$($target.Name) not found in any probe path - may need manual PATH fix."
            Add-ManualStep "$($target.Name) ($($target.CheckCmd)) is not on PATH and could not be located automatically. Add its bin directory to your user PATH manually."
        }
    }

    if ($added.Count -gt 0) {
        [Environment]::SetEnvironmentVariable("Path", $userPath, "User")
        $script:Installed.Add("PATH repairs ($($added.Count)): $($added -join '; ')")
        Set-TaskStatus -Index $TaskIndex -Status "completed" -Details "$($added.Count) path(s) added"
    }
    else {
        $script:Skipped.Add("PATH repair (all tools already on PATH)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "All tools already on PATH"
    }
    Render-Dashboard -CurrentStep "Repair PATH"
}

function Set-TaskbarPins {
    param([int]$TaskIndex)

    $pinItems = @("Vivaldi", "Windows Terminal")
    $pinLabel = $pinItems -join ", "

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Pinning: $pinLabel"
    Write-Log "Applying taskbar pins: $pinLabel"
    Render-Dashboard -CurrentStep "Pin taskbar items"

    if ($DryRun) {
        $script:Skipped.Add("Taskbar pins [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would pin $pinLabel"
        Render-Dashboard -CurrentStep "Pin taskbar items"
        return
    }

    try {
        $xmlDir  = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Shell"
        $xmlPath = Join-Path $xmlDir "LayoutModification.xml"

        if (-not (Test-Path $xmlDir)) {
            New-Item -ItemType Directory -Path $xmlDir -Force | Out-Null
        }

        $xml = @'
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection>
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationLinkPath="%APPDATA%\Microsoft\Windows\Start Menu\Programs\Vivaldi\Vivaldi.lnk"/>
        <taskbar:DesktopApp DesktopApplicationLinkPath="%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe"/>
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
'@

        Set-Content -Path $xmlPath -Value $xml -Encoding UTF8
        Write-Log "LayoutModification.xml written to $xmlPath"
        $script:Installed.Add("Taskbar pins ($pinLabel)")
        Set-TaskStatus -Index $TaskIndex -Status "completed" -Details "Log off and back on to apply"
        Add-ManualStep "Taskbar pins written. Log off and log back in (or run: Stop-Process -Name explorer -Force) to see Vivaldi and Windows Terminal pinned."
    }
    catch {
        $script:Failed.Add("Taskbar pins")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Failed: $($_.Exception.Message)"
        Add-ManualStep "Taskbar pinning failed: $($_.Exception.Message)"
    }
    Render-Dashboard -CurrentStep "Pin taskbar items"
}

function Install-NerdFont {
    param([int]$TaskIndex)

    Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Checking NerdFont install"
    Write-Log "Checking for JetBrains Mono Nerd Font..."
    Render-Dashboard -CurrentStep "Install NerdFont"

    if ($DryRun -and $Mac) {
        $script:Skipped.Add("JetBrains Mono Nerd Font [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run (mac): install manually"
        Add-ManualStep "Mac: Install NerdFont for LazyVim: brew install --cask font-jetbrains-mono-nerd-font  Then set your terminal font to 'JetBrainsMono Nerd Font Mono' (iTerm2: Preferences > Profiles > Text > Font; Kitty/WezTerm: set font_family in config)."
        Render-Dashboard -CurrentStep "Install NerdFont"
        return
    }

    $fontDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $sampleFont = Join-Path $fontDir "JetBrainsMonoNerdFont-Regular.ttf"

    if (Test-Path $sampleFont) {
        $script:Skipped.Add("JetBrains Mono Nerd Font (already installed)")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Already installed"
        Render-Dashboard -CurrentStep "Install NerdFont"
        return
    }

    if ($DryRun) {
        $script:Skipped.Add("JetBrains Mono Nerd Font [dry-run]")
        Set-TaskStatus -Index $TaskIndex -Status "skipped" -Details "Dry run: would download and install per-user"
        Render-Dashboard -CurrentStep "Install NerdFont"
        return
    }

    $zipUrl     = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    $zipPath    = Join-Path $env:TEMP "JetBrainsMono-NerdFont.zip"
    $extractPath = Join-Path $env:TEMP "JetBrainsMono-NerdFont-extract"

    try {
        Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Downloading JetBrains Mono Nerd Font"
        Write-Log "Downloading $zipUrl ..."
        Render-Dashboard -CurrentStep "Install NerdFont"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

        Set-TaskStatus -Index $TaskIndex -Status "running" -Details "Extracting and installing fonts"
        Write-Log "Extracting fonts to $fontDir ..."
        Render-Dashboard -CurrentStep "Install NerdFont"
        if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        if (-not (Test-Path $fontDir)) {
            New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
        }

        # Load Win32 font API for immediate activation (no logoff required)
        if (-not ([System.Management.Automation.PSTypeName]'FontInstaller').Type) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class FontInstaller {
    [DllImport("gdi32.dll", CharSet = CharSet.Auto)]
    public static extern int AddFontResource(string lpFileName);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xffff);
    public const uint WM_FONTCHANGE = 0x001D;
}
'@
        }

        $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        $ttfFiles = Get-ChildItem -Path $extractPath -Filter "*.ttf" -Recurse
        $count = 0
        foreach ($ttf in $ttfFiles) {
            $dest = Join-Path $fontDir $ttf.Name
            Copy-Item -Path $ttf.FullName -Destination $dest -Force
            $regName = [System.IO.Path]::GetFileNameWithoutExtension($ttf.Name) + " (TrueType)"
            Set-ItemProperty -Path $regPath -Name $regName -Value $ttf.Name -Force
            [void][FontInstaller]::AddFontResource($dest)
            $count++
        }
        [void][FontInstaller]::SendMessage([FontInstaller]::HWND_BROADCAST, [FontInstaller]::WM_FONTCHANGE, [IntPtr]::Zero, [IntPtr]::Zero)

        Write-Log "Installed $count NerdFont files to $fontDir."
        $script:Installed.Add("JetBrains Mono Nerd Font ($count files, per-user)")
        Set-TaskStatus -Index $TaskIndex -Status "installed" -Details "$count font files installed"
        Add-ManualStep "NerdFont installed. Set your terminal font to 'JetBrainsMono Nerd Font Mono' (Windows Terminal: Settings > Profiles > Appearance > Font face)."
    }
    catch {
        $script:Failed.Add("JetBrains Mono Nerd Font")
        Set-TaskStatus -Index $TaskIndex -Status "failed" -Details "Install failed: $($_.Exception.Message)"
        Add-ManualStep "NerdFont install failed. Download JetBrainsMono.zip from https://github.com/ryanoasis/nerd-fonts/releases/latest, extract, and right-click each .ttf to install (choose 'Install' for per-user, no admin needed)."
    }
    finally {
        if (Test-Path $zipPath)     { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Render-Dashboard -CurrentStep "Install NerdFont"
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
    Write-Log "Cloning dotfiles from $RepoUrl ..."
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

        Write-Log "Running: git clone --depth 1 $RepoUrl"
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

        Write-Log "Neovim config copied to $target."
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

$npmPackageFile = Join-Path $PSScriptRoot "config/npm-packages.json"
if (-not (Test-Path $npmPackageFile)) {
    throw "Missing npm package config: $npmPackageFile"
}

$packages = Get-Content -Raw -Path $packageFile | ConvertFrom-Json
$npmPackages = Get-Content -Raw -Path $npmPackageFile | ConvertFrom-Json

$preflightTask = Add-Task -Title "Preflight checks"
$packageTaskMap = @{}
foreach ($pkg in $packages) {
    $packageTaskMap[$pkg.id] = Add-Task -Title ("Install {0}" -f $pkg.name)
}
$npmPackageTaskMap = @{}
foreach ($npkg in $npmPackages) {
    $npmPackageTaskMap[$npkg.package] = Add-Task -Title ("Install {0}" -f $npkg.name)
}
$nvimInstallTask = Add-Task -Title "Install Neovim"
$nerdFontTask = Add-Task -Title "Install JetBrains Mono Nerd Font"
$nvimTask = Add-Task -Title "Setup Neovim config"
$repairPathTask = Add-Task -Title "Repair PATH entries"
$taskbarPinTask = Add-Task -Title "Pin taskbar items: Vivaldi, Windows Terminal"

Render-Dashboard -CurrentStep "Starting bootstrap"

Set-TaskStatus -Index $preflightTask -Status "running" -Details "Checking execution policy"
Write-Log "Checking PowerShell execution policy..."
Render-Dashboard -CurrentStep "Preflight checks"

if (-not $DryRun) {
    $ep = Get-ExecutionPolicy -Scope CurrentUser
    if ($ep -eq "Undefined" -or $ep -eq "Restricted") {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Log "Set execution policy to RemoteSigned for current user."
    }
}

Set-TaskStatus -Index $preflightTask -Status "running" -Details "Checking winget availability"
Write-Log "Checking winget availability..."
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

    Write-Log "winget is available."
    Set-TaskStatus -Index $preflightTask -Status "completed" -Details "winget is ready"
}

Render-Dashboard -CurrentStep "Preflight checks"

foreach ($pkg in $packages) {
    $scope      = if ($pkg.PSObject.Properties["scope"])      { $pkg.scope }      else { "user" }
    $launchCmd  = if ($pkg.PSObject.Properties["launchCmd"])  { $pkg.launchCmd }  else { "" }
    $checkCmd   = if ($pkg.PSObject.Properties["checkCmd"])   { $pkg.checkCmd }   else { "" }
    $minVersion = if ($pkg.PSObject.Properties["minVersion"]) { $pkg.minVersion } else { "" }
    Install-WingetPackage -Name $pkg.name -Id $pkg.id -TaskIndex $packageTaskMap[$pkg.id] -Scope $scope -LaunchCmd $launchCmd -CheckCmd $checkCmd -MinVersion $minVersion
}

Install-NeovimPortable -TaskIndex $nvimInstallTask

Install-NerdFont -TaskIndex $nerdFontTask

# Refresh PATH so Node.js installed by winget is available in this session
Write-Log "Refreshing PATH from registry..."
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# Fallback: if npm still isn't in PATH (winget MSI may write PATH after its process exits),
# probe common Node.js install locations and add the first one found.
if (-not (Test-CommandExists "npm")) {
    $nodeProbePaths = @(
        "$env:LOCALAPPDATA\Programs\nodejs",
        "$env:ProgramFiles\nodejs",
        "${env:ProgramFiles(x86)}\nodejs"
    )
    foreach ($p in $nodeProbePaths) {
        if (Test-Path (Join-Path $p "npm.cmd")) {
            $env:Path += ";$p"
            break
        }
    }
}

foreach ($npkg in $npmPackages) {
    $openCmd = if ($npkg.PSObject.Properties["openCmd"]) { $npkg.openCmd } else { "" }
    Install-NpmPackageGlobal -Name $npkg.name -Package $npkg.package -Cmd $npkg.cmd -TaskIndex $npmPackageTaskMap[$npkg.package] -OpenCmd $openCmd
}

# Persist npm global bin to user PATH so new sessions find npm-installed CLIs without manual steps
if (-not $DryRun -and (Test-CommandExists "npm")) {
    $npmBin = (& npm prefix -g 2>$null).Trim()
    if ($npmBin) {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notlike "*$npmBin*") {
            [Environment]::SetEnvironmentVariable("Path", "$userPath;$npmBin", "User")
            $env:Path += ";$npmBin"
            Write-Log "Added npm global bin to user PATH: $npmBin"
        }
    }
}

Apply-NvimConfigFromDotfiles -RepoUrl $DotfilesRepoUrl -SubPath $DotfilesSubPath -TaskIndex $nvimTask

Repair-PathEntries -TaskIndex $repairPathTask

Set-TaskbarPins -TaskIndex $taskbarPinTask

Add-ManualStep "All winget installs run as your user (no admin needed). If one fails anyway, IT may have blocked that specific package - ask them to allow it."
Add-ManualStep "Claude Code, Codex CLI, and Gemini CLI require auth - after install, open a new PowerShell window and run 'claude', 'codex', or 'gemini' to sign in interactively."
if ($DryRun -and $Mac) {
    Add-ManualStep "Mac dry run mode ran. No system changes were made."
}

Write-FinalReport
