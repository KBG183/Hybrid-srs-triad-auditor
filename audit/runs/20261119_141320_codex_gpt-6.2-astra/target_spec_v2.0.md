# 🏛️ Architecture Option 2 Specification: Git-Bound Fail-Closed Dual Hard-Gates

Version: 2.0.0  
Auditor Target: OpenAI Codex (gpt-6.2-astra)  
Key Tenet: Zero Trust on Agent Workspace Files. Reliance only on Git Staged Index and Fail-Closed Trace Ledgers.

---

## 1. Problem Statement & Threat Model
Previous proposals (Option 1) relied on temporary files in `scratch/` and wrapper scripts (`run_guarded.ps1`), which are vulnerable to:
1. **Wrapper Bypass**: The agent directly runs `powershell -File script.ps1`, bypassing runtime tracking.
2. **Queue Tampering / Deletion**: The agent overwrites `scratch/pending_incidents.json` with an empty array or deletes it.
3. **Receipt Forgery**: The agent synthesizes a fake Markdown file in `scratch/runs/`.

Option 2 shifts enforcement entirely into **Git Staged Index (pre-commit hook) + C# Roslyn Linter (VerifySRS_Integrity) + Fail-Closed Tracked Trace Ledgers**.

---

## 2. PROC-005: Git-Bound Heavy Track Codex Draft Gate

### 2.1 Trigger Condition
- The Git pre-commit hook inspects `git diff --cached --name-only`.
- If any Heavy Track file is staged:
  - `config/srs_specification_ssot.md`
  - `domain_target/**/*.java`
  - `tools/scripts/VerifySRS_Integrity.cs`
  - `tools/scripts/VerifySRS_Deterministic.cs`

### 2.2 Verification Rule (Strict Staged Binding)
1. **Co-Staged Receipt Requirement**:
   - The commit index MUST simultaneously stage an official JSON receipt under `audit/runs/{timestamp}/codex_receipt.json`.
   - If no receipt is staged alongside the code changes, commit is rejected immediately (`exit 1`).
2. **Receipt Schema & Staged Blob Hash Binding**:
   - `codex_receipt.json` must be strictly formatted:
     ```json
     {
       "schema_version": "2.0",
       "run_id": "20261119_140625",
       "target_file": "config/srs_specification_ssot.md",
       "staged_blob_sha256": "...",
       "model": "gpt-6.2-astra",
       "prompt_tokens": 2048,
       "completion_tokens": 1024,
       "duration_sec": 55.2,
       "exit_code": 0
     }
     ```
   - C# Linter computes `SHA256(git show :"$target_file")` and verifies it matches `staged_blob_sha256`.
   - If hash mismatches or target file differs: `[FATAL] [PROC-005] Staged blob does not match signed Codex receipt.`

---

## 3. PROC-006: Tracked Trace Log & Incident Reconciliation Gate

### 3.1 Trace Log Architecture (`logs/incident_execution_trace.log`)
- Temporary files are eliminated. A Git-tracked ledger `logs/incident_execution_trace.log` is maintained.
- All testing, verification, and linting scripts append execution outcomes in structured single lines:
  `[2026-11-19T14:10:00Z] [VERIFY_REPO] [STATUS: FAIL] [CODE: ERR-BOM-001] [MSG: UTF-8 BOM detected in 5 files]`
  `[2026-11-19T14:10:30Z] [VERIFY_REPO] [STATUS: PASS] [CODE: OK] [MSG: All 10 checks passed]`

### 3.2 Verification Rule (Pre-Commit Hard-Gate)
1. **Fail-Closed on Log Absence**:
   - If `logs/incident_execution_trace.log` is missing, 0-byte, or not staged, the pre-commit hook rejects the commit:
     `[FATAL] [PROC-006] Execution trace log is missing or empty. Verification proof required.`
2. **Reconciliation with Incident Ledger**:
   - For every entry with `[STATUS: FAIL]` in the trace log since the last git commit (`HEAD`):
     - The error code or failure signature MUST physically match an active entry in `logs/incident_history_ledger.md`.
     - The entry in `incident_history_ledger.md` must have status `RESOLVED` and document permanent remediation.
   - If any `[STATUS: FAIL]` remains unmapped in `incident_history_ledger.md`:
     `[FATAL] [PROC-006] Unresolved/unregistered failure detected in trace log. Registration in incident_history_ledger.md required.`
3. **Recursion Prevention**:
   - Gate rejections (e.g., PROC-005/PROC-006 aborts) log with `[STATUS: GATE_BLOCKED]`, which is explicitly excluded from the `[STATUS: FAIL]` incident requirement, breaking recursive loops.

---

## 4. Evaluation Questions for Codex
1. Does this architecture close the loop on agent bypass (wrapper avoidance and file deletion)?
2. What are the edge cases in Git index extraction (`git show :file`) during merge conflicts, rebase, or partial staging (`git add -p`)?
3. How can `staged_blob_sha256` balance exact hash matching with post-Codex human/agent minor integration touch-ups?
4. Is there any remaining loophole where an agent could commit code without triggering this gate?
