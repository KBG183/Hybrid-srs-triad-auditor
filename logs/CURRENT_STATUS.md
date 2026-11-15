# 📍 KINTAI 品質検証パイプライン 統括ステータス台帳

最終更新: 2026-11-16（多層AI交差検証・確定論的リンター稼働中）

---

## 1. 現在のマイルストーン

- **プロジェクト位置づけ**: 本リポジトリは、アルバイト勤怠・給与SaaS「KINTAI」の労働基準法計算・並行性制御を担保するための独立品質検証パイプラインです。
- **現行フェーズ**: 多層AIハイブリッド（Google Gemini + OpenAI Codex + Anthropic Claude + ローカルQwen 27B）および確定論的C#リンター環境の稼働確認完了
- **障害・再発防止台帳**: `logs/incident_history_ledger.md`（実運用中の課題と恒久対策を記録）
- **最新ヘルスチェック判定**: `ALL_ENGINES_ONLINE` (PASS)

---

## 2. 検証パイプラインの構成

1. **統括オーケストレーター**: Antigravity (Google Gemini Engine — ワークスペース調整・SSOT管理)
2. **高速文脈分析器**: ローカル Qwen 27B (`call_qwen.ps1` — RTX 5070 Ti P2Pリモートアクセラレーション)
3. **機能・境界交差監査官**: OpenAI Codex CLI (`call_codex.ps1` — 読み取り専用サンドボックス、自動ルーティング機能付き)
4. **労務・法令深層監査官**: Anthropic Claude (`call_claude.ps1` — 従量課金保護ポリシー準拠、ユーザー明示指示時のみ稼働)
5. **確定論的ハードゲート**: C# Roslyn リンター (`VerifySRS_Integrity.exe`, `TestV52Suite_Regression.exe` — 94/94 回帰テスト全件PASS)

---

## 3. 実証対象ドメイン (`domain_target/`)

- **対象プロダクト**: 店長・アルバイト向け勤怠・シフト・給与管理SaaS（KINTAI）
- **主要検証資産**: MySQL 8.4 DDL、労働基準法第37条割増賃金計算エンジン、InnoDB悲観的ロックによる二重打刻防止・デッドロック解消サービス、JUnit 5統合テスト
