# config/herdr

- `config/herdr/config.toml`: herdr の設定（キー操作は tmux に合わせる。ただし prefix `r` はサイズ変更モード（続けて h/j/k/l、Esc で抜ける）、設定の再読込は prefix `R`。prefix `C-g`。kitty 方式の画像を通す）

## 常時起動サーバー（herdr と Claude Code）

常時起動のサーバー（どの端末でも同じ）で herdr を立ち上げ、その中で Claude Code を動かす。PC からは herdr に入って見る。モバイルからは Claude アプリの remote-control でメインの会話を見て指示する:

```sh
curl -fsSL https://herdr.dev/install.sh | sh   # 初回だけ: herdr を ~/.local/bin に入れる（sudo なし）
herdr                       # サーバーの persistent session に入る（無ければ作る）
claude                      # メインの pane で。初回は /login（claude.ai）と remote-control の確認
```

- herdr の導入: install.sh の対象外（インストーラーは版を固定しないリモートのスクリプトなので埋め込まない）。使う端末で一度、上の 1 行目を手で実行する。Claude Code の状態は herdr が画面から読むので、herdr の連携（`herdr integration install claude`）は入れない（resume のための hook を `~/.claude/settings.json` に書き足し、リンク先のリポジトリの settings.json が変わる）
- remote-control: settings.json の `remoteControlAtStartup: true` で、対話のセッションはすべて最初からモバイルにつながる（Pro/Max の claude.ai ログインが要る。`DISABLE_TELEMETRY`・`DO_NOT_TRACK` などを設定すると使えない）。モバイルからも `/clear` を送れる
- 自分で clear して続ける（待っている間に人が同じ pane で /clear・/resume・/branch したら取り消す）: 文脈が 60% を超えたとき（context-nudge が促す）と、issue の統合の後に次の issue を始めるとき（wrap-up skill の 5）に、Claude は handoff skill の手順で引き継ぎ（relay の記憶と Linear）を保存して `handoff` を呼ぶ。`handoff` はターンの終わりを待って `/clear` を送り、clear の後の SessionStart を待って続きの指示を送る。続きの指示は普通の入力として入るので、PC でもモバイルでも見える。続きの指示には合言葉（`[handoff <id>]`）が付き、clear の SessionStart が同じ合言葉を会話に入れたときだけ Claude が従う（送る直前に人が会話を切り替えた一瞬の隙間への備え）。閉じきれない隙間: idle を確かめてから `/clear` を送るまでの一瞬に人が `/resume` すると、再開した会話に `/clear` が届く（herdr から送る入力はセッションを指定できない）。`/clear` は会話を消さず新しい会話を始めるだけなので、`/resume` で戻せる。続きの指示は合言葉で拒まれる。経過は `~/.local/state/handoff.log`、止めたときは notify
- サブエージェントの進み（PC だけ）: 開始で `agent-pane view` の pane を開き、終了で閉じる。1 つ目はメインを右に半分ずつで分け、2 つ目からはその右の列のいちばん下を上下に分ける（フォーカスは移さない）。開いたとき・閉じたときに右の列の高さをそろえる（人が手で閉じたときは、次に開くか閉じるときにそろう）。同時に 3 つまで。workflow のエージェント（`agent_type` が `workflow-subagent`）は数が多いので開かず、バックグラウンドのまま。サブエージェントの pane の枠の上に `<役割> · <モデル> <effort>` の名前を出す（例 `plan · claude-opus-5-5 xhigh`。役割は Agent の description の先頭の役割名（グローバルの指示の「モデルの割り当て」）、無ければ agentType。モデルは最初の応答の正式な名前で、最初の応答を待って付ける（モデルが分からなければ付けない）。effort は記録（meta.json）に無ければ出さない）。メインの pane には、ステータスラインが `main · <モデル> <effort>` の名前を付ける（`/model`・`/effort` で変えたら付け直す。Claude Code を閉じたとき（SessionEnd）に消す）
- 限界: workflow で `agentType` を指定したエージェントはフックの入力で見分けられないので、普通のサブエージェントと同じに開く（3 つまで）。チームのメンバー（agent teams）の split pane は tmux・iTerm2 だけで、herdr には出ない（in-process のメンバーは SubagentStart で上と同じ pane に出る）
