# Slice 4 給与精算・労働基準法第37条割増賃金計算エンジンおよび月次確定排他制御 要件定義書（As-Built Track 2）

## 適用範囲および検証状態

本書は、日本国労働基準法第37条および昭和63年3月14日付基発第150号（婦発第47号）行政通達に準拠した割増賃金算定、店舗締日に基づく月次給与集計、日別給与詳細スナップショット永続化、2段階階層的悲観的ロック（`store_staff` → `payroll`）と Double-Checked Lock による確定トランザクション、給与確定後の不変性保護（Immutability Guard）、および `payroll` / `payroll_daily_detail` テーブルの物理定義を対象とします。

本書の実装記述は、提示されたソースコード（`PayrollService.java`、`PayrollCalculator.java`、`LaborCalculationService.java`、`PayrollApiController.java`）および DDL（`schema.sql`）に基づきます。根拠はファイル名とシンボル名で示します。

## 共通境界条件

- **認証・店舗境界**: 店舗管理者またはオーナーによる給与確定・支払操作では、認証済み `SecurityContext` から操作権限（`StoreAuthorizationService`）を検証し、認可されないアクセスは拒否します。
- **入力境界**: 年月文字列は `YYYY-MM` 形式（`YearMonth.parse`）で検証し、不正形式は `IllegalArgumentException`（HTTP 400）を送出します。
- **HTTP境界**: パラメータ不正は HTTP 400、未認証は HTTP 401、他店舗アクセスおよび権限不足は HTTP 403、対象給与不存在は HTTP 404、確定済み再計算および状態不整合は HTTP 409、未処理勤怠残存および締期間未終了時の早期確定は HTTP 422 を返却します。
- **排他・トランザクション境界**: 全体のロック順序の照合基準は `member → store → store_staff → contract_history → attendance → payroll` です。給与確定処理における排他制御は `PayrollService.java / confirmPayroll` において `payrollMapper.lockStoreStaffForUpdate(staffId)`（Level 1）獲得後に `payrollMapper.findByIdForUpdate(payrollId)`（Level 2）を獲得する2段階階層ロックを厳格に適用します。

#### [REQ-OBS-PAYROLL-001] 労働基準法第37条に基づく4区分支給額詳細算定および端数処理

- **入力**: 勤怠実績の日次実労働分数（`netWorkMinutes`）、深夜労働分数（`nightMinutes`）、時間外残業分数（`overtimeMinutes`）、勤務日時点の適用契約時給（未設定時は最低賃金 `minHourlyWage` = 1280円）、および月間総時間外・総深夜・総休日労働分数を対象とします。
- **処理**: `PayrollCalculator.calculateDetailedDailyPay` は実労働を所定内通常（100%）、所定内深夜（125%）、法定外通常残業（125%）、法定外深夜残業（150%重畳割増）の4区分に完全分解して日別支給額を算出します。日次計算において労働者に不利な端数処理（分単位切捨て等）は行いません。契約時給未設定時は設定値 `minHourlyWage`（デフォルト1,280円、地域別最低賃金マスタ連動）を適用します。月次集計時には行政通達（昭63.3.14基発第150号）に準拠した `PayrollService.applyStatutoryMonthlyRounding` を適用します。月間総時間外分数・総深夜分数について各々30分未満を切捨て、30分以上を1時間に切り上げます。1時間あたりの割増賃金額（時給 × 0.25）および手当別月間支給総額について、各々50銭未満を切捨て、50銭以上1円未満を1円に切り上げる四捨五入（`RoundingMode.HALF_UP`）を適用します。日別明細（`payroll_daily_detail`）の実分数積算と月次法定丸め手当額との端数調整差分は月次サマリ側で決定論的に集約・整合管理されます。
- **出力**: 日別4区分金額（`regularPay`, `regularNightPay`, `overtimePay`, `nightOvertimePay`）、基本給相当（`basePay`）、深夜手当（`nightAllowance`）、時間外手当（`overtimeAllowance`）、および法定端数処理後の月間手当額を `StatutoryPayrollResult` および `PayrollDto` として出力します。
- **例外処理**: 無効な勤務時間または負の労働時間は `InvalidWorkTimeException` を送出します。給与データが null の場合は `IllegalArgumentException`（HTTP 400）を送出します。
- **完了基準 (DoD)**: `LaborCalculationEngineTest.java` および `StatutoryRoundingTest.java` において、日8時間超過（125%）、深夜22:00〜翌05:00（125%）、深夜時間外重畳（150%）の正確性を検証します。月間29分が0時間、30分が1時間に切り上げられること、49銭が切捨て、50銭が1円に切り上げられる法定端数処理の完全一致を確認します。

#### [REQ-OBS-PAYROLL-002] 月次給与一括集計・差分計算および日別詳細スナップショット永続化

- **入力**: 店舗ID（`storeId`）、対象年月（`targetYearMonth`）、店舗設定締日（`payCutoffDay`: 1〜28または99=末日締）、および対象期間内の確定済み勤怠リストを対象とします。
- **処理**: `PayrollService.calculateMonthlyPayroll` は `PayrollCalculator.resolveDateRange` により集計開始日と終了日を決定論的に解決します。対象スタッフごとに `payrollMapper.lockStoreStaffForUpdate(staffId)` で悲観的ロックを獲得し、確定済み給与の有無を検証します。`countUnresolvedAttendance` により未退勤打刻（勤務中）または未承認修正申請が存在するか確認し、未処理勤怠が存在する場合は給与計算を即時中断します。なお、退職者や打刻忘れ等に伴う未退勤打刻の強制退勤処理（Force Close API: `AttendanceService.forceCloseAttendance`）および、`payroll` テーブル Upsert 時の確定済み行上書き防止ガード（`payroll_status = 'DRAFT'` 条件）は現行実装には未導入であり、Phase 3 リファクタリング適用予定として設計・管理されます。現行実装では完了勤怠に基づき日別給与と交通費（`appliedTransportLimit`、月額上限15,000円）を算定し、`payroll` テーブルに `DRAFT` 状態で Upsert（`ON DUPLICATE KEY UPDATE`）します。既存の日別明細を削除した上で、全勤務日の計算結果を `payroll_daily_detail` にスナップショットとして挿入保存します。
- **出力**: 月次給与サマリレコード（`payroll`）および日別給与明細レコード群（`payroll_daily_detail`）が永続化されます。
- **例外処理**: 対象年月のフォーマット不正は `IllegalArgumentException`（HTTP 400）、確定済み給与（`CONFIRMED`, `PAID`）に対する再計算試行は `IllegalStateException`（HTTP 409）、未退勤・未承認勤怠の残存は `IllegalStateException`（HTTP 422）を送出します。
- **完了基準 (DoD)**: 締日（20日締、末日締等）に応じた集計期間境界がうるう年を含め正確に解決されることを確認します。同一入力に対する再計算で重複レコードが発生せず冪等性が維持されること、未処理勤怠が存在する場合に計算が安全に中断されること、および交通費上限が月間合計に対して正しく適用されることを検証します。

#### [REQ-OBS-PAYROLL-003] 2段階階層的悲観的ロックおよびDouble-Checked Lockによる給与確定トランザクション

- **入力**: 給与ID（`payrollId`）、確定要求DTO（`PayrollConfirmRequestDto`）、および認証済み店舗管理者情報を対象とします。
- **処理**: `PayrollService.confirmPayroll` はデッドロックおよびレースコンディションを防止するため多重防衛線を適用します。第一に、非ロック初期照会（`findById`）により対象の `storeStaffId` および `storeId` を特定します。第二に、グローバルロック階層に従い `store_staff` 親行の排他的ロック（`lockStoreStaffForUpdate`、Level 1）を獲得します。第三に、`payroll` 子行の排他的ロック（`findByIdForUpdate`、Level 2）を獲得します。第四に、ロック後再照会結果と初期照会結果の所属IDが完全一致するか検証（Double-Checked Lock による TOCTOU 防御）します。第五に、現在の状態が `DRAFT` であること、清算対象期間終了日の翌日暦日以降（`LocalDate.now().isAfter(rangeEndDate)`）であること、および未処理勤怠件数が0件であることを確認します。第六に、同一トランザクション内で最新勤怠に基づき給与を再計算し、状態を `CONFIRMED`、`confirmed_at` を現在時刻に更新します。
- **出力**: 状態が `CONFIRMED` に更新された給与レコードが永続化されます。
- **例外処理**: 存在しない給与IDは `IllegalArgumentException`（HTTP 404）、初期照会とロック後照会での所属不一致は `IllegalStateException`（HTTP 409）、既に確定済みの給与に対する確定試行は `IllegalStateException`（HTTP 409）、期間終了前の早期確定および未処理勤怠残存は `IllegalStateException`（HTTP 422）を送出します。
- **完了基準 (DoD)**: 同一給与に対する並行確定リクエストにおいて厳格に1件のみが成功し二重確定が排除されることを確認します。締期間終了日以前の確定リクエストが確実に遮断されること、未承認勤怠が存在する場合に確定が阻止されること、およびロック取得順序が `store_staff → payroll` の階層を遵守することを検証します。

#### [REQ-OBS-PAYROLL-004] 給与確定不変性保護および支払処理ステータス制御

- **入力**: 給与ID（`payrollId`）、支払処理日時、および認証済み店舗管理者情報を対象とします。
- **処理**: `PayrollService.payPayroll` は、デッドロック防止のため `store_staff` 親行の排他的ロック（Level 1）を獲得した上で対象給与の排他的ロック（Level 2）を獲得し、状態が `CONFIRMED` であることを検証します。状態を `PAID` に更新し、`paid_at` に支払完了日時を記録します。確定（`CONFIRMED`）または支払済み（`PAID`）の給与に対しては、いかなる再計算処理（`calculatePayrollForStaff`）および勤怠修正申請（`AttendanceService.requestModification`）も物理的に遮断（給与不変性保護）します。確定後に勤怠の誤りが判明した場合は、当月給与を改変せず、翌月調整伝票（`payroll_adjustment`）にて差額調整を行います。
- **出力**: 状態が `PAID`、`paid_at` が設定された給与レコードが永続化されます。
- **例外処理**: 対象が存在しない場合は `IllegalArgumentException`（HTTP 404）、`DRAFT` 状態からの直接支払試行および既に `PAID` であるレコードへの重複支払は `IllegalStateException`（HTTP 409）、確定済み給与の再計算試行は `IllegalStateException`（HTTP 409）を送出します。
- **完了基準 (DoD)**: `CONFIRMED → PAID` の正当な遷移のみが成功し、草稿からの直接支払や二重支払が遮断されることを確認します。確定状態の給与が存在する日付の勤怠修正申請が `AttendanceService` において確実に拒否されること、および日別詳細スナップショットが改変されないことを検証します。

#### [DDL-001] payroll テーブル物理定義

- **入力**: 根拠は `domain_target/02_database_schema_ssot/schema.sql / payroll` です。対象列は `payroll_id`, `store_id`, `store_staff_id`, `target_year_month`, `range_start_date`, `range_end_date`, `work_days_count`, `total_work_minutes`, `total_night_minutes`, `total_overtime_minutes`, `applied_hourly_wage`, `applied_transport_limit`, `base_pay`, `night_allowance`, `overtime_allowance`, `transport_allowance`, `gross_pay`, `payroll_status`, `confirmed_at`, `paid_at`, `created_at`, `updated_at` の全22列です。
- **処理**: `store_staff_id` と `target_year_month` に対する複合一意制約 `uq_payroll_staff_month` により同一スタッフ・同一月の重複給与作成を物理排除します。`fk_payroll_store` および `fk_payroll_staff_store` により所属整合性を保証します。`chk_payroll_range` により `range_end_date >= range_start_date` を強制し、`chk_payroll_status` により許容状態を `'DRAFT'`, `'CONFIRMED'`, `'PAID'` に制限します。
- **出力**: 店舗・スタッフ・年月ごとの確定給与、支給内訳、時間集計およびステータスを永続化します。
- **例外処理**: 同一スタッフ・同月の重複登録は一意制約違反（ER_DUP_ENTRY / 1062）、期間逆転および許容外ステータス値は CHECK 制約違反（HTTP 400/409）としてDBレベルで遮断します。
- **完了基準 (DoD)**: 全22列の物理型、制約名、デフォルト値がDDLと完全一致することを確認します。同一スタッフ・同月の二重登録が拒否されること、期間逆転レコードが拒否されること、および3状態以外のステータス値が遮断されることを検証します。

#### [DDL-002] payroll_daily_detail テーブル物理定義

- **入力**: 根拠は `domain_target/02_database_schema_ssot/schema.sql / payroll_daily_detail` です。対象列は `payroll_daily_detail_id`, `payroll_id`, `attendance_id`, `work_date`, `applied_hourly_wage`, `total_break_minutes`, `net_work_minutes`, `night_work_minutes`, `overtime_minutes`, `base_pay`, `night_allowance`, `overtime_allowance`, `transport_amount`, `created_at` の全14列です。
- **処理**: `fk_payroll_detail_payroll` により親 `payroll` を参照し、`fk_payroll_detail_attendance` により元勤怠 `attendance` を参照します。`uq_payroll_detail_attendance (payroll_id, attendance_id)` により同一給与内での同一勤怠の二重計上を物理排除します。`idx_payroll_detail_date (payroll_id, work_date)` により日付検索を高速化します。
- **出力**: 確定給与の内訳根拠となる勤務日別の労働時間・支給額スナップショットを不変証跡として保持します。
- **例外処理**: 親給与または勤怠が存在しない外部キー不整合、同一給与内での同一勤怠の重複登録はDB制約違反として遮断します。
- **完了基準 (DoD)**: 全14列の物理定義、外部キー、一意制約、インデックスがDDLと一致することを確認します。同一給与に対する同一勤怠IDの複数回登録が確実に拒否されることを検証します。

## 賃金計算および端数処理通達基準

労働基準法第37条および基発第150号に定める算定・端数処理条件は以下の通りです。

| 区分 | 法定算定基準および端数処理 |
|---|---|
| **所定内通常労働 (100%)** | 実労働時間のうち1日8時間以内の通常時間帯労働に対し、契約時給の100%を支給。 |
| **所定内深夜労働 (125%)** | 実労働時間のうち1日8時間以内の22:00〜翌05:00労働に対し、基本100% + 深夜割増25% = 125%を支給。 |
| **法定外通常残業 (125%)** | 1日8時間を超える通常時間帯労働に対し、基本100% + 時間外割増25% = 125%を支給。 |
| **法定外深夜残業 (150%)** | 1日8時間を超え、かつ22:00〜翌05:00に重複する労働に対し、基本100% + 時間外25% + 深夜25% = 150%（重畳割増）を支給。 |
| **月間割増時間端数処理** | 時間外労働・深夜労働それぞれの月間総時間数において、30分未満を切捨て、30分以上を1時間に切り上げ（基発第150号第1の4(1)）。 |
| **割増賃金額端数処理** | 1時間あたりの割増賃金額および月間手当別支給額において、50銭未満を切捨て、50銭以上1円未満を1円に切り上げ（基発第150号第1の4(2)(3)）。 |
