# Forestring v3.4 알림 정책 1차 확정안

작성일: 2026-10-05  
상태: 1차 확정 / DB 구조 반영  
대상 앱: 선생님·지점장·전체 관리자 앱  
첫 출시 범위: 일반 선생님 Push만 활성화

## 1. 목적

Forestring의 Push 알림은 특정 `lesson_id` 중심 기능으로 제한하지 않는다.

수업, 정규 일정, 담당 관계, 개인 일정, 근무시간, 지점 휴원, 학기 등 서로 다른 도메인 이벤트를 장기적으로 처리할 수 있도록 설계한다.

첫 출시에서는 일반 선생님에게 필요한 핵심 일정 변화만 실제 발송한다. 지점장과 전체 관리자 알림은 이벤트 분류, 수신 정책, payload/navigation 계약까지 설계 가능한 구조로 준비하되 실제 발송은 비활성 상태로 둔다.

개발자가 조치해야 하는 자동화 실패, 데이터 정합성 오류, Push/cron 장애 등은 지점장·전체 관리자용 업무 알림에 포함하지 않는다. 해당 항목은 별도의 **개발자 운영 알림 정책**으로 분리하며, 개발자 계정 또는 별도 운영 채널 중 어떤 방식으로 수신할지는 추후 결정한다.

---

## 2. 역할 구분

### 일반 선생님 (teacher)

핵심 목적은 **본인의 실제 수업표와 담당 학생에 영향을 주는 변화를 놓치지 않는 것**이다.

### 지점장 (manager)

핵심 목적은 **자기 지점에서 본인의 직접 조작 외에 발생한 운영·일정 변화를 파악하는 것**이다.

행위자 본인이 직접 만든 변경은 기본적으로 자기 자신에게 다시 Push하지 않는다. 같은 지점에 다른 지점장이 존재하는 경우에는 향후 actor/recipient 정책에 따라 다른 지점장에게 전달할 수 있다.

### 전체 관리자 (master)

핵심 목적은 **개별 수업 단위가 아니라 지점·학기·인력 구조처럼 전체 운영에 영향을 주는 변화**를 파악하는 것이다.

일반적인 개별 수업 예약·변경·취소는 기본 수신 대상이 아니다.

### 개발자 운영 알림 (별도 정책)

앱 역할 알림과 분리한다.

예:
- 자동 수업 생성 실패
- 다음 학기 자동 전환 실패
- Push dispatcher 반복 실패
- cron/자동화 실패
- 데이터 누락·재생성·정합성 이상 감지
- 그 밖에 사용자 조치가 아니라 개발자 수정이 필요한 오류

현재 DB의 `STUDENT_NEXT_SEMESTER_AUTO_FAILED` 같은 이벤트는 이 범주에 포함한다.

---

## 3. 일반 선생님 알림 정책

| 알림 이벤트 | 목적 | 기본 destination | 첫 출시 |
| --- | --- | --- | --- |
| 새 학생/수업 배정 | 새 담당 학생 및 향후 수업 발생 인지 | 마이페이지 → 해당 학생 상세 | ON |
| 개별 수업 시간/길이 변경 | 실제 예정 수업 변경 인지 | 해당 수업 강조 | ON |
| 수업 취소 | 예정 수업 취소 인지 | 해당 날짜·시간 또는 취소 수업 정보 | ON |
| 보강 수업 등록 | 새로운 보강 일정 인지 | 해당 보강 수업 강조 | ON |
| 보강 수업 취소 | 보강 일정 취소 인지 | 해당 날짜·시간 또는 취소 수업 정보 | ON |
| 자율 학생 수업 예약 | 학생이 직접 예약한 신규 수업 인지 | 해당 수업 강조 | ON |
| 정규 일정 변경 | 반복 일정 규칙 변경 인지 | 마이페이지 → 해당 학생 상세 | ON |
| 새 담당 선생님 배정 | 학생이 새 담당 선생님에게 배정됨 | 마이페이지 → 해당 학생 상세 | ON |
| 학생 퇴원 예정/확정 | 담당 학생의 향후 수업 종료 인지 | 학생 정보 또는 마지막 수업 주차 | OFF / 향후 |
| 근무시간 변경 | 예약 가능 시간 변경 인지 | 주간 화면 + 변경 시간대 | OFF / 향후 |
| 개인 일정 등록/변경/삭제 | 예약 불가 시간 변경 인지 | 해당 개인 일정 블록 | OFF / 향후 |
| 지점 휴원/휴원 변경 | 본인 수업에 영향을 주는 휴원 인지 | 해당 휴원 기간의 주간 화면 | OFF / 향후 |
| 학기 기간 변경 | 수업 생성 범위 변경 인지 | 일정/학기 안내 화면 | OFF / 향후 |
| 다음 학기 학생 수강형태 변경 | 다음 학기 담당 방식 변경 인지 | 학생 상세/다음 학기 정보 | OFF / 향후 |

> 첫 출시에서는 위 표의 ON 이벤트만 실제 Push 발송 대상으로 한다.

---

## 4. 지점장 알림 정책

첫 출시에서는 실제 발송하지 않는다. 구조와 이벤트 계약만 고려한다.

| 알림 이벤트 | 목적 | 기본 destination | 계획 |
| --- | --- | --- | --- |
| 학생의 자율 수업 예약 | 학생 행동으로 지점 일정 변경 | 일정 → 해당 선생님 필터 → 수업 강조 | 향후 |
| 학생의 수업 취소/재예약 | 관리자 조작 없이 일정 변경 | 해당 선생님 주간 화면 | 향후 |
| 담당 선생님 변경 | 학생 배정 변화 | 학생 상세 또는 해당 선생님 일정 | 향후 |
| 학생 등록/재등록 | 새로운 재원생 발생 | 수강생 상세 | 향후 |
| 학생 퇴원 예정/확정 | 향후 수업/배정 종료 | 수강생 상세 | 향후 |
| 선생님 개인 일정 등록/변경/삭제 | 지점 예약 가능 시간 변화 | 선생님 필터 + 개인 일정 블록 | 향후 |
| 선생님 근무시간 변경 | 지점 예약 가능 시간 변화 | 선생님 상세/주간 화면 | 향후 |
| 보강 등록/취소 | 타 사용자에 의한 지점 일정 변화 | 해당 수업 | 향후 |
| 지점 휴원 설정/변경 | 지점 전체 일정에 영향 | 지점/학기 휴원 상세 | 향후 |
| 학기 기간 변경 | 지점 수업 생성 범위 변화 | 학기 정보 | 향후 |

개발자 조치가 필요한 시스템 실패/자동화 오류는 지점장에게 발송하지 않는다.

---

## 5. 전체 관리자 알림 정책

첫 출시에서는 실제 발송하지 않는다.

| 알림 이벤트 | 목적 | 기본 destination | 계획 |
| --- | --- | --- | --- |
| 지점 휴원 생성/변경 | 다수 수업에 광범위한 영향 | 해당 지점·학기 | 향후 |
| 학기 생성/기간 변경 | 전체 서비스 일정 기준 변경 | 학기 관리 | 향후 |
| 지점 생성/비활성화 | 운영 지점 구조 변경 | 지점 관리 | 향후 |
| 지점장 생성/퇴사/지점 변경 | 권한 및 지점 운영 구조 변화 | 지점장 관리 | 향후 |
| 선생님 퇴사 예정/확정 | 담당 학생 재배정 필요 가능 | 선생님 상세 | 향후 |
| 일반 수업 예약/변경/취소 | 지나치게 빈번하며 전체 관리자 관점에서 낮은 가치 | 수신하지 않음 | 기본 OFF |

개발자가 고쳐야 하는 자동화 실패·Push 장애·cron 장애·정합성 오류는 전체 관리자에게 발송하지 않는다.

---

## 6. 알림 도메인 설계 원칙

### 6.1 Audit event와 Notification event를 동일시하지 않는다

감사 로그는 변경 이력을 최대한 상세히 남기는 것이 목적이다.

Push는 사용자가 실제로 알아야 할 의미 있는 변화를 전달하는 것이 목적이다.

따라서 장기 구조는 다음을 기준으로 한다.

```text
Business operation
    ↓
Audit event(s)
    ↓
Notification domain event
    ↓
Recipient policy
    ↓
Notification outbox
    ↓
FCM / APNs
```

하나의 업무 변경이 여러 audit event를 만들더라도 사용자에게는 하나의 의미 있는 Notification event로 정규화할 수 있다.

### 6.2 lessonId를 공통 필수값으로 사용하지 않는다

알림마다 대상 도메인이 다르므로 공통 envelope와 이벤트별 context를 분리한다.

개념상 공통 필드는 다음과 같다.

```text
eventKey
targetKind
targetId
actorProfileId
recipientRole
branchId?
teacherId?
studentId?
startsAt?
endsAt?
effectiveFrom?
context(jsonb)
```

예:
- 수업 변경: `targetKind=lesson`, `targetId=lessonId`
- 정규 일정 변경: `targetKind=regularSchedule`, `targetId=scheduleSlotId`
- 개인 일정: `targetKind=blockedPeriod`, `targetId=blockedPeriodId`
- 담당 관계 변경: `targetKind=assignment`, `targetId=assignmentId`

필요하지 않은 필드는 억지로 채우지 않는다.

### 6.3 역할별 수신 정책과 이벤트 정의를 분리한다

향후 다음 개념을 기준으로 설계한다.

```text
notification_event_catalog
- event_key
- target_kind
- navigation_kind
- title/body template metadata

notification_role_policy
- event_key
- recipient_role
- enabled_by_default
- release_enabled
```

첫 출시 정책:
- teacher: v1 핵심 8개 이벤트만 `release_enabled=true`
- manager: `release_enabled=false`
- master: `release_enabled=false`

DB에는 `private.notification_event_catalog`과 `private.notification_role_policy`로 반영되어 있다.

### 6.4 사용자 개인 설정은 이벤트 추가에 대응 가능해야 한다

이벤트가 늘어날 것을 고려해 장기적으로는 알림 설정을 이벤트별 행 구조로 확장할 수 있도록 한다.

실제 DB에는 `private.notification_event_preferences(profile_id, event_key, enabled)`를 두었다. 기존 Flutter 알림 설정 UI는 그룹형 설정을 그대로 사용하고, DB trigger가 해당 값을 이벤트 단위 설정으로 동기화한다. 따라서 앱 UI 호환성을 깨지 않으면서 향후 이벤트별 설정으로 확장할 수 있다.

---

## 7. 앱 상태별 표시 및 navigation 원칙

### Foreground

OS Push 배너 대신 인앱 알림을 사용한다.

사용자가 인앱 알림을 누르면 해당 Notification event의 destination resolver를 실행한다.

### Background

OS Push 배너를 표시한다.

사용자가 알림을 누르면 `onMessageOpenedApp`을 통해 destination resolver로 전달한다.

### Terminated

OS Push 배너를 표시한다.

알림으로 앱이 시작되면 `getInitialMessage()`의 정보를 pending navigation intent로 보관한다.

다음 초기화가 완료된 이후 이동한다.

```text
Firebase / Supabase 초기화
→ 저장된 Supabase session 복원
→ 현재 profile 조회
→ 역할 판단
→ TeacherShell / ManagerShell 구성
→ LessonController 등 필요한 데이터 로드
→ pending notification intent 소비
→ destination 이동/필터/포커스
```

일반 아이콘 실행 또는 일반 background → foreground 복귀는 기존 화면 흐름을 바꾸지 않는다.

---

## 8. 주간 화면 포커스 기본 UX

수업 또는 시간대 포커스가 필요한 알림은 역할에 따라 다음을 기본으로 한다.

- 일반 선생님: 주간 화면 → 해당 주차 → 대상 수업/시간 강조
- 지점장: 일정 주간 화면 → 자기 지점 → 대상 선생님 필터 → 대상 강조
- 전체 관리자: 일정 주간 화면 → 대상 지점 → 대상 선생님 필터 → 대상 강조

대상 카드/블록은 진입 직후 2~3회 부드러운 강조 애니메이션을 사용하고, 이후 약한 강조 상태를 유지한다. 사용자가 상세정보를 열면 강조 상태를 해제한다.

lesson이 아닌 정규 일정/개인 일정/담당 관계 이벤트는 각 targetKind에 맞는 resolver가 적절한 주차·시간·상세 화면을 선택한다.

---

## 9. 다음 작업

완료:
1. 일반 선생님 첫 출시 ON 이벤트 8종 확정
2. 이벤트별 payload/context 계약 확정
3. audit/RPC/trigger/outbox/FCM payload 전수 감사
4. notification event catalog / role policy / event preference / domain transformer DB 반영
5. manager/master `release_enabled=false` 정책 반영

다음:
1. Flutter Notification navigation intent/coordinator 및 destination resolver 구현
2. Foreground / Background / Terminated를 iPhone 실기기에서 각각 검증
3. 일반 선생님 v1 검증 완료 후 manager/master 발송은 비활성 상태로 출시
4. 개발자 운영 알림은 별도 정책 문서 및 수신 방식으로 설계


---

## 10. 일반 선생님 v1 Push payload 계약

이 절의 계약을 기준으로 현재 DB audit event / RPC / notification outbox / FCM data payload를 감사한다.

### 10.1 공통 원칙

- `lessonId`를 모든 알림의 공통 식별자로 사용하지 않는다.
- `focusAt`은 공통 필드로 사용하지 않는다.
- 도메인 대상은 `targetKind + targetId`로 식별한다.
- 화면 이동은 Flutter route 문자열이 아니라 의미적 `navigationKind`로 표현한다.
- v1의 navigation 종류는 우선 `lesson_week`, `student_detail` 두 가지다.
- 가능한 경우 앱은 `targetId`로 최신 DB 객체를 우선 조회한다.
- 취소/삭제 등으로 최신 객체 조회가 불가능할 수 있는 이벤트는 payload snapshot을 fallback으로 사용한다.
- 기존 담당 선생님에게 담당 변경 Push를 보내지 않는다. 새 담당 선생님만 수신한다.
- `recipientRole`은 권한 판단용 payload로 사용하지 않는다. 실제 역할은 session 복원 후 `CurrentProfile.role`을 신뢰한다.

### 10.2 공통 data payload

| 필드 | v1 | 설명 |
| --- | --- | --- |
| `schemaVersion` | 필수 | payload 계약 버전. 최초값 `1` |
| `notificationId` | 필수 | 중복 처리/추적용 알림 식별자 |
| `eventKey` | 필수 | 알림 도메인 이벤트 |
| `targetKind` | 필수 | `lesson`, `regularSchedule`, `assignment` |
| `targetId` | 필수 | 해당 도메인 객체 ID |
| `navigationKind` | 필수 | `lesson_week` 또는 `student_detail` |
| `recipientProfileId` | 필수 | 현재 로그인 계정과 알림 수신자 일치 검증 |
| `branchId` | 필수 | 지점 context |
| `teacherId` | 필수 | 수신 선생님/향후 필터 context |
| `studentId` | 필수 | 대상 학생 |
| `occurredAt` | 필수 | 알림 원인 사건 발생 시각 |

`actorProfileId` 등 발신 행위자 정보는 recipient 계산과 감사에는 필요할 수 있으나 v1 클라이언트 navigation에 필요하지 않으면 서버 측 notification domain event에만 유지한다.

### 10.3 이벤트별 계약

| # | eventKey | target | navigationKind | 이벤트별 필수 context | 선택 context |
| --- | --- | --- | --- | --- | --- |
| 1 | `student_assigned` | `assignment / assignmentId` | `student_detail` | `assignmentStartsOn`, `studentType` | 없음 |
| 2 | `lesson_changed` | `lesson / lessonId` | `lesson_week` | `previousStartsAt`, `startsAt`, `previousDurationMinutes`, `durationMinutes` | 없음 |
| 3 | `lesson_canceled` | `lesson / lessonId` | `lesson_week` | `startsAt`, `durationMinutes` | `reason` |
| 4 | `makeup_created` | `lesson / lessonId` | `lesson_week` | `startsAt`, `durationMinutes` | 없음 |
| 5 | `makeup_canceled` | `lesson / lessonId` | `lesson_week` | `startsAt`, `durationMinutes` | `reason` |
| 6 | `flex_lesson_booked` | `lesson / lessonId` | `lesson_week` | `startsAt`, `durationMinutes` | 없음 |
| 7 | `regular_schedule_changed` | `regularSchedule / scheduleSlotId` | `student_detail` | `effectiveFrom`, `previousWeekday`, `previousStartTime`, `previousDurationMinutes`, `weekday`, `startTime`, `durationMinutes` | 없음 |
| 8 | `student_teacher_assigned` | `assignment / assignmentId` | `student_detail` | `effectiveFrom` | 없음 |

### 10.4 navigation 동작

#### lesson_week

대상:
- 개별 수업 변경
- 수업 취소
- 보강 등록/취소
- 자율 예약

처리:
1. `targetId`의 lesson을 현재 로딩 데이터/DB에서 찾는다.
2. 찾으면 최신 `lesson.startsAt`을 기준으로 해당 주차로 이동하고 lesson을 강조한다.
3. 취소/삭제 등으로 lesson을 찾지 못하면 payload의 `startsAt`을 이용해 해당 주차/시간대로 이동한다.
4. 대상 상세를 열면 강조 상태를 해제한다.

#### student_detail

대상:
- 신규 학생/수업 배정
- 정규 일정 변경
- 새 담당 선생님 배정

처리:
1. 마이페이지의 내 수강생 영역으로 이동한다.
2. `studentId` 대상 학생 상세를 연다.
3. 화면은 Push snapshot보다 DB의 최신 학생/수강 정보를 우선 표시한다.

### 10.5 담당 선생님 변경 수신 정책

```text
기존 선생님 A → 새 선생님 B

A: Push 발송하지 않음
B: student_teacher_assigned 발송
```

기존 선생님 제거 사실은 audit history에는 남겨도 v1 Push recipient에는 포함하지 않는다.

### 10.6 감사 기준

각 8개 이벤트에 대해 다음 경로를 순서대로 검증한다.

```text
Business operation
→ audit event(s)
→ notification domain event 정규화
→ recipient 결정
→ 필수 payload/context 생성
→ notification_outbox 저장
→ Edge dispatcher
→ FCM data payload 전달
```

감사 중 기존 DB 구조에서 `targetId`가 안정적으로 존재하지 않거나, 필요한 이전값이 audit metadata에 보존되지 않는 경우에는 계약을 약화하기보다 notification domain event 생성 시점에 필요한 snapshot을 명시적으로 저장하는 방향을 우선 검토한다.


### 10.7 정규 일정 종료 정책

`REGULAR_SCHEDULE_ENDED`는 감사 이력에는 계속 기록하지만 Push 알림으로 만들지 않는다.

정규 일정 종료 처리 과정에서 발생하는 내부 `LESSON_CANCELED` 이벤트 중 `reason=regular_schedule_ended`인 항목도 개별 Push로 변환하지 않는다. 따라서 정규 일정 하나를 종료했을 때 미래 수업 개수만큼 취소 알림이 발생하는 문제를 방지하면서, 사용자에게 별도의 정규 일정 종료 Push도 보내지 않는다.
