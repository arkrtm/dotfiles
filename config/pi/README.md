# Pi / herdr config

Config for the [Pi coding agent](https://pi.dev) and the [herdr](https://herdr.dev)
terminal multiplexer. `install.sh` symlinks the files below; the binaries and Pi
packages are installed separately (steps at the bottom).

## What `install.sh` links

| repo | → | $HOME |
|---|---|---|
| `config/agents/AGENTS.md` | | `.pi/agent/AGENTS.md` (also `.claude/CLAUDE.md`, `.codex/AGENTS.md`) — the one global instruction file shared by CC, Pi and Codex |
| `config/pi/extensions/format-json-yaml.ts` | | `.pi/agent/extensions/…` — format JSON (jq) / YAML (yamlfix) on write/edit |
| `config/herdr/config.toml` | | `.config/herdr/config.toml` — keybindings ported from tmux (prefix `C-g`) |
| `config/agents/skills/issue`, `wrap-up` | | `.agents/skills/…` — the Linear skills, read by Pi and Codex (also linked into `.claude/skills`) |

`config/pi/settings.sample.json` is a **reference** (default model/provider, powerline,
the package list) — not symlinked, because Pi rewrites `~/.pi/agent/settings.json` at
runtime (deviceId, installed packages, powerline preset).

Not versioned (machine-local / secret): `~/.pi/agent/auth.json` (API keys / OAuth),
the `~/.tinymemory` memory store, and all Pi runtime dirs (sessions, npm, caches).

## Bootstrap (binaries + packages)

`tinymemory` is already handled by `config/mise/config.toml` + `install.sh` (mise install
+ `~/.local/bin` shim) — nothing to do here.

Run the sudo-less agent bootstrap (Pi + packages + yamlfix + Codex memory hook). It installs
only into `$HOME` (npm global via the fnm prefix, `~/.pi`, `~/.local`) — no sudo, no system
packages. Safe on a no-sudo dev box like geotwin, after `install.sh`:

```sh
sh config/pi/setup.sh
```

herdr is optional and kept separate (its installer is an unpinned remote script); install it
by hand when wanted — still sudo-less, into `~/.local/bin`:

```sh
curl -fsSL https://herdr.dev/install.sh | sh   # then: herdr integration install pi
```

## Notes

- Export `POWERLINE_NERD_FONTS=1` in your shell — tmux/WSL terminals are not auto-detected,
  so the powerline footer needs it to render Nerd Font glyphs.
- Mobile control (when needed): use [paseo](https://paseo.sh) — multi-agent, with an
  E2E relay / LAN / own-tunnel. (remote-pi was dropped: its public relay is dead and it is non-E2E.)
- `pi-herdsman` is omitted — `pi-subagents` already covers parallel, worktree-isolated work;
  add herdsman only if you specifically want the herdr-pane fleet view.
- `pi-tinymemory` is loaded with `"skills": []` (settings.sample.json) — `tinymemory init codex`
  already installs remember/recall/dream into `~/.agents/skills` (shared by Pi and Codex), so
  disabling the package's bundled copies avoids a skill-name collision. The package's extension
  (session-start auto-load) still loads.
