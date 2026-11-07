# 全プロジェクト共通の指示

## 作業の哲学

優先順位は 正しさと堅牢さ > 読みやすさ > コードの少なさ > 速さ。なるべくシンプルに作業する:

- **要件の不明点**: 推測で進めない。設計・実装に入る前に質問し尽くし（または調べて根拠を示し）、完全に理解してから進む。要件が明確になった後の実装の判断は、止まらずに決めて進める
- **変更の量**: 目的に必要な最小の変更だけをする。頼まれていない機能・抽象化・設定項目・依存は足さない（コードの書き方と量の指示は、CC ではプラグイン ponytail が毎ターン入れる）
- **検証**: 目標を検証可能な形にして確認するまで繰り返す。テストは superpowers の TDD に従う。完了と言う前に検査を通し、結果を示す
- **リファクタ**: 無関係な箇所は触らない（気づいた不要なコードは伝えるだけ）。ただし**触った箇所は触る前より整った状態で終える**（TDD の REFACTOR）。それを超える整理は別 issue に切り出して提案する

開発の手順は superpowers の skill に従う（ここに手順を書かない）。ただし次の skill は、この指示の方法に置き換える:

| superpowers の skill | 代わりに |
| -- | -- |
| brainstorming | `/issue` の要件と受け入れ条件の合意 |
| using-git-worktrees | `/issue` が作る worktree（「Git」の節） |
| subagent-driven-development・executing-plans | 「モデルの割り当て」の表（タスクごとに実装と検証のサブエージェント） |
| requesting-code-review | `codex-review`（「レビュー」の節） |
| finishing-a-development-branch | `integrate`（「Git」の節）と `/wrap-up` |

そのまま使う: writing-plans（置き場は「Linear」の節）・test-driven-development・systematic-debugging・verification-before-completion・receiving-code-review・dispatching-parallel-agents・writing-skills・using-superpowers・diagnosing-superpowers。Linear の記録の手順は skill の `/issue`・`/wrap-up`（dotfiles）。

この指示は Claude Code と Codex の共通（dotfiles の `config/agents/AGENTS.md`）。以下は Claude Code の書き方で記す。Codex での読み替え:

- skill の呼び出し: CC は `/issue`、Codex は `$issue`
- 選択肢での質問: CC は AskUserQuestion、Codex は選択肢に番号を付けて尋ねる
- 会話の区切り: CC は `/clear`（herdr の中では handoff skill で自分で clear して続ける）、Codex は `/new`

## 規約

- 応答は日本語
- Python は `uv` で実行・管理する（`uv run`・`uv add`）
- ファイルは今の内容を読んでから編集・実行する（思い込みで変更しない）
- 長期記憶は tinymemory（全ツール共通）。作業の節目（タスクの完了、大きな寄り道の前、文脈が埋まる前）には頼まれなくても remember skill で保存する。issue の作業中の保存は中継の記憶: `--tags relay` を付け、タイトルを `ARK-nn` で始める（片づけは統合の後の `/wrap-up`）。セッション開始時の記憶ブロックが整理を促したら、ほかの作業の前に dream skill を実行する

## レビュー

レビューは Codex に任せる（`codex-review`。読み取り専用で、ファイルは変えない）。Codex は指摘を「直す」と「参考」に分ける。「直す」は、実際の使い方で起こる不具合、テストや検査や手順を弱める変更（テストが実際には確かめていない場合を含む）、設計の誤り（もっと単純で壊れにくい方法があるのに壊れやすい作りを選んでいる場合を含む）だけ。仕様の上ではありうるが実際には起こりにくい入力や環境は「参考」。FAIL の理由になるのは「直す」だけ（計画のレビューも同じ）:

- 計画書ができたら `codex-review plan <計画書>` を 1 回だけ実行し、「直す」の指摘を計画書に反映して実装に入る（計画のレビューはやり直さない）
- 実装が終わったら、ブランチ全体を `codex-review branch` でレビューする（ベースの既定は `origin/<integrate setup の base>`）。最後の行が `VERDICT: PASS` になるまで「直す」の指摘を直して実行し直す。2 回目からは、codex-review が前回の「直す」が直ったかと、その後の修正の差分だけを見させる（新しい粗探しはしない。rebase で履歴が変わったら全体を見直す）。2 往復で PASS にならなければ、統合せず `notify "<理由>"` で知らせて人を待つ
- 「参考」の指摘は直さず、作業中の issue の本文に書く（Backlog の issue に起こすかは `/wrap-up` で決める）

## モデルの割り当て

Claude Code だけ（Codex には適用しない）。メインのセッション（settings.json の既定の Opus 5.5 high）は、人との会話、要件と受け入れ条件の合意、取りまとめ、Linear・git・テストを受け持つ。ほかのフェーズは独立したエージェントに任せ、Agent ツールに次の `model`・`effort` を渡す:

| フェーズ | 担当 | model・effort |
| -- | -- | -- |
| 設計・計画 | サブエージェント | `opus`・`xhigh` |
| 計画のレビュー | Codex（`codex-review plan`） | gpt-6.1-sol xhigh |
| 実装（plan のタスクごと） | サブエージェント | `sonnet`・`high` |
| 検証（受け入れ条件を実際に動かす） | 実装と別のサブエージェント | `opus`・`high` |
| ブランチのレビュー | Codex（`codex-review branch`） | gpt-6.1-sol xhigh |
| 広い検索 | Explore | `model: haiku`（渡さないとメインのモデルになる） |

- 依頼には Linear の本文（要件・受け入れ条件）と読むファイルを渡す
- Agent の description は役割名とコロンで始める（例: `plan: 計画を書く`）。役割名は 設計・計画が `plan`、実装が `impl`、検証が `verify`、広い検索が `explore`（herdr の中では agent-pane がサブエージェントの pane の名前に出す）
- サブエージェントは人に質問できない。設計の役は迷う点を推測で埋めず、質問として返させる。メインが人に聞き、答えを渡して続けさせる

## Git

1 つの issue に短命なブランチを 1 つ切り、worktree の中で作業する。最上位のブランチ（main や develop。以下 `<最上位>`）は常にテストが通る状態に保つ:

- リポジトリごとに一度 `integrate setup` で種類（kind）・`<最上位>`（base）・テストのコマンド（test）を決める（設定は `~/.config/integrate/repos/`。リポジトリの外）。`integrate setup --show` で今の設定を見る。無ければ `integrate setup` を引数なしで実行して推測を見て、ユーザーに選択肢で確かめてから `--kind`・`--base`・`--test` で渡す。既にある設定の上書き（`--force`）は人が端末で行う。設定が無いと Claude Code では編集をフック（`integrate-hook`）が止める
- kind:
  - `bare`（サーバーの bare）・`github`（自分の GitHub）: 一人の開発。integrate が関門の後に `<最上位>` へ直接 push する（PR は作らない）
  - `pr`（書き込み権限のあるチームの GitHub）: integrate はブランチを push して `<最上位>` に向けた PR を作るところまで。マージはチーム。PR を出した後は rebase せず、修正はコミットを足して integrate をやり直す（`<最上位>` が進んで止まったら人に聞く）
- ブランチは `feature/<作業内容>`（英小文字とハイフン）。worktree は元のチェックアウト（`git worktree list --porcelain` の先頭。以下 `<元>`）の下に作る: `git -C <元> fetch` の後、`git -C <元> worktree add --no-track -b feature/<作業内容> <元>/.worktrees/<作業内容> origin/<最上位>`。作るのは `/issue`
- コミット: 構造の変更（`refactor:`）と振る舞いの変更（`feat:`・`fix:`）を別にする。テストと実装は同じコミットにし、どのコミットでもテストが通る状態にする。メッセージは英語で最大 3 行（1 行目は型付きの件名、命令形、50 文字以内。必要なら空行の後に理由を 1 行）
- Linear と superpowers の情報（issue 番号・題・URL、受け入れ条件の番号、プロジェクトや文書の名前、spec・plan の中身やパス、Task の番号、skill の名前）は、リポジトリに入るもの（コード・コメント・テスト・文書・指示ファイル・コミット・PR・ブランチ名）に書かない（個人の作業の道具で、プロジェクトに関係ないため）。理由が要る所には理由の文を書く（仕組みや設計の判断を、コードから分かる形で README などに書くのは構わない）。issue 番号は integrate が止める。dotfiles だけは Linear・superpowers の使い方の説明と設定を書いてよい（実際の番号は書かない）
- 統合の前の順番: `git fetch` → `git rebase origin/<最上位>`（`bare`・`github` は毎回、`pr` は PR を出す前だけ）→ `codex-review branch` → `integrate`（setup の test は integrate が実行する。前に同じテストを実行しない）。レビューの後に変えたら、レビューからやり直す
- 統合は `integrate` だけで行う（`git push`・`gh pr merge` を直接使わない。Claude Code では禁止）。integrate は関門（一覧は dotfiles の `bin/integrate` の先頭のコメント。安いものから確かめ、テストは最後）を確かめ、1 つでも欠けたら統合せず `notify` して止まる。直せる理由だけ直してレビューからやり直し、直せなければ人を待つ。秘密か issue 番号で止まったら、含むコミットを作り直す（後のコミットで消しても履歴ごと push される）。テストや検査を弱める必要があれば、理由を書いて人に `integrate --human-approved` を頼む
- `<最上位>` への push が早送りでなく拒否されたら（`<最上位>` が進んだ）、fetch・rebase・テスト・レビューからやり直す。bare は早送りでない push とブランチの削除を拒む（`config/git/config`）ので、feature ブランチは bare に push しない
- 強制 push はしない

## Linear（タスク管理）

会話はあとから見返せないので、**後から Linear だけ見れば作業内容と状況が分かる**状態を保つ。遠慮せず issue を作り、状態を更新してよい。

- 作業の起点に issue が無ければ作る（数分で終わる小さな修正だけは任意。issue が無ければコミットメッセージが記録）。issue があれば `/issue ARK-nn` で始める（「ARK-nn をやって」と言われたときも）
- 要件と受け入れ条件、設計の決定は、コメントではなく issue の**本文**に書く（最新が 1 か所で分かるように。本文が正本）。計画（plan）の全文はファイルにして、元のチェックアウトの `<元>/.superpowers/plans/<ARK-nn>-<名前>.md` に置き（worktree の中に置くと worktree の削除で消える。`.superpowers/` は dotfiles のグローバル gitignore で全リポジトリから除外）、本文にはそのパスを書く。リポジトリに `docs/superpowers/` のファイルは作らない
- 状態: 着手で In Progress。コミット済み・未マージの間はそのまま（コメントに「未マージ」と書く）。マージした、または統合しないと決めた後に Done（統合の判断と一緒に確認してよい）。手を止める理由があれば Blocked や Backlog に戻す
- コメントは節目だけ: 要件・計画の合意、方針変更、詰まった点、途中で止めるとき（状態と次の手順。tinymemory は端末ごとなので、別の端末で続けるにはここが要る）、完了（統合の前に、作業ブランチの上で `/wrap-up`。コメントはコミットと、検証のコマンドと結果だけ。決定と参考は本文に書く。「Git」の節の方法で統合するより先。統合の後にもう一度 `/wrap-up` で片づける）
- 子 issue は、セッションやブランチをまたぐ作業に分けるときだけ作る。1 つのブランチで終わる内訳は、本文のチェックリストに書く
- 将来やる / 見送ったことも issue に残す（Backlog）
- Linear が使えない環境では、issue の代わりに `.superpowers/tasks/<短い名前>.md`（`.superpowers/` はグローバル gitignore で除外され、リポジトリに入らない）に、同じ見出し（要件・受け入れ条件・設計・計画・経過）で書く

## スクリーンショット

ユーザーが「スクショ」「スクリーンショット」「今撮った画像」などと言ったら、WSL では Windows のピクチャの `Screenshots`（Windows のスニッピングツールが撮影のたびに保存する）の最新ファイルを、ファイルを読むツールで見る。ユーザー名は固定せず glob で書く。次のコマンドが新しい順にパスを出す:

```sh
ls -t /mnt/c/Users/*/Pictures/Screenshots/*.png | head
```

- ファイル名は `スクリーンショット YYYY-MM-DD HHMMSS.png`（保存時刻。空白を含むのでパスは引用する）。「さっきの 2 枚」なら新しい順に 2 枚。時刻の指定があればファイル名で探す
- WSL 以外の端末にはスクショを見る手段が無い（どこからも転送していない）。そう伝える
