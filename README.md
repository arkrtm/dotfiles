# dotfiles

mac / linux（Ubuntu・WSL・NAS = Debian 12）共通の開発環境。Windows ネイティブは対象外。
環境構築は **sudo 不要・ユーザー領域のみ**（`~/.local` 以下。システム全体には何も入れない）。Python は uv、Node は fnm で管理する。設定は `$HOME` へのシンボリックリンクなので、
**どの端末で編集してもこのリポジトリが変わる** → commit / push → 他端末で `git pull`（必要なら `./install.sh`）。

経緯・決定理由は Linear の Dev-Environment プロジェクト（ARK-28、ドキュメント「ツール選定」）。

## セットアップ

前提: `git` `curl` があること（sudo は不要）。

```sh
git clone https://github.com/arkrtm/dotfiles.git ~/dotfiles
~/dotfiles/install.sh        # 何度実行しても安全。既存ファイルは *.bak.<日時> に退避
```

`install.sh` がやること:

1. 下表のファイルをシンボリックリンクで配置
2. zsh プラグイン 2 つを clone（プラグインマネージャなし）
3. zsh が無ければ [zsh-bin](https://github.com/romkatv/zsh-bin)（静的ビルド、zsh 5.8）を `~/.local` に入れる
4. [mise](https://mise.jdx.dev) を `~/.local/bin/mise` に入れ、`config/mise/config.toml` のツール（tmux を含む）を全部入れる
5. fnm で Node の最新 LTS を入れて既定にする（`~/.local/share/fnm`。再実行で新しい LTS に追随）
6. `harness-hook` 用に uv の実体を `~/.local/libexec/uv`（PATH には入れない）にリンクし、Python を用意する（システムに 3.9 以上が無い時だけ）
7. Neovim プラグインを `lazy-lock.json` の版に揃える
8. mac のみ: `mac/setup.sh`（Brewfile、スクリーンショット設定、launchd 登録）

install.sh の対象外（GUI 端末・管理者権限が要るもの。サーバーでは不要）:

| | mac | Ubuntu / WSL | NAS (UGOS) |
|---|---|---|---|
| Ghostty | Brewfile | Ubuntu 24.04 以前: `snap install ghostty --classic`（26.04+ は apt） / WSL は Windows Terminal | 不要 |
| フォント | Hack Nerd Font（手動導入済み） | Hack Nerd Font を `~/.local/share/fonts` に置いて `fc-cache -f` | 不要 |
| Tailscale | 公式 pkg（自動更新） | `curl -fsSL https://tailscale.com/install.sh \| sh` → `sudo tailscale up` | Docker（下記） |
| GitHub | `gh auth login` | `gh auth login` | `gh auth login` |
| ログインシェル | 標準で zsh | 任意: `chsh -s "$(command -v zsh)"`（`/etc/shells` に無い zsh は不可）。しなくても `bash_profile` が `exec zsh` | chsh 不可 → `exec zsh` |

## 構成

| リポジトリ | 配置先 | 内容 |
|---|---|---|
| `shell/zshenv` `shell/zshrc` | `~/.zshenv` `~/.zshrc` | vi キー、fzf（Ctrl-R/T, Alt-C）、starship、mise、fnm（既定の Node を PATH に、対話シェルでは `fnm env`）、エイリアス `ll la lt lg lzd cw` |
| `shell/bashrc` `shell/bash_profile` | `~/.bashrc` `~/.bash_profile` | zsh が無い端末用。対話ログインで zsh があれば `exec zsh`（`NO_ZSH=1` で抑止） |
| `config/mise/config.toml` | `~/.config/mise/config.toml` | rg fd bat eza fzf starship gh uv fnm tmux lazygit lazydocker neovim tree-sitter yazi tinymemory |
| `config/starship.toml` | `~/.config/starship.toml` | 2 行・最小、One Dark |
| `config/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` | prefix `C-g`、hjkl、`-` `\|` 分割、passthrough（画像）、extended-keys、OSC52、エージェント状態表示 |
| `config/ghostty/config` | `~/.config/ghostty/config` | Hack Nerd Font Mono、Atom One Dark、ssh-terminfo、通知 |
| `config/nvim/` | `~/.config/nvim/` | lazy.nvim + onedark, lualine, telescope, gitsigns, yazi.nvim, treesitter, noice（コマンドラインは画面上部のポップアップ、メッセージは右下） |
| `config/yazi/` | `~/.config/yazi/` | GeoTIFF プレビュー（`geotiff.yazi` → `geoview`） |
| `config/claude/settings.json` | `~/.claude/settings.json` | tinymemory プラグイン、hooks（状態表示 + ハーネス + compact・resume 後の記憶の注入）、ログ 365 日 |
| `config/claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | 全プロジェクト共通の指示: 作業の哲学（Karpathy guidelines + Ponytail を原文で取り込み）、作業の進め方（S/M/L、TDD、検証、レビュー、ブランチ）、Linear の使い方、スクショの場所 |
| `config/claude/skills/{issue,design,tdd,implement,accept,verify,review,diagnose,wrap-up}` | `~/.claude/skills/…` | `/design` 設計の対話（2〜3 案の比較と推奨、設計の合意）、`/tdd` TDD の手順と避けるべきテストの書き方、`/accept` acceptor による受け入れ検証（fork。成果物を実際に動かして受け入れ条件を確かめる）、`/verify` 検証手順、`/review` reviewer による敵対的レビュー（fork。`/review fix` は範囲限定の再レビュー）、`/issue ARK-nn` Linear 起点の作業、`/wrap-up` M/L 完了時の締め（Linear 記録 → 知識の振り分け → tinymemory 保存）、`/implement` 計画をタスクに分けて implementer で並列に実装、`/diagnose` 根本原因を確かめてから直すデバッグ手順 |
| `config/claude/agents/reviewer.md` | `~/.claude/agents/reviewer.md` | 読み取り専用・effort high の敵対的レビュアー |
| `config/claude/agents/implementer.md` | `~/.claude/agents/implementer.md` | `/implement` の実装者。持ち分のファイルだけを TDD で変え、短い状態報告を返す |
| `config/claude/agents/acceptor.md` | `~/.claude/agents/acceptor.md` | `/accept` の受け入れ検証役。実装を読む前に成果物を動かし、条件ごとに観測値で判定し、検査スクリプトを tests/ に残す。実装は直さない |
| `config/git/config` | `~/.config/git/config` | user / defaultBranch / `core.hooksPath`。端末固有設定は `~/.gitconfig`（リポジトリ外） |
| `config/git/hooks/` | `~/.config/git/hooks/` | 全リポジトリ共通の git hooks。`run-hook` 1 本に各 hook 名のリンク。pre-commit でハーネスの関門、続けてリポジトリ自身の `.git/hooks/<name>` に委譲。リポジトリ側で `core.hooksPath` を設定していると呼ばれない（関門も効かない） |
| `config/bat/config` | `~/.config/bat/config` | TwoDark |
| `config/ss-sync/targets` | `~/.config/ss-sync/targets` | スクショ送信先ホスト（`nas`） |
| `ssh/config` | `~/.ssh/config` | `nas`: LAN に居れば 192.168.0.49、外では Tailscale |
| `bin/*` | `~/.local/bin/*` | 下記 |
| `Brewfile` `mac/` | — | mac 専用（ghostty, スクショ, launchd） |

`bin/`:

- `agent-status` — Claude Code hooks から呼ばれ、tmux のウィンドウ名に `● 作業中 / ? 入力待ち / ✓ 完了` を出し、入力待ち・完了でデスクトップ通知（OSC 777）
- `geoview FILE [-o out.png]` — GeoTIFF の情報表示 / プレビュー PNG（uv + rasterio。GDAL 同梱 wheel なので sudo・conda 不要）
- `ss-sync` — `~/Screenshots` の新しい画像を `ss-YYYYmmdd-HHMMSS.png` に改名して送信先の `~/screenshots/` へ `scp -O`（7 日で削除）
- `lan-reachable HOST PORT` — 1 秒の TCP 到達判定（ssh config の Match exec 用）
- `harness-hook` — Claude Code の自作ハーネス（ARK-30）。git の pre-commit（`config/git/hooks/run-hook`、`core.hooksPath` で全リポジトリ共通）として、ステージした内容に証拠（要件の写し、宣言した検証の成功、acceptor による受け入れ検証の合格、reviewer の 3 軸 = 仕様適合・テスト・品質・保守性の承認）が無いコード変更のコミットを止める。Claude Code の hooks としては、main/master 上の編集と代表的な迂回（`--no-verify` 等）を拒否し、Stop でも 1 回差し戻す。証拠は内容（blob ID）の指紋で作業ツリー単位に `~/.local/state/harness/repo/` へ、ログは `~/.local/state/harness/log`。対象は Claude Code から行うコミットだけ（人の手動コミットは止めない）。uv で動く: 先頭の sh の起動部が、install.sh の置く `~/.local/libexec/uv`（uv の実体へのリンク）で自分を `uv run --script` し直す。起動側の PATH の並びや、mise の shim（cwd の mise 設定で壊れうる）には左右されない。uv が無いと Claude Code の hooks は動かず編集・迂回の拒否が効かない（Claude からのコミットは pre-commit が失敗して止まる）。テスト: `sh tests/harness-hook.sh`、`sh tests/install.sh`、`sh tests/install-nosudo.sh`（sudo も python3 も無い debian:12 コンテナで install.sh を通す。docker が要る。mac からは `DOCKER='ssh nas docker'`）

## Claude Code ハーネス（superpowers の代替）

常時読み込むのは CLAUDE.md・skill と agent の説明・SessionStart で注入する記憶（合わせて約 6k トークン。ARK-47 の計測）。手順は skill、強制は hook。

### 流れの全体図

```
依頼 → 規模の判定（S/M/L。迷ったら重い方）
  → 要件と受け入れ条件（/issue・/design）→ 承認 → 要件の写しを固定 ………… hook: 写しが無いと証拠にならない。書き換えると証拠は無効
  →（L）計画（plan mode。/implement の形）
  → ブランチ（main から）→ TDD（/tdd）／並列の実装（/implement）…… hook: main 上の編集を拒否。失敗したテストの出力（RED）を記録
  → /accept … acceptor が実装を読む前に成果物を動かし、条件ごとに観測値で判定 … hook: 合格が無いとコミットできない
  → /verify … 宣言した全体の検証コマンドをすべて通す ………………………… hook: 宣言に無い実行は証拠にならない。失敗で証拠が消える
  → /review … reviewer が 3 軸で判定（要件の写し・受け入れの報告・RED の記録を読む）… hook: 承認が無いとコミットできない
      指摘を直したら /accept → /verify → /review fix（2 回まで。残ればユーザーが裁定）
  → コミット … pre-commit が、ステージした内容に対する 4 つの証拠を確かめる
  → 統合の判断（ユーザー: マージ／PR／残す）→ マージ後に main で検証 → ブランチと worktree を片付ける
  → /wrap-up … Linear・CLAUDE.md・README・tinymemory に 1 か所ずつ記録
  （途中でコンテキストが溜まると、区切りで session の保存を促す。compact の後は記憶を注入）
```

### superpowers との対応

superpowers（obra/superpowers）の各 skill に当たるものと、どちらが強いか。superpowers は入れない（ARK-42）。「強い方」の凡例: **自作** = 自作が上回る（多くは hook で強制できるため）／**同等** = 同じことができる（違いは書き方）／**superpowers** = superpowers が上回る／**自作だけ** = superpowers に当たるものが無い

| superpowers | 自作 | 強い方 | 違い |
|---|---|---|---|
| using-superpowers（作業の前に skill を使わせる案内） | CLAUDE.md の流れの 1 行（常時読み込み） | 自作 | superpowers は案内の文を入れるだけ。自作は、手順を飛ばすと Stop が差し戻し、pre-commit が止める |
| brainstorming | `/design`・`/issue` | 同等 | 質問は 1 問ずつでなく、選択肢と推奨を付けてまとめて聞く（往復が少ない）。設計・要件・受け入れ条件は issue の本文に 1 か所 |
| writing-plans | `/implement` の計画の形 | 同等 | superpowers は手順ごとのコードまで書く。自作は、全体の制約・レビューの焦点・受け入れ条件 → タスクの対応・RED で期待する失敗を書き、コードは implementer に任せる |
| executing-plans・subagent-driven-development | `/implement` | 同等 | 自作は波ごとに並列で速く、安い（implementer は約 1.5 万トークン）。superpowers はタスクごとに 2 段のレビューをする。自作はその代わりに、インタフェースを作った波の後と最後に `/review`、最後に `/accept`。進捗は issue の本文のチェックリスト |
| dispatching-parallel-agents | `/implement` の波、`/diagnose` の並列の調査 | 同等 | — |
| test-driven-development・testing-anti-patterns | `/tdd`、reviewer のテスト軸 | 自作 | RED を hook が記録し、reviewer が読む（自己申告にしない）。既存テストの変更・削除も関門の対象 |
| systematic-debugging（根本原因の追跡・多層の防御・条件で待つ・汚染の特定） | `/diagnose` | 同等 | superpowers は補助の文書が多い。自作は安い順に絞り、原因が見えたら止める（試行でコスト増を 2〜4 割に抑えた。ARK-44） |
| verification-before-completion | `/verify`、`.harness-verify` | 自作 | 宣言した全体の検証がすべて同じ内容で通らないとコミットできない（文章だけでなく hook で止める） |
| — | `/accept`（acceptor） | 自作だけ | 成果物を実際に動かし、受け入れ条件ごとに観測値で判定し、検査を tests/ に残す（ARK-48） |
| requesting-code-review | `/review`（reviewer） | 自作 | 報告前の関門・重大度の定義・判断しなかったこと。承認が無いとコミットできない。`/review fix` は前回の報告（hook が保存）と修正差分だけを見る |
| receiving-code-review | CLAUDE.md の手順 6 | 同等 | 確かめてから直す。誤りは根拠を添えて反論し、reviewer が確かめて取り下げる。人・PR・`/code-review` の指摘も同じ |
| using-git-worktrees | `cw`（`claude -w`）、着手時の基準の検証 | 同等 | — |
| finishing-a-development-branch | CLAUDE.md の手順 8 | 同等 | 選択肢の提示、マージ後の検証、破棄は明示の依頼のときだけ、worktree は `--force` を使わない |
| writing-skills | 同梱の skill-creator、`tests/skills.sh`、`tests/e2e-flow.sh` | superpowers | superpowers は skill そのものを TDD で書く手法（圧力をかける場面で失敗を見てから直す）が詳しい。自作は skill・agent・参照・リンクの一貫性の検査（関門に入れる）と、流れ全体を `claude -p` で実際に動かす検査（手動）で補う |
| — | 記録の振り分け（`/issue`・`/wrap-up`・区切りの remember） | 自作だけ | Linear・CLAUDE.md・README・tinymemory に重複なく |
| プラグインとして 15 以上の環境に入る | dotfiles 前提 | superpowers | 自作は個人の環境での強制を優先した（ARK-46） |

- 規模判定 S / M / L で手順を変える（CLAUDE.md の表）
- コードを書くときの規則: 作業ブランチ、TDD（REFACTOR まで）、`/accept`、`/verify`、`/review`（仕様適合・テスト・品質・保守性の 3 軸）。証拠（検証の成功・受け入れ検証の合格・レビューの承認）が無いコード変更は git の pre-commit が止める
- 受け入れ検証（ARK-48。いちばん大事な段階）: 型やテストが通っても、成果物が要件どおりとは限らない。受け入れ条件は成果物を実際に動かして確かめられる性質（データなら件数・スキーマ・値の範囲・一意性・参照の整合・再現性・境界）で書き、独立した acceptor が実装を読む前に本物の入力（無理ならサンプル）で成果物を動かして確かめる。作った本人が確かめないので甘くならない。判定行 `受け入れ: 合格` と条件ごとの行 `[ACn] 合格` がそろったときだけ hook が「受け入れ済み」を記録し、報告は git dir の `harness-last-accept` に保存して reviewer が読む。検査スクリプトは tests/ に残るので、以後の変更でも壊れたら分かる
- レビューの往復を抑える仕組み（ARK-41。superpowers の範囲限定の再レビューと ECC の報告前の関門を参考）: フルレビューは 1 回。直した後は `/review fix` が「前回の未解決の指摘」と「前回見た版からの修正差分」だけを見る（版は `skills/review/snapshot.sh` が作業ツリー全体の tree ID として記録）。重大・中は具体的な発生条件が書けるものだけで、軽と範囲外は判定に影響しない（issue に記録）。reviewer は検証を回し直さない。`/review fix` は 2 回まで、それでも残ればユーザーが指摘ごとに裁定する
- 並列実装とデバッグ（ARK-42。superpowers の subagent-driven-development・systematic-debugging と ECC の multi-*・build-error-resolver を参考に自作し、どちらも入れない）: `/implement` は計画を「持ち分のファイルが重ならないタスク」に分けて波ごとに implementer を同時に起動し、コントローラは短い状態報告だけを受けて統合・検証・レビューする。implementer はツールを絞っていて、小さなタスク 1 つで約 1.5 万トークン（汎用のエージェントの約 4 分の 1。ARK-47）。`/diagnose` は再現コマンド → 安い順の絞り込み（スタックトレースの箇所 → 逆向きの追跡 → 最近の変更 → 動く例との比較 → 境界の計測 → `git bisect run`。原因が見えたらそこで止める）→ 反証できる仮説 → 回帰テスト付きで共有の関数を直す。3 回直らなければ設計を疑って相談する
- 対象: Claude Code から行うコミット（環境変数 `CLAUDECODE` がある）で、Claude が cwd にして作業したことのあるリポジトリ（その worktree を含む）。人の手動コミット、GUI クライアント、テストが作る一時リポジトリ、セッションの cwd 以外のリポジトリは対象外。検証・受け入れ検証・レビューの証拠は、セッションの cwd の作業ツリーに対して記録される
- 「コード」= `bin/harness-hook` の `CODE_EXT` にある拡張子のファイル（設定の .json .toml .yaml .yml .ini .cfg を含む）、名前が Dockerfile・Makefile・justfile のファイル、拡張子の無い shebang 付きスクリプト、リポジトリの `.harness-code` に書いたパス。それ以外（Markdown など）の変更は関門を通る。テスト実行の生成物（`__pycache__/`、`.pyc`、`.pyo`）は、名前や置き場所がテストに見えてもテストとして数えない
- 限界（ガードレールであって、セキュリティ境界ではない）:
  - 意図的な迂回は防ぎ切れない（`git commit-tree`、`env -i` のような環境の丸ごとの消去、証拠ファイルの書き換えなど。代表的な形は Bash hook が拒否し、CLAUDE.md で禁止している。ARK-49 で、閲覧目的のコマンド（小文字の `git_config` の grep、`--no-verbose`、`echo $CLAUDECODE`）の誤検知は減らした）
  - pre-commit を通らない操作（`cherry-pick`、`rebase`、競合の無い `merge`）、競合解消の締めのコミット、テストの追加だけのコミットは対象外（マージ後は main で検証一式を流す手順で補う）
  - リポジトリ側で `core.hooksPath` を設定している場合（husky 等）は関門が呼ばれない
  - 受け入れ検証とレビューの証拠は、サブエージェントが終わった時点の内容に記録される。その間にファイルを変えると、見ていない内容にも付く（CLAUDE.md で禁止）
  - 要件の写しはメインが書く（承認済みの issue の本文を写す手順）。写しが本文と一致しているかは、機械では確かめない
  - 共通 hooks にリンクを置いていない hook 名（`reference-transaction`、`post-index-change`、`pre-auto-gc`、`p4-*`。高頻度で呼ばれるため）は、リポジトリ自身に同名の hook があっても実行されない
  - グローバルな `core.hooksPath` との非互換: `pre-commit install`（pre-commit フレームワーク）は hooksPath が設定されていると拒否する。`git lfs install` は hooks を `~/.config/git/hooks`（= この dotfiles）に書こうとする。必要なリポジトリでは、そのリポジトリの設定で hooksPath を `.git/hooks` に向ける（その場合、そのリポジトリでは関門は効かない）
  - TDD（テストが十分か）は reviewer が内容を読んで判定する。hook はテストファイルの有無を見ないが、失敗したテストの実行（コマンドと出力。implementer の分も）を git dir の `harness-red-log` に記録し、reviewer は RED をそこで確かめる（自己申告にしない。ARK-49）
  - 検証の証拠になるのは、リポジトリが宣言した全体の検証コマンド（`.harness-verify`、置けなければ `<git-common-dir>/harness-verify`）が、すべて同じ内容で単独で成功したときだけ（ARK-49 で宣言を必須にした。lint だけ・絞った実行は証拠にならない）。検証コマンドが後で失敗すると証拠は消える。サブエージェント内（hook の入力に `agent_id` がある）の検証は記録しない
  - 要件の写し（ARK-49）: 承認済みの要件と受け入れ条件を `harness-hook requirements-save`（標準入力から保存。置き場所は git dir の下でブランチごと、Claude Code の Write ツールでは書けないため）で置き、その内容を証拠の指紋に含める。写しが無いとコミットできず、書き換えると検証・受け入れ・レビューの証拠はすべて無効になる。acceptor と reviewer は依頼の文面ではなくここを読む（本人の転記や、後から条件を削ることを防ぐ）
  - 関門の対象: 上の「コード」（この repo の `.harness-code` は `config/*`・`shell/*`・`CLAUDE.md`）と、既存テストの変更・削除（テストを弱めて通すのを防ぐ。テストの追加だけなら対象外）。`.harness-code`・`.harness-verify` 自体の変更も対象
  - reviewer の報告は git dir の `harness-last-review` に保存し、`/review fix` は前回の版と未解決の指摘をそこから読む（メインの転記に頼らない）
- 計画は plan mode、L のレビュー補助は同梱 `/code-review`。自作しない
- 記録と記憶: 置き場所（Linear・CLAUDE.md・README・コミット・tinymemory の fact / session）の振り分けは `skills/wrap-up` の表。M/L の最後に `/wrap-up` が振り分けて保存する。作業の途中はコンテキストが溜まると区切りで session だけを保存させる（ARK-38）。tinymemory は端末ごとなので、別の端末で続けるための状態は Linear に書く。読み込みと整理（`/dream`）は tinymemory 側の仕組み
  - 区切りでの保存（ARK-38）: 前回の session の保存（`tinymemory save --type session`）からコンテキストが溜まったら、`harness-hook` の Stop が 1 回差し戻して `/tinymemory:remember` させる。コミットしたターンなら 30%、それ以外でも 60%（同じ起点から 1 回だけ）。使用量は transcript の最後の assistant の usage、ウィンドウは既定 100 万（`HARNESS_CONTEXT_WINDOW` で変える）。clear は自動化しない（デスクトップアプリでは clear 後に自動で再開できないため、CLI とそろえた）。compact・resume の後も settings.json の SessionStart で記憶を注入する
- 常時コストを増やさない: 新しい規則は CLAUDE.md に足す前に skill にできないか考える

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
- tmux は Homebrew から mise に移した（ARK-37）。以前から使っている mac では `brew uninstall tmux` で Homebrew 版を消す（`brew bundle` は消さない。残ると PATH 次第で版がずれ、クライアントとサーバーの版が合わなくなる）
- `config.toml` の後半はテーブル形式。**その後ろに `key = value` を書くとテーブルに入ってしまう**ので、通常のツールは前半に追加する
- tinymemory のプラグイン hook は PATH・`~/.local/bin`・`~/.cargo/bin` しか探さない（hook 文字列は変更不可）→ `install.sh` が `~/.local/bin/tinymemory` に shim を置く

### 使わないもの（決定済み）

conda / conda-forge / pixi（Python は uv）、システムや Homebrew の Python・Node を開発に使うこと（uv / fnm で管理）、Windows ネイティブ、superpowers（自作ハーネスを別途作成: ARK-30）
