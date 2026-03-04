# file_sync_test retrospective

Created-By: codex
Updated: 2026-03-05

## 目的
- 構築中に発生した問題と再発防止策を記録し、次回以降の再現性を上げる。

## 今回の反省点
1. Azure 側依存の前提不足
- `Microsoft.StorageSync` プロバイダー未登録で初回 apply が失敗した。
- 対策: 事前チェック項目に「Resource Provider 登録確認」を入れる。

2. Cloud Endpoint 作成の権限設計が不十分
- Storage Sync Service 側の ID/ロール不足で Cloud Endpoint 作成が不安定だった。
- 対策: Terraform で Managed Identity 有効化 + 必要ロール付与を自動化する。

3. Cloud Endpoint/Sync Group の不整合状態を想定できていなかった
- 一度失敗した後に `invalid partnership Id` が発生し、再作成が必要になった。
- 対策: `MgmtBadRequest` 系を検知したら `sync_group` / `cloud_endpoint` の再作成手順を明示する。

4. Server Endpoint パス設計のリスク
- `C:\` 運用は環境依存で不安定なケースがあり、`404`/不整合を誘発した。
- 対策: 既定をデータディスク (`F:\AFSData`) に統一する。

5. VM Extension スクリプトの冪等性不足
- 既登録サーバーで `Register-AzStorageSyncServer` が非0終了し、再適用に失敗した。
- 対策: 既登録エラー (`already`, `0x80C8004F`) を成功扱いする。

6. ツール差異の見落とし
- Azure CLI サブコマンド差異や引数差異で切り分けに時間を要した。
- 対策: 手順書に「実コマンド例（この環境で確認済み）」を残す。

## 試行錯誤ログ (時系列)
1. 初回 apply
- 状況: NSG 設定値不備 / Provider 未登録 / Cloud Endpoint 作成失敗が連続発生。
- 結果: apply 失敗。
- 学び: Azure File Sync は「前提条件未充足」があると後続で連鎖的に失敗する。

2. NSG 修正と StorageSync Provider 登録
- 試行: NSG の source 設定を修正し、`Microsoft.StorageSync` を登録。
- 結果: 基盤リソース (RG/VNet/Bastion/VM/Sync Service) は進むようになった。
- 学び: 基礎リソースの失敗と AFS 固有失敗を分離して見るべき。

3. Cloud Endpoint 権限問題の切り分け
- 試行: Storage Sync Service の identity/useIdentity を確認し、Storage Account へのロール付与を検証。
- 結果: Cloud Endpoint は一度は作成できたが、以後不安定化。
- 学び: 「通った/通らない」だけでなく、再実行時の安定性を評価軸にする必要がある。

4. `azapi` で identity 更新を Terraform 化
- 試行: `azapi_update_resource` で `SystemAssigned + useIdentity=true` を管理。
- 結果: API 応答の癖で失敗しやすく、運用性が低いと判断。
- 判断: 不採用。

5. `null_resource + az CLI` へ切替
- 試行: identity 有効化とロール付与を `local-exec` 化し、冪等チェックを入れる。
- 結果: 権限面は安定。Cloud Endpoint 作成成功率が改善。
- 判断: 採用。

6. Cloud Endpoint の state 不整合対応
- 試行: Azure 上に作成済みだが state 未登録の Endpoint を import。
- 結果: Terraform 管理に復帰可能。
- 学び: 失敗直後は「Azure 実体」と「state」のずれをまず疑う。

7. Server Endpoint で 404 が断続発生
- 試行: `C:\AFSData` のまま作成を継続。
- 結果: `MgmtUnknown/CosmosDB bad request` や `404` が再発。
- 判断: `C:` 前提をやめ、データディスク方式に変更。

8. データディスク方式へ移行
- 試行: VM に managed disk を追加し `F:\AFSData` を Server Endpoint パスに変更。拡張で RAW ディスク初期化も実施。
- 結果: `vm2` は安定して Server Endpoint 作成。全体成功率が向上。
- 判断: 採用 (標準化)。

9. 再登録時エラーの扱い
- 試行: VM Extension 再実行時 `Register-AzStorageSyncServer` が `0x80C8004F` で失敗。
- 対応: `already|0x80C8004F` を成功扱いに変更。
- 結果: 拡張の再適用が可能になった。

10. `invalid partnership Id` 対応
- 試行: Cloud Endpoint 側エラーを CLI で詳細確認。
- 結果: `sync_group/cloud_endpoint` の不整合が原因と判明。
- 対応: taint で `sync_group` + `cloud_endpoint` を再作成。
- 学び: このエラーは「再作成が最短」のケースがある。

11. 最終整合
- 試行: 片系のみ作成済みの Server Endpoint を CLI で補完し、Terraform import で state 整合。
- 結果: `terraform apply` が最終成功。`server_endpoint_ids` が2台分出力。
- 学び: 「CLIで復旧 → state取り込み → applyで収束」は有効な復旧パターン。

12. destroy 時の削除依存
- 試行: `terraform destroy` を実行。
- 結果: Storage Sync Service 削除時に `MgmtDeletionDependency` (registered server 残存) で失敗。
- 対応: `az storagesync registered-server delete` で登録サーバーを先に削除し、destroy を再実行して完了。
- 学び: AFS は「Server Endpoint 削除済みでも Registered Server が残る」ケースがある。destroy 失敗時の定型復旧として手順化する。

## 採用/不採用の判断まとめ
- 採用:
  - `null_resource + az CLI` による identity/role 自動化
  - `F:\AFSData` + データディスク方式
  - 既登録エラーを成功扱いする拡張スクリプト
  - 必要時の import ベース復旧手順
  - destroy 失敗時の「registered server 先行削除」復旧手順
- 不採用:
  - `azapi_update_resource` による Storage Sync identity 更新
  - `C:\` 前提の Server Endpoint 標準運用

## 次回チェックリスト
- `Microsoft.StorageSync` が `Registered` か確認
- Key Vault / Storage Sync / Storage Account の権限が Terraform で自動化されているか確認
- `server_endpoint_local_path` が `F:\AFSData` になっているか確認
- 1回目 apply 後に `registered_server_ids` を取得して 2回目 apply する
- Cloud Endpoint 失敗時は `invalid partnership Id` の有無を確認
- VM 側変更検出 (`Invoke-StorageSyncServerChangeDetection`) と Cloud 側変更検出 (`Invoke-AzStorageSyncChangeDetection`) の実行手順を確認
