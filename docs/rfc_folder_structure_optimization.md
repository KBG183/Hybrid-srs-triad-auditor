# RFC-008: リポジトリ構成最適化およびクリーンアーキテクチャ標準仕様

- 作成日: 2026-11-24
- 状態: APPROVED (4重交差検証・指摘事項全件反映完了)
- 適用対象: 全リポジトリ構成要素およびCI/CDパイプライン

---

## 1. 概要・背景

本リポジトリは、KINTAI要件定義（SRS）の作成および多層AI（Antigravity、Codex、Claude、Qwen 27B）とC#決定論的リンター（VerifySRS）によるハイブリッド交差検証システムを支える基盤です。
開発の進展に伴い、マルチトラック設計（Track 1/2）、ガバナンス憲法、実行時監査ログ、CSV台帳などの諸機能が拡充され、管理対象はルート直下および11の最上位ディレクトリへと拡張されました。

初期（v1.02）時点の構成図と実態との乖離、ローカル環境における過去監査ログ（`docs/audit_runs/`）の残存、およびツール類の平坦な配置により、構成上の認知的負荷が生じていました。
本RFCは、4重交差監査陣（Codex、Claude、Qwen 27B、VerifySRS）の精査指摘を完全反映し、既存CI/CD、Gitフック、C#リンターのパス依存性を100%維持しながら（Zero-Regression）、ディレクトリ構成の責務を厳格に定義・確立することを目的とします。

---

## 2. ディレクトリ責務・境界マトリクス

リポジトリ内の全資産をルート直下および11領域に分類し、各領域の責務、境界、および正本優先順位（憲法 > SSOT > 承認 > 運用）を定めます。

| 領域・ディレクトリ | 追跡ファイル | 主な責務・格納内容 | ガバナンス・参照規則 |
|---|:---:|---|---|
| `(root)/` | 5 | 憲法（`GEMINI.md`）、仕様書（`README.md`）、Git設定 | 最上位エントリーポイントおよび環境定義 |
| `approved/` | 1 | 承認済みマニフェスト（`approval_manifest.json`）の保管 | 変更時は事前検証および暗号署名必須 |
| `audit/` | 124 | 外部AI監査実機ログ（`audit/runs/`）および静的監査レポート | 過去24時間以内の実機ログ・ハッシュを検証 |
| `config/` | 5 | 単一真実原書（SSOT）および対象定義（`srs_targets.json`） | Track 1/2要件の正本格納領域 |
| `docs/` | 8 | 技術仕様書、RFC、ADR、およびトレーサビリティ文書 | 設計決定およびアーキテクチャ根拠の蓄積 |
| `domain_target/` | 21 | KINTAI業務ドメインフィクスチャ（DDL、労基法37条サービス等） | 参照実装およびテストフィクスチャ |
| `governance/` | 2 | SRS絶対憲法（`ARTICLE_0_SRS.md`）の格納 | リポジトリ最上位ルールとしての排他的管理 |
| `logs/` | 10 | 統括台帳（CSV 5種、MD 3種、実行トレースログ等） | 全数監査・トークン消費・障害インシデント記録 |
| `metrics/` | 2 | パイプライン自動実行メトリクスおよびロックファイル | `pipeline_draft_and_integrate.ps1`の実行記録 |
| `queue/` | 1 | 外部指摘フェイルクローズド・キュー（`srs_pending_findings.json`） | 未解決指摘の残存コミット遮断ゲート |
| `tools/` | 42 | リンター、スクリプト、Gitフック、ルール、テンプレート | 検証エンジンおよび運用自動化ツール群 |
| `.github/` | 1 | GitHub Actions ワークフロー定義（`ci.yml`） | リモートプッシュ時の11大ゲート自動検証 |

---

## 3. パス依存性分析および破壊的変更の抑止

本リポジトリの検証体系は、C#リンター（`VerifySRS.exe`）、統合監査スクリプト（`verify_repo_total_integrity.ps1`）、およびGit事前フックにより強固に結合されています。
不用意なファイル移動やリネームは広範囲のパス破損を招くため、以下の10大カノニカルエントリポイントは現行パスを厳格に維持（保護）します。

| カノニカルエントリポイント | 参照元・依存コンポーネント | 維持理由 |
|---|---|---|
| `tools/scripts/VerifySRS.exe` | CI、Git事前フック、全数検証スクリプト | 決定論的検証の単一チョークポイント |
| `tools/scripts/verify_repo_total_integrity.ps1` | CI、開発者コミット前ゲート | 11大完全性ゲート統括エンジン |
| `tools/scripts/run_quad_audit.ps1` | 4重交差監査パイプライン | Codex / Claude / Qwen 統合リレー実行 |
| `tools/scripts/call_ai.ps1` | 各種自動化スクリプト | 外部AI無出力ストリーミング共通ランナー |
| `tools/scripts/finalize_daily_ledgers.ps1` | スプリント終了処理 | 6大台帳の整合性確認およびコミット準備 |
| `config/srs_targets.json` | CI、リンター、全数監査スクリプト | マルチトラック要件定義の単一登録台帳 |
| `approved/approval_manifest.json` | C#リンター、整合性ゲート | 承認済みSSOT整合性保証マニフェスト |
| `queue/srs_pending_findings.json` | C#リンター（Phase 4）、コミット遮断ゲート | 外部指摘の未消化残存検知チョークポイント |
| `governance/ARTICLE_0_SRS.md` | 全検証エンジン、開発者指針 | 最上位SRS絶対憲法 |
| `.github/workflows/ci.yml` | GitHub Actions CI基盤 | リモートビルド・全数ゲート自動実行定義 |

また、ローカル環境の `docs/audit_runs/` に存在する427件の非追跡ファイルは、初期検証段階の遺産であり、現行パイプラインはすべて `audit/runs/` へ出力されます。
本ファイル群はCIおよびリンターの走査対象外（`.gitignore`）として隔離されており、リポジトリの健全性に影響を与えません。

---

## 4. ドキュメント構成図の同期基準

`README.md` に記載されているディレクトリ構成図を最新のルート直下＋11領域モデルへ更新し、外部向け仕様書としての正確性を回復します。

1. **Constitutional Alignment**: `GEMINI.md` の版数表示を最新（v1.07）へ改訂。
2. **Multi-Track Representation**: `config/` 配下のスライス管理（Track 2 As-Built Slices）を明示。
3. **Governance & Queue Visibility**: `governance/` および `queue/` を構成図に追加。
4. **Tool Inventory Alignment**: `tools/scripts/` 配下の主要スクリプトを機能別に分類して提示。

---

## 5. 移行手順および検証

本最適化は以下の3フェーズで段階的に適用します：

- **Phase A**: 本RFCの策定および4重交差監査（Codex、Claude、Qwen、VerifySRS）による無欠性レビュー。
- **Phase B**: `README.md` および関連ドキュメントの構成図の最新化。
- **Phase C**: `verify_repo_total_integrity.ps1`（12大ゲート）による全件パスの機械的検証。

---

## 6. 4重交差監査指摘の反映および解決検証（Resolution Table）

4重交差監査陣（Codex、Claude、Qwen 27B）より提示された指摘事項はすべて中央キュー（`queue/srs_pending_findings.json`）へ登録され、以下の物理的証跡に基づき全件解決（`VERIFIED`）を確認しました。

| 指摘ID | 監査官 | 対象・論点 | 適用された是正措置 | 検証状態 |
|---|---|---|---|:---:|
| `FINDING-RFC-001` | Codex | 起動パス互換性 | カノニカルエントリポイント5系統および相対パス参照の回帰遮断をCheck 12で機械的検証 | **VERIFIED** |
| `FINDING-RFC-002` | Codex | 監査証跡・ハッシュ結合 | `verdict.json`の`response_sha256`と生レポートの厳格バインドおよびCheck 11検証 | **VERIFIED** |
| `FINDING-RFC-003` | Codex | 多層AI監査成立条件 | 本RFC §5およびREADMEにVerifySRSおよび12大ゲートの検査項目・役割分担を明記 | **VERIFIED** |
| `FINDING-RFC-004` | Codex | ルート直下資産の境界 | 本RFC §2にルート資産のガバナンス境界定義および旧ログ隔離規約を追加 | **VERIFIED** |
| `FINDING-RFC-005` | Codex | logs/台帳対応表 | `docs/powershell_scripts_manifest.csv`（32種）新設および`finalize_daily_ledgers.ps1`の同期 | **VERIFIED** |
| `FINDING-RFC-006` | Claude | 正本優先順位の厳格化 | `GEMINI.md` 第3条および本RFC §2にSSOT原則と優先順位（憲法 > SSOT > 運用）を明文化 | **VERIFIED** |
| `FINDING-RFC-007` | Claude | 自動ドリフト防止ゲート | `verify_repo_total_integrity.ps1` にCheck 12（ツリー構造整合性ゲート）を実装完了 | **VERIFIED** |
