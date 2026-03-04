# file_sync_test parameters

Created-By: codex

## Terraform Parameters

| Name | Type | Required | Default | Example | Description | Source |
|---|---|---|---|---|---|---|
| `subscription_id` | `string` | Yes | - | `<AZURE_SUBSCRIPTION_ID>` | 対象 Azure サブスクリプション ID | requirements |
| `key_vault_name_prefix` | `string` | No | `kvfilesync` | `kvfilesync` | 作成する Key Vault 名プレフィックス (suffix 自動付与) | requirements |
| `prefix` | `string` | No | `filesync` | `filesync` | リソース名接頭辞 | design |
| `location` | `string` | No | `japaneast` | `japaneast` | デプロイ先リージョン | requirements |
| `admin_username` | `string` | No | `azureuser` | `azureuser` | VM 管理者ユーザー名 | requirements |
| `admin_password_secret_name` | `string` | No | `filesync-vm-admin-password` | `filesync-vm-admin-password` | 生成パスワードを保存する Secret 名 | requirements |
| `admin_password_length` | `number` | No | `20` | `20` | 生成する管理者パスワード長 | rules |
| `password_rotation_token` | `string` | No | `initial` | `2026-03-05-rotate1` | 任意文字列。変更するとパスワード再生成を強制 | tasks |
| `vm_size` | `string` | No | `Standard_B2s` | `Standard_B2s` | VM サイズ | design |
| `data_disk_size_gb` | `number` | No | `128` | `128` | Server Endpoint 用データディスクサイズ (GB) | design |
| `file_share_name` | `string` | No | `shared` | `shared` | Azure Files 共有名 | design |
| `file_share_quota_gb` | `number` | No | `100` | `100` | Azure Files クォータ | design |
| `storage_sync_service_name` | `string` | No | `filesync-svc` | `filesync-svc` | Storage Sync Service 名 | design |
| `storage_sync_group_name` | `string` | No | `filesync-group` | `filesync-group` | Sync Group 名 | design |
| `storage_sync_cloud_endpoint_name` | `string` | No | `filesync-cloud-endpoint` | `filesync-cloud-endpoint` | Cloud Endpoint 名 | design |
| `server_endpoint_local_path` | `string` | No | `F:\\AFSData` | `F:\\AFSData` | VM ローカル同期フォルダ (データディスク上) | design |
| `afs_agent_download_url` | `string` | Yes | `""` | `<AFS_AGENT_MSI_URL>` | AFS Agent MSI URL | requirements |
| `registered_server_ids` | `map(string)` | 2回目applyでYes | `{}` | `{ vm1 = "...", vm2 = "..." }` | Server Endpoint 作成用の registered server id | tasks |

## CLI/API Parameters

| Name | Required | Example | Description | Source |
|---|---|---|---|---|
| `az_subscription` | Yes | `<AZURE_SUBSCRIPTION_ID>` | `az` CLI 実行先サブスクリプション | tasks |
| `kv_name` | Yes | `kv-terraform-dev` | VM ログイン時に参照する Key Vault 名 | tasks |
| `kv_secret_name` | No | `filesync-vm-admin-password` | VM ログイン時に参照する Secret 名 | tasks |

## 環境差分

| Environment | Difference | Reason |
|---|---|---|
| `dev` | 既定値を利用 | 検証スピード優先 |
| `prod-like` | `vm_size`, `file_share_quota_gb` を増強 | 性能検証 |

## 変更履歴
- 2026-03-05: Azure File Sync 構成向けに更新
- 2026-03-05: admin_password を Terraform生成 + Key Vault 保存方式へ変更
- 2026-03-05: Key Vault を外部参照から同一スタック作成へ変更
