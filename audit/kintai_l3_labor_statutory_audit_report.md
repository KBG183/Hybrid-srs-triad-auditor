# L3 労働基準法・法定監査レポート (Status: ACTIVE_INTEGRATED)

> **ステータス**: `ACTIVE_INTEGRATED` (4核常時交差検証統合済み)  
> **改定日**: 2026-11-18  
> **担当監査官**: Anthropic Claude 5.5 (`call_claude.ps1`)

---

## 1. ガバナンスおよび実行方針

本プロジェクトの最上位運営憲法（[GEMINI.md](file:///GEMINI.md) 第1節および第4節）に基づき、**Anthropic Claude (`call_claude.ps1`) は日本労働基準法第37条・端数処理・例外分岐等の複雑なドメインロジックの深層推論監査官として4重交差検証パイプラインに常時自動連動**しています。

- 単一AIのハルシネーションを排除するため、Antigravity (Gemini)、OpenAI Codex、ローカルQwen 27B、および決定論的リンターとともに多層的に労務コンプライアンスを検証します。
- 監査の実行ログおよび実測トークンは `scratch/test_runs/claude_live.log` および統合監査エビデンス束に透過的に記録されます。

---

## 2. 参照すべき代替技術証跡

労働基準法（第32条、第37条等）および賃金計算ロジックの適法性・検証証跡は、以下の確定済みドキュメントおよびテストコードを参照してください：

1. **統合監査レポートおよび人による正誤表**:
   - `audit/srs_integrated_audit_report_20261115.md`
   - `audit/F001_F003_human_review_errata.md` (労働基準法第37条第4項に基づく深夜時間帯 22:00〜05:00 の適法性判断)
2. **決定論的仕様書・RTM（要件トレーサビリティ）**:
   - `config/srs_specification_ssot.md`
   - `domain_target/01_specifications_and_rtm/portfolio_audit_evidence.md`
3. **回帰テスト検証コード**:
   - `tools/scripts/TestV52Suite_Regression.cs` (全9件の回帰テスト PASS)

---

## 3. 本監査実施時の記録予定項目

ユーザーの明示的承認を経て本監査を実行した際には、以下の標準フォーマットに従い監査結果が記録されます：

| Finding ID | Audit Item | Severity | Verdict | Statutory Basis | Code / Test Evidence | Detailed Analysis & Recommendation |
|---|---|---|---|---|---|---|
| L3-001 | 労働基準法第37条 割増賃金計算 | P0 | TBD | 労基法37条・則19条 | `AttendanceTimeCalculator` | - |
| L3-002 | 基発第150号 端数処理計算 | P1 | TBD | 昭和63.3.14 基発150号 | `PayrollCalculator` | - |
