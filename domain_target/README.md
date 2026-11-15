# KINTAI Domain Target Fixture for Project 2 (SRS & Audit System)

이 패키지는 프로젝트 2(AI 하이브리드 SRS 작성 및 검수 시스템)가 분석 및 검증을 수행하기 위한 '검증 대상 도메인(Target Domain Fixture)' 데이터 세트입니다.

## 폴더 구조 및 역할
- 01_specifications_and_rtm: 시스템 목표, 초기 요구사항 명세서, 추적성 매트릭스(RTM), 감사 증적서
- 02_database_schema_ssot: 데이터베이스 제약조건 및 테이블 구조 SSOT (MySQL 8.4 DDL)
- 03_core_domain_services: 노동기준법 제37조 계산 엔진, 비관적 락 급여 확정, 출퇴근 타각 핵심 로직
- 04_api_contracts_and_dtos: REST API 계약 및 입출력 DTO 명세
- 05_core_domain_tests_fixtures: 정답지 역할을 하는 핵심 단위/통합 테스트 (노동법 수식, 동시성 락 등)