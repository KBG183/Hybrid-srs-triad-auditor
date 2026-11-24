### [Hermes Audit Execution Metrics v1.2.0]
| Target File | Model | Duration | Input Code Tokens | Output Tokens | Speed | Done Reason | Run ID |
|---|---|---|---|---|---|---|---|
| docs/labor37_e2e_traceability.md | qwen3.8:27b (IQ3_M) | 79.82s | 3325 tokens | 3489 tokens | 49.6 tokens/s | stop | 20261124_040109_94516f96 |

# Red-Team Labour Standards Audit: Labor Law Article 37 SSOT & Implementation Traceability

## 1. Interaction Matrix & Adversarial Simulation

### Interaction Matrix
The system defines a strict dependency chain: **SSOT (Legal/Spec)** -> **Java Domain (Logic)** -> **JUnit (Verification)**.

| Component | Role | Critical Constraint | Potential Failure Mode |
| :--- | :--- | :--- | :--- |
| **SSOT** | Source of Truth | Defines `REQ-LABOR-001` to `005`. Specifies `IllegalStateException` for missing clock-out. | Ambiguity in "unrecorded work" handling if exceptions are swallowed upstream. |
| **Java Domain** | Execution | `AttendanceTimeCalculator`, `PayrollCalculator`. Implements `RoundingMode.HALF_UP`. | **P1 Risk**: If `clockOutAt == null` throws an exception, does the transaction roll back? If not, the employee's work day is lost (Ghost Work). |
| **JUnit** | Verification | Tests boundary values (29/30 mins, 49/50 sen). | **P6 Risk**: Tests verify calculation *if* data exists. They do not verify data *persistence* or *recovery* from state errors. |

### Adversarial Simulation: The "Ghost Shift" Deadlock (P1 & P6)

**Scenario:**
1.  **22:00**: Employee clocks in.
2.  **05:00**: Employee works through the night.
3.  **05:01**: Employee forgets to clock out or the biometric scanner fails. `clockOutAt` remains `null`.
4.  **System Event**: Payroll calculation triggers for the day.
5.  **Code Execution**:
    *   `LaborCalculationService.calculateDetailedLabor` is invoked.
    *   Per `REQ-LABOR-001` and `LaborCalculationService.java` L53-L55, the system detects `clockOutAt == null`.
    *   The system throws an `IllegalStateException`.
6.  **The Paradox**:
    *   **Legal Reality**: The employee worked 7+ hours. Wages are owed.
    *   **System State**: An exception is thrown. Unless the calling context (not provided in the traceability doc but implied by standard Java service patterns) catches this and *manually* inserts a default clock-out or flags the record for manual review, the calculation **fails**.
    *   **Consequence**: If the exception propagates to a batch processor that skips failed records, the employee's entire day of work is **unrecorded**. No wages are calculated. No overtime is tracked. This constitutes a violation of the right to remuneration for work performed.
    *   **Traceability Gap**: The JUnit tests (`clockOutBeforeClockIn_ShouldThrowException`) verify the *exception*, but there is **no traceability link** to a recovery mechanism, a manual override workflow, or a default-value imputation rule in the SSOT. The SSOT defines the *block*, but not the *resolution*.

### Adversarial Simulation: The Midnight Boundary & "Silent Default" (P3 & P6)

**Scenario:**
1.  Employee works from 23:30 to 00:30.
2.  **SSOT Rule**: `REQ-LABOR-002` defines Night as `[22:00, 05:00)`.
3.  **Calculation**:
    *   23:30 - 00:00 = 30 mins Night.
    *   00:00 - 00:30 = 30 mins Night.
4.  **Risk**: The documentation mentions `BigInteger` common denominator for *monthly* aggregation in the "Future Extension" section (Section 4, Item 2), but the *current* implementation (`PayrollCalculator.java` L150-L153) uses `RoundingMode.HALF_UP` on `BigDecimal` for daily calculations.
5.  **Conflict**: If the system calculates daily pay and rounds to the nearest Yen, then sums the months, it may diverge from the statutory requirement of rounding *after* monthly aggregation (if such a requirement exists in the full SSOT, though `REQ-LABOR-003` mentions "Monthly rounding convention control"). The traceability matrix links `REQ-LABOR-003` to `yenRound` (L150-L153) which is a *daily* or *per-component* rounding. If the law requires monthly aggregation before rounding, the current Java implementation (`calculateDailyPay`) is structurally incapable of compliance without a separate monthly aggregation layer that is **not evidenced** in the traceability matrix.

---

## 2. Standardized Findings

| Finding ID | Attack Vector | Severity (P0/P1/P2/Info) | Verdict (PASS / WARN / FAIL / N/A) | Code & Test Evidence | Detailed Scenario & Recommendation |
|---|---|---|---|---|---|
| **ADV-001** | **P1 Blocked-Terminator** | **P0** | **FAIL** | **SPEC_QUOTE**: `REQ-LABOR-001`: "未退勤打刻 (`clockOutAt == null`) 時の `IllegalStateException` 送出"<br>**CODE**: `LaborCalculationService.java` L53-L55<br>**TEST**: `clockOutBeforeClockIn_ShouldThrowException` (L192) | **Scenario**: An employee works a full shift but fails to clock out. The system throws an `IllegalStateException`. If the payroll batch job treats this as a fatal error and skips the record, the employee's work is **unrecorded**. There is no traceability to a "default clock-out" or "manual correction" workflow. This creates a "Ghost Work" scenario where labor is performed but legally unacknowledged by the system, leading to wage theft.<br>**Recommendation**: Implement a "Safe Harbor" default. If `clockOutAt` is null, default to the end of the shift or 24:00, flag the record for HR review, and **do not** throw an unhandled exception that halts calculation. Add a test case verifying that wages are still calculated (albeit provisionally) when clock-out is missing. |
| **ADV-002** | **P6 Silent Default** | **P1** | **WARN** | **SPEC_QUOTE**: `REQ-LABOR-003`: "月間端数処理規約の統制" (Monthly rounding convention control)<br>**CODE**: `PayrollCalculator.java` L150-L153 (`yenRound` uses `RoundingMode.HALF_UP`)<br>**DOC**: Section 4, Item 2 mentions `BigInteger` common denominator for monthly aggregation is a *future* extension. | **Scenario**: The SSOT requires "Monthly rounding convention control." The current Java implementation rounds *per component* or *per day* using `HALF_UP`. If the statutory requirement is to sum all minutes/hours for the month and *then* round to the nearest Yen, the current implementation will produce cumulative rounding errors (drift). The traceability matrix claims `REQ-LABOR-003` is covered by `yenRound`, but `yenRound` is a local utility, not a monthly aggregator. The "Monthly" aspect of the requirement is **not** traced to a specific monthly aggregation method in the Java code.<br>**Recommendation**: Explicitly trace the "Monthly" aggregation logic. If the current system calculates daily and sums, prove that this is legally equivalent to monthly aggregation under the specific jurisdiction's interpretation. Otherwise, implement the `BigInteger` monthly aggregator before claiming compliance with `REQ-LABOR-003`. |
| **ADV-003** | **P4 Rule Collision** | **P2** | **WARN** | **SPEC_QUOTE**: `REQ-LABOR-002`: "深夜時間帯 (`[22:00, 05:00)`)"<br>**CODE**: `AttendanceTimeCalculator.java` `regularNightWorkMinutes` (L75)<br>**TEST**: `nightBreakDeduction_ShouldDeductOnlyFromNightRange` (L102) | **Scenario**: The definition of Night is `[22:00, 05:00)`. What happens at exactly 05:00? The interval is half-open, so 05:00:00 is *not* night. However, if an employee works 23:59:59 to 05:00:01, the system must split the minute. The test `nightBreakDeduction` verifies deduction, but does it verify the **exact second** boundary? If the system uses `LocalTime` with minute precision, 05:00 is safe. If it uses millisecond precision, the boundary is clear. However, the risk lies in **Break Deduction**. If a break spans 21:55 to 22:05, how is the "Night" portion of the break calculated? The spec says "strict deduction." If the break is 10 mins, and 5 mins are Night, does the system deduct 5 mins from Night work? The test `nightBreakDeduction_ShouldDeductOnlyFromNightRange` implies yes, but the **calculation logic** for partial-minute breaks within the night band is not explicitly detailed in the traceability matrix beyond the method name.<br>**Recommendation**: Add a specific test case for a break that starts in Day and ends in Night (e.g., 21:50 - 22:10) to ensure the "strict deduction" logic correctly splits the break time between Day and Night categories before applying the 25% premium. |
| **ADV-004** | **P7 Irreversibility** | **P2** | **WARN** | **SPEC_QUOTE**: `REQ-LABOR-005`: "Minimum wage... `appliedHourlyWage` inheritance"<br>**CODE**: `LaborCalculationService.java` L71-L75 (`findHourlyWageForStaffOnDate`)<br>**DOC**: Section 4, Item 2 mentions `prefecture_minimum_wage` history table is a *future* extension. | **Scenario**: The current implementation uses a hardcoded `minHourlyWage = 1280` (L31-L32) or a lookup that may not be historically accurate. If the minimum wage changes mid-month, and the system uses the *current* minimum wage to recalculate past days (retroactive edit), it may violate the "As-Built" state. More critically, if `findHourlyWageForStaffOnDate` returns a `null` or default value when the specific date's wage record is missing (due to data entry error), does it default to the hardcoded 1280? If so, and the actual wage was higher, the system **underpays** the employee. The traceability does not show a "Fail-Safe High" mechanism (i.e., if wage is unknown, assume the highest possible rate to prevent underpayment).<br>**Recommendation**: Implement a "Fail-Safe High" logic for wage lookups. If the specific date's wage is missing, default to the *maximum* wage recorded for that employee in the last 30 days, or the current minimum wage, whichever is higher, and flag for audit. Do not silently default to a hardcoded constant. |

---

## 3. JSON Output

```json
{
  "audit_engine": "Hermes-2Tier-Adversarial",
  "version": "1.2.0",
  "findings": [
    {
      "finding_id": "ADV-001",
      "vector": "P1 Blocked-Terminator",
      "severity": "P0",
      "verdict": "FAIL",
      "evidence": "SPEC_QUOTE: '未退勤打刻 (clockOutAt == null) 時の IllegalStateException 送出' (REQ-LABOR-001). CODE: LaborCalculationService.java L53-L55 throws exception. TEST: clockOutBeforeClockIn_ShouldThrowException verifies exception, not recovery.",
      "scenario": "Employee works full shift but fails to clock out. System throws IllegalStateException. If batch job skips failed records, work is unrecorded (Ghost Work), resulting in unpaid wages and legal liability.",
      "recommendation": "Replace hard exception with a 'Safe Harbor' default clock-out (e.g., end of shift or 24:00) that flags the record for manual review. Ensure wages are calculated provisionally to prevent unrecorded work."
    },
    {
      "finding_id": "ADV-002",
      "vector": "P6 Silent Default",
      "severity": "P1",
      "verdict": "WARN",
      "evidence": "SPEC_QUOTE: '月間端数処理規約の統制' (REQ-LABOR-003). CODE: PayrollCalculator.java L150-L153 uses daily/per-component rounding. DOC: Section 4 states monthly BigInteger aggregation is a 'future extension'.",
      "scenario": "SSOT requires monthly rounding control, but Java implementation rounds per day/component. This may cause cumulative rounding drift compared to statutory monthly aggregation requirements, leading to minor but systematic wage discrepancies.",
      "recommendation": "Trace the 'Monthly' aggregation logic explicitly. If daily rounding is used, provide legal justification for equivalence. Otherwise, implement the monthly BigInteger aggregator to ensure strict compliance with 'Monthly rounding convention'."
    },
    {
      "finding_id": "ADV-003",
      "vector": "P4 Rule Collision",
      "severity": "P2",
      "verdict": "WARN",
      "evidence": "SPEC_QUOTE: '深夜時間帯 ([22:00, 05:00))' (REQ-LABOR-002). CODE: AttendanceTimeCalculator.java regularNightWorkMinutes. TEST: nightBreakDeduction_ShouldDeductOnlyFromNightRange.",
      "scenario": "Breaks spanning the 22:00 boundary (e.g., 21:50-22:10) require precise splitting of break time between Day and Night categories. Current tests verify deduction exists but may not verify the exact minute-level split logic for partial-night breaks, risking incorrect premium calculation.",
      "recommendation": "Add specific unit tests for breaks that cross the 22:00 and 05:00 boundaries to verify that break time is correctly apportioned between Day and Night categories before premium calculation."
    },
    {
      "finding_id": "ADV-004",
      "vector": "P7 Irreversibility",
      "severity": "P2",
      "verdict": "WARN",
      "evidence": "SPEC_QUOTE: 'Minimum wage... appliedHourlyWage inheritance' (REQ-LABOR-005). CODE: LaborCalculationService.java L31-L32 (hardcoded 1280), L71-L75 (lookup).",
      "scenario": "If wage lookup fails or returns null for a specific date, the system may default to a hardcoded minimum (1280). If the employee's actual wage was higher, this results in underpayment. There is no 'Fail-Safe High' mechanism to prevent underpayment during data gaps.",
      "recommendation": "Implement 'Fail-Safe High' logic: if wage is missing, default to the highest recent wage or current minimum (whichever is higher) and flag for audit. Do not silently default to a hardcoded constant that may be lower than the actual wage."
    }
  ]
}
```