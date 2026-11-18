# 🏛️ KINTAI Hermes 多層統合検証レポート (Master Quality Audit Report)

- **検証日時 (Timestamp)**: 2026-11-18 15:33:53
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
| config/srs_specification_ssot.md | qwen27b:latest (IQ3_M) | 82.58s | 9781 tokens | 4019 tokens | 48.9 tokens/s | stop | 20261118_062922_c55e591c |

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
## 独立交差監査結果: FAIL

予備的な Qwen 結果のうち F-001・F-003 は有効ですが、F-004・F-006・F-007〜F-010 の PASS 判定は仕様のみでは成立しません。特に以下の P0 項目は実装前の仕様補完が必須です。

| ID | 深刻度 | 交差監査結果 | 迂回／競合条件 |
|---|---|---|---|
| X-001 | P0 | 確定シフト重複競合 | REQ-SHIFT-002 は対象 `shift` のみをロックし、「他の CONFIRMED シフト」をロックしません。異なる2件の SUBMITTED シフトを2名の管理者が同時に確定した場合、双方とも相手の未確定状態のみを参照して通過し、双方が CONFIRMED となる恐れがあります。 |
| X-002 | P0 | 給与確定状態遷移の矛盾 | 「`LOCKED → CONFIRMED`」としながら CAS 条件は `status='OPEN'` となっています。これは OPEN→CONFIRMED への直接遷移となるか、LOCKED 状態で CAS が失敗する矛盾を生じさせます。また LOCKED 状態の再試行・復旧・タイムアウト規約が存在しません。 |
| X-003 | P0 | 給与スナップショットと原簿データの競合 | REQ-LABOR-004 の `store` ロックは給与確定同士のみを直列化します。打刻修正、休憩修正、契約変更 API も同一の store ロック／バージョン検証を取得する規定がなく、スナップショット読み込み中に原簿データが変更される TOCTOU が発生し得ます。 |
| X-004 | P0 | 実休憩区間の操作／二重控除 | `breakIntervals` の範囲内包含、開始 < 終了、相互非重複、和集合基準の控除、負数純労働時間の禁止が未定義です。重複する2つの休憩を二重合算すると給与が過小算定されるリスクがあります。 |
| X-005 | P0 | 深夜時間帯の基準日欠落 | `[22:00, 29:00)` は業務表記としては許容され得ますが `LocalTime` に直接入力できません。00:00〜05:00 に開始した勤務が「前日日付の 22:00〜翌日 05:00」窓と積集合を持つべき規則が必要です。 |
| X-006 | P0 | 入力集計値の信頼リスク | REQ-LABOR-003 は `overtimeMinutesUnder60`、`nightMinutes`、重複分等の結果値を入力として受け取ります。これらがサーバー側で不変打刻から算定された値である検証規則が必須です。 |
| X-007 | P1 | 招待・QR トークンのライフサイクル不在 | 招待コードの有効期限・失効・再発行・試行制限・監査、QR トークンのローテーション・漏洩耐性・再生防止・保存時ハッシュ化が必要です。 |
| X-008 | P1 | 契約履歴 DB 不変式の不足 | アプリケーションの親行ロックのみでは直接 SQL やバッチを防げません。期間重複防止制約、単一有効契約制約、確定給与が参照した契約履歴の改変禁止を明記すべきです。 |
| X-009 | P1 | 精度保証の未完成 | 「BigDecimal 維持」のみでなく `payroll_settlement_line` の DECIMAL 精度・スケール、中間値丸め禁止、DB ドライバー直列化規則が必要です。 |
| X-010 | P1 | カレンダー DTO 迂回の可能性 | `null` マスキングだけでなく、エンティティ直接シリアライズやエラーレスポンスで機微情報が漏洩しないホワイトリスト DTO および権限別テストが必要です。 |

予備 Qwen 結果の訂正事項：
- F-001: **維持**。単なる `29:00` 表記の問題ではなく、`ZonedDateTime` 基準で各実労働区間と深夜窓の積集合を計算する規則の欠落が本質です。
- F-002: **PASS が妥当**。月 60 時間以下の時間外＋深夜は 150%、超過分＋深夜は 175% です。
- F-004: **PASS ではない**。シフト確定のファントム競合および給与原簿データ TOCTOU が残存しています。
- F-006: **Qwen の指摘は不正確**。日次法定外時間を除外した週次「未割当一般労働時間」により 40 時間超過分のみを追加算定することは二重割増防止として妥当です。
- F-007〜F-009: 仕様の意図は適切ですが、実装・スキーマ・権限テストの裏付けなしには **PASS 判定不可** です。
- F-005: 完全な ISO-8601 タイムスタンプであれば `clockOutAt < clockInAt` を翌日補正してはならず、不正打刻として拒否すべきです。

必須補完事項：
1. シフト確定も同一 `store_staff` 行を先行ロックするか、DB の時間範囲排他制約（`EXCLUDE`）により確定シフトの重複を原子的に遮断すること。
2. 給与状態遷移を `OPEN → LOCKED → CONFIRMED` として明文化し、各 CAS 条件・失敗コード・復旧契機を分離すること。
3. 給与スナップショットに含まれる打刻・休憩・契約変更経路も同一のロック順序（`store → staff → source rows`）または楽観的バージョン検証を義務付けること。
4. 休憩は正規化・マージした半開区間の和集合のみを控除し、勤務外・逆転・重複区間は HTTP 422 で拒否すること。
5. 深夜は `Asia/Tokyo` 基準の実タイムライン上で `[D 22:00, D+1 05:00)` 窓を生成して積集合を計算すること。
6. 給与エンジンの分類時間は不変原簿打刻からサーバー側で算出し、相互排他性・合計一致性を検証すること。
7. 中間金額カラムの最小精度（`DECIMAL(18,6)` 等）と最終 1 回の `HALF_UP` 規則を強制すること。

本結果は提供された SRS に対する独立設計交差監査であり、実装・スキーマ・テストに基づく最終 PASS 判定ではありません。

---

## 5. [Step 3] Anthropic Claude Sonnet 5.5 法規深層検証レポート
# 交差審査（Cross-Examination）: KINTAI SRS v1.0.2

## 総合判定: **REJECT**（P0 を複数残存。実装前に仕様改訂が必要）

Qwen 27B と Codex の指摘を、仕様原文と照合して個別に裁定します。結論として、Qwen 27B の F-001・F-006 は誤診または不正確、Codex の X-001〜X-006 は概ね正当、さらに両者が見落とした法令・論理上の欠陥が複数あります。

---

## 1. 既存指摘の裁定

| 指摘 | 裁定 | 理由 |
|---|---|---|
| Qwen F-001（`29:00` は無効） | **部分的に有効（P1 に格下げ）** | 「29:00」は日本の勤怠実務で慣用される25時間制表記であり、法的誤りではない。実害は表記が `LocalTime` で表現できないことと、**早朝0:00〜5:00開始の勤務に対する基準日ウィンドウの欠落**（Codex X-005）。後者が実質的な P0。 |
| Qwen F-002（重畳率の誤り） | **Qwen 自身が撤回済み。PASS** | 150%/175%/160% は正しい。 |
| Qwen F-006（週40h算定が誤り） | **Qwen の指摘は誤り。Codex の訂正が正しい**（ただし仕様に別の欠陥あり。§2-E 参照） | 日次法定外時間は既に割増対象のため、週40h判定から除外するのは二重計上防止として正しい。Qwen の算例（50h − 10h = 40h → 週残業0）は、実際は日次残業10hで全て算定済みであり過少払いではない。 |
| Qwen F-004/F-007〜F-010 PASS | **REJECT** | 確定時の phantom race、原データ TOCTOU、DB 制約不在が残存（下記）。 |
| Codex X-001〜X-006 | **有効（P0 維持）** | 下記 §2 で補強。 |
| Codex F-005 の指摘 | **有効** | ISO-8601 完全タイムスタンプでの `clockOut < clockIn` は翌日補正ではなく拒否が正。ただし REQ-SHIFT-001 の「時刻のみ入力」は補正が正で、両者の入力型の区別を仕様化すべき。 |

---

## 2. 両レビューが見落とした重大欠陥

### A. [P0・法令] 割増賃金の算定基礎賃金と「割増率の分類不整合」
- 法定休日労働（35%）と時間外労働の関係が未定義。**法定休日労働は時間外労働に算入されず（昭22.11.21基発366号、平6.3.31基発181号）、休日労働時間は8h超でも 135% 固定**（深夜と重なれば 160%）。REQ-LABOR-001 は日8h超を機械的に時間外とするため、休日労働日の8h超を 125% で二重分類する実装を誘発する。
- **法定休日の特定要件がない**（週1日の休日定義、就業規則の起算、4週4休の変形休日制）。「法定休日/所定休日」の区別が入力に存在せず、REQ-LABOR-003 の `holidayMinutes` の出所が不明。
- 時間外労働の**60時間超カウントの起算**（月の起算日＝給与締め日か暦月か）、および**法定休日労働は60h算定から除外**する規則が未記載。
- **割増の「率」は法令の最低基準**であり、**割増賃金の算定基礎から除外できる手当（家族・通勤・住宅等、則21条）**の記述がない。本システムの時給＋交通費モデルで、交通費を算定基礎に含めない旨の明記が必要。

### B. [P0・法令] 第34条休憩・長時間拘束の矛盾
- REQ-SHIFT-002 の休憩推奨は「**拘束時間** ≤360分 → 0分、≤525分 → 45分、>525分 → 60分」。しかし法定基準は「**労働時間** が6時間を**超える**場合45分、8時間を**超える**場合60分」。
  - 拘束 360分ちょうどは正しいが、**拘束 361〜405分（休憩45分控除後の実労働が6時間以下）の扱いが曖昧**。例: 拘束 6h10m・休憩45分 → 実労働 5h25m で、法定上は45分不要だった可能性（過剰休憩）。逆に拘束 525分・休憩45分 → 実労働 480分（ちょうど8h）で適法だが、480分超の時点で+15分が必要という**境界の連続性**がテスト化されていない。
- 休憩の**途中付与・一斉付与・自由利用**の原則（第34条第2・3項）が未実装。休憩が勤務末尾に偏っていても現仕様は検出不能。
- 最大拘束16時間許容は、**勤務間インターバル・連続勤務・週休（第35条）・変形労働時間制**に関するチェックが皆無。16時間シフトで休憩60分でも、翌日シフトとの間隔が確認されない。

### C. [P0・法令] 未成年者・年少者保護の欠落（アルバイトドメインで致命的）
- 満18歳未満は**深夜労働（22:00〜05:00）原則禁止**（第61条）、**時間外労働禁止**（第60条）、**1日8h/週40h**固定、修学時間の考慮。会員マスタに**生年月日がなく**、シフト確定・打刻・給与算定のいずれにも年齢ガードがない。学生バイト中心の飲食・小売で重大な法的リスク。
- **外国人留学生のシフト上限（資格外活動：週28時間）** も同様に未モデル化（入管法違反リスク。システム責任ではないが警告機能は事実上必須）。

### D. [P0・法令] 最低賃金の検証手段が未定義
- REQ-STAFF-001/002・REQ-LABOR-001 は「地域別最低賃金以上」を要求するが、**最低賃金マスタ（都道府県別・発効日付き・毎年10月改定）のデータモデルがどこにもない**。`prefectureCode` のみで、改定日をまたぐ勤務の**日付別適用**、特定（産業別）最低賃金の扱い、改定時の既存契約の一括違反検出がない。履歴管理の過去日付スナップショット参照とも整合しない。
- 契約時給が最低賃金未満になった場合、**REQ-LABOR-001 は 422 で算定拒否**とあるが、給与支払は法的義務。**算定拒否＝未払い**となるため、拒否ではなく「最低賃金補正＋アラート」で支払を止めない設計が必要。サイレント補正禁止との方針競合を仕様で裁定すること。

### E. [P1] 週次残業の算定アルゴリズム不在（F-006 の真の問題）
- 入力 `weeklyAccumulatedMinutes` は「日次残業算定済分を除く」と定義されるが、**週内で日付を遡って修正された打刻・遅延打刻**があった場合の再配分（先に確定した日の残業区分が後日変わる）のルールがない。
- **週起算曜日が店舗就業規則に依存**するが、`store` 入力項目に週起算日がない（REQ-STORE-001 の入力に不在）。
- **月またぎの週**（例: 月末〜翌月初）の週40h超過分を、どちらの月の給与に計上するかが未定義。給与締め日（`payCutoffDay`）と暦週が不整合になる。
- 変形労働時間制・フレックス・みなし労働の拡張余地なし（現仕様は「日8h/週40h」のみ。許容するなら明記が必要）。

### F. [P0・並行性] 追加レース条件
1. **REQ-SHIFT-001 の悲観ロックがスタッフ単位のみ**: 申請（SUBMITTED）では自分の行をロックするが、REQ-SHIFT-002 は `shift_schedule` 行ロック。**異なるロック対象で同一スタッフの重複確定**が成立（Codex X-001 と同根）。ロック順序（`store → store_staff → shift`）の統一が必要。デッドロック回避の順序規約も未定義。
2. **REQ-LABOR-004 の CAS 矛盾**（Codex X-002 に同意）。加えて「LOCKED」という状態が処理本文で突然登場し、`payroll_settlement` のステータス列挙（OPEN/LOCKED/CONFIRMED/CLOSED）の**遷移図が不在**。LOCKED のまま障害終了した場合の**ゾンビロック復旧手段**もない。
3. **給与確定後の打刻訂正**: 確定後に打刻誤りが判明した場合の**訂正・差額精算（遡及調整）の仕様がない**。「不変」とだけ書くと、実務上の過払い・未払い是正が不可能になり、法的には未払賃金（第24条全額払い、賃金請求権の時効は現行3年→2020年改正で当面3年、将来5年）の温床になる。

### G. [P1・セキュリティ] 認証・認可のギャップ
- REQ-MEMBER-001: **オーナー昇格フロー**が「管理権限を持つ専用フロー」とのみ記述され、実体が未定義。システム管理者（`ROLE_ADMIN`）の存在、最初のオーナー作成経路（ブートストラップ）、昇格の監査ログがない。
- **ログイン試行制限・アカウントロック・パスワードリセット・メール確認（登録時の所有確認）・MFA**が全て未記載。email 小文字正規化は書かれているが、**Unicode 正規化（NFKC）・サブアドレス**の扱いなし。
- **店舗オーナーが複数店舗を持つ場合**と**マネージャー権限**: REQ-SHIFT-002/004 で「店長」「店舗管理者」が登場するが、ロールモデルは `ROLE_OWNER`/`ROLE_STAFF` のみ。**店長（ROLE_MANAGER）が RBAC に存在しない**。仕様が参照する主体と定義済みロールが不一致。
- **QR 打刻トークン**: 静的トークンだと写真共有による**遠隔不正打刻（代理打刻・スクリーンショット）**が可能。位置情報・端末バインド・短寿命ワンタイムトークン・打刻の承認フローがない。**本システムの法的中核は打刻データの真正性**（労働時間の客観的把握義務、労働安全衛生法第66条の8の3・ガイドライン）であるのに、打刻REQ（clock-in/out）の仕様書自体がこのSRSに存在しない。

### H. [P1] データ・時間モデルの空白
- **タイムゾーン**: 店舗ローカル日付が REQ-SHIFT-001 に登場するが、`store` に tz 列がない。Codex 提案の `Asia/Tokyo` 固定は国内限定なら妥当だが、**仕様として明記**し、DST 非適用・UTC 保存・表示変換の方針を定める。
- 勤務基準日の**始業日基準**は通達準拠で正しいが、**暦日またぎ勤務で翌日が法定休日の場合**、休日割増は「暦日単位（午前0時〜）」で判断されるため、**始業日基準と矛盾**する（昭63.3.14基発150号：休日労働は暦日。ただし継続勤務が休日に及んだ場合の例外取扱いあり）。仕様が単純化しすぎ。
- 端数処理: 昭63基発150号は「1か月における時間外・休日・深夜の**各割増賃金の総額**に1円未満の端数が生じた場合に四捨五入」を認める。仕様は「**月次支給総額**に対して HALF_UP」としているが、これは**通達の許容範囲（割増賃金総額での処理）と異なる**。さらに、**労働時間の端数（1分未満切捨て・30分切捨て）は賃金未払いとなるため月合計で1時間未満の端数のみ30分基準で処理可**（同通達）。本システムは分単位で算定するため問題ないが、**交通費も月次丸め対象か**が不明確で、全額払いの原則（第24条）との整合を検討すべき。
- `hourlyWage × 0.25 × minutes / 60` の **BigDecimal 除算に scale と RoundingMode の指定がない**（`divide` で `ArithmeticException` の恐れ）。内部精度（scale≥10）と**除算順序（乗算先行）**を明記すること。C# リンター言及と Java 例外・`SecurityContextHolder`・MyBatis（`#{}`）・BigDecimal が混在しており、**実装言語が文書内で矛盾**している（DoD が C#、本文が Java/Spring）。

### I. [P2] 仕様の内部不整合
- REQ-SHIFT-003 の「**物理削除**」と状態名 `CANCELLED_DELETED` が矛盾。監査証跡（誰がいつ取消したか）が消える。論理削除＋履歴が望ましい。
- REQ-SHIFT-001 の `workDate` は「当日以降」だが、**当日の過去時刻**（既に開始済みの時刻）の希望申請が通る。
- REQ-SHIFT-002 の 16時間検証が申請時・確定時で二重に存在するが、**確定時に時刻を店長が変更**した場合の**スタッフ同意**フローがない（労働条件の一方的変更）。
- 招待コード衝突リトライ最大5回の失敗時の例外が未定義。
- REQ-STAFF-001: 退職（RESIGNED）後の**未払い賃金・最終給与の確定フロー**、退職日の最終精算、PENDING の**期限切れ・却下**状態の遷移がない。
- REQ-STAFF-002: 契約開始日が**未来日のみ許可**（過去遡及禁止）だが、実務上の**時給の遡及是正**（最低賃金改定の遡及適用、入力ミス訂正）が不可能。

---

## 3. 総合リスク評価

| 区分 | 件数 | 内容 |
|---|---|---|
| P0 | 9 | 確定の phantom race、給与 CAS 矛盾、原データ TOCTOU、休憩区間の不正、深夜窓の基準日欠落、集計値入力の信頼、**休日労働の二重分類、年少者保護の欠落、最低賃金モデル不在** |
| P1 | 10 | 週次算定の起算・月跨ぎ、確定後訂正フロー欠落、端数処理通達との乖離、認証強化・ロール不一致、QR 真正性、招待コード寿命、DB 制約、時間モデル、精度仕様 |
| P2 | 4+ | 物理削除と監査、スタッフ同意、状態機械の空白 ほか |

## 4. 最終判定: **REJECT**

**必須の仕様改訂（優先順）**

1. **ロック階層の統一**: `store → store_staff → shift/source rows` を全 REQ に義務化。シフト確定は DB の排他制約（`EXCLUDE USING gist (staff_id WITH =, tstzrange(start,end) WITH &&) WHERE status='CONFIRMED'` 相当）でも二重防御。
2. **給与状態機械の明文化**: `OPEN → LOCKED → CONFIRMED → (ADJUSTED)`、各遷移の CAS 条件・失敗コード・LOCKED タイムアウト復旧、確定後の**遡及調整（差額）フロー**を新設。
3. **労働時間算定の単一真実源化**: 集計値の外部入力を廃止し、不変の打刻・休憩から**サーバー側で `Asia/Tokyo` 実タイムライン上の区間代数**（休憩の正規化・合併・範囲検証、各割増窓との交差）で算出。カテゴリの相互排他・合計一致を不変条件として検証。
4. **労基法モデルの補完**: 法定休日定義と「休日労働は時間外に非算入」ルール、月60h算定の起算・休日除外、算定基礎賃金の範囲、**年少者（生年月日）保護ルール**、**最低賃金マスタ（発効日付）** と「違反時は支払を止めず補正＋アラート」の方針裁定。
5. **打刻真正性要件（欠落REQ）の新設**: 客観的記録、トークン回転、位置・端末検証、手動訂正の二者承認と監査。
6. **仕様の技術スタック統一**（Java/Spring vs C# の矛盾解消）と、BigDecimal の `scale`/`RoundingMode`、DB `DECIMAL(18,6)` 以上の明記。
7. **端数処理を昭63基発150号の文言に再整合**（割増賃金総額単位／時間端数の扱い）し、法務確認を取得。

**注記**: 本評価は SRS 文書のみに基づく設計監査であり、実装・スキーマ・テスト証跡に基づく合否ではありません。また、労働基準法・関連通達の解釈は最終的に社会保険労務士・弁護士による法務レビューを経る必要があります。

---

## 6. 総括および推奨事項 (Conclusion & Recommendations)
- 本レポートは、個別の手動操作を排し、**Hermes 統合コントローラーによる単一パイプライン下で決定論的リンター、Qwen 27B、Codex、Claude 5.5を統合実行**して生成された公式技術証跡です。