# 📍 KINTAI 品質検証パイプライン 統括ステータス台帳

最終更新: 2026-11-23 14:12（Track 2 Slice 1 ゼロベース完全新規SRS作成・4層独立交差検証・単一進入点マスターゲート合格・SSOT統合完了）

---

## 1. 現在のマイルストーン

- **プロジェクト位置づけ**: 本リポジトリは、アルバイト勤怠・給与SaaS「KINTAI」の労働基準法計算・並行性制御を担保するための独立品質検証パイプラインです。
- **現行フェーズ**: Track 2（ゼロリファレンスによる完全新規SRS作成および設計対比検証）Slice 1 [店舗・会員管理および権限統制] 完走。
- **進捗状況**:
  - OpenAI Codex (`gpt-6.2-astra`) によるゼロベース初案起草（18.8KB, 9,987文字）。
  - Antigravity、Claude Sonnet 5.5、Local Qwen 27B、C# Roslyn リンターによる4層独立交差監査の完走（指摘21件全数摘発）。
  - `queue/srs_pending_findings.json` への全件キューイングおよび1-Shot統合是正完了（全21件 VERIFIED 遷移）。
  - 単一進入点マスターゲート（`gate_master_srs.ps1`）Stage 1〜3 完全突破、`approval_manifest.json` 公式発行。
  - 単一真実原書（`config/srs_specification_ssot.md`）への原子的一体パッチ（`patch_ssot.ps1`）統合完了。
- **最新ヘルスチェック判定**: `PIPELINE_TRACK2_SLICE1_VERIFIED` (全11項目リポジトリ整合性ゲート100% PASS)

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
