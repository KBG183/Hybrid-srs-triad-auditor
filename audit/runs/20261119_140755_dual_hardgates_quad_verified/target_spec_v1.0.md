# 🏛️ KINTAI Governance Extension: Dual Hard-Gates Specification (PROC-005 & PROC-006)

Version: 1.0.0  
Date: 2026-11-19  
Target Architecture: VerifySRS_Integrity (C#), Git Pre-Commit Hook, PowerShell Automation Engine

---

## 1. Background and Objectives

過去の運用において、以下の2大重大ガバナンス違反が摘発された：
1. **INCIDENT-66**: Heavy Track作業（SSOT、DDL、並行性、労基法計算等）において、エージェントがCodex初案自動生成（約50%分担）を行わず、Antigravity（Gemini）単独で過多執筆し、トークン平準化規約に違反してユーザーのトークンを偏重消費させた問題。
2. **INCIDENT-65 / INCIDENT-67**: スクリプト実行失敗やBOM混入、マルチバイト構文エラーが発生した際、エージェントが自律的にインシデント台帳へ記録せず、ユーザーの厳格な追及を受けて初めて事後記録するという隠蔽・受動的運用体質。

本仕様は、エージェントの自律的反省や定性的な誓約を一切信用せず、**物理的コードおよび決定論的リンターによって機械的にFail-Closedで遮断する2大ハードゲート（PROC-005 / PROC-006）**のアーキテクチャを定義する。

---

## 2. Specification: PROC-005 (Heavy Track Codex Draft Hard-Gate)

### 2.1 目的
Heavy Trackに該当する中核資産の変更時、OpenAI Codexによる物理的な初案生成領収書が存在しない限り、C#リンターおよびGitプレコミットがビルドおよびコミットを即時拒否する。

### 2.2 監視対象ファイル
- `config/srs_specification_ssot.md`
- `domain_target/**/*.java`
- `tools/scripts/VerifySRS_Integrity.cs`
- `tools/scripts/VerifySRS_Deterministic.cs`

### 2.3 検証条件 (Fail-Closed)
- ステージング（または作業ツリー）で上記監視対象ファイルのいずれかに変更差分（git diff）が存在する場合：
  - `scratch/runs/*/draft.md` または `audit/runs/*/codex_*.md`（直近1時間以内に生成された物理ファイル）が存在すること。
  - 当該ファイル内に `model: gpt-6.2-astra`（または `gpt-6.2-sol`）および有効なトークン/実行メトリクスブロックが含まれていること。
- **違反時挙動**:
  - `VerifySRS_Integrity.exe` は以下を出力して `exit 1` で終了する：
    `[FATAL] [PROC-005] Heavy Track modification detected without valid physical Codex draft receipt in scratch/runs/ or audit/runs/. Abort commit.`

---

## 3. Specification: PROC-006 (Unregistered Failure Block Gate)

### 3.1 目的
スクリプト実行時、テスト時、またはリンター検査時に発生したエラー・警告・終了コード非ゼロの事象を、エージェントの介在なしにスクリプト自身が物理キューへ自動強制排出し、当該事象が `logs/incident_history_ledger.md` に登録されない限り次工程を完全遮断する。

### 3.2 自動エラー補足（Trap / Auto-Capture）
- 全 PowerShell スクリプト（`verify_repo_total_integrity.ps1` 等）の失敗ブロック（`catch`、終了前チェック）に以下を義務化：
  - エラー発生時、直ちに `scratch/pending_incidents.json` へ `[timestamp, script_name, error_category, error_message, status="UNRESOLVED"]` を物理 append。
  - この処理はエージェントのプロンプトではなく、PowerShell エンジン自身が決定論的に実行する。

### 3.3 リンター照合ゲート (Fail-Closed)
- `VerifySRS_Integrity.exe` 実行時：
  - `scratch/pending_incidents.json` を読み込む。
  - 配列内に `status: "UNRESOLVED"` のレコードが1件でも存在する場合：
    - 当該エラーシグネチャまたはタイムスタンプが `logs/incident_history_ledger.md` 内に公式INCIDENTとして記載されているかを全文字照合。
    - 記載されていない（未登録・隠蔽）場合、以下を出力して `exit 1`：
      `[FATAL] [PROC-006] Unregistered failure detected in pending_incidents.json (Script: {0}, Error: {1}). Ledger registration required.`
  - 公式インシデントとして登録され、恒久対策が明記されている場合のみ `status: "RESOLVED"` への遷移を認める。

---

## 4. Verification Matrix & Edge Cases

1. **TOCTOU攻撃耐性**: エージェントが `pending_incidents.json` を手動削除して隠蔽しようとした場合、Git差分またはPre-commitフックでファイルの不当削除を検知して遮断。
2. **False Positive回避**: 正常終了（Exit 0）時はキューに追加されないこと。
3. **オフライン/自律実行性**: 外部ネットワーク障害時であっても、ローカルのファイル照合のみで決定論的に100% Fail-Closed判定可能であること。
