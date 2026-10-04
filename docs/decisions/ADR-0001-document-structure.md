# ADR-0001: Project Documentation Structure

- Status: Accepted
- Date: 2026-10-04

## Context

`NOTE.md`に、確定した要件、検討中の案、将来構想、構成案が混在していた。エージェントが検討中の案を確定仕様として実装したり、常時読むべきルールが埋もれたりする可能性があった。

## Decision

次の責務分離を採用する。

- `AGENTS.md`: 常に適用するエージェント向けルールと文書参照ポインター
- `docs/project-specification.md`: 確定した目的、MVP要件、制約、受け入れ条件
- `docs/architecture.md`: システム構成、データフロー、運用構成
- `docs/open-questions.md`: 未決定で判断が必要な項目
- `docs/roadmap.md`: MVP後の将来構想
- `docs/decisions/`: 重要な設計判断と理由

`NOTE.md`は正式文書への移行案内だけを残す。

## Consequences

エージェントはタスクに必要な文書だけを段階的に参照でき、検討中の案を誤って実装しにくくなる。一方、情報を複数ファイルへ分けるため、仕様変更時には該当文書と参照ポインターを同時に更新する必要がある。
