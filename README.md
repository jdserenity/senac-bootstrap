# School PC Bootstrap (Windows)

Automate setup on shared school computers:
- install apps with `winget`
- apply your Neovim config from your dotfiles repo
- show a live progress dashboard (percent, current step, pending/complete tasks)
- print manual steps for anything that cannot or should not be automated

## Quick start

Open **PowerShell** (normal user is fine unless your school policy requires admin):

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
./bootstrap.ps1
```

## Recommended school workflow

On a fresh SENAC Windows computer:

```powershell
git clone https://github.com/jdserenity/senac-bootstrap.git
cd senac-bootstrap
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
./bootstrap.ps1
```

## What this installs by default

Configured in `config/packages.json`:
- Arc Browser (`TheBrowserCompany.Arc`)
- Neovim (`Neovim.Neovim`)
- Git (`Git.Git`)
- Claude Code CLI (`Anthropic.ClaudeCode`)
- Codex CLI (`OpenAI.Codex`)

You can add/remove packages anytime by editing that file.

## Neovim config setup (default enabled)

By default, bootstrap clones:
- `https://github.com/jdserenity/nvim-lazyvim-config.git`

Then it copies config files into `%LOCALAPPDATA%\\nvim` (if that folder does not already exist).

Override repo and subpath:

```powershell
./bootstrap.ps1 -DotfilesRepoUrl https://github.com/<you>/<dotfiles>.git -DotfilesSubPath nvim
```

Skip Neovim dotfiles sync:

```powershell
./bootstrap.ps1 -DotfilesRepoUrl ""
```

## Dry run

See what would happen without installing anything:

```powershell
./bootstrap.ps1 -DryRun
```

Dry run preview on macOS (bypasses `winget` preflight):

```powershell
./bootstrap.ps1 -DryRun -Mac
```

`-Mac` is only valid together with `-DryRun`.

## DryRun modes

- `-DryRun`: no installs/writes, but still performs normal Windows preflight checks (`winget`).
- `-DryRun -Mac`: no installs/writes, and skips `winget` preflight for Mac preview usage.

## Running from macOS/Ghostty

- Ghostty is just a terminal emulator; this script still requires **PowerShell (`pwsh`)** to run.
- If `pwsh` is not installed, the script will not run.
- If `pwsh` is installed, run:

```bash
pwsh -NoProfile -File ./bootstrap.ps1 -DryRun -Mac
```

## Dashboard

Default behavior is a live dashboard page with:
- overall progress bar
- current step
- installed/skipped/failed counts
- per-step status for everything still pending or done

Disable dashboard (plain output):

```powershell
./bootstrap.ps1 -NoDashboard
```

## Notes

- Browser account sign-in (Chrome/Arc sync, MFA, SSO) is intentionally manual.
- If `winget` is blocked by school policy, the script reports manual instructions.
- If you later want languages/toolchains (Node, Python, Go, Rust, etc.), add package IDs in `config/packages.json`.
