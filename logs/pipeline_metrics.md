# 📊 多層パイプライン検証メトリクス ＆ 監査ダッシュボード

最終更新: 2026-11-19 | システムバージョン: v1.02

---

## 🚦 1. パイプライン総合稼働状態 (Summary)
* **確定要件定義**: 単一真実原書（`config/srs_specification_ssot.md`）全12要件
* **最新統合監査判定**: `AUDIT_FINDINGS_REPORTED`（`enterprise_audit_ledger.csv` BATCH-11 準拠: 4層交差検証実行（C#リンターPASS・Qwen27B完了・Codex指摘・Claude5.5により法定休日除外およびEXCLUDE排他制約P0課題是正確定））
* **C# 決定論的リンター**: `ONLINE`（`VerifySRS_Deterministic.cs` ＋ `VerifySRS_Integrity.cs` Fail-Closed 確定論的構文・無欠性検証）
* **Codex 独立交差監査**: `ONLINE`（無損失UTF-8バイトストリーム・GPT-6.2 Astra自動ルーティング対応）
* **ローカル Qwen 27B**: `ONLINE`（Ollama REST API・自社GPU RTX 5070 Ti P2P高速化）
* **Claude 深層法規監査**: `ONLINE`（Anthropic Claude Sonnet 5.5 労基法第37条・不変性深層検証）
* **最終検証ゲート**: `ACTIVE`（C#決定論的回帰テストスイート連動）

---

## 2. 要件完全性検証スコア (SSOT 全12要件 - BATCH-11 4層交差監査連動)
| ID | 要件項目 | C# リンター | Qwen 27B | Codex 監査 | Claude 5.5 | 最終判定 |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| REQ-STORE-001 | 店舗マスター登録および招待コード・QRトークン管理 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-MEMBER-001 | 会員登録・BCrypt認証およびRBAC認可制御 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-STAFF-001 | 店舗スタッフ所属申請・オーナー承認および多店舗アクセス制御 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-STAFF-002 | 給与算定用契約条件（時給・交通費）履歴管理および期間排他制御 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-SHIFT-001 | スタッフ希望シフト申請および排他制御（悲観的ロック） | PASS | PASS | PASS | PASS | **PASS** |
| REQ-SHIFT-002 | 店長によるシフト確定調停および労働基準法第34条法定休憩時間の算定 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-SHIFT-003 | 希望シフト申請の本人取消および状態遷移制御 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-SHIFT-004 | カレンダー表示連携（FullCalendar 6.x）およびプライバシー保護 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-LABOR-001 | 法定労働時間超過・時間外割増手当（日8時間および週40時間基準）の算定 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-LABOR-002 | 深夜労働割増手当（深夜手当・半開区間境界）の算定 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-LABOR-003 | 時間外・深夜・法定休日の重畳割増マトリクスおよび月次端数処理統制 | PASS | PASS | PASS | PASS | **PASS** |
| REQ-LABOR-004 | 悲観的ロック（Pessimistic Lock）および一意制約に基づく給与確定トランザクション整合性 | PASS | PASS | PASS | PASS | **PASS** |

---

## 3. 監査・障害対応履歴
* **実運用障害・再発防止台帳**: [`incident_history_ledger.md`](incident_history_ledger.md)（全30件の技術課題・恒久対策を記録）
* **監査実行台帳**: [`enterprise_audit_ledger.csv`](enterprise_audit_ledger.csv)
* **クラウドトークン消費台帳**: [`cloud_api_token_ledger.csv`](cloud_api_token_ledger.csv)
