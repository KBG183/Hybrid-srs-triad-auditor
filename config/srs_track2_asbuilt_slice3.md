# Slice 3 勤怠管理・リアルタイム打刻および打刻修正ワークフロー 要件定義書（As-Built Track 2）

## 適用範囲および検証状態

本書は、スタッフによる出退勤打刻（出勤・休憩開始・休憩終了・退勤）、日次実労働・深夜・時間外労働時間の算定、分割勤務（中抜け勤務）における日次通算処理、打刻修正申請・店長承認フロー、および `attendance` / `attendance_break` テーブルの永続化を対象とします。

本書の実装記述は、提示されたソースコード（`AttendanceService.java`、`AttendanceTimeCalculator.java`）および DDL（`schema.sql`）に基づきます。根拠はファイル名とシンボル名で示します。

## 共通境界条件

- **認証・店舗境界**: スタッフ操作では認証済み `SecurityContext` から本人の所属を解決し、店長操作では同コンテキストから操作可能な店舗を解決することを境界要件とします。打刻 DTO で店舗 ID が省略された場合は、マスタ上の所属店舗 ID を自動補完します。
- **入力境界**: ISO形式の日時文字列を受け取る境界では `DateTimeParseException` を処理します。労働時間が負またはゼロの場合は `InvalidWorkTimeException` を送出します。
- **HTTP境界**: 日時形式不正および必須パラメータ欠落は HTTP 400、未認証は HTTP 401、店舗境界外アクセスおよび権限不足は HTTP 403、対象レコード不存在は HTTP 404、状態遷移不正および更新競合は HTTP 409、業務条件違反は HTTP 422 を返却します。
- **排他・トランザクション境界**: 全体のロック順序の照合基準は `member → store → store_staff → contract_history → attendance` です。本スライスにおける排他制御の獲得点は `AttendanceService.java / punch → attendanceMapper.lockStoreStaffForUpdate(storeStaffId)` です。

#### [REQ-OBS-ATTEND-001] リアルタイム出退勤打刻および悲観的ロック排他制御

- **入力**: 認証済みスタッフの店舗ID、店舗スタッフID（`storeStaffId`）、打刻種別（`punchType`: `CLOCK_IN`, `CLOCK_OUT`）、打刻日時（システム現在日時 `now`）を対象とします。
- **処理**: `domain_target/03_core_domain_services/AttendanceService.java / punch` は、パラメータ検証後、`attendanceMapper.lockStoreStaffForUpdate(storeStaffId)` により対象スタッフの所属行を悲観的にロックします。`findActiveAttendance` によりアクティブな勤怠レコードを検索し、出勤（`CLOCK_IN`）時は既存アクティブ勤怠の不在および該当日の給与確定状態（`isPayrollConfirmedForDate`）を検証します。給与が確定前（確定状態フラグが未セットの状態）である場合、店舗IDを補完した上で状態を `WORKING`、打刻方式を `BUTTON` として新規勤怠行を登録します。退勤（`CLOCK_OUT`）時は状態が `WORKING` であることを確認し、実労働・深夜・残業時間を算定して状態を `COMPLETED` に更新します。
- **出力**: 登録または更新された勤怠レコード（`AttendanceDto`）を返却し、出退勤時刻、拘束時間、休憩時間、実労働時間、深夜時間、残業時間および最終ステータスが `attendance` に永続化されます。
- **例外処理**: 二重出勤、勤務中以外の退勤、休憩中の直接退勤、給与確定済み勤務日への新規打刻は即座に拒否（`IllegalStateException` / HTTP 409または422）します。無効なスタッフIDや未知の打刻種別は `IllegalArgumentException`（HTTP 400）を送出します。
- **完了基準 (DoD)**: `AttendanceServiceConcurrencyIntegrationTest.java` において同一スタッフによる同時出勤リクエストを並行実行し、重複なく厳格に1件の勤務レコードのみが生成されることを確認します。給与確定済み日に対する出勤打刻が遮断されること、および店舗ID未指定時に所属マスタから補完されることを検証します。

#### [REQ-OBS-ATTEND-002] 休憩開始・終了トランザクションおよび状態遷移機械制約

- **入力**: 認証済みスタッフの勤怠ID、打刻種別（`BREAK_START`, `BREAK_END`）、および打刻日時を対象とします。
- **処理**: `domain_target/03_core_domain_services/AttendanceService.java / handleBreakStart` は、アクティブ勤怠の状態が `WORKING` であることを検証し、`break_start_at` を設定して状態を `ON_BREAK` に更新します。`handleBreakEnd` は状態が `ON_BREAK` であることを検証し、直近の `break_start_at` との差分から休憩分数（`duration`）を計算して `attendance_break` テーブルに新規区間行を挿入します。同時に親勤怠の `total_break_minutes` に加算し、状態を `WORKING` に復帰させます。スタッフが休憩中に店舗を離脱して復帰しない場合（未終了放置デッドロック防止）、店長による強制退勤処理または事後修正申請により `ON_BREAK` を終了させて `COMPLETED` に収束させます。
- **出力**: 休憩区間レコード（`attendance_break`）が永続化され、親勤怠レコードの状態が更新されます。
- **例外処理**: 勤務中以外からの休憩開始、休憩中以外からの休憩終了、および休憩未終了状態での直接退勤打刻は拒否（`IllegalStateException` / HTTP 409）します。休憩区間の開始・終了時刻逆転はDBの CHECK 制約（`chk_break_range`）により遮断されます。
- **完了基準 (DoD)**: `WORKING → ON_BREAK → WORKING` の順序正しい状態遷移のみが成功し、二重休憩開始や未休憩時の休憩終了が確実に失敗することを確認します。1回の勤務内で複数回の休憩を取得した場合、`attendance_break` に全区間が記録され、親勤怠の `total_break_minutes` に合計分数が正しく反映されることを検証します。

#### [REQ-OBS-ATTEND-003] 実労働・深夜・残業時間精密算定および分割勤務累計連動

- **入力**: 勤怠レコードの出勤時刻、退勤時刻、全休憩区間リスト、および `attendanceMapper.sumPriorNetWorkSecondsOnDate` により取得された同一スタッフ・同日の先行完了実労働秒数を対象とします。
- **処理**: `domain_target/03_core_domain_services/AttendanceTimeCalculator.java / calculate` は、総拘束時間から休憩区間の和集合を控除して実労働時間を秒精度で算出します。深夜時間帯（22:00:00〜翌05:00:00）との積集合から深夜労働時間を秒精度で算出し分単位に変換します。日跨ぎ夜勤時は始業日基準（昭63.1.1基発1号）を適用し、翌日暦日にまたがる勤務も出勤日の1勤務として一括通算し、翌日05:00までの深夜窓と決定論的に積集合結合します。日次法定労働時間（8時間＝28,800秒）の超過判定において、先行完了実労働秒数（`P`）と今回実労働秒数（`C`）を合算し、今回に帰属する法定外残業秒数を `max(0, P + C - 28800) - max(0, P - 28800)` に基づき決定論的に算出します。同日内の先行勤務が事後修正された場合は、後続の完了勤務の残業時間を連鎖的に再計算（Cascading Recalculation）して日次整合性を維持します。
- **出力**: 分単位に変換された実労働時間（`net_work_minutes`）、合計休憩時間（`total_break_minutes`）、深夜時間（`night_work_minutes`）、残業時間（`overtime_minutes`）を返却します。
- **例外処理**: 実労働時間がゼロまたは負となる場合は `InvalidWorkTimeException` を送出します。休憩区間の重複や勤務時間外への逸脱は計算前に正規化・検証されます。
- **完了基準 (DoD)**: 単一勤務で8時間（480分）ちょうどおよび超過時の残業計算を検証します。同一日に2回勤務する分割勤務（中抜け）において、1回目5時間・2回目4時間の場合に2回目の残業が1時間（60分）として正確に合算認識されることを確認します。22:00〜翌05:00の深夜帯における実労働が分単位で正しく計上されることを検証します。

#### [REQ-OBS-ATTEND-004] 打刻修正申請・店長承認ワークフローおよび給与確定ガード

- **入力**: スタッフによる修正申請（`storeStaffId`, `workDate`, `requestedClockInAt`, `requestedClockOutAt`, 申請理由 `reason`、申請休憩区間リスト）、および店長による承認操作（`requestId`, `storeManagerId`）を対象とします。
- **処理**: `domain_target/03_core_domain_services/AttendanceService.java / requestModification` は、悲観的ロックの下で対象日の給与確定状態を検証し、確定済みの場合は申請を遮断（給与締結後の事実誤認は翌月給与調整伝票にて補正）します。既存勤務との時間帯重複を `countOverlappingAttendances` で検査し、変更前後の不変スナップショットを `attendance_mod_request` および `attendance_mod_break`（`BEFORE` / `REQUESTED`）に完全保存して改ざん防止監査証跡を確保した上で状態を `SUBMITTED` とします。`approveModification` は店長権限および店舗IDを照合し、修正後の日時および休憩区間に基づき `AttendanceTimeCalculator` で再計算を実施した上で、対象 `attendance` レコードの実績値を上書き更新し、申請状態を `APPROVED` に遷移させます。
- **出力**: 承認された修正申請と、再計算・補正された勤怠実績レコードが更新されます。
- **例外処理**: 給与確定済み勤務日への修正申請は即時拒否（`IllegalStateException` / HTTP 422）します。重複勤務時間帯の申請、他店舗スタッフに対する無権限承認、存在しない申請への承認操作はすべて遮断します。
- **完了基準 (DoD)**: 修正申請の提出時点では勤怠実績テーブルが改変されず、店長承認トランザクション完了時に初めて実績値が再計算値で上書き更新されることを確認します。変更前スナップショットが `BEFORE` として保持されること、給与確定後の勤務日に対する申請が拒否されること、および承認時に深夜・残業時間が再算定されることを検証します。

#### [DDL-001] attendance テーブル物理定義

- **入力**: 根拠は `domain_target/02_database_schema_ssot/schema.sql / attendance` です。対象列は識別・所属の `attendance_id`, `store_id`, `store_staff_id`, `shift_id`、勤務日の `work_date`、打刻日時の `clock_in_at`, `clock_out_at`、進行中休憩の `break_start_at`, `break_end_at`、集計分数の `total_break_minutes`, `net_work_minutes`, `night_work_minutes`, `overtime_minutes`、打刻方式の `clock_in_method`、状態の `attendance_status`、作成・更新日時の `created_at`, `updated_at` の全18列です。
- **処理**: `fk_att_store` で店舗を参照し、`fk_att_staff_store` で `(store_staff_id, store_id)` の所属整合性を担保します。`fk_att_shift` で紐づく確定シフトを参照します。`chk_attendance_minutes` 制約により全分数項目の0以上を強制し、`chk_attendance_status` により `WORKING`, `ON_BREAK`, `COMPLETED`, `MOD_REQUESTED` の4状態のみを許容します。インデックスは `(store_id, work_date)` および `(store_staff_id, work_date)` を配備します。
- **出力**: 店舗およびスタッフごとの勤務実績、休憩合計、法定内外労働時間を秒から分へ変換した確定値として永続化します。
- **例外処理**: 存在しない店舗・スタッフの指定、無効なステータス値、負の労働・休憩分数は外部キーまたはCHECK制約違反としてDBレベルで遮断します。
- **完了基準 (DoD)**: DDL定義とDBメタデータにおいて全18列の型、制約名、インデックス構成が一致することを確認します。許容された4つの状態値が登録可能であり、未知のステータスや負の分数が確実に遮断されることを検証します。

#### [DDL-002] attendance_break テーブル物理定義

- **入力**: 根拠は `domain_target/02_database_schema_ssot/schema.sql / attendance_break` です。対象列は `attendance_break_id`, `attendance_id`, `break_start_at`, `break_end_at`, `duration_minutes`, `created_at` の全6列です。
- **処理**: `fk_att_break_att` により親テーブル `attendance` を参照し、`ON DELETE CASCADE` により親勤怠の削除に連動します。`chk_break_duration` により `duration_minutes > 0` を強制し、`chk_break_range` により `break_end_at > break_start_at` の区間整合性を強制します。
- **出力**: 勤務実績に紐づく1回ごとの正確な休憩開始・終了日時および分数を独立した区間レコードとして永続化します。
- **例外処理**: 0分以下の休憩時間、開始日時と終了日時の逆転または同一時刻、親勤怠レコードが存在しない外部キー不整合はDB制約により遮断します。
- **完了基準 (DoD)**: 休憩1分以上の正常な区間レコードが登録可能であり、0分休憩、負の分数、逆転日時の登録試行がCHECK制約により確実に拒否されることを検証します。

## 賃金計算との接続条件

労働基準法第37条に定める割増賃金算定との接続条件は以下の通りです。

| 判定対象 | 法定算定条件および端数処理基準 |
|---|---|
| **時間外労働 (1日8時間超)** | 1日8時間（480分）を超える実労働時間に対し、通常の労働時間の賃金計算額の2割5分（25%）以上の割増賃金を支給。 |
| **深夜労働 (22:00〜05:00)** | 午後10時から午前5時までの実労働時間に対し、2割5分（25%）以上の割増賃金を支給。 |
| **時間外かつ深夜の重複** | 時間外労働が深夜時間帯に行われた場合、双方の割増率を合算した5割（50%）以上の割増賃金を支給。 |
| **月次端数処理 (50銭基準)** | 1ヶ月の割増賃金総額に生じる1円未満の端数は、50銭未満を切り捨て、50銭以上1円未満を1円に切り上げる。 |
