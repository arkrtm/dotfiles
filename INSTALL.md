# install.sh

`install.sh` がやること:

1. `install.sh` の LINKS のファイル（説明は各ディレクトリの README）をシンボリックリンクで配置し、ponytail の band（プロンプトの上の行）を既定で隠す（`~/.claude/.ponytail-band` が無ければ `off` を書く。出し続ける端末は中身を `on` にする）
2. `~/.ssh` を 700、`ssh/config` を 600 にする（ssh は他ユーザーが書ける設定ファイルを拒むため）
3. zsh プラグイン 2 つを clone（プラグインマネージャなし。版は固定せず再実行で最新に）
4. zsh が無ければ [zsh-bin](https://github.com/romkatv/zsh-bin)（静的ビルド、zsh 5.8）を `~/.local` に入れる
5. [mise](https://mise.jdx.dev) を `~/.local/bin/mise` に入れ（インストーラは取得してから版を固定して実行）、`config/mise/config.toml` のツール（tmux を含む）を全部入れる
6. fnm で Node の最新 LTS を入れて既定にする（`~/.local/share/fnm`。再実行で新しい LTS に追随）
7. Codex: `~/.codex/config.toml` を `config/codex/config.toml.tmpl` から生成（承認と信頼の表は引き継ぐ。中身が違えば既存を `*.bak.<日時>` に退避）。codex が無ければ[公式のインストーラー](https://github.com/openai/codex)で `~/.local/bin` に入れ、ponytail のプラグインと `tinymemory init codex` の hook を入れる
8. Neovim プラグインを `lazy-lock.json` の版に揃える
9. mac のみ: `mac/setup.sh`（Homebrew があれば Brewfile、スクリーンショット設定）

install.sh の対象外（GUI 端末・管理者権限が要るもの。サーバーでは不要）:

| | mac | Ubuntu / WSL |
|---|---|---|
| Ghostty | Brewfile（Homebrew が無ければ省略されるので、先に Homebrew を入れる） | Ubuntu 24.04 以前: `snap install ghostty --classic`（26.04+ は apt） / WSL は Windows の WezTerm（`winget install wez.wezterm`。設定は `config/wezterm/README.md`） |
| フォント | Hack Nerd Font（手動導入済み。Nerd Fonts 3.5.0 以降: ステータスラインの Claude・OpenAI のアイコン） | Hack Nerd Font を `~/.local/share/fonts` に置いて `fc-cache -f` |
| Tailscale | 公式 pkg（自動更新） | `curl -fsSL https://tailscale.com/install.sh \| sh` → `sudo tailscale up` |
| GitHub | `gh auth login` | `gh auth login` |
| ログインシェル | 標準で zsh | 任意: `chsh -s "$(command -v zsh)"`（`/etc/shells` に無い zsh は不可）。しなくても ssh・コンソールでは `bash_profile` が `exec zsh`（GUI 端末は非ログインの bash なので chsh か Ghostty の `command` が要る） |
| クリップボード | — | `sudo apt install wl-clipboard`（Neovim のヤンクをデスクトップのクリップボードへ。SSH 越しは OSC52 で不要） |
