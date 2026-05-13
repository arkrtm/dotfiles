# dotfiles

Personal dotfiles. Bootstraps a fresh macOS or Linux machine with my Claude Code setup and tooling.

## Quick start

```sh
git clone https://github.com/arkrtm/dotfiles ~/dotfiles
cd ~/dotfiles
./install.sh
```

Re-runnable any time; each step is idempotent.

## Updating an existing machine

| Changed what? | Run |
| --- | --- |
| Only config files (`CLAUDE.md`, `settings.json`, …) | `git -C ~/dotfiles pull` — symlinks update immediately |
| `install.sh` added a new tool | `git -C ~/dotfiles pull && ~/dotfiles/install.sh` |
| Want to bump installed tools to their latest versions | `~/dotfiles/update.sh` (pulls repo, self-updates each tool, re-runs `install.sh`) |

## What `install.sh` does

| Step | Tool | Source |
| --- | --- | --- |
| 1 | [`uv`](https://github.com/astral-sh/uv) — Python package/project manager | `astral.sh/uv/install.sh` |
| 2 | [`rtk`](https://github.com/rtk-ai/rtk) — Claude Code context compressor | `brew install rtk` (macOS) or upstream `install.sh` |
| 3 | Symlink `claude/settings.json` → `~/.claude/settings.json` and `claude/CLAUDE.md` → `~/.claude/CLAUDE.md` | this repo |
| 4 | Fetch [`andrej-karpathy-skills`](https://github.com/forrestchang/andrej-karpathy-skills) root `CLAUDE.md` → `~/.claude/karpathy-CLAUDE.md` (auto-imported via `@`-reference) | curl |
| 5 | `rtk init -g` — register the Claude Code bash hook + write `~/.claude/RTK.md` | rtk |

Plus, on next Claude Code launch, two plugins auto-install from
`enabledPlugins` declared in `settings.json`:
- `andrej-karpathy-skills@karpathy-skills` (skill)
- `claude-mem@thedotmack` (memory hooks + MCP)

## Layout

```
dotfiles/
├── install.sh            # idempotent bootstrap (fresh install)
├── update.sh             # pull + self-update every managed tool
├── claude/
│   ├── settings.json     # symlinked to ~/.claude/settings.json
│   └── CLAUDE.md         # symlinked to ~/.claude/CLAUDE.md (global user instructions)
└── README.md
```

## Notes

- `claude-mem` and `rtk init` both write to `~/.claude/settings.json`. Because that file is a symlink into this repo, their edits land here automatically — review and commit them as needed.
- On Linux without Node, claude-mem is skipped. Install Node (e.g. via `mise` or `nvm`) and re-run `./install.sh`.
- Restart your shell after running so `PATH` updates (uv, rtk) and the rtk bash hook take effect.
