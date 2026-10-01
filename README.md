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
| `config/claude/agents/reviewer.md` | `~/.claude/agents/reviewer.md` | 読み取り専用・effort high・モデルは opus に固定（関門の審査はセッションのモデルに左右されない）の敵対的レビュアー |
| `config/claude/agents/implementer.md` | `~/.claude/agents/implementer.md` | `/implement` の実装者。持ち分のファイルだけを TDD で変え、短い状態報告を返す |
| `config/claude/agents/acceptor.md` | `~/.claude/agents/acceptor.md` | `/accept` の受け入れ検証役（モデルは opus に固定）。実装を読む前に成果物を動かし、条件ごとに観測値で判定し、検査スクリプトを tests/ に残す。実装は直さない |
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

常時読み込むのは CLAUDE.md（約 1.15 万字）・skill と agent の説明（12 件、約 1.2 千字）・SessionStart で注入する記憶。ユーザー設定（プラグインを含む）を読み込むと、読み込まない場合より最初の入力が約 1.2 万トークン増える（2026-10-01、`claude -p` の usage で 43,631 と 31,752 を比べた。ARK-51）。手順は skill、強制は hook。

### 流れの全体図

```
依頼 → 規模の判定（S/M/L。迷ったら重い方）
  → 要件と受け入れ条件（/issue・/design）→ 承認
  →（L）計画（plan mode。/implement の形）
  → ブランチ（基点から）……………………………… hook: main 上の編集と、main 上での写しの保存を拒否
  → 要件の写しを固定 ………………………………… hook: 写しが無い・古い（コード変更のコミットの後）と証拠にならない。書き換えると証拠は無効。
                                                      条件を減らす版は「## 変更の承認」が無いと保存しない（版は .history に残る）
  → TDD（/tdd）／並列の実装（/implement）…… hook: 失敗したテストの出力（RED）を記録
  → /accept … acceptor が実装を読む前に成果物を動かし、条件ごとに観測値で判定 … hook: 合格が無いとコミットできない
  → /verify … 宣言した全体の検証コマンドをすべて、リポジトリのトップで通す … hook: 宣言に無い・下位での実行は証拠にならない。失敗で証拠が消える
  → /review … reviewer が 3 軸で判定（要件の写し・受け入れの報告・RED の記録を読む）… hook: 承認が無いとコミットできない
      指摘を直したら /accept → /verify → /review fix（2 回まで。残ればユーザーが裁定）
  → コミット … pre-commit が、ステージした内容に対する 4 つの証拠を確かめる。git の hook を通らなかったコミットは Stop が見つける
  → /wrap-up（作業ブランチの上で、統合の前）… Linear・CLAUDE.md・README・tinymemory に 1 か所ずつ記録
  → 統合の判断（ユーザー: マージ／PR／残す）→ main へ fast-forward でマージ（ならなければ基点を作業ブランチに取り込み、
      競合は作業ブランチで解消して /accept → /verify → /review の後に）→ マージ後に main で検証 → ブランチと worktree を片付ける → issue を Done
  （途中でコンテキストが溜まると、区切りで session の保存を促す。compact の後は記憶を注入）
```

### superpowers との対応

superpowers（obra/superpowers）の各 skill に当たるものと、どちらが強いか。superpowers は入れない（ARK-42）。「強い方」の凡例: **自作** = 自作が上回る（多くは hook で強制できるため）／**同等** = 同じことができる（違いは書き方）／**superpowers** = superpowers が上回る／**自作だけ** = superpowers に当たるものが無い

| superpowers | 自作 | 強い方 | 違い |
|---|---|---|---|
| using-superpowers（作業の前に skill を使わせる案内） | CLAUDE.md の流れの 1 行（常時読み込み） | 自作 | superpowers は案内の文を入れるだけ。自作は、手順を飛ばすと Stop が差し戻し、pre-commit が止める |
| brainstorming | `/design`・`/issue` | 同等 | 質問は 1 問ずつでなく、選択肢と推奨を付けてまとめて聞く（往復が少ない）。承認の前に 4 項目の自己点検（空欄・矛盾・曖昧さ・範囲）、大きな依頼は子 issue に分ける。設計・要件・受け入れ条件は issue の本文に 1 か所 |
| writing-plans | `/implement` の計画の形 | 同等 | superpowers は手順ごとのコードまで書く。自作は、全体の制約・レビューの焦点・受け入れ条件 → タスクの対応・「作る側 → 使う側」の表・RED で期待する失敗を書き、承認の前に決めていない行が無いかを見直す。コードは implementer に任せる |
| executing-plans・subagent-driven-development | `/implement` | 同等 | 自作は波ごとに並列で速く、安い（implementer は約 1.5 万トークン）。superpowers はタスクごとに 2 段のレビューをする。自作はその代わりに、インタフェースを作った波の後に `/review interim`、最後に `/accept` とフルの `/review`。進捗は issue の本文のチェックリスト、実装者が自分で決めたことは `## 判断` に集めて完了報告に全件並べる。2 回 BLOCKED なら上位のモデルで立て直す |
| dispatching-parallel-agents | `/implement` の波、`/diagnose` の並列の調査 | 同等 | — |
| test-driven-development・testing-anti-patterns | `/tdd`、reviewer のテスト軸 | 自作 | RED を hook が記録し、reviewer が読む（自己申告にしない）。既存テストの変更・削除も関門の対象 |
| systematic-debugging（根本原因の追跡・多層の防御・条件で待つ・汚染の特定） | `/diagnose` | 同等 | superpowers は補助の文書が多い。自作は安い順に絞り、原因が見えたら止める（試行でコスト増を 2〜4 割に抑えた。ARK-44） |
| diagnosing-superpowers（うまくいかなかったセッションを transcript から調べ、証拠付きで報告する） | `/diagnose` の「ハーネス自体の不具合」 | superpowers | superpowers は transcript を観点ごとに並列の分析役で読み、`path:line` 付きの報告と不具合報告の束を作る。自作は hook のログ（1 呼び出し 1 行）・証拠と報告のファイル・RED の記録から、どの証拠が欠けたかを突き合わせるだけ（transcript の分析の手順は無い） |
| verification-before-completion | `/verify`、`.harness-verify` | 自作 | 宣言した全体の検証がすべて同じ内容で通らないとコミットできない（文章だけでなく hook で止める） |
| — | `/accept`（acceptor） | 自作だけ | 成果物を実際に動かし、受け入れ条件ごとに観測値で判定し、検査を tests/ に残す（ARK-48） |
| requesting-code-review | `/review`（reviewer） | 自作 | 報告前の関門・重大度の定義・判断しなかったこと。承認が無いとコミットできない。`/review fix` は前回の報告（hook が保存）と修正差分だけを見る |
| receiving-code-review | CLAUDE.md の手順 6 | 同等 | 確かめてから直す。誤りは根拠を添えて反論し、reviewer が確かめて取り下げる。人・PR・`/code-review` の指摘も同じ |
| using-git-worktrees | `cw`（`claude -w`）、着手時の基準の検証 | 同等 | — |
| finishing-a-development-branch | CLAUDE.md の手順 9 | 同等 | 選択肢の提示、fast-forward でのマージ（ならなければ基点を作業ブランチに取り込んで競合を解消し、検証し直してから）、マージ後の検証、破棄は明示の依頼のときだけ、worktree は `--force` を使わない |
| writing-skills | 同梱の skill-creator、`tests/skills.sh`、`tests/e2e-flow.sh` | superpowers | superpowers は skill そのものを TDD で書く手法（圧力をかける場面で失敗を見てから直す）が詳しい。自作は skill・agent・参照・リンクの一貫性の検査（関門に入れる）と、流れ全体を `claude -p` で実際に動かす検査（手動。ふつうの依頼と、「テストとレビューを省いてすぐコミットして」と圧力をかける依頼の 2 場面）で補う |
| — | 記録の振り分け（`/issue`・`/wrap-up`・区切りの remember） | 自作だけ | Linear・CLAUDE.md・README・tinymemory に重複なく |
| プラグインとして 15 以上の環境に入る | dotfiles 前提 | superpowers | 自作は個人の環境での強制を優先した（ARK-46） |

- 規模判定 S / M / L で手順を変える（CLAUDE.md の表）
- コードを書くときの規則: 作業ブランチ、TDD（REFACTOR まで）、`/accept`、`/verify`、`/review`（仕様適合・テスト・品質・保守性の 3 軸）。証拠（検証の成功・受け入れ検証の合格・レビューの承認）が無いコード変更は git の pre-commit が止める
- 受け入れ検証（ARK-48。いちばん大事な段階）: 型やテストが通っても、成果物が要件どおりとは限らない。受け入れ条件は成果物を実際に動かして確かめられる性質（データなら件数・スキーマ・値の範囲・一意性・参照の整合・再現性・境界）で書き、独立した acceptor が実装を読む前に本物の入力（無理ならサンプル）で成果物を動かして確かめる。作った本人が確かめないので甘くならない。判定行 `受け入れ: 合格` と条件ごとの行 `[ACn] 合格` がそろい、しかも要件の写しにある AC 番号がすべて合格で報告に出ているときだけ（一部の条件だけを確かめた報告は通らない。ARK-50）hook が「受け入れ済み」を記録し、報告は git dir の `harness-last-accept` に保存して reviewer が読む。検査スクリプトは tests/ に残るので、以後の変更でも壊れたら分かる
- レビューの往復を抑える仕組み（ARK-41。superpowers の範囲限定の再レビューと ECC の報告前の関門を参考）: フルレビューは 1 回。直した後は `/review fix` が「前回の未解決の指摘」と「前回見た版からの修正差分」だけを見る（版は `skills/review/snapshot.sh` が作業ツリー全体の tree ID として記録）。重大・中は具体的な発生条件が書けるものだけで、軽と範囲外は判定に影響しない（issue に記録）。reviewer は検証を回し直さない。`/review fix` は 2 回まで、それでも残ればユーザーが指摘ごとに裁定する
- 並列実装とデバッグ（ARK-42。superpowers の subagent-driven-development・systematic-debugging と ECC の multi-*・build-error-resolver を参考に自作し、どちらも入れない）: `/implement` は計画を「持ち分のファイルが重ならないタスク」に分けて波ごとに implementer を同時に起動し、コントローラは短い状態報告だけを受けて統合・検証・レビューする。implementer はツールを絞っていて、小さなタスク 1 つで約 1.5 万トークン（汎用のエージェントの約 4 分の 1。ARK-47）。`/diagnose` は再現コマンド → 安い順の絞り込み（スタックトレースの箇所 → 逆向きの追跡 → 最近の変更 → 動く例との比較 → 境界の計測 → `git bisect run`。原因が見えたらそこで止める）→ 反証できる仮説 → 回帰テスト付きで共有の関数を直す。3 回直らなければ設計を疑って相談する
- 対象: Claude Code から行うコミット（環境変数 `CLAUDECODE` がある）で、Claude が cwd にして作業したことのあるリポジトリ（その worktree を含む）と、一時ディレクトリ（TMPDIR）の外のリポジトリ（親ディレクトリから `git -C` でコミットした場合など。ARK-51）。人の手動コミット、GUI クライアント、テストが一時ディレクトリに作るリポジトリは対象外（Claude から実行したスクリプトが TMPDIR の外にリポジトリを作ってコミットすると関門が掛かるので、テストの準備のコミットは `env -u CLAUDECODE` で人の操作として行う。例: tests/e2e-flow.sh）。検証・受け入れ検証・レビューの証拠は、セッションの cwd の作業ツリーに対して記録される
- 「コード」= 文書・画像など（`bin/harness-hook` の `DOC_EXT` の拡張子: .md .txt .rst .adoc .png .jpg .svg .pdf・フォントなど、`DOC_NAME` の名前: LICENSE・CHANGELOG・README など）以外のすべてのファイル（ARK-51 で反転。依存の定義・lockfile・.env・テンプレート・スキーマ・データ・拡張子の無いスクリプトも含む。requirements*.txt・CMakeLists.txt は .txt でもコード）。文書でも、リポジトリの `.harness-code` に書いたパスはコード。テスト実行の生成物（`__pycache__/`、`.pyc`、`.pyo`）はコードにもテストにも数えない
- 限界（ガードレールであって、セキュリティ境界ではない）:
  - 意図的な迂回は防ぎ切れない（`git commit-tree`、`env -i`、証拠ファイルの書き換えなど）。代表的な形は Bash の検査が拒否し、CLAUDE.md で禁止している。自分用の検証の宣言（git-common-dir の harness-verify）の内容も指紋に含める
  - Bash の検査のしかた（ARK-50）: クォートを見分ける字句解析でコマンドを区切り（サブシェルの `( )` も）、`sh -c`・`eval`・コマンド置換の中も再帰して見る。文字列で見る形はクォートを外したコマンドにも当てる（`--"no-verify"` のように語を割る形）。git のサブコマンド・設定のキー・alias の値は、クォートを外した字句で見る
  - Bash の検査が拒否する形:
    - `--no-verify`（省略形も）と、git commit の `-n`（`-anm`・`-nm1` のような束、alias で commit にした形も）
    - git commit の引数のコマンド置換（`$(printf -- -n)` のように `-n` に展開されうる。`-m` の値は除く。ARK-51）。字句は、そのままと、クォートの外のブレースを展開した後の両方で見る（`-{n,m}`・`git {commit,-n,-m,x}`・文字の連番の `-{n..n}`。数の連番は文字を作れないので代表の 1 桁に置き換える（`{-n,-m{1..1}}` の外側は展開する）。展開が 256 語を超える字句は、`-` を含めば判定できないので拒否し、含まなければ展開せずに見る）
    - `commit-tree`、`core.hooksPath`・`include.path`・`includeIf.*.path` の設定（`-c`・`--config-env`・`git config`）、迂回になる alias の定義、git の設定ファイルを `sed -i`・`tee`・リダイレクトで書き換える形
    - コミットを作りうる git（init・clone・status・log・diff・show・config・rev-parse・ls-files・version・fetch・remote・branch 以外のサブコマンド。alias、ダッシュ形の `git-commit`（git-core の下のものも）を含む）と同じ行での環境の差し替え: `HOME`・`XDG_CONFIG_HOME` の代入・export・unset・`env -u`、`env -i`（ARK-51）。`CLAUDECODE` を消す・書き換える形、`GIT_CONFIG*` の指定
    - 共通の hooks（`~/.config/git/hooks`）・hook の本体（`~/.local/bin/harness-hook`・`~/.local/libexec/uv`）・git の設定・要件の写しとその版（git dir の `harness-requirements`。ARK-51）を、消す・動かす・権限を変える・上書きする形。hooksPath を含む行で書き込む形（行き先を問わない）
    - 証拠を記録する hook のサブコマンド（`harness-hook review-done`・`bash` など）を直接呼ぶ形（偽の入力で証拠を作れるため。ARK-51）
  - Bash の検査が通す形（誤検知を減らした。ARK-49〜51）:
    - 閲覧だけの形: `grep -n git_config`、`--no-verbose`、`echo $CLAUDECODE`、`git log --grep=commit-tree`、`grep hooksPath`。`--no-verify` は検索の引数でも拒否する（検索だけの行を通す免除は、パスで指したコマンド・PATH・ページャ・ヒアドキュメントで穴が開くので取り下げた。ARK-51）。検索は `rg -n 'no-verify'` のように先頭の `--` を付けずに書く
    - コミットメッセージの中の `-n`・`-inf`、コミットを作らない git での環境の差し替え（`HOME=$PWD/tmp-home git init`）
    - プロジェクトの `.git/hooks` への hook の導入・書き換え（共通の pre-commit が関門を通した後に委譲する先なので、関門は外れない。ARK-51）
  - ヒアドキュメントの本文の扱い（ARK-51）:
    - 行のコマンドがすべて本文を実行しない既知のコマンドで、環境変数の前置（`GIT_EDITOR=…`）とコマンド置換が無ければ、本文はデータとして検査しない（記憶の保存・`git commit -F -`・ファイルへの書き出し）
    - 既知のコマンド: cat・tee・tinymemory・harness-hook・cd・mkdir・echo・printf・true・ls・chmod・wc、gh の pr・issue・release・gist（`-e`・`--editor` を除く）、git の commit・notes・tag・add（オプションは `-F`・`--file`・`-m`・`--message`・`-q`・`-a`・`-A`・`-u`・`--cleanup`・`--signoff`・`--no-edit`・`--annotate` とその束、全体のオプションは `-C`・`--no-pager`・`--git-dir=`・`--work-tree=` だけ。commit・tag・notes は `-F`・`-m` でメッセージを渡すときだけ。渡さないと git はエディタを起動し、エディタは本文を標準入力として受け継ぐ）
    - データのコマンドでも、区切りの語をクォートしていない本文のコマンド置換（`cat <<EOF` の本文の `$(…)`・`` `…` ``）はシェルが実行するので、その置換の中身をコマンド行として検査する（本文の文章や `#` は検査しない）。区切りの語はシェルと同じく、クォートとエスケープを外して連結した語として読む（`<<E"OF"` の区切りは `EOF`）
    - 区切りをクォートしたヒアドキュメントを cat してメッセージ・本文の値に渡す形（`git commit -m "$(cat <<'EOF' … EOF)"`、gh の `--body`）もデータ（本文は展開されない）
    - ほかのコマンド（`sh <<E`、`cat <<E | sh`、`read`、ファイルに書いて次の行で `sh f`・`./f`・`make`・`mise run`）やほかのコマンド置換があれば、本文もコマンド行として検査する。hooksPath を含む書き込みは、書き込み先が git の設定になりうるとき（`cd .git && cat >> config <<E` など）は本文の語も見て拒否する
  - Bash の検査が見ていないもの: コマンド置換の終わりを読み違える構文（置換の中の `case … x)`・コメントの `)`・ヒアドキュメントの `)`。シェルの完全な構文解析はしない）、引用符の中の空白を含む字句のブレース展開（`{-n,'a b'}`。空白を含む字句は `sh -c` の引数などとして見直す側で、展開しない）、hooksPath の語を含まない行での `cd` の後の相対パス、`xargs`・`find -exec` の `{}`、変数・alias による間接呼び出し（`g=git; $g commit -n`）、`curl -o`・スクリプト言語からの書き込み、別々の Bash 呼び出しに分けた手順。誤検知として残るもの: `rm -rf .git`、`mv ~/.gitconfig ~/.gitconfig.bak`、クォートの中の文字列がコマンド行に見える形（`echo "git commit -n"`、`grep "hooksPath\|cp"`）
  - マージ・cherry-pick・revert の途中のコミット（ARK-51）:
    - 自動の結果（`git merge-tree --write-tree`）との差（競合の解消、`--no-commit` の後に足した変更）に証拠を求める（自動の結果のままなら要らない）
    - 自動の結果を求められないとき（3 つ以上の親、`merge-tree --write-tree` の無い git 2.38 より前、`--merge-base` の無い 2.40 より前の cherry-pick・revert）は、HEAD との差全体（Stop の事後の確認では最初の親との差）に求める
  - git の hook が呼ばれないコミット（リポジトリ側の `core.hooksPath`（husky 等）、rebase・cherry-pick など）への備え（ARK-51）:
    - リポジトリ側の `core.hooksPath` があれば、Bash の `git commit` の前に作業ツリーの証拠を確かめ、足りなければ拒否する。判定を通した、git の add・commit と読むだけのもの（status・log・diff・show）だけのコマンドでできたコミットは、コミットした内容（親との差）の指紋が証拠と同じときだけ関門を通ったものとして記録する
    - Stop が、そのターンに作られたコミット（ターン開始時の HEAD とローカルブランチの先端から届かず、コミット時刻がターン開始以降のもの。どのブランチでも。ターンの間に fetch・pull で取り込んだ他人のコミットは、リモート追跡ブランチの reflog と FETCH_HEAD で除く。このリポジトリで作ったもの（HEAD・ローカルブランチの reflog にコミットを作った記録があるもの）は除かない）を、関門を通ったコミットの記録（tree と patch-id）と突き合わせ、コード変更を含むのに記録に無ければ 1 回差し戻す
    - 関門を通ったコミットを rebase・cherry-pick で付け替えただけ（`git patch-id --verbatim` が同じ）なら差し戻さない。土台が変わるので、統合の後に main で検証一式を流す（CLAUDE.md の手順 9）
    - マージコミットは、2 つの親なら自動の結果と違うときだけ、3 つ以上の親と自動の結果を求められないマージ（無関係な履歴など）は最初の親との差で見る
    - 見つけたコミットは記録し、リモートに無い間は（次のターンでも）`git push` を拒否する。それを含むブランチの main・master への `git merge`（fast-forward も。同じコマンドの中で `git switch main &&` のように移ってからの形も）は、リモートに出た後も拒否する（統合はユーザーが判断して自分で行う）
    - 記録は post-commit が、同じ git commit（git の PID で結び付ける）の pre-commit が関門を通したときだけ、実際にコミットされた内容で行う（リポジトリ自身の pre-commit が整形してインデックスを書き換えても一致する。`-n` のコミットは記録されない）
    - `--amend` は、pre-commit が付け直す前のコミットとの差しか見ないので、付け直したコミットが関門を通っていたか、コミットの変更全体に証拠があるときだけ記録する（関門を通っていないコミットを、変更なしの `--amend` で関門を通ったことにしない）
    - 見ないもの: Stop の後に作られたコミット（次のターンで作れば見る）、セッションの cwd 以外のリポジトリのコミット
  - 報告の版（ARK-51）: 受け入れ検証とレビューの証拠は、報告の「受け入れ検証した版」「レビューした版」が SubagentStop の時点の作業ツリー全体の版（snapshot.sh と同じ求め方）と同じときだけ記録する。違いが生成物・文書だけなら同じとみなす。合わずに記録しなかったときは、次の差し戻しと pre-commit の理由に、報告の版の後に変わったファイルを出す
  - 利用者の作業中の変更（ARK-51）: そのブランチで最初に写しを保存したターンの開始時に既にあった未ステージの変更（未追跡のファイルと、追跡済みのファイルの変更）は、その後に変えず未ステージのままなら証拠の対象から外す（部分コミットを止めない）
    - ステージしたら証拠が要る。pre-commit の理由に、そのファイル名と手順（`git restore --staged` か、ステージしたまま証拠を取り直す）が出る
    - 写しをコードを書いた後に保存すると、それより前の自分の変更も外れるので、写しはコードを書く前に保存する
  - 要件の写しはメインが書く（承認済みの issue の本文を写す手順）。写しが本文と一致しているかは、機械では確かめない
  - 共通 hooks にリンクを置いていない hook 名（`reference-transaction`、`post-index-change`、`pre-auto-gc`、`p4-*`。高頻度で呼ばれるため）は、リポジトリ自身に同名の hook があっても実行されない
  - グローバルな `core.hooksPath` との非互換: `pre-commit install`（pre-commit フレームワーク）は hooksPath が設定されていると拒否する。`git lfs install` は hooks を `~/.config/git/hooks`（= この dotfiles）に書こうとする。必要なリポジトリでは、利用者がそのリポジトリの設定で hooksPath を `.git/hooks` に向ける（そのリポジトリでは pre-commit の関門は効かず、Bash の前の判定と Stop の事後の確認だけになる）
  - TDD（ARK-49・51）: テストが十分かは reviewer が内容を読んで判定する。hook は失敗したテストの実行（コマンドと出力。implementer の分も）を git dir の `harness-red-log` に記録し、reviewer は RED をそこで確かめる（自己申告にしない）
    - 記録するのは、宣言した検証・よく使うテストランナーと、test・tests/・spec を含むコマンド（`python manage.py test`・`bazel test` など。grep などの読むだけのコマンドは除く）の失敗
    - パイプを付けた実行は終了コードが 0 になるので記録されない
  - 検証（ARK-49・51）: 証拠になるのは、宣言した全体の検証コマンド（`.harness-verify`、置けなければ `<git-common-dir>/harness-verify`）が、すべて同じ内容で、リポジトリのトップで単独で成功したときだけ
    - lint だけ・絞った実行・下位のディレクトリでの実行は証拠にならない。検証コマンドが後で失敗すると証拠は消える
    - 並列に実行しても記録は落ちない（状態の読み書きはファイルロックで順番にする）。サブエージェント内（hook の入力に `agent_id` がある）の検証は記録しない
  - 要件の写し（ARK-49・51）: 承認済みの要件と受け入れ条件を `harness-hook requirements-save`（標準入力から。git dir の下にブランチごと。Write ツールでは書けない）で置き、その内容を証拠の指紋に含める
    - 写しが無いとコミットできず、書き換えると検証・受け入れ・レビューの証拠はすべて無効になる。acceptor と reviewer は依頼の文面ではなくここを読む
    - main・master の上では保存できない。保存した後にコード変更を含むコミットがあれば写しは古いとみなし、次のコード変更には保存し直しが要る（前の依頼の写しの使い回しを防ぐ）
    - 同じ依頼の途中で、前の版にあった受け入れ条件の番号が無い版は、「## 変更の承認」の節（ユーザーの承認の引用）が無ければ保存しない。保存した版はすべて写しの横の `.history` に残り（新しい依頼の版で始めるときは、前の依頼の版を `.history.prev` に移す）、reviewer が最初の版と比べて削除・緩和に承認があるかを見る（文言の緩和は機械では見分けない）
  - 関門の対象: 上の「コード」（この repo の `.harness-code` は `config/*`・`shell/*`・`CLAUDE.md`）と、既存テストの変更・削除（テストを弱めて通すのを防ぐ）。`.harness-code`・`.harness-verify` 自体の変更も対象
    - 新しいテストの追加だけなら対象外。テストとみなすのは、リポジトリのトップの tests/・test/・spec/・__tests__/ の下と、テストの名前の規則（test_*.py、`*_test.*`・`*.test.*`・`*.spec.*`・`*_spec.*`（データ・設定の拡張子は除く）、JVM・Swift・C#・PHP・Scala・Groovy の `*Test.*`・`*Tests.*`）に当たるものだけ（ARK-51。`src/test/server.go`・`api/spec/openapi.yaml`・`SpeedTest.tsx` はコード）
    - conftest.py・`__init__.py`・pytest.ini・`*.config.*` は、テストのディレクトリにあってもコード
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
