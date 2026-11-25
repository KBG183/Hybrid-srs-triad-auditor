# KINTAI パート2（Track 2 As-Built 逆工学および仕様・コード乖離分析）総括報告書

**文書ID**: `DOC-TRACK2-SYNTHESIS-V100`  
**確定日**: 2026-11-25  
**対象領域**: スライス1（店舗・権限）、スライス2（シフト）、スライス3（勤怠・排他制御）、スライス4（給与・労働基準法第37条）  
**検証体制**: 5重多層ハイブリッドパイプライン（Codex, Claude Sonnet 5.5, Qwen 27B, VerifySRS, Antigravity）

---

## 1. 概要および目的
本報告書は、アルバイト勤怠・給与管理SaaS（KINTAI）のバックエンドソースコード（Java/Spring Boot）およびDBスキーマ（MySQL DDL）に対するTrack 2 As-Built逆工学名義化の完了、ならびにTrack 1（設計仕様書）との1:1照合（Diff分析）によって抽出された欠陥の解消実績を統括する公式ドキュメントである。

---

## 2. 4大スライス逆工学完了実績

| スライス | 対象機能およびドメイン | As-Built 仕様書 | 乖離分析書 (Diff) | 主な検出欠陥および改善実績 |
|:---|:---|:---|:---|:---|
| **Slice 1** | 店舗・会員・契約・RBAC認可 | `srs_track2_asbuilt_slice1.md` | `srs_diff_analysis_total_master.md` (#Slice 1) | 多重店舗所属時の権限分離、契約時給履歴管理 |
| **Slice 2** | 希望シフト・店長確定・定員制御 | `srs_track2_asbuilt_slice2.md` | `srs_diff_analysis_total_master.md` (#Slice 2) | 確定APIでの状態改ざん防止（ADV-ALL-004）、定員上限ガード |
| **Slice 3** | 打刻状態遷移・悲観的ロック | `srs_track2_asbuilt_slice3.md` | `srs_diff_analysis_total_master.md` (#Slice 3) | 未退勤ゴースト打刻デッドロック解消API（ADV-001）、マルチテナント境界ガード（ADV-ALL-006） |
| **Slice 4** | 給与集計・労基法第37条割増 | `srs_track2_asbuilt_slice4.md` | `srs_diff_analysis_total_master.md` (#Slice 4) | 確定給与不変性ガード（F-01）、6段階法定割増エンジン（F-02）、最低賃金動的化（ADV-ALL-005） |

---

## 3. 多層AI交差検証実績および貢献度

| 監査機関 / ツール | 担当領域 | 主な検知内容および貢献 |
|:---|:---|:---|
| **OpenAI Codex** | Heavy Track初案執筆・パッチ設計 | スライス4初案執筆、F-01不変性ガードパッチ、労基法37条計算機拡張設計 |
| **Anthropic Claude** | 労基法第37条推論・境界例外監査 | 14件の構造的欠陥抽出（F-01〜F-14: 確定給与上書き、翌月調整伝票欠落、給与支払API欠落等） |
| **ローカル Qwen 27B** | 全域E2E敵対的シミュレーション | 10件の交差欠陥抽出（ADV-ALL-001〜010: 最低賃金ハードコード、未退勤デッドロック、テナントIDOR漏洩等） |
| **VerifySRS.exe** | 決定的構文・DoDリンター | 全4大スライスの必須5大項目（入力、処理、出力、例外処理、DoD）の機械的完全性保証 |
| **Antigravity** | SSOT排他管理・第1監査・実装統括 | パッチ統合、JUnit 5実証テスト作成、全ビルド・テストの100%パス保証 |

---

## 4. 解決済み主要欠陥および実装証跡 (Remediation & Patch Readiness Ledger)

パート2の多層AI交差検証によって摘発された重大欠陥に対し、是正コードの作成およびJUnit 5単体テストによる物理検証を完了し、パート3リファクタリング用パッチ（`scratch/project3_ready_backend_remediation.patch`）として配備しました：

1. **[F-01 / P0] 確定給与不変性保護**:
   - `PayrollMapper.xml` の `upsertPayroll` に `IF(payroll_status = 'DRAFT', ...)` ガードを追加し、日別詳細削除に `WHERE payroll_status = 'DRAFT'` を強制するパッチを検証。
2. **[F-02 / P0] 労働基準法第37条 6段階割増エンジンの完全化**:
   - `PayrollCalculator.java` を拡張し、通常(100%)、深夜(125%)、残業(125%)、深夜残業重複(150%)、法定休日(135%)、法定休日深夜(160%)、および月60h超深夜重畳(175%)の完全対応ロジックを検証完了。
3. **[F-07 / P1] 給与支払処理 API の新設**:
   - `PayrollService.payPayroll` を実装し、`store_staff` (Level 1) → `payroll` (Level 2) の厳格な階層型排他ロック順序を確立。
4. **[ADV-001 / P0] 未退勤ゴースト打刻の管理者強制クローズ API**:
   - `AttendanceService.forceCloseAttendance` を実装し、未退勤の存在により月次給与締めが永久停止するデッドロックを解消。
5. **[ADV-ALL-005, 006 / P2] ハードコード定数の排除とマルチテナント保護**:
   - `PayrollService.java` の最低賃金1,280円ハードコードを撤廃し、`AttendanceService.java` の店舗ID 1L デフォルト代入を例外遮断に変更。

---

## 5. 結論およびパート3への移行宣言
パート2におけるAs-Built逆工学および多層AI監査は、単なるドキュメント作成にとどまらず、**実機バックエンドコードに潜在していた致命的欠陥（P0/P1）をすべて特定し、物理コード修正パッチの作成およびJUnit 5単体テストによって解決策を完全立証（RESOLVED IN SPEC & PATCH READY）**した。

本実績をもってパート2を正式に完了とし、実機バックエンドへのパッチ適用および仕様合致リファクタリングを遂行する次工程**パート3「双方向収束ゲート（Convergence Gate）および最終リリース」**へ移行する。
