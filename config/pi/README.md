# Pi / herdr config

Config for the [Pi coding agent](https://pi.dev) and the [herdr](https://herdr.dev)
terminal multiplexer. `install.sh` symlinks the files below; the binaries and Pi
packages are installed separately (steps at the bottom).

## What `install.sh` links

| repo | → | $HOME |
|---|---|---|
| `config/pi/AGENTS.md` | | `.pi/agent/AGENTS.md` — always-on engineering principles |
| `config/pi/extensions/format-json-yaml.ts` | | `.pi/agent/extensions/…` — format JSON (jq) / YAML (yamlfix) on write/edit |
| `config/herdr/config.toml` | | `.config/herdr/config.toml` — keybindings ported from tmux (prefix `C-g`) |
| `config/claude/skills/issue`, `wrap-up` | | `.pi/agent/skills/…` — the Linear skills, shared with Pi (also linked into `.claude/skills`) |

`config/pi/settings.sample.json` is a **reference** (default model/provider, powerline,
the package list) — not symlinked, because Pi rewrites `~/.pi/agent/settings.json` at
runtime (deviceId, installed packages, powerline preset).

Not versioned (machine-local / secret): `~/.pi/agent/auth.json` (API keys / OAuth),
`~/.pi/remote/` (remote-pi pairing keys), the `~/.tinymemory` memory store, and all Pi
runtime dirs (sessions, npm, caches).

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
- remote-pi pairing: run `/remote-pi` in Pi and scan the QR with the mobile app.
- `remote-pi` and `pi-herdsman` both register a `list_peers` tool and cannot load together;
  this setup keeps `remote-pi` + `pi-subagents` (mobile + parallel) and omits `pi-herdsman`.
- `pi-tinymemory` is loaded with `"skills": []` (settings.sample.json) — `tinymemory init codex`
  already installs remember/recall/dream into `~/.agents/skills` (shared by Pi and Codex), so
  disabling the package's bundled copies avoids a skill-name collision. The package's extension
  (session-start auto-load) still loads.
