# Slice 1 Cross-Audit: REQ-STORE-001 to REQ-STAFF-002

**Overall verdict: NOT READY for approval.** There are 4 P0 and 9 P1 findings. The spec states its security intent (the DoD says access is "ç¢ºå®ã«é®æ­") but defines no mechanism for store-scoped authorization, retroactive-change control, or lifecycle states.

## 1. Multi-store authorization leaks

| ID | Item | Sev | Verdict | Recommendation |
|---|---|---|---|---|
| A-01 | REQ-STAFF-001 DoD ("æå±åºèå¤ã¢ã¯ã»ã¹é®æ­") | **P0** | FAIL: no enforcement rule. RBAC is global (`ROLE_OWNER`/`ROLE_STAFF`), with no store-scoped check. | Add a normative rule: every store-bound API must verify `store.owner_id == principal.id` (owner) or an `ACTIVE` `store_staff(store_id, principal.id)` (staff). Enforce it centrally (e.g. `@PreAuthorize("@storeAuth.canAccess(#storeId)")`) and add a cross-store negative test matrix. |
| A-02 | REQ-STAFF-001 input `initialHourlyWage` / `dailyTransportFee` supplied by the applying staff | **P0** | FAIL: the applicant self-declares their own wage and allowance, which is a privilege and integrity hole. | The applicant submits only `inviteCode`. The owner sets wage and allowance at approval, and the contract is created at that point. |
| A-03 | REQ-STAFF-001 `memberId` and REQ-STORE-001 `ownerId` as request inputs | **P1** | CONTRADICTS REQ-MEMBER-001 Â§4 (IDOR elimination). | Remove both from the API input. Derive them from `SecurityContext`. |
| A-04 | REQ-STAFF-001 Â§3 "PENDING **ã¾ãã¯** ãªã¼ãã¼æ¿èªã«ãã ACTIVE" | **P1** | AMBIGUOUS: the state-transition rule is undefined, so direct `ACTIVE` on join is possible. | Define a state machine: `PENDING â ACTIVE/REJECTED`, `ACTIVE â SUSPENDED/TERMINATED`. Joins always start as `PENDING`. Only the store's own owner can transition. `PENDING` grants no data access. |
| A-05 | Role model: one global `role` per member | **P1** | GAP: an owner who also works as staff at another owner's store (common in Japanese SMBs) cannot be modeled. | Make roles store-scoped (the relationship determines the role), or explicitly prohibit and document dual roles. |
| A-06 | REQ-LABOR-004 mentions åºé·, but Slice 1 defines only OWNER and STAFF | **P1** | GAP: the manager role and its delegation scope are missing. | Add `ROLE_MANAGER` or a store-scoped permission set, including who may approve staff, edit contracts, and confirm payroll. |
| A-07 | Cross-store aggregation (å´åºæ³38æ¡, éç®å´åæé) | **P1** | RISK: the same employer (one owner, several stores) must a