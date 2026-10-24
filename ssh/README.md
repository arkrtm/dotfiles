# ssh

- `ssh/config`: 端末固有の Host は `~/.ssh/config.local`（リポジトリ外、`Include`）

## SSH 鍵

端末ごとに別鍵（ed25519、パスフレーズなし、コメント `arkrithm@<端末名>`）。秘密鍵はリポジトリに入れない。
