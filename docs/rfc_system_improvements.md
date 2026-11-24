# KINTAI パイプライン・ガバナンス システム機能改善 RFC (v1.0)

## 1. 提案概要および背景

本RFCは、アルバイト勤怠・給与管理SaaS（KINTAI）の要件定義書逆工学（Track 2）および多層AIハイブリッド交差検証システムにおける運用課題に基づき、パイプラインの堅牢性、自動化、決定論的検証精度を抜本的に高めるための5大機能・システム改善策を定義します。

## 2. 5大システム・機能改善仕様

### 2.1 [RFC-SYS-01] GitHub Actions CIにおける targets 動的巡回検証エンジンの配備
- **背景**: 現行 `.github/workflows/ci.yml` は検証対象が3ファイル（`ssot.md`, `common_contract.md`, `asbuilt_slice1.md`）にハードコードされており、本日追加された `srs_track2_asbuilt_slice2.md` や今後の Slice 3/4 が自動検収から脱落する構造的脆弱性を抱えています。
- **改善仕様**: `config/srs_targets.json` をPowerShellで直接読み取り、`"required": true` かつ物理ファイルが存在する全ターゲットを動的抽出して `VerifySRS.exe` を一括ループ検証します。

### 2.2 [RFC-SYS-02] パイプライン初案統合直後の自動Gitステージング（Auto-Staging）ガード
- **背景**: `pipeline_draft_and_integrate.ps1` でCodex初案を統合した直後はファイルがUntracked状態であり、AIコンテキスト圧縮（チェックポイント復元）時にファイルが消失するリスクが存在します。
- **改善仕様**: 初案リンター検証合格およびファイル配置（`[PIPELINE INTEGRATED]`）直後に、自動的に `git add "$OutputTargetFile"` を実行し、Gitインデックス（Staged Blob）として物理ロックします。

### 2.3 [RFC-FUNC-03] DDL静的メタデータ自動抽出エンジン (`extract_ddl_spec.ps1`) の新設
- **背景**: LLMにDDL全文を自然言語プロンプトとして渡すと、カラム総数（14列を15列と誤認）等の数値・制約の近似値ハルシネーションが発生します。
- **改善仕様**: `domain_target/02_database_schema_ssot/schema.sql` を正規表現解析し、テーブルごとの正確な列数・列名リスト・PK・FK・CHECK制約を抽出するツールを新設します。これをCodexプロンプトに `[IMMUTABLE DDL GROUND TRUTH]` として強制注入します。

### 2.4 [RFC-FUNC-04] C#決定論的リンター (`VerifySRS.cs`) へのFSM状態遷移・ロック順序検証規則装填
- **背景**: 現行リンターはDoD5大項目や禁止語を検査しますが、Track 2の核心である状態遷移（`SUBMITTED ➔ CONFIRMED ➔ REJECTED`）や4階層ロック順序（`member ➔ store ➔ store_staff ➔ contract_history`）の逆転はAIの読解に依存しています。
- **改善仕様**: `VerifySRS.cs` に `RULE-FSM-01` および `RULE-LOCK-01` を新設し、要件定義書内の状態遷移表記およびロック順序が `srs_track2_common_contract.md` と乖離している場合に `[FATAL]` を送出します。

### 2.5 [RFC-GOV-05] コミット直後ワーキングツリー残余差分の自動クリーン化規約
- **背景**: Pre-Commitフック実行時に `approval_manifest.json`、`incident_execution_trace.log`、`verify_repo_total_integrity.ps1` が自動更新され、コミット完了直後に未追跡差分が残存します。
- **改善仕様**: マニフェスト更新およびログ追記を先行コミットに内包するか、コミット直後の自動クリーン同期バッチを整備し、常に `working tree clean` を保ちます。

## 3. 改善提案の比較評価マトリクス

| 提案番号 | 対象領域 | 影響度 | 実装難易度 | 即時適用可否 |
|---|---|:---:|:---:|:---:|
| **RFC-SYS-01** | CI/CD パイプライン | 高 | 低 | 即時適用可能 |
| **RFC-SYS-02** | 開発環境・データ保護 | 高 | 低 | 即時適用可能 |
| **RFC-FUNC-03** | AIプロンプト・メタデータ抽出 | 中 | 中 | 即時適用可能 |
| **RFC-FUNC-04** | C# Roslyn 決定論的リンター | 高 | 中 | 段階的配備 |
| **RFC-GOV-05** | Git構成ガバナンス | 中 | 低 | 即時適用可能 |
