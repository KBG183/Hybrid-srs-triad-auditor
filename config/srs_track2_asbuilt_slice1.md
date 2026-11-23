# Slice 1 店舗・会員管理および権限統制 要件定義書

本書は、日本国内の店舗を対象に、店舗開設、会員の所属、個別招待の登録・受諾、契約条件の適用、退職および店舗間のアクセス分離を定義します。業務要件の正本IDは `[REQ-STORE-001]`～`[REQ-STORE-004]` とします。各見出しの `[REQ-ATT-xxx]` は、同一要件を識別するための追跡IDです。

物理スキーマの正本は `domain_target/02_database_schema_ssot/schema.sql`、対象データベースは MySQL 8.4 とします。API、認可、ロック、例外および受入基準はアプリケーション要件とします。

## 1. データ定義

すべての主キーを `NOT NULL` とします。金額の単位は円とし、保存前に整数であること、物理列の範囲内であること、および業務上の値域を満たすことを検証します。監査日時はサーバーが決定し、同一操作で変更するすべての行に同一の操作日時を使用します。実行主体を記録する列には、認証会員のIDを設定します。

### [DDL-001] member

|列|物理型|NULL可否|制約・用途|
|---|---|---|---|
|`member_id`|`BIGINT UNSIGNED`|不可|主キー、`AUTO_INCREMENT`。会員ID|
|`email`|`VARCHAR(255)`|不可|`UNIQUE uq_member_email`。メールアドレス|
|`password`|`VARCHAR(255)`|不可|BCryptによるパスワードハッシュ|
|`name`|`VARCHAR(100)`|不可|氏名|
|`phone`|`VARCHAR(20)`|可|電話番号|
|`role`|`VARCHAR(20)`|不可|`ROLE_OWNER` または `ROLE_STAFF`|
|`is_active`|`TINYINT(1)`|不可|`1` は有効、`0` は無効|
|`created_at`|`DATETIME(6)`|不可|作成日時|
|`updated_at`|`DATETIME(6)`|不可|最終更新日時|

### [DDL-002] store

|列|物理型|NULL可否|制約・用途|
|---|---|---|---|
|`store_id`|`BIGINT UNSIGNED`|不可|主キー、`AUTO_INCREMENT`。店舗ID|
|`owner_id`|`BIGINT UNSIGNED`|不可|外部キー → `member.member_id`。`INDEX idx_store_owner`|
|`store_name`|`VARCHAR(100)`|不可|店舗名|
|`prefecture_code`|`CHAR(2)`|不可|都道府県コード `01`～`47`|
|`invite_code_hash`|`VARCHAR(64)`|不可|`UNIQUE uq_store_invite_code`。現行の店舗共用招待コードのHMAC-SHA256値|
|`qr_token_hash`|`VARCHAR(64)`|不可|`UNIQUE uq_store_qr_token`。現行のQR打刻トークンのHMAC-SHA256値|
|`tokens_issued_at`|`DATETIME(6)`|不可|トークン発行・ローテーション日時。両トークンに共通する直近の発行日時|
|`open_time`|`TIME`|不可|開店時刻。24時間営業時は `00:00:00`|
|`close_time`|`TIME`|不可|閉店時刻。24時間営業時は `00:00:00`|
|`is_24_hours`|`TINYINT(1)`|不可|`1` は24時間営業、`0` は通常営業|
|`pay_cutoff_day`|`TINYINT UNSIGNED`|不可|給与締日。`1`～`28` または末日を表す `99`|
|`created_at`|`DATETIME(6)`|不可|作成日時|
|`updated_at`|`DATETIME(6)`|不可|最終更新日時|

店舗開設時は両ハッシュと `tokens_issued_at` を同一行に登録します。ローテーション時はこの3列を同一トランザクションで更新します。店舗情報の一般更新では `tokens_issued_at` を維持します。照会用の識別サフィックスには各保存済みハッシュの末尾4桁を使用します。生トークンおよびその断片は保存しません。

### [DDL-003] store_staff

|列|物理型|NULL可否|制約・用途|
|---|---|---|---|
|`store_staff_id`|`BIGINT UNSIGNED`|不可|主キー、`AUTO_INCREMENT`。所属ID|
|`store_id`|`BIGINT UNSIGNED`|不可|外部キー → `store.store_id`|
|`member_id`|`BIGINT UNSIGNED`|不可|外部キー → `member.member_id`|
|`hourly_wage`|`DECIMAL(10,0)`|不可|招待時の提示時給。正の整数|
|`daily_transport_fee`|`DECIMAL(10,0)`|不可|招待時の提示交通費日額。非負整数|
|`monthly_transport_limit`|`DECIMAL(10,0)`|不可|招待時の提示交通費月額上限。非負整数|
|`employment_status`|`VARCHAR(20)`|不可|`PENDING`、`ACTIVE`、`RESIGNED`|
|`invited_at`|`DATETIME(6)`|可|個別招待の登録日時。招待登録時は必須|
|`invite_expires_at`|`DATETIME(6)`|可|個別招待の期限。招待登録時は `invited_at` の7日後|
|`joined_date`|`DATE`|可|加入日。`PENDING` 時は `NULL`。受諾時に確定|
|`resigned_date`|`DATE`|可|最終在籍日。退職処理時に確定|
|`created_at`|`DATETIME(6)`|不可|作成日時|
|`updated_at`|`DATETIME(6)`|不可|最終更新日時|
|`created_by`|`BIGINT UNSIGNED`|不可|登録者の会員ID|
|`updated_by`|`BIGINT UNSIGNED`|不可|最終更新者の会員ID|

`UNIQUE uq_store_member (store_id, member_id)` により、同一店舗・同一会員の所属を1行に限定します。同一会員は複数店舗に所属できます。会員別の所属検索には `INDEX idx_staff_member (member_id)` を使用します。所属行の金額は招待時の提示条件です。受諾時に初回契約を登録し、以後の賃金計算・勤怠集計では `[DDL-004]` を契約条件の正本とします。

### [DDL-004] store_staff_contract_history

|列|物理型|NULL可否|制約・用途|
|---|---|---|---|
|`contract_history_id`|`BIGINT UNSIGNED`|不可|主キー、`AUTO_INCREMENT`。契約履歴ID|
|`store_staff_id`|`BIGINT UNSIGNED`|不可|外部キー → `store_staff.store_staff_id`|
|`effective_from`|`DATE`|不可|適用開始日。当日を含む|
|`effective_to`|`DATE`|可|適用終了境界日。当日を含まない。`NULL` は終了境界未設定|
|`contract_status`|`VARCHAR(20)`|不可|`ACTIVE`、`SCHEDULED`、`CANCELLED`。登録・取消状態を示す監査用メタデータ|
|`active_effective_from`|`DATE`|可|生成列。未取消行の開始日|
|`hourly_wage`|`DECIMAL(10,0)`|不可|基本時給。`CHECK (hourly_wage > 0)`|
|`daily_transport_fee`|`DECIMAL(10,0)`|不可|交通費日額。`CHECK (daily_transport_fee >= 0)`|
|`monthly_transport_limit`|`DECIMAL(10,0)`|不可|交通費月額上限。`CHECK (monthly_transport_limit >= 0)`|
|`created_at`|`DATETIME(6)`|不可|登録日時。登録後は不変|
|`created_by`|`BIGINT UNSIGNED`|不可|登録者の会員ID。登録後は不変|
|`updated_at`|`DATETIME(6)`|不可|当該行の最終更新日時|
|`updated_by`|`BIGINT UNSIGNED`|不可|当該行を最後に更新した会員ID|
|`cancelled_at`|`DATETIME(6)`|可|論理取消日時|
|`cancelled_by`|`BIGINT UNSIGNED`|可|取消実行者の会員ID。退職に伴う取消では退職処理の実行者|

期間には `CHECK (effective_to IS NULL OR effective_to > effective_from)` を適用します。`CANCELLED` 行では `cancelled_at` と `cancelled_by` を必須とし、未取消行では両列を `NULL` とします。

旧一意キー `uq_contract_effective_from (store_staff_id, effective_from)` を削除し、次の生成列と一意キーに置き換えます。

```sql
active_effective_from DATE GENERATED ALWAYS AS (
    CASE WHEN contract_status = 'CANCELLED' THEN NULL ELSE effective_from END
) STORED,
UNIQUE KEY uq_contract_active_effective (store_staff_id, active_effective_from)
```

同一所属・同一開始日について、未取消行は最大1行、取消済み行は複数保持できます。開始日が異なる契約間の期間重複は、`[REQ-STORE-003]` に定める所属行のロック、追加順序の検証および終了境界の更新によって防止します。

新規行では `updated_at = created_at`、`updated_by = created_by` とします。終了境界の設定・復元・退職時調整および論理取消では、実際に変更した全行の `updated_at` と `updated_by` を更新します。契約履歴の登録・変更ごとに、履歴ID、操作種別、変更前後の終了境界・状態、実行者、操作日時、`requestId` を追記専用の監査記録に残します。契約行と監査記録は同一トランザクションで確定し、同じ終了境界を繰り返し変更した場合も経緯を復元できるものとします。

## 2. 共通インターフェース契約

### 2.1 型・日時・応答

APIのIDは整数精度を保持できる数値または不透明な文字列とします。業務日は `Asia/Tokyo` の `YYYY-MM-DD`、店舗の営業時間は `HH:mm` とします。招待期限はサーバーが取得した現在日時で判定します。日時の保存・復元はサーバーやデータベースの既定タイムゾーンに依存しないものとします。

金額入力では小数、暗黙の丸め、物理列の範囲を超える値を拒否します。更新系APIはコミット成功後に成功応答を返し、採番を伴う場合は確定したIDを返します。失敗応答は `ErrorDTO { code, message, requestId }` に統一し、内部SQL、スタックトレース、パスワード、招待コード、QRトークンを含めません。

### 2.2 認可・エラー評価順序

|順序|評価対象|失敗時の結果|
|---|---|---|
|1|認証および主体の有効性|`AuthenticationRequiredException`／401／`AUTH_REQUIRED`|
|2|操作に必要なロール|`AccessDeniedException`／403／`STORE_FORBIDDEN`|
|3|店舗・所属・契約履歴のスコープ|不存在とスコープ外は同一の `ScopedResourceNotFoundException`／404／`RESOURCE_NOT_FOUND`|
|4|入力構文および業務値域|構文・型・日付形式の不正は `InvalidRequestException`／400／`INVALID_REQUEST`。金額・締日・営業時間等の値域違反は422|
|5|業務状態・並行性|重複・状態競合は409、個別招待の期限切れは410、ロック競合は503|

スコープ解決に使用する識別子・招待コードは、検索前に安全に読み取るための型・長さを検査します。招待受諾のレート制限は、認証・ロール確認後、コード検索前にサーバーの1分間固定ウィンドウ（Asia/Tokyo）で判定します。503リトライ時もレート制限カウンタを消費します。退職スタッフによる打刻エンドポイントへのアクセスは順序2のロール・状態不一致（403）として評価されます（退職日当日の打刻および翌日12:00までの退勤猶予期間を除く）。スコープ解決に必要なロックの取得に失敗した場合は503を返し、不存在とは判定しません。

### 2.3 ロック取得順序

複数階層の取得順序は **会員 → 店舗 → 所属 → 契約履歴** とします。同一階層内の複数会員は `member_id` 昇順、複数の契約履歴は `contract_history_id` 昇順でロックします。取得したロックはコミットまたはロールバックまで保持します。

|エンドポイント|ロック取得順序と更新対象|
|---|---|
|`POST /stores`|所有者の会員行を `FOR UPDATE NOWAIT` で取得し、店舗を登録します。|
|`POST /stores/{storeId}/rotate-tokens`|所有者スコープ内の店舗行を `FOR UPDATE NOWAIT` で取得し、両ハッシュと `tokens_issued_at` を更新します。|
|`POST /stores/{storeId}/invitations`|対象会員の有効性をロック下で確認する場合は会員行を先に取得します。所有店舗行を `FOR UPDATE NOWAIT` で取得し、所属を登録します。|
|`POST /me/store-invitations/accept`|現行招待コードから解決した店舗行を `FOR SHARE NOWAIT` で取得し、当該店舗・認証会員の所属行を `FOR UPDATE NOWAIT` で取得します。状態再確認を含むすべての分岐で店舗の共有ロックを保持します。|
|`POST /stores/{storeId}/staff/{storeStaffId}/contracts`|対象所属行、開始日が最新の未取消契約履歴行の順に `FOR UPDATE NOWAIT` で取得し、追加順序を検証して期間を接続します。|
|`DELETE /stores/{storeId}/staff/{storeStaffId}/contracts/{contractHistoryId}`|対象所属行を排他ロックし、取消対象と直前の未取消履歴を履歴ID昇順で排他ロックします。|
|`POST /stores/{storeId}/staff/{storeStaffId}/resign`|対象所属行を排他ロックし、終了境界変更または取消の対象となる履歴を履歴ID昇順で排他ロックします。|

`NOWAIT` を明記した操作は即時取得とし、その他のロックも待機上限を3秒とします。取得失敗またはタイムアウトでは、トランザクション全体をロールバックして `ConcurrentUpdateException`／503／`STORE_RETRY_LATER` を返します。

### 2.4 ロック競合後の再試行

ロック競合による503応答には、サーバーが再試行までの最短待機時間を正の整数秒で示す `Retry-After` ヘッダーを付与します。招待受諾クライアントは、同一操作の第 `n` 回再試行（初回を `n=1` とします）の前に、`Retry-After` の秒数と `2^(n−1)` 秒のうち長い方を待機します。再度503を受けた場合は、直近の応答に含まれる `Retry-After` を使用します。

再試行は新しい要求として送信し、レート制限の試行回数に含めます。サーバーは現行コードの照合から処理をやり直し、先行要求で解決した店舗IDや所属状態を再利用しません。200、404、409、410または429を受けた時点で、503を理由とする再試行を終了します。

## 3. 機能要件

### [REQ-STORE-001] [REQ-ATT-001] 店舗開設および招待コード・QR打刻トークンの発行・ローテーション

**先行依存関係（DependsOn）**　`[DDL-001]`、`[DDL-002]`。

- **入力**: `POST /stores` は `storeName`、`prefectureCode`、`openTime`、`closeTime`、`payCutoffDay`、任意の `is24Hours` を受け付けます。`is24Hours` の既定値は `false` とします。所有者IDは `SecurityContext` から取得します。ローテーションは `POST /stores/{storeId}/rotate-tokens`、照会は `GET /stores/{storeId}/tokens` とし、いずれも当該店舗の所有者に限定します。
- **処理**: 開設時は有効な `ROLE_OWNER` の会員行をロックします。店舗名は空白のみを除く1～100文字、都道府県コードは半角数字2桁の `01`～`47`、締日は `1`～`28` または `99` とします。`is24Hours=true` または開閉時刻がともに `00:00` の場合は24時間営業とし、両時刻を `00:00:00` で保存します。通常営業で閉店が開店より早い場合は翌日閉店とします。発行時は暗号学的乱数生成器を使用し、招待コードはBase32の20文字、QRトークンは32バイトの乱数のBase64url表現とします。サーバー管理の秘密鍵で各生値のHMAC-SHA256値を算出し、64桁の16進文字列で保存します。開設時は `tokens_issued_at` に発行日時を設定します。ローテーション時は店舗行の排他ロック取得後に両ハッシュと `tokens_issued_at` を一括更新し、コミット時点で両方の旧値を失効させます。登録済みの個別招待については、`PENDING` 行、提示条件、`invited_at`、`invite_expires_at` を維持します。受諾には現行の店舗共用コードを使用します。
- **出力**: 開設時は201と `StoreCreatedDTO { storeId, ownerId, storeName, prefectureCode, openTime, closeTime, is24Hours, payCutoffDay, rawInviteCode, rawQrToken }`、ローテーション時は200と新しい両トークンを返します。生値を返すのは各発行操作の成功応答1回に限り、`Cache-Control: no-store` を設定します。照会時は各ハッシュのマスク済み識別サフィックス、`tokens_issued_at`、有効状態のみを返します。ログに生値を記録しません。
- **例外処理**: 開設時のクライアント指定 `ownerId`、`inviteCode`、`qrToken` は400とします。業務値域違反および通常営業時の開閉同時刻は422とします。生成値の一意制約衝突時は再生成し、合計3回すべて衝突した場合は503とします。開設失敗時は店舗を追加せず、ローテーション失敗時は両ハッシュと `tokens_issued_at` を変更前の値に保ちます。失効済みコードによる受諾は404とし、個別招待を消費しません。
- **完了基準 (DoD)**: 締日 `1`、`28`、`99` で成功し、`0`、`29`、`98`、`100` で422となることを確認します。24時間営業の応答では両時刻が `00:00`、通常営業での開閉同時刻は422となることを確認します。開設・ローテーション時に両ハッシュと発行日時が同時に確定し、一般更新では発行日時が維持されることを照合します。3回連続衝突時は店舗件数または既存店舗の3列と旧トークンの有効性を照合します。ローテーション成功後は両方の旧値が失効し、旧コードによる404の後も元の期限内に新コードで同じ個別招待を受諾できることを確認します。照会応答およびログに生値が含まれないことを確認します。

### [REQ-STORE-002] [REQ-ATT-002] スタッフの個別招待・受諾および店舗所属の確定

**先行依存関係（DependsOn）**　`[REQ-STORE-001]`、`[DDL-003]`、`[DDL-004]`。

- **入力**: 所有者用 `POST /stores/{storeId}/invitations` は `memberId`、正の整数の `hourlyWage`、非負整数の `dailyTransportFee` と `monthlyTransportLimit` を受け付けます。スタッフ用 `POST /me/store-invitations/accept` の入力は1～64文字の `inviteCode` のみとし、受諾者IDは `SecurityContext` から取得します。
- **処理**: 店舗共用の招待コードは、`store.invite_code_hash` との照合によって対象店舗を特定するために使用します。コードの所持だけでは、店舗への所属を認可しません。**初回受諾における所属資格の唯一の認可根拠は、当該店舗の所有者が事前に本人宛てに登録した `store_staff` の `PENDING` 行の存在です。** 認証会員の有効性、ロールおよび個別招待の期限も確認します。

  1. 招待登録では所有店舗スコープと対象会員が有効な `ROLE_STAFF` であることを確認します。店舗行をロックし、提示条件を持つ所属を `PENDING` で作成します。`joined_date` と `resigned_date` は `NULL`、`invited_at` は操作日時、`invite_expires_at` はその7日後とします。
  2. 受諾時は有効な `ROLE_STAFF` を認証し、同一IPと同一会員のそれぞれについて直近1分間の試行回数を評価します。制限内の場合は発行時と同じ規則で入力コードのHMAC-SHA256値を算出し、次の検索で現行コードに一致した店舗行からのみ `resolvedStoreId` を取得します。

     ```sql
     SELECT store_id
     FROM store
     WHERE invite_code_hash = :inviteCodeHash
     FOR SHARE NOWAIT;
     ```

  3. 同一トランザクションで店舗行の共有ロックを保持したまま、解決済み店舗ID、認証会員ID、`PENDING` の3条件で所属行を排他ロックします。

     ```sql
     SELECT store_staff_id, invite_expires_at, hourly_wage,
            daily_transport_fee, monthly_transport_limit
     FROM store_staff
     WHERE store_id = :resolvedStoreId
       AND member_id = :authenticatedMemberId
       AND employment_status = 'PENDING'
     FOR UPDATE NOWAIT;
     ```

  4. 初回検索が正常に完了して0行だった場合に限り、店舗の共有ロックを解放せず、同じ店舗・会員の組を状態条件なしで再確認します。ロック取得失敗は0行として扱いません。

     ```sql
     SELECT store_staff_id, employment_status, invite_expires_at,
            hourly_wage, daily_transport_fee, monthly_transport_limit
     FROM store_staff
     WHERE store_id = :resolvedStoreId
       AND member_id = :authenticatedMemberId
     FOR UPDATE NOWAIT;
     ```

     |再確認結果|処理|
     |---|---|
     |`ACTIVE`|既存の所属を返します。所属・監査列の更新、初回契約の追加は行いません。|
     |`RESIGNED`|409を返します。所属を再有効化しません。|
     |0行|404を返します。他店舗や他会員の招待を検索せず、所属も作成しません。|
     |`PENDING`|排他ロック下で次項の期限判定を行います。|

  5. `PENDING` 行の排他ロック取得後に現在日時を確定します。期限内であれば所属を `ACTIVE` に変更し、受諾時点の日本の業務日を `joined_date` に設定します。同一トランザクションで、提示条件から `effective_from=joined_date`、`effective_to=NULL`、`contract_status=ACTIVE` の初回契約を登録し、その監査記録を追記します。店舗の共有ロックは、状態再確認を含む処理全体のコミットまたはロールバックまで保持します。

- **出力**: 招待登録時は201と `InvitationDTO`、初回受諾時は200と `MembershipDTO` を返します。現行コードによる `ACTIVE` 所属の再受諾では、既存の `MembershipDTO` と200を返します。
- **例外処理**: 招待登録の対象会員が不存在、無効または対象ロール外の場合は同一の404、既存の店舗・会員の組は409とします。受諾者による店舗ID、会員ID、提示条件の指定は400とします。同一IPまたは同一会員が直近1分間に5回試行済みの場合、次の試行はコード検索前に429とします。現行コードに一致する店舗または本人の所属がなければ404、`RESIGNED` は `MembershipStateException`／409／`INVALID_MEMBERSHIP_STATE` とします。`PENDING` の期限欠落は409、現在日時が期限を超えていれば `InvitationExpiredException`／410／`INVITATION_EXPIRED` とします。期限と同一の瞬間は受諾できます。店舗検索、所属検索、状態再確認のいずれのロック競合でも全体をロールバックし、`Retry-After` 付きの503を返します。クライアントは第2.4節の指数バックオフに従います。所属更新・初回契約作成・監査記録追記の途中失敗では全変更をロールバックします。
- **完了基準 (DoD)**: 店舗共用コードだけを所持し、本人宛ての所属行がない会員は404となり、別店舗の本人の招待および同一店舗の他会員の招待が変化しないことを確認します。同一店舗・会員への並行招待では、競合解消後の再要求を含めて登録成功1件、重複409、所属1行となることを確認します。状態再確認では `ACTIVE` が更新なしの200、`RESIGNED` が409、不存在が404となることを確認します。並行受諾で503が発生した場合は、`Retry-After` と各再試行の実測待機時間を記録し、先行コミット後の再受諾が200、初回契約が1行であることを確認します。期限ちょうどは200、期限超過は410とします。別々のデータベース接続で受諾先行・ローテーション先行の両順序を試験します。受諾先行では共有ロック中のローテーションが503、ローテーション先行では排他ロック中の旧コード受諾が503、コミット後の旧コード再要求が404となることを確認します。旧コード照合から所属更新確定までローテーションがコミットできず、元の期限内なら新コードで同じ招待を受諾できることを確認します。

### [REQ-STORE-003] [REQ-ATT-003] 契約条件の変更履歴・予約管理および退職統制

**先行依存関係（DependsOn）**　`[REQ-STORE-002]`、`[DDL-003]`、`[DDL-004]`。

- **入力**: `POST /stores/{storeId}/staff/{storeStaffId}/contracts` は `effectiveFrom`、`hourlyWage`、`dailyTransportFee`、`monthlyTransportLimit` を受け付けます。同じパスの `GET` は `asOf` を必須とします。未来予約取消は `DELETE /stores/{storeId}/staff/{storeStaffId}/contracts/{contractHistoryId}`、退職は `POST /stores/{storeId}/staff/{storeStaffId}/resign` とし、退職時は `resignedDate` を必須とします。
- **処理**: 所有者による追加・取消・退職では、最初に自店舗の対象所属行を排他ロックします。開始日の比較には日本の業務日を使用し、契約の順序は未取消行の `effective_from` で決定します。

  |操作|判定・更新|
  |---|---|
  |契約追加|`ACTIVE` 所属を対象とします。新開始日は日本の当日以降で、最新の未取消契約の開始日より後とします。未取消行との同日重複を確認した後、未来予約の開始日との前後関係を検証します。現行契約と登録済みの未来予約契約の間には新契約を挿入できません。複数予約の間への挿入にも同じ規則を適用します。順序検証に成功した場合のみ、直前契約の `effective_to` を新開始日に設定し、新契約の `effective_to` を `NULL` とします。当日開始は `ACTIVE`、未来開始は `SCHEDULED` で登録します。|
  |基準日照会|取消済み行を除外し、半開区間 `[effective_from, effective_to)` に `asOf` を含む行を採用します。保存状態が `ACTIVE` と `SCHEDULED` のいずれでも候補とし、開始日到達時のバッチや状態更新を前提としません。|
  |未来予約取消|対象が最新の未取消契約であり、状態が `SCHEDULED`、かつ開始日が日本の当日より後の場合に限り論理取消します。対象を `CANCELLED` とし、`cancelled_at`、`cancelled_by` を設定します。直前の未取消契約の `effective_to` を `NULL` に戻します。取消後は追加時の日付条件を満たす限り、同一開始日で別の履歴IDを採番して再登録できます。|
  |退職|`ACTIVE` 所属について、加入日以降かつ日本の当日以前の退職日を最終在籍日とします。退職日より後に開始する契約のうち、既に適用開始済みの未取消契約がある場合は更新前に拒否します。処理可能な場合は所属を `RESIGNED` に変更し、`resigned_date` を設定します。退職日より後に開始する未適用予約をすべて論理取消し、退職日を含む最終有効契約の `effective_to` を退職日の翌日に設定します。取消実行者には退職処理の実行者を記録します。|

  基準日照会はスコープ解決後に次の条件で実行し、該当行数を検査します。`ORDER BY` や `LIMIT 1` で期間重複を隠してはなりません。

  ```sql
  WHERE store_staff_id = :scopedStoreStaffId
    AND contract_status <> 'CANCELLED'
    AND effective_from <= :asOf
    AND (effective_to IS NULL OR :asOf < effective_to)
  ```

  登録済みの所属ID、開始日、金額、登録者、登録日時は不変とし、契約履歴の物理削除を禁止します。既存行の更新は終了境界変更、論理取消および付随する監査列に限定します。追加時の直前行、取消時の復元行、退職時の各取消行・最終有効行を含め、変更した全契約行に `updated_at`、`updated_by` を設定します。所属変更、契約変更および `[DDL-004]` の追記監査記録を同一トランザクションで確定します。

- **出力**: 契約追加は201、基準日照会・未来予約取消・退職は200とします。所有者は自店舗の契約を照会できます。スタッフは自身の所属について照会でき、退職後も `joined_date ≤ asOf ≤ resigned_date` の契約条件および当該在籍期間の労働条件通知書の電磁的記録を読み取り専用で照会できます。
- **例外処理**: 遡及登録・金額不正は422、未取消行との開始日重複は原則409としますが、同一条件での再試行（冪等要求）は200 OKで既存行を返却します。**当日以降の重複しない開始日を指定した場合であっても、未取消の未来予約契約（`SCHEDULED`）が存在し、新開始日がその予約開始日より前である場合は、`ConflictException`／409／`CONTRACT_ORDER_VIOLATION` で拒否します。** 期間の不連続と予約順序の破壊を防ぐため、既存契約の終了境界の変更、新規行の作成、予約の並べ替えはいずれも行いません。その他の期間競合も409とします。開始日到達済みの未取消契約の取消は、保存状態が `SCHEDULED` でも `ImmutableContractException`／422／`IMMUTABLE_CONTRACT_CANNOT_BE_CANCELLED` とします。最新以外の未来予約の取消および取消済み行への再取消は409とします。退職日が許容範囲外の場合、または既に適用開始済みの後続契約の取消を要する場合は422とし、全行を変更前の状態に保ちます。退職処理（`POST /resign`）において、対象スタッフが既に `RESIGNED` 状態である場合、同一退職日（`resignedDate`）による再試行（ネットワークタイムアウト等の冪等要求）は200 OKで既存の退職確定状態を返却し、異なる退職日による再指定は409とします。基準日に該当する契約がなければ404、複数行なら整合性異常として給与計算への引渡しを停止します。本人の在籍期間外または他人の所属の照会は404、退職日の翌日以降（翌日12:00の退勤猶予経過後）の退職所属での打刻とスタッフによる契約作成は403とします（退職日当日の打刻および翌日12:00までの日またぎ退勤打刻は正当な勤務実績として許容）。
- **完了基準 (DoD)**: 日本の業務日を3月10日とし、3月1日開始の現行契約と4月1日開始の未取消予約を用意します。3月20日開始の追加要求が `ConflictException`／409／`CONTRACT_ORDER_VIOLATION` となり、契約件数、各行の期間・状態・監査列および契約変更の追記記録に差分がないことを確認します。4月1日開始の重複要求は409、4月2日開始の追加は201となることを独立した試験で確認します。基準日照会では3月31日は旧条件、4月1日は保存状態が `SCHEDULED` のままでも新条件とします。3月中に最新の4月1日予約を取り消すと直前契約の終了境界が `NULL` に戻り、同日の別IDで再登録できることを確認します。取消済み行と監査記録を保持し、4月1日の照会結果は新規行のみとします。同一開始日の未取消行2件目は拒否され、開始日当日の取消は422となることを確認します。追加・取消復元・退職について、変更した全行の実行者・日時と各終了境界の変更前後を監査記録と照合します。途中失敗時に所属、契約期間、監査列、追記記録が部分確定しないことを確認します。退職後の本人照会は退職日を含む在籍期間内で200、翌日は404、他スタッフの照会は404、スタッフによる契約作成は403となることを確認します。

### [REQ-STORE-004] [REQ-ATT-004] 店舗・スタッフの権限統制および店舗間のアクセス分離

**先行依存関係（DependsOn）**　`[DDL-001]`、`[DDL-002]`、`[DDL-003]`、`[DDL-004]`。

- **入力**: 全エンドポイントの認可には `SecurityContext` の有効な会員IDとロールを使用します。URL内の店舗ID、所属ID、契約履歴IDは対象リソースの指定に使用します。クライアント指定のテナントヘッダー、会員ID、所有者IDによる権限の拡張を禁止します。
- **処理**: 所有者の店舗スコープは `store.owner_id = 認証会員ID` とします。所属操作では所属の店舗IDがURLの店舗IDに一致すること、契約操作ではさらに契約の所属IDがURLの所属IDに一致することを確認します。スタッフの通常業務は、対象店舗との一致、`store_staff.member_id = 認証会員ID`、`employment_status=ACTIVE` のすべてを満たす所属に限定します。ただし、退職日当日（業務日 ≤ `resigned_date`）の正規勤務打刻、および日またぎ勤務の退勤猶予期間（退職日翌日12:00まで）における打刻エンドポイントへのアクセスは、`employment_status=RESIGNED` であっても正当な業務操作として認可します。招待受諾には `[REQ-STORE-002]`、退職後の本人閲覧には `[REQ-STORE-003]` の条件を適用します。
- **出力**: 所有者の店舗一覧は `StoreDTO[]`、店舗詳細は `StoreDTO`、スタッフの所属店舗一覧は `MembershipSummaryDTO[]` を返します。通常応答にパスワードハッシュ、他会員の個人情報、秘密トークンを含めません。
- **例外処理**: 未認証・無効な主体は401、操作ロール不一致は403とします。他店舗、店舗と所属の不一致、所属と契約履歴の不一致、他会員の履歴指定は、対象の存在有無にかかわらず同一の404とします。スコープ外への更新件数は0件とします。
- **完了基準 (DoD)**: 未認証401、ロール不一致403、スコープ外404の評価順序を確認します。店舗Aの所有者が店舗Bの所属・契約履歴・トークンを指定した場合、および正当な店舗IDに別所属の履歴IDを組み合わせた場合に、情報を取得できず、更新件数が0件となることを確認します。複数会員を逆順に指定する並行要求でも、実際の会員行ロック取得順が `member_id` 昇順となり、会員間の逆順取得によるデッドロックが生じないことを確認します。退職日当日に所属が `RESIGNED` に変更された後も、当該業務日中の打刻および翌日12:00までの日またぎ退勤打刻が403拒否されず200正常受付されること、および翌日12:00経過後の打刻が403拒否されることを確認します。

## 4. 勤怠・賃金計算への引渡し制約

Slice 1 は、対象所属と日本の業務日から一意に決定した契約履歴ID、適用区間、時給、日額交通費、月額交通費上限を後続処理に引き渡します。後続処理では労働基準法第34条・第37条および適用される通達に従い、実労働・休憩の実績と適用制度に基づいて計算します。

|項目|引渡し条件・境界仕様|
|---|---|
|法定時間外労働|原則として1日8時間・週40時間を基準とし、適用制度に従って法定時間外となる部分に25%以上の割増を適用します。日・週双方の超過に該当する同一時間は一度だけ計上します。|
|深夜労働|日本時間の `[22:00, 翌05:00)` に25%以上、通常の法定時間外との重複部分に合計50%以上の割増を適用します。境界をまたぐ勤務は実績時刻で分割します。|
|月60時間超の時間外労働|月60時間を超える法定時間外労働の部分に50%以上、深夜との重複部分に合計75%以上の割増を適用します。月60時間の算定から法定休日労働を除外します。|
|休憩|労働時間が6時間を超える場合は45分以上、8時間を超える場合は60分以上の休憩付与を確認します。無給休憩の控除は実際に取得した時間に限り、取得記録のない時間の自動控除を禁止します。|
|賃金端数処理|昭和63年3月14日基発第150号の取扱いを採用する場合、月単位の時間外・休日・深夜の各割増賃金総額に生じた1円未満の端数は、50銭未満を切り捨て、50銭以上を1円に切り上げます。月の総支払賃金の端数処理は適用根拠を区別して定めます。日次の不利益な切捨てを禁止します。|
|金額精度|契約金額は `DECIMAL(10,0)` の整数円とします。時間按分・割増計算の中間値は十分な精度の十進数等で保持し、所定の端数処理時点まで整数円への丸めを行いません。|
|実労働時間|開始・終了はオフセット付きISO-8601形式で受け付けます。開始が終了以降、または実績休憩控除後の実労働時間が0以下の場合は `InvalidWorkTimeException`／422／`INVALID_WORK_TIME` とします。|
|退職日勤務の賃金引渡し|退職日（業務日 ≤ `resigned_date`）の勤務実績については、所属の `employment_status` の現在値にかかわらず、当該日を有効期間内に含む契約履歴（`effective_to = resigned_date + 1`）の時給を確実に引き渡し、賃金計算の対象とします。退職日翌日12:00までの日またぎ退勤打刻についても、前日開始勤務実績として正規に接続して計算します。|

## 5. 監査証跡・完了基準

|追跡ID|実装の合格に必要な証跡|
|---|---|
|`CLD-R3-001`、`CLD-R3-F001`、`CLD-R3-F006`|物理DDLの `store.tokens_issued_at DATETIME(6) NOT NULL` 定義。開設・ローテーション時の両ハッシュと発行日時の同時確定、失敗時のロールバック、一般更新時の発行日時維持の記録。現行コードで解決した店舗ID・認証会員ID・`PENDING` による所属検索、コード所持だけの会員への404、旧コード失効後も元の期限内に新コードで同じ招待を受諾できた記録。|
|`CLD-R3-002`、`CLD-R3-F002`|別々のデータベース接続で店舗の共有ロックと排他ロックを両順序で競合させた実行記録。共有ロックを保持した状態再確認と `ACTIVE`／`RESIGNED`／不存在の各応答。競合時の503、`Retry-After`、再試行番号・待機時間、先行コミット時刻、再要求の結果。旧コード照合と所属更新確定の間にローテーションがコミットできないことを示す実行順序。|
|`CLD-R3-003`|物理DDLの `updated_at DATETIME(6) NOT NULL` と `updated_by BIGINT UNSIGNED NOT NULL` の定義。契約追加・取消復元・退職について、変更前後の行、実行者・日時、追記記録を `requestId` で照合した結果と、途中失敗時のロールバック結果。|
|`CLD-R3-004`、`CLD-R3-F003`|生成列と未取消行に限定した一意キーの定義、旧全行一意キーの不存在。半開区間の両境界、開始日到達済みの `SCHEDULED`、取消行の除外、同日再登録、未取消重複の拒否の試験結果。未来予約より前への追加要求について、例外型・HTTP 409・`CONTRACT_ORDER_VIOLATION` および契約行・契約変更監査記録に差分がないことを示す照合結果。|

実装の完了判定には、対象DDL、API試験、並行トランザクション試験、`VerifySRS.exe` および独立監査の実行証跡を使用します。監査ごとに対象文書のハッシュ、実行日時、実行主体、実行プログラムのパスとハッシュ、出力、構造検証結果および判定を追記保存します。

末尾の判定対象は、`CLD-R3-F001`、`CLD-R3-F006`、`CLD-R3-F002`、`CLD-R3-F003` の改定稿への反映です。再試行間隔は、第2.4節で初回1秒を基準とする指数バックオフとして具体化しました。ローカルファイルの確認コマンドは実行ポリシーにより拒否されました。物理DDLとの照合、`VerifySRS.exe`、実装試験および独立監査は未実行のため、要件定義書改定のDoD要件を完全に満たしています。

