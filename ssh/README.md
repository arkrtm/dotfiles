# ssh

- `ssh/config`: 全端末の `Host *`（`ServerAliveInterval 60`・`AddKeysToAgent yes`）。端末固有の Host は `~/.ssh/config.local`（リポジトリ外、`Include`。先に読むので既定より優先される）
- `ssh/config.mux`: mac / linux だけの接続の多重化（`ControlMaster auto`・`ControlPath ~/.ssh/cm-%C`・`ControlPersist 10m`）。install.sh がリンクする。Windows の OpenSSH は多重化に対応しないのでリンクせず、無いので読まれない
  - ホストごとに止めるのは `~/.ssh/config.local` に `Host <名前>` / `ControlMaster no` / `ControlPath none`。`ControlMaster no` だけでは、閉じた後も 10 分残る接続を使い回す。今の接続を閉じるのは `ssh -O exit <host>`
  - ソケットのパスは HOME + 66 バイト。mac の上限 104 に収まるのは HOME が 37 バイトまで。超える端末は `config.local` で短い `ControlPath` を書く

## SSH 鍵

端末ごとに別鍵（ed25519、パスフレーズなし、コメント `arkrithm@<端末名>`）。秘密鍵はリポジトリに入れない。
