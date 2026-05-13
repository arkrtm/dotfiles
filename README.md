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
| 2 | [`rtk`](https://github.com/rtk-ai/rtk) — Claude Code context compressor (shell tool output filter) | `brew install rtk` (macOS) or upstream `install.sh` |
| 3 | Ensure `~/.claude/` and `~/.claude/skills/` exist | — |
| 4 | Symlink `claude/settings.json` → `~/.claude/settings.json` and `claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (global user instructions) | this repo |
| 5 | [`andrej-karpathy-skills`](https://github.com/forrestchang/andrej-karpathy-skills) — install the `karpathy-guidelines` skill into `~/.claude/skills/`, plus copy the repo's `CLAUDE.md` to `~/.claude/karpathy-CLAUDE.md` (auto-imported by our `CLAUDE.md` via `@`-reference) | git clone |
| 6 | [`claude-mem`](https://github.com/thedotmack/claude-mem) — persistent memory for Claude Code | `npx -y claude-mem install` (requires Node) |
| 7 | `rtk init -g` — register the Claude Code bash hook + write `~/.claude/RTK.md` | rtk |

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
