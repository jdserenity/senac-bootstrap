# senac-bootstrap

PowerShell bootstrap for school Windows PCs. No admin required.

## Quick start

```powershell
git clone https://github.com/jdserenity/senac-bootstrap.git
cd senac-bootstrap
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
./bootstrap.ps1
```

## What gets installed

**Windows apps** (`config/packages.json`, via winget `--scope user`)

| App | Winget ID |
|---|---|
| Vivaldi | `Vivaldi.Vivaldi` |
| Node.js LTS | `OpenJS.NodeJS.LTS` |
| VS Code | `Microsoft.VisualStudioCode` |

**Neovim** — downloaded as a portable zip from GitHub releases, extracted to `%LOCALAPPDATA%\Programs\Neovim`, and added to your user PATH.

**JetBrains Mono Nerd Font** — downloaded from the nerd-fonts GitHub releases and installed per-user to `%LOCALAPPDATA%\Microsoft\Windows\Fonts` (no admin needed). Required for LazyVim icons and glyphs to render correctly. After install, set your terminal font to `JetBrainsMono Nerd Font Mono` (Windows Terminal: Settings > Profiles > Appearance > Font face).

**AI CLIs** (`config/npm-packages.json`, via `npm install -g`)

| Tool | Package |
|---|---|
| Claude Code | `@anthropic-ai/claude-code` |
| Codex CLI | `@openai/codex` |
| Gemini CLI | `@google/gemini-cli` |

**Neovim config** — cloned from `jdserenity/nvim-lazyvim-config` and copied to `%LOCALAPPDATA%\nvim` (skipped if the folder already exists).

To use a different dotfiles repo or subpath:

```powershell
./bootstrap.ps1 -DotfilesRepoUrl https://github.com/<you>/<repo>.git -DotfilesSubPath nvim
```

To skip Neovim config sync:

```powershell
./bootstrap.ps1 -DotfilesRepoUrl ""
```

## Dry run

```powershell
./bootstrap.ps1 -DryRun
```

On macOS (bypasses the winget preflight check):

```powershell
./bootstrap.ps1 -DryRun -Mac
```

## Reset

Uninstalls everything and lets you start clean:

```powershell
./reset.ps1 -Force
```

Without `-Force` it just prints what it would do.

## Dashboard

Bootstrap shows a live progress dashboard by default — progress bar, per-step status, and a recent activity log. To disable it (plain output):

```powershell
./bootstrap.ps1 -NoDashboard
```

## Notes

- All winget installs use `--scope user` — no admin needed. If a package is blocked by school policy, the script logs it and continues, then lists manual steps at the end.
- AI CLI auth is intentionally manual. After install, open a new PowerShell window and run `claude`, `codex`, or `gemini` to sign in.
- Launch Neovim once (`nvim`) after first run to let LazyVim install plugins.
- **Mac users:** The script is Windows-only. For the NerdFont, run: `brew install --cask font-jetbrains-mono-nerd-font`, then set your terminal font to `JetBrainsMono Nerd Font Mono`.
