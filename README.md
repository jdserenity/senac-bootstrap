# School PC Bootstrap (Windows)

Automate setup on shared school computers:
- install apps with `winget`
- optionally apply your Neovim config from a dotfiles repo
- print manual steps for anything that cannot or should not be automated

## Quick start

Open **PowerShell** (normal user is fine unless your school policy requires admin):

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
./bootstrap.ps1
```

## What this installs by default

Configured in `config/packages.json`:
- Arc Browser (`TheBrowserCompany.Arc`)
- Google Chrome (`Google.Chrome`)
- Neovim (`Neovim.Neovim`)
- Git (`Git.Git`)
- Claude Code CLI (`Anthropic.ClaudeCode`)
- Codex CLI (`OpenAI.Codex`)

You can add/remove packages anytime by editing that file.

## Optional dotfiles setup

To copy a Neovim config from your dotfiles repo into `%LOCALAPPDATA%\\nvim`:

```powershell
./bootstrap.ps1 -DotfilesRepoUrl https://github.com/<you>/<dotfiles>.git -DotfilesSubPath nvim
```

## Dry run

See what would happen without installing anything:

```powershell
./bootstrap.ps1 -DryRun
```

## Notes

- Browser account sign-in (Chrome/Arc sync, MFA, SSO) is intentionally manual.
- If `winget` is blocked by school policy, the script reports manual instructions.
- If you later want languages/toolchains (Node, Python, Go, Rust, etc.), add package IDs in `config/packages.json`.
