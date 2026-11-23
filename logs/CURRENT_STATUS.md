# 📍 KINTAI 品質検証パイプライン 統括ステータス台帳

最終更新: 2026-11-23 13:28（共通検証コアSRS移植 ADR-004・単一進入点マスターゲート構築・4層交差検証・11/11ハードゲートPASS）

---

## 1. 現在のマイルストーン

- **プロジェクト位置づけ**: 本リポジトリは、アルバイト勤怠・給与SaaS「KINTAI」の労働基準法計算・並行性制御を担保するための独立品質検証パイプラインです。
- **現行フェーズ**: 事前検証済み共通検証コアのSRSプロファイル移植および単一進入点マスターゲート構築（ADR-004）完了（第0条SRS憲法配備、外部指摘キュー確立、4層交差検証合格、全11項目リポジトリ整合性ゲートPASS）
- **障害・再発防止台帳**: `logs/incident_history_ledger.md`（実運用中の課題と恒久対策を記録）
- **最新ヘルスチェック判定**: `PIPELINE_V12_INTEGRITY_CLEAN` (ADR-004: 共通検証コア移植・単一進入点マスターゲート(gate_master_srs.ps1)配備・4層交差検証合格・全11ゲート100% PASS)

---

## 2. 検証パイプラインの構成

1. **単一進入点直列マスターゲート**: `gate_master_srs.ps1` (事前点検 ➔ 規格検証 ➔ 最終承認のFail-Closedパイプライン・終了コード0〜4厳格契約・SkipAi承認遮断)
2. **第0条SRS絶対憲法およびハッシュロック**: `governance/ARTICLE_0_SRS.md` + `.sha256` (2.1KB高密度不可変ルール・改ざん時Exit 4即時遮断)
3. **外部指摘事項追跡キュー**: `queue/srs_pending_findings.json` (未解消欠陥残存時の承認物理遮断・2-Tier是正プロセス)
4. **統括オーケストレーター**: Antigravity (Google Gemini Engine — ワークスペース調整・SSOT管理)
5. **統合AIストリーミング基盤**: `call_ai.ps1` (OpenAI Codex, Anthropic Claude, Local Qwen 27B — 非同期デッドロック防止・Unicode正規表現保護・P0/P1 Fail-Closed契約)
6. **単一C#マスターリンター**: `VerifySRS.exe v1.2` (`VerifySRS.cs` — 構文・DoD・カルチャ非依存日付・テーブル構造の統合検証)
7. **原子的SSOT反映基盤**: `patch_ssot.ps1` (ジャンクション走査防止・PID生存確認排他ロック・SHA-256完全一致ロールバック)
8. **確定論的ハードゲート**: `verify_repo_total_integrity.ps1` (11/11 総合無欠陥検証PASS)

---

## 3. 実証対象ドメイン (`domain_target/`)

- **対象プロダクト**: 店長・アルバイト向け勤怠・シフト・給与管理SaaS（KINTAI）
- **主要検証資産**: MySQL 8.4 DDL、労働基準法第37条割増賃金計算エンジン、InnoDB悲観的ロックによる二重打刻防止・デッドロック解消サービス、JUnit 5統合テスト
