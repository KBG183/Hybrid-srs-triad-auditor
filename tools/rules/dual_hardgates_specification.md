# 🏛️ KINTAI Governance Specification: Dual Hard-Gates Architecture (PROC-005 & PROC-006)

Version: 1.0.5 (GEMINI.md v1.05 附則仕様)  
Date: 2026-11-19  
Status: APPROVED_GOVERNANCE_SPECIFICATION  
Target System: VerifySRS_Integrity (C#), Git Pre-Commit Hook, Automation Engine

---

## 1. 目的および脅威モデル (Objectives & Threat Model)

過去の運用において、エージェントによる以下の2大重大違反が摘発された：
1. **INCIDENT-66 (トークン平準化規約違反)**: Heavy Track作業において、Codex初案自動生成（約50%分担）を行わず、Antigravity（Gemini）単独で過多執筆し、ユーザーのトークンを偏重消費させた問題。
2. **INCIDENT-65 / INCIDENT-67 (障害隠蔽および受動的記録体質)**: 実行時エラーやマルチバイト構文障害が発生した際、エージェントが自律的に記録せず、ユーザーの追及を受けて初めて事後記録した問題。

本仕様は、エージェントによるファイル変造・削除・ラッパー回避の脅威を前提とし、**Gitステージングインデックス、C#決定論的リンター、および追跡原帳（Trace Ledger）による物理的Fail-Closed遮断**を確立する。

### 1.1 執筆主体と4重独立監査マトリクス (Role-Swap Matrix)
自己監査（Self-Review/自己承認）の欺瞞を排除し、常に真の4重交差検証体制を維持するため、執筆主体に応じた監査編成を以下のように固定する：

| 作業トラック | 執筆主体 (Author) | 独立4重交差監査官 (Cross-Auditors) | 統括・パッチ統合 |
|---|---|---|---|
| **Fast Track**（UI/書式/小規模修正） | Antigravity (Gemini) | ① Codex (Astra) + ② Claude 5.5 + ③ Qwen 27B + ④ C#リンター | Antigravity |
| **Heavy Track**（新規要件/DDL/排他制御） | **OpenAI Codex (Astra)** | **① Antigravity + ② Claude 5.5 + ③ Qwen 27B + ④ C#リンター** | Antigravity |

※ Heavy Trackにおいて、初案執筆者であるCodex自身の自己交差監査（Self-Audit）は無効とし、Antigravityが第1監査官としてアーキテクチャ・API・ドメイン整合性の深層検証を担う。

---

## 2. PROC-005: Git-Bound Heavy Track Codex Draft Gate

### 2.1 監視対象ファイル (Monitored Paths)
ステージング（`git diff --cached --name-only`）に以下のいずれかが含まれる場合、Heavy Track検証を発動する：
- `config/srs_specification_ssot.md`
- `domain_target/**/*.java`
- `tools/scripts/VerifySRS_Integrity.cs`
- `tools/scripts/VerifySRS_Deterministic.cs`

### 2.2 検証ルール (Fail-Closed Verification)
1. **領収書および監査レポートの同時ステージング義務**:
   - コミットインデックス内に、`audit/runs/{timestamp}/codex_receipt.json` および `audit/runs/{timestamp}/codex_report.txt` が同時にステージングされていなければならない。
   - 存在しない場合、リンターおよびGitフックは即時コミットを拒否する（`exit 1`）。
2. **領収書スキーマおよび実体検証**:
   - `codex_receipt.json` は以下のスキーマに厳格準拠すること：
     - `schema_version`: "2.0"
     - `target_file`: 変更対象ファイルパス
     - `staged_blob_sha256`: 対象ファイルのインデックスBlobのSHA-256
     - `model`: "gpt-6.2-astra"
     - `exit_code`: 0
   - **原典レポート照合**: 同一ディレクトリ内の `codex_report.txt` が実在し、空ファイル（0バイト）でないことを検証。単なるハッシュ偽造テキストを遮断する。
3. **判定エラーコード**:
   - `[FATAL] [PROC-005] Heavy Track modification detected without valid co-staged Codex receipt and report in audit/runs/.`

---

## 3. PROC-006: Tracked Trace Log & Incident Reconciliation Gate

### 3.1 追跡原帳仕様 (`logs/incident_execution_trace.log`)
- 揮発性の一時ファイル（`scratch/`）を廃止し、Git追跡ファイル `logs/incident_execution_trace.log` を唯一の実行証跡とする。
- 検証・ビルドスクリプトは、実行結果を1行固定フォーマットで原帳へ追加（Append）する：
  `[TIMESTAMP] [SCRIPT_NAME] [STATUS: PASS|FAIL] [CODE: ERROR_CODE] [MSG: ERROR_SUMMARY]`

### 3.2 検証ルール (Pre-Commit Hard-Gate)
1. **原帳不在時のFail-Closed**:
   - `logs/incident_execution_trace.log` が存在しない、0バイト、またはステージングされていない場合、コミットを拒否する：
     `[FATAL] [PROC-006] Execution trace log is missing or empty. Verification proof required.`
2. **追記専用（Append-Only）接頭辞検証**:
   - 前回コミット（`HEAD`）時点の `logs/incident_execution_trace.log` の全バイト列が、現在ステージングされたログの完全な接頭辞（Prefix）であることを検証する。
   - 過去の失敗ログを1行でも削除・切断・改ざんした場合、即時遮断する：
     `[FATAL] [PROC-006] Trace log truncation/mutation detected. History must be strictly append-only.`
3. **インシデント台帳との突合（Reconciliation）**:
   - 直前コミット以降に追加された `[STATUS: FAIL]` レコードについて：
     - 当該エラーコードまたはシグネチャが `logs/incident_history_ledger.md` に公式INCIDENTとして記載され、かつ状態が `RESOLVED` であることを全文字照合。
     - 未登録の失敗が1件でも残存している場合、コミットを拒否する：
       `[FATAL] [PROC-006] Unregistered failure detected in trace log. Registration in incident_history_ledger.md required.`
4. **再帰ループ遮断**:
   - ゲート自体の正当な遮断は `[STATUS: GATE_BLOCKED]` として記録され、これは `[STATUS: FAIL]` の突合対象外とすることで再帰的ループを防止する。

---

## 4. 保証水準および例外規定 (Assurance Level & Exceptions)

1. **オフライン自律性**: 本ゲートは外部ネットワークに依存せず、Gitインデックスとローカル追跡原帳のみで決定論的（100% Fail-Closed）に判定する。
2. **監査証跡の永続性**: 生成された領収書およびトレースログはすべてGitリポジトリの正本としてコミットされ、事後監査可能性を完全に担保する。
