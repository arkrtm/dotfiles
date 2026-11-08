# shell

- `shell/zshenv` `shell/zprofile` `shell/zshrc`: vi キー、fzf（Ctrl-R/T, Alt-C）、starship、mise（非対話は PATH の shims が呼ばれた場所の版を使い、対話は mise activate）、エイリアス `ll la lt lg lzd`、関数 `cw`。入れ子のシェル（tmux → nvim → :terminal、スクリプトの中の bash -lc など）でも PATH が積まれない（zsh は typeset -U、bash も zshenv で同じに）。zprofile は mac のログインで path_helper が組み替えた PATH の先頭をユーザー領域に戻し、Homebrew を PATH に入れる。補完は install.sh が書き出す道具の補完と、システムの vendor-completions（docker など）
- `shell/bashrc` `shell/bash_profile`: zsh が無い端末用（環境変数は zshenv を読んで共有）。対話ログインで zsh があれば `exec zsh`（`NO_ZSH=1` で抑止。zsh が起動直後に死ぬ時は `ssh -t <host> 'NO_ZSH=1 bash -l'` で入る）
- WSL: Windows が足す PATH は system32 と WINDOWS だけ残す（zshenv。bash も。mise が作り直す元 `__MISE_ORIG_PATH` も）。名前で呼ばれる powershell.exe・win32yank.exe は install.sh が `~/.local/bin` にリンクする。ほかの Windows の道具は絶対パスで呼ぶか、`~/.zshenv.local` で PATH に足す
- 端末ごとの設定と秘密（トークンなど）はリポジトリの外の `~/.zshenv.local`（全ての zsh と bash が読み、スクリプトとエージェントのコマンドにも渡る。POSIX sh の書き方）・`~/.zshrc.local`（対話の zsh。プラグインより前に読む）・`~/.bashrc.local`（対話の bash）に書く。無ければ読まない。git は `~/.gitconfig`、ssh は `~/.ssh/config.local`
