# Codex·Antigravity 공용 운영 및 크로스 감사 정책

시행일: 2026-11-15

## 1. 기본 원칙 (분업과 상호 견제)

- **Antigravity (총괄)**: 프로젝트 전체 맥락 파악, 파일 입출력 총괄, 사용자 인터페이스 담당.
- **Codex CLI (감사관)**: 파일 쓰기 권한이 없는 `--sandbox read-only` 모드로 격리 실행되며, 제안된 SRS 명세서나 코드의 모호성, 경계 조건(Edge Case) 누락, 보안 취약점, 헌법 위반을 독립적으로 교차 검증한다.
- **로컬 Qwen 27B (생성기)**: GPU 자원을 활용하여 요구사항 목록 초안 및 유스케이스 시나리오 뼈대를 0초 지연으로 고속 생성한다.

## 2. 크로스 감사 실행 절차

1. 안티그래비티가 작성한 SRS 초안을 `scratch/test_runs/codex_workspace/` 또는 임시 파일에 배치.
2. `tools/scripts/call_codex.ps1`을 호출하여 표준 감사 계약에 따른 검수 실행.
3. 코덱스의 출력에서 `CRITICAL`, `WARNING`, `DEFECT`를 파싱하여 `audit/SRS_통합_검수리포트.md`에 적재.
4. 코덱스가 지적한 결함을 보정한 후 C# 결정론적 린터(`gate_phase3.ps1`)를 통과시킨다.

## 3. 원클릭 승인형 일괄 갱신 프로토콜

작업 완료 시 안티그래비티는 사용자에게 다음과 같은 정형화된 블록을 제시한다:

```markdown
### 📦 연계 갱신 대상 파일 패키지 (단일 승인 대기)
1. `config/srs_specification_ssot.md` (요구사항 ID 확정 반영)
2. `logs/pipeline_metrics.md` (검증 합격 메트릭 최신화)
3. `logs/incident_history_ledger.md` (특이사항 및 감사 증적 기록)
4. `logs/CURRENT_STATUS.md` (프로젝트 단계 완료 마킹)
```
사용자가 "승인", "진행", "ㅇㅇ" 등을 입력하면 추가 질문 없이 위 패키지를 한 번에 갱신하고 최종 보고한다.