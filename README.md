# dotfiles

mac / linux（Ubuntu・WSL・NAS = Debian 12）共通の開発環境。Windows ネイティブは対象外。
環境構築は **sudo 不要・ユーザー領域のみ**（`~/.local` 以下。システム全体には何も入れない）。Python は uv、Node は fnm で管理する。設定は `$HOME` へのシンボリックリンクなので、
**どの端末で編集してもこのリポジトリが変わる** → commit / push → 他端末で `git pull`（LINKS を変えたとき、または `ssh/config` を変えたときは `./install.sh` も。umask 002 の端末では pull で `ssh/config` が 664 になり、ssh が拒むため）。

経緯・決定理由は Linear の Dev-Environment プロジェクト（ARK-28、ドキュメント「ツール選定」）。

## セットアップ

前提: `git` `curl` があること（sudo は不要）。

```sh
git clone https://github.com/arkrtm/dotfiles.git ~/dotfiles
~/dotfiles/install.sh        # 何度実行しても安全。既存ファイルは *.bak.<日時> に退避
```

`install.sh` がやること:

1. 下表のファイルをシンボリックリンクで配置
2. `~/.ssh` を 700、`ssh/config` を 600 にする（ssh は他ユーザーが書ける設定ファイルを拒むため）
3. zsh プラグイン 2 つを clone（プラグインマネージャなし。版は固定せず再実行で最新に）
4. zsh が無ければ [zsh-bin](https://github.com/romkatv/zsh-bin)（静的ビルド、zsh 5.8）を `~/.local` に入れる
5. [mise](https://mise.jdx.dev) を `~/.local/bin/mise` に入れ（インストーラは取得してから版を固定して実行）、`config/mise/config.toml` のツール（tmux を含む）を全部入れる
6. fnm で Node の最新 LTS を入れて既定にする（`~/.local/share/fnm`。再実行で新しい LTS に追随）
7. Neovim プラグインを `lazy-lock.json` の版に揃える
8. mac のみ: `mac/setup.sh`（Homebrew があれば Brewfile、スクリーンショット設定、launchd 登録）

install.sh の対象外（GUI 端末・管理者権限が要るもの。サーバーでは不要）:

| | mac | Ubuntu / WSL | NAS (UGOS) |
|---|---|---|---|
| Ghostty | Brewfile（Homebrew が無ければ省略されるので、先に Homebrew を入れる） | Ubuntu 24.04 以前: `snap install ghostty --classic`（26.04+ は apt） / WSL は Windows Terminal | 不要 |
| フォント | Hack Nerd Font（手動導入済み） | Hack Nerd Font を `~/.local/share/fonts` に置いて `fc-cache -f` | 不要 |
| Tailscale | 公式 pkg（自動更新） | `curl -fsSL https://tailscale.com/install.sh \| sh` → `sudo tailscale up` | Docker（下記） |
| GitHub | `gh auth login` | `gh auth login` | `gh auth login` |
| ログインシェル | 標準で zsh | 任意: `chsh -s "$(command -v zsh)"`（`/etc/shells` に無い zsh は不可）。しなくても ssh・コンソールでは `bash_profile` が `exec zsh`（GUI 端末は非ログインの bash なので chsh か Ghostty の `command` が要る） | chsh 不可 → `exec zsh` |
| クリップボード | — | `sudo apt install wl-clipboard`（Neovim のヤンクをデスクトップのクリップボードへ。SSH 越しは OSC52 で不要） | 不要 |

## 構成

| リポジトリ | 配置先 | 内容 |
|---|---|---|
| `shell/zshenv` `shell/zprofile` `shell/zshrc` | `~/.zshenv` `~/.zprofile` `~/.zshrc` | vi キー、fzf（Ctrl-R/T, Alt-C）、starship、mise、fnm（既定の Node を PATH に、対話シェルでは `fnm env`）、エイリアス `ll la lt lg lzd`、関数 `cw`。zprofile は mac のログインで path_helper が組み替えた PATH の先頭をユーザー領域に戻し、Homebrew を PATH に入れる |
| `shell/bashrc` `shell/bash_profile` | `~/.bashrc` `~/.bash_profile` | zsh が無い端末用（環境変数は zshenv を読んで共有）。対話ログインで zsh があれば `exec zsh`（`NO_ZSH=1` で抑止。zsh が起動直後に死ぬ時は `ssh -t <host> 'NO_ZSH=1 bash -l'` で入る） |
| `config/mise/config.toml` | `~/.config/mise/config.toml` | rg fd bat eza fzf starship gh jq uv fnm tmux lazygit lazydocker neovim tree-sitter yazi tinymemory |
| `config/starship.toml` | `~/.config/starship.toml` | 2 行・最小、One Dark |
| `config/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` | prefix `C-g`、hjkl、`-` `\|` 分割、passthrough（画像）、extended-keys、OSC52、エージェント状態表示 |
| `config/ghostty/config` | `~/.config/ghostty/config` | Hack Nerd Font Mono、Atom One Dark、ssh-terminfo、通知 |
| `config/nvim/` | `~/.config/nvim/` | lazy.nvim + onedark, lualine, telescope, gitsigns, yazi.nvim, treesitter, noice（コマンドラインは画面上部のポップアップ、メッセージは右下） |
| `config/yazi/` | `~/.config/yazi/` | GeoTIFF プレビュー（`geotiff.yazi` → `geoview`） |
| `config/claude/settings.json` | `~/.claude/settings.json` | プラグイン（tinymemory は GitHub の marketplace、superpowers は公式の marketplace）、hooks（状態表示 + compact・resume 後の記憶の注入）、ログ 365 日 |
| `config/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | 全プロジェクト共通の指示: 作業の哲学（Karpathy guidelines + Ponytail を原文で取り込み）、Linear の使い方、スクショの場所（開発の手順は superpowers の skill に任せる） |
| `config/claude/skills/issue` `config/claude/skills/wrap-up` | `~/.claude/skills/issue` `~/.claude/skills/wrap-up` | Linear の記録の skill（`/issue ARK-nn` で issue から始める、`/wrap-up` で統合の前に結果を振り分けて残す）。ほかの skill は置かない |
| `config/git/config` | `~/.config/git/config` | user / defaultBranch。端末固有設定は `~/.gitconfig`（リポジトリ外） |
| `config/git/ignore` | `~/.config/git/ignore` | 全リポジトリ共通の除外（superpowers の plan と台帳 `.superpowers/`） |
| `config/bat/config` | `~/.config/bat/config` | TwoDark |
| `config/ss-sync/targets` | `~/.config/ss-sync/targets` | スクショ送信先ホスト（`nas`） |
| `ssh/config` | `~/.ssh/config` | `nas`: LAN に居れば 192.168.0.49、外では Tailscale。端末固有の Host は `~/.ssh/config.local`（リポジトリ外、`Include`） |
| `bin/*` | `~/.local/bin/*` | 下記 |
| `Brewfile` `mac/` | — | mac 専用（ghostty, スクショ, launchd） |
| `tests/` | — | コミット前の検査（何を通すかは `CLAUDE.md`）。`static.sh` は構文と設定、`install.sh` はリンク、`acceptance/*.sh` は受け入れ、`install-nosudo.sh` はコンテナでのフル install、`nvim.sh` は Neovim |

`bin/`:

- `agent-status` — Claude Code hooks から呼ばれ、tmux のウィンドウ名に `● 作業中 / ? 入力待ち / ✓ 完了` を出し、入力待ち・完了でデスクトップ通知（OSC 777）
- `geoview FILE [-o out.png]` — GeoTIFF の情報表示 / プレビュー PNG（uv + rasterio。GDAL 同梱 wheel なので sudo・conda 不要）
- `ss-sync` — `~/Screenshots` の新しい画像を `ss-YYYYmmdd-HHMMSS.png`（保存時刻。同じ秒は `-2`）の名前で送信先の `~/screenshots/` へ `scp -O`（送信のたびに 7 日より古いものを削除。元のファイルはそのまま）。送信先は `config/ss-sync/targets`（1 行 1 ホスト、`#` はコメント）。失敗は `~/.local/state/ss-sync/log`（mac は `launchd.err` も）。`BatchMode` なので、新しい端末では一度手で `ssh nas` して known_hosts に入れる
- `lan-reachable HOST PORT` — 1 秒の TCP 到達判定（ssh config の Match exec 用）

## Claude Code の手順

開発の手順（設計・計画・TDD・レビュー・ブランチの仕上げ）は [superpowers](https://github.com/obra/superpowers)（プラグイン。公式の marketplace `claude-plugins-official`）の skill に任せる。Linear の記録は dotfiles の skill（`/issue`・`/wrap-up`）。自作のハーネス（プラグイン harness）はやめた（ARK-67。経緯は ARK-30・52・63〜66）。dotfiles が受け持つのは次の 2 つ:

- `config/claude/settings.json` の宣言（`extraKnownMarketplaces` の `claude-plugins-official`・`tinymemory` と、`enabledPlugins` の `superpowers@claude-plugins-official`・`tinymemory@tinymemory`）。宣言だけでは入らないので、新しい端末では `install.sh` の後に `claude plugin marketplace add anthropics/claude-plugins-official` → `claude plugin install superpowers@claude-plugins-official` → `claude plugin marketplace add arkrtm/tinymemory` → `claude plugin install tinymemory@tinymemory`
- skill の `issue`・`wrap-up`（`install.sh` が `~/.claude/skills` にリンクする）

更新は `claude plugin marketplace update <marketplace>` → `claude plugin update <plugin>`（新しいセッションから効く）。`LIVE=1 sh tests/acceptance/claude-config.sh` は、本物の `claude -p` の新しいセッションで superpowers・tinymemory と skill の issue・wrap-up が見えることと、空の設定の置き場で上の新しい端末の手順が通り settings.json を変えないことを確かめる（haiku を 1 回呼ぶ。課金あり。marketplace の取得にネットワークが要る）。

## 端末ごとの注意

### SSH 鍵

端末ごとに別鍵（ed25519、パスフレーズなし、コメント `arkrithm@<端末名>`）。秘密鍵はリポジトリに入れない。
**NAS はパスワード認証を無効化済み**（`/etc/ssh/sshd_config.d/10-no-password.conf`）なので `ssh-copy-id` は使えない。
新しい端末の公開鍵（`cat ~/.ssh/id_ed25519.pub` の 1 行）を、**登録済みの端末から**追加する:

```sh
ssh nas 'cat >> ~/.ssh/authorized_keys' <<'EOF'
ssh-ed25519 AAAA... arkrithm@<端末名>
EOF
```

登録済みの端末がすべて使えなくなった時: UGOS の SSH 設定ではパスワード認証を戻せない（オフ・オンしてもこのファイルは残る）。
UGOS の Docker アプリで `/etc/ssh` をマウントしたコンテナを作り、`10-no-password.conf` を削除 → UGOS で SSH をオフ・オンすると、パスワードで入れるようになる。
NAS のホスト鍵: `ED25519 SHA256:+v6I4BkYicGHnmjlo25WTLr2iKmaMgkdbYdt6oWwu/w`（ssh config で `HostKeyAlias nas`）。
自宅外で同じ IP（192.168.0.49）に別の sshd がいると LAN 経路が選ばれ、ホスト鍵の検証で拒否される（Tailscale には切り替わらない。安全側。その場で使うなら `ssh nas.tail9542af.ts.net`）。

### スクリーンショット → NAS の Claude Code

- mac: `mac/setup.sh` が保存先を `~/Screenshots` に変え、撮影後サムネイルを無効化（保存が約 5 秒遅れるため）、launchd の WatchPaths で `ss-sync` を起動
- Ubuntu: **未実装**。GNOME は `~/Pictures/Screenshots` に保存するので `~/Screenshots` をそこへのリンクにし、systemd ユーザーの path unit（`PathChanged=`）で `ss-sync` を起動する想定
- NAS 側の Claude Code は `~/.claude/CLAUDE.md` の指示で「スクショ」と言われたら `~/screenshots/` の最新を見る

### NAS (UGOS / Debian 12) の癖

- **sudo 不要が前提**（UGOS 更新で apt 導入物が消える可能性）。apt は依存が壊れていた（`ctdb` が `time` 未導入）→ 入れる時は `time` も明示
- **chsh 不可**（UGOS 管理のユーザー）→ `bash_profile` で `exec zsh`
- `/etc/profile.d/go.sh` が廃止済み `GODEBUG=tlskyber=0` を設定 → Go 1.24+ のツール（fzf, gh 等）が落ちるので shell 設定で外している
- glibc 2.36: mise の gnu 版バイナリが動かないものがある → yazi は musl 版、tree-sitter CLI は動かないので nvim-treesitter は自動で無効
- SFTP は仮想パス（`/home/` = 自分のホーム）。`scp -O`（従来方式）なら実パスで使える。ssh 経由の rsync は不可
- sshd は 127.0.0.1 からの接続に応答しない
- UGOS の SSH 設定: オートオフ =「長期有効」（既定では一定時間で自動オフになり `Connection refused` になる）、「ローカルネットワークアクセスのみを許可する」= オン（インターネットからの ssh は UGOS が拒否。Tailscale 経由は NAS 自身からの接続になるので通る）
- Tailscale: `/volume1/docker/nas-ts/docker-compose.yaml`（host ネットワーク + userspace）。ssh は `tailscale serve --tcp 22 tcp://192.168.0.49:22` で転送。LAN IP を変えたら ssh config と serve の両方を直す
- LAN IP 192.168.0.49 はルーター（TP-Link AX5400）の「アドレス予約」で固定済み（MAC `6C-1F-F7-AC-BE-8D` = NAS の eth1）。**LAN ケーブルを別ポート（eth0 = `…:8C`）に差し替えたら予約も更新する**

### mise

- 公開 24 時間未満のリリースは `latest` で選ばれない（サプライチェーン対策）。自作の tinymemory は版を明示しているので、**リリースしたら `config/mise/config.toml` の版を上げる**
- mise 本体の版は `install.sh` の `MISE_VERSION=` で固定している（最初の install にだけ効く。インストーラが配布物をその release の SHASUMS256.txt で検証するため）。上げるときはその値を直す。入っている端末は `mise self-update`
- tmux は Homebrew から mise に移した（ARK-37）。以前から使っている mac では `brew uninstall tmux` で Homebrew 版を消す（`brew bundle` は消さない。残ると PATH 次第で版がずれ、クライアントとサーバーの版が合わなくなる）
- `config.toml` の後半はテーブル形式。**その後ろに `key = value` を書くとテーブルに入ってしまう**ので、通常のツールは前半に追加する
- tinymemory のプラグイン hook は PATH・`~/.local/bin`・`~/.cargo/bin` しか探さない（hook 文字列は変更不可）→ `install.sh` が `~/.local/bin/tinymemory` に shim を置く

### 使わないもの（決定済み）

conda / conda-forge / pixi（Python は uv）、システムや Homebrew の Python・Node を開発に使うこと（uv / fnm で管理）、Windows ネイティブ
