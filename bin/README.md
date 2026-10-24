# bin

`bin/`:

- `agent-status` — Claude Code hooks から呼ばれ、tmux のウィンドウ名に `● 作業中 / ? 入力待ち / ✓ 完了` を出し、入力待ち・完了でデスクトップ通知（OSC 777）
- `geoview FILE [-o out.png]` — GeoTIFF の情報表示 / プレビュー PNG（uv + rasterio。GDAL 同梱 wheel なので sudo・conda 不要）
- `integrate [--human-approved]` — 統合はこれだけで行う。関門（`integrate setup` の設定がある・最上位のブランチ（base）の最新を含む・未コミットの変更が無い・設定の test が通る・今のコミットの origin/<base> との差分への `codex-review branch` が `VERDICT: PASS`・テストの削除や移動と skip・xfail・`type: ignore`・`noqa` の追加が無い。Markdown の文書は数えない）を 1 つでも満たさなければ統合せず `notify` して終了コード 1（設定の remote が origin と違う・origin の push 先が取得先と違う設定でも止まる）。kind が `bare`・`github` なら base へ push（早送りだけ）、`pr` ならブランチを push して base に向けた PR を作るだけ（マージはチーム）。`--human-approved` はテストや検査を弱める変更を人が確認して通す（人用）
- `integrate setup` — リポジトリごとの設定（下の「integrate setup」）
- `integrate-hook <session-start|pre-edit>` — Claude Code のフック。origin があって `integrate setup` の設定が無いリポジトリでは、会話の始まりに setup を案内し、編集（Edit・Write・NotebookEdit）を拒む（終了コード 2）。読む・調べる・Bash は止めない（Bash での書き換えは捕らえない抑止）。設定がある・origin が無い・git の外では何もしない
- `handoff <続きの指示>` — herdr の中で、このターンの後に自分の pane へ `/clear` と続きの指示を送る（`config/herdr/README.md` の「常時起動サーバー」）。Claude が handoff skill の手順で呼ぶ。herdr の外では 1
- `context-nudge` — PostToolUse のフック。ステータスラインが書いた文脈の使用率が 60% 以上なら、10% 刻みに 1 回 handoff を促す（サブエージェントの中では出さない）
- `agent-pane <start|stop|cleanup|view>` — サブエージェントのフック。herdr の中で、サブエージェントの進みを別の pane に出す（同時に 2 つまで）
- `notify MESSAGE` — エージェントが止めた理由を `~/.local/state/agent-notify.log` に記録して標準エラーに出す（外部には送らない。スマホへは Claude Code mobile が届ける）
- `codex-review` — Codex のレビュー（`config/codex/README.md`）

## integrate setup

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
- ARK-98 より前から使っている端末（業務サーバーなど）の移行:

```sh
cd ~/dotfiles && git pull
rm ~/.claude/hooks                 # check・fmt のフックのリンク（リンク先が無くなった）
DOTFILES_LINKS_ONLY=1 sh install.sh  # bin/integrate-hook のリンクを足す
cd <各リポジトリ> && integrate setup  # 端末なら推測を既定値に尋ねる
```
