# Documentation Standards

このディレクトリは、`terraform/` 配下の各プロジェクトで再利用するドキュメント標準を管理する。

## 基本方針
- 原則は `Terraform` で構築し、Terraform で不足する箇所のみ `CLI/API` を併用する。
- 手作業は残さず、再現手順を `tasks.md` に明文化する。
- 要件から手順までのトレーサビリティを維持する。

## 標準セット
- `requirements.md`: 何を実現するか
- `design.md`: どう実現するか
- `parameters.md`: 何を入力値として管理するか
- `tasks.md`: どう実行・検証するか
- `rules.md`: 何を守るか
- `retrospective.md`: 何を学び、次回にどう活かすか
- `security-rules.md`: エージェント運用時の共通セキュリティルール

## 推奨配置
各プロジェクト配下に `docs/` を作成し、以下を配置する。

```text
<project>/
  main.tf
  variables.tf
  docs/
    requirements.md
    design.md
    parameters.md
    tasks.md
    rules.md
    retrospective.md
```

## 読み順
1. `requirements.md`
2. `design.md`
3. `parameters.md`
4. `tasks.md`
5. `rules.md`
6. `retrospective.md`
