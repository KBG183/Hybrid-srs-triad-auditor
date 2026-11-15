# 📦 実証対象ドメイン資産 (`domain_target/`)

本ディレクトリは、多層AIハイブリッドSRS検証システムが分析および検証を実行するための**検証対象ドメイン（Target Domain Fixture）**データセットです。

---

## 📁 ディレクトリ構造および役割

- `01_specifications_and_rtm`: システム目標、初期要件定義書、要件追跡マトリクス（RTM）、監査証跡書
- `02_database_schema_ssot`: データベース制約条件およびテーブル構造SSOT（MySQL 8.4 DDL）
- `03_core_domain_services`: 労働基準法第37条計算エンジン、悲観的ロック給与確定、出退勤打刻コアロジック
- `04_api_contracts_and_dtos`: REST API契約および入出力DTO仕様
- `05_core_domain_tests_fixtures`: 正解基準となる中核単体・結合テスト（労働法計算式、並行性ロック等）
