# 📐 ソフトウェア要件定義書 (SRS SSOT)

- **システム名**: 日本型シフト・勤怠・給与精算システム (KINTAI)
- **文書バージョン**: v1.0.2
- **ステータス**: APPROVED_FOR_AUDIT
- **ドメイン分類**: 店舗・会員認可マスタ、打刻勤怠管理、および日本国労働基準法第37条割増賃金算定エンジン
- **多言語ガバナンス**: GitHub公式正本は日本語（JA）標準、内部開発・確認用に対照版（KO）を配置

---

## 0. 言語および対外成果物基準 (日本IT市場標準)
1. **GitHub対外公式正本**: すべての公式SRS仕様書、README.md、アーキテクチャ図、およびコミットメッセージは、日本のエンタープライズ技術評価基準（ビジネス日本語）に準拠して策定される。
2. **監査確認用対照版**: 開発者の直観的な検証および多角確認のため、主要ドキュメントごとに対照版（`_KO.md`）をローカルに常時ペアリング配置する。

---

## 1. システム概要およびドメイン目的
本システムは、日本の飲食・小売店舗における多店舗アルバイト勤務契約、出退勤打刻データ、シフト調整、ならびに日本国労働基準法第37条に規定された割増賃金（残業・深夜・重畳割増）を1円の誤差もなく決定論的に算定・監査する高信頼性バックエンド基盤である。

---

## 2. 要件トレーサビリティ・マトリクス (Traceability Matrix)

### 2.1 [Slice 1] 店舗・会員管理および権限統制 (Store & Member Management)

#### [REQ-STORE-001] 店舗マスター登録および招待コード・QRトークン管理
- **区分**: 機能要件およびセキュリティ (Function & Security)
- **概要**: 認証済み店舗オーナー（`ROLE_OWNER`）が店舗を新規開設し、スタッフ合流用の一意な招待コードおよび店舗固有QR打刻トークンを発行・管理する。
- **入力**:
  - `storeName` (店舗名, 100文字以内, 必須)
  - `prefectureCode` (都道府県コード, CHAR(2), 例: '13'=東京都)
  - `openTime` (開店時間, TIME, デフォルト '09:00:00')
  - `closeTime` (閉店時間, TIME, デフォルト '23:00:00')
  - `payCutoffDay` (給与締め日, 整数, `1 ~ 28` または `99`=末日締め)
  - *(注: `ownerId` はリクエストパラメータから一切受け取らず、`SecurityContext` の認証済みPrincipalよりサーバー側で自動解決する)*
- **処理**:
  1. 認証コンテキストのPrincipalが有効な `ROLE_OWNER` 権限を保持していることを検証する。
  2. 8桁のセキュアな英数字からなる一意な `invite_code` およびユニークな `qr_token`（UUID v4ベース）を生成する。
  3. `pay_cutoff_day` が `1 ~ 28` または `99` の許容範囲内であることをチェック制約（`chk_store_cutoff`）に適合させる。
  4. オーナーIDをFKとしてバインドし、店舗レコードを `store` テーブルに永続化する。
- **出力**:
  - `storeId` (生成された店舗PK, BIGINT)
  - `inviteCode` (発行された招待コード, VARCHAR(20))
  - `qrToken` (打刻用QRトークン, VARCHAR(100))
- **例外処理**:
  - 招待コードの一意性衝突が発生した場合、再生成リトライ（最大5回）を行い、一意性を担保する。
  - 締め日パラメータが不正な場合、`IllegalArgumentException`（HTTP 400）を送出する。
  - 未認証または `ROLE_OWNER` 以外の呼び出しは `AccessDeniedException`（HTTP 403）で遮断する。
- **完了基準 (DoD)**:
  - リクエストJSONに偽造された `ownerId` が含まれていても完全に無視され、認証ユーザーの店舗として作成されること。
  - `store` レコードが外部キー制約（`fk_store_owner`）を満たして正常作成されること。
  - C#リンター規則に100%適合し、単体テストを全件パスすること。

---

#### [REQ-MEMBER-001] 会員登録・BCrypt認証およびRBAC認可制御
- **区分**: セキュリティおよび認可 (Security & RBAC)
- **概要**: 一般スタッフおよび店舗オーナーのアカウントを登録し、BCrypt暗号化認証および厳格なロールベースアクセス制御（RBAC）を適用する。ロールの自己昇格を物理的に遮断する。
- **入力**:
  - `email` (ログインメールアドレス, RFC 5322準拠, 100文字以内)
  - `rawPassword` (パスワード平文, 8文字以上、英数記号混在)
  - `name` (氏名, 50文字以内)
  - `phone` (連絡先電話番号, 20文字以内)
  - *(注: クライアント入力からの `role` パラメータ指定を完全禁止。一般登録時はサーバー側で `'ROLE_STAFF'` に固定設定される)*
- **処理**:
  1. `email` の一意性を小文字正規化の上、`member` テーブル上で照合する。
  2. パスワード強度をバリデーションし、BCryptハッシュアルゴリズム（ストレングス10以上）で不可逆暗号化する。
  3. 会員登録処理において、クライアントからのロール指定は受け付けず、サーバー側で強制的に `role = 'ROLE_STAFF'`、`is_active = TRUE` で初期化する。
  4. オーナーアカウント発行は管理権限を持つ専用フローに限定し、任意のロール自己昇格（P0脆弱性）を原初から遮断する。
  5. 認可において、全リソースアクセスは `SecurityContextHolder.getContext().getAuthentication()` の認証Principal IDに限定照会し、他者ID偽造（IDOR脆弱性）を排除する。
- **出力**:
  - `memberId` (会員PK, BIGINT)
  - `assignedRole` (付与確定ロール, VARCHAR(20))
- **例外処理**:
  - 重複メールアドレスが存在する場合、`IllegalStateException`（重複リソース例外, HTTP 400）を送出する。
  - 不正な入力パラメータ・パスワード書式は `MethodArgumentNotValidException`（HTTP 400）を返却する。
- **完了基準 (DoD)**:
  - 一般登録リクエストで `role: "ROLE_OWNER"` を送信しても無視され、`ROLE_STAFF` で登録されること。
  - データベース上にパスワード平文が一切保存されないこと。

---

#### [REQ-STAFF-001] 店舗スタッフ所属申請・オーナー承認および多店舗アクセス制御
- **区分**: 機能要件および多店舗認可 (Function & Multi-Store Authorization)
- **概要**: アルバイトスタッフが店舗招待コードを入力して所属を申請し、店舗オーナーが承認時に時給・交通費契約を決定・有効化する。スタッフによる賃金の自己決定を禁止し、多店舗間のデータ漏洩を遮断する。
- **入力 (スタッフ申請時)**:
  - `inviteCode` (店舗招待コード, VARCHAR(20), 必須)
  - *(注: スタッフによる時給・交通費の入力は完全禁止。申請時は招待コードのみを受け付ける)*
- **入力 (オーナー承認時)**:
  - `storeStaffId` (承認対象のスタッフ所属ID, BIGINT)
  - `hourlyWage` (オーナー決定契約時給, 整数, 最低賃金以上)
  - `dailyTransportFee` (オーナー決定1日通勤手当, 整数, 0以上)
  - `monthlyTransportLimit` (月額交通費上限, 整数, デフォルト 15000)
- **処理**:
  1. **スタッフ申請時**: `inviteCode` より対象店舗を特定し、複合ユニーク制約（`uq_store_member`）を検証の上、`employment_status = 'PENDING'` で `store_staff` を初期生成する。
  2. **オーナー承認時**: ログインオーナーが当該店舗の正当な所有者（`store.owner_id == principal.id`）であることを検証する。
  3. オーナーが入力した時給・交通費を初期契約として `store_staff_contract_history` に新規作成し、ステータスを `'PENDING' → 'ACTIVE'` へ昇格させる。
  4. **多店舗アクセス制御**: 店舗スコープを持つすべての処理（打刻・シフト・給与）において、認証ユーザーの店舗所属権限（`store_staff` / `store.owner_id`）を厳格に照合し、他店舗スタッフおよび無関係な第三者オーナーのアクセスをHTTP 403で遮断する。
  5. **雇用状態遷移マシン**:
     - `PENDING → ACTIVE` (オーナー承認)
     - `ACTIVE → RESIGNED` (退職処理: 以後の打刻・シフト申請を即時遮断、確定済み給与の監査閲覧権限のみ維持)
     - `RESIGNED → ACTIVE` (不正再昇格の禁止: 再雇用の場合は新規 `store_staff` レコードを発行)
- **出力**:
  - `storeStaffId` (店舗スタッフ所属PK, BIGINT)
  - `employmentStatus` (雇用確定ステータス, `'ACTIVE'` / `'RESIGNED'`)
- **例外処理**:
  - 無効な招待コードは `IllegalArgumentException`（HTTP 400）を送出する。
  - オーナー以外のユーザーが承認APIを呼び出した場合、`AccessDeniedException`（HTTP 403）を送出する。
- **完了基準 (DoD)**:
  - スタッフが自身の時給・交通費を改ざん申請できないこと。
  - 所属外店舗のデータアクセス試行が100%確実にHTTP 403でブロックされること。

---

#### [REQ-STAFF-002] 給与算定用契約条件（時給・交通費）履歴管理および期間排他制御
- **区分**: データ整合性および並行性制御 (Data Integrity & Concurrency)
- **概要**: スタッフの時給改定や通勤手当の変更が行われた際、過去の確定給与計算の不変性を担保するため、適用開始日・終了日を持つ契約履歴テーブル（`store_staff_contract_history`）へ履歴保存し、期間重複を悲観的ロックで排他制御する。
- **入力**:
  - `storeStaffId` (店舗スタッフFK, BIGINT)
  - `effectiveFrom` (適用開始日, DATE, 必須)
  - `hourlyWage` (適用基本時給, 整数, 正の値)
  - `dailyTransportFee` (適用日別交通費, 整数, 0以上)
  - `monthlyTransportLimit` (適用月別交通費上限, 整数, デフォルト 15000)
- **処理**:
  1. トランザクション内で対象 `store_staff` 行を悲観的ロック（`SELECT ... FOR UPDATE`）でロック獲得し、競合する同時契約更新を直列化する。
  2. 当該スタッフの既存有効契約（`effective_to IS NULL`）を特定する。
  3. 新規 `effectiveFrom` が既存契約の `effective_from` より未来日であることを検証する（過去遡及による期間逆転の防止）。
  4. 既存契約の `effective_to` を新規 `effectiveFrom` の前日日付で確定更新する。
  5. 新規契約レコードを `effective_to = NULL` で新規作成し、コミットする。
- **出力**:
  - `contractHistoryId` (契約履歴PK, BIGINT)
  - `effectiveFrom` (適用開始確定日, DATE)
- **例外処理**:
  - 期間重複や日付逆転（`effectiveFrom <= 既存effective_from`）の場合、`InvalidPeriodException`（HTTP 400）を送出する。
  - 時給が0以下または地域別最低賃金未満の場合、`IllegalArgumentException`（HTTP 400）を送出する。
- **完了基準 (DoD)**:
  - 過去日付の給与再計算時、該当勤務日時点の有効時給が正確にスナップショット参照されること。
  - 同時に複数件の契約更新が発生しても、`SELECT ... FOR UPDATE` により期間重複レコードが一切生成されないこと。
  - C#リンター規則に100%適合すること。

---

### 2.2 [Slice 2] シフト管理および確定調停・労働基準法第34条休憩統制 (Shift Management & Concurrency Control)

#### [REQ-SHIFT-001] スタッフ希望シフト申請および排他制御（悲観的ロック）
- **区分**: 機能要件および並行性制御 (Function & Concurrency)
- **概要**: アルバイトスタッフが自身の勤務希望日時を申請し（新規申請 → SUBMITTED）、同一スタッフの多重申請レースコンディションを悲観的ロック（`SELECT ... FOR UPDATE`）により直列化して重複申請を遮断する。
- **入力**:
  - `storeId` (店舗ID, BIGINT, 必須)
  - `workDate` (勤務基準日, DATE, 必須, 当日以降の日付)
  - `requestedStartTime` (希望開始時刻, TIME, 必須, 'HH:mm' 形式)
  - `requestedEndTime` (希望終了時刻, TIME, 必須, 'HH:mm' 形式)
  - `staffMemo` (スタッフ側メモ, VARCHAR(255), 任意)
  - *(注: `storeStaffId` はリクエストボディの偽造値を信用せず、セッション認証済みPrincipalにバインドされたIDを使用する)*
- **処理**:
  1. 勤務基準日 `workDate` が店舗ローカル日付の当日より過去である場合、即時拒否する。
  2. 開始・終了時刻を解析し、終了時刻が開始時刻より前の場合は翌日跨ぎ勤務（翌日日付）として終了日時を解決する。開始時刻と終了時刻が同一の場合は拒否する。
  3. `Duration.between(startAt, endAt).compareTo(Duration.ofHours(16)) > 0` により、1回のシフト拘束時間が最大16時間以内であることをミリ秒/分単位で厳密に検証する。
  4. 対象 `store_staff_id` に対し悲観的排他ロック（`SELECT store_staff_id FROM store_staff WHERE store_staff_id = ? FOR UPDATE`）を獲得し、並行申請トランザクションを直列化する。
  5. 同一スタッフについて `status IN ('SUBMITTED', 'CONFIRMED')` の既存シフトとの時間帯重複（Overlap）を検証し、重複がある場合は登録を拒否する。
  6. 検証成功時、状態遷移（新規申請 → SUBMITTED）を行い、`status = 'SUBMITTED'`、`planned_break_minutes = 0` として `shift_schedule` テーブルに新規永続化する。
- **出力**:
  - `shiftId` (生成されたシフトPK, BIGINT)
  - `status` (初期状態 'SUBMITTED', VARCHAR(20))
- **例外処理**:
  - 時刻文字列の解析失敗時は `DateTimeParseException`（HTTP 400）を送出する。
  - 過去日付指定または16時間超過時は `IllegalArgumentException`（HTTP 400）を送出する。
  - 同一スタッフの既存シフトと時間帯重複が発生した場合は `IllegalStateException`（HTTP 409 Conflict）を送出する。
  - 他者の `store_staff_id` への偽造申請は `AccessDeniedException`（HTTP 403 Forbidden）で遮断する。
- **完了基準 (DoD)**:
  - 並行する2件の希望申請が同一スタッフ・同一時間帯に発生した場合、悲観的ロックにより一方が確実に HTTP 409 で拒否され、重複レコードが生成されないこと。
  - 翌日跨ぎのシフト（例: 22:00 `~` 翌06:00）が正常に日付跨ぎ計算され、16時間境界検証を通過すること。

#### [REQ-SHIFT-002] 店長によるシフト確定調停および労働基準法第34条法定休憩時間の算定
- **区分**: 機能要件および労働法遵守 (Function & Legal Compliance)
- **概要**: 店舗管理者が申請された希望シフトを確認・調停し、日本労働基準法第34条に基づく法定休憩時間を自動算定・検証した上で確定調停（SUBMITTED → CONFIRMED または SUBMITTED → REJECTED）へ状態遷移させる。
- **入力**:
  - `shiftId` (調停対象シフトPK, BIGINT, パス変数, 必須)
  - `confirmedStartTime` (確定開始時刻, TIME, 必須, 'HH:mm' 形式)
  - `confirmedEndTime` (確定終了時刻, TIME, 必須, 'HH:mm' 形式)
  - `plannedBreakMinutes` (計画休憩時間（分）, INT, 任意・未指定時は法定推奨値を自動設定)
  - `status` (確定状態 'CONFIRMED' または却下 'REJECTED', 必須)
  - `ownerMemo` (店長側メモ, VARCHAR(255), 任意)
  - *(注: 操作者の `storeId` はセッション認証コンテキストより取得する)*
- **処理**:
  1. 操作対象シフトの `store_id` と店長セッションの `store_id` が一致することを検証し、他店舗シフトの不正操作（クロス店舗IDOR）を即時遮断する。
  2. 対象 `shift_schedule` レコードを行排他ロック（`SELECT ... FOR UPDATE`）で取得する。
  3. 拘束時間（`grossMinutes = Duration.between(startAt, endAt).toMinutes()`）を算出し、最大16時間以内であることを検証する。
  4. 自身を除く確定済みシフトとの時間重複が存在しないことを検証する。
  5. 計画休憩時間を評価する：
     - 未指定時の自動算定推奨値：拘束時間 `<= 360分`（6時間以下）は `0分`、`360分 < 拘束時間 <= 525分`（6時間超8時間以下）は `45分`、`拘束時間 > 525分`（8時間超）は `60分`。
     - 手動指定時：`plannedBreakMinutes` が拘束時間以上または負数の場合は拒否する。実労働時間（`grossMinutes - plannedBreakMinutes`）が6時間超で45分未満、または8時間超で60分未満の場合は警告・再確認を要求する。
  6. CAS条件付き更新（`WHERE shift_id = ? AND store_id = ? AND status = 'SUBMITTED'`）を実行し、状態遷移（SUBMITTED → CONFIRMED または SUBMITTED → REJECTED）を行い、`affected rows == 1` を検証して確定状態へ更新する。
- **出力**:
  - `shiftId` (確定シフトPK, BIGINT)
  - `status` (確定ステータス 'CONFIRMED', VARCHAR(20))
  - `plannedBreakMinutes` (適用計画休憩時間（分）, INT)
- **例外処理**:
  - 対象シフトが存在しない場合は `SHIFT_NOT_FOUND`（HTTP 404）を返却する。
  - 店舗不一致の場合は `CROSS_STORE_ACCESS_DENIED`（HTTP 403）を送出し、監査ログへ記録する。
  - 休憩時間が拘束時間を超過する場合は `BREAK_EXCEEDS_SPAN`（HTTP 422）を返却する。
  - 他の管理者との同時更新競合（CAS失敗）時は `SHIFT_CONCURRENT_MODIFICATION`（HTTP 409）を返却する。
- **完了基準 (DoD)**:
  - 拘束時間8時間30分（510分）のシフトに対して休憩45分を適用した場合、実労働時間が7時間45分となり法定45分基準を満たして確定されること。
  - 他店舗の店長アカウントからの更新リクエストが HTTP 403 で遮断されること。

#### [REQ-SHIFT-003] 希望シフト申請の本人取消および状態遷移制御
- **区分**: 機能要件および認可制御 (Function & Authorization)
- **概要**: スタッフ本人が提出済みの希望申請中シフトを取り下げる（SUBMITTED → CANCELLED_DELETED）。確定済（CONFIRMED）シフトの無断取消は防止し、店長直接連絡を強制する。
- **入力**:
  - `shiftId` (取消対象シフトPK, BIGINT, パス変数, 必須)
  - *(注: 操作者の `storeStaffId` および `storeId` はセッション認証コンテキストより取得する)*
- **処理**:
  1. セッションの `storeStaffId` に基づき、対象シフトを行ロック（`SELECT ... FOR UPDATE`）で取得する。
  2. 対象レコードの `store_staff_id` がセッション値と一致しない場合、他者シフトの不正削除（IDOR）として即時遮断する。
  3. シフトの現在の `status` を検証する：
     - `status == 'SUBMITTED'` の場合のみ、状態遷移（SUBMITTED → CANCELLED_DELETED）による物理削除を許可する。
     - `status == 'CONFIRMED'` または `'REJECTED'` の場合は取消を拒否し、確定後の無断欠勤・自己取消を防止する。
  4. 削除クエリ実行時、`affected rows == 1` を検証して直列化を完了する。
- **出力**:
  - `success` (取消完了フラグ, BOOLEAN, `true`)
- **例外処理**:
  - 他スタッフのシフト取消試行時は `SecurityException`（HTTP 403 Forbidden）を送出し、監査ログへ記録する。
  - 確定済みシフトの取消試行時は `IllegalStateException`（HTTP 409 Conflict: "確定済のシフトは申請取消できません"）を送出する。
  - 対象シフトが存在しない場合は `IllegalArgumentException`（HTTP 404 Not Found）を送出する。
- **完了基準 (DoD)**:
  - `SUBMITTED` 状態の希望シフトのみが正常に取り消され、`CONFIRMED` 状態のシフトに対する取消リクエストが HTTP 409 で確実にブロックされること。

#### [REQ-SHIFT-004] カレンダー表示連携（FullCalendar 6.x）およびプライバシー保護
- **区分**: 機能要件およびプライバシー統制 (Function & Privacy Protection)
- **概要**: 月間カレンダー画面（FullCalendar 6.x）向けにシフトイベント一覧を配信し、排他終了日境界（`work_date < endDate`）を厳守するとともに、他スタッフへの個人情報（メモ・給与単価等）漏洩をマスキング遮断する。
- **入力**:
  - `storeId` (店舗ID, BIGINT, クエリパラメータ, 必須)
  - `startDate` (検索開始日, DATE, ISO-8601, 必須)
  - `endDate` (検索終了日, DATE, ISO-8601, 必須, ※FullCalendar仕様上この日付自体は含まない)
  - *(注: 操作者のスタッフIDおよび管理者権限フラグ `isManager` はセッションより解決する)*
- **処理**:
  1. 日付境界条件 `s.work_date >= #{startDate} AND s.work_date < #{endDate}` を厳守して `shift_schedule` レコードを抽出する（`endDate` 当日のシフトを除外）。
  2. 抽出された各シフトレコードに対し、操作者権限に応じたプライバシーマスキング（DTO変換）を実施する：
     - **本人または店舗管理者（店長）**: 確定/希望日時、状態、`staffMemo`、`ownerMemo`、計画休憩時間の全項目を開示する。
     - **同一店舗の他スタッフ**: 開始日時、終了日時、スタッフ表示名、状態（確定・希望）のみを開示し、`staffMemo`、`ownerMemo`、給与単価、時給等の機微情報は完全に `null` マスクする。
  3. FullCalendar用表示プロパティを構築する：
     - `CONFIRMED`: 青色表示（`#0d6efd`）、確定時間帯表示
     - `SUBMITTED`: 橙色表示（`#fd7e14`）、希望時間帯表示
     - `REJECTED`: 灰色表示（`#6c757d`）
- **出力**:
  - `events` (FullCalendar Event DTOリスト, JSON配列)
- **例外処理**:
  - 日付形式のパース失敗時は `DateTimeParseException`（HTTP 400）を送出する。
  - 無効な `storeId` または店舗未所属スタッフのアクセスは `AccessDeniedException`（HTTP 403）で遮断する。
- **完了基準 (DoD)**:
  - 他スタッフのシフト情報レスポンスに `staffMemo` や `ownerMemo` が一切漏洩せず、プライバシーが保護されること。
  - 月間カレンダーの末日翌日（`endDate`）のデータが誤ってレスポンスに含まれないこと。

---

### 2.3 [Slice 4] 労働基準法第37条 割増賃金算定エンジンおよび並行性制御 (Payroll Engine)

#### [REQ-LABOR-001] 法定労働時間超過・時間外割増手当（残業手当）の算定
- **区分**: 機能要件 (Function)
- **概要**: 実労働時間が1日の法定基準である8時間（480分）を超過した時間に対し、通常基本時給の1.25倍（基本100% + 残業割増25%）を適用して残業手当を算定する。
- **入力**: 
  - `clockInAt` (出勤日時, ISO-8601)
  - `clockOutAt` (退勤日時, ISO-8601)
  - `breakIntervals` (休憩開始・終了日時リスト)
  - `hourlyWage` (基本時給, JPY 整数)
- **処理**:
  1. 総滞在時間から有効休憩時間の合算分を控除し、実労働時間を分単位で算出する。
  2. 実労働時間が480分を超過する場合、超過分を `overtimeMinutes` に分類する。
  3. 基本給は総実労働時間×時給で算定し、残業手当（割増分） = `Math.floor((hourlyWage * 0.25 * overtimeMinutes) / 60)` とする。
- **出力**:
  - `overtimeMinutes` (残業時間, 分)
  - `overtimePay` (残業割増手当, JPY)
- **例外処理**:
  - `clockOutAt` が未打刻の状態である場合、`IllegalStateException` をスローして算定を中断する。
  - `hourlyWage` が0以下の場合、店舗所在地の都道府県別最低賃金で安全にフォールバックする。
- **完了基準 (DoD)**:
  - 480分以下の労働時、残業時間が0分として算出されること。
  - C#リンター規則に100%適合し、JUnit 5単体テスト3種と計算結果が完全に一致すること。

---

#### [REQ-LABOR-002] 深夜労働割増手当（深夜手当）の算定
- **区分**: 機能要件 (Function)
- **概要**: 夜間深夜時間帯である `22:00 ~ 05:00` の間に実施された実労働時間に対し、法定割増分25%を加算適用する。
- **入力**:
  - 勤務日付および出退勤打刻区間
  - 深夜時間帯定義: 当日 `22:00:00` から翌日 `05:00:00` まで
- **処理**:
  1. 出退勤区間と深夜区間（`22:00 ~ 05:00`）の重複区間を分単位で抽出する。
  2. 深夜区間内に含まれる休憩時間を厳密に控除し、純粋な深夜実労働時間（`nightMinutes`）を確定する。
  3. 深夜手当（割増分） = `Math.floor((hourlyWage * 0.25 * nightMinutes) / 60)`。
- **出力**:
  - `nightMinutes` (深夜労働時間, 分)
  - `nightPay` (深夜加算手当, JPY)
- **例外処理**:
  - 日付跨ぎシフト（Overnight Shift）において、日付境界線の誤認なく24時以降を翌日05時まで正常な連続区間として認識すること。
- **完了基準 (DoD)**:
  - 深夜時間帯に休憩が含まれる場合、休憩分が深夜実労働から正確に控除されること。
  - C#リンターを100%通過し、境界値（21:59、22:01打刻）テストを満足すること。

---

#### [REQ-LABOR-003] 時間外および深夜の重畳割増（150%）算定
- **区分**: 機能要件 (Function)
- **概要**: 1日8時間を超過した残業労働が深夜時間帯（`22:00 ~ 05:00`）に同時に発生した場合、法定要率に基づき1.50倍（基本100% + 残業25% + 深夜25%）の重畳割増を適用する。二重計上を厳格に排除する。
- **入力**:
  - `overtimeMinutes` (残業時間)
  - `nightMinutes` (深夜労働時間)
  - `overlapMinutes` (残業かつ深夜に該当する重複時間)
- **処理**:
  1. 8時間超過後の残業区間と深夜区間（`22:00 ~ 05:00`）が重複する区間を `overlapMinutes` として算出する。
  2. 日別支給総額 = 基本労働給（全実労働時間×時給） + 残業割増分（`0.25 × overtimeMinutes`） + 深夜割増分（`0.25 × nightMinutes`）。重複区間は残業と深夜の双方が加算されることで自然に150%割増に収束する。
- **出力**:
  - `overlapMinutes` (重畳時間, 分)
  - `totalDailyPay` (日給合算額, JPY)
- **例外処理**:
  - 日本通貨基準（基発第150号）に従い、月次合算確定時に `RoundingMode.HALF_UP`（50銭以上切り上げ）を適用して1円齟齬を排除する。
- **完了基準 (DoD)**:
  - 残業と深夜が重複しない区間では重畳加算が0円として算出されること。
  - C#リンターを100%通過し、重畳手当150%の実測エビデンスと一致すること。

---

#### [REQ-LABOR-004] 悲観的ロック（Pessimistic Lock）に基づく給与確定トランザクション整合性
- **区分**: セキュリティおよび並行性制御 (Security & Concurrency)
- **概要**: 店長が特定月の給与を一括締めおよび確定する際、同時打刻修正や重複確定リクエストによるデータ汚染を遮断するため、データベース行レベル悲観的ロック（`SELECT ... FOR UPDATE`）を適用する。
- **入力**:
  - `storeId` (店舗ID)
  - `targetMonth` (精算対象年月, YYYY-MM)
- **処理**:
  1. 給与精算テーブルの該当月レコードに対し、トランザクション内で排他的書き込みロック（`SELECT ... FOR UPDATE`）を獲得する。
  2. 締め状態（`status == 'CLOSED'` または `'CONFIRMED'`）を検証し、確定済みの場合は追加更新を厳格に拒否する。
  3. トランザクション完了時にコミットとともにロックを解放する。
- **出力**:
  - `settlementStatus` ('LOCKED' → 'CONFIRMED')
- **例外処理**:
  - ロック獲得タイムアウト（3秒）超過時、即座に `PessimisticLockException` をスローしてロールバックする。
- **完了基準 (DoD)**:
  - 同時に2件の給与確定リクエストが発生した場合、1件のみが成功し、もう1件は確実にブロックされること。
  - C#リンターを100%通過し、Spring Boot並行性統合テストを合格すること。
