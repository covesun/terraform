# file_sync_test rules

Created-By: codex

## 共通ルール参照
- 共通セキュリティルール: `../../docs/security-rules.md`

## ドキュメント更新順序
1. `requirements.md`
2. `design.md`
3. `parameters.md`
4. `tasks.md`
5. `rules.md`
6. `retrospective.md`

## 構築ルール
- 原則 Terraform 優先で実装する。
- Terraform 未対応項目のみ CLI/API を使う。
- Azure File Sync の登録サーバーID取得は CLI で実施し、値は `registered_server_ids` に反映する。
- Azure Portal で手動実施した設定は同日中に手順化する。

## セキュリティルール
- シークレット情報をドキュメントに平文で記載しない。
- `terraform.tfvars` は Git 管理対象に含めない。
- `admin_password` を `terraform.tfvars` に記載しない。Terraform でランダム生成し、Key Vault Secret として保管する。
- VM Public IP は付与しない。
- RDP は `AzureBastion` サービスタグ経由のみ許可する。

## 検証ルール
- 受け入れ条件は `requirements.md` と一致させる。
- 変更後は `terraform plan` を再実行して差分を確認する。
- 実行結果は `tasks.md` の `Execution Log` に記録する。
- `password_rotation_token` は任意の文字列でよい。値を変更したタイミングで VM 管理者パスワードをローテーションする。
- 検証サイクル完了時は必ず `docs/retrospective.md` を更新し、試行錯誤・失敗原因・採用判断を記録する。

## レビュー観点
- Azure File Sync 構成要素 (Service/Group/Cloud/Server Endpoint) が揃っているか。
- Agent導入とサーバー登録の手順が再現可能か。
- 第三者が `tasks.md` のみで再現できるか。
