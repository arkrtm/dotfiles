---
name: wrap-up
description: 作業をコミットした後、統合（マージ）の前に、作業ブランチの上で使う。このセッションで得た情報を、Linear・指示ファイル・README・tinymemory のどこに残すかを決めて保存する。統合の後にもう一度使い、Linear の完了・relay・worktree を片づける
allowed-tools: Bash(tinymemory:*), Bash(git status:*), Bash(git log:*), Bash(git worktree:*), Bash(git branch:*), Bash(gh pr view:*), Bash(gh pr checks:*)
argument-hint: "[ARK-nn]"
---

タスクの締め。統合の前は 1〜4 を順に行う。統合の後に呼ばれたら 5 だけを行う。補足: $ARGUMENTS

## 1. 前提の確認
- 作業ブランチの上で、統合（マージ）の前に行う（ここでの指示ファイル・README の変更は作業ブランチの別コミットにして、一緒に統合する）
- `git status --porcelain` でコード変更が残っていないこと（残っていれば先にコミットを終える）
- 状態（Done）と session の「現在の状態」は統合の後に決まる。統合の後に Linear を Done（kind が `pr` でマージ待ちなら In Review。5 の 1）にし、必要なら session を 1 行直す

## 2. 情報の振り分け（置き場所はここで判断する）
このセッションで分かったこと・決めたことを 1 件ずつ、次の表で置き場所を決める。**同じ内容は 1 か所だけ**に書き、他からはパスで指す（issue 番号など Linear の情報で指すのはリポジトリの外の Linear・tinymemory からだけ。リポジトリに入るものには Linear・superpowers の情報を書かない: グローバル指示の Git の節）。**迷ったら残さない**。コード・README・git log から導けることは残さない。

| 置き場所 | 入れるもの | 読む人・タイミング |
|---|---|---|
| **Linear の本文**（起点の issue） | 要件・受け入れ条件・計画のパス、決定と理由、計測の値、Codex の「参考」、残件・判断待ち、見送ったこと。**決定と理由の詳細はここ** | 人が後から経緯を追う |
| **Linear の完了のコメント** | コミット（`git log --oneline`）と、検証のコマンドと結果だけ。本文にあることは書き写さない | 人が後から結果を確かめる。状態はグローバル指示の Linear の節（Done は統合の後、確認してから） |
| **プロジェクトの指示ファイル**（リポジトリの `CLAUDE.md` / `AGENTS.md`、Edit で追記して別コミット） | 毎セッション最初から必要なこと: ビルド・テスト・実行のコマンド、守るべき不変条件、規約、「これはやらない」。短く安定したものだけ | そのリポジトリで動く全エージェントが毎回 |
| **グローバル指示**（dotfiles の `config/agents/AGENTS.md`。CC・Codex 共通） | 全プロジェクトに効く規則・好み。**追記はユーザーに提案し、合意してから** | 全プロジェクトで毎回 |
| **README・設計メモ** | 仕組みと限界（今どうなっているか）だけ。理由や経緯は書かない（Linear にだけ置く。issue 番号など Linear の情報も書かない） | 人・エージェントが仕組みを知りたいとき |
| **コミットメッセージ** | その差分の理由だけ（経緯・計測は issue へ） | git log・blame を読むとき |
| **tinymemory `fact`** | 毎回は要らないが関連時に効く知識: ハマりどころ、環境・道具の癖。プロジェクトに依らない好み・端末や道具の癖は `--global` | 関連するときに recall / search で |
| **tinymemory `session`** | 現在の状態と次の手順（1 件。150 行以内）。Linear にあることは issue 番号で指し、書き写さない | 次のセッションの開始時に自動で（**端末ごと**。別の端末で続けるなら Linear のコメントが要る） |
| **残さない** | デバッグの途中経過、試行錯誤の履歴、一時的な状態、他の場所にあるもの | — |

Codex のレビューの「参考」: issue の本文の「参考」の指摘を、1 件ずつ Backlog の issue に起こすか決める。

降格・更新:
- 既存の fact を `tinymemory search` で確認し、**同じ話題があれば同じタイトルで保存し直す**（supersede）。間違いになったもの、指示ファイルや README と重なるものは `tinymemory delete <id>`
- 以前の session（`tinymemory list`）の「次の手順」を今回ですべて終え、状態も古くなったなら、`tinymemory archive <id>` で recall から外す（未完了や判断待ちの状態が次のセッションに残らないように）。作業中の中継の記憶（relay）は 5 で外す
- 指示ファイルの記述が状況依存になっていたら、fact に降格する

## 3. 保存
- Linear: 本文は `save_issue` の patch 1 回でまとめて直す。完了のコメントを 1 回書く（コミットと、検証のコマンドと結果）
- 指示ファイル: Edit で追記する（プロジェクトのものは別コミット。グローバルは提案まで）
- README: 仕組みが変わったのに直っていなければ Edit で直す（指示ファイルと同じく別コミット）。コミットメッセージは直さない（書き写しもしない）
- tinymemory: `tinymemory save --type session --title "…"` と `--type fact` を quoted heredoc で実行する（remember skill の保存のコマンドと同じ形。remember の最後の「/clear してよい」の案内は出さない）

## 4. 報告
残したものを「置き場所: タイトル」で 1 行ずつ列挙し、残さなかった判断も 1 行で述べる。次はグローバル指示の Git の節の方法で統合し、統合の後にもう一度この skill を使う（5. 統合の後。この skill は統合の前に走るので、ここでは区切りを促さない）。

## 5. 統合の後
統合が済んだ後に呼ばれたときは、1〜4 をせずこれだけを順に行う。`<作業内容>` は issue の本文の `ブランチ: feature/<作業内容>`、`<元>` は `git worktree list --porcelain` の先頭（元のチェックアウト）、`<kind>`・`<base>` は `integrate setup --show` の kind と base。
1. 統合の確認。満たさなければ 2 以降をせず、止めて人に聞く
   - kind が `bare`・`github`: `git fetch` の後、`git merge-base --is-ancestor feature/<作業内容> origin/<base>` が成功する
   - kind が `pr`: `gh pr view feature/<作業内容> --json url,state,baseRefName,headRefOid` の `state` が `MERGED`、`baseRefName` が `<base>`、`headRefOid` が `git rev-parse feature/<作業内容>` と一致する（一致しなければ PR に入っていないローカルのコミットがある）
       - `state` が `OPEN`（チームのマージ待ち）で、`baseRefName` と `headRefOid` が合うなら止めない: Linear を In Review にし（チームに In Review が無ければ In Progress のまま、PR の url と「マージ待ち」をコメントする）、2〜4 をせず（worktree と relay を残す）5 へ進む。片づけはマージの後、次の作業を決めるとき（5）に行う
       - `state` が `CLOSED`（マージされていない）や、`MERGED` でも `headRefOid` が合わなければ、止めて人に聞く
2. 結果を Linear にコメントして Done にする: `pr` は PR の url、`bare`・`github` は `<base>` に入ったコミット（`git log --oneline` の該当範囲）
3. relay の片づけ: `tinymemory list --json | jq -r '.[] | select((.tags | index("relay")) and (.title | test("^ARK-nn([^0-9]|$)"))) | .id'`（`ARK-nn` はこの issue の番号）の各 id を `tinymemory archive <id>`
4. worktree とブランチ: `<元>` に移る。`<元>` のブランチが `<base>` なら `git pull --ff-only`（失敗したら止めて人に聞く）、違えば切り替えず更新もしない（そう報告する）。`git worktree remove <元>/.worktrees/<作業内容>`（未コミット・未追跡のファイルで拒まれたら消さずに人に聞く）。ブランチは `git branch -D feature/<作業内容>` で消す（`-d` は `<元>` のブランチや上流への取り込みで判定するので、`<base>` と違うブランチの上や `pr` のマージでコミットが作り直されたときに拒む。取り込みは 1 で `<base>` に対して確かめ済み）
5. 残したものを 1 行ずつ報告し、次の作業を決めて始める
   - 決め方: ユーザーが示した作業（続きの指示に書かれたものを含む）があればそれ。無ければ先に下のマージ待ちの PR を見る。それでも決まらなければ同じリポジトリ（issue のタイトルの先頭の `[<リポジトリ名>]` で見分ける）の Todo から優先度の高い順（No priority は最後。同じ優先度なら番号の小さい順）に選ぶ。同じリポジトリの Todo が無ければ、Todo・Backlog の候補（同じリポジトリの Backlog と、ほかのリポジトリの Todo）を選択肢で示して尋ね、答えを待つ
   - マージ待ちの PR: 同じリポジトリのマージ待ちの issue（In Review。チームに無ければ In Progress で「マージ待ち」のコメントがあるもの。今の issue は除く）ごとに、本文の `ブランチ: feature/<作業内容>` の PR を見る。`MERGED` なら、その issue でこの 5 の 1〜4 を行う（片づけ。1 で止まれば人に聞く）。`OPEN` で、人の指摘（読み方は issue の skill の 6）か落ちた CI（`gh pr checks feature/<作業内容>`）があるか、`gh pr view feature/<作業内容> --json mergeable` が `CONFLICTING`（`<最上位>` が進んで衝突した。衝突中は CI が動かない）なら、その issue を次の作業にする（`/issue ARK-nn` で再開）
   - 始め方: Claude Code は handoff skill で始める（herdr の中なら自分で clear して次を始め、外なら `/clear` と続きの指示を促す）。Codex は `/new` を促し、続きの指示の文（`/issue ARK-nn` から始める）を示す。ほかのリポジトリの issue に決まったら handoff せず、そのリポジトリで新しいセッションを開いて続きの指示の文を送るよう促す（clear しても作業ディレクトリは変わらない）
