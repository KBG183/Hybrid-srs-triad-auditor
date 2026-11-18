# 🏛️ KINTAI Hermes 多層統合検証レポート (Master Quality Audit Report)

- **検証日時 (Timestamp)**: 2026-11-17 16:35:44
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
=== [SRS DETERMINISTIC LINTER v1.1] Target: srs_specification_ssot.md ===
=== Linter Results: FATAL=0, WARNING=0 (Checked 8 Requirements) ===
>>> [PASS] All mandatory integrity and security checks passed cleanly.
`

---

## 3. [Step 1] ローカル Qwen 27B 主幹検証レポート
### [Hermes Audit Execution Metrics v1.1.1]
| Target File | Model | Duration | Input Code Tokens | Output Tokens | Speed | Done Reason | Run ID |
|---|---|---|---|---|---|---|---|
| config/srs_specification_ssot.md | qwen27b:latest (IQ3_M) | 53.72s | 5206 tokens | 2707 tokens | 50.6 tokens/s | stop | 20261117_073228_92d6a477 |

| Finding ID | Audit Item | Severity (P0/P1/P2/Info) | Verdict (PASS / WARN / FAIL / N/A) | Code & Test Evidence | Detailed Analysis & Recommendation |
|---|---|---|---|---|---|
| F-001 | Japanese Labor Standards Act Art 37: Night Work Premium Calculation | P0 | FAIL | **REQ-LABOR-002**<br>Code: `nightPay = Math.floor((hourlyWage * 0.25 * nightMinutes) / 60)` | **Critical Logic Error**: The specification calculates the *premium* portion only (`0.25 * wage`). However, the total pay for night hours must be `1.25 * wage` (Base + Premium). If this `nightPay` is added to a base calculation that already includes the full hours at `1.00 * wage`, the total is correct. However, if `nightPay` is intended to be the *total* payout for those minutes, it is underpaid by 75%. <br><br>**Recommendation**: Clarify that `nightPay` is strictly the *additional* premium. Ensure the main payroll engine adds `BasePay (all hours)` + `OvertimePremium` + `NightPremium`. If the engine replaces the base rate for night hours, the formula must be `hourlyWage * 1.25`. The current formula `0.25 * wage` is only valid as an *add-on* to the base wage. |
| F-002 | Japanese Labor Standards Act Art 37: Overtime Premium Calculation | P0 | FAIL | **REQ-LABOR-001**<br>Code: `overtimePay = Math.floor((hourlyWage * 0.25 * overtimeMinutes) / 60)` | **Critical Logic Error**: Similar to F-001, this calculates only the 25% premium. The total overtime pay must be `1.25 * wage`. If the system calculates `BasePay` for ALL minutes (including overtime) at `1.00 * wage`, then adding this `0.25` premium is correct. However, the spec does not explicitly state that `BasePay` covers the overtime minutes at 100%. <br><br>**Risk**: If the developer interprets `overtimePay` as the total payout for overtime minutes, the employee is underpaid. <br><br>**Recommendation**: Explicitly define the total daily pay formula in the SRS: `Total = (TotalMinutes * BaseRate) + OvertimePremium + NightPremium`. Ensure `BaseRate` is applied to ALL worked minutes, and premiums are additive. |
| F-003 | Japanese Labor Standards Act Art 37: Concurrent Night + Overtime (150%) | P1 | WARN | **REQ-LABOR-003**<br>Code: `Total = Base + OvertimePremium + NightPremium` | **Logic Verification**: The spec states that overlap naturally converges to 150% by adding both premiums (25% + 25%) to the base (100%). This is mathematically correct for the *premium* calculation. <br><br>**Risk**: The spec relies on the "Base" being calculated for *all* minutes. If the base calculation excludes overtime or night hours, the 150% target fails. <br><br>**Recommendation**: Add a specific unit test case in the DoD for a 10-hour shift entirely within 22:00-05:00. Expected: `Base (10h * 1.0) + OT Premium (2h * 0.25) + Night Premium (10h * 0.25)`. Total multiplier for the last 2 hours = 1.0 + 0.25 + 0.25 = 1.5. This confirms the logic is sound *if* implemented as additive premiums on top of a full base wage. |
| F-004 | Payroll Math & Rounding: 1-Yen Discrepancy Prevention | P1 | WARN | **REQ-LABOR-001/002/003**<br>Code: `Math.floor(...)` in individual components; `RoundingMode.HALF_UP` in REQ-LABOR-003 Exception | **Inconsistent Rounding Strategy**: <br>1. **REQ-LABOR-001 & 002** use `Math.floor` (truncation) for individual premium calculations. <br>2. **REQ-LABOR-003** mentions `RoundingMode.HALF_UP` for monthly aggregation. <br><br>**Risk**: Truncating individual daily premiums (e.g., `floor(12.4) = 12`) and then summing them may result in a total that is systematically lower than the mathematically precise amount, violating the "1-yen error" requirement if the final aggregation does not re-calculate from raw minutes. <br><br>**Recommendation**: Do NOT round intermediate daily premiums. Store raw minutes and wages. Calculate the final monthly total using high-precision arithmetic (e.g., `BigDecimal`) and apply `RoundingMode.HALF_UP` only at the final currency conversion step. Using `Math.floor` on daily components introduces cumulative rounding errors. |
| F-005 | Concurrency & Security: Pessimistic Locking on Contract History | P1 | PASS | **REQ-STAFF-002**<br>Code: `SELECT ... FOR UPDATE` on `store_staff` | **Correct Implementation**: The spec correctly identifies the need for pessimistic locking on the `store_staff` row (or the contract history table) to prevent race conditions when updating `effective_to` and inserting new records. <br><br>**Recommendation**: Ensure the lock is acquired on the *parent* `store_staff` row before querying/inserting into `store_staff_contract_history`. This prevents two concurrent transactions from both seeing `effective_to IS NULL` and creating duplicate active contracts. |
| F-006 | Concurrency & Security: Payroll Settlement Locking | P1 | PASS | **REQ-LABOR-004**<br>Code: `SELECT ... FOR UPDATE` on settlement record | **Correct Implementation**: The spec mandates row-level locking for monthly settlement. <br><br>**Recommendation**: Verify that the lock timeout (3 seconds) is configured correctly in the JPA/Hibernate properties (`jpa.properties` or `application.yml`). Ensure that the `PessimisticLockException` is caught and translated to a user-friendly HTTP 409 (Conflict) or 423 (Locked) response, rather than a generic 500 error. |
| F-007 | IDOR Vulnerability Prevention | P1 | PASS | **REQ-MEMBER-001** & **REQ-STAFF-001**<br>Code: `SecurityContextHolder` principal resolution | **Correct Implementation**: The spec explicitly forbids client-side `ownerId` or `staffId` input for authorization checks. It mandates resolving the ID from the `SecurityContext`. <br><br>**Recommendation**: Ensure that all repository queries (e.g., `findByStoreIdAndMemberId`) include the authenticated principal's ID as a mandatory filter parameter. Do not rely solely on service-layer checks; enforce it at the data access layer where possible. |
| F-008 | Exception Handling: DateTime Parsing & Edge Cases | P2 | WARN | **REQ-LABOR-002**<br>Code: "Overnight Shift... recognize as continuous interval" | **Missing Specifics on Date Boundary Logic**: The spec mentions handling overnight shifts but does not specify how `LocalDate` vs `LocalDateTime` is handled for the 22:00-05:00 window. <br><br>**Risk**: A shift from 23:00 to 04:00 crosses a date boundary. If the system calculates night hours based on `LocalDate` alone, it may fail to attribute the 00:00-04:00 portion to the correct "night" bucket if not handled as a continuous `ZonedDateTime` or `LocalDateTime` range. <br><br>**Recommendation**: Explicitly state that night hour calculation must use `LocalDateTime` ranges, not just `LocalDate`. Provide a test case: Clock In 23:00, Clock Out 04:00. Expected Night Minutes: 300 (5 hours). |
| F-009 | Data Integrity: Break Time Deduction in Night Hours | P1 | PASS | **REQ-LABOR-002**<br>Code: "Break time between 22:00~05:00 must be deducted specifically from night work hours" | **Correct Requirement**: The spec correctly identifies that breaks must be subtracted from the *night* bucket if they occur during night hours, not just from total hours. <br><br>**Recommendation**: Ensure the algorithm iterates through break intervals and calculates the intersection with the night window (22:00-05:00) separately from the intersection with the total work window. |
| F-010 | Security: Role Self-Elevation Prevention | P0 | PASS | **REQ-MEMBER-001**<br>Code: `role = 'ROLE_STAFF'` hardcoded on registration | **Correct Implementation**: The spec explicitly prohibits client-side role assignment during registration. <br><br>**Recommendation**: Ensure that the `Member` entity constructor or DTO mapping does not expose the `role` field for public registration endpoints. Use a separate, secured admin endpoint for role changes. |
| F-011 | Validation: Minimum Wage Enforcement | P2 | WARN | **REQ-STAFF-002**<br>Code: `hourlyWage` < minimum wage check | **Missing Dynamic Minimum Wage Data**: The spec mentions checking against "regional minimum wage" but does not specify where this data comes from. <br><br>**Risk**: If the minimum wage is hardcoded or not updated annually, the system may allow illegal wage settings. <br><br>**Recommendation**: Define a `minimum_wage` master table or configuration service that is updated annually by an admin. The validation logic must query this service based on the store's `prefectureCode`. |
| F-012 | Transactional Isolation: Payroll Calculation | P1 | WARN | **REQ-LABOR-004**<br>Code: `@Transactional` implied | **Missing Isolation Level Specification**: The spec mentions `@Transactional` but does not specify the isolation level. <br><br>**Risk**: Default isolation levels (e.g., `READ_COMMITTED` in PostgreSQL/MySQL) may allow "dirty reads" or "non-repeatable reads" if a clock-in is modified during payroll calculation. <br><br>**Recommendation**: Specify `Isolation.READ_COMMITTED` or `REPEATABLE_READ` for the payroll calculation transaction. Ensure that the clock-in/out data is locked or snapshotted at the start of the calculation to prevent mid-calculation changes. |
| F-013 | Boundary Validation: Negative Hours | P2 | WARN | **REQ-LABOR-001**<br>Code: `clockOutAt` < `clockInAt` handling | **Missing Negative Time Handling**: The spec does not explicitly state how to handle `clockOutAt` earlier than `clockInAt` (e.g., data entry error or overnight shift misinterpretation). <br><br>**Recommendation**: Add a validation rule: If `clockOutAt` is before `clockInAt`, treat it as an overnight shift (add 24h) OR reject with `IllegalArgumentException` if the difference exceeds 24h. Explicitly define the maximum allowed shift duration (e.g., 24h). |
| F-014 | Code Quality: Linter Compliance | Info | PASS | **All REQs**<br>Code: "C# Linter rules 100% compliance" | **Note**: The spec mentions "C# Linter rules" despite the context being Spring Boot (Java). This is likely a copy-paste error from a previous project template. <br><br>**Recommendation**: Correct the language reference to "Java/Spring Boot Linter rules (e.g., Checkstyle, SpotBugs)" to avoid confusion during the audit. |

---

## 4. [Step 2] OpenAI Codex CLI 技術交差検証レポート
| ID | 分類 | 重要度 | 指摘 | 推奨対応 |
|---|---|---:|---|---|
| F-01 | 技術スタック整合性 | High | DoDに「C#リンター」とある一方、要件本文は Spring Boot、JUnit 5、`SecurityContextHolder`、`PessimisticLockException` を前提としており、実装言語・検証基盤が矛盾しています。 | Java/Spring Bootを正とするなら Checkstyle/Spotless/PMD・JUnit 5へ統一し、C#リンター記載を削除してください。 |
| F-02 | `store` DDL | High | `owner_id` のFK、`invite_code`・`qr_token` の一意制約、`pay_cutoff_day` のCHECK制約は必要ですが、DDLとしてのNULL制約・命名・インデックス要件が未定義です。 | `owner_id NOT NULL REFERENCES member(member_id)`、`UNIQUE(invite_code)`、`UNIQUE(qr_token)`、`CHECK (pay_cutoff_day BETWEEN 1 AND 28 OR pay_cutoff_day = 99)` を明記してください。 |
| F-03 | 招待コード | Medium | 8桁英数字は総当たり耐性が十分ではなく、照会APIが無制限なら店舗参加への不正試行に使われます。 | 招待申請APIにレート制限・監査ログ・失敗回数制限を追加し、失効日時・再発行・無効化状態を持たせてください。可能なら十分なエントロピーへ拡張してください。 |
| F-04 | 会員DTO契約 | Critical | 「`role` を完全禁止」としつつ、偽造されたJSONプロパティをどう扱うか未定義です。JSONデシリアライザが未知プロパティを許容すると攻撃試行の検知もできません。 | 一般登録DTOには `role` を定義せず、未知フィールド拒否をAPI共通方針として明記してください。レスポンスのみ `assignedRole` を返してください。 |
| F-05 | パスワード仕様 | High | 「英数記号混在」の具体的な正規表現・最大長・Unicode正規化・漏えい済みパスワード対策がありません。 | 最小8文字に加え最大長、許容文字、Unicode方針、BCryptコスト値（10以上、運用標準値）を固定してください。平文をログ・例外・監査イベントへ出力しない要件も追加してください。 |
| F-06 | メール一意性 | High | 小文字化だけではUnicodeメールやDB照合順序によって重複を防げない場合があります。 | 正規化済み専用列 `email_normalized` を `NOT NULL UNIQUE` とし、アプリ・DB双方で同一の正規化方針を採用してください。 |
| F-07 | 所属状態遷移 | High | `RESIGNED → ACTIVE` を禁止する一方、`uq_store_member` が存在すると同じ店舗への再雇用用レコードを作れません。 | 一意制約を「現役・申請中のみ一意」にする部分ユニークインデックス、または `employment_instance_no` を含む複合一意制約に変更してください。 |
| F-08 | 所属申請DTO | High | スタッフ申請で賃金入力を禁止しているものの、DTOの未知フィールド拒否、所有者承認DTOとの分離が明記されていません。 | `JoinStoreRequest(inviteCode)` と `ApproveStoreStaffRequest(hourlyWage, dailyTransportFee, monthlyTransportLimit)` を別DTOにし、前者に給与関連フィールドを置かないでください。 |
| F-09 | 最低賃金 | High | 時給が最低賃金未満の場合の検証を求めていますが、最低賃金マスタ、適用基準日、都道府県変更時の判定根拠がありません。 | `minimum_wage_history(prefecture_code, effective_from, effective_to, hourly_wage)` を定義し、契約開始日の有効レコードで検証してください。 |
| F-10 | 契約履歴期間制約 | Critical | `effective_to IS NULL` の現行契約だけを対象にする仕様では、将来日付の予約契約を複数作成した際の重複・逆転を防げません。 | 有効期間を半開区間 `[effective_from, effective_to)` と定義し、全履歴との重複禁止をDB制約で保証してください。PostgreSQLなら daterange exclusion constraint、他DBならトリガーまたは直列化ロックを明記してください。 |
| F-11 | 悲観的ロック境界 | Critical | 契約更新の `store_staff` 行ロックだけでは、初回契約作成・異なる更新経路・DB分離レベル次第で履歴競合を完全には防げません。 | 対象 `store_staff` のロック取得から、既存履歴読取・終了日更新・新規履歴挿入・コミットまでを単一トランザクション境界として定義してください。ロック取得順序も固定してください。 |
| F-12 | 打刻・給与の認可 | High | 「店舗所属権限を照合」とあるのみで、各APIの対象リソースと認可判定の対応が未定義です。IDOR防止を実装可能な契約に落とせていません。 | `storeId`、`storeStaffId`、勤務レコード、給与明細ごとに、所有者・本人・退職者の許可操作を認可マトリクスとして定義してください。 |
| F-13 | 打刻QRトークン | High | QRトークンの漏えい・複製・ローテーション・失効・保存形式が未定義です。 | トークンは平文保存せずハッシュ保存し、ローテーション時刻、旧トークン失効、利用監査、店舗内打刻以外の本人認証要件を定義してください。 |
| F-14 | 労働時間の分割 | Critical | 日跨ぎ勤務に対し、「1日8時間」の日次境界が未定義です。開始日基準で全時間を集計すると、暦日別残業計算と不整合になります。 | 勤務・休憩区間を店舗タイムゾーンの暦日で分割し、日ごとに実労働・残業・深夜・重畳時間を算定する仕様にしてください。 |
| F-15 | 休憩区間の妥当性 | High | 休憩が勤務時間外、重複、逆順、重複入力の場合の扱いが未定義で、控除時間の二重計上が起こり得ます。 | 休憩区間を勤務区間内に制限し、開始＜終了、相互非重複を検証してください。重複を正規化するのか400で拒否するのかも固定してください。 |
| F-16 | 給与丸め | High | 日次の `Math.floor` と月次の `HALF_UP` が併記され、どの金額をどの粒度で丸めるか不明です。日次切捨てと月次丸めでは結果が変わります。 | 基本給・残業割増・深夜割増の算定単位、日次明細への丸め、月次合算後の最終丸めを一意に定義し、`BigDecimal` と明示的な `RoundingMode` を必須化してください。 |
| F-17 | 最低賃金フォールバック | High | 時給0以下を最低賃金へフォールバックする要件は、契約・入力異常を隠し、賃金額を暗黙に変更します。 | 契約登録時は0以下を必ず400で拒否してください。既存データ異常時のみ、監査イベントを残した上で明示的な例外処理または再計算停止方針を定義してください。 |
| F-18 | 割増計算の証跡 | Medium | 再計算可能性・監査可能性のための、算定時点の時給、契約履歴ID、深夜・残業分数、丸め結果のスナップショットが未定義です。 | 給与明細に計算入力・適用契約ID・適用最低賃金版・各手当・丸め方式を不変スナップショットとして保存してください。 |
| F-19 | 給与確定ロック | Critical | 「該当月レコードを `SELECT ... FOR UPDATE`」では、精算レコード未作成時に同時確定が通る可能性があります。また対象となる打刻・契約履歴の更新阻止範囲も不明です。 | `(store_id, target_month)` の一意制約を置き、先に精算ヘッダを原子的に作成・取得してロックしてください。ロック中の打刻修正・契約修正を拒否する対象期間と状態遷移を明示してください。 |
| F-20 | 給与状態遷移 | High | `LOCKED → CONFIRMED` のみでは、失敗・再試行・取消・確定済み再実行への応答が曖昧です。 | `OPEN → PROCESSING/LOCKED → CONFIRMED` を基本とし、障害時の復旧状態、冪等キー、確定済み要求への409等のAPI契約を定義してください。 |
| F-21 | ロックタイムアウト | Medium | 3秒タイムアウトの設定箇所、DB方言、HTTP変換、リトライ可否が未定義です。 | DB/ORMのロックタイムアウト設定、`PessimisticLockException` のHTTP 409または503へのマッピング、クライアントの安全な再試行規則を定義してください。 |
| F-22 | 並行性テスト | High | 「2件中1件のみ成功」だけでは、待機後の二重実行、未作成ヘッダ、ロールバック後のロック解放を検証できません。 | バリア同期を用いた統合試験で、同月二重確定・異月並列確定・ロールバック・ロックタイムアウト・確定後打刻修正拒否を検証してください。 |

監査結論: **要修正（FAIL）** です。特に F-04、F-07、F-10、F-11、F-14、F-19 は、実装前にDTO・DDL・トランザクション境界として確定する必要があります。

---

## 5. [Step 3] Anthropic Claude Sonnet 5.5 法規深層検証レポート
# 監査報告書: KINTAI SRS v1.0.2 (労基法第37条・端数処理・不変性)

## 0. 総合判定

**判定: 不承認 (REJECT, 要改訂 v1.1)**

| 区分 | 件数 | 内容 |
|---|---|---|
| Critical | 8 | 法的に誤った支給額が出る、または不変性が破れる欠陥 |
| High | 9 | 仕様矛盾、未定義の境界、監査不能 |
| Medium / Low | 9 | 運用・セキュリティ補完事項 |

「1円の誤差もなく決定論的に算定」(§1) という中核主張は、現行仕様では**成立しません**。主な理由は次の4点です。
- 端数処理規則が矛盾している。
- 法定の割増類型が欠落している。
- 「1日」の定義がない。
- 確定済み給与の不変性が強制されていない。

---

## 1. 労基法第37条・関連法令の適合性

| ID | 重大度 | 対象 | 指摘 | 影響 | 是正案 |
|---|---|---|---|---|---|
| L-01 | **Critical** | LABOR-001 | 時間外を「日8時間超」のみで定義している。**週40時間超**(法32条1項)の時間外が欠落している。小規模の商業・接客娯楽業の週44時間特例の扱いも未定義。 | 週5日超の勤務や日8時間以下の長時間週で、割増未払い(37条違反)が発生する。 | 日次と週次の2段階判定を導入し、重複計上を排除する(厚労省通達の控除順序に従う)。週の起算曜日を店舗設定とし、特例適用フラグを持たせる。 |
| L-02 | **Critical** | 全体 | **月60時間超の時間外は割増率50%**(37条1項但書)。2023年4月から中小企業にも適用されているが、仕様に存在しない。 | 長時間勤務者の賃金が恒常的に過少になる。 | 月間累積の時間外時間に応じて25%と50%を切り替える。深夜と重なる場合は75%になる。代替休暇制度は対象外と明記する。 |
| L-03 | **Critical** | 全体 | **法定休日労働(35%)** が未定義。法定休日の特定(法35条)、休日と深夜の重複(60%)、休日労働と時間外の非重畳(休日労働には時間外を適用しない)が欠落している。 | 休日出勤が通常労働として計算される。 | `day_type`(平日、法定外休日、法定休日)を導入し、割増の優先順位マトリクスを仕様化する。 |
| L-04 | **Critical** | LABOR-002 | 深夜帯を「当日22:00〜翌日05:00」と定義している。**同一暦日の00:00〜05:00**(前日起算ではない早朝勤務)がカバーされない。例: 02:00〜10:00の勤務。 | 早朝勤務の深夜割増が0円になる。 | 深夜帯を暦日ごとの2区間 `[00:00,05:00)` と `[22:00,24:00)` で定義する。または連続勤務を勤務日起算で正規化するルールを明記する。 |
| L-05 | **Critical** | LABOR-001/002/003 | 「**1日**」の定義がない。労基法上は原則として暦日だが、継続勤務が暦日をまたぐ場合は始業日の勤務として扱う(昭和63.1.1基発1号)。仕様は日付境界の扱いを深夜判定にしか書いていない。 | 日跨ぎシフトで8時間の判定がずれ、残業が二重計上されるか欠落する。 | 「勤務日=始業時刻の属する暦日、継続勤務は同一勤務日」と定義する。日跨ぎ時の契約時給の適用日、週・月の帰属日もこれに従う。 |
| L-06 | **High** | STAFF-001, LABOR-001 | **労働時間の通算(法38条)** が未定義。多店舗勤務で、同一事業主の複数店舗は通算される。事業主が異なる場合も副業・兼業の通算ルールがある。計算が store スコープのみになっている。 | 同一オーナーの複数店舗を掛け持つスタッフで、8時間超や週40時間超の割増が漏れる。 | `owner_id` 単位で通算する設計にする。異事業主の通算は、スコープ外であれば明示的に除外宣言する。 |
| L-07 | **High** | 全体 | **休憩(法34条)** の検証がない。6時間超で45分、8時間超で60分の付与義務、休憩の一斉付与、休憩重複区間のマージ、打刻区間外の休憩の扱いが未定義。「有効休憩時間」(LABOR-001)の定義も存在しない。 | 休憩が不足していても無警告で処理される。重複した休憩を二重控除して賃金が過少になる。 | 休憩区間は正規化(クリップ・マージ)し、法定休憩不足時は警告または未払い休憩扱いとして記録する。 |
| L-08 | **High** | 全体 | **36協定の上限**(月45時間、年360時間、特別条項の月100時間未満・複数月平均80時間)の監視がない。 | 使用者の法的リスクを検知できない。 | 閾値アラート(任意機能)を追加する。非対応なら明示的に範囲外とする。 |
| L-09 | **High** | STAFF-001/002 | **年少者(法61条、18歳未満の深夜禁止)** と**在留資格外活動(留学生は週28時間上限)** の制約が未定義。飲食・小売では高頻度で該当する。 | 違法就労の検知が不能になる。 | 生年月日と就労上限属性を保持し、シフト・打刻時に警告する。 |
| L-10 | **Medium** | 全体 | 割増賃金の**算定基礎賃金の定義**がない。通勤手当は除外できる(施行規則21条)が、他の手当を扱う仕様がない。`totalDailyPay` に交通費が含まれるかも不明。 | 手当が追加された際に割増単価が誤る。 | 算定基礎=基本時給(+算入手当)、除外=通勤手当等、と明記する。交通費の月上限の適用箇所(日次か月次か)を定義する。 |

---

## 2. 端数処理・計算の決定性

| ID | 重大度 | 対象 | 指摘 | 影響 | 是正案 |
|---|---|---|---|---|---|
| R-01 | **Critical** | LABOR-001/002 vs 003 | **端数処理の矛盾**。001/002は日次・項目別に `Math.floor`(常に切捨て)としている。一方003は月次合算時に `HALF_UP` としている。どちらが最終値か不定で、floor済みの値にHALF_UPを適用しても意味がない。 | 実装者ごとに結果が分かれ、「完全一致」の完了基準を満たせない。 | 端数処理を単一の方針として章立てする。推奨は「分単位の整数で累積し、月次合計の割増賃金額に対して1回だけ50銭未満切捨て・以上切上げ」。 |
| R-02 | **Critical** | LABOR-001/002 | **常時切捨ては労働者に不利**。昭和63.3.14基発150号が認める便宜措置は、①1か月の時間外・休日・深夜の合計時間について30分未満切捨て・以上切上げ、②1円未満の50銭未満切捨て・以上切上げ、③1か月の賃金総額の100円未満端数の50円未満切捨て・以上切上げである。毎日・毎項目の常時切捨ては含まれない。 | 賃金全額払い原則(法24条)や37条の過少払いと評価され得る。例: 時給1,226円、残業25分の割増は127.708円。floorなら127円、HALF_UPなら128円で、1項目1日あたり最大0.99円が系統的に過少になる。 | 方針をR-01の通りに統一する。必要ならゴールデンテストを追加する。 |
| R-03 | **High** | LABOR-003 | 「基発第150号」の引用が不正確。同通達の対象は割増の端数処理の便宜措置であり、「日本通貨基準」ではない。**基本給(時給×実労働分)の丸め規則が未定義**。 | 基本給が最大の金額であるにもかかわらず、丸め規則が定義されていない。 | 基本給の算定式と丸めタイミングを明記する。通達の正式名称(昭和63年3月14日基

---





## 6. 総括および推奨事項 (Conclusion & Recommendations)
- 本レポートは、個別の手動操作を排し、**Hermes 統合コントローラーによる単一パイプライン下で決定論的リンター、Qwen 27B、Codex、Claude 5.5を統合実行**して生成された公式技術証跡です。