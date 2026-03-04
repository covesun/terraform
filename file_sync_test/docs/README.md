# file_sync_test docs

このフォルダは `file_sync_test` のドキュメント一式を管理する。

## 読み順
1. `requirements.md`
2. `design.md`
3. `parameters.md`
4. `tasks.md`
5. `rules.md`
6. `retrospective.md`

## 参照
- 共通スタイル: `../../docs/style.md`
- 共通テンプレート: `../../docs/templates/`

## パスワード取得
- VM ログイン用パスワード取得スクリプト: `../scripts/get-vm-admin-password.sh`
- 使い方:
```bash
./scripts/get-vm-admin-password.sh
# 必要なら明示指定も可能:
# ./scripts/get-vm-admin-password.sh <KEY_VAULT_NAME> [SECRET_NAME]
```
