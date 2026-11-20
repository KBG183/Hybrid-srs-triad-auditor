### [Hermes Audit Execution Metrics v1.2.0]
| Target File | Model | Duration | Input Code Tokens | Output Tokens | Speed | Done Reason | Run ID |
|---|---|---|---|---|---|---|---|
| scratch/runs/20261120_105541_36fcefa2/draft.md | qwen27b:latest (IQ3_M) | 116.38s | 7073 tokens | 5562 tokens | 49.4 tokens/s | stop | 20261120_015912_fa70d1df |

# Red-Team Audit: Slice 4 Payroll Settlement & Labor Standards Engine

## 1. Interaction Matrix & Adversarial Simulation

### Interaction Matrix
| Component | State/Event | Guard/Constraint | Potential Conflict/Deadlock |
| :--- | :--- | :--- | :--- |
| **DDL-015** | `ck_line_time` | `overtime_under60_minutes + overtime_over60_minutes + holiday_minutes <= total_work_minutes` | **P4 Rule Collision**: This constraint allows `total_work_minutes` to be significantly larger than the sum of categorized minutes. It does not enforce that *all* work minutes are categorized into one of the four pay components (Base, OT, Night, Holiday). If the engine fails to categorize a segment (e.g., due to a logic gap in "Night" vs "Holiday" overlap), the minutes exist in `total_work_minutes` but contribute 0 to `gross_pay` unless explicitly added to `base_pay` via the "Base" component logic. However, the spec says `base_pay` covers "all actual labor time". The constraint does not verify `base_pay` corresponds to `total_work_minutes`. |
| **REQ-ATT-003** | Step 4 (Calculation) | "Statutory holiday... time is not included in day/week/month overtime." | **P1 Blocked-Terminator / P2 Divergence**: If a worker works on a statutory holiday, the minutes are excluded from the 60-hour OT counter. However, the spec states: "Statutory holiday labor is excluded from the monthly 60-hour overtime cumulative." This is legally correct under Japanese LSA Art 37(2) for the *calculation of the 50% premium threshold*, but the *base pay* must still be calculated. The risk lies in the "Night" overlap. If a worker works 22:00-05:00 on a Statutory Holiday, they get Holiday (35%) + Night (25%) + Base (100%). The spec table shows "Statutory Holiday, Night" = 160%. This is consistent. |
| **REQ-ATT-004** | Step 5 (CAS Update) | `WHERE ... status = 'OPEN'` | **P6 Silent Default / P7 Irreversibility**: The CAS update sets `confirmed_at = :now`. The spec states `:now` is "obtained from DB after lock acquisition". However, the `payroll_settlement` table has `created_at` and `updated_at`. The CAS updates `updated_at`. The constraint `ck_settlement_times` requires `confirmed_at BETWEEN created_at AND updated_at`. If the DB clock drifts or if `:now` is slightly before `created_at` (impossible if `created_at` is default `CURRENT_TIMESTAMP` and `:now` is fetched later, but possible if `created_at` was manually set in the past or if there is clock skew between app and DB), the constraint fails. More critically, if the transaction takes a long time, `updated_at` is set to `:now`. This is safe. |
| **REQ-ATT-003** | Step 7 (Multi-Store Allocation) | "Allocate integer part... distribute remainder... by store_id ascending." | **P5 Aggregation Gap / P2 Divergence**: The spec mandates that for multi-store employees, the *total* monthly pay is calculated first, then allocated. However, the `payroll_settlement_line` table is per `store_id`. The `gross_pay` in the line item is the *allocated* amount. The constraint `ck_line_pay` checks `gross_pay = base_pay + overtime_pay + night_pay + holiday_pay`. This is local to the line. The *global* consistency (sum of lines = total calculated) is guaranteed by the allocation algorithm. **Risk**: If the allocation algorithm has a floating-point error or rounding discrepancy that isn't caught by the "1 yen" remainder distribution, the sum of `gross_pay` across stores might not equal the theoretical total. The spec says "distribute the difference... 1 yen at a time". This is deterministic. |
| **DDL-015** | `ck_line_time` | `total_work_minutes BETWEEN 0 AND 44640` | **P3 Boundary Instant**: 44640 minutes = 31 days. This is a hard cap. If a worker works 31 days straight (24/7), they hit the cap. If they work 31 days and 1 minute, the insert fails. This is a valid business rule (impossible physically), but if the system allows "unrecorded work" or "corrections" that push a worker over 31 days in a month (e.g., due to timezone shifts or data entry errors), the settlement will fail with a 500 error or constraint violation, blocking the entire store's payroll. |
| **REQ-ATT-004** | Step 6 (Idempotency) | "If CAS becomes 0 rows... rollback... re-read." | **P1 Blocked-Terminator**: If a user clicks "Confirm" twice rapidly. Request A locks, calculates, inserts lines, executes CAS (success). Request B locks (waits for A), A commits. B acquires lock, sees status `CONFIRMED`. B returns success. This is safe. **However**, what if Request A inserts lines but fails *before* CAS (e.g., network drop)? The transaction rolls back. Lines are gone. Status is `OPEN`. Request B proceeds. Safe. |
| **REQ-ATT-003** | Step 1 (Parsing) | "Prohibit truncation, rounding, or snapping to standard hours." | **P2 Record-vs-Reality**: The system stores `numeric` for minutes. If the input is `2023-04-01T09:00:00.000001Z` to `2023-04-01T18:00:00.000000Z`, the duration is 8 hours minus 1 microsecond. The spec says "exact fraction". `BigDecimal` is used. This is robust. |

### Adversarial Simulation: The "Ghost Minute" & The "Midnight Shift"

**Scenario 1: The Midnight Shift & Holiday Boundary (P3/P1)**
*   **Setup**: Employee works on a Statutory Holiday (e.g., April 29). Shift: `2023-04-29T23:00:00+09:00` to `2023-04-30T06:00:00+09:00`.
*   **Logic**:
    *   23:00 - 24:00 (1h): Statutory Holiday + Night. Rate: 160%.
    *   00:00 - 05:00 (5h): Statutory Holiday + Night. Rate: 160%.
    *   05:00 - 06:00 (1h): Statutory Holiday (Day). Rate: 135%.
*   **Constraint Check**: `holiday_minutes` = 720. `night_minutes` = 360.
*   **OT Counter**: Spec says "Statutory holiday... time is not included in day/week/month overtime." So `overtime_under60_minutes` = 0.
*   **Pay**: Base (720 min) + Holiday Premium (35% of 720) + Night Premium (25% of 360).
*   **Risk**: Does the "Night" premium apply to the *Holiday* hours? Yes, spec table says "Statutory Holiday, Night" = 160%.
*   **Verdict**: Safe, provided the engine correctly identifies the 00:00 boundary as a segment split point (Step 3: "segment... at Tokyo time month boundary, statutory holiday start/end, 22:00, 05:00").

**Scenario 2: The 60-Hour Threshold & Multi-Store (P5/P2)**
*   **Setup**: Employee works at Store A and Store B.
    *   Store A: 30 hours OT (under 60).
    *   Store B: 31 hours OT (under 60).
    *   Total: 61 hours OT.
*   **Logic**:
    *   The first 60 hours (30 from A, 30 from B) should be 25% premium.
    *   The 1st hour of Store B's OT (the 61st hour globally) should be 50% premium.
*   **Allocation**:
    *   Total OT Pay = (60h * 25%) + (1h * 50%).
    *   Store A gets: 30h * 25%.
    *   Store B gets: 30h * 25% + 1h * 50%.
*   **Risk**: The spec says "Allocate... integer part... distribute remainder".
    *   If Store A's calculated OT pay is `1234.5` yen and Store B's is `1234.5` yen, and the total is `2469.0` yen.
    *   The engine must ensure that the *rate* applied to the specific minutes in Store B's 61st hour is 50%, not 25%.
    *   **Critical Check**: Does the engine calculate the *global* OT bucket first, then allocate? Yes, Step 4: "Scan... in chronological order... first 3600 min 25%, excess 50%."
    *   **Verdict**: Safe, *if* the chronological scan correctly attributes the "excess" minute to the specific store where it occurred. If the employee worked the 61st hour at Store B, Store B's line item must reflect the 50% rate for that specific minute. The `calculation_snapshot_json` must prove this.

**Scenario 3: The "Unrecorded Work" Deadlock (P1)**
*   **Setup**: An employee's attendance record is "Unapproved" (e.g., pending manager approval).
*   **Logic**: `REQ-ATT-004` Step 4: "Input deficiencies or unapproved attendance are not treated as no-target." Wait, the text says: "Input deficiencies or unapproved attendance are **not** treated as no-target." (Japanese: `対象なしとして扱いません`). This means they **ARE** treated as targets? Or does it mean they are **not** ignored?
    *   Let's re-read carefully: `入力不備や未承認勤怠を対象なしとして扱いません。` -> "Do not treat input deficiencies or unapproved attendance as 'no target'."
    *   This implies they **MUST** be processed.
    *   However, `REQ-ATT-003` Exception Handling says: "Unapproved/incomplete attendance is `PayrollInputNotFinalException` / 409 `PAYROLL_INPUT_NOT_FINAL`."
    *   **Contradiction**: `REQ-ATT-004` says "Do not treat as no-target" (implying proceed or fail hard?), while `REQ-ATT-003` says return 409.
    *   If the system returns 409, the settlement **fails**. The store cannot close payroll.
    *   **Adversarial Case**: A manager forgets to approve one employee's shift. The entire store's payroll confirmation fails with 409. The manager must approve the shift, then retry. This is a **P1 Operational Deadlock**. It blocks the entire store's payroll for one missing approval. It is not a "wage loss" (P0) because the system prevents the error, but it is a severe operational blocker.

**Scenario 4: The "Zero Work" Month (P6)**
*   **Setup**: Employee has no work in the month.
*   **Logic**: `REQ-ATT-004` Step 4: "Months with no target work can be confirmed with 0 items and 0 yen."
*   **Risk**: Safe.

**Scenario 5: The "Precision Loss" (P2)**
*   **Setup**: Work duration is 1/3 of a minute.
*   **Logic**: `REQ-ATT-003` Step 5: "If exact time cannot be represented as finite decimal minutes... exception."
*   **Risk**: If the input clock has microsecond precision, 1/3 minute is 20,000,000 nanoseconds. This is representable. But if the calculation results in a repeating decimal for the *pay* (e.g., 1/3 yen), the spec uses `HALF_UP` rounding at the end. This is safe.

## 2. Findings Table

| Finding ID | Attack Vector | Severity | Verdict | Code & Test Evidence | Detailed Scenario & Recommendation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| ADV-001 | P1 Blocked-Terminator | P1 | WARN | `REQ-ATT-004` Step 4: "Input deficiencies or unapproved attendance are not treated as no-target." vs `REQ-ATT-003` Exception: `PayrollInputNotFinalException` / 409. | **Scenario**: A single unapproved attendance record for one employee causes the entire store's monthly settlement to fail with HTTP 409. The manager cannot close the month until *all* attendance records are approved. This creates an operational deadlock where a single administrative oversight blocks payroll for hundreds of employees. <br>**Recommendation**: Clarify if "unapproved" records should be excluded from the calculation (treated as 0 hours) with a warning, or if the system should allow "Partial Confirmation". If strict compliance is required, ensure the UI clearly lists *which* records are blocking the confirmation to prevent "blind" retries. |
| ADV-002 | P4 Rule Collision | P2 | WARN | `DDL-015` `ck_line_time`: `overtime_under60_minutes + overtime_over60_minutes + holiday_minutes <= total_work_minutes`. | **Scenario**: The constraint allows `total_work_minutes` to be 1000, while `overtime_under60` + `overtime_over60` + `holiday` = 0. This implies 1000 minutes of "Base" work. However, if the engine logic fails to categorize a segment (e.g., a bug in the "Night" vs "Day" logic), the minutes might fall into `total_work_minutes` but not be paid correctly if the `base_pay` calculation relies on a different internal counter. The DB constraint does not enforce that `base_pay` corresponds to `total_work_minutes` minus the premium minutes. <br>**Recommendation**: Add a derived check in the application layer (not just DB) that verifies `base_pay` is calculated based on `total_work_minutes` (or the specific "Base" segment minutes) and that the sum of all segment minutes equals `total_work_minutes`. |
| ADV-003 | P3 Boundary Instant | P2 | WARN | `REQ-ATT-003` Step 3: "Segment... at Tokyo time... 22:00, 05:00". | **Scenario**: A shift ends exactly at `22:00:00.000000`. Is the last microsecond "Night" or "Day"? The spec defines Night as `[22:00, 05:00)`. So `22:00:00.000000` is Night. If a shift is `21:59:59.999999` to `22:00:00.000001`, it is split. The engine must handle this split precisely. The spec says "Prohibit truncation". This is safe *if* the engine uses `BigDecimal` for time as well, not just money. The spec says "Input time precision is microsecond". <br>**Recommendation**: Ensure the time segmentation logic uses the same precision as the input (microseconds) and does not round time to the nearest minute before segmentation. |
| ADV-004 | P5 Aggregation Gap | P2 | WARN | `REQ-ATT-003` Step 7: Multi-store allocation. | **Scenario**: Employee works at Store A and Store B. The 60-hour OT threshold is crossed. The "excess" 50% premium is applied to the specific minutes that cross the threshold. If the employee works the crossing minute at Store B, Store B's line item must reflect the 50% rate for that minute. The allocation algorithm distributes the *total* pay. If the allocation is done by "pro-rata" or "integer part", it might misattribute the *rate* applied. The spec says "Allocate... integer part... distribute remainder". It does not explicitly state that the *rate* is preserved per-minute in the allocation. It implies the *total* is calculated correctly, then split. <br>**Recommendation**: Verify that the `calculation_snapshot_json` for each store line item contains the *exact* breakdown of minutes by rate (25% vs 50%) for that specific store, ensuring the 50% premium is attributed to the correct store's line item, not just the total sum. |
| ADV-005 | P6 Silent Default | P2 | WARN | `DDL-015` `ck_line_time`: `total_work_minutes BETWEEN 0 AND 44640`. | **Scenario**: 44640 minutes is 31 days. If a data entry error or timezone bug results in a worker having 31 days and 1 minute of work in a month, the insert fails with a constraint violation. This is a 500 error or 400 error, blocking the settlement. <br>**Recommendation**: This is a valid hard limit, but ensure the error message is user-friendly ("Work hours exceed maximum physical limit") rather than a generic DB constraint error. |
| ADV-006 | P7 Irreversibility | P2 | WARN | `REQ-ATT-004` Step 7: "CLOSED... reopen... prohibited." | **Scenario**: Once a settlement is `CLOSED`, it cannot be reopened. If a critical error is found (e.g., wrong hourly rate applied to all employees), the only way to fix it is to create a *new* settlement for the same month? No, `uq_settlement_store_month` prevents a second settlement for the same store/month. <br>**Recommendation**: The spec does not provide a mechanism to correct a `CLOSED` settlement. If the `CLOSED` state is final, any error requires a manual DB intervention or a "Correction" settlement type that is not defined in this slice. This is a significant operational risk. A "Correction" or "Adjustment" mechanism is needed for post-close errors. |

## 3. JSON Output

```json
{
  "audit_engine": "Hermes-2Tier-Adversarial",
  "version": "1.2.0",
  "findings": [
    {
      "finding_id": "ADV-001",
      "vector": "P1 Blocked-Terminator",
      "severity": "P1",
      "verdict": "WARN",
      "evidence": "REQ-ATT-004 Step 4: 'Input deficiencies or unapproved attendance are not treated as no-target.' vs REQ-ATT-003 Exception: 'PayrollInputNotFinalException / 409 PAYROLL_INPUT_NOT_FINAL'.",
      "scenario": "A single unapproved attendance record for one employee causes the entire store's monthly settlement to fail with HTTP 409. The manager cannot close the month until all attendance records are approved. This creates an operational deadlock where a single administrative oversight blocks payroll for hundreds of employees.",
      "recommendation": "Clarify if 'unapproved' records should be excluded from the calculation (treated as 0 hours) with a warning, or if the system should allow 'Partial Confirmation'. If strict compliance is required, ensure the UI clearly lists which records are blocking the confirmation to prevent 'blind' retries."
    },
    {
      "finding_id": "ADV-002",
      "vector": "P4 Rule Collision",
      "severity": "P2",
      "verdict": "WARN",
      "evidence": "DDL-015 ck_line_time: 'overtime_under60_minutes + overtime_over60_minutes + holiday_minutes <= total_work_minutes'.",
      "scenario": "The constraint allows total_work_minutes to be significantly larger than the sum of categorized minutes. It does not enforce that all work minutes are categorized into one of the four pay components. If the engine fails to categorize a segment, the minutes exist in total_work_minutes but may not be paid correctly if the base_pay calculation relies on a different internal counter.",
      "recommendation": "Add a derived check in the application layer that verifies base_pay is calculated based on total_work_minutes (or the specific 'Base' segment minutes) and that the sum of all segment minutes equals total_work_minutes."
    },
    {
      "finding_id": "ADV-003",
      "vector": "P3 Boundary Instant",
      "severity": "P2",
      "verdict": "WARN",
      "evidence": "REQ-ATT-003 Step 3: 'Segment... at Tokyo time... 22:00, 05:00'.",
      "scenario": "A shift ends exactly at 22:00:00.000000. The engine must handle the split precisely. The spec says 'Prohibit truncation'. This is safe if the engine uses BigDecimal for time as well, not just money.",
      "recommendation": "Ensure the time segmentation logic uses the same precision as the input (microseconds) and does not round time to the nearest minute before segmentation."
    },
    {
      "finding_id": "ADV-004",
      "vector": "P5 Aggregation Gap",
      "severity": "P2",
      "verdict": "WARN",
      "evidence": "REQ-ATT-003 Step 7: Multi-store allocation.",
      "scenario": "Employee works at Store A and Store B. The 60-hour OT threshold is crossed. The 'excess' 50% premium is applied to the specific minutes that cross the threshold. If the employee works the crossing minute at Store B, Store B's line item must reflect the 50% rate for that minute. The allocation algorithm distributes the total pay. It might misattribute the rate applied.",
      "recommendation": "Verify that the calculation_snapshot_json for each store line item contains the exact breakdown of minutes by rate (25% vs 50%) for that specific store, ensuring the 50% premium is attributed to the correct store's line item."
    },
    {
      "finding_id": "ADV-005",
      "vector": "P6 Silent Default",
      "severity": "P2",
      "verdict": "WARN",
      "evidence": "DDL-015 ck_line_time: 'total_work_minutes BETWEEN 0 AND 44640'.",
      "scenario": "44640 minutes is 31 days. If a data entry error or timezone bug results in a worker having 31 days and 1 minute of work in a month, the insert fails with a constraint violation. This is a 500 error or 400 error, blocking the settlement.",
      "recommendation": "This is a valid hard limit, but ensure the error message is user-friendly ('Work hours exceed maximum physical limit') rather than a generic DB constraint error."
    },
    {
      "finding_id": "ADV-006",
      "vector": "P7 Irreversibility",
      "severity": "P2",
      "verdict": "WARN",
      "evidence": "REQ-ATT-004 Step 7: 'CLOSED... reopen... prohibited.'",
      "scenario": "Once a settlement is CLOSED, it cannot be reopened. If a critical error is found (e.g., wrong hourly rate applied to all employees), the only way to fix it is to create a new settlement for the same month? No, uq_settlement_store_month prevents a second settlement for the same store/month. The spec does not provide a mechanism to correct a CLOSED settlement.",
      "recommendation": "The spec does not provide a mechanism to correct a CLOSED settlement. If the CLOSED state is final, any error requires a manual DB intervention or a 'Correction' settlement type that is not defined in this slice. This is a significant operational risk. A 'Correction' or 'Adjustment' mechanism is needed for post-close errors."
    }
  ]
}
```