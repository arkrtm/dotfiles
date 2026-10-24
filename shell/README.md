# shell

- `shell/zshenv` `shell/zprofile` `shell/zshrc`: vi キー、fzf（Ctrl-R/T, Alt-C）、starship、mise、fnm（既定の Node を PATH に、対話シェルでは `fnm env`）、エイリアス `ll la lt lg lzd`、関数 `cw`。zprofile は mac のログインで path_helper が組み替えた PATH の先頭をユーザー領域に戻し、Homebrew を PATH に入れる
- `shell/bashrc` `shell/bash_profile`: zsh が無い端末用（環境変数は zshenv を読んで共有）。対話ログインで zsh があれば `exec zsh`（`NO_ZSH=1` で抑止。zsh が起動直後に死ぬ時は `ssh -t <host> 'NO_ZSH=1 bash -l'` で入る）
