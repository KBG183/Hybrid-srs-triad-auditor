### [Hermes Audit Execution Metrics v1.2.0]
| Target File | Model | Duration | Input Code Tokens | Output Tokens | Speed | Done Reason | Run ID |
|---|---|---|---|---|---|---|---|
| config\srs_specification_ssot.md | qwen27b:latest (IQ3_M) | 82.56s | 8763 tokens | 3820 tokens | 49 tokens/s | stop | 20261119_071847_51506ae9 |

### Interaction Matrix & Adversarial Simulation Narrative

**1. Rule Extraction & State Identification**
*   **State Machine (REQ-ATT-002):** `UNCLOCK` -> `WORKING` -> `ON_BREAK` -> `WORKING` -> `CLOSED`.
*   **Youth Guard (REQ-STORE-002):**
    *   *Pre-check:* Blocks `CLOCK_IN` if shift overlaps prohibited hours (22:00-05:00 for minors).
    *   *Post-check (Critical):* "退勤打刻 (`CLOCK_OUT`) ... is strictly prohibited from being rejected with an error... Retention is determined at the true time... `youth_night_violation_flag = TRUE`... full wage payment."
    *   *Age Calculation:* Leap year Feb 29 birthdate turns 18 on Mar 1 00:00 in non-leap years.
*   **Attendance Integrity (REQ-ATT-001):**
    *   GPS Geofence: Must be within 100m.
    *   Accuracy: `horizontalAccuracy` must be <= 50.0m.
    *   Mock Location: `isMockProvider` must be false.
    *   Timestamp: `fixTimestamp` must be within 60s of server time.
*   **Correction Flow (REQ-ATT-003):**
    *   Two-person approval (or single owner bypass).
    *   Immutable audit log with hash chain.
    *   OCC (Optimistic Concurrency Control) via `baseVersion`.

**2. Adversarial Simulation: The "Ghost Work" Deadlock (P1/P2 Vector)**

*   **Scenario A: The Indoor/Underground Store Failure**
    *   *Context:* A store is located in a basement or has poor GPS reception. The staff member is physically present and working.
    *   *Event:* Staff attempts `CLOCK_IN`.
    *   *System Behavior:* GPS signal is weak. `horizontalAccuracy` returns 80.0m (or `isMockProvider` is falsely triggered by OS glitch, or simply distance > 100m due to GPS drift indoors).
    *   *Result:* System throws `ValidationException (HTTP 422 LOCATION_ACCURACY_UNRELIABLE)` or `LOCATION_OUT_OF_BOUNDS`.
    *   *Consequence:* The `attendance_session` remains in `UNCLOCK` state. No `sessionId` is generated.
    *   *Escalation:* Staff starts working. 8 hours pass. Staff attempts `CLOCK_OUT`.
    *   *System Behavior:* Since no active session exists, the system cannot process a `CLOCK_OUT` against a non-existent session. The staff is effectively "unrecorded."
    *   *Legal Impact:* The employer has no record of work. If the staff claims wages, the employer has no system evidence. If the staff *doesn't* claim wages (due to fear of termination for "not clocking in"), they suffer wage loss. This violates the principle of recording actual work hours. The spec mandates "Append-Only" recording of *valid* events, but provides no mechanism to record *invalid-but-physically-real* events without a prior valid session.

*   **Scenario B: The Midnight Youth Boundary & Wage Calculation**
    *   *Context:* Staff born Feb 29, 2000. Current year: 2023 (Non-leap).
    *   *Event:* Shift starts Feb 28, 2023, 23:00 JST.
    *   *Age Check:* At 23:00, staff is 17 (legal minor). At 00:00 Mar 1, staff becomes 18 (adult).
    *   *System Behavior:*
        *   `CLOCK_IN` at 23:00: Valid (Adult? No, Minor. But wait, is 23:00 "Night"? Yes, 22:00-05:00).
        *   *Conflict:* REQ-STORE-002 states: "Shall strictly prohibit... SiFT registration... for minors... in the late-night time slot (22:00-05:00)."
        *   If the shift is *registered* as 23:00-07:00, the system must block it *before* clock-in because the *start* is in the prohibited zone for a minor.
        *   *However*, if the staff clocks in at 23:00 (Minor), works until 00:00, then continues to 07:00 (Adult).
        *   *Wage Calculation:* REQ-LABOR-005 calculates wage based on `business_date`.
        *   *The Paradox:* The spec says `business_date` is fixed to the "start date" (REQ-ATT-002, Item 4).
        *   *Issue:* If the staff is a Minor at 23:00, they are subject to Minor Wage Laws (if applicable) or specific youth protections. If they become an Adult at 00:00, do their wage rates change mid-session? The spec says `applied_rate` is determined by `business_date`. It does not specify *segmented* wage calculation based on age change *within* a session. It implies a single rate for the session. This creates a legal ambiguity: Was the 23:00-00:00 hour paid at the Minor rate or Adult rate? The spec forces a single `business_date` logic, potentially misclassifying the first hour's labor status for wage calculation purposes if minor/adult wage floors differ.

*   **Scenario C: The "Silent Default" of GPS Failure during Break**
    *   *Context:* Staff is `WORKING`. Walks to a nearby cafe (150m away) for a break.
    *   *Event:* Staff attempts `BREAK_START`.
    *   *System Behavior:* GPS distance > 100m. `LOCATION_OUT_OF_BOUNDS` thrown.
    *   *Consequence:* Staff cannot start break. They are technically still `WORKING` in the system.
    *   *Escalation:* Staff returns to store (within 100m). Attempts `BREAK_END`.
    *   *System Behavior:* State is `WORKING`. `BREAK_END` is an invalid transition from `WORKING` (must be `ON_BREAK` -> `WORKING`).
    *   *Result:* Staff cannot record the break. The entire 15-minute break is counted as `WORKING` time.
    *   *Legal Impact:* Overpayment of wages (employer pays for break time). While not a wage *loss* for the employee, it creates a "Record-vs-Reality Divergence" (P2). The employer is liable for overtime calculations based on inflated hours. If this pushes the employee over the 40-hour weekly limit, the employer faces legal liability for unpaid overtime premiums on the *actual* work, but the system records show excessive hours. The correction flow (REQ-ATT-003) requires a "Correction Reason" and two approvals, which is operationally heavy for a simple GPS glitch during a break.

### Findings Table

| Finding ID | Attack Vector | Severity (P0/P1/P2/Info) | Verdict (PASS / WARN / FAIL / N/A) | Code & Test Evidence | Detailed Scenario & Recommendation |
|---|---|---|---|---|---|
| ADV-001 | P1 Blocked-Terminator | P0 | FAIL | **SPEC_QUOTE:** "horizontalAccuracy > 50.0m ... is blocked"; "distance > 100m ... blocked"; "CLOCK_OUT ... is strictly prohibited from being rejected with an error" (implied by "true time" requirement, but blocked by pre-conditions). **DERIVED:** If `CLOCK_IN` fails due to GPS, no `sessionId` exists. `CLOCK_OUT` requires a valid `sessionId` (REQ-ATT-002 Input). | **Scenario:** Staff works in a basement store with poor GPS. `CLOCK_IN` fails (422). Staff works 8 hours. `CLOCK_OUT` fails because no session exists. Work is unrecorded. **Recommendation:** Implement a "Manual Override Clock-In" that creates a `DRAFT` or `MANUAL` session with a flag, allowing the `CLOCK_OUT` to succeed and attach to the manual session, preserving the audit trail of *attempted* objective clocking. |
| ADV-002 | P2 Record-vs-Reality Divergence | P1 | WARN | **SPEC_QUOTE:** "State transition: WORKING -> ON_BREAK (BREAK_START)"; "GPS distance > 100m ... blocked". **DERIVED:** If `BREAK_START` is blocked by GPS, state remains `WORKING`. `BREAK_END` is invalid from `WORKING`. | **Scenario:** Staff goes 150m away for lunch. `BREAK_START` rejected. Staff returns. `BREAK_END` rejected (Invalid Transition). Break time is recorded as Work Time. **Recommendation:** Allow `BREAK_START` to succeed if the *previous* state was valid, or allow `BREAK_END` to implicitly close a "de facto" break if the user was away for >X minutes, logging a `GPS_ANOMALY` flag rather than hard-blocking the state transition. |
| ADV-003 | P3 Boundary Instant | P1 | WARN | **SPEC_QUOTE:** "business_date ... fixed to 'start date'"; "Age ... calculated at time of employment". **DERIVED:** Wage rate `applied_rate` is derived from `business_date`. Age changes at 00:00. | **Scenario:** Minor (17yo) works 23:00-07:00. Turns 18 at 00:00. `business_date` is Day 1. Wage calculated using Day 1 rules. If Minor/Adult wage floors differ, the 23:00-00:00 hour might be underpaid or overpaid relative to the *actual* legal status at that minute. **Recommendation:** Implement segmented wage calculation where the `applied_rate` is recalculated at the 00:00 boundary within the session, or explicitly state that the *start* age determines the entire session's wage class. |
| ADV-004 | P6 Silent Default | P1 | WARN | **SPEC_QUOTE:** "isMockProvider == true ... blocked"; "horizontalAccuracy > 50.0m ... blocked". **DERIVED:** No fallback mechanism specified for when GPS is *unavailable* (null/timeout) vs *inaccurate*. | **Scenario:** Phone GPS module hangs. `latitude`/`longitude` are null or stale. System blocks clock-in. Staff cannot start work. **Recommendation:** Define behavior for `null` GPS data. Should it default to "Store Location" with a `LOW_CONFIDENCE` flag, or require manual manager approval? Currently, it defaults to "Hard Block," causing operational deadlock. |
| ADV-005 | P7 Irreversibility | P2 | WARN | **SPEC_QUOTE:** "Append-Only ... attendance_event"; "Correction ... PENDING_FIRST -> PENDING_SECOND". **DERIVED:** If a `CLOCK_IN` is recorded with wrong GPS (e.g., 99m, valid) but staff was actually 200m away (proxy punch), the event is immutable. | **Scenario:** Staff A punches in for Staff B. GPS is within 100m (Staff A stands near door, Staff B is inside). Event is valid. Later discovered. Correction requires 2 approvals. If the "Owner" is the one who committed the fraud (single owner store), the `is_single_owner_bypass` allows them to alter the record with only their own approval, defeating the "Immutable Audit" intent for fraud prevention. **Recommendation:** For single-owner stores, require an external audit log export or secondary verification (e.g., photo evidence) for corrections involving wage impact > threshold. |

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
      "evidence": "SPEC_QUOTE: 'horizontalAccuracy > 50.0m ... is blocked'; 'distance > 100m ... blocked'. DERIVED: CLOCK_OUT requires a valid sessionId which is only created upon successful CLOCK_IN. If CLOCK_IN fails due to GPS, no session exists to terminate.",
      "scenario": "Staff works in a basement store with poor GPS. CLOCK_IN fails (422). Staff works 8 hours. CLOCK_OUT fails because no session exists. Work is unrecorded, leading to potential wage loss or unrecorded labor.",
      "recommendation": "Implement a 'Manual Override Clock-In' that creates a DRAFT or MANUAL session with a flag, allowing the CLOCK_OUT to succeed and attach to the manual session, preserving the audit trail of attempted objective clocking."
    },
    {
      "finding_id": "ADV-002",
      "vector": "P2 Record-vs-Reality Divergence",
      "severity": "P1",
      "verdict": "WARN",
      "evidence": "SPEC_QUOTE: 'State transition: WORKING -> ON_BREAK (BREAK_START)'; 'GPS distance > 100m ... blocked'. DERIVED: If BREAK_START is blocked by GPS, state remains WORKING. BREAK_END is invalid from WORKING.",
      "scenario": "Staff goes 150m away for lunch. BREAK_START rejected. Staff returns. BREAK_END rejected (Invalid Transition). Break time is recorded as Work Time, causing record divergence and potential overtime miscalculation.",
      "recommendation": "Allow BREAK_START to succeed if the previous state was valid, or allow BREAK_END to implicitly close a 'de facto' break if the user was away for >X minutes, logging a GPS_ANOMALY flag rather than hard-blocking the state transition."
    },
    {
      "finding_id": "ADV-003",
      "vector": "P3 Boundary Instant",
      "severity": "P1",
      "verdict": "WARN",
      "evidence": "SPEC_QUOTE: 'business_date ... fixed to start date'; 'Age ... calculated at time of employment'. DERIVED: Wage rate applied_rate is derived from business_date. Age changes at 00:00.",
      "scenario": "Minor (17yo) works 23:00-07:00. Turns 18 at 00:00. business_date is Day 1. Wage calculated using Day 1 rules. If Minor/Adult wage floors differ, the 23:00-00:00 hour might be underpaid or overpaid relative to the actual legal status at that minute.",
      "recommendation": "Implement segmented wage calculation where the applied_rate is recalculated at the 00:00 boundary within the session, or explicitly state that the start age determines the entire session's wage class."
    },
    {
      "finding_id": "ADV-004",
      "vector": "P6 Silent Default",
      "severity": "P1",
      "verdict": "WARN",
      "evidence": "SPEC_QUOTE: 'isMockProvider == true ... blocked'; 'horizontalAccuracy > 50.0m ... blocked'. DERIVED: No fallback mechanism specified for when GPS is unavailable (null/timeout) vs inaccurate.",
      "scenario": "Phone GPS module hangs. latitude/longitude are null or stale. System blocks clock-in. Staff cannot start work.",
      "recommendation": "Define behavior for null GPS data. Should it default to 'Store Location' with a LOW_CONFIDENCE flag, or require manual manager approval? Currently, it defaults to 'Hard Block', causing operational deadlock."
    },
    {
      "finding_id": "ADV-005",
      "vector": "P7 Irreversibility",
      "severity": "P2",
      "verdict": "WARN",
      "evidence": "SPEC_QUOTE: 'Append-Only ... attendance_event'; 'Correction ... PENDING_FIRST -> PENDING_SECOND'. DERIVED: If a CLOCK_IN is recorded with wrong GPS (e.g., 99m, valid) but staff was actually 200m away (proxy punch), the event is immutable.",
      "scenario": "Staff A punches in for Staff B. GPS is within 100m. Event is valid. Later discovered. Correction requires 2 approvals. If the 'Owner' is the one who committed the fraud (single owner store), the is_single_owner_bypass allows them to alter the record with only their own approval, defeating the 'Immutable Audit' intent for fraud prevention.",
      "recommendation": "For single-owner stores, require an external audit log export or secondary verification (e.g., photo evidence) for corrections involving wage impact > threshold."
    }
  ]
}
```