# 全プロジェクト共通の指示

## 作業の哲学

優先順位は 正しさと堅牢さ > 読みやすさ > コードの少なさ > 速さ。なるべくシンプルに作業する:

- **要件の不明点**: 推測で進めない。設計・実装に入る前に質問し尽くし（または調べて根拠を示し）、完全に理解してから進む。要件が明確になった後の実装の判断は、止まらずに決めて進める
- **変更の量**: 目的に必要な最小の変更だけをする。頼まれていない機能・抽象化・設定項目・依存は足さない（コードの書き方と量の指示は、CC ではプラグイン ponytail が毎ターン入れる）
- **検証**: 目標を検証可能な形にして確認するまで繰り返す。テストは superpowers の TDD に従う。完了と言う前に検査を通し、結果を示す
- **リファクタ**: 無関係な箇所は触らない（気づいた不要なコードは伝えるだけ）。ただし**触った箇所は触る前より整った状態で終える**（TDD の REFACTOR）。それを超える整理は別 issue に切り出して提案する

開発の手順（設計・計画・TDD・レビュー）は superpowers の skill に従う（Pi では同じ役割の bigpowers の skill）。ここには手順を書かない（二重にしない）。統合は下の「Git」の節の方法で行う（superpowers の finishing-a-development-branch は使わない）。Linear の記録の手順は skill の `/issue`・`/wrap-up`（dotfiles）。

この指示は Claude Code・Pi・Codex の共通（dotfiles の `config/agents/AGENTS.md`）。以下は Claude Code の書き方で記す。ツールごとの読み替え:

- skill の呼び出し: CC は `/issue`、Pi は `/skill:issue`、Codex は `$issue`
- 選択肢での質問: CC は AskUserQuestion、Pi は ask_user_question、Codex は選択肢に番号を付けて尋ねる
- 会話の区切り: CC は `/clear`、Pi と Codex は `/new`

## 規約

- 応答は日本語
- Python は `uv` で実行・管理する（`uv run`・`uv add`）
- ファイルは今の内容を読んでから編集・実行する（思い込みで変更しない）
- 長期記憶は tinymemory（全ツール共通）。作業の節目（タスクの完了、大きな寄り道の前、文脈が埋まる前）には頼まれなくても remember skill で保存する。issue の作業中の保存は中継の記憶: `--tags relay` を付け、タイトルを `ARK-nn` で始める（片づけは統合の後の `/wrap-up`）。セッション開始時の記憶ブロックが整理を促したら、ほかの作業の前に dream skill を実行する

## レビュー

レビューは Codex に任せる（`codex-review`。読み取り専用で、ファイルは変えない）:

- 計画書ができたら `codex-review plan <計画書>` を実行し、指摘を反映してから実装に入る
- 実装が終わったら、ブランチ全体の最終レビューは superpowers の requesting-code-review でなく `codex-review branch [ベース]` で行う。最後の行が `VERDICT: PASS` になるまで直して実行し直す
- 2 往復で PASS にならなければ、統合せず `notify "<理由>"` で知らせて人を待つ

## Git

1 つの issue に短命なブランチを 1 つ切り、worktree の中で作業する。main は常にテストが通る状態に保つ:

- ブランチは `feature/<作業内容>`（英小文字とハイフン）。worktree は元のチェックアウト（`git worktree list --porcelain` の先頭。以下 `<元>`）の下に作る: `git -C <元> fetch` の後、`git -C <元> worktree add --no-track -b feature/<作業内容> <元>/.worktrees/<作業内容> origin/main`。作るのは `/issue`
- コミット: 構造の変更（`refactor:`）と振る舞いの変更（`feat:`・`fix:`）を別にする。テストと実装は同じコミットにし、どのコミットでもテストが通る状態にする。メッセージは英語で最大 3 行（1 行目は型付きの件名、命令形、50 文字以内。必要なら空行の後に理由を 1 行）
- issue 番号はコミット・PR・ブランチ名に入れない（対応は Linear の issue の本文にだけ書く）
- 統合の前の順番: `git fetch` → `git rebase origin/main`（PR を出す前だけ）→ リポジトリの指示ファイルにある検査 → `codex-review branch origin/main` → `integrate`。レビューの後に変えたら、検査とレビューをやり直す
- 統合は `integrate` だけで行う（`git push`・`gh pr merge` を直接使わない。Claude Code では禁止）。integrate は関門（main の最新を含む、未コミットの変更が無い、`scripts/check` が通る、今のコミットへの `codex-review branch origin/main` の最後の行が `VERDICT: PASS`、テストを削除・移動していない、skip・xfail・`type: ignore`・`noqa` を足していない）を確かめ、1 つでも欠けたら統合せず `notify` して止まる。直せる理由だけ直して検査・レビューからやり直し、直せなければ人を待つ。テストや検査を弱める必要があれば、理由を書いて人に `integrate --human-approved` を頼む
- integrate の統合は push 先（`git remote get-url --push origin`）で変わる:
  - github.com: ブランチを push して PR を作るところまで。マージは人が確かめて行う（`gh pr merge --rebase --delete-branch`。squash しない）。PR を出した後は rebase せず、修正はコミットを足して integrate をやり直す（main が進んで止まったら人に聞く）
  - それ以外（bare）: main へ push する（bare 側の pre-receive でも `scripts/check` を確かめる）。main が進んで止まったら fetch・rebase・検査・レビューからやり直す。bare は早送りでない push とブランチの削除を拒む（`config/git/config`）ので、feature ブランチは bare に push しない
- 強制 push はしない

## Linear（タスク管理）

会話はあとから見返せないので、**後から Linear だけ見れば作業内容と状況が分かる**状態を保つ。遠慮せず issue を作り、状態を更新してよい。

- 作業の起点に issue が無ければ作る（数分で終わる小さな修正だけは任意。issue が無ければコミットメッセージが記録）。issue があれば `/issue ARK-nn` で始める（「ARK-nn をやって」と言われたときも）
- 要件と受け入れ条件、superpowers の設計（spec）と計画（plan）は、コメントではなく issue の**本文**に書く（最新が 1 か所で分かるように。本文が正本）。superpowers の実行の skill は plan のファイルを要求するので、plan はリポジトリの `.superpowers/plans/<ARK-nn>-<名前>.md` にも置く（`.superpowers/` は dotfiles のグローバル gitignore で全リポジトリから除外）。リポジトリに `docs/superpowers/` のファイルは作らない
- 状態: 着手で In Progress。コミット済み・未マージの間はそのまま（コメントに「未マージ」と書く）。マージした、または統合しないと決めた後に Done（統合の判断と一緒に確認してよい）。手を止める理由があれば Blocked や Backlog に戻す
- コメントは節目だけ: 要件・計画の合意、方針変更、詰まった点、途中で止めるとき（状態と次の手順。tinymemory は端末ごとなので、別の端末で続けるにはここが要る）、完了（統合の前に、作業ブランチの上で `/wrap-up`。「Git」の節の方法で統合するより先。統合の後にもう一度 `/wrap-up` で片づける）
- 子 issue は、セッションやブランチをまたぐ作業に分けるときだけ作る。1 つのブランチで終わる内訳は、本文のチェックリストに書く
- 将来やる / 見送ったことも issue に残す（Backlog）
- Linear が使えない環境では、issue の代わりにリポジトリの `docs/tasks/<短い名前>.md` に、同じ見出し（要件・受け入れ条件・設計・計画・経過）で書く

## スクリーンショット

ユーザーが「スクショ」「スクリーンショット」「今撮った画像」などと言ったら、`~/screenshots/` の最新ファイルをファイルを読むツールで見る（`ls -t ~/screenshots | head` で確認）。

- ユーザーのローカル端末で撮影したものが自動で転送されている。ファイル名は `ss-YYYYmmdd-HHMMSS.png`（保存時刻。同じ秒は `-2`。撮影から数秒ずれるので、時刻で探すときは幅を持たせる）
- 「さっきの 2 枚」なら新しい順に 2 枚。時刻の指定があればファイル名で探す
- 7 日より古いものは自動で削除される
