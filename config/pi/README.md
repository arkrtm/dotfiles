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

```sh
# Pi itself (npm global; Node comes from fnm via install.sh)
npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Pi packages (keep in sync with settings.sample.json "packages")
for p in pi-subagents pi-web-access billion-context @narumitw/pi-usage \
         @juicesharp/rpiv-todo @juicesharp/rpiv-ask-user-question cc-safety-net \
         pi-tinymemory pi-lens bigpowers pi-cache-optimizer \
         @dietrichgebert/ponytail @micka33/pi-karpathy-skill pi-powerline-footer remote-pi; do
  pi install "npm:$p"
done

uv tool install yamlfix            # YAML formatter used by the format extension
tinymemory init codex              # shared memory hook for Codex (Claude Code uses the tinymemory plugin)

# herdr (terminal multiplexer) + its Pi state integration
curl -fsSL https://herdr.dev/install.sh | sh
herdr integration install pi
```

## Notes

- Export `POWERLINE_NERD_FONTS=1` in your shell — tmux/WSL terminals are not auto-detected,
  so the powerline footer needs it to render Nerd Font glyphs.
- remote-pi pairing: run `/remote-pi` in Pi and scan the QR with the mobile app.
- `remote-pi` and `pi-herdsman` both register a `list_peers` tool and cannot load together;
  this setup keeps `remote-pi` + `pi-subagents` (mobile + parallel) and omits `pi-herdsman`.
