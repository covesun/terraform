# <project> tasks

## 実行ルール
- 手順は上から順に実行する。
- 各ステップに「期待結果」と「失敗時対応」を記載する。
- 実行した証跡は末尾の `Execution Log` に残す。

## Phase 0: 準備
1. 認証確認 (`az login`, `aws sts get-caller-identity` など)
2. 変数ファイル準備 (`terraform.tfvars`)

## Phase 1: Terraform
1. `terraform init`
2. `terraform plan`
3. `terraform apply`
4. 期待結果: リソース作成成功
5. 失敗時対応: エラーメッセージを記録し、`design.md` と差分確認

## Phase 2: CLI/API 補完
1. Terraform 未対応の設定を CLI/API で適用
2. 期待結果: 対象設定が有効化される
3. 失敗時対応: 再実行条件とロールバック条件を記録

## Phase 3: 検証
1. 機能確認コマンドを実行
2. 監視/アラート発火テストを実施
3. 期待結果: 受け入れ条件を満たす

## Phase 4: 破棄
1. `terraform destroy`
2. 期待結果: 残存リソースがない

## Execution Log

| Date | Operator | Phase | Command/Action | Result | Notes |
|---|---|---|---|---|---|
| YYYY-MM-DD | human/codex/kiro | Phase 1 | `terraform apply` | success/fail | 補足 |

