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
7. Codex: `~/.codex/config.toml` を `config/codex/config.toml.tmpl` から生成（承認と信頼の表は引き継ぐ。中身が違えば既存を `*.bak.<日時>` に退避）。codex が無ければ[公式のインストーラー](https://github.com/openai/codex)で `~/.local/bin` に入れ、ponytail のプラグインと `tinymemory init codex` の hook を入れる
8. Neovim プラグインを `lazy-lock.json` の版に揃える
9. mac のみ: `mac/setup.sh`（Homebrew があれば Brewfile、スクリーンショット設定、launchd 登録）

install.sh の対象外（GUI 端末・管理者権限が要るもの。サーバーでは不要）:

| | mac | Ubuntu / WSL | NAS (UGOS) |
|---|---|---|---|
| Ghostty | Brewfile（Homebrew が無ければ省略されるので、先に Homebrew を入れる） | Ubuntu 24.04 以前: `snap install ghostty --classic`（26.04+ は apt） / WSL は Windows の WezTerm（`winget install wez.wezterm`。設定は下の「WezTerm（Windows）」） | 不要 |
| フォント | Hack Nerd Font（手動導入済み。Nerd Fonts 3.5.0 以降: ステータスラインの Claude・OpenAI のアイコン） | Hack Nerd Font を `~/.local/share/fonts` に置いて `fc-cache -f` | 不要 |
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
| `config/wezterm/wezterm.lua` | —（Windows の `WEZTERM_CONFIG_FILE` で指す） | WSL の端末。既定は WSL、`Ctrl+Shift+1` で WSL・`Ctrl+Shift+2` で PowerShell のタブ、`Ctrl+Shift+O` でランチャー。kitty 方式の画像（herdr の中の yazi） |
| `config/nvim/` | `~/.config/nvim/` | lazy.nvim + onedark, lualine, telescope, gitsigns, yazi.nvim, treesitter, noice（コマンドラインは画面上部のポップアップ、メッセージは右下） |
| `config/yazi/` | `~/.config/yazi/` | GeoTIFF プレビュー（`geotiff.yazi` → `geoview`） |
| `config/claude/settings.json` | `~/.claude/settings.json` | プラグイン（tinymemory・ponytail は GitHub の marketplace、superpowers は公式の marketplace）、remote-control を常に（`remoteControlAtStartup`）、hooks（状態表示 + compact・resume 後の記憶の注入 + integrate-hook・handoff・context-nudge・agent-pane）、permissions（`git push`・`gh pr merge`・`integrate --human-approved`・`integrate setup --force` と `.env`・`~/.ssh`・`~/.codex/auth.json` の読み取り、`~/.config/integrate/` の編集を禁止。push の禁止は統合を `integrate` に通すための抑止で、Bash の規則は前方一致なので `git -C . push` や `bin/integrate setup --force` などは捕らえない。機械的な関門は integrate 自身。設定の上書きは integrate が端末からだけ受け付ける）、ステータスライン、ログ 365 日 |
| `config/claude/statusline.sh` | `~/.claude/statusline.sh` | ステータスライン（2 行。Claude のモデルと effort → Codex のモデルと effort（`~/.codex/config.toml` から）→ ブランチと、コンテキスト・5 時間・週の上限のメーター → Codex の 5 時間・週の上限のメーター（`~/.codex/sessions` の更新の新しいセッションの最後の記録から）。Nerd Font のアイコン。Claude・OpenAI のアイコン（`nf-cod-claude`・`nf-cod-openai`）は Nerd Fonts 3.5.0 以降のフォントが要る） |
| `config/agents/AGENTS.md` | `~/.claude/CLAUDE.md` `~/.pi/agent/AGENTS.md` `~/.codex/AGENTS.md` | 全プロジェクト共通の指示（Claude Code・Pi・Codex で 1 本。ツールごとの読み替えも書く）: 作業の哲学（優先順位と、質問・変更の量・検証・リファクタの判断。コードの書き方と量は ponytail のプラグインに任せる）、レビュー（計画と最終は codex-review）、Linear の使い方、スクショの場所（開発の手順は superpowers の skill に任せる） |
| `config/codex/config.toml.tmpl` | —（`~/.codex/config.toml` を生成） | Codex の設定: モデル sol（`gpt-6.1-sol`）・effort xhigh に固定、ponytail、tinymemory の書き込み先、Linear の MCP。リンクしないのはホームの絶対パスが要るため。Codex が書き込んだ分は install.sh の再実行で消える。ただしフックの承認（`hooks.state`）・プロジェクトの信頼（`projects`）・表示（`tui`）の表は引き継ぐ |
| `config/agents/skills/issue` `config/agents/skills/wrap-up` | `~/.claude/skills/…` `~/.agents/skills/…`（Pi・Codex が読む） | Linear の記録の skill（`/issue ARK-nn` で issue から始める、`/wrap-up` で統合の前に結果を振り分けて残す）。ほかの skill は置かない |
| `config/git/config` | `~/.config/git/config` | user / defaultBranch、rebase 中心の pull・push（`push.autoSetupRemote` は git 2.37 から）、衝突は diff3、bare の守り（この端末の bare は新旧とも、早送りでない push とブランチの削除を拒む）。端末固有設定は `~/.gitconfig`（リポジトリ外） |
| `config/git/hooks-nosign/` | `~/.config/git/hooks-nosign/` | コミットメッセージから AI の `Co-Authored-By` 行を消す commit-msg フック。業務サーバーだけが使う（下の「業務サーバー」） |
| `config/pi/` `config/herdr/` | `~/.pi/agent/…` `~/.config/herdr/…` | Pi と herdr の設定（詳細は `config/pi/README.md`） |
| `config/git/ignore` | `~/.config/git/ignore` | 全リポジトリ共通の除外（superpowers の plan と台帳 `.superpowers/`、issue ごとの worktree `.worktrees/`） |
| `config/bat/config` | `~/.config/bat/config` | TwoDark |
| `config/ss-sync/targets` | `~/.config/ss-sync/targets` | スクショ送信先ホスト（`nas`） |
| `ssh/config` | `~/.ssh/config` | `nas`: LAN に居れば 192.168.0.49、外では Tailscale。端末固有の Host は `~/.ssh/config.local`（リポジトリ外、`Include`） |
| `bin/*` | `~/.local/bin/*` | 下記 |
| `Brewfile` `mac/` | — | mac 専用（ghostty, スクショ, launchd） |
| `scripts/check` | — | dotfiles のテスト（`tests/static.sh`・`install.sh`・`acceptance.sh`。dotfiles の `integrate setup` の test と CI が呼ぶ。ほかのリポジトリに同じ名前を求める決まりではない） |
| `.github/workflows/check.yml` | — | GitHub の CI。PR と main への push で `scripts/check` を ubuntu で実行する（push の後の知らせ。main の保護の必須チェックではない） |
| `tests/` | — | コミット前の検査（何を通すかは `CLAUDE.md`）。`static.sh` は構文と設定、`install.sh` はリンク、`acceptance/*.sh` は受け入れ、`install-nosudo.sh` はコンテナでのフル install、`nvim.sh` は Neovim |

`bin/`:

- `agent-status` — Claude Code hooks から呼ばれ、tmux のウィンドウ名に `● 作業中 / ? 入力待ち / ✓ 完了` を出し、入力待ち・完了でデスクトップ通知（OSC 777）
- `geoview FILE [-o out.png]` — GeoTIFF の情報表示 / プレビュー PNG（uv + rasterio。GDAL 同梱 wheel なので sudo・conda 不要）
- `ss-sync` — `~/Screenshots` の新しい画像を `ss-YYYYmmdd-HHMMSS.png`（保存時刻。同じ秒は `-2`）の名前で送信先の `~/screenshots/` へ `scp -O`（送信のたびに 7 日より古いものを削除。元のファイルはそのまま）。送信先は `config/ss-sync/targets`（1 行 1 ホスト、`#` はコメント）。失敗は `~/.local/state/ss-sync/log`（mac は `launchd.err` も）。`BatchMode` なので、新しい端末では一度手で `ssh nas` して known_hosts に入れる
- `lan-reachable HOST PORT` — 1 秒の TCP 到達判定（ssh config の Match exec 用）
- `integrate [--human-approved]` — 統合はこれだけで行う。関門（`integrate setup` の設定がある・最上位のブランチ（base）の最新を含む・未コミットの変更が無い・設定の test が通る・今のコミットの origin/<base> との差分への `codex-review branch` が `VERDICT: PASS`・テストの削除や移動と skip・xfail・`type: ignore`・`noqa` の追加が無い。Markdown の文書は数えない）を 1 つでも満たさなければ統合せず `notify` して終了コード 1（設定の remote が origin と違う・origin の push 先が取得先と違う設定でも止まる）。kind が `bare`・`github` なら base へ push（早送りだけ）、`pr` ならブランチを push して base に向けた PR を作るだけ（マージはチーム）。`--human-approved` はテストや検査を弱める変更を人が確認して通す（人用）
- `integrate setup` — リポジトリごとの設定（下の「integrate setup」）
- `integrate-hook <session-start|pre-edit>` — Claude Code のフック。origin があって `integrate setup` の設定が無いリポジトリでは、会話の始まりに setup を案内し、編集（Edit・Write・NotebookEdit）を拒む（終了コード 2）。読む・調べる・Bash は止めない（Bash での書き換えは捕らえない抑止）。設定がある・origin が無い・git の外では何もしない
- `handoff <続きの指示>` — herdr の中で、このターンの後に自分の pane へ `/clear` と続きの指示を送る（下の「常時起動サーバー」）。Claude が handoff skill の手順で呼ぶ。herdr の外では 1
- `context-nudge` — PostToolUse のフック。ステータスラインが書いた文脈の使用率が 60% 以上なら、10% 刻みに 1 回 handoff を促す（サブエージェントの中では出さない）
- `agent-pane <start|stop|cleanup|view>` — サブエージェントのフック。herdr の中で、サブエージェントの進みを別の pane に出す（同時に 2 つまで）
- `notify MESSAGE` — エージェントが止めた理由を `~/.local/state/agent-notify.log` に記録して標準エラーに出す（外部には送らない。スマホへは Claude Code mobile が届ける）

## Claude Code の手順

開発の手順（設計・計画・TDD・レビュー）は [superpowers](https://github.com/obra/superpowers)（プラグイン。公式の marketplace `claude-plugins-official`）の skill に任せる。ブランチ・worktree・統合の方法はグローバル指示（`config/agents/AGENTS.md`）の「Git」の節で、統合の後の片づけ（Linear の完了・relay・worktree）は `/wrap-up` の「統合の後」。Linear の記録は dotfiles の skill（`/issue`・`/wrap-up`）。自作のハーネス（プラグイン harness）はやめた（ARK-67。経緯は ARK-30・52・63〜66）。dotfiles が受け持つのは次の 3 つ:

- `config/claude/settings.json` の宣言（`extraKnownMarketplaces` の `claude-plugins-official`・`tinymemory`・`ponytail` と、`enabledPlugins` の `superpowers@claude-plugins-official`・`tinymemory@tinymemory`・`ponytail@ponytail`。ponytail は node で動き、コードを最小にする指示を毎ターン入れる）。宣言だけでは入らないので、新しい端末では `install.sh` の後に `claude plugin marketplace add anthropics/claude-plugins-official` → `claude plugin install superpowers@claude-plugins-official` → `claude plugin marketplace add arkrtm/tinymemory` → `claude plugin install tinymemory@tinymemory` → `claude plugin marketplace add DietrichGebert/ponytail` → `claude plugin install ponytail@ponytail`
- skill の `issue`・`wrap-up`（`install.sh` が `~/.claude/skills` と `~/.agents/skills` にリンクする）
- ステータスライン（上の表）

更新は `claude plugin marketplace update <marketplace>` → `claude plugin update <plugin>`（新しいセッションから効く）。`LIVE=1 sh tests/acceptance/claude-config.sh` は、本物の `claude -p` の新しいセッションで superpowers・tinymemory・ponytail と skill の issue・wrap-up が見えることと、空の設定の置き場で上の新しい端末の手順が通り settings.json を変えないことを確かめる（haiku を 1 回呼ぶ。課金あり。marketplace の取得にネットワークが要る）。

## Codex の手順

Codex はレビュー役（`bin/codex-review`。AGENTS.md の「レビュー」）。`install.sh` が本体・config.toml・ponytail・tinymemory の hook まで入れる。新しい端末ではその後に `codex login` → `codex plugin add superpowers@openai-curated-remote`（Codex 公式のカタログ。ログインが要る）→ `codex` を起動して `/hooks` で tinymemory と ponytail の hook を承認（端末ごとに一度）。

- `codex-review plan <計画書>` / `codex-review branch [ベース]` — `codex exec` を読み取り専用の sandbox・effort xhigh・フックなし（tinymemory の記憶を入れない。ponytail のフックも止まる）で呼ぶ。branch の最後の行は `VERDICT: PASS` / `VERDICT: FAIL`。branch の結果は `<git の共通ディレクトリ>/codex-review/<日時>-branch-<merge-base>-<HEAD>.md` にも保存する（`integrate` が読む）

## 端末ごとの注意

### 業務サーバー

端末ごとの違いは git のアカウントと署名だけ（私用の端末では Claude Code の既定どおりコミットに `Co-Authored-By` が付く）。業務サーバーでは `~/.gitconfig`（端末ローカル）に次を書く。`core.hooksPath` は各リポジトリの `.git/hooks` より優先されるので、業務のリポジトリで git フックを使い始めたら見直す:

```ini
[user]
	name = <業務の名前>
	email = <業務のアドレス>
[core]
	hooksPath = ~/.config/git/hooks-nosign
```

### integrate setup

`integrate` はリポジトリごとの設定に従う。設定は `~/.config/integrate/repos/<origin の識別子の英数字と ._- 以外を _ にした名前の先頭 100 文字>-<識別子のハッシュの先頭 12 文字>`（識別子は取得先 URL。ローカルのパスは解決した絶対パス） に `kind=`・`base=`・`test=`・`remote=` の 4 行で置く（リポジトリの外。worktree・clone し直しでも origin が同じなら同じ設定）:

| kind | 使う場面 | 統合 |
|---|---|---|
| `bare` | サーバーの bare に同じサーバーのクローンから push（一人の開発） | base（例 develop）へ直接 push |
| `github` | 自分の GitHub（一人の開発） | base（main）へ直接 push |
| `pr` | 書き込み権限のあるチームの GitHub | ブランチを push して base に向けた PR を作るまで（マージはチーム） |

- `integrate setup --kind <kind> --base <branch> --test '<command>'` で書く。引数が足りなければ、端末では推測を既定値に 1 項目ずつ尋ね、端末でなければ推測（kind: GitHub でなければ bare、持ち主が `gh` のログインなら github、ほかは pr。base: リモートの HEAD。test: `scripts/check`・`pyproject.toml`・`package.json`・`Cargo.toml`・`go.mod` から）を出して終了コード 2
- `integrate setup --show` で今の設定を出す。既にある設定は上書きしない（終了コード 1）。上書きは `integrate setup --force …` を人が端末で実行する。端末の確かめと settings.json の deny は抑止で（`--human-approved` と同じ水準）、同じユーザーで動くエージェントが擬似端末（`script`）や設定のファイルの rm で越えることまでは防げない
- この dotfiles は `integrate setup --kind github --base main --test 'sh scripts/check'`
- 設定の無いリポジトリで Claude Code が編集しようとすると、`integrate-hook` が止めて setup を促す。Claude は推測をユーザーに選択肢で確かめてから引数で setup する
- ARK-98 より前から使っている端末（業務サーバー・NAS など）の移行:

```sh
cd ~/dotfiles && git pull
rm ~/.claude/hooks                 # check・fmt のフックのリンク（リンク先が無くなった）
DOTFILES_LINKS_ONLY=1 sh install.sh  # bin/integrate-hook のリンクを足す
cd <各リポジトリ> && integrate setup  # 端末なら推測を既定値に尋ねる
```

### 常時起動サーバー（herdr と Claude Code）

常時起動のサーバー（どの端末でも同じ）で herdr を立ち上げ、その中で Claude Code を動かす。PC からは herdr に入って見る。モバイルからは Claude アプリの remote-control でメインの会話を見て指示する（ARK-90）:

```sh
herdr                       # サーバーの persistent session に入る（無ければ作る）
claude                      # メインの pane で。初回は /login（claude.ai）と remote-control の確認
```

- remote-control: settings.json の `remoteControlAtStartup: true` で、対話のセッションはすべて最初からモバイルにつながる（Pro/Max の claude.ai ログインが要る。`DISABLE_TELEMETRY`・`DO_NOT_TRACK` などを設定すると使えない）。モバイルからも `/clear` を送れる
- 自分で clear して続ける（待っている間に人が同じ pane で /clear・/resume・/branch したら取り消す）: 文脈が 60% を超えたとき（context-nudge が促す）と、issue の統合の後に次の issue を始めるとき（wrap-up skill の 5）に、Claude は handoff skill の手順で引き継ぎ（relay の記憶と Linear）を保存して `handoff` を呼ぶ。`handoff` はターンの終わりを待って `/clear` を送り、clear の後の SessionStart を待って続きの指示を送る。続きの指示は普通の入力として入るので、PC でもモバイルでも見える。続きの指示には合言葉（`[handoff <id>]`）が付き、clear の SessionStart が同じ合言葉を会話に入れたときだけ Claude が従う（送る直前に人が会話を切り替えた一瞬の隙間への備え）。閉じきれない隙間: idle を確かめてから `/clear` を送るまでの一瞬に人が `/resume` すると、再開した会話に `/clear` が届く（herdr から送る入力はセッションを指定できない）。`/clear` は会話を消さず新しい会話を始めるだけなので、`/resume` で戻せる。続きの指示は合言葉で拒まれる。経過は `~/.local/state/handoff.log`、止めたときは notify
- サブエージェントの進み（PC だけ）: 開始で `agent-pane view` の pane を開き、終了で閉じる。1 つ目はメインの下に 3 分の 1 の高さ、2 つ目はその右（フォーカスは移さない）。同時に 2 つまで。workflow のエージェント（`agent_type` が `workflow-subagent`）は数が多いので開かず、バックグラウンドのまま
- 限界: メインの上には出せない（herdr 0.9.5 の split は右と下だけで、入れ替え（swap）はフォーカスを移す）。workflow で `agentType` を指定したエージェントはフックの入力で見分けられないので、普通のサブエージェントと同じに開く（2 つまで）。チームのメンバー（agent teams）の split pane は tmux・iTerm2 だけで、herdr には出ない（in-process のメンバーは SubagentStart で上と同じ pane に出る）。`/clear` の後もモバイルの接続が続くことは実機で確かめた（2026-10-24）

### GitHub の main の保護

自分の GitHub（kind `github`）は integrate が main へ直接 push するので、PR 必須・必須チェックは入れず、強制 push と main の削除だけを禁じる。CI（`.github/workflows/check.yml`）は push の後に結果を知らせるだけ。PR を使うとき（手作業など）のマージは rebase だけ（squash・merge commit は無効）で、マージ後にブランチを消す。リポジトリごとに一度:

```sh
gh api -X PUT repos/arkrtm/dotfiles/branches/main/protection --input - <<'EOF'
{"required_status_checks":null,"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null,"required_linear_history":true,"allow_force_pushes":false,"allow_deletions":false}
EOF
gh api -X PATCH repos/arkrtm/dotfiles -F allow_rebase_merge=true -F allow_squash_merge=false -F allow_merge_commit=false -F delete_branch_on_merge=true -F allow_auto_merge=false
```

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

### WezTerm（Windows）

WSL では Windows Terminal ではなく WezTerm を使う。herdr は画像を kitty 方式でしか外へ通さず、Windows Terminal は sixel しか表示できないため、herdr の中の yazi で画像が見えない（`config/herdr/config.toml` の `[experimental] kitty_graphics` と `wezterm.lua` の `enable_kitty_graphics` で通す）。

WSL へは ConPTY を通らずに、WezTerm 内蔵の SSH で localhost の sshd につなぐ（ConPTY は kitty 方式の画像を落とし、iTerm2 方式でも位置がずれる。公式の unix_domains の方法は WSL1 専用で、`wsl.exe` 越しの `wezterm cli proxy` は Windows の GUI からだと応答が返らない）。前提: WSL の mirrored networking と、WSL で動く sshd。一度だけ:

1. Windows の PowerShell で、この接続専用の鍵を作り、設定ファイルを指す（WSL が止まっていると設定を読めず既定の設定になる）:
   ```powershell
   ssh-keygen -t ed25519 -N '""' -C wezterm-wsl -f $env:USERPROFILE\.ssh\wezterm_wsl
   setx WEZTERM_CONFIG_FILE "\\wsl.localhost\Ubuntu-22.04\home\<ユーザー>\dotfiles\config\wezterm\wezterm.lua"
   ```
2. WSL で、その鍵を localhost からの接続に限って許可する（`<Windows のユーザー>` は Windows 側の名前）:
   ```sh
   printf 'from="127.0.0.1,::1" %s\n' "$(cat /mnt/c/Users/<Windows のユーザー>/.ssh/wezterm_wsl.pub)" >> ~/.ssh/authorized_keys
   ```
3. WezTerm を起動し、初回はホスト鍵の確認に答える

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
