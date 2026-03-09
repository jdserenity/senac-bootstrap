# School PC Bootstrap (Windows)

Automate setup on shared school computers:
- install apps with `winget` (no admin required)
- install AI CLIs inside WSL2/Ubuntu via npm
- apply your Neovim config from your dotfiles repo
- show a live progress dashboard (percent, current step, pending/complete tasks)
- print manual steps for anything that cannot or should not be automated

## Quick start

Open **PowerShell** (no admin needed):

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

Bootstrap runs in two passes when WSL is involved:

1. **First run** — installs Vivaldi, Neovim, WSL, and Ubuntu 24.04 via winget. WSL steps are skipped with a message if Ubuntu hasn't been initialized yet.
2. **Initialize Ubuntu** — open "Ubuntu 24.04" from the Start Menu, pick a username and password, then close it.
3. **Second run** — re-run `./bootstrap.ps1`. It detects Ubuntu is ready and installs Node.js (via nvm), Claude Code, Codex CLI, and Gemini CLI inside WSL.

## What this installs

### Windows apps (`config/packages.json`, via winget `--scope user`)

| App | Winget ID |
|---|---|
| Vivaldi | `Vivaldi.Vivaldi` |
| Neovim | `Neovim.Neovim` |
| WSL | `Microsoft.WSL` |
| Ubuntu 24.04 | `Canonical.Ubuntu.2404` |

### AI CLIs inside WSL/Ubuntu (`config/wsl-npm-packages.json`, via npm)

| Tool | npm package |
|---|---|
| Claude Code CLI | `@anthropic-ai/claude-code` |
| Codex CLI | `@openai/codex` |
| Gemini CLI | `@google/gemini-cli` |

Node.js is installed inside WSL via nvm (no system-wide install needed).

You can add/remove packages by editing the relevant config file.

## Admin / school policy notes

All winget installs run with `--scope user` — no admin required. The one exception is the `VirtualMachinePlatform` Windows Feature that WSL depends on. On most school Windows 11 machines this is already enabled. If `winget install Microsoft.WSL` fails, ask IT to enable it once — it is a one-time unlock.

## Neovim config setup (default enabled)

By default, bootstrap clones:
- `https://github.com/jdserenity/nvim-lazyvim-config.git`

Then copies config files into `%LOCALAPPDATA%\nvim` (if that folder does not already exist).

Override repo and subpath:

```powershell
./bootstrap.ps1 -DotfilesRepoUrl https://github.com/<you>/<dotfiles>.git -DotfilesSubPath nvim
```

Skip Neovim dotfiles sync:

```powershell
./bootstrap.ps1 -DotfilesRepoUrl ""
```

## Reset (for debugging)

To uninstall everything and start fresh:

```powershell
./reset.ps1 -Force
```

Without `-Force`, it just shows what it would do. This unregisters the Ubuntu WSL distro (deletes all WSL data), uninstalls all winget packages, and removes the Neovim config directory.

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

## Running from macOS/Ghostty

- Ghostty is just a terminal emulator; this script still requires **PowerShell (`pwsh`)**.
- If `pwsh` is installed, run:

```bash
pwsh -NoProfile -File ./bootstrap.ps1 -DryRun -Mac
```

## Dashboard

Default behavior is a live dashboard with:
- overall progress bar
- current step
- installed/skipped/failed counts
- per-step status

Disable dashboard (plain output):

```powershell
./bootstrap.ps1 -NoDashboard
```

## Notes

- AI CLI auth (Claude Code, Codex, Gemini) is intentionally manual — after install, open Ubuntu and run `claude`, `codex`, or `gemini` to sign in.
- Browser account sign-in (Vivaldi sync, MFA) is intentionally manual.
- If a winget install is blocked by school policy, the script reports manual instructions and continues.
