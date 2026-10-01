# Claude Code ハーネスの細目

README の「Claude Code ハーネス」節の細目（hook がどう判定するか、何を見ていないか）。流れと superpowers との対応は README に、決定の経緯は Linear の issue（ARK-nn）にある。実装は `bin/harness-hook`、振る舞いの検査は `tests/harness-hook.sh`。

## 仕組み

- 規模判定 S / M / L で手順を変える（CLAUDE.md の表）
- コードを書くときの規則: 作業ブランチ、TDD（REFACTOR まで）、`/accept`、`/verify`、`/review`（仕様適合・テスト・品質・保守性の 3 軸）。証拠（検証の成功・受け入れ検証の合格・レビューの承認）が無いコード変更は git の pre-commit が止める
- 受け入れ検証（ARK-48。いちばん大事な段階）: 型やテストが通っても、成果物が要件どおりとは限らない。受け入れ条件は成果物を実際に動かして確かめられる性質（データなら件数・スキーマ・値の範囲・一意性・参照の整合・再現性・境界）で書き、独立した acceptor が実装を読む前に本物の入力（無理ならサンプル）で成果物を動かして確かめる。作った本人が確かめないので甘くならない
  - 判定行 `受け入れ: 合格` と条件ごとの行 `[ACn] 合格` がそろい、しかも要件の写しにある AC 番号がすべて合格で報告に出ているときだけ（一部の条件だけを確かめた報告は通らない。ARK-50）hook が「受け入れ済み」を記録する
  - 報告は git dir の `harness-last-accept` に保存して reviewer が読む。検査スクリプトは tests/ に残るので、以後の変更でも壊れたら分かる
- レビューの往復を抑える仕組み（ARK-41。superpowers の範囲限定の再レビューと ECC の報告前の関門を参考）: フルレビューは 1 回。直した後は `/review fix` が「前回の未解決の指摘」と「前回見た版からの修正差分」だけを見る（版は `skills/review/snapshot.sh` が作業ツリー全体の tree ID として記録）
  - 重大・中は具体的な発生条件が書けるものだけで、軽と範囲外は判定に影響しない（issue に記録）。reviewer は検証を回し直さない
  - `/review fix` は 2 回まで、それでも残ればユーザーが指摘ごとに裁定する
  - reviewer の報告は git dir の `harness-last-review` に保存し、`/review fix` は前回の版と未解決の指摘をそこから読む（メインの転記に頼らない）
- 並列実装とデバッグ（ARK-42。superpowers の subagent-driven-development・systematic-debugging と ECC の multi-*・build-error-resolver を参考に自作し、どちらも入れない）
  - `/implement` は計画を「持ち分のファイルが重ならないタスク」に分けて波ごとに implementer を同時に起動し、コントローラは短い状態報告だけを受けて統合・検証・レビューする。implementer はツールを絞っていて、小さなタスク 1 つで約 1.5 万トークン（汎用のエージェントの約 4 分の 1。ARK-47）
  - `/diagnose` は再現コマンド → 安い順の絞り込み（スタックトレースの箇所 → 逆向きの追跡 → 最近の変更 → 動く例との比較 → 境界の計測 → `git bisect run`。原因が見えたらそこで止める）→ 反証できる仮説 → 回帰テスト付きで共有の関数を直す。3 回直らなければ設計を疑って相談する
- 対象: Claude Code から行うコミット（環境変数 `CLAUDECODE` がある）で、Claude が cwd にして作業したことのあるリポジトリ（その worktree を含む）と、一時ディレクトリ（TMPDIR）の外のリポジトリ（親ディレクトリから `git -C` でコミットした場合など。ARK-51）
  - 人の手動コミット、GUI クライアント、テストが一時ディレクトリに作るリポジトリは対象外（Claude から実行したスクリプトが TMPDIR の外にリポジトリを作ってコミットすると関門が掛かるので、テストの準備のコミットは `env -u CLAUDECODE` で人の操作として行う。例: tests/e2e-flow.sh）
  - 検証・受け入れ検証・レビューの証拠は、セッションの cwd の作業ツリーに対して記録される
- 「コード」= 文書・画像など（`bin/harness-hook` の `DOC_EXT` の拡張子: .md .txt .rst .adoc .png .jpg .svg .pdf・フォントなど、`DOC_NAME` の名前: LICENSE・CHANGELOG・README など）以外のすべてのファイル（ARK-51 で反転。依存の定義・lockfile・.env・テンプレート・スキーマ・データ・拡張子の無いスクリプトも含む。requirements*.txt・CMakeLists.txt は .txt でもコード）。文書でも、リポジトリの `.harness-code` に書いたパスはコード。テスト実行の生成物（`__pycache__/`、`.pyc`、`.pyo`）はコードにもテストにも数えない
- 関門の対象: 上の「コード」（この repo の `.harness-code` は `config/*`・`shell/*`・`CLAUDE.md`）と、既存テストの変更・削除（テストを弱めて通すのを防ぐ）。`.harness-code`・`.harness-verify` 自体の変更も対象
  - 新しいテストの追加だけなら対象外。テストとみなすのは、リポジトリのトップの tests/・test/・spec/・__tests__/ の下と、テストの名前の規則（test_*.py、`*_test.*`・`*.test.*`・`*.spec.*`・`*_spec.*`（データ・設定の拡張子は除く）、JVM・Swift・C#・PHP・Scala・Groovy の `*Test.*`・`*Tests.*`）に当たるものだけ（ARK-51。`src/test/server.go`・`api/spec/openapi.yaml`・`SpeedTest.tsx` はコード）
  - conftest.py・`__init__.py`・pytest.ini・`*.config.*` は、テストのディレクトリにあってもコード
- 要件の写し（ARK-49・51）: 承認済みの要件と受け入れ条件を `harness-hook requirements-save`（標準入力から。git dir の下にブランチごと。Write ツールでは書けない）で置き、その内容を証拠の指紋に含める
  - 写しが無いとコミットできず、書き換えると検証・受け入れ・レビューの証拠はすべて無効になる。acceptor と reviewer は依頼の文面ではなくここを読む
  - main・master の上では保存できない。保存した後にコード変更を含むコミットがあれば写しは古いとみなし、次のコード変更には保存し直しが要る（前の依頼の写しの使い回しを防ぐ）
  - 前の版（`.history` の最後の版。写しが古くなった後も）にあった受け入れ条件の番号が無い版は、「## 変更の承認」の節（ユーザーの承認の引用）が無ければ保存しない。新しい依頼として始めるときだけ `requirements-save --new` を使い、前の依頼の版は `.history.prev` に移して比べない
  - 保存した版はすべて写しの横の `.history` に残り、reviewer が最初の版と比べて削除・緩和に承認があるかを見る（文言の緩和は機械では見分けない）。`.history.prev` があれば、今の写しが前の依頼の続きでないかも確かめる
  - 写しはメインが書く（承認済みの issue の本文を写す手順）。写しが本文と一致しているかは、機械では確かめない
- 検証（ARK-49・51）: 証拠になるのは、宣言した全体の検証コマンド（`.harness-verify`、置けなければ `<git-common-dir>/harness-verify`）が、すべて同じ内容で、リポジトリのトップで単独で成功したときだけ
  - lint だけ・絞った実行・下位のディレクトリでの実行は証拠にならない。検証コマンドが後で失敗すると証拠は消える
  - 並列に実行しても記録は落ちない（状態の読み書きはファイルロックで順番にする）。サブエージェント内（hook の入力に `agent_id` がある）の検証は記録しない
- TDD（ARK-49・51）: テストが十分かは reviewer が内容を読んで判定する。hook は失敗したテストの実行（コマンドと出力。implementer の分も）を git dir の `harness-red-log` に記録し、reviewer は RED をそこで確かめる（自己申告にしない）
  - 記録するのは、宣言した検証・よく使うテストランナーと、test・tests/・spec を含むコマンド（`python manage.py test`・`bazel test` など。grep などの読むだけのコマンドは除く）の失敗
  - パイプを付けた実行は終了コードが 0 になるので記録されない
- 報告の版（ARK-51）: 受け入れ検証とレビューの証拠は、報告の「受け入れ検証した版」「レビューした版」が SubagentStop の時点の作業ツリー全体の版（snapshot.sh と同じ求め方）と同じときだけ記録する。違いが生成物・文書だけなら同じとみなす。合わずに記録しなかったときは、次の差し戻しと pre-commit の理由に、報告の版の後に変わったファイルを出す
- 利用者の作業中の変更（ARK-51）: そのブランチで最初に写しを保存したターンの開始時に既にあった未ステージの変更（未追跡のファイルと、追跡済みのファイルの変更）は、その後に変えず未ステージのままなら証拠の対象から外す（部分コミットを止めない）
  - ステージしたら証拠が要る。pre-commit の理由に、そのファイル名と手順（`git restore --staged` か、ステージしたまま証拠を取り直す）が出る
  - 写しをコードを書いた後に保存すると、それより前の自分の変更も外れるので、写しはコードを書く前に保存する
- 計画は plan mode、L のレビュー補助は同梱 `/code-review`。自作しない
- 記録と記憶: 置き場所（Linear・CLAUDE.md・README・コミット・tinymemory の fact / session）の振り分けは `skills/wrap-up` の表。M/L の最後に `/wrap-up` が振り分けて保存する。tinymemory は端末ごとなので、別の端末で続けるための状態は Linear に書く。読み込みと整理（`/dream`）は tinymemory 側の仕組み
  - 区切りでの保存（ARK-38）: 前回の session の保存（`tinymemory save --type session`）からコンテキストが溜まったら、`harness-hook` の Stop が 1 回差し戻して `/tinymemory:remember` させる。コミットしたターンなら 30%、それ以外でも 60%（同じ起点から 1 回だけ）。使用量は transcript の最後の assistant の usage、ウィンドウは既定 100 万（`HARNESS_CONTEXT_WINDOW` で変える）
  - clear は自動化しない（デスクトップアプリでは clear 後に自動で再開できないため、CLI とそろえた）。compact・resume の後も settings.json の SessionStart で記憶を注入する
- 常時コストを増やさない: 新しい規則は CLAUDE.md に足す前に skill にできないか考える

## git の hook が呼ばれないコミットへの備え（ARK-51）

リポジトリ側の `core.hooksPath`（husky 等）、revert・cherry-pick・rebase・am などでは git の pre-commit が呼ばれない。

- リポジトリ側の `core.hooksPath` があれば、Bash の `git commit` の前に作業ツリーの証拠を確かめ、足りなければ拒否する。判定を通したコマンド（git 以外を含んでもよい）でできたコミットは、コミットした内容（親との差）の指紋が証拠と同じときだけ関門を通ったものとして記録する
- Stop が、そのターンに作られたコミットを、関門を通ったコミットの記録（tree と patch-id）と突き合わせ、コード変更を含むのに記録に無ければ差し戻す
  - そのターンに作られたコミット: ターン開始時の HEAD とローカルブランチの先端から届かず、コミット時刻がターン開始以降のもの（どのブランチでも）。ターンの間に fetch・pull で取り込んだ他人のコミットは、リモート追跡ブランチの reflog と FETCH_HEAD で除く。このリポジトリで作ったもの（HEAD・ローカルブランチの reflog にコミットを作った記録があるもの）は除かない
  - 差し戻しの後の続き（`stop_hook_active`）でも、この確認だけはする。まだ差し戻していないコミットがあればもう一度差し戻し、差し戻し済みのものだけなら通す
  - 関門を通ったコミットを rebase・cherry-pick で付け替えただけ（`git patch-id --verbatim` が同じ）なら差し戻さない。土台が変わるので、統合の後に main で検証一式を流す（CLAUDE.md の手順 9）
  - マージコミットは、2 つの親なら自動の結果と違うときだけ、3 つ以上の親と自動の結果を求められないマージ（無関係な履歴など）は最初の親との差で見る
  - 頼まれた revert・cherry-pick は `--no-commit` で行い、証拠をそろえてから `git commit` する（CLAUDE.md の手順 7）
- 見つけたコミットは記録し、リモートに無い間は（次のターンでも）`git push` を拒否する。それを含むブランチの main・master への `git merge`（fast-forward も。同じコマンドの中で `git switch main &&` のように移ってからの形も）は、リモートに出た後も拒否する（統合はユーザーが判断して自分で行う）
- 記録は post-commit が、同じ git commit（git の PID で結び付ける）の pre-commit が関門を通したときだけ、実際にコミットされた内容で行う（リポジトリ自身の pre-commit が整形してインデックスを書き換えても一致する。`-n` のコミットは記録されない）
- `--amend` は、pre-commit が付け直す前のコミットとの差しか見ないので、付け直したコミットが関門を通っていたか、コミットの変更全体に証拠があるときだけ記録する（関門を通っていないコミットを、変更なしの `--amend` で関門を通ったことにしない）
- マージ・cherry-pick・revert の途中のコミットは、自動の結果（`git merge-tree --write-tree`）との差（競合の解消、`--no-commit` の後に足した変更）に証拠を求める（自動の結果のままなら要らない）。自動の結果を求められないとき（3 つ以上の親、`merge-tree --write-tree` の無い git 2.38 より前、`--merge-base` の無い 2.40 より前の cherry-pick・revert）は、HEAD との差全体（Stop の事後の確認では最初の親との差）に求める
- 見ないもの: Stop の後に作られたコミット（次のターンで作れば見る）、セッションの cwd 以外のリポジトリのコミット

## Bash の検査（ARK-49〜51）

ガードレールであって、セキュリティ境界ではない。意図的な迂回は防ぎ切れない（`git commit-tree`、`env -i`、証拠ファイルの書き換えなど）。代表的な形は Bash の検査が拒否し、CLAUDE.md で禁止している。自分用の検証の宣言（git-common-dir の harness-verify）の内容も指紋に含める。

- 検査のしかた（ARK-50）: クォートを見分ける字句解析でコマンドを区切り（サブシェルの `( )` も）、`sh -c`・`eval`・コマンド置換の中も再帰して見る。文字列で見る形はクォートを外したコマンドにも当てる（`--"no-verify"` のように語を割る形）。git のサブコマンド・設定のキー・alias の値は、クォートを外した字句で見る
- 拒否する形:
  - `--no-verify`（省略形も）と、git commit の `-n`（`-anm`・`-nm1` のような束、alias で commit にした形も）
  - git commit の引数のコマンド置換（`$(printf -- -n)` のように `-n` に展開されうる。`-m` の値は除く。ARK-51）。字句は、そのままと、クォートの外のブレースを展開した後の両方で見る（`-{n,m}`・`git {commit,-n,-m,x}`・文字の連番の `-{n..n}`。数の連番は文字を作れないので代表の 1 桁に置き換える（`{-n,-m{1..1}}` の外側は展開する）。展開が 256 語を超える字句は、`-` を含めば判定できないので拒否し、含まなければ展開せずに見る）
  - `commit-tree`、`core.hooksPath`・`include.path`・`includeIf.*.path` の設定（`-c`・`--config-env`・`git config`）、迂回になる alias の定義、git の設定ファイルを `sed -i`・`tee`・リダイレクトで書き換える形
  - コミットを作りうる git（init・clone・status・log・diff・show・config・rev-parse・ls-files・version・fetch・remote・branch 以外のサブコマンド。alias、ダッシュ形の `git-commit`（git-core の下のものも）を含む）と同じ行での環境の差し替え: `HOME`・`XDG_CONFIG_HOME` の代入・export・unset・`env -u`、`env -i`（ARK-51）。`CLAUDECODE` を消す・書き換える形、`GIT_CONFIG*` の指定
  - 共通の hooks（`~/.config/git/hooks`）・hook の本体（`~/.local/bin/harness-hook`・`~/.local/libexec/uv`）・git の設定・要件の写しとその版（git dir の `harness-requirements`。ARK-51）を、消す・動かす・権限を変える・上書きする形。hooksPath を含む行で書き込む形（行き先を問わない）
  - 証拠を記録する hook のサブコマンド（`harness-hook review-done`・`bash` など）を直接呼ぶ形（偽の入力で証拠を作れるため。ARK-51）
- 通す形（誤検知を減らした）:
  - 閲覧だけの形: `grep -n git_config`、`--no-verbose`、`echo $CLAUDECODE`、`git log --grep=commit-tree`、`grep hooksPath`。`--no-verify` は検索の引数でも拒否する（検索だけの行を通す免除は、パスで指したコマンド・PATH・ページャ・ヒアドキュメントで穴が開くので取り下げた。ARK-51）。検索は `rg -n 'no-verify'` のように先頭の `--` を付けずに書く
  - コミットメッセージの中の `-n`・`-inf`、コミットを作らない git での環境の差し替え（`HOME=$PWD/tmp-home git init`）
  - プロジェクトの `.git/hooks` への hook の導入・書き換え（共通の pre-commit が関門を通した後に委譲する先なので、関門は外れない。ARK-51）
- ヒアドキュメントの本文の扱い（ARK-51）:
  - 行のコマンドがすべて本文を実行しない既知のコマンドで、環境変数の前置（`GIT_EDITOR=…`）とコマンド置換が無ければ、本文はデータとして検査しない（記憶の保存・`git commit -F -`・ファイルへの書き出し）
  - 既知のコマンド: cat・tee・tinymemory・harness-hook・cd・mkdir・echo・printf・true・ls・chmod・wc、gh の pr・issue・release・gist（`-e`・`--editor` を除く）、git の commit・notes・tag・add（オプションは `-F`・`--file`・`-m`・`--message`・`-q`・`-a`・`-A`・`-u`・`--cleanup`・`--signoff`・`--no-edit`・`--annotate` とその束、全体のオプションは `-C`・`--no-pager`・`--git-dir=`・`--work-tree=` だけ。commit・tag・notes は `-F`・`-m` でメッセージを渡すときだけ。渡さないと git はエディタを起動し、エディタは本文を標準入力として受け継ぐ）
  - データのコマンドでも、区切りの語をクォートしていない本文のコマンド置換（`cat <<EOF` の本文の `$(…)`・`` `…` ``）はシェルが実行するので、その置換の中身をコマンド行として検査する（本文の文章や `#` は検査しない）。区切りの語はシェルと同じく、クォートとエスケープを外して連結した語として読む（`<<E"OF"` の区切りは `EOF`）
  - 区切りをクォートしたヒアドキュメントを cat してメッセージ・本文の値に渡す形（`git commit -m "$(cat <<'EOF' … EOF)"`、gh の `--body`）もデータ（本文は展開されない）
  - ほかのコマンド（`sh <<E`、`cat <<E | sh`、`read`、ファイルに書いて次の行で `sh f`・`./f`・`make`・`mise run`）やほかのコマンド置換があれば、本文もコマンド行として検査する。hooksPath を含む書き込みは、書き込み先が git の設定になりうるとき（`cd .git && cat >> config <<E` など）は本文の語も見て拒否する
- 見ていないもの: コマンド置換の終わりを読み違える構文（置換の中の `case … x)`・コメントの `)`・ヒアドキュメントの `)`。シェルの完全な構文解析はしない）、引用符の中の空白を含む字句のブレース展開（`{-n,'a b'}`。空白を含む字句は `sh -c` の引数などとして見直す側で、展開しない）、hooksPath の語を含まない行での `cd` の後の相対パス、`xargs`・`find -exec` の `{}`、変数・alias による間接呼び出し（`g=git; $g commit -n`）、`curl -o`・スクリプト言語からの書き込み、別々の Bash 呼び出しに分けた手順
- 誤検知として残るもの: `rm -rf .git`、`mv ~/.gitconfig ~/.gitconfig.bak`、クォートの中の文字列がコマンド行に見える形（`echo "git commit -n"`、`grep "hooksPath\|cp"`）

## git の共通 hooks との関係

- 共通 hooks にリンクを置いていない hook 名（`reference-transaction`、`post-index-change`、`pre-auto-gc`、`p4-*`。高頻度で呼ばれるため）は、リポジトリ自身に同名の hook があっても実行されない
- グローバルな `core.hooksPath` との非互換: `pre-commit install`（pre-commit フレームワーク）は hooksPath が設定されていると拒否する。`git lfs install` は hooks を `~/.config/git/hooks`（= この dotfiles）に書こうとする。必要なリポジトリでは、利用者がそのリポジトリの設定で hooksPath を `.git/hooks` に向ける（そのリポジトリでは pre-commit の関門は効かず、Bash の前の判定と Stop の事後の確認だけになる）
