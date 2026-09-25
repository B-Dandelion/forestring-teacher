# Forestring Data Portfolio

Issue: #3

## Goal
운영 중인 포레스트링 데이터를 이용해 단순 집계가 아니라 **데이터 신뢰도 확인 → 패턴 탐색 → 운영/서비스 의사결정 → AI 확장 가능성**까지 연결되는 분석 사례를 만든다.

## Safety / Scope
- production DB는 **read-only**로 조회한다.
- 이름, 이메일, 전화번호 등 개인 식별정보는 분석 산출물에 저장하지 않는다.
- 학생/교사 단위 분석이 필요할 때도 UUID를 외부 산출물에 노출하지 않고 aggregate 또는 익명 cohort로만 표현한다.
- 모든 시간 분석은 KST(`Asia/Seoul`) 기준으로 통일한다.

## Data sources
- `lessons`
- `lesson_series`
- `lesson_cancellation_events`
- `lesson_rights`
- `audit_events`
- `student_enrollment_periods`
- `student_semester_plans`
- `teacher_work_hours`
- `semesters`
- `closure_periods`

GitHub 기준으로 현재 Supabase schema는 136개 migration과 60개 SQL test/inspection 파일로 관리되고 있다.

## Phase 0 baseline — 2026-09-25 snapshot

### Overall historical lessons
- past lessons: **2,319**
- canceled: **186**
- scheduled: **2,133**
- observed range: **2025-03-17 ~ 2026-09-21**
- historical cancel rate: **8.02%**

> 주의: v3 이전 이력은 현재 cancellation ledger와 기록 방식이 다르므로, 취소 원인/lead-time 분석에는 그대로 사용하지 않는다.

### v3-era operational window
분석 기준 시작일을 현재 v3 schema migration이 시작된 **2026-08-17**로 둔다.

- past lessons: **359**
- canceled: **25**
- cancel rate: **6.96%**
- makeup lessons: **44**

최근 30일:
- lessons: **255**
- canceled: **14**
- cancel rate: **5.49%**
- makeup: **34**

### Cancellation ledger coverage
v3 기간의 canceled lessons 25건 중:
- cancellation event가 연결된 lesson: **16**
- event가 없는 canceled lesson: **9**
- lesson 자체의 `canceled_at` 누락: **0**

따라서 `lesson_cancellation_events` 기반의 origin/lead-time 분석은 **전체 canceled lesson의 완전한 모집단이 아니라 부분집합**으로 취급해야 한다.

### Initial hypotheses — not conclusions
최근 30일 기준:
- 수요일 취소율 9.38% (3 / 32)
- 목요일 취소율 8.33% (5 / 60)
- 18시 취소율 10.71% (3 / 28)

표본이 작아 현재 단계에서는 “취소가 집중된다”는 결론을 내리지 않는다. 향후 월별 누적과 최소 표본 기준을 적용해 재검증한다.

cancellation event 19건의 lead time:
- median: **71.47h**
- p25: **4.13h**
- p75: **134.76h**
- lesson 시작 24시간 이내 취소: **4**
- lesson 시작 이후 기록된 취소: **4**

마지막 항목은 데이터 오류로 단정하지 않고, 운영상 사후 처리인지 event semantics 차이인지 먼저 확인한다.

## Analysis questions

### 1. Cancellation / rebooking
- 어떤 요일·시간대·수업 유형에서 취소율이 높은가?
- 학생 취소와 학원 취소의 패턴은 다른가?
- 취소 후 보강/대체 수업으로 이어지는 비율과 소요시간은?
- 취소 lead time이 운영 부담과 어떤 관계가 있는가?

### 2. Student lifecycle
- 월별 신규 등록 / 종료 / active 학생 흐름은?
- 재원 기간별 취소·일정 변경 패턴이 다른가?
- 수업권 발급 → 예약 → 소진/만료 흐름에서 병목이 있는가?

### 3. Operational cost proxy
- 수업 100건당 수동 변경 event는 몇 건인가?
- 자동화 이후 수동 개입이 감소했는가?
- 어떤 event type이 운영자 개입의 대부분을 차지하는가?

### 4. AI extension
데이터량과 label 품질을 먼저 확인한 뒤 다음 순서로 실험한다.
1. Logistic Regression baseline
2. tree-based model
3. 설명가능성 / leakage 확인
4. anomaly detection baseline

목표는 모델 점수가 아니라 **분석 결과를 실제 운영 액션으로 연결할 수 있는지**를 검증하는 것이다.

## Repository outputs
- `sql/01_baseline.sql` — 기간/상태/유형 기본 집계
- `sql/02_cancellation_patterns.sql` — 요일·시간대·lead time 분석
- `sql/03_data_quality.sql` — cancellation ledger coverage 검사

추후 Python 시각화와 portfolio case study를 추가한다.
