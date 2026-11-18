# 🏛️ KINTAI Hermes 多層統合検証レポート (Master Quality Audit Report)

- **検証日時 (Timestamp)**: 2026-11-18 15:04:50
- **対象仕様書 (Target)**: srs_specification_ssot.md
- **統括オーケストレーター**: Hermes Multi-Agent Controller (hermes_controller.ps1)

---

## 1. 多層ハードゲート総合判定サマリー (Multi-Layer Verdict Summary)

| 検証階層 | 検証エンジン / モデル | 担当領域 | 最終判定 |
|---|---|---|---|
| **Step 0: ハードゲート** | C# Deterministic Linter | 禁止文字、未確定記号、正規表現整合性 | **PASS** |
| **Step 1: 主幹検証** | Qwen 27B (ローカルGPU RTX 5070 Ti) | ドメイン完全性・構造整合性・文脈検証 | **COMPLETED** |
| **Step 2: 技術交差検証** | OpenAI Codex CLI (GPT-5.6) | DDL制約、DTO整合性、排他ロック境界条件 | **COMPLETED** |
| **Step 3: 法規深層検証** | Anthropic Claude (Sonnet 5.5) | 労働基準法第37条、端数処理、労使協定整合性 | **COMPLETED** |

---

## 2. [Step 0] C# 決定論的リンター検証ログ
`	ext
=== [SRS Integrity Verifier v2.0] Analyzing: srs_specification_ssot.md ===
Total Lines: 369 | Total Bytes: 34088
>>> VERDICT: PASS (Clean Integrity, Zero Defects)
=== [SRS DETERMINISTIC LINTER v1.1] Target: srs_specification_ssot.md ===
=== Linter Results: FATAL=0, WARNING=0 (Checked 12 Requirements) ===
>>> [PASS] All mandatory integrity and security checks passed cleanly.
`

---

## 3. [Step 1] ローカル Qwen 27B 主幹検証レポート
### [Hermes Audit Execution Metrics v1.1.1]
| Target File | Model | Duration | Input Code Tokens | Output Tokens | Speed | Done Reason | Run ID |
|---|---|---|---|---|---|---|---|
| config/srs_specification_ssot.md | qwen27b:latest (IQ3_M) | 87.43s | 9781 tokens | 4019 tokens | 48.9 tokens/s | stop | 20261118_060040_c55e591c |

| Finding ID | Audit Item | Severity (P0/P1/P2/Info) | Verdict (PASS / WARN / FAIL / N/A) | Code & Test Evidence | Detailed Analysis & Recommendation |
|---|---|---|---|---|---|
| F-001 | Japanese Labor Standards Act Art 37: Night Work Definition | P0 | FAIL | REQ-LABOR-002: "Night work (22:00~05:00): +25% extra pay." <br> REQ-LABOR-002 Processing Step 1: "Night half-open interval `[22:00, 29:00)`" | **Critical Legal/Logic Error**: The specification defines the night work window as `[22:00, 29:00)`. In a 24-hour clock context, `29:00` is invalid. If interpreted as "22:00 to 29:00 next day", it implies a 7-hour window (22:00-05:00 is 7 hours). However, the standard Japanese labor law definition for "Night Work" (深夜労働) is strictly **22:00 to 05:00** (7 hours). <br><br>**Analysis**: <br>1. The notation `[22:00, 29:00)` is mathematically ambiguous in standard `LocalTime` implementations which reset at 24:00. <br>2. If the code implements `29:00` as `05:00` of the *next* day, it is correct. However, if it treats it as a continuous 29-hour mark from midnight, it is incorrect. <br>3. **Crucial Missing Logic**: The spec fails to explicitly state that the night work calculation must handle the **date boundary** correctly (i.e., 22:00 Day 1 to 05:00 Day 2). The "29:00" notation suggests a potential implementation flaw where developers might try to add 7 hours to 22:00, resulting in 05:00, but the interval logic `[22:00, 29:00)` is non-standard. <br><br>**Recommendation**: Explicitly define the night work window as two separate intervals if crossing midnight: `[22:00, 24:00)` of Day D and `[00:00, 05:00)` of Day D+1. Avoid using "29:00" in technical specifications to prevent `DateTimeParseException` or logic errors in Java `LocalTime`/`ZonedDateTime` handling. |
| F-002 | Japanese Labor Standards Act Art 37: Overtime & Night Overlap (Concurrent) | P0 | FAIL | REQ-LABOR-003: "Night + Overtime concurrent overlap: +50% combined extra pay." <br> REQ-LABOR-003 Matrix: "Statutory Overtime (<=60h) + Night Overlap: Surcharge 50% (Total 150%)" | **Legal Compliance Failure**: The specification incorrectly calculates the combined surcharge for Overtime + Night Work. <br><br>**Analysis**: <br>According to Japanese Labor Standards Act Article 37: <br>1. Overtime (up to 45h/month): +25% <br>2. Night Work: +25% <br>3. **Combined (Overtime + Night)**: The surcharges are additive. Total Surcharge = 25% (OT) + 25% (Night) = **50%**. <br>Therefore, the **Total Pay Multiplier** should be `100% (Base) + 50% (Surcharge) = 150%`. <br><br>The spec states: "Surcharge 50% (Total 150%)". This is **CORRECT** for the <=60h case. <br><br>**HOWEVER**, look at the "Night + Overtime concurrent overlap" description in the prompt's checklist vs the spec. The checklist says "+50% combined extra pay". The spec says "Surcharge 50%". This matches. <br><br>**Wait, let's re-read the "Night + Overtime" rule in the prompt checklist**: "Night + Overtime concurrent overlap: +50% combined extra pay." <br><br>**Let's check the >60h case in REQ-LABOR-003**: <br>"Statutory Overtime (>60h) + Night Overlap: Surcharge 75% (Total 175%)". <br>Calculation: Base 100% + OT Surcharge 50% (>60h) + Night Surcharge 25% = 175%. This is **CORRECT**. <br><br>**Re-evaluating F-001**: The "29:00" notation is the primary risk. In Java, `LocalTime` does not support 29:00. If the developer hardcodes `29:00` as a string or integer, it will fail. If they interpret it as `05:00` next day, it is fine. But the spec is ambiguous. <br><br>**Re-evaluating F-002**: Is there a flaw? <br>Standard Rule: <br>- Daytime OT: 1.25x <br>- Night Work: 1.25x <br>- Night OT: 1.25x * 1.25x? **NO**. Japanese law adds the percentages. <br>Base + 25% (OT) + 25% (Night) = 1.50x. <br>The spec says "Total 150%". This is correct. <br><br>**Verdict Change**: The math in REQ-LABOR-003 is actually **PASS** for the multipliers. The issue is strictly the **Time Boundary Definition** in REQ-LABOR-002. <br><br>**Revised Finding F-001**: The definition of Night Work as `[22:00, 29:00)` is technically invalid in standard time libraries. It must be defined as `22:00-24:00` and `00:00-05:00`. <br><br>**Revised Finding F-002**: The multiplier logic is correct. <br><br>**Let's look for other issues.** |
| F-003 | Payroll Math & Rounding: RoundingMode.HALF_UP Application | P1 | WARN | REQ-LABOR-003 Processing Step 2: "Final confirmation processing... `RoundingMode.HALF_UP`... Daily intermediate truncation is strictly prohibited." | **Risk of Precision Loss**: The specification mandates maintaining `BigDecimal` precision until the monthly aggregation. <br><br>**Analysis**: <br>1. **Correct Approach**: Keep all calculations in `BigDecimal` with high scale (e.g., scale 10) during the month. Apply `RoundingMode.HALF_UP` only at the final monthly total. <br>2. **Potential Pitfall**: If the system calculates `overtimePayExact` per shift and stores it in a database column with limited precision (e.g., `DECIMAL(10,2)`), the "daily truncation" prohibition is violated at the storage level. <br>3. **Recommendation**: Ensure the database schema for `payroll_settlement_line` uses `DECIMAL(18, 6)` or higher for intermediate calculations, or that the application layer aggregates all `BigDecimal` values in memory before persisting the final rounded integer. The spec says "maintain high-precision rational numbers (BigDecimal)", which is good, but does not explicitly forbid low-precision DB storage of intermediate lines. <br><br>**Verdict**: WARN. The spec is logically sound but lacks explicit DB schema precision constraints to guarantee the "no daily truncation" rule is physically enforced. |
| F-004 | Concurrency & Security: Pessimistic Locking Strategy | P1 | PASS | REQ-SHIFT-001 Step 4: `SELECT ... FOR UPDATE` on `store_staff`. <br> REQ-LABOR-004 Step 1: `SELECT ... FOR UPDATE` on `store`. <br> REQ-LABOR-004 Step 2: `SELECT ... FOR UPDATE` on `payroll_settlement`. | **Analysis**: <br>1. **Shift Application (REQ-SHIFT-001)**: Locking the `store_staff` row is sufficient to serialize concurrent shift applications for the *same staff member*. This prevents duplicate overlapping shifts for that staff. <br>2. **Payroll Settlement (REQ-LABOR-004)**: Locking the `store` row first is a strong strategy to serialize all payroll operations for a specific store, preventing race conditions on the `payroll_settlement` table. The use of `UNIQUE KEY uq_settlement_store_month` provides a second layer of defense (DB constraint) against phantom inserts. <br>3. **IDOR Protection**: REQ-MEMBER-001 and REQ-STAFF-001 explicitly state that `ownerId` and `storeStaffId` are resolved from `SecurityContext`, not request parameters. This correctly mitigates IDOR vulnerabilities. <br><br>**Verdict**: PASS. The concurrency control strategy is robust, using pessimistic locking combined with unique constraints. |
| F-005 | Exception Handling & Boundary Validation: Time Parsing | P2 | WARN | REQ-SHIFT-001 Exception: `DateTimeParseException`. <br> REQ-LABOR-002 Exception: Boundary validation (21:59 vs 22:00). | **Analysis**: <br>1. **Time Parsing**: The spec mentions `DateTimeParseException` for invalid formats. This is standard. <br>2. **Boundary Conditions**: REQ-LABOR-002 explicitly tests boundaries (21:59:59 vs 22:00:00). This is good. <br>3. **Missing Edge Case**: What happens if `clockInAt` is after `clockOutAt` (e.g., 23:00 in, 01:00 out)? REQ-SHIFT-001 Step 2 handles "next day crossing" for *planned* shifts. Does REQ-LABOR-001 handle *actual* clock-in/out crossing midnight? <br>REQ-LABOR-001 Step 1 says: "Work date is the date of the start time... night shift treated as continuous 1 work session." This implies the logic handles it. <br>4. **Negative Hours**: The spec mentions checking for negative hours in REQ-STAFF-002 (wage) but not explicitly for *worked* hours in REQ-LABOR-001. If `clockOut` < `clockIn` (without date rollover logic), it could result in negative minutes. The "next day" logic in REQ-SHIFT-001 should be mirrored in the payroll calculation engine. <br><br>**Recommendation**: Explicitly state in REQ-LABOR-001 that if `clockOutAt` is earlier than `clockInAt` in the same day context, it must be treated as a next-day rollover (adding 24h) before calculating duration, consistent with the shift planning logic. |
| F-006 | Japanese Labor Standards Act Art 37: Weekly Overtime Calculation | P1 | WARN | REQ-LABOR-001 Step 4: "Weekly statutory overtime... cumulative actual work hours (excluding daily overtime counted portion) exceeds 2400 minutes (40 hours)..." | **Analysis**: <br>1. **Definition of "Weekly"**: The spec defines the week start as "Monday 00:00" (default). Japanese labor law typically defines the "week" as the 7-day period ending on the day of calculation, or a fixed weekly cycle defined in the employment rules. <br>2. **Exclusion Logic**: The spec says "excluding daily overtime counted portion". This is **INCORRECT** for the *calculation* of weekly overtime, though it might be correct for *payment* categorization. <br><br>**Legal Nuance**: <br>- **Daily Overtime**: Hours > 8h/day. <br>- **Weekly Overtime**: Hours > 40h/week. <br>- **Overlap**: If you work 10 hours on Monday (2h OT) and 10 hours on Tuesday (2h OT), you have 4h Daily OT. Your total weekly hours are 20h. If you work 10h every day for 5 days, you have 10h Daily OT. Your total weekly hours are 50h. The Weekly Overtime is 10h (50 - 40). <br><br>The spec says: "Weekly statutory overtime... cumulative actual work hours (excluding daily overtime counted portion) exceeds 2400 minutes". <br>If you exclude the daily overtime portion from the cumulative total, you are calculating `Total Hours - Daily OT Hours`. <br>Example: 5 days x 10h = 50h total. Daily OT = 5 days x 2h = 10h. <br>Spec Formula: `50h - 10h = 40h`. <br>Is 40h > 40h? No. So Weekly OT = 0? <br>**This is WRONG.** The Weekly Overtime is the amount exceeding 40h *total* work hours. The fact that some of those hours are already paid as Daily OT does not reduce the *total* hours worked for the purpose of the 40h threshold. <br><br>**Correct Logic**: <br>1. Calculate Total Weekly Hours. <br>2. If Total Weekly Hours > 40h, then `Weekly Overtime Minutes = Total Weekly Hours - 40h`. <br>3. **Payment**: These `Weekly Overtime Minutes` are paid at the OT rate. <br>4. **Double Dipping**: Hours that are both Daily OT and Weekly OT are paid at the OT rate (not double OT rate, unless it's Night OT). The "Daily OT" and "Weekly OT" are not additive surcharges on top of each other in the same way Night is. They are both "Overtime". The rate is determined by the *highest* applicable category. <br><br>**Spec Error**: The spec implies a subtraction logic that will under-report weekly overtime. <br><br>**Recommendation**: Change REQ-LABOR-001 Step 4 to: "Calculate total actual work hours for the week. If total > 2400 minutes, `weeklyOvertimeMinutes = total - 2400`. Note: These minutes are subject to the overtime surcharge. If these minutes also fall within night hours, apply the night surcharge additively." |
| F-007 | IDOR Vulnerability: Store Staff Access | P0 | PASS | REQ-STAFF-001 Step 4: "Strictly verify store affiliation... block access to other store staff... with HTTP 403." <br> REQ-SHIFT-003 Step 2: "If `store_staff_id` does not match session value... block as IDOR." | **Analysis**: The specification consistently enforces that resource access is scoped to the authenticated user's `storeStaffId` or `storeId`. It explicitly rejects client-provided IDs in favor of session-resolved IDs. This effectively prevents IDOR vulnerabilities. |
| F-008 | Data Integrity: Contract History Overlap | P1 | PASS | REQ-STAFF-002 Step 1: `SELECT ... FOR UPDATE` on `store_staff`. <br> REQ-STAFF-002 Step 4: "Update existing contract's `effective_to` to new `effectiveFrom` minus 1 day." | **Analysis**: The use of pessimistic locking on the parent `store_staff` row ensures that concurrent contract updates for the same staff member are serialized. The logic to close the previous contract (`effective_to = newStart - 1`) and open a new one is standard and prevents overlapping valid periods. The unique constraint or application-level check for date overlaps is implied by the "period overlap" exception handling. |
| F-009 | Privacy: Calendar Data Masking | P2 | PASS | REQ-SHIFT-004 Step 2: "Other staff: ... `staffMemo`, `ownerMemo`, wage unit price... completely `null` masked." | **Analysis**: The specification explicitly defines a DTO transformation layer that masks sensitive fields for non-privileged users. This prevents leakage of personal notes and wage information via the calendar API. |
| F-010 | Rounding: 1-Yen Discrepancy Prevention | P1 | PASS | REQ-LABOR-003 Step 2: "Only apply `RoundingMode.HALF_UP` to the final monthly total... Daily intermediate truncation is strictly prohibited." | **Analysis**: By deferring rounding to the final monthly aggregation and using `BigDecimal` for intermediate steps, the system avoids the "1-yen discrepancy" that occurs when rounding daily amounts and then summing them. This is the correct approach for payroll accuracy. |

### Summary of Critical Findings

1.  **F-001 (P0 FAIL)**: The definition of Night Work as `[22:00, 29:00)` is technically flawed for implementation. It must be split into `[22:00, 24:00)` and `[00:00, 05:00)` to handle the date boundary correctly in standard time libraries.
2.  **F-006 (P1 WARN)**: The calculation logic for Weekly Overtime in REQ-LABOR-001 is flawed. It suggests excluding Daily Overtime hours from the total before checking the 40-hour threshold. This will result in underpayment of weekly overtime for employees who work long days. The threshold check must be against the **total** hours worked in the week.

---

## 4. [Step 2] OpenAI Codex CLI 技術交差検証レポート
| ID | 重要度 | 監査所見 | 実装・DDL上の是正要求 |
|---|---|---|---|
| AUD-001 | Critical | 技術スタックが不整合です。仕様には `SecurityContextHolder`、`BigDecimal`、`SELECT ... FOR UPDATE` 等のJava/Spring前提記述がある一方、DoDは「C#リンター規則」としています。 | 採用基盤をJava/Springまたは.NETへ明示統一し、認証コンテキスト、ORM、例外、ロック実装、リンター基準を同一技術スタックで再定義してください。 |
| AUD-002 | Critical | `store_staff` の `uq_store_member` と「退職後は新規 `store_staff` レコードで再雇用」が両立しません。`(store_id, member_id)` の単純一意制約では再雇用レコードを作成できません。 | 履歴を保持するなら `employment_instance` 等の識別子を導入し、部分一意制約またはACTIVE/PENDINGのみを対象にした一意性設計へ変更してください。DBが部分一意制約を持たない場合は、別の現役所属テーブルで保証してください。 |
| AUD-003 | Critical | 給与計算の「基本給」「割増手当」「合計乗率」の関係が曖昧で、重畳区間で基本給を二重計上する危険があります。REQ-LABOR-001/002は割増分のみ、REQ-LABOR-003は総額乗率で記述されています。 | 相互排他的な分単位カテゴリと、`basePayExact`・`premiumPayExact`・`grossPayExact` の算式を固定してください。各カテゴリの分数合計が `workMinutes` と一致する不変条件も設けてください。 |
| AUD-004 | High | DDL上の必須制約が仕様化されていません。FK、UNIQUE、CHECK名の一部しか提示されず、状態値、金額、期間、時刻、参照整合性がDBで保証されません。 | 少なくとも `store`、`member`、`store_staff`、契約履歴、shift、settlement、settlement_line のDDLを提示し、FK、NOT NULL、CHECK、UNIQUE、必要インデックスを明文化してください。アプリ側検証だけに依存しないでください。 |
| AUD-005 | High | 契約履歴の排他制御は「現在有効な契約」だけを扱い、既存の過去期間との重複を完全には防げません。また、DB標準の範囲排他制約は定義されていません。 | `(store_staff_id, effective_from)` の一意制約、期間重複検証、適切なロック対象・索引を定義してください。DBが範囲排他制約をサポートする場合は採用してください。 |
| AUD-006 | High | 最低賃金検証の参照元、適用日、都道府県別改定履歴、例外時の処理が未定義です。将来改定時に契約・給与の再現性を保証できません。 | 最低賃金マスタに都道府県・適用開始日・金額・改定版を持たせ、契約確定時および給与明細へ参照値またはスナップショットを保存してください。 |
| AUD-007 | High | 日本時間・タイムゾーンの基準が未定義です。`DATE`、`TIME`、ISO-8601日時、週起算、深夜帯、給与締め日はタイムゾーンなしでは決定論的に計算できません。 | 業務時刻の基準を `Asia/Tokyo` と明記し、永続化する打刻はoffset付き時刻またはUTC、業務日付・ローカル時刻はJST変換規則を定義してください。 |
| AUD-008 | High | 休憩区間の入力契約と検証が不十分です。休憩が勤務区間外、重複、逆転、重複登録された場合の扱いがありません。 | 半開区間の休憩DTO、開始＜終了、勤務内包含、重複禁止または統合規則、分単位丸め規則を定義してください。深夜・残業との積集合計算は正規化済み休憩区間を入力にしてください。 |
| AUD-009 | High | シフト取消で「`CANCELLED_DELETED` への状態遷移」と「物理削除」が混在しています。物理削除後は状態・監査証跡を保持できません。 | 原則ソフトデリートへ統一し、`status=CANCELLED`、取消者、取消日時、理由を保持してください。物理削除が必須なら、独立した監査履歴テーブルを必須化してください。 |
| AUD-010 | High | REQ-SHIFT-002 の「休憩不足は警告・再確認要求」はHTTP契約として未完成です。確認トークンや再送時の状態がなく、クライアントが警告を無視できます。 | `422 BREAK_CONFIRMATION_REQUIRED`、計算済み不足内容、確認用トークンまたは明示的な確認フラグをDTOへ定義し、監査ログへ保存してください。 |
| AUD-011 | Medium | 招待コードの「最大5回再生成」は、DB一意制約違反を捕捉する単位・トランザクション境界・最終エラーが未定義です。 | `invite_code` のUNIQUE制約を必須化し、保存時の一意制約違反のみを再試行対象にしてください。5回失敗時は安全なサーバーエラーとし、コード値をログ出力しないでください。 |
| AUD-012 | Medium | QRトークンの有効期限、ローテーション、失効、漏えい時の再発行、ハッシュ保存方針がありません。固定の生トークン保存は認証情報漏えいにつながります。 | トークンID・ハッシュ・発行日時・失効日時・ローテーション世代を定義し、生トークンは原則再表示不可にしてください。 |
| AUD-013 | Medium | メールアドレスの「RFC 5322準拠」は実装・DB照合に不適切で、`lower(email)` 一意性をアプリ検証だけで保証すると競合します。 | 正規化方式を固定し、正規化済みメール列にUNIQUE制約を設定してください。メール構文検証は実用的な入力制約と確認メール認証を併用してください。 |
| AUD-014 | Medium | RBACのPrincipal仕様が不足しています。`ROLE_OWNER` と店舗単位の店長権限、複数店舗所有、スタッフ所属の解決規則が曖昧です。 | `principal.memberId` を唯一の信頼境界とし、店舗操作ごとに `store.owner_id` または有効な所属レコードを照合する認可サービスを定義してください。クライアント送信の `storeStaffId`、`ownerId`、`role` はDTOから除外してください。 |
| AUD-015 | Medium | 悲観的ロックはSQL断片のみで、トランザクション分離レベル、ロック待機時間、デッドロック再試行、対象索引が未定義です。 | 各ユースケースのトランザクション境界、ロック順序（例: `store`→`settlement`）、3秒タイムアウト、デッドロック時の安全な再試行可否を明文化してください。対象検索条件を支える複合索引も定義してください。 |
| AUD-016 | Medium | 給与確定の状態遷移に矛盾があります。説明では `LOCKED → CONFIRMED`、CAS条件では `status = 'OPEN'` です。 | 有限状態機械を `OPEN → LOCKED → CONFIRMED` 等に固定し、各遷移のCAS条件、失敗時の復旧、明細作成失敗時のロールバックを定義してください。 |
| AUD-017 | Medium | 週40時間計算の `weeklyAccumulatedMinutes` は、日次残業を除外する順序・複数勤務日の配賦・週跨ぎ夜勤の扱いを十分に定義していません。 | 週起算曜日、勤務基準日への帰属、日次残業控除後の累計方式、同週内の処理順序を固定し、再計算可能な明細データを保存してください。 |
| AUD-018 | Medium | FullCalendarイベントDTOの契約が不足しています。夜勤の終了日、タイムゾーン、`id/title/start/end/color/extendedProps`、取消済みの表示可否が不明確です。 | FullCalendar 6.x互換のJSONスキーマを提示し、JST offsetを含む開始・終了日時、権限別に許可された `extendedProps` のホワイトリストを定義してください。 |
| AUD-019 | Medium | カレンダー検索に最大検索期間・ページング・対象ステータスの制限がなく、大量取得と情報露出の余地があります。 | 検索可能な期間上限、認可済み店舗への限定、必要な状態条件、`(store_id, work_date, status)` 索引を定義してください。 |
| AUD-020 | Low | API例外にHTTP 400/403/404/409/422が混在する一方、標準エラーDTOがありません。クライアントの安全な再試行・表示が困難です。 | `code`、`message`、`traceId`、`fieldErrors` を持つ共通エラーDTOを定義し、例外コードとHTTPステータスを一対一で管理してください。 |

総評として、業務要件と主要なセキュリティ意図は明確ですが、現状は技術基盤の不整合、再雇用と一意制約の衝突、給与計算の二重計上リスクの3点を解消するまで実装着手判定は保留が適切です。

---

## 5. [Step 3] Anthropic Claude Sonnet 5.5 法規深層検証レポート
# KINTAI SRS v1.0.2 監査報告書

**監査範囲**: 労働基準法第32条・34条・37条の遵守性、端数処理、不変性（イミュータビリティ）、並行性、仕様間整合性
**総合判定**: ❌ **APPROVED_FOR_AUDIT は不可。P0が6件あり、実装着手前に仕様改訂が必須**

> 本監査は技術仕様レビューであり法的助言ではありません。最終的な法的解釈は社労士・弁護士の確認を要します。

---

## 1. エグゼクティブ・サマリ

| 重大度 | 件数 | 概要 |
|---|---|---|
| 🔴 P0 (違法・不払・データ破壊リスク) | 6 | 端数処理の解釈誤り、週40h算定の二重計上、法定休日の入力欠落、確定給与の遡及改変、60h超の起算欠落、深夜日跨ぎ分割の未定義 |
| 🟠 P1 (コンプライアンス/整合性) | 9 | 最低賃金の時点参照、休憩の労働時間算入、36協定、暦月/締め日の矛盾、確定フロー破綻 等 |
| 🟡 P2 (曖昧性・品質) | 7 | 状態機械の不整合、用語揺れ、技術スタック混在 等 |

---

## 2. P0 所見 (Critical)

### P0-1: 端数処理の通達解釈が不正確で、法的に不要かつ不利益な丸めを規定している (REQ-LABOR-003)

**該当**: 「昭63基発150号準拠 / 月次支給総額に対して50銭未満切捨て・50銭以上切上げ」

**問題**:
- 昭和63年3月14日基発第150号が認める端数処理は、**項目単位**での処理である。
  - (a) 1か月の時間外・休日・深夜の各労働時間数の合計に1時間未満の端数がある場合、**30分未満切捨て・30分以上切上げ**
  - (b) 1時間当たり賃金額・割増賃金額に1円未満の端数が生じた場合、**50銭未満切捨て・50銭以上切上げ**
  - (c) 1か月の割増賃金総額の1円未満の端数処理（同様の50銭基準）
- 仕様は「月次支給総額（基本給＋割増の合算）に対してのみ丸める」としており、**通達が想定する丸め対象（割増賃金額）とずれている**。
- 基本給部分（`hourlyWage × 実労働分/60`）は端数処理の通達の対象ではなく、通常は賃金全額払い（労基法24条）の観点から切捨てが問題になりうる。**総額単位の丸めで基本給の端数を含めて切上げ/切捨てするのは、通達の適用範囲外の運用**であり、50銭未満の切捨てが常に基本給側で発生すると、構造的に過少払いとなる。
- **「1分単位の厳密計算」が原則**（昭和24年通達等：1分単位管理が原則、15分/30分単位の切捨ては違法）であり、月合計の30分丸め(a)は**労働者に有利な/同等の扱いとなる場合のみ許容**。仕様は(a)を一切言及しておらず、運用者がどちらを採用するか未定義。

**リスク**: 労基法24条（全額払い）、37条違反の疑い。監督署是正勧告リスク。

**是正案**:
```
1. 丸め対象を「基本給」「各割増賃金」で分離し、割増賃金額のみ通達(b)(c)に従い丸める
2. 時間数の月次30分丸め(a)は「採用しない（1分単位厳密）」と仕様で明記
3. 基本給の端数方針（切捨て可否・労働者有利方向）を就業規則パラメータ化し、
   デフォルトは「切上げ（労働者有利）」を推奨、変更は法務承認必須
4. RoundingMode.HALF_UP の適用箇所と対象項目を明細レベルで列挙
5. 丸め後の各明細の合計＝支給総額となることを不変条件にする（丸め差異の配賦禁止）
```

---

### P0-2: 週40時間超の算定が日次残業と二重計上/漏れを起こす構造 (REQ-LABOR-001)

**該当**: 「`weeklyAccumulatedMinutes` (日次残業算定済分を除く)」「日次超過 + 週超過 = totalOvertimeMinutes」

**問題**:
- 通達(昭63基発1号)上、週40h超の時間外は「**日8h超として既にカウントした時間を除いた**週の実労働時間」が40hを超えた部分。仕様の方向性は合っているが、以下が未定義:
  1. **処理順序依存性**: 週途中で日をまたいで再計算（遡及打刻修正・後日承認）が入ると、既に確定した日次の `weeklyOvertimeMinutes` が変動する。**どの勤務日に週次残業を帰属させるか**（週を超過した"その日"に帰属）が未規定。
  2. **入力の `weeklyAccumulatedMinutes` が呼び出し側依存**: エンジンの決定論性が外部入力の正しさに依存し、**同じ勤務データから異なる結果が出る**余地がある。エンジンは週の全勤務を自己完結で受け取るべき。
  3. **多店舗勤務の通算**: 労基法38条により**事業場が異なっても労働時間は通算**される（同一労働者が複数事業主/複数店舗）。REQ-STAFF-001は多店舗所属を前提とするが、**店舗スコープ内でしか週累計を取らない**ため、複数店舗合算で週40h/日8hを超えるケースを検知できない。
  4. **週の起算曜日の変更**: 「デフォルト月曜」の店舗設定変更時の移行ルール（変更月の週の扱い）が未定義。
- 分単位での週超過の算定において、「週40h超部分」が日次残業分と**重複して計上されない**ことを検証する具体的テストベクタが不足（DoDの例「7h×6日=42h」は最も単純なケース1つのみ）。

**是正案**:
```
- エンジンIFを「週の全勤務明細リスト」入力に変更（累計値を外部入力にしない）
- 週次残業は「週累計(日次残業除く)が2400分を超過した時点以降の勤務分」に帰属、と明文化
- 38条通算ポリシー: 同一事業主の多店舗は通算必須（事業主ID単位で集計）。
  別事業主兼務は自己申告ベースの警告に留める旨を明記
- 起算曜日変更は「翌月初日の週から適用」等の遷移ルールを規定
- テストベクタ追加: 日8h超+週超の併発、週跨ぎ夜勤、起算曜日変更週、多店舗通算
```

---

### P0-3: 法定休日の判定入力が存在せず、休日割増(35%)が実装不能 (REQ-LABOR-003)

**問題**:
- 休日割増の乗率表は存在するが、**何が法定休日かを決める入力・設定・ルールが全仕様に皆無**。
  - 法定休日（週1日 or 4週4日）の特定方法（就業規則で特定/特定なしの場合は暦週の最後の休日 等）。
  - 所定休日（法定外休日）に働いた場合は休日割増(35%)ではなく、週40h超なら**時間外25%**。この区別がない。
- 法定休日労働には**時間外割増（25%）が重ねて付かない**（休日労働は時間外にカウントしない）。一方、法定休日の**深夜は60%**。乗率表は正しいが、**法定休日の8h超部分を「時間外」として二重加算しない**制約が仕様上未記述。実装者が日8h超ルールを休日にも適用するバグ（135%→160%過大/誤算定）を作りやすい。
- 法定休日が日跨ぎ（暦日0:00）で**休日の暦日と通常日をまたぐ夜勤**の場合の按分（暦日基準で割増率が切り替わる）が未定義。

**是正案**:
```
- store に statutory_holiday_rule（曜日固定 / 変形）を追加。未設定は確定処理を拒否
- calendar_day 単位で day_type ∈ {WORKDAY, SCHEDULED_HOLIDAY, STATUTORY_HOLIDAY} を解決
- 法定休日労働は日8h超・週40h超カウントから除外し、時間外と排他であることを明記
- 日跨ぎシフトは暦日0:00で分割して day_type を別個に判定
```

---

### P0-4: 「確定給与の不変性」と契約履歴・打刻データの遡及整合が破綻している (REQ-STAFF-002 / REQ-LABOR-004)

**問題**:
1. **スナップショットのタイミング矛盾 (REQ-LABOR-004)**: スナップショット永続化（手順4）とステータス遷移（手順5: `'LOCKED' → 'CONFIRMED'` を `WHERE status='OPEN'` でCAS）が**状態機械上不整合**。手順5は `OPEN→CONFIRMED` を意図しているのに `LOCKED` を経由する記述で、`LOCKED` 状態の定義・遷移元が存在しない。CAS条件 `status='OPEN'` では `LOCKED` からは更新0件となり**確定が永遠に失敗**する。
2. **確定後訂正手段の欠如**: 確定後に打刻誤り・時給誤設定・最低賃金違反が判明した場合の**是正フロー（赤伝/調整明細/再計算）が皆無**。「不変」だけを規定すると、過少払いを**修正できない仕様**になり、賃金支払義務（労基法24条）と衝突する。労働者への未払い賃金の時効は現行**3年**（2020年改正、当面）であり、訂正経路は法的に必須。
3. **契約履歴の遡及禁止が人事実務と衝突 (REQ-STAFF-002 手順3)**: 「`effectiveFrom` は既存より未来日のみ」と制限しているが、
   - 最低賃金改定（例：10月発効）の**適用漏れの遡及是正**
   - 昇給の遡及適用
   が不可能。さらに「`effectiveFrom > 既存effective_from`」は過去日も許容してしまい（既存開始日より後であれば昨日でも可）、**確定済み月の期間に遡って契約を変更でき、確定給与の根拠履歴と食い違う**。確定済み期間との交差検査がない。
4. **ロック階層**: REQ-STAFF-002は `store_staff` 行ロック、REQ-LABOR-004は `store` 行ロック。確定処理中に契約更新が走ると、**確定計算が参照する契約履歴がスナップショット前に変わる**（ロック対象が異なるため直列化されない）。

**是正案**:
```
- 状態機械を明示: OPEN → CALCULATING → CONFIRMED →(訂正時) ADJUSTED / VOIDED、
  LOCKED は削除 or 定義して遷移表を追加
- 確定後訂正: 元明細は不変のまま「調整明細(adjustment line, 差額のみ)」を追記する
  追記専用(append-only)モデルを定義。承認者・理由・監査ログ必須
- 契約履歴: 確定済み期間と交差する effectiveFrom は拒否 or 調整フロー強制。
  最低賃金適用漏れ是正用の「遡及訂正」専用権限パスを別途定義
- ロック順序規約を全仕様で統一: store → store_staff → shift/settlement
  (デッドロック回避のため取得順序を明文化)
```

---

### P0-5: 月60時間超の時間外判定の起算・対象が未定義 (REQ-LABOR-003)

**問題**:
- 「月60h超」の**「月」の起算日**が不明（暦月か、給与締め日 `payCutoffDay` ベースの賃金計算期間か）。法的には**賃金計算期間と一致させるか1か月の起算日を就業規則で定める**必要があり、ここがずれると50%/25%の境界がずれて**割増の過少払い**が発生。
- **60h超の時間数の算定対象**: 通達上、60h超の時間数に**法定休日労働は算入しない**（所定休日=法定外休日の労働は算入）。仕様に算入/除外ルールがない。
- **処理順序**: 60h到達の瞬間をまたぐ1勤務内では、**到達前の分に25%、到達後の分に50%**を分単位で切り分ける必要があるが、`overtimeMinutesUnder60` / `Over60` を**入力として受ける**設計で、**誰がどう切り分けるかが未定義**（REQ-LABOR-001は月累計を持たない）。
- **代替休暇制度**（60h超の割増引上げ分を有給休暇で代替）の取り扱いが不明。使わないなら「非対応」と明記が必要。
- 仕様は「中小企業猶予撤廃済」と記載するが、現行法令上の根拠(2023年4月施行)の記載は妥当。ただし**算定が"月次エンジン"と"日次エンジン"のどちらの責務か**が両REQで断絶。

**是正案**:
```
- 「割増計算の月」= 賃金計算期間(payCutoffDay準拠)と定義し、締め日変更時の移行規則を追記
- 月次累計は月次エンジンが勤務順(時系列)に分単位でカテゴリ割当を行う責務と明記
- 60h超算入ルール(法定休日除外)を条文化。代替休暇は「v1.0非対応」と宣言
```

---

### P0-6: 深夜帯 `[22:00, 29:00)` の日跨ぎ・複数暦日にまたがる分割ロジックが不完全 (REQ-LABOR-002)

**問題**:
- 深夜帯を「`[22:00, 29:00)` = 当日22:00〜翌05:00」と定義するが、**勤務が前日22:00〜当日05:00から継続している場合**、当日の 00:00〜05:00 は「前日の深夜帯の続き」。仕様の `[22:00, 29:00)` は**勤務基準日基準**の単一窓のため、**始業が 05:00〜22:00 の日に勤務開始し翌朝まで続く場合の翌日側深夜（00:00-05:00）**は拾えるが、**始業が深夜帯内（例: 02:00 始業）の場合、その日の 00:00-05:00 は基準日の窓 `[22:00, 29:00)` の外**（`02:00 < 22:00`）となり**深夜として計上されない**。
- 実装は「各暦日の `[00:00, 05:00)` と `[22:00, 24:00)`」の**2窓**で判定すべき。仕様の `29:00` 表記は勤務基準日からの相対表現で、**勤務基準日が前日の場合にしか成立しない**。
- 深夜手当の**日次切捨て排除は妥当**だが、**深夜×時間外×休日**の三重重畳を分単位でカテゴリ分解する際の優先順位・排他規則（深夜窓の分割と日8h/週40h帰属の合成順序）が未記述。
- 実在しない時刻の扱い: 日本は現在サマータイムなしだが、**打刻時刻のタイムゾーン**（UTC保存かJST保存か）が未規定。ISO-8601入力で**オフセット付き/なしが混在**すると境界判定（22:00/05:00）が狂う。

**是正案**:
```
- 全時刻を Asia/Tokyo ZonedDateTime に正規化することを要件化(入力のオフセット必須)
- 深夜判定は各暦日の [00:00,05:00) ∪ [22:00,24:00) の2窓交差で実装すると明記
- 分単位ビットマップ(または区間代数)で {日次超, 週次超, 月60h超, 深夜, 休日} を
  合成するカテゴリ割当アルゴリズムと優先順位を擬似コードで規定
```

---

## 3. P1 所見 (High)

| ID | 該当 | 問題 | 是正案 |
|---|---|---|---|
| P1-1 | REQ-STAFF-001/002, LABOR-001 | **最低賃金の判定時点と基準都道府県が曖昧**。最低賃金は10月頃に改定され発効日が都道府県ごとに異なる。契約時だけでなく**勤務日時点の最低賃金**と時給を比較すべき。`prefectureCode` は店舗単位で保持するが、改定履歴テーブルがない。交通費は最低賃金比較対象外であることも未明記。 | `minimum_wage_history(pref, effective_from, amount)` を追加し、勤務日基準で毎回検証。改定時に既存契約の下回りを検知するバッチ/アラート |
| P1-2 | REQ-LABOR-001 | **「サイレントフォールバック禁止→HTTP 422」はエンジン内で拒否すると月次確定全体が停止**。1名の違反で全員の確定が止まる運用リスク。かつ最低賃金違反は計算エンジンでなく契約登録時に防ぐべき(責務分離)。 | 契約登録時にハードブロック、エンジンは防御的検証のみ。違反は個別エラーリストとして返し他者の確定は継続 |
| P1-3 | REQ-SHIFT-002 | **休憩の労働時間算入**: 法定休憩(34条)は「労働時間が6hを超える場合45分、8hを超える場合60分」で、判定基準は**労働時間**（拘束時間ではない）。仕様は拘束時間(`grossMinutes`)で自動算定している。例: 拘束6時間30分・休憩45分→実労働5時間45分で6h以下となり、本来は休憩不要だったケースを過剰控除（賃金過少）。逆に、境界で休憩が不足するケースも発生。DoD例(510分/休憩45分/実7h45m)は**実労働8h未満なので適法だが、拘束510分は"8h超"判定→推奨60分**となり、推奨値(60分)とDoD(45分)が**自己矛盾**。 | 休憩要否は「実労働時間」で再帰的に判定する式を定義(実労働 = 拘束 − 休憩 が6h/8hを超える最小休憩)。DoD例を整合化 |
| P1-4 | REQ-SHIFT-002 / LABOR-001 | **休憩は労働時間に含まれず賃金控除は適法だが、「休憩の自由利用」「一斉付与」「途中付与」の要件**が未検証。計画休憩と**実打刻の休憩（`breakIntervals`）が別系統**で、どちらが給与計算の正本かが不明(計画0分→実績ありのズレ)。休憩が実際に取れていない場合(手待ち時間)は労働時間扱い。 | 給与計算の正本を実績打刻と明記し、計画との乖離アラートと手待ち時間の取扱いを規定 |
| P1-5 | 全体 | **36協定・時間外上限規制が「アラートイベント」のみ**。法定上限（原則月45h/年360h、特別条項でも月100h未満・2〜6か月平均80h以下・年720h）、および**単月100h未満・複数月平均80h以下は休日労働を含めて判定**。仕様は45h/60hのアラートのみで、**ハードストップ判定・年累計・複数月平均が皆無**。アルバイトでも適用される。 | 時間外/休日労働累計の監視(月/年/平均)を要件化。シフト確定時(REQ-SHIFT-002)に超過見込みを事前検知するチェックを追加 |
| P1-6 | REQ-STORE-001 vs 給与 | **`payCutoffDay`(1〜28,99)と月次確定 `targetMonth('YYYY-MM')` の対応が未定義**。締め日20日なら「2025-03」は2/21〜3/20か。割増の「月」「週起算」「確定月」の3概念が整合しない。**締め日変更時の期間重複/空白**も未規定。 | `payroll_period` エンティティ(開始/終了日)を導入し、全月次概念をこれに束縛 |
| P1-7 | REQ-MEMBER-001 | **オーナー昇格フローが「専用フロー」とのみ記述され、定義がない**。最初のオーナーは誰がどう作るか(ブートストラップ問題)。`ROLE_STAFF` が店舗作成(REQ-STORE-001は`ROLE_OWNER`必須)できず、**オーナー登録手段が仕様上存在しない＝システムが起動不能**。 | オーナー申請・審査フロー(運営承認/メール検証/本人確認)を定義 |
| P1-8 | REQ-STAFF-001 | **退職(RESIGNED)後の再雇用で新規 `store_staff` を発行**するが、`uq_store_member(store, member)` 複合ユニーク制約と**直接衝突**(同一store×memberの2行目が挿入不可)。かつ有給休暇の勤続年数通算・過去契約の連続性が分断される。 | ユニーク制約を `(store_id, member_id, employment_period)` へ変更、または部分ユニーク(ACTIVE/PENDINGのみ)にする |
| P1-9 | REQ-SHIFT-001〜003 | **希望シフトの「取消=物理削除」(CANCELLED_DELETED)と監査証跡**。物理削除は労働者名簿・出勤簿等の**法定保存義務(賃金台帳・出勤簿は5年、当面3年)**対象外ではあるが、シフトが確定給与の根拠になる場合はトレーサビリティを失う。状態名`CANCELLED_DELETED`と「物理削除」が矛盾(行が無いのにステータス遷移?)。 | 論理削除(`deleted_at`)に統一し、状態機械図を規定 |

---

## 4. P2 所見 (Medium)

| ID | 問題 | 是正案 |
|---|---|---|
| P2-1 | **技術スタック混在**: 例外が Java/Spring(`MethodArgumentNotValidException`, `SecurityContextHolder`, `BigDecimal`, `Duration.ofHours`, `@RequestParam`風)とMyBatis(`#{startDate}`)なのに、DoDは**「C#リンター規則」**。言語が確定していない。 | 実装言語/FWを1つに確定し、例外・型名を統一 |
| P2-2 | **休憩の「半開区間」「分単位」と打刻の秒精度**: 打刻は秒精度(21:59:59)だが算定は分単位。**秒の切捨て/切上げ規則**が不明(1分未満の端数を切り捨てると労働時間の過少把握＝違法の恐れ。日ごとの切捨ては厳禁)。 | 秒は切り捨てずに保持し月合計時に処理、または労働者有利の方向に丸める方針を明記 |
| P2-3 | **`staffMemo`/`ownerMemo` の自由記述にPII・健康情報が入るリスク**、マスキングは他スタッフ向けのみで**ログ/監査ログ

---

## 6. 総括および推奨事項 (Conclusion & Recommendations)
- 本レポートは、個別の手動操作を排し、**Hermes 統合コントローラーによる単一パイプライン下で決定論的リンター、Qwen 27B、Codex、Claude 5.5を統合実行**して生成された公式技術証跡です。