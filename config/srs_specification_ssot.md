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
3. **技術スタックおよび検証エンジンの責務分離**:
   - **システム実装基盤 (Target Architecture)**: Java 21 / Spring Boot 3.x / MyBatis 3.5 / PostgreSQL 16（トランザクション境界、悲観的ロック、BigDecimal高精度有理数演算）。
   - **品質検証エンジン (Verification Toolchain)**: C# Roslyn 決定論的リンター（`VerifySRS_Deterministic.exe`, `VerifySRS_Integrity.exe`）、ローカルGPU Qwen 27B、OpenAI Codex CLI、Anthropic Claude 5.5。

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
  2. 8桁のセキュアな英数字からなる一意な `invite_code`（DB制約 `CONSTRAINT uq_store_invite_code UNIQUE`）およびユニークな `qr_token`（UUID v4ベース、DB制約 `CONSTRAINT uq_store_qr_token UNIQUE`）を生成する。
  3. `pay_cutoff_day` が `1 ~ 28` または `99` の許容範囲内であることをチェック制約（`chk_store_cutoff`）に適合させる。
  4. オーナーIDをFKとしてバインドし、店舗レコードを `store` テーブルに永続化する。
  5. 打刻の現場性担保および不正防止策として、静的 `qr_token` 発行に加え、未退勤状態での二重出勤をDBレベルで物理的に遮断する部分一意インデックス（`CREATE UNIQUE INDEX uq_open_attendance ON attendance (store_staff_id) WHERE clock_out_at IS NULL;`）の参照店舗キーとして機能させる。
- **出力**:
  - `storeId` (生成された店舗PK, BIGINT)
  - `inviteCode` (発行された招待コード, VARCHAR(20))
  - `qrToken` (打刻用QRトークン, VARCHAR(100))
- **例外処理**:
  - 招待コードまたはQRトークンの一意性衝突（SQLSTATE `23505`）が発生した場合、同一トランザクションの汚染を防止するためセーブポイント（`SAVEPOINT sp_store_retry`）へロールバックした上で再生成リトライ（最大5回、指数バックオフ）を行い、一意性を担保する。
  - 締め日パラメータが不正な場合、`IllegalArgumentException`（HTTP 400）を送出する。
  - 未認証または `ROLE_OWNER` 以外の呼び出しは `AccessDeniedException`（HTTP 403）で遮断する。
- **完了基準 (DoD)**:
  - リクエストJSONに偽造された `ownerId` が含まれていても完全に無視され、認証ユーザーの店舗として作成されること。
  - `store` レコードが外部キー制約（`fk_store_owner`）を満たして正常作成され、`qr_token` の一意性がDBレベルで担保されること。
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
  1. `email` の一意性を小文字正規化の上、DB層の関数ベース一意インデックス（`CREATE UNIQUE INDEX uq_member_lower_email ON member (LOWER(email))`）により同時実行TOCTOU競合を確実に遮断して照合する。
  2. パスワード強度をバリデーションし、BCryptハッシュアルゴリズム（ストレングス10以上）で不可逆暗号化する。
  3. 会員登録処理において、クライアントからのロール指定は受け付けず、サーバー側で強制的に `role = 'ROLE_STAFF'`、`is_active = TRUE` で初期化する。
  4. オーナーアカウント発行は管理権限を持つ専用フローに限定し、任意のロール自己昇格（P0脆弱性）を原初から遮断する。
  5. 認可において、全リソースアクセスは `SecurityContextHolder.getContext().getAuthentication()` の認証Principal IDに限定照会し、他者ID偽造（IDOR脆弱性）を排除する。
- **出力**:
  - `memberId` (会員PK, BIGINT)
  - `email` (登録メールアドレス, VARCHAR(100))
  - `role` (付与ロール `'ROLE_STAFF'`, VARCHAR(20))
- **例外処理**:
  - 重複メールアドレスが存在する場合（`INSERT ... ON CONFLICT (lower(email)) DO NOTHING` で更新行数0）、一貫して `DuplicateResourceException`（HTTP 409 Conflict）を送出する。
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
  - `effectiveFrom` (契約適用開始日, DATE, 必須, 原則として承認日当日または指定開始日)
  - `hourlyWage` (オーナー決定契約時給, 整数, 最低賃金以上)
  - `dailyTransportFee` (オーナー決定1日通勤手当, 整数, 0以上)
  - `monthlyTransportLimit` (月額交通費上限, 整数, デフォルト 15000)
- **処理**:
  1. **スタッフ申請時**: `inviteCode` より対象店舗を特定し、複合ユニーク制約（`CONSTRAINT uq_store_member UNIQUE (store_id, member_id)`）および店舗所属整合性制約（`CONSTRAINT uq_store_staff_store UNIQUE (store_staff_id, store_id)`）を検証の上、`employment_status = 'PENDING'`、`application_version = 1` で `store_staff` を初期生成する。
  2. **オーナー承認時**: ログインオーナーが当該店舗の正当な所有者（`store.owner_id == principal.id`）であることを検証する。
  3. **原子的状態昇格と契約発行 (CAS防護)**: 並行承認競合や古い申請の誤承認を防ぐため、`UPDATE store_staff SET employment_status = 'ACTIVE' WHERE store_staff_id = :storeStaffId AND employment_status = 'PENDING' AND application_version = :expectedVersion` を実行し、更新行数が正確に1行であることを検証する。検証成功時のみ、オーナー指定の時給・交通費を初期契約として `store_staff_contract_history`（`effective_from = :effectiveFrom, effective_to = NULL`）に新規永続化する。
  4. **多店舗アクセス制御**: 店舗スコープを持つすべての処理（打刻・シフト・給与）において、認証ユーザーの店舗所属権限（`store_staff` / `store.owner_id`）を厳格に照合し、他店舗スタッフおよび無関係な第三者オーナーのアクセスをHTTP 403で遮断する。
  5. **雇用状態遷移マシン**:
     - `PENDING → ACTIVE` (オーナー承認)
     - `ACTIVE → RESIGNED` (退職処理: 以後の打刻・シフト申請を即時遮断、確定済み給与の監査閲覧権限のみ維持。最終契約の `effective_to` を退職日当日で確定終了させる)
     - `RESIGNED → PENDING → ACTIVE` (再雇用フロー: 複合ユニーク制約 `uq_store_member` との衝突を回避するため、既存 `store_staff` レコードの `application_version` をインクリメントし、`employment_status = 'PENDING'` として状態更新した上で、新規契約履歴とともにオーナーが再承認する。直接の `RESIGNED → ACTIVE` 不正再昇格は禁止)
- **出力**:
  - `storeStaffId` (店舗スタッフ所属PK, BIGINT)
  - `employmentStatus` (雇用確定ステータス, `'ACTIVE'` / `'RESIGNED'`)
- **例外処理**:
  - 無効な招待コードは `IllegalArgumentException`（HTTP 400）を送出する。
  - オーナー以外のユーザーが承認APIを呼び出した場合、`AccessDeniedException`（HTTP 403）を送出する。
- **完了基準 (DoD)**:
  - スタッフが自身の時給・交通費を改ざん申請できないこと。
  - 所属外店舗のデータアクセス試行が100%確実にHTTP 403でブロックされること。
  - 退職後の再雇用時に複合一意制約エラーを発生させず、新規契約履歴とともに安全に再承認されること。

---

#### [REQ-STAFF-002] 給与算定用契約条件（時給・交通費）履歴管理および期間排他制御
- **区分**: データ整合性および並行性制御 (Data Integrity & Concurrency)
- **概要**: スタッフの時給改定や通勤手当の変更が行われた際、過去の確定給与計算の不変性を担保するため、適用開始日・終了日（無期限契約は `effective_to IS NULL`）を持つ契約履歴テーブル（`store_staff_contract_history`）へ履歴保存し、PostgreSQLのGiST排他制約および悲観的ロックで期間重複を完全排除する。
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
  6. DB層における防御線として、`btree_gist` 拡張を有効化し、`store_staff_contract_history` に排他制約（`CONSTRAINT ex_contract_period EXCLUDE USING gist (store_staff_id WITH =, daterange(effective_from, effective_to, '[]') WITH &&)`）を強制適用し、期間重複の挿入を物理的に遮断する。
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
  1. 操作対象シフトの `store_id` と店長セッションの `store_id` が一致することを検証し、他店舗シフトの不正操作（クロス店舗IDOR）を即時遮断する。また、シフトテーブルに `FOREIGN KEY (store_staff_id, store_id) REFERENCES store_staff(store_staff_id, store_id)` 複合外部キー制約を強制し、他店舗所属スタッフの混入をDB層で物理排除する。
  2. 対象スタッフの先行排他ロック（`SELECT member_id FROM store_staff WHERE store_staff_id = ? FOR UPDATE`）を獲得し、多店舗並行確定や同一スタッフへの同時調停トランザクションを直列化する。
  3. 対象 `shift_schedule` レコードを行排他ロック（`SELECT ... FOR UPDATE`）で取得する。
  4. 拘束時間（`grossMinutes = Duration.between(startAt, endAt).toMinutes()`）を算出し、最大16時間以内であることを検証する。
  5. アプリケーション層およびDB排他制約（PostgreSQL: `EXCLUDE USING gist (member_id WITH =, tstzrange(confirmed_start_at, confirmed_end_at, '[)') WITH &&) WHERE (status = 'CONFIRMED')`）により、同一人物（`member_id`）が複数店舗で同時刻に重複確定される競合を二重防御線で遮断する（他店舗競合時は店舗詳細を伏せてHTTP 409を返却）。
  6. 労働基準法第34条に基づく法定休憩時間の完全Fail-Closed評価：
     - 未指定時の自動算定推奨値：拘束時間 `<= 360分`（6時間以下）は `0分`、`360分 < 拘束時間 <= 525分`（6時間超8時間以下）は `45分`、`拘束時間 > 525分`（8時間超）は `60分`。
     - 手動指定時：実労働時間（`grossMinutes - plannedBreakMinutes`）に対し、`実労働 > 8時間` で休憩60分未満、または `実労働 > 6時間` で休憩45分未満の場合、警告にとどめず `BREAK_TIME_DEFICIT`（HTTP 422 Unprocessable Entity）を送出し、確定（CONFIRMED）への状態遷移を即時拒否・遮断する。
  7. CAS条件付き更新（`WHERE shift_id = ? AND store_id = ? AND status = 'SUBMITTED'`）を実行し、状態遷移（SUBMITTED → CONFIRMED または SUBMITTED → REJECTED）を行い、`affected rows == 1` を検証して確定状態へ更新する。
- **出力**:
  - `shiftId` (確定シフトPK, BIGINT)
  - `status` (確定ステータス 'CONFIRMED', VARCHAR(20))
  - `plannedBreakMinutes` (適用計画休憩時間（分）, INT)
- **例外処理**:
  - 対象シフトが存在しない場合は `SHIFT_NOT_FOUND`（HTTP 404）を返却する。
  - 店舗不一致の場合は `CROSS_STORE_ACCESS_DENIED`（HTTP 403）を送出し、監査ログへ記録する。
  - 休憩時間が拘束時間を超過する場合、または法定休憩基準に未達の場合は `BREAK_TIME_DEFICIT`（HTTP 422）を返却する。
  - 他の管理者との同時更新競合（CAS失敗）または他店舗重複確定時は `SHIFT_CONCURRENT_MODIFICATION`（HTTP 409）を返却する。
- **完了基準 (DoD)**:
  - 拘束時間8時間30分（510分）のシフトに対して休憩45分を適用した場合、実労働時間が7時間45分となり法定45分基準を満たして確定されること。
  - 実労働8時間超に対し休憩が60分未満の場合は確定が HTTP 422 で確実にブロックされること。
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
- **概要**: 月間カレンダー画面（FullCalendar 6.x）向けにシフトイベント一覧を配信し、時間交差判定（`event_start_at < rangeEnd AND event_end_at > rangeStart`）により前日夜勤の翌朝跨ぎ表示を担保するとともに、他スタッフへの個人情報（メモ・給与単価等）漏洩を行単位認可でマスキング遮断する。
- **入力**:
  - `storeId` (店舗ID, BIGINT, クエリパラメータ, 必須)
  - `startDate` (検索開始日, DATE, ISO-8601, 必須)
  - `endDate` (検索終了日, DATE, ISO-8601, 必須, ※FullCalendar仕様上この日付自体は含まない)
  - *(注: 操作者のスタッフIDおよび管理者権限フラグ `isManager` はセッションより解決する)*
- **処理**:
  1. 日付交差条件（`event_start_at < :rangeEnd AND event_end_at > :rangeStart`、境界は `Asia/Tokyo` タイムゾーン準拠のTIMESTAMPTZ）を適用し、前日からの夜勤跨ぎシフトを含めて正確に `shift_schedule` レコードを抽出する。
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
  - 前月末日22:00から当月初日06:00に及ぶ夜勤跨ぎシフトが当月カレンダー画面に漏れなく表示されること。

---

### 2.3 [Slice 4] 労働基準法第37条 割増賃金算定エンジンおよび並行性制御 (Payroll Engine)

#### [REQ-LABOR-001] 法定労働時間超過・時間外割増手当（日8時間および週40時間基準）の算定
- **区分**: 機能要件および労働法遵守 (Function & Legal Compliance)
- **概要**: 労働基準法第32条、第37条、および第38条（事業場を異にする場合の通算）に基づき、同一労働者の同一法定労働日（LWD）における全勤務セグメントを通算合算し、1日8時間超過（日次法定外残業）および週40時間超過（週次法定外残業）の実労働時間を厳密に算出して基本時給の1.25倍（基本100% + 残業割増25%）を適用する。法定休日労働（第35条）は時間外労働算定（週40h・日8h）から完全に除外して独立算定する。同日複数回勤務（中抜け勤務等）における8時間超過漏れを完全排除し、月次確定時まで秒単位・有理数（BigDecimal）の精度を維持する。
- **入力**: 
  - `clockInAt` (出勤日時, ISO-8601, 秒精度)
  - `clockOutAt` (退勤日時, ISO-8601, 秒精度)
  - `breakIntervals` (休憩開始・終了日時リスト, 半開区間, 秒精度)
  - `hourlyWage` (基本時給, JPY 整数)
  - `isStatutoryHoliday` (法定休日該当フラグ, BOOLEAN, 週1日または4週4日の法定休日)
  - `priorDailyMinutes` (同一法定労働日内の先行動務の実労働累計時間, 分)
  - `priorWeeklyMinutes` (同一週内の既算定実労働累計時間（法定休日および日次残業算定済分を除く）, 分)
- **処理**:
  1. **二元属性判定（Dual Attribution）および継続勤務評価**:
     - **日次8時間枠算入（第32条）**: 始業時刻の属する日（就業規則上の起算時刻）を法定労働日（LWD）とし、日跨ぎシフト全体を始業日単一勤務として扱う（昭63.1.1基発第150号通達）。
     - **法定休日判定（第35条）**: 暦日（00:00:00〜24:00:00）を厳密な単位とし、通常日（土曜等）から法定休日（日曜等）へ跨ぐ勤務は暦日午前0時（00:00）で区間分割する。休日区間（00:00〜退勤）は休日労働（+35%）として算定し、日次・週次の時間外労働枠からは完全に除外する。
  2. 秒精度実労働時間の算出：総滞在時間（秒）から有効休憩時間の和集合（秒）を控除し、実労働秒数および分数を算出する。
  3. **同日複数勤務の日次8時間超過通算（SPEC-WAGE-01）**:
     - 同一労働者・同一法定労働日の勤務セグメントに対し、`currentEligibleMinutes` を算出する。
     - 日次残業時間を `dailyOvertimeMinutes = max(0, priorDailyMinutes + currentEligibleMinutes - 480) - max(0, priorDailyMinutes - 480)` として決定論的に抽出し、中抜け勤務や複数回打刻時にも8時間超過分が確実に割増対象となることを担保する。
  4. 通常勤務日の週次法定外残業判定（日次・週次二重計上防止）：
     - 当該勤務の週次算入基準時間（`weeklyAddition`）を `min(currentEligibleMinutes, max(0, 480 - priorDailyMinutes))` と決定論的に固定する。
     - 週累計実労働時間に対し、`priorWeeklyMinutes + weeklyAddition > 2400`（40時間）となる場合、その超過部分 `max(0, (priorWeeklyMinutes + weeklyAddition) - max(2400, priorWeeklyMinutes))` を `weeklyOvertimeMinutes` として計上する。
  5. 合計時間外労働時間：`totalOvertimeMinutes = dailyOvertimeMinutes + weeklyOvertimeMinutes`。
  6. 最低賃金保障（最低賃金法第4条遵守）：契約時給が改定等により法定最低賃金を下回る場合、給与確定をブロックせず `payableRate = max(contractWage, applicableMinimumWage)` で自動補正して支給計算を行い、差額およびコンプライアンス監査イベントを発行・記録する。
  7. 金額計算：日次での通貨切捨ては実施せず、乗算先行かつ除算時スケール指定により `overtimePayExact = payableRate.multiply(BigDecimal.valueOf(0.25)).multiply(BigDecimal.valueOf(totalOvertimeMinutes)).divide(BigDecimal.valueOf(60), 10, RoundingMode.HALF_UP)` を高精度 `BigDecimal` として算出し、月次集計へ連携する。
- **出力**:
  - `dailyOvertimeMinutes` (日次8h超残業時間, 分)
  - `weeklyOvertimeMinutes` (週40h超残業時間, 分)
  - `totalOvertimeMinutes` (合計時間外労働時間, 分)
  - `overtimePayExact` (高精度残業割増手当, BigDecimal)
- **例外処理**:
  - `clockOutAt` が未打刻の状態である場合、`IllegalStateException`（HTTP 409）を送出して算定を中断する。
- **完了基準 (DoD)**:
  - 同一日に 09:00〜14:00（5時間）と 16:00〜21:00（5時間）の複数回勤務を行った場合、通算10時間となり、19:00以降の2時間が確実に日次時間外割増（25%）として算定されること。
  - C#リンター規則に100%適合し、日次切捨てによる1円未満の過少払いが一切発生しないこと。

---

#### [REQ-LABOR-002] 深夜労働割増手当（深夜手当・半開区間境界）の算定
- **区分**: 機能要件および労働法遵守 (Function & Legal Compliance)
- **概要**: 労働基準法第37条第4項および昭和63年3月14日基発第150号通達に基づき、夜間深夜時間帯（当日22:00:00から翌日05:00:00直前まで）に実施された実労働時間に対し、法定割増分25%を加算適用する。暦日を跨ぐ勤務の所属日判定および深夜時間帯の積集合を高精度に算定する。
- **入力**:
  - 勤務所属日（出勤打刻の始業時刻が属する暦日）
  - 出退勤打刻日時（ISO 8601 形式 `YYYY-MM-DDTHH:mm:ss`, 秒精度）
  - 深夜時間帯定義: 当日 `22:00:00` から翌日 `05:00:00` 直前まで（半開区間 `[22:00, 05:00)`）
  - `hourlyWage` (基本時給, JPY 整数)
- **処理**:
  1. 暦日・所属日判定ルール（基発第150号準拠）：
     - 始業時刻（出勤打刻）が属する暦日を当該勤務の「所属日（起算日）」とし、暦日を跨いで翌日に及ぶ一継続勤務は、翌日の勤務を含めて始業日の単一勤務として通算する。
     - 翌日深夜（例: 00:00〜05:00）に新たに始業（出勤）した勤務は、前日の延長ではなく、当日始業の新規勤務として独立して取り扱い、当日早朝の深夜労働として算定する。
  2. 出退勤打刻区間と深夜時間帯（22:00:00〜翌日05:00:00）の重複積集合を秒精度で抽出する。
  3. 深夜区間内に交差する休憩時間を厳密に控除し、純粋な深夜実労働時間（`nightSeconds` および `nightMinutes`）を算出する（22:00境界または05:00境界に跨る休憩は深夜該当部分のみ按分控除）。
  4. 金額計算：日次での通貨切捨ては実施せず、月次集計用分子として `hourlyWage * nightSeconds * 25` を蓄積し、高精度を維持する。
- **出力**:
  - `nightMinutes` (深夜実労働時間, 分)
  - `nightSeconds` (深夜実労働時間, 秒)
  - `nightPayExact` (高精度深夜加算手当, BigDecimal)
- **例外処理**:
  - 境界値検証：21:59:59退勤時は深夜時間0秒、22:00:00在籍時は秒単位算定開始、05:00:00退勤時は04:59:59までの深夜区間のみを算定対象とすること。
- **完了基準 (DoD)**:
  - 深夜時間帯（22:00 `~` 05:00）に休憩が含まれる場合、深夜実労働から正確に休憩分が控除されること。
  - 暦日跨ぎ勤務および未明（00:00〜05:00）始業勤務の所属日判定が基発第150号と完全に合致すること。
  - C#リンター規則を100%通過し、境界値打刻テスト（21:59、22:01）を完全に満足すること。

---

#### [REQ-LABOR-003] 時間外・深夜・法定休日の重畳割増マトリクスおよび月次端数処理統制
- **区分**: 機能要件および労働法遵守 (Function & Legal Compliance)
- **概要**: 2023年4月1日施行の改正労働基準法第37条（月60時間超の時間外労働割増率50%引上げ、中小企業猶予撤廃済、法定休日労働は60h算定対象から除外）および法定休日労働（35%割増）を含む完全な重畳割増マトリクスを適用する。金額計算は累積分子・共通分母方式（`BigInteger` による分子累計および分母 `360000`）により中間丸め誤差を完全排除し、端数処理は昭和63年3月14日基発第150号通達に基づき、時間外・深夜・休日の各割増手当項目ごとに月次集計確定時の単一 `RoundingMode.HALF_UP`（50銭未満切捨て、50銭以上1円切上げ）を適用して決定論的整合性を担保する。
- **入力**:
  - `workMinutes` (総実労働時間, 分)
  - `overtimeMinutesUnder60` (月60時間以下の時間外労働時間, 分)
  - `overtimeMinutesOver60` (月60時間超の時間外労働時間, 分, 法定休日労働は除外)
  - `nightMinutes` (深夜労働時間, 分)
  - `holidayMinutes` (法定休日労働時間, 分)
  - `hourlyWage` (基本時給, JPY 整数)
  - *(注: 各種重複積集合時間はクライアント入力に一切依存せず、サーバー側給与エンジンが原始出退勤打刻・休憩区間から相互排他的セグメントとして自動抽出・検証する)*
- **処理**:
  1. サーバー側排他セグメント自動分解（不正投入遮断）：
     - 出退勤打刻および休憩区間より、全実労働時間を以下の「重複のない相互排他的な割増カテゴリー」へ自動分類する。
  2. 法定割増手当算定基準（基本給との二重計上防止）：
     - 基本給と割増手当を厳格に分離し、総乗率（125%, 150%等）を手当に乗算して基本給を二重計上する誤りを完全に排除する。
     - **基本給（Base Pay）**: `総実労働時間 × hourlyWage`（基本 100% 相当）
     - **時間外手当（<=60h）**: `overtimeMinutesUnder60 × hourlyWage × 0.25`
     - **時間外手当（>60h）**: `overtimeMinutesOver60 × hourlyWage × 0.50`（月累計60時間到達境界でセグメント分割し、超過以降の時間帯のみ50%を適用）
     - **深夜手当**: `nightMinutes × hourlyWage × 0.25`
     - **時間外×深夜重複加算**: 残業かつ深夜に重複する時間に対し、残業割増に加え深夜割増（+25%）を手当として加算（月60h超重複時は手当合計 +75%）
     - **法定休日手当**: `holidayMinutes × hourlyWage × 0.35`（法定休日の実労働に対する純粋加算分、時間外割増との二重適用なし）
     - **法定休日×深夜手当**: 休日かつ深夜に重複する時間に対し、休日割増（+35%）に深夜割増（+25%）を手当として加算（手当合計 +60%）
  3. 高精度算定および基発第150号項目別端数処理確定（50銭境界誤差の完全排除）：
     - ① 中間除算の `scale=10` 丸めによる50銭境界の1円不整合を防ぐため、秒単位実労働と時給に対し分子累計 `numerator += hourlyWage * seconds * rateFactor`（基本給 100, 割増 25, 35, 50, 60, 75）を整数/BigIntegerで保持し、共通分母 `3600 * 100` とする。
     - ② 基発第150号通達の厳格準拠：月次集計時、50銭未満切捨て・50銭以上1円切上げ（`HALF_UP`）の対象は「時間外割増手当総額」「法定休日割増手当総額」「深夜割増手当総額」の**各手当項目別**に適用し、確定整数円を算出する。基本給および通勤手当は別個に確定する。
     - ③ 月次総支給額は、確定された基本給、項目別丸め後の各割増手当、および通勤手当の総和として算定する。日次での途中切捨ては一切禁止する。
- **出力**:
  - `monthlyGrossPay` (確定月次総支給額, JPY 整数)
  - `breakdown` (基本給、残業手当(<=60h)、残業手当(>60h)、深夜手当、休日手当の各確定明細および未丸めDecimal明細)
- **例外処理**:
  - 月間時間外労働が45時間および60時間を超過する見込みとなった場合、36協定超過防止アラートイベントを発行する。
- **完了基準 (DoD)**:
  - 月60時間を超える残業が深夜時間帯に発生した場合、正確に175%（基本100% + 残業50% + 深夜25%）の乗率で算定されること。
  - 各割増手当ごとの端数処理が基発第150号と完全に合致し、中間丸めに起因する1円の差異も生じないこと。

---

#### [REQ-LABOR-004] 悲観的ロック（Pessimistic Lock）および一意制約に基づく給与確定トランザクション整合性
- **区分**: セキュリティおよび並行性制御 (Security & Concurrency)
- **概要**: 給与精算テーブルに初回確定レコードが存在しない場合でも二重確定レースコンディション（ファントム確定）を100%遮断するため、親テーブル（`store`）の先行悲観的ロック、複合一意制約（`uq_settlement_store_month`）、および行レベル排他ロック（`SELECT ... FOR UPDATE`）の三重防御線を確立する。
- **入力**:
  - `storeId` (店舗ID, BIGINT, 必須)
  - `targetMonth` (精算対象年月, VARCHAR(7), 'YYYY-MM' 形式, 必須)
- **処理**:
  1. **所有権検証・先行店舗排他ロックの単一トランザクション原子的実行（IDOR・TOCTOU完全防護）**: トランザクション開始直後、`SET LOCAL lock_timeout = '3s'` を設定し、`SELECT store_id FROM store WHERE store_id = :storeId AND owner_id = :principalId FOR UPDATE` を実行する。店舗行の存在と所有権を単一クエリで排他検証し、認可とロック獲得の間の競合窓（TOCTOU）を物理的に排除する（不一致時は即時 HTTP 403 遮断）。
  2. **ロック階層の固定と遡及打刻の凍結防護**: デッドロック防止および精算期間中の遡及打刻割り込みを防ぐため、システム全体のロック獲得順序を「`store` → `store_staff` → `payroll_settlement`」に厳格統一する。給与精算中は店舗ロックの保護下で対象月の全打刻・休憩登録が排他待機となり、精算対象データの決定論的凍結（Snapshot Consistency）を担保する。
  3. 給与精算テーブル（`payroll_settlement`）において `(store_id, target_month)` を指定して既存レコードを取得する（`SELECT ... FOR UPDATE`）。
  4. 初回確定時（レコード未存在時）：
     - PostgreSQLの複合一意制約（`CONSTRAINT uq_settlement_store_month UNIQUE (store_id, target_month)`）の保護下で、初期ステータス `'OPEN'` の精算ヘッダーレコードを安全に発行する。
  5. 締め状態の検証および不変スナップショット永続化：
     - ステータスが `'CONFIRMED'` または `'CLOSED'` の場合、確定済み給与の不正改変として `ALREADY_CONFIRMED`（HTTP 409）で即座に更新を拒否する。
     - 確定計算結果および参照契約のスナップショットを不変明細テーブル（`payroll_settlement_line`）へ永続化し、以後の打刻変更から給与計算結果を完全隔離する。
  6. 精算ヘッダーステータスを `'OPEN' → 'CONFIRMED'` へCAS更新（`WHERE settlement_id = ? AND status = 'OPEN'`）し、`affected rows == 1` を確認してコミットとともにロックを解放する。
- **出力**:
  - `settlementId` (確定給与精算PK, BIGINT)
  - `settlementStatus` (確定ステータス 'CONFIRMED', VARCHAR(20))
- **例外処理**:
  - オーナー以外のユーザーによる給与確定リクエストは `AccessDeniedException`（HTTP 403）を送出し、セキュリティ監査ログへ記録する。
  - 3秒のロック獲得待機がタイムアウトした場合（SQLSTATE `55P03`）、二重確定と誤認させず `SETTLEMENT_LOCK_BUSY`（HTTP 503 Service Unavailable、再試行ヘッダー付与）を返却する。
  - 複合一意制約衝突（SQLSTATE `23505`, 制約名 `uq_settlement_store_month`）または既に確定済みの場合は `DuplicateSettlementException`（HTTP 409 Conflict）を送出し、二重支払いを確実に阻止する。
- **完了基準 (DoD)**:
  - 給与確定レコードが初期状態（未作成）であっても、2件の並行確定リクエストが同時に実行された際に確実に1件のみが成功し、もう1件は重複衝突として HTTP 409 で遮断されること。
  - C#リンター規則に100%適合し、確定後の過去勤務データ変更が確定済み給与額に一切影響を与えないこと。
