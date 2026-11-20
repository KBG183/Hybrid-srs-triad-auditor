# 📍 KINTAI 品質検証パイプライン 統括ステータス台帳

最終更新: 2026-11-20 11:10（Day 4 第4スライス給与・労基法第37条要件4層交差検証・11/11ハードゲートPASS・Track 1完走）

---

## 1. 現在のマイルストーン

- **プロジェクト位置づけ**: 本リポジトリは、アルバイト勤怠・給与SaaS「KINTAI」の労働基準法計算・並行性制御を担保するための独立品質検証パイプラインです。
- **現行フェーズ**: Day 4 スプリント完了（第4スライス給与・労基法第37条計算エンジン・階層悲観的ロック要件の4層交差検証完了、全4スライス・17要件・15 DDLのTrack 1設計検証100%完走）
- **障害・再発防止台帳**: `logs/incident_history_ledger.md`（実運用中の課題と恒久対策を記録）
- **最新ヘルスチェック判定**: `TRACK1_COMPLETED_CLEAN` (enterprise_audit_ledger.csv BATCH-12: 4層交差検証実行（Codex Astra初案執筆・Claude 5.5深層監査・Local Qwen 27B適応・C#決定論的11/11ゲート全数PASS・F-DAY4-001~007全件RESOLVED）)

---

## 2. 検証パイプラインの構成

1. **統括オーケストレーター**: Antigravity (Google Gemini Engine — ワークスペース調整・SSOT管理)
2. **高速文脈分析器**: ローカル Qwen 27B (`call_qwen.ps1` — RTX 5070 Ti P2Pリモートアクセラレーション)
3. **機能・境界交差監査官**: OpenAI Codex CLI (`call_codex.ps1` — 読み取り専用サンドボックス、自動ルーティング機能付き)
4. **労務・法令深層監査官**: Anthropic Claude (`call_claude.ps1` — 運営規約に準拠した4重交差検証の常時監査官)
5. **確定論的ハードゲート**: C#決定論的リンター (`verify_repo_total_integrity.ps1 -Fix` — 10/10 総合無欠陥検証PASS)

---

## 3. 実証対象ドメイン (`domain_target/`)

- **対象プロダクト**: 店長・アルバイト向け勤怠・シフト・給与管理SaaS（KINTAI）
- **主要検証資産**: MySQL 8.4 DDL、労働基準法第37条割増賃金計算エンジン、InnoDB悲観的ロックによる二重打刻防止・デッドロック解消サービス、JUnit 5統合テスト
