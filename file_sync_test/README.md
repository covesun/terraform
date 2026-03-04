# file_sync_test

Azure File Sync を使って 2 台の Windows VM と Azure Files を同期検証する Terraform プロジェクト。

## ドキュメント
- `docs/requirements.md`
- `docs/design.md`
- `docs/parameters.md`
- `docs/tasks.md`
- `docs/rules.md`
- `docs/retrospective.md`

## 実行概要
1. `terraform.tfvars.example` を `terraform.tfvars` にコピー
2. `subscription_id`, `key_vault_name_prefix`, `afs_agent_download_url` を設定
3. `chmod +x scripts/tf-secure.sh`
4. `chmod +x scripts/get-vm-admin-password.sh`
5. `./scripts/tf-secure.sh init`
6. 登録済みサーバーIDを取得して `registered_server_ids` を設定
7. `./scripts/tf-secure.sh apply` (1回目)
8. `./scripts/tf-secure.sh apply` (2回目)
9. `./scripts/get-vm-admin-password.sh` でログイン用パスワード取得
10. Bastion 経由で VM1/VM2 に接続し同期を検証
11. `./scripts/tf-secure.sh destroy`

## 補足
- この実行環境では `registry.terraform.io` への接続制限により `terraform init/validate` が失敗する場合がある。
