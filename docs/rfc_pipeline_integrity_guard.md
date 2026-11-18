# RFC-002: KINTAI Quality Pipeline Integrity Guard Architecture

## 1. Executive Summary & Objective
This architecture defines a three-tier deterministic barrier to eliminate human/AI synchronization errors, sensitive metadata leaks, and status discrepancies across markdown dashboards, CSV audit ledgers, and the Single Source of Truth (SSOT).

---

## 2. Three-Tier Integrity Architecture

```
[ Tier 1: Git Pre-Commit Hook (Physical Gate) ]
  - Regex scan on staged diff: Authorship, local absolute paths, private IPs, legacy identifier tokens.
  - Fail-Closed scan on staged files: Zero-Korean unicode ([\uAC00-\uD7A3]) enforcement on all public files.
  - Line ending enforcement: LF strictly required for shell interpreter compatibility.
         |
         v (PASS)
[ Tier 2: C# Deterministic Linter Gate (Structural & Cross-File Integrity) ]
  - VerifySRS_Integrity.exe expansion:
    1. CSV Column Cardinality: Validates each row column count against header (e.g. cloud_api_token_ledger.csv 8 cols vs 9 cols).
    2. Heading Cross-Check: Maps SSOT REQ-* headings 1:1 against pipeline_metrics.md §2 table.
    3. Audit Ledger vs Dashboard Verdict Alignment: Confirms CURRENT_STATUS.md reflects latest enterprise_audit_ledger.csv status.
  - Execution cost: 0 tokens, sub-second execution, deterministic abort.
         |
         v (PASS)
[ Tier 3: Automated Ledger-to-Dashboard Sync (Single Source of State) ]
  - Eliminate manual human/AI markdown edits on status boards.
  - hermes_controller.ps1 post-execution hook atomically renders CURRENT_STATUS.md directly from enterprise_audit_ledger.csv.
  - Guarantees zero discrepancy between raw audit logs and summary dashboards.
```

---

## 3. Multi-Engine Cross-Audit Dispatch Model
To optimize execution speed without race conditions:
1. **Phase 1 (Fail-Fast)**: Deterministic C# Linter. If failed, abort immediately with 0 cloud tokens spent.
2. **Phase 2 (Composite Hash Invalidation)**: `SHA256(TargetFileContent + PromptContent)`. If identical and cached, bypass model call.
3. **Phase 3 (Isolated Parallel Fan-Out)**:
   - Local Qwen 27B (`scratch/tmp_qwen.txt`)
   - OpenAI Codex CLI (`scratch/tmp_codex.txt`)
   - Anthropic Claude (`scratch/tmp_claude.txt`)
4. **Phase 4 (Atomic Join)**: Merge isolated buffers into final consolidated timestamped report.

---

## 4. Specific Issues Addressed
1. **H-1 (Phantom Requirement REQ-LABOR-004)**: Prevented by Tier 2 Cross-Heading Validator.
2. **H-2 (Audit REJECT vs Dashboard PASS contradiction)**: Prevented by Tier 3 Automated Sync.
3. **M-3 (CSV Header/Row Column Mismatch)**: Prevented by Tier 2 CSV Column Cardinality Linter.
4. **M-6 (Buffer Pollution / Stale Cache Re-use)**: Prevented by Isolated Buffers and pre-execution buffer wipe in Tier 3 dispatch.
5. **L-2 (Sensitive / Legacy Identifier Leakage)**: Prevented by Tier 1 Pre-Commit Hard-Gate.

---

## 5. Review Questions for Cross-Audit
1. **Tier 1 (Git Hook)**: Are there edge cases where `git commit --no-verify` or Windows Git GUI bypasses the hook? How to enforce server-side or pipeline redundancy?
2. **Tier 2 (C# Linter)**: Does cross-file checking introduce tight coupling that makes linting slow or fragile during rapid prototyping?
3. **Tier 3 (Automated Sync)**: Can race conditions occur during atomic rendering of `CURRENT_STATUS.md` if multiple background jobs run?
4. **Parallel Fan-Out**: What is the failure recovery behavior if one engine times out while two succeed?
