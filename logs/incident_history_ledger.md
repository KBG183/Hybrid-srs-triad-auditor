# 🏛️ [멀티에이전트 시스템 장애·예외 해결 통합 원장 (사건 이력 & 인프라 벤치마크)]

> 이 파일은 Antigravity 집필·검수 이력, 인프라 연속성 엔진 벤치마크, 그리고 Codex에서 이어진 모든 문제·원인·해결·검증 상태를 함께 기록하는 **공용 서술 통합 원장**입니다.  
> 기계 판독용 사건 ID와 수치 원장은 [`logs/enterprise_audit_ledger.csv`](logs/enterprise_audit_ledger.csv)를 사용하고, 이 파일에는 사람에게 필요한 원인·해결·잔여 위험 및 인프라 검증 기준을 영구 보존합니다.  
> 대시보드([`logs/pipeline_metrics.md`](logs/pipeline_metrics.md))와 1:1로 연결됩니다.

---

## 🧠 1. 고신뢰성 텍스트 상태 머신 & 연속성 검증 엔진 벤치마크 (영구 보존 기준점)

> 📌 **[베이스라인 벤치마크 안내]**:  
> 수만 줄 규모의 대규모 도메인 텍스트 및 사양서 검증을 위해 로컬 Qwen 27B, C# 결정론적 검사 엔진, Claude 크로스 감사로 구축된 **v1.05 연속성 운영 아키텍처 및 그림자 운영(Shadow Mode) 알고리즘의 최초 실측 벤치마크(기준 성적표)**입니다.  
> 본 섹션은 '엔진 기본 알고리즘의 신뢰성(9/9 PASS, 불확실성 보존)'을 증명해 둔 불변의 기준점이므로 영구 동결 보존됩니다. (이후 회차별 실제 도메인 사양 무결성 관리는 매 회차 [`audit/DayN_통합_검수리포트.md`](audit/) 및 SSOT에서 실시간 관리됨)

### 🔬 1.1 C# 결정론적 회귀 테스트베드 성적표 (`TestV52Suite_Regression.cs`)
* **최종 판정**: **9 / 9 PASS (결정론적 100% 무결점 통과)**
* **검증 엔진**: `tools/scripts/TestV52Suite_Regression.cs`

| 검증 ID | 검증 도메인 | 핵심 검증 내용 | 실측 결과 | 판정 |
| :--- | :--- | :--- | :--- | :---: |
| **ARITHMETIC** | 바이트 차이 분해 | 사양서 슬라이스(5,377B) vs 별도 파일(5,455B) 간 78B 차이 완전 규명 (BOM 3B + CRLF 73B + 개행 2B) | LF 정규화 후 2,305자 100% 일치 | **PASS** |
| **TEST-01** | 비파괴적 휴면·복원 | 3씬 미언급 시 `DORMANT` 전환 및 이력 보존, 화이트리스트 3종 `ACTIVE` 유지, 복원 전이 사건(`last_transition: REACTIVATED`) 모델링 | 화이트리스트 유지, 전이 모델 일치 | **PASS** |
| **TEST-02** | 미해결 큐 정돈 | 50개 합성 티켓 중복 병합(50 ➔ 34개, 32% 정돈), 독립 사안 15개 및 조건상이 5개 오병합 0건, 원본 ID 16개 1:1 전수 추적 | 1:1 우선순위 불일치 0건, 16개 ID 보존 | **PASS** |
| **TEST-03** | 추론 자동 승격 차단 | `inferred: true` 객체 승격 요청 100% 거부 및 위조 플래그 무력화 | C# 게이트키퍼 수준 원천 차단 | **PASS** |
| **TEST-04** | 이중 해시 및 오프셋 | `raw_source_sha256` vs `canonical_text_sha256` 분리 및 `offset_basis: RAW_UTF8_BYTES` 표준 확립 | 4대 변형 STALE 캐스케이드 통과 | **PASS** |
| **TEST-05** | 별칭 충돌 확장 | 인물(`CHAR_`), 장소(`LOC_`), 물품(`ITEM_`) 간 동명/별칭 중첩 시 최장 일치 우선(Longest-Match First) Span 점유 맵 격리 | 5개 엔티티 1:1 무간섭 단독 추출 | **PASS** |
| **TEST-06** | 길이 접두 HMAC MAC | 구분자 충돌 차단 길이 접두(`length:value;`) 직렬화 및 대칭키 기반 무결성 검증, 사양서/명세 변조 즉시 거부 | 변조 주장 및 사양 버전 재사용 100% 차단 | **PASS** |
| **TEST-07** | STALE DAG 전파 | 명세 블록 간 상태 의존성 그래프 구축, 원천 명세 수정 시 종속 블록만 무효화하고 독립 블록은 `VALID` 보존 | 선별적 무효화 및 불필요한 재검사 차단 | **PASS** |
| **TEST-08** | DAG 순환 참조 차단 | `A ➔ B ➔ C ➔ A` 순환 참조 시도 및 중복 엣지 등록을 DFS 삼색 마킹으로 사전 탐지 및 롤백 | 순환 및 중복 엣지 100% 차단 | **PASS** |

### 🛡️ 1.2 실제 원고 그림자 운영(Shadow Mode) 3회 누적 실측 지표
> 원고 정본(`원고/`)과 마스터 설정집(`config/`)을 100% 읽기 전용으로 동결하고, 완전히 격리된 샌드박스(`audit/shadow_ledger/`)에서 실측한 결과입니다.

| 회차 및 대상 씬 | 씬 범위 및 오프셋 | 추출 상태 수 (검증완료 / 판단대기) | 자동 증거 분류 비율 | 예상 검토 시간 | 원문 인용 정확도 | 정본 변경 | 작가 판단 및 보류 처리 |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **1차: Day 3 Scene 8**<br>(비품 지급 및 방 배정) | Line 810 ~ 881<br>`[54744, 59448)` (4,704B) | 총 9개<br>(완료 7 / 대기 2) | **77.8%** | **약 75초** | **100% (7/7 EXACT)** | **0건 (불변)** | PC 수거 시점: 보류 확정 (`UNKNOWN`)<br>SSD 소유권: 증여 추론 기각 및 보류 (`UNKNOWN`) |
| **2차: Day 2 Scene 9**<br>(비화 전화기 및 안심 통화) | Line 1010 ~ 1175<br>`[76679, 87814)` (11,135B) | 총 12개<br>(완료 10 / 대기 2) | **83.3%** | **약 80초** | **100% (10/10 EXACT)** | **0건 (불변)** | 전화기 반출 여부: 보류 확정 (`UNKNOWN`)<br>감청 영구 보관: 보류 확정 (`UNKNOWN`) |
| **3차: Day 2 Scene 9 ➔ 10**<br>(연속 전이 및 안심 편지) | Line 1177 ~ 1248<br>`[87816, 93193)` (5,377B) | 총 6개<br>(완료 5 / 대기 1) | **83.3%** | **약 45초** | **100% (5/5 EXACT)** | **0건 (불변)** | 기존 `ABSENT_CONFIRMED` 무효화(`SUPERSEDED`), 전화기 위치 `UNKNOWN` 불확실성 정상 보존 |

* **💡 그림자 운영 핵심 성과**:
  1. **불확실성의 엄격한 보존**: 원문에 명시되지 않은 사안(PC 수거 완료 시점, SSD 소유권 성격, 비화 전화기 퇴실 여부)을 AI가 임의로 확정하지 않고 불확실성(`UNKNOWN`)으로 정확히 격리하여 작가에게 보고함.
  2. **작가 검토 대상의 고도 압축**: 명확한 팩트(원문 인용 100% EXACT)는 자동으로 근거 검증을 완료하고, 작가가 실제로 확인해야 하는 티켓을 씬당 1 ~ 2건으로 압축하여 검토 피로를 실질적으로 최소화함.

---

## 🏛️ 2. 시스템 장애 및 예외 해결 통합 사건 이력 통합 기록

### 📅 2026-11-15 — 삼각 편대 정식 가동 및 Day8 전 구간 정본 완결 1건

<details open>
<summary>접기/펼치기 — INCIDENT-42</summary>

### 2026-11-15 — INCIDENT-42 — 삼각 편대 파이프라인 가동 및 Day8 12씬 최종 외과수술 완결

- 문제: INCIDENT-41에서 제기된 Day8 원고의 다중 퇴장 루프(Scene 8의 27줄, Scene 9의 51줄), 미르/세하 종결 어미 금기 위반 10건, 씬별 1,800자 하한 미달, 소개문 후보 3차 중복 등 구조적 결함 잔존.
- 원인: 에이전트 간 분업 규칙 미비로 인한 분량 부풀리기 및 기계적 종결 남발, 린터의 C타입 하드웨어 규격 과차단.
- 해결:
  1. 안티그래비티-로컬Qwen-코덱스CLI 삼각 편대 가동 (`call_codex.ps1` stdin 스트리밍, `--sandbox read-only` 감사관 지정, 안티그래비티 수정 전담).
  2. Part 1, Part 2, Part 3 전 구간 외과수술 집도: 중복 루프 삭제 후 콘티 연출 기반 감정선/티키타카 1,500자 이상 정밀 보강.
  3. 미르/세하 말투 전수 구어체 교정 및 '안경' 어휘 완전 적출.
  4. 린터(`VerifyHumanize.cs`)에 'C타입', 'USB-C' 등 하드웨어 규격 기술 예외 추가 등록.
  5. 로컬 Qwen 스크립트(`call_qwen.ps1`) 실시간 스트리밍 전면 개조.
- 검증: RAW 36,824자 / 공백 제외 26,939자 / 85,224 바이트. C# 린터 `verify_humanize.ps1` FATAL 0건 (100% ALL PASS). 전 12개 씬 1,800자 분량 하한 돌파. `audit/Day8_통합_검수리포트.md` 완성.
- 상태: `RESOLVED / CANONICAL_ESTABLISHED`.
- 원본 로그: `원고/Day8_일요일의_첫_작업표.md`, `audit/Day8_통합_검수리포트.md`.

</details>

---

### 📅 2026-11-13 — Day8 재집필·분량 교정·화자 잠금 및 린터 검증 14건

<details>
<summary>접기/펼치기 — INCIDENT-28 ~ INCIDENT-41</summary>

### 2026-11-13 — INCIDENT-28 — Day8 투고 시점 선행 조건 오반영 교정
- 문제: 작가가 실제 소설 투고·등록을 다음 주까지 보류했는데 Day8 콘티에 정식 투고·등록·초기 반응 확인을 포함하고, Scene 7 직전 연결 팩트를 `방송 운용 테스트 종료 및 투고 준비 완료`로 기록했다.
- 원인: `config/open_items.md`의 이전 계획 문구와 작가의 최신 보류 지시를 우선순위 대조에서 잘못 적용했다.
- 해결: Day8은 투고 전 검토본·체크리스트·다음 주 실행 일정만 확정하도록 수정했다. 실제 투고·등록·랭킹 확인은 OI-002를 `planned / DEFERRED`로 유지하고 다음 주 회차로 이관했다.
- 검증: Day8 콘티·`config/open_items.md`·`logs/CURRENT_STATUS.md`의 투고 시점과 OI-002 상태를 상호 대조했다.
- 상태: `RESOLVED / AUTHOR_TIMING_CORRECTED`.
- 원본: `콘티/Day8_콘티_초안.md`, `config/open_items.md`, `logs/CURRENT_STATUS.md`.

### 2026-11-13 — INCIDENT-29 — Day8 콘티 재검수 및 원고 린터 적용 범위 교정
- 문제: Day8 콘티 변경 후 고정 대조와 씬 계약 재검수가 필요했다. 원고용 Humanize 린터를 콘티에 실행하면 씬 분량 하한 FATAL이 발생한다.
- 확인: 8씬·투고 보류·OI-002 `planned / DEFERRED`·윤지혜 간호사 정기 아침 검진·Scene 1 직전 연결 팩트는 모두 정합했다.
- 판정: Humanize FATAL 2건은 콘티 결함이 아니라 원고 전용 분량 하한의 부적합 적용으로 `NOT_APPLICABLE_TO_OUTLINE` 처리했다.
- 상태: `PARTIAL / AUTHOR_APPROVAL_PENDING`.
- 원본 로그: `logs/audit_evidence/day8_outline_revalidation_20261113.md`.

### 2026-11-13 — INCIDENT-30 — Day8 콘티 작가 승인 및 정본 승격
- 승인: 작가가 Day8 콘티를 승인했다.
- 교정: 승인된 파일에 `_초안`을 남겨둔 것이 부정확했다. 내용 중복 없이 기존 파일을 공식 경로 `콘티/Day8_콘티.md`로 이름 변경하고 `_초안` 파일을 제거했다.
- 검증 대상: 8씬, 바다 미열·기침, 윤지혜 간호사 정기 아침 검진, OI-002 다음 주 투고 보류.
- 상태: `RESOLVED / CANONICAL_PROMOTED`.
- 원본: `콘티/Day8_콘티.md`, `logs/CURRENT_STATUS.md`.

### 2026-11-13 — INCIDENT-31 — Day8 로컬 반복 지적 반영 및 최종 게이트 통과
- 문제: 로컬 Qwen이 Scene 5~12의 파일 저장·화면 종료·상태 확인·투고 보류를 새 진전 없이 반복하는 것으로 판정했고, 원고에 Scene 5·6 분량 하한 FATAL 2건도 남아 있었다.
- 원인: 장면별 건강 확인과 작업 상태 기록이 실제 선택·관계 변화와 같은 문단에 섞였고, 로컬 감리 프롬프트가 설정상 반복되는 건강 관리까지 무진전 반복으로 넓게 분류했다.
- 해결: Scene 5·6의 분량 하한을 의미 있는 행동·관계 변화로 보강하고, Scene 5·7·11·12의 저장·상태 확인 반복을 편집 판단·소개문 선택·다음 역할 전환으로 치환했다.
- 검증: Humanize FATAL 0건, WARNING 4건(비차단), 12씬, RAW 48,511자, 공백 제외 35,436자, UTF-8 112,288바이트. Qwen `verdict=PASS`, canonical 게이트 `status=PASS / decision=NEXT`.
- 원본 로그: `원고/Day8_일요일의_첫_작업표_12씬_재집필.md`, `scratch/day8_full_manuscript_final_local_review_final.json`, `scratch/day8_episode_gate_final.json`.

### 2026-11-13 — INCIDENT-32 — Day8 공백 포함 분량 기준 교정 및 중첩 REVIEW 게이트 보강
- 문제: Day8에 공백 제외 35,000자를 회차 목표로 잘못 적용해 RAW 48,511자까지 늘어났고, 최종 Qwen의 최상위 `PASS`만으로 내부 `duplicate_groups` REVIEW를 통과 처리할 위험이 있었다.
- 해결: Scene 12 반복 엔딩을 재편집해 RAW 39,968자·공백 제외 29,170자·UTF-8 92,145바이트로 조정했다. 회차 목표는 공백 포함 35,000~40,000자로 고정하고, 씬 보조 하한은 공백 제외 1,800자로 분리했다.
- 린터 교정: STYLE-001 대명사 정규식에 한글 단어 경계를 추가해 `프롤로그의`·`로그의` 안의 `그의` 부분 문자열 오탐을 제거했다.
- 게이트 교정: `check_workflow_gate.ps1`가 최상위 `PASS`라도 `duplicate_groups.severity=REVIEW/BLOCK`이면 `REVIEW_REQUIRED / BLOCK`으로 정규화하도록 fail-closed 보강했다.
- 원본 로그: `원고/Day8_일요일의_첫_작업표_12씬_재집필.md`, `scratch/day8_full_manuscript_final_local_review_raw_metric_final.json`.

### 2026-11-13 — INCIDENT-33 — Day8 Part 2·3 반복 정리 및 공백 포함 최종 게이트 통과
- 수정 범위: Part 2의 Scene 6~8 전환·저장 반복을 점검하고, Part 3의 Scene 10 방송 종료·로그 재확인 반복과 Scene 11 파일 상태 재확인을 선택·담당·원인 기록 중심으로 압축했다.
- 최종 분량: 공백 포함 39,393자, 공백 제외 28,755자, UTF-8 90,798바이트, 12씬. 씬별 공백 포함 2,500자 및 공백 제외 1,800자 하한 충족.
- 기계 검수: FATAL 0건, INFO 0건, WARNING 4건.
- 로컬 Qwen: `verdict=PASS`; 게이트 `status=PASS / decision=NEXT`.
- 원본 로그: `원고/Day8_일요일의_첫_작업표_12씬_재집필.md`, `scratch/day8_full_manuscript_final_local_review_raw_metric_final_v3.json`.

### 2026-11-13 — INCIDENT-34 — 문제·원인·해결 자동 보고 규칙 고정
- 문제: 작업 중 기준 충돌이나 검수 불일치를 발견해도 결과만 먼저 보고하면 사용자가 원인과 잔여 위험을 다시 물어야 하는 문제가 있었다.
- 해결: `GEMINI.md`와 `tools/rules/CODEX_작업_실행_정책.md`에 문제·원인·영향·해결·재검증·잔여 위험·다음 조치의 자동 보고 형식을 고정했다.

### 2026-11-13 — INCIDENT-35 — Day8 선행 Day9·과도한 메모·대사 톤 교정
- 문제: Scene 12에 설정상 아직 확정되지 않은 `Day9` 명칭이 등장했고, 0.1% 지능·28세 친구 설정에 비해 세부 메모와 체크리스트가 과도했다.
- 해결: `Day9`를 `내일 준비표`로 교체하고, 바다의 세부 메모 작성을 기억과 즉시 판단으로 축소했다. 친구 사이 반말로 수정.
- 상태: 원고는 공백 포함 39,229자이며 투고·등록·랭킹 확인은 보류.

### 2026-11-13 — INCIDENT-36 — 대사 축약 중 화자 설정 잠금 누락
- 문제: Day8 말미의 세하·주현 대사가 세하의 능글맞은 팩폭과 주현의 직선적 보호 행동이 약해져 화자 차별화가 소실됨.
- 해결: 화자별 기능이 드러나도록 수정하고 대사 잠금 절차 추가.

### 2026-11-13 — INCIDENT-37 — 화자 잠금 수정 후 로컬 재검증
- 결과: 화자 분리는 PASS했으나 Scene 4~6 및 Scene 8~10 반복 비트와 패딩 위험은 REVIEW. 게이트 `REVIEW_REQUIRED / BLOCK`.

### 2026-11-13 — INCIDENT-38 — Day8 반복 비트 재구성 후 재감리
- 조치: 첫 작업 종료부 동일 행동 반복 제거 및 씬별 1,800자 하한 조정. 공백 포함 38,920자.

### 2026-11-13 — INCIDENT-39 — Day8 후반 반복 재정리 및 최종 로컬 판정
- 조치: 20:30 내일 계획 재확인을 한 번으로 축소, 16:35 파일 정리 블록 재구성. 공백 포함 37,860자.

### 2026-11-13 — INCIDENT-40 — Day8 반복 비트 최종 범위 고정
- 조치: 19:00 본문·소개문 불일치 해결, 16:35 입력 충돌 위험 분리. 공백 포함 37,126자.

### 2026-11-13 — INCIDENT-41 — Day8 개연성·기록 과잉 구조 결함 확인
- 문제: Day7의 휴식·일상 정서와 달리 Day8에 기록·체크리스트·작업표 관련 표현이 76건 과잉 누적되어 씬 구조 재설계(`REWRITE_REQUIRED`) 판정.

</details>

---

### 📅 2026-11-12 — Codex·공용 운영 초기 연동 및 감사 사건 27건

<details>
<summary>접기/펼치기 — INCIDENT-01 ~ INCIDENT-27</summary>

### 2026-11-12 — INCIDENT-01 — 공용 크로스 감사 엔진 경로 인코딩 오류
- 문제: Windows PowerShell에서 한글 경로 문자열이 깨져 `call_claude.ps1`를 찾지 못함.
- 해결: 프로젝트 루트에서 `call_claude.ps1`를 파일명 기준으로 재귀 탐색하도록 수정. `RESOLVED`.

### 2026-11-12 — INCIDENT-02 — Anthropic API 인증 401
- 문제: 첫 Claude Round 1 호출에서 `401 Unauthorized` 발생.
- 해결: 환경 변수 갱신 후 재실행 성공. `RESOLVED`.

### 2026-11-12 — INCIDENT-03 — 크로스 감사 결과 보고서 변수 보간 오류
- 해결: 실행기 템플릿의 변수 표현 수정. `RESOLVED`.

### 2026-11-12 — INCIDENT-04 — 정리 후보의 폴더 단위 분류 오류
- 해결: 핵심 입력·소스는 보존하고 실행 파일·구형 산출물만 `scratch/archive_20261112/`로 격리. `PARTIAL`.

### 2026-11-12 — INCIDENT-05 — 공용 로그 분산 문제
- 해결: `pipeline_metrics.md`를 Codex·Antigravity 공용 서술 원본으로 지정. `RESOLVED`.

### 2026-11-12 — INCIDENT-06 — UTF-8 BOM 없는 한글 파일의 PowerShell 표시 오류
- 해결: 검증 시 명시적 UTF-8 읽기 사용. `RESOLVED_FOR_READ`.

### 2026-11-12 — INCIDENT-07 — v3 단독 집필 파이프라인 시험
- 검증: `scratch/test_runs/CODEX_V3_PILOT_20261112/`에 비정본 시험 씬 작성 및 헌법 작동 확인. `PARTIAL`.

### 2026-11-12 — INCIDENT-08 — 정리 작업 안전 격리
- 해결: 임시 파일들을 `scratch/archive_20261112/` 하위로 이동. `RESOLVED_WITH_REVERSIBLE_QUARANTINE`.

### 2026-11-12 — INCIDENT-09 — 실제 콘티 기반 씬 파일럿
- 해결: Day 7 Scene 3 비정본 씬 작성 및 격리 검증. `PARTIAL`.

### 2026-11-12 — INCIDENT-10 — 선행 인과율 린터 판정 불일치
- 해결: `VerifyPrereq.cs`에서 DRAFT를 REVIEW로, PROMOTE를 FATAL로 분리. `RESOLVED_FOR_STAGE_CONTRACT`.

### 2026-11-12 — INCIDENT-11 — pipeline_metrics Day7 분량 불일치
- 해결: 대시보드 Day7 수치를 실제 원고 측정값으로 정정. `RESOLVED_FOR_CURRENT_METRIC`.

### 2026-11-12 — INCIDENT-12 — SSOT 재감사 후 legacy 분량 경고
- 해결: 과거 원고 분량 경계 구간을 작가 승인 백로그로 분리. `WARN / AUTHOR_DECISION_REQUIRED`.

### 2026-11-12 — INCIDENT-13 — 실제 씬 연속성 대조에서 호출 주체 불일치
- 판정: 파일럿 바다 호출 vs 정본 세하 인터폰 호출 불일치 기록. `PARTIAL`.

### 2026-11-12 — INCIDENT-14 — 호출 주체 교정 후 선행 문맥 게이트 잔존
- 해결: 교정본 별도 보존 및 선행 문맥 번들 요구 확인. `RESOLVED_FOR_BEHAVIOR`.

### 2026-11-12 — INCIDENT-15 — 전체 Day6 문맥에서 씬 헤더 매핑 누락
- 해결: 시간 범위 정규식 보완 및 5번 이후 씬 기본값 적용. `RESOLVED_WITH_RUNTIME_RETEST`.

### 2026-11-12 — INCIDENT-16 — Day7 전체 원고 읽기 전용 감사
- 판정: Humanize FATAL 0, 분량 하한 경고 분리. `PARTIAL`.

### 2026-11-12 — INCIDENT-17 — Day7 선행문맥 파서의 회차 하드코딩 수정
- 해결: 파일명에서 `DayN` 추출해 이전 정본 회차 동적 파싱 지원. `RESOLVED_WITH_SCOPE_AWARE_RETEST`.

### 2026-11-12 — INCIDENT-18 — Day7 분량 및 금기 후보 문맥 판정
- 해결: 113행 멸치볶음 작가 검토 대상으로 분리. `PARTIAL / AUTHOR_REVIEW_REQUIRED`.

### 2026-11-12 — INCIDENT-19 — Day7 전체 씬 구조·전환 감사
- 검증: 콘티 11씬과 정본 11씬 번호·시간·장소 전수 대조 일치. `PASS`.

### 2026-11-12 — INCIDENT-20 — Day7 인물 등장·정보 흐름 정적 감사
- 검증: 네 주인공 전 씬 등장 및 보조 인물 정상 등장 확인. `PASS`.

### 2026-11-12 — INCIDENT-21 — Day7 113행 금기 대체안 및 분량 의사결정 비교
- 해결: A, B, C 세 대체안 비교 분석. `PARTIAL / AUTHOR_APPROVAL_REQUIRED`.

### 2026-11-12 — INCIDENT-22 — Day7 3단계 콘티 기준 증보 및 대시보드 재동기화
- 해결: 113행 A안 수정 및 34,105자 확장. `RESOLVED / SSOT_METRIC_RESYNCED`.

### 2026-11-12 — INCIDENT-23 — Day7 증보 후 최종 SSOT 재감사
- 검증: Checks 0~9 PASS, 대시보드 수치 일치 PASS. `PASS_WITH_WARN`.

### 2026-11-12 — INCIDENT-24 — 외부 동기화 및 146개 감사 의무 읽기 전용 점검
- 해결: 안전 검증 전 외부 쓰기 보류. `PARTIAL`.

### 2026-11-12 — INCIDENT-25 — 안전 동기화 3단계 분리 및 로컬 백업 검증
- 해결: Preview, Backup, Apply 3단계 분리 스크립트 작성. `RESOLVED_FOR_SAFE_PREVIEW_AND_BACKUP`.

### 2026-11-12 — INCIDENT-26 — iCloud 로컬 최신본 반영 및 해시 검증
- 검증: Day7 정본 및 GEMINI.md 로컬-iCloud 해시 일치. `PASS_WITH_WARN`.

### 2026-11-12 — INCIDENT-27 — Google Drive 읽기 전용 대조 후 안전 업로드
- 검증: Drive 파일 최신본 교체 및 신규 업로드 성공. `PASS_WITH_WARN`.

</details>

---

### 📜 공용 기록 규칙

1. 새 버그·문제·원인·해결은 `YYYY-MM-DD — INCIDENT-ID` 날짜 형식과 함께 이 원장에 기록한다.
2. `enterprise_audit_ledger.csv`에는 기계 판독용 상태·수치·원장 행을 추가한다.
3. 원시 Claude 결과, 로컬 모델 출력, 실행 명령 출력은 `logs/audit_runs/` 또는 `logs/audit_evidence/`에 보존하고 이 원장에서 경로를 연결한다.
4. API 키·비밀값은 어떤 로그에도 기록하지 않는다.
5. 원본 로그 경로가 없거나 검증되지 않은 해결은 `RESOLVED`로 기록하지 않고 `PARTIAL`, `NOT_TESTED`, 또는 `EVIDENCE_MISSING`으로 표시한다.
