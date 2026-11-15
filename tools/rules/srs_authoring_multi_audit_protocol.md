# SRS 작성 및 다층 검수 표준 프로토콜

## 1. 5단계 파이프라인

```text
[1단계] 요구사항 수집 & 인터뷰 (Antigravity)
   ▼
[2단계] 고속 뼈대 및 유스케이스 생성 (로컬 Qwen 27B)
   ▼
[3단계] 정밀 교차 감사 (OpenAI Codex CLI - Read Only)
   ▼
[4단계] 결정론적 Fail-Closed 린터 (C# VerifySRS & VerifySRS_Integrity)
   ▼
[5단계] 최종 승인 및 SSOT 원장 동기화 (Antigravity)
```

## 2. 요구사항 식별자(ID) 표준 규칙
- 기능 요구사항: `REQ-FUNC-XXX`
- 성능/확장성 요구사항: `REQ-PERF-XXX`
- 보안 및 권한 요구사항: `REQ-SEC-XXX`
- 인터페이스/API 요구사항: `REQ-INT-XXX`
- 예외 및 에러 처리: `REQ-ERR-XXX`

각 요구사항은 반드시 **[입력 - 처리 - 출력 - 예외 - 완료 조건(DoD)]**을 포함해야 하며, C# 린터가 누락 여부를 검사한다.