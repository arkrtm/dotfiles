#!/bin/sh
# Pi / herdr agent layer — sudo-less bootstrap (user space only).
# Run AFTER install.sh (which installs node via fnm and tinymemory/uv via mise, all without sudo).
# Everything here lands under $HOME: npm global uses the fnm-managed prefix, pi packages go to
# ~/.pi, uv tools and the herdr binary go to ~/.local. No sudo, no system packages.
#   sh config/pi/setup.sh
set -eu

need() { command -v "$1" >/dev/null 2>&1; }

need npm || { echo "npm not found — run install.sh first (node comes from fnm)."; exit 1; }

# Pi itself (npm global into the fnm prefix = user space; --ignore-scripts for supply-chain safety)
need pi || npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Pi packages (keep in sync with settings.sample.json "packages")
for p in \
  pi-subagents pi-web-access billion-context @narumitw/pi-usage \
  @juicesharp/rpiv-todo @juicesharp/rpiv-ask-user-question cc-safety-net \
  pi-tinymemory pi-lens bigpowers pi-cache-optimizer \
  @dietrichgebert/ponytail @micka33/pi-karpathy-skill pi-powerline-footer remote-pi; do
  pi install "npm:$p"
done

# YAML formatter used by the format-json-yaml extension (uv comes from mise)
need yamlfix || { need uv && uv tool install yamlfix || echo "skip yamlfix (uv missing — run install.sh)"; }

# tinymemory Codex integration (the binary itself is installed by install.sh via mise)
need tinymemory && tinymemory init codex || true

# herdr is optional on a headless dev box. Its installer is user-space (~/.local/bin) but is an
# unpinned remote script, so it is left as a manual, opt-in step rather than embedded here:
#   curl -fsSL https://herdr.dev/install.sh | sh
need herdr && herdr integration install pi || echo "herdr not installed (optional). See config/pi/README.md."

echo "pi setup done (sudo-less)."
