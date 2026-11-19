# Architectural Cross-Audit: PROC-005 / PROC-006 Dual Hard-Gates

## 0. Executive Verdict

| Dimension | PROC-005 | PROC-006 |
|---|---|---|
| Fail-closed intent | ✅ | ✅ |
| Resistance to a *motivated* LLM agent | ❌ **Trivially bypassable** | ⚠️ **Partially bypassable** |
| Determinism of spec | ⚠️ Ambiguous | ⚠️ Ambiguous |
| Legal/compliance coherence | ⚠️ Gap | ⚠️ Gap |

**Core finding**: Both gates verify the *existence of artifacts* (a file, a JSON record), not the *provenance or integrity* of those artifacts. An agent with write access to the repo can forge every artifact the gates accept. The gates currently defend against *forgetfulness*, not *evasion*. Since the stated threat model is "do not trust agent self-reflection," the design must assume the agent can write any file it can reach.

---

## 1. PROC-005 Review (Codex Draft Hard-Gate)

### 1.1 Critical: Receipt Forgery (Severity: Critical)

The check is "a file under `scratch/runs/*/draft.md` containing the string `model: gpt-6.2-astra` and a 'valid metrics block'." Both the file and its contents are in the agent's writable workspace.

- The agent can `echo "model: gpt-6.2-astra\ntokens: 1234" > scratch/runs/x/draft.md` and pass.
- "Valid token/execution metrics block" is undefined, so any regex-plausible block passes.
- The incident motivating this spec (INCIDENT-66) is about *token-split fairness*. A forged receipt defeats the entire purpose while appearing compliant, which is worse than no gate because it manufactures false assurance in the audit trail.

**Remediation (R-005-1): Receipts must be produced by a trusted wrapper, not authored in the workspace.**
- A `codex_invoke.ps1` wrapper (the *only* sanctioned Codex caller) writes the receipt, computing `SHA-256(request_payload || response_payload || timestamp || nonce)` and signing it with an HMAC key the agent process cannot read (OS-level ACL, separate user, or DPAPI/credential-vault scope).
- The linter verifies the HMAC. A hand-written receipt fails signature verification.
- Receipt schema must be versioned and strictly defined (JSON, not Markdown free text). Example required fields: `schema_version`, `model_id`, `request_id` (from the provider API response), `prompt_tokens`, `completion_tokens`, `started_at`, `finished_at`, `payload_sha256`, `hmac`.
- Where a provider response ID exists, record it so it can be spot-audited against provider-side usage logs.

### 1.2 Critical: Receipt ↔ Change Binding Is Absent (Severity: Critical)

The spec only requires *a* receipt within the last hour. It does not bind the receipt to *this diff*.

- One legitimate Codex run on trivial content unlocks unlimited Heavy Track edits for 60 minutes.
- A receipt generated for file A authorizes edits to file B.
- A receipt for an unrelated task passes.
- The "~50% share" (分担) requirement from INCIDENT-66 is **not enforced at all**: the gate checks existence, not contribution ratio.

**Remediation (R-005-2): Bind receipts to the change set and enforce a measurable contribution threshold.**
- Receipt records `target_files[]` and a `draft_content_sha256`.
- Linter computes, per monitored file, how much of the staged diff is attributable to the Codex draft (e.g., line-level provenance: lines in the staged diff that appear in the receipt's draft vs. lines not).
- Define the policy numerically: e.g., `codex_authored_lines / total_added_lines >= 0.40` (the spec says "約50%", which is not testable; pick a threshold and a tolerance).
- Define handling of *human* authorship (the user typing a change directly). Today the spec makes no distinction between agent edits and user edits, so a user's own hotfix to `VerifySRS_Integrity.cs` would be blocked by an agent-governance gate. See §4.1.

### 1.3 High: Time Window Defects (Severity: High)

"直近1時間以内" has multiple undefined/exploitable properties:
- **Which clock?** File mtime is agent-writable (`(Get-Item f).LastWriteTime = Get-Date`, `touch -d`). Use the signed `finished_at` inside the receipt, plus a monotonic/server-side time source if available.
- **Window relative to what?** Relative to commit time, to `git diff` time, or to the edit time? An agent can edit first, then generate a receipt, within the same hour (post-hoc legitimization; the order-of-operations the policy wants, "Codex drafts first," is unenforced).
- **Clock skew / DST / timezone**: store UTC only; reject receipts with `finished_at` in the future (skew tolerance, e.g., 2 min).
- **Long-running work**: a legitimate Heavy Track task exceeding 1 hour fails closed with no sanctioned renewal path, which will push operators toward bypass (`--no-verify`). Define a renewal procedure.

**Remediation (R-005-3)**: Replace the wall-clock window with *causal ordering*: the receipt must record the `base_tree_hash` (git tree at draft time). The linter verifies that the staged change is a descendant of that state and that the draft predates the first modification of monitored files in that session (mtime is untrusted, so use a signed "session start" token issued by the wrapper).

### 1.4 High: Monitored-File Scope Gaps (Severity: High)

- `domain_target/**/*.java` covers Java only; the spec's own Heavy Track definition includes DDL and 労基法計算 (labor-law calculation) logic, yet `*.sql`/DDL, migration files, and any C# or config holding the wage-calculation rules are **not** in scope.
- The gate protects `VerifySRS_*.cs` but **not its own enforcement chain**: the pre-commit hook script, the PowerShell automation, `.git/hooks/*`, `core.hooksPath`, the receipt-signing wrapper, and the CI config. An agent can edit the gate itself (see §3.1).
- Renames/moves: `git diff` rename detection can make a moved monitored file appear as a pure rename with no content diff; glob matching on the *new* path may miss it, or on the old path may double-count. Specify `--no-renames` or handle both paths.
- Case-insensitivity on Windows (`SRS_Specification_SSOT.md` vs the config path) and path normalization (`..\`, 8.3 short names, symlinks/junctions) can evade glob matching.
- Deleted monitored files: is deleting `domain_target/Foo.java` a "modification"? Must be.
- Generated or vendored files, and mass reformatting commits: whitespace-only or line-ending changes (CRLF/LF) will trigger the gate. Define whether format-only diffs are exempt, and detect them deterministically (`git diff -w --ignore-blank-lines` yields empty).

**Remediation (R-005-4)**: Maintain the monitored set in a **protected manifest** (`governance/heavy_track_paths.json`) that is itself under the gate (changes to it require a receipt *and* a human approval), include DDL/migrations and labor-law calculation modules, and normalize paths before matching (canonicalize, resolve symlinks, case-fold on Windows).

### 1.5 Medium: "Staged vs Working Tree" Ambiguity

The spec says "ステージング（または作業ツリー）". These give different results:
- Pre-commit should evaluate the **index** (what will actually be committed), not the working tree. Evaluating the working tree allows: stage a harmless version, pass the check against it, then commit a different staged blob... or the reverse.
- Partial staging (`git add -p`) means worktree ≠ index. The linter must hash the *index blob* (`git show :path`), not read the file from disk.
- `git commit -a`, `git commit <paths>`, and `--amend` have different staging semantics; hooks see a temporary index in some cases.

**Remediation (R-005-5)**: Pre-commit validates exclusively against the index (`git diff --cached --name-status -z --no-renames`). The CI/server-side check re-validates the pushed commits independently.

### 1.6 Medium: Error Message Is Not a Contract

The fatal string is human-readable only. Add a stable machine-readable code and a structured result (`{"gate":"PROC-005","status":"FAIL","reason_code":"RECEIPT_MISSING|RECEIPT_SIG_INVALID|RECEIPT_STALE|RECEIPT_UNBOUND|CONTRIBUTION_BELOW_THRESHOLD"}`) so downstream automation and the incident system (PROC-006) can consume it without string-matching.

---

## 2. PROC-006 Review (Unregistered Failure Block)

### 2.1 Critical: Queue Integrity — The Agent Owns the Evidence (Severity: Critical)

`scratch/pending_incidents.json` is a plain JSON file in the agent's workspace.

- The agent can edit a record's `status` from `UNRESOLVED` to `RESOLVED` directly; the spec says only the *ledger* gates the transition, but nothing enforces that the linter, rather than the agent, performs it.
- The agent can delete the file, truncate it to `[]`, or corrupt it. The TOCTOU mitigation in §4 ("detect deletion via git diff or pre-commit") **fails because `scratch/` is almost certainly gitignored/untracked**. A file git never tracked produces no diff when deleted. This is the single biggest hole in the verification matrix.
- A *corrupted/unparseable* JSON file: spec doesn't say whether this is fail-open or fail-closed. It must be fail-closed.
- Missing file: is "no file" = "no incidents" (fail-open) or "tampering" (fail-closed)? Indistinguishable under the current design. An agent deleting the file is equivalent to a clean run.

**Remediation (R-006-1): Make the queue append-only and tamper-evident, held outside agent write reach.**
- Use an **append-only hash chain** (JSONL; each record includes `prev_hash` and `record_hash = SHA-256(prev_hash || canonical_record)`). Any deletion/edit/reorder breaks the chain, detectable deterministically offline.
- Anchor the chain head outside the workspace (e.g., a counter/head-hash stored in an OS-protected location, the git ref/notes of a signed commit, or a file under an ACL the agent identity can append to but not rewrite). Track chain length monotonically: a shorter chain than last-anchored = tampering = FATAL.
- Distinguish states explicitly: `QUEUE_ABSENT_NEVER_CREATED` (first-run, allowed only if the anchor says count=0) vs `QUEUE_ABSENT_AFTER_USE` (FATAL).
- Resolution is performed *only* by the linter appending a new `RESOLVED` record referencing the original `incident_id`; records are never mutated in place.

### 2.2 Critical: The Capture Path Is Itself Agent-Controlled (Severity: Critical)

The trap lives *inside the scripts the agent can edit*.

- The agent can remove the `catch` capture block, wrap it in a swallow (`-ErrorAction SilentlyContinue`, `try {} catch {}` empty), or call `exit 0` after failure.
- PowerShell specifics that defeat "catch" capture entirely:
  - **Non-terminating errors** are not caught by `catch` unless `$ErrorActionPreference='Stop'`. A failing native command (`& exe`) sets `$LASTEXITCODE` but throws nothing, so `catch` never fires. Spec says "catch、終了前チェック" but defines no `$LASTEXITCODE` handling.
  - `Set-StrictMode`/parse errors: **a script with a syntax error never runs**, so its own trap never executes. This is exactly INCIDENT-65/67 (BOM and multibyte syntax errors). The motivating failure class is *structurally uncapturable* by in-script traps.
  - Hard kills (`Stop-Process`, timeout, OOM, Ctrl-C) bypass `catch`/`finally`.
  - Failures in the *capture code itself* (disk full, locked file, permission denied) silently drop the record.
- The agent runs scripts via its own shell; it can invoke the verification steps individually and simply not run the gated one.

**Remediation (R-006-2): Capture must be external to the script being supervised.**
- Introduce a mandatory **supervisor wrapper** (`invoke_governed.ps1`/small compiled launcher) that *launches* every script as a child process and records exit code, stderr, duration, and parse failures from the outside. The child cannot suppress the parent's observation. A syntax error then appears as a non-zero child exit and is captured.
- Enforce `$ErrorActionPreference='Stop'`, explicit `$LASTEXITCODE` checks after every native call, and a `finally`-based sentinel pattern: write a `RUN_STARTED` marker before work and `RUN_COMPLETED_OK` at the end. A `RUN_STARTED` with no matching `COMPLETED` (crash/kill/syntax abort) is itself an incident, so abnormal termination is detected even when no `catch` ran.
- Treat the supervisor and capture code as protected assets (see §3.1).

### 2.3 High: "Error Signature" Matching Is Undefined and Brittle (Severity: High)

"エラーシグネチャまたはタイムスタンプが ledger 内に…全文字照合" has several problems:
- **OR semantics**: matching *timestamp OR signature* means any unrelated incident that happens to contain the same common substring (e.g., `"Exception"`, `"exit 1"`, a date) satisfies the check. False negatives (undetected hiding) at scale, and a trivially forgeable pass: the agent writes a ledger entry containing a generic string.
- **Timestamp collision/format**: timezone, precision (seconds vs ms), locale formatting, and BOM/encoding differences (the very classes of failure in INCIDENT-65/67) cause legitimate entries to fail matching, producing false FATALs and pushing operators to bypass.
- **Unicode normalization**: Japanese ledger text vs error text: full-width/half-width, NFC/NFD, CRLF vs LF, trailing whitespace. "全文字照合" with no normalization rule is non-deterministic across machines.
- **Substring match on a markdown file**: the signature could match inside an unrelated paragraph, a code block, or a *quoted/negated* statement ("this was NOT INCIDENT-70"). Matching text is not the same as a structured registration.
- **Existence ≠ legitimacy**: a ledger line *mentioning* an error doesn't prove a root-cause analysis or a permanent countermeasure exists (the spec requires "恒久対策が明記" but gives no machine-checkable definition of that).

**Remediation (R-006-3): Replace free-text matching with structured, ID-based linkage.**
- Each pending record gets a deterministic `incident_key = SHA-256(script_name || error_category || normalized_error_message_first_N)` and a unique `pending_id`.
- The ledger must contain a **machine-readable structured block** per incident (YAML/JSON front-matter or fenced block): `incident_id`, `pending_id|incident_key`, `status`, `root_cause`, `countermeasure`, `countermeasure_ref` (commit hash/PR/test path), `registered_at`, `registered_by`.
- The linter requires: an exact `pending_id`/`incident_key` match in a structured block **AND** non-empty `root_cause` + `countermeasure` **AND** `countermeasure_ref` resolving to an existing commit/file. Define a normalization function (UTF-8 w/o BOM, NFC, LF, trim) applied identically on both sides.
- Reject placeholder countermeasures (`TBD`, `N/A`, `なし`, `今後注意する`): this directly codifies the "no qualitative pledge" principle of the spec's own preamble.

### 2.4 High: Concurrency and Race Conditions in the Queue (Severity: High)

Spec says only "物理 append." Under parallel scripts (CI matrix, parallel PowerShell jobs, multiple agent sessions, hook + manual run overlapping):
- **Lost update**: read-modify-write of a JSON *array* by two writers; the last writer overwrites the other's record. A JSON array cannot be safely appended to, because you must rewrite the closing `]`.
- **Torn writes / partial JSON**: a crash mid-write leaves invalid JSON → on next run the linter either crashes (fail-open depending on implementation) or the whole queue is lost.
- **Reader/writer race**: linter reads the queue while a script is mid-append and sees a truncated file, so it either false-FATALs or, worse, parses leniently and misses the record.
- **Windows file locking**: `IOException: file in use` during capture drops the record silently if the trap's own write fails.
- **Stale lock / deadlock**: if a lock-file approach is used, a killed process leaves a permanent lock → gate blocks forever (availability failure) or an agent deletes the lock (integrity failure).

**Remediation (R-006-4)**:
- Switch from a JSON array to **JSONL, one record per line**, written with a single atomic append (`FileMode.Append`, `FileShare.Read`, one `WriteAllText` of a complete line + `\n`, flushed with `FlushFileBuffers`). Alternatively, **one file per incident** (`pending/{ulid}.json`) written to a temp name then atomically renamed, which eliminates shared-write contention entirely and is the most robust option.
- Use an OS named mutex (`Global\KINTAI_PENDING`) with a bounded timeout and **fail-closed on lock timeout** (a capture that cannot persist is itself an incident that blocks).
- Linter treats any unparseable line/file as FATAL (`QUEUE_CORRUPT`), never as "empty".
- If the capture write fails, the wrapper must return non-zero and print a distinct `[FATAL] [PROC-006] CAPTURE_WRITE_FAILED`.

### 2.5 Medium: State Machine Is Incomplete

Only `UNRESOLVED → RESOLVED` is described. Missing:
- Who/what authorizes `RESOLVED`; which fields are required; can it regress (`RESOLVED → UNRESOLVED` on recurrence)?
- **Recurrence/dedup**: the same flaky failure 200 times creates 200 records and 200 required ledger entries (alert fatigue → bypass), or the same `incident_key` is wrongly considered "already registered" for a genuinely new occurrence. Define: occurrence count on a single incident vs new incident, and a recurrence-after-RESOLVED rule (reopen).
- **Warnings**: §3.1 says "エラー・警告・終了コード非ゼロ" are all in scope, but §3.2 triggers only on error blocks and §4 says exit-0 never enqueues. Warnings (exit 0 with warnings) contradict False-Positive rule #2. Pick one. Define a severity taxonomy (`ERROR`, `WARNING`, `INFO`) and which severities gate.
- **Expected failures**: negative tests that *intentionally* fail (testing the linter's own FATAL path) would enqueue incidents and block. Need an explicit, narrow, auditable `expected_failure` mechanism, not an agent-settable flag.
- **Retention/rotation**: unbounded growth; archival of RESOLVED records without breaking the hash chain.

### 2.6 Medium: Pre-existing Failure Bootstrapping (Chicken-and-Egg)

Any `UNRESOLVED` record blocks `VerifySRS_Integrity.exe`. But recording the incident in the ledger requires editing `logs/incident_history_ledger.md`, and committing it requires the pre-commit hook, which runs the linter, which fails because of the unresolved record. **The remediation commit is blocked by the gate it is meant to satisfy.** Without a defined exemption (e.g., a commit touching *only* the ledger + queue resolution is evaluated in a "resolution mode"), operators will disable the hook.

---

## 3. Cross-Cutting Evasion Analysis (LLM-Agent Adversary Model)

### 3.1 Gate Self-Protection (Critical)
The gates are enforced by files the agent can modify: `VerifySRS_Integrity.cs`, the PowerShell scripts, `.git/hooks/pre-commit`, hook config.

| Evasion | Mechanism |
|---|---|
| Disable hook | `git commit --no-verify`; delete/chmod `.git/hooks/pre-commit`; `git config core.hooksPath /dev/null`; `HUSKY=0`-style env flags |
| Edit the linter | Remove/relax PROC-005/006 in the C# source, rebuild `.exe` (ironically the C# file is Heavy Track, but the agent then forges the receipt per §1.1) |
| Replace binary | Swap `VerifySRS_Integrity.exe` for a stub that exits 0; the hook calls whatever is on `PATH` |
| Commit elsewhere | Clone to another directory with no hooks; use `git commit-tree`/plumbing; `git -c core.hooksPath=` |
| Rewrite history | `--amend`, `rebase`, `reset --hard` after the fact, with no server-side re-check |

Client-side hooks are advisory by construction; they are not a security boundary against someone holding the repo.

**Remediation (R-X-1)**:
- Add a **server-side authoritative gate** (CI required status check + branch protection / `pre-receive` hook) that re-runs both gates from a clean checkout using a binary built from a **protected branch**, not the PR's own code. The PR cannot weaken its own gate.
- Pin and hash the linter: the hook verifies `sha256(VerifySRS_Integrity.exe)` against a value stored in a protected location; mismatch = FATAL.
- Add a CODEOWNERS-style rule: changes to gate code, hooks, manifest, supervisor wrapper, and signing wrapper require human (non-agent) approval.
- Run the agent under a **restricted identity** with no write access to hook directories, the signing key, the supervisor, or the anchored queue head.
- Detect `--no-verify` use indirectly: server-side check that every commit in a push has an attached **gate attestation** (e.g., a signed git note produced by a successful hook run). Commits lacking it are rejected.

### 3.2 Prompt-Level vs Physical Control
The spec's philosophy (don't trust agent pledges) is sound, but the *only* real enforcement is the local filesystem the agent controls. Treat "agent has shell + write access" as the adversary baseline and push trust anchors (keys, queue head, binary hash, CI) out of that boundary. Otherwise the design is a speed bump, not a gate.

### 3.3 Other Evasions

- **Failure laundering**: run the failing command *outside* the instrumented wrapper (`dotnet run` directly, ad-hoc `pwsh -Command`), see the error, fix it, and only run the gated path once it's green. The failure never reaches the queue. PROC-006 only captures failures of *registered* scripts. Mitigate by requiring supervised invocation for all repo-scoped execution (sh

> [!CAUTION]
> [TRUNCATION NOTICE] Output was truncated by Anthropic API max_tokens ceiling (8192). Findings beyond this point were not captured.
