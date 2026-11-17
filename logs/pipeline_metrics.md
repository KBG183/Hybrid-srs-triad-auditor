# 📊 多層パイプライン検証メトリクス ＆ 監査ダッシュボード

最終更新: 2026-11-17 | システムバージョン: v1.02

---

## 🚦 1. パイプライン総合稼働状態 (Summary)
* **確定要件定義**: 単一真実原書（`config/srs_specification_ssot.md`）承認済み（全8要件確定）
* **C# 決定論的リンター**: `ONLINE`（`VerifySRS_Deterministic.cs` v1.1 Fail-Closed 0.05秒検証）
* **Codex 独立交差監査**: `STANDBY`（読み取り専用サンドボックス・自動ルーティング対応）
* **ローカル Qwen 27B**: `ONLINE`（Ollama REST API・自社GPU RTX 5070 Ti P2P高速化）
* **最終検証ゲート**: `VERIFIED`（9/9 C#決定論的回帰テスト全件PASS達成）

---

## 2. 要件完全性検証スコア (SSOT Slice 1 全8要件)
| ID | 要件項目 | C# リンター | Qwen 27B | Codex 監査 | 最終判定 |
| :--- | :--- | :---: | :---: | :---: | :---: |
| REQ-STORE-001 | 店舗初期登録およびオーナー自動紐付け | PASS | PASS | PASS | **PASS** |
| REQ-MEMBER-001 | 新規会員登録およびロール初期化 | PASS | PASS | PASS | **PASS** |
| REQ-STAFF-001 | スタッフ招待および二重承認制約 | PASS | PASS | PASS | **PASS** |
| REQ-STAFF-002 | スタッフ招待受託および時給・交通費設定隔離 | PASS | PASS | PASS | **PASS** |
| REQ-LABOR-001 | 法定労働時間超過（時間外割増 25%）計算 | PASS | PASS | PASS | **PASS** |
| REQ-LABOR-002 | 法定深夜労働（22:00〜05:00 割増 25%）計算 | PASS | PASS | PASS | **PASS** |
| REQ-LABOR-003 | 時間外 ＋ 深夜重複（割増 50%）単一適用 | PASS | PASS | PASS | **PASS** |
| REQ-LABOR-004 | 休日労働（割増 35%）法定計算 | PASS | PASS | PASS | **PASS** |

---

## 3. 監査・障害対応履歴
* **実運用障害・再発防止台帳**: [`logs/incident_history_ledger.md`](incident_history_ledger.md)（全18件の技術課題・恒久対策を記録）
* **トークン・コスト数値原帳**: [`logs/enterprise_audit_ledger.csv`](enterprise_audit_ledger.csv)
