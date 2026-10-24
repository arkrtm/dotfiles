# config/wezterm

- `config/wezterm/wezterm.lua`: Windows の `WEZTERM_CONFIG_FILE` で指す（リンクしない）。WSL の端末。既定は WSL、`Ctrl+Shift+1` で WSL・`Ctrl+Shift+2` で PowerShell のタブ、`Ctrl+Shift+O` でランチャー。kitty 方式の画像（herdr の中の yazi）

## WezTerm（Windows）

WSL では Windows Terminal ではなく WezTerm を使う。herdr は画像を kitty 方式でしか外へ通さず、Windows Terminal は sixel しか表示できないため、herdr の中の yazi で画像が見えない（`config/herdr/config.toml` の `[experimental] kitty_graphics` と `wezterm.lua` の `enable_kitty_graphics` で通す）。

WSL へは ConPTY を通らずに、WezTerm 内蔵の SSH で localhost の sshd につなぐ（ConPTY は kitty 方式の画像を落とし、iTerm2 方式でも位置がずれる。公式の unix_domains の方法は WSL1 専用で、`wsl.exe` 越しの `wezterm cli proxy` は Windows の GUI からだと応答が返らない）。前提: WSL の mirrored networking と、WSL で動く sshd。一度だけ:

1. Windows の PowerShell で、この接続専用の鍵を作り、設定ファイルを指す（WSL が止まっていると設定を読めず既定の設定になる）:
   ```powershell
   ssh-keygen -t ed25519 -N '""' -C wezterm-wsl -f $env:USERPROFILE\.ssh\wezterm_wsl
   setx WEZTERM_CONFIG_FILE "\\wsl.localhost\Ubuntu-22.04\home\<ユーザー>\dotfiles\config\wezterm\wezterm.lua"
   ```
2. WSL で、その鍵を localhost からの接続に限って許可する（`<Windows のユーザー>` は Windows 側の名前）:
   ```sh
   printf 'from="127.0.0.1,::1" %s\n' "$(cat /mnt/c/Users/<Windows のユーザー>/.ssh/wezterm_wsl.pub)" >> ~/.ssh/authorized_keys
   ```
3. WezTerm を起動し、初回はホスト鍵の確認に答える
