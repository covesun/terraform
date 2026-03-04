# Project Doc Style

`file_sync_test` の記述をベースに、実用性の高いスタイルを標準化する。

## スタイル原則
- 先に目的、後に実装。
- 文章より箇条書きを優先。
- すべてのドキュメントに検証可能な条件を入れる。
- コストとセキュリティの判断理由を明記する。

## 推奨トーン
- 短く、具体的に、曖昧語なしで書く。
- 「できるだけ」ではなく「何を許可し、何を禁止するか」を書く。

## 必須セクション
- `requirements.md`: 目的 / 要件 / 前提 / 非機能要件 / 受け入れ条件
- `design.md`: 構成概要 / 判断理由 / 検証フロー / セキュリティ留意点
- `parameters.md`: 変数一覧表 / 環境差分 / 変更履歴
- `tasks.md`: フェーズ別手順 / 期待結果 / 失敗時対応 / 実行証跡
- `rules.md`: 更新順序 / 記述ルール / 構築ルール / レビュー観点

## Terraform ファイル配置標準
- Terraform ファイルは原則プロジェクト直下に配置する。
- 最小構成の推奨:
  - `main.tf`
  - `variables.tf`
  - `outputs.tf`
- 規模拡大時の推奨分割:
  - `versions.tf` (Terraform と Provider バージョン固定)
  - `providers.tf` (provider 設定分離)
  - `locals.tf` (locals 定義が増えた場合)
  - `network.tf`, `compute.tf`, `monitoring.tf` など責務別分割
- 入力例は `terraform.tfvars.example` を置き、`terraform.tfvars` は Git 管理しない。
- 実行生成物 (`.terraform/`, `*.tfstate`, `plan.out`) はドキュメント管理対象外とする。

## 命名
- ドキュメント名は固定: `requirements.md`, `design.md`, `parameters.md`, `tasks.md`, `rules.md`
- プロジェクト名は見出し1行目に記載する。

## 運用
- 新規プロジェクト開始時は `docs/templates/` から複製して作成する。
- 変更時は `tasks.md` の `Execution Log` に実施記録を残す。
