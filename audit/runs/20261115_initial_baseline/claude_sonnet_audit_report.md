# L3 労働基準法・法定監査レポート (Status: NOT_EXECUTED)

> **ステータス**: `NOT_EXECUTED` (本文未作成 / 実行保留)  
> **最終確認日**: 2026-11-15  
> **担当監査官**: Anthropic Claude 3.5 Sonnet / 3.7 Sonnet (予定)

---

## 1. 未実施の理由およびガバナンス方針

本プロジェクトの最上位運営憲法（`GEMINI.md` 第4節「変更権限および承認ワークフロー - 従量課金API費用保護原則」）に基づき、**Anthropic Claude (`call_claude.ps1`) による多層・深層監査は従量課金保護対象**として厳格に管理されています。

- ユーザーからの明示的な指示（「Claude呼出」「L3監査実施」）がない限り、自動バッチやパイプラインによる無断実行をFail-Closed方針により禁止しています。
- 本リポジトリの継続的検証は、無償かつ高速な確定論的リンター（`VerifySRS_Integrity.exe`）、回帰テストスイート（`TestV52Suite_Regression.exe`）、およびOpenAI Codex CLI（`call_codex.ps1`）、リモートQwen 27B（`call_qwen.ps1`）によって担保されています。

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
   - `tools/scripts/TestV52Suite_Regression.cs` (全94件の回帰テスト PASS)

---

## 3. 本監査実施時の記録予定項目

ユーザーの明示的承認を経て本監査を実行した際には、以下の標準フォーマットに従い監査結果が記録されます：

| Finding ID | Audit Item | Severity | Verdict | Statutory Basis | Code / Test Evidence | Detailed Analysis & Recommendation |
|---|---|---|---|---|---|---|
| L3-001 | 労働基準法第37条 割増賃金計算 | P0 | TBD | 労基法37条・則19条 | `AttendanceTimeCalculator` | - |
| L3-002 | 基発第150号 端数処理計算 | P1 | TBD | 昭和63.3.14 基発150号 | `PayrollCalculator` | - |
